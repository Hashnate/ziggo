"""Events / ticketing — public list + detail, and the customer purchase pipeline.

Browse:   GET  /events                 published upcoming events (cards)
          GET  /events/{id}            event detail + ticket tiers
Purchase: POST /events/{id}/book       buy tickets (wallet or cash)
          GET  /events/orders/mine     the signed-in customer's tickets

A purchase writes an EventOrder + EventOrderItem rows. Wallet payments debit
Customer.wallet_balance and write a WalletTransaction, mirroring rides/food.
"""
import secrets
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ...database import get_db
from ...models import (
    Customer,
    Event,
    EventOrder,
    EventOrderItem,
    EventOrderStatus,
    EventTicketTier,
    User,
    WalletTransaction,
)
from ...schemas import EventBookRequest
from ...services.auth_service import require_role

router = APIRouter()

# Platform fee on event tickets — 1% (PickMe shows +225 on a 22,500 subtotal).
CONVENIENCE_FEE_PCT = Decimal("0.01")


def _as_utc(dt: datetime | None) -> datetime | None:
    """SQLite hands back naive datetimes; treat stored times as UTC so they
    compare cleanly against an aware `now`. Postgres values are already aware."""
    if dt is None:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


async def _sold_by_tier(db: AsyncSession, tier_ids: list[int]) -> dict[int, int]:
    """How many tickets have been sold per tier (excludes cancelled orders).
    Used to compute remaining capacity / sold-out state."""
    if not tier_ids:
        return {}
    rows = (
        await db.execute(
            select(EventOrderItem.tier_id, func.coalesce(func.sum(EventOrderItem.quantity), 0))
            .join(EventOrder, EventOrder.id == EventOrderItem.order_id)
            .where(
                EventOrderItem.tier_id.in_(tier_ids),
                EventOrder.status != EventOrderStatus.CANCELLED,
            )
            .group_by(EventOrderItem.tier_id)
        )
    ).all()
    return {tid: int(qty or 0) for tid, qty in rows}


def _tier_dict(t: EventTicketTier, sold: int, now: datetime) -> dict:
    capacity = t.capacity
    remaining = None if capacity is None else max(0, capacity - sold)
    starts = _as_utc(t.sale_starts_at)
    ends = _as_utc(t.sale_ends_at)
    not_started = starts is not None and now < starts
    ended = ends is not None and now > ends
    sold_out = remaining is not None and remaining <= 0
    available = not (not_started or ended or sold_out)
    return {
        "id": t.id,
        "name": t.name,
        "price": float(t.price or 0),
        "capacity": capacity,
        "sold": sold,
        "remaining": remaining,
        "description": t.description,
        "sale_starts_at": t.sale_starts_at.isoformat() if t.sale_starts_at else None,
        "sale_ends_at": t.sale_ends_at.isoformat() if t.sale_ends_at else None,
        "available": available,
        "sold_out": sold_out,
    }


def _serialize_event(e: Event, tiers_payload: list[dict] | None = None) -> dict:
    out = {
        "id": e.id,
        "name": e.name,
        "description": e.description,
        "venue": e.venue,
        "city": e.city,
        "category": e.category,
        "image_url": e.image_url,
        "organizer_name": e.organizer_name,
        "organizer_phone": e.organizer_phone,
        "starts_at": e.starts_at.isoformat() if e.starts_at else None,
        "ends_at": e.ends_at.isoformat() if e.ends_at else None,
    }
    if e.tiers:
        out["from_price"] = float(min(t.price for t in e.tiers))
    else:
        out["from_price"] = None
    if tiers_payload is not None:
        out["tiers"] = tiers_payload
    return out


def _serialize_order(o: EventOrder) -> dict:
    return {
        "id": o.id,
        "order_ref": o.order_ref,
        "status": o.status.value if o.status else None,
        "subtotal": float(o.subtotal or 0),
        "convenience_fee": float(o.convenience_fee or 0),
        "discount_amount": float(o.discount_amount or 0),
        "total_amount": float(o.total_amount or 0),
        "payment_method": o.payment_method,
        "payment_status": o.payment_status,
        "created_at": o.created_at.isoformat() if o.created_at else None,
        "qr_payload": o.order_ref,
        "event": _serialize_event(o.event) if o.event else None,
        "items": [
            {
                "tier_id": it.tier_id,
                "tier_name": it.tier_name,
                "quantity": it.quantity,
                "price": float(it.price_at_order or 0),
            }
            for it in o.items
        ],
    }


@router.get("")
async def list_events(
    city: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    """List published, upcoming events. Optional ?city=Colombo filter."""
    now = datetime.now(timezone.utc)
    stmt = (
        select(Event)
        .options(selectinload(Event.tiers))
        .where(Event.is_published == True, Event.starts_at >= now)  # noqa: E712
        .order_by(Event.starts_at)
    )
    if city:
        stmt = stmt.where(Event.city == city)
    rows = (await db.execute(stmt)).scalars().all()
    return [_serialize_event(e) for e in rows]


@router.get("/orders/mine")
async def my_tickets(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """The signed-in customer's purchased tickets, newest first."""
    cust = (
        await db.execute(select(Customer).where(Customer.user_id == user.id))
    ).scalars().first()
    if not cust:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    rows = (
        await db.execute(
            select(EventOrder)
            .options(selectinload(EventOrder.items), selectinload(EventOrder.event))
            .where(EventOrder.customer_id == cust.id)
            .order_by(EventOrder.created_at.desc())
        )
    ).scalars().all()
    return [_serialize_order(o) for o in rows]


@router.get("/{event_id}")
async def get_event(event_id: int, db: AsyncSession = Depends(get_db)):
    e = (
        await db.execute(
            select(Event).options(selectinload(Event.tiers)).where(Event.id == event_id)
        )
    ).scalars().first()
    if e is None or not e.is_published:
        raise HTTPException(status_code=404, detail="Event not found")
    now = datetime.now(timezone.utc)
    sold = await _sold_by_tier(db, [t.id for t in e.tiers])
    tiers_payload = [_tier_dict(t, sold.get(t.id, 0), now) for t in e.tiers]
    return _serialize_event(e, tiers_payload=tiers_payload)


@router.post("/{event_id}/book", status_code=201)
async def book_tickets(
    event_id: int,
    body: EventBookRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust = (
        await db.execute(select(Customer).where(Customer.user_id == user.id))
    ).scalars().first()
    if not cust:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    e = (
        await db.execute(
            select(Event).options(selectinload(Event.tiers)).where(Event.id == event_id)
        )
    ).scalars().first()
    if e is None or not e.is_published:
        raise HTTPException(status_code=404, detail="Event not found")

    now = datetime.now(timezone.utc)
    tiers = {t.id: t for t in e.tiers}
    sold = await _sold_by_tier(db, list(tiers.keys()))

    subtotal = Decimal("0")
    order_items: list[EventOrderItem] = []
    for line in body.items:
        tier = tiers.get(line.tier_id)
        if tier is None:
            raise HTTPException(
                status_code=400, detail=f"Ticket tier {line.tier_id} not in this event"
            )
        t_starts = _as_utc(tier.sale_starts_at)
        t_ends = _as_utc(tier.sale_ends_at)
        if t_starts is not None and now < t_starts:
            raise HTTPException(status_code=400, detail=f"'{tier.name}' is not on sale yet")
        if t_ends is not None and now > t_ends:
            raise HTTPException(status_code=400, detail=f"'{tier.name}' sales have ended")
        if tier.capacity is not None and sold.get(tier.id, 0) + line.quantity > tier.capacity:
            raise HTTPException(status_code=400, detail=f"'{tier.name}' is sold out")

        price = Decimal(str(tier.price or 0))
        subtotal += price * line.quantity
        order_items.append(
            EventOrderItem(
                tier_id=tier.id,
                tier_name=tier.name,
                quantity=line.quantity,
                price_at_order=price,
            )
        )

    # Optional promo (events-eligible). Unknown / ineligible codes are ignored.
    discount = Decimal("0")
    if body.promo_code:
        from ...models import PromoCode

        p = (
            await db.execute(
                select(PromoCode).where(PromoCode.code == body.promo_code.upper())
            )
        ).scalars().first()
        if (
            p
            and p.is_active
            and p.category in ("all", "events")
            and (p.usage_limit is None or p.used_count < p.usage_limit)
        ):
            if p.discount_type == "percentage":
                discount = (subtotal * Decimal(str(p.discount_value)) / Decimal("100")).quantize(Decimal("0.01"))
                if p.max_discount:
                    discount = min(discount, Decimal(str(p.max_discount)))
            else:
                discount = Decimal(str(p.discount_value))

    discount = min(discount, subtotal)
    taxable = subtotal - discount
    convenience_fee = (taxable * CONVENIENCE_FEE_PCT).quantize(Decimal("0.01"))
    total = (taxable + convenience_fee).quantize(Decimal("0.01"))

    if body.payment_method == "wallet":
        if (cust.wallet_balance or Decimal(0)) < total:
            raise HTTPException(status_code=400, detail="Insufficient wallet balance")

    order_ref = "EV" + secrets.token_hex(4).upper()
    order = EventOrder(
        order_ref=order_ref,
        customer_id=cust.id,
        event_id=e.id,
        status=EventOrderStatus.CONFIRMED,
        subtotal=subtotal,
        convenience_fee=convenience_fee,
        discount_amount=discount,
        total_amount=total,
        payment_method=body.payment_method,
        payment_status="paid" if body.payment_method == "wallet" else "pending",
    )
    order.items = order_items
    db.add(order)

    if body.payment_method == "wallet":
        cust.wallet_balance = (cust.wallet_balance or Decimal(0)) - total
        db.add(
            WalletTransaction(
                user_id=cust.user_id,
                amount=total,
                type="debit",
                description=f"Event tickets — {e.name}",
                reference_id=order_ref,
                balance_after=cust.wallet_balance,
            )
        )

    await db.commit()
    # Re-load with relationships for the response.
    order = (
        await db.execute(
            select(EventOrder)
            .options(selectinload(EventOrder.items), selectinload(EventOrder.event))
            .where(EventOrder.id == order.id)
        )
    ).scalars().first()
    return _serialize_order(order)

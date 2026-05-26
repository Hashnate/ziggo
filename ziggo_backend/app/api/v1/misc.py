"""Public-ish endpoints: promos, complaints, Gold subscription."""
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...database import get_db
from ...models import (
    PromoCode,
    Complaint,
    ComplaintMessage,
    Customer,
    CustomerPromoClaim,
    Driver,
    FlashWeightTier,
    LoyaltyTransaction,
    User,
    UserRole,
    WalletTransaction,
)
from ...schemas import (
    PromoCodeResponse,
    ComplaintCreate,
    ComplaintResponse,
    ComplaintMessageCreate,
    ComplaintMessageResponse,
    GoldSubscribeRequest,
    LoyaltyBalanceResponse,
    LoyaltyTransactionResponse,
)
from ...services.auth_service import get_current_user, require_role
from ...services import loyalty_service as L

router = APIRouter()


# ---------- Flash pricing tiers (public — used by the customer flash screen) ----------
@router.get("/flash/pricing")
async def list_flash_tiers(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    q = await db.execute(
        select(FlashWeightTier)
        .where(FlashWeightTier.is_active == True)  # noqa: E712
        .order_by(FlashWeightTier.display_order, FlashWeightTier.id)
    )
    return [
        {
            "id": t.id,
            "label": t.label,
            "min_weight_kg": float(t.min_weight_kg or 0),
            "max_weight_kg": float(t.max_weight_kg) if t.max_weight_kg is not None else None,
            "representative_weight_kg": float(t.representative_weight_kg or 0),
            "surcharge": float(t.surcharge or 0),
            "icon": t.icon or "inventory_2",
            "display_order": t.display_order,
        }
        for t in q.scalars().all()
    ]


# ---------- Promos (BRD: RW-04 promotions inbox) ----------
async def _customer_for(db: AsyncSession, user: User) -> Customer:
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = cq.scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    return c


async def _customer_or_none(db: AsyncSession, user: User) -> "Customer | None":
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    return cq.scalars().first()


@router.get("/promos", response_model=List[PromoCodeResponse])
async def list_active_promos(
    category: str | None = None,           # BRD: RW-04 — filter the inbox by category
    only_claimed: bool = False,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Promotions inbox.

    Shows every redeemable promo (active, in-date, under-limit). When the
    caller is a customer, each row carries a `claimed_at` so the app can
    badge saved ones. `category` filters by surface (rides/food/market/all)
    and `only_claimed=true` restricts to promos the customer has saved.
    """
    now = datetime.now(timezone.utc)
    where_clauses = [
        PromoCode.is_active == True,  # noqa: E712
        (PromoCode.valid_from == None) | (PromoCode.valid_from <= now),  # noqa: E711
        (PromoCode.valid_to == None) | (PromoCode.valid_to >= now),  # noqa: E711
        (PromoCode.usage_limit == None) | (PromoCode.used_count < PromoCode.usage_limit),  # noqa: E711
    ]
    if category and category != "all":
        where_clauses.append(PromoCode.category.in_(["all", category]))

    q = await db.execute(select(PromoCode).where(*where_clauses).order_by(PromoCode.id.desc()))
    promos = q.scalars().all()

    # Attach claimed_at for the requesting customer (if any).
    claimed_map: dict[int, datetime] = {}
    if user.role == UserRole.CUSTOMER:
        customer = await _customer_or_none(db, user)
        if customer:
            cq = await db.execute(
                select(CustomerPromoClaim).where(CustomerPromoClaim.customer_id == customer.id)
            )
            for cp in cq.scalars().all():
                claimed_map[cp.promo_code_id] = cp.claimed_at

    out = []
    for p in promos:
        if only_claimed and p.id not in claimed_map:
            continue
        out.append(PromoCodeResponse(
            id=p.id, code=p.code, description=p.description,
            category=p.category or "all",
            discount_type=p.discount_type, discount_value=float(p.discount_value or 0),
            min_order_amount=float(p.min_order_amount) if p.min_order_amount is not None else None,
            max_discount=float(p.max_discount) if p.max_discount is not None else None,
            valid_to=p.valid_to,
            claimed_at=claimed_map.get(p.id),
        ))
    return out


@router.post("/promos/{promo_id}/claim", status_code=201)
async def claim_promo(
    promo_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Save a promo to the customer's inbox (BRD: RW-04)."""
    customer = await _customer_for(db, user)
    pq = await db.execute(select(PromoCode).where(PromoCode.id == promo_id))
    p = pq.scalars().first()
    if not p:
        raise HTTPException(status_code=404, detail="Promo not found")
    # Already claimed? Idempotent — just return the existing claim time.
    existing_q = await db.execute(
        select(CustomerPromoClaim).where(
            CustomerPromoClaim.customer_id == customer.id,
            CustomerPromoClaim.promo_code_id == promo_id,
        )
    )
    existing = existing_q.scalars().first()
    if existing:
        return {"ok": True, "claimed_at": existing.claimed_at, "already_claimed": True}
    claim = CustomerPromoClaim(customer_id=customer.id, promo_code_id=promo_id)
    db.add(claim)
    await db.commit()
    await db.refresh(claim)
    return {"ok": True, "claimed_at": claim.claimed_at, "already_claimed": False}


@router.delete("/promos/{promo_id}/claim", status_code=204)
async def unclaim_promo(
    promo_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    customer = await _customer_for(db, user)
    q = await db.execute(
        select(CustomerPromoClaim).where(
            CustomerPromoClaim.customer_id == customer.id,
            CustomerPromoClaim.promo_code_id == promo_id,
        )
    )
    claim = q.scalars().first()
    if claim:
        await db.delete(claim)
        await db.commit()
    return None


# ---------- Loyalty (BRD: RW-01 balance + history) ----------
@router.get("/loyalty/balance", response_model=LoyaltyBalanceResponse)
async def loyalty_balance(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    customer = await _customer_for(db, user)
    points = int(customer.loyalty_points or 0)
    value = await L.value_of(db, points)
    settings = await L._settings(db)
    return LoyaltyBalanceResponse(
        points=points,
        value=float(value),
        earn_rupees_per_point=float(settings.loyalty_earn_rupees_per_point or 0),
        value_per_point=float(settings.loyalty_value_per_point or 0),
        min_redeem_points=int(settings.loyalty_min_redeem_points or 0),
        max_redeem_order_pct=float(settings.loyalty_max_redeem_order_pct or 0),
    )


@router.get("/loyalty/history", response_model=List[LoyaltyTransactionResponse])
async def loyalty_history(
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    customer = await _customer_for(db, user)
    q = await db.execute(
        select(LoyaltyTransaction)
        .where(LoyaltyTransaction.customer_id == customer.id)
        .order_by(LoyaltyTransaction.id.desc())
        .limit(max(1, min(200, limit)))
    )
    return q.scalars().all()


# ---------- Complaints ----------
# BRD: CD-33 — automated complaint responses, keyword-routed.
# Order matters: the first rule whose keyword list matches the
# subject + description (case-insensitive) wins. The reply lands as a
# `ComplaintMessage` with sender_role="admin" so the customer sees it as
# a real support reply (and the existing chat UI just works).
_AUTO_REPLY_RULES = [
    (
        ["refund", "double charge", "double-charge", "charged twice", "overcharge"],
        "Thanks for reporting this — our finance team will review the transaction within 24h. "
        "If a duplicate charge is confirmed, the refund posts back to your wallet automatically.",
    ),
    (
        ["fare", "price", "expensive", "too much", "cost"],
        "Your fare is calculated from a base fare + per-km + per-minute rates, plus any surge. "
        "If you think the price is wrong for this trip, our team will review it and reply here.",
    ),
    (
        ["driver", "rude", "unsafe", "harass", "behaviour", "behavior"],
        "Sorry to hear that. We take driver conduct seriously and will investigate this trip. "
        "If you feel unsafe right now please use the SOS button on your ride screen.",
    ),
    (
        ["safety", "accident", "emergency"],
        "Your safety is our priority. We've flagged this ticket for urgent review. "
        "If this is an active emergency, please call 119 (Sri Lanka Police) right away.",
    ),
    (
        ["app", "bug", "crash", "otp", "login", "freeze"],
        "Thanks — we've logged the issue. Our tech team usually replies within 24h. "
        "A quick fix is often to log out and back in, or update the app to the latest version.",
    ),
    (
        ["promo", "discount", "code", "coupon"],
        "Promo codes need to be entered at the fare-estimate screen BEFORE booking — they can't be applied retroactively. "
        "Codes also have time/usage limits which we've checked against your account.",
    ),
]


def _auto_reply_for(complaint: "Complaint") -> str | None:
    text = f"{complaint.subject or ''} {complaint.description or ''}".lower()
    for keywords, reply in _AUTO_REPLY_RULES:
        if any(kw in text for kw in keywords):
            return reply
    return None


@router.post("/complaints", response_model=ComplaintResponse, status_code=201)
async def create_complaint(
    body: ComplaintCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = Complaint(
        user_id=user.id,
        booking_id=body.booking_id,
        category=body.category,
        subject=body.subject,
        description=body.description,
        status="open",
    )
    db.add(c)
    await db.flush()  # need c.id for the auto-reply message

    # BRD: CD-33 — instant keyword-routed auto-reply so the customer doesn't
    # feel ignored. The chat screen will pick it up like any other admin reply.
    auto_text = _auto_reply_for(c)
    if auto_text:
        db.add(ComplaintMessage(
            complaint_id=c.id,
            sender_user_id=None,        # automated, not authored by a human
            sender_role="admin",
            body=auto_text,
        ))
        # Move the ticket into in_progress so dashboards reflect attention.
        c.status = "in_progress"

    await db.commit()
    await db.refresh(c)
    return c


@router.get("/complaints", response_model=List[ComplaintResponse])
async def list_my_complaints(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(
        select(Complaint)
        .where(Complaint.user_id == user.id)
        .order_by(Complaint.id.desc())
    )
    return q.scalars().all()


async def _get_my_complaint(db: AsyncSession, user: User, complaint_id: int) -> Complaint:
    q = await db.execute(
        select(Complaint).where(
            Complaint.id == complaint_id, Complaint.user_id == user.id
        )
    )
    c = q.scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Ticket not found")
    return c


def _sender_role(user: User) -> str:
    return "driver" if user.role == UserRole.DRIVER else "customer"


@router.get("/complaints/{complaint_id}/messages", response_model=List[ComplaintMessageResponse])
async def list_complaint_messages(
    complaint_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    await _get_my_complaint(db, user, complaint_id)
    q = await db.execute(
        select(ComplaintMessage)
        .where(ComplaintMessage.complaint_id == complaint_id)
        .order_by(ComplaintMessage.id)
    )
    return q.scalars().all()


@router.post("/complaints/{complaint_id}/messages", response_model=ComplaintMessageResponse, status_code=201)
async def post_complaint_message(
    complaint_id: int,
    body: ComplaintMessageCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = await _get_my_complaint(db, user, complaint_id)
    text = body.body.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message body is required")

    msg = ComplaintMessage(
        complaint_id=c.id,
        sender_user_id=user.id,
        sender_role=_sender_role(user),
        body=text,
    )
    db.add(msg)
    # If a closed ticket gets a new message from the customer, treat it as a re-open
    if c.status in ("resolved", "closed"):
        c.status = "open"
        c.resolved_at = None
    await db.commit()
    await db.refresh(msg)
    return msg


# ---------- Gold subscription ----------
GOLD_PRICE_PER_MONTH = 500  # LKR


@router.post("/gold/subscribe")
async def subscribe_gold(
    body: GoldSubscribeRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    if body.months not in {1, 3, 6, 12}:
        raise HTTPException(status_code=400, detail="months must be 1, 3, 6, or 12")

    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    cost = GOLD_PRICE_PER_MONTH * body.months
    if (customer.wallet_balance or Decimal(0)) < Decimal(str(cost)):
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient wallet balance. Need Rs.{cost}, have Rs.{customer.wallet_balance or 0}",
        )

    # Debit wallet
    customer.wallet_balance = (customer.wallet_balance or Decimal(0)) - Decimal(str(cost))
    db.add(
        WalletTransaction(
            user_id=user.id,
            amount=Decimal(str(cost)),
            type="debit",
            description=f"Ziggo Gold - {body.months} month(s)",
            reference_id="GOLD",
            balance_after=customer.wallet_balance,
        )
    )

    # Extend Gold membership
    now = datetime.now(timezone.utc)
    base = customer.gold_expires_at if (customer.gold_expires_at and customer.gold_expires_at > now) else now
    customer.gold_expires_at = base + timedelta(days=30 * body.months)
    customer.gold_member = True

    await db.commit()
    return {
        "ok": True,
        "gold_member": True,
        "expires_at": customer.gold_expires_at.isoformat(),
        "wallet_balance": float(customer.wallet_balance),
        "months": body.months,
        "cost": cost,
    }


@router.get("/gold/status")
async def gold_status(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = cust_q.scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    now = datetime.now(timezone.utc)
    active = bool(c.gold_member and c.gold_expires_at and c.gold_expires_at > now)
    return {
        "gold_member": active,
        "expires_at": c.gold_expires_at.isoformat() if c.gold_expires_at else None,
        "price_per_month": GOLD_PRICE_PER_MONTH,
    }


# ---------- BRD: Incident reporting ----------
_VALID_INCIDENT_KINDS = {
    "accident", "traffic", "closure", "police", "hazard", "other",
}


@router.post("/incidents", status_code=201)
async def report_incident(
    body: dict = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Driver (or rider) reports a road event near their current location.

    Other drivers fetching `/incidents` within range will see it on their map.
    """
    from ...models import Incident
    body = body or {}
    kind = (body.get("kind") or "").strip().lower()
    if kind not in _VALID_INCIDENT_KINDS:
        raise HTTPException(
            status_code=400,
            detail=f"kind must be one of {sorted(_VALID_INCIDENT_KINDS)}",
        )
    try:
        lat = float(body["lat"])
        lng = float(body["lng"])
    except (KeyError, ValueError, TypeError):
        raise HTTPException(status_code=400, detail="lat + lng are required")

    inc = Incident(
        reported_by_user_id=user.id,
        kind=kind,
        lat=Decimal(str(lat)),
        lng=Decimal(str(lng)),
        note=(body.get("note") or "")[:300] or None,
        status="active",
    )
    db.add(inc)
    await db.commit()
    await db.refresh(inc)
    return {
        "id": inc.id,
        "kind": inc.kind,
        "lat": float(inc.lat),
        "lng": float(inc.lng),
        "note": inc.note,
        "status": inc.status,
        "created_at": inc.created_at.isoformat() if inc.created_at else None,
    }


@router.get("/incidents")
async def list_recent_incidents(
    lat: float | None = None,
    lng: float | None = None,
    radius_km: float = 5.0,
    minutes: int = 60,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Return active incidents from the last `minutes` (default 60).

    If lat+lng are supplied we also filter to a radius — used by the driver
    app to render warning pins on their map without paging through the
    whole country's reports.
    """
    from ...models import Incident
    from ...services.fare_service import haversine_km
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=max(1, min(24 * 60, minutes)))
    q = await db.execute(
        select(Incident)
        .where(Incident.status == "active", Incident.created_at >= cutoff)
        .order_by(Incident.id.desc())
        .limit(200)
    )
    rows = q.scalars().all()
    out = []
    for r in rows:
        if lat is not None and lng is not None:
            d = haversine_km(lat, lng, float(r.lat), float(r.lng))
            if d > radius_km:
                continue
        out.append({
            "id": r.id,
            "kind": r.kind,
            "lat": float(r.lat),
            "lng": float(r.lng),
            "note": r.note or "",
            "created_at": r.created_at.isoformat() if r.created_at else None,
        })
    return out

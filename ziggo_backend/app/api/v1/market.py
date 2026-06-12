"""Market/grocery delivery endpoints (PickMe Mart equivalent)."""
from datetime import datetime, timezone
from decimal import Decimal
from typing import List, Optional
import secrets

from fastapi import APIRouter, Body, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...database import get_db
from ...models import (
    MarketVendor,
    Product,
    MarketOrder,
    MarketOrderItem,
    MarketOrderStatus,
    Customer,
    Driver,
    Notification,
    User,
    UserRole,
    CustomerCard,
    Payment,
    MarketAd,
)
from ...schemas.market_schema import (
    ProductResponse,
    MarketOrderCreate,
    MarketOrderResponse,
)
from ...services.auth_service import get_current_user, require_role
from ...services.fare_service import haversine_km
from ...services.matching_service import find_all_nearby_drivers
from ...services import market_delivery_service as delivery
from ...services.ws_manager import manager
from ...services import payhere_service

router = APIRouter()


def _is_within_hours(opening: Optional[str], closing: Optional[str]) -> bool:
    if not opening or not closing:
        return True
    try:
        oh, om = [int(x) for x in opening.split(":")[:2]]
        ch, cm = [int(x) for x in closing.split(":")[:2]]
    except (ValueError, AttributeError):
        return True
    now = datetime.now()
    cur = now.hour * 60 + now.minute
    o = oh * 60 + om
    c = ch * 60 + cm
    if o == c:
        return True
    if c > o:
        return o <= cur < c
    return cur >= o or cur < c


@router.get("/vendors")
async def list_vendors(
    db: AsyncSession = Depends(get_db),
    lat: Optional[float] = None,
    lng: Optional[float] = None,
):
    """List active, currently-open market vendors. When `lat`/`lng` are
    supplied the result is enriched with `distance_km` and sorted nearest-first
    so "Outlets near you" reflects the customer's chosen delivery location."""
    q = await db.execute(
        select(MarketVendor).where(MarketVendor.is_active == True).order_by(MarketVendor.id)  # noqa: E712
    )
    rows = q.scalars().all()
    has_origin = lat is not None and lng is not None
    enriched = []
    for v in rows:
        within = _is_within_hours(v.opening_time, v.closing_time)
        is_open_now = (bool(v.is_open) if v.is_open is not None else True) and within
        if not is_open_now:
            continue
        distance_km = None
        if has_origin:
            if v.lat is None or v.lng is None:
                continue
            distance_km = round(
                haversine_km(lat, lng, float(v.lat), float(v.lng)), 2
            )
            if distance_km > 10.0:
                continue
            # Hard radius block: hide stalls that can't deliver to this point.
            radius = float(delivery.vendor_radius_km(v.delivery_radius_km))
            if distance_km > radius:
                continue
        enriched.append(
            {
                "id": v.id,
                "name": v.name,
                "category": v.category,
                "description": v.description,
                "address": v.address,
                "image_url": v.image_url,
                "rating": float(v.rating or 0),
                "delivery_fee": float(v.delivery_fee or 0),
                "eta_minutes": v.eta_minutes,
                "distance_km": distance_km,
                "opening_time": v.opening_time,
                "closing_time": v.closing_time,
                "is_active": bool(v.is_active),
                "is_open": bool(v.is_open) if v.is_open is not None else True,
                "is_open_now": is_open_now,
            }
        )
    if has_origin:
        # Vendors without coordinates sort last (distance None -> +inf).
        enriched.sort(
            key=lambda x: (
                not x["is_open_now"],
                x["distance_km"] if x["distance_km"] is not None else float("inf"),
                x["id"],
            )
        )
    else:
        enriched.sort(key=lambda x: (not x["is_open_now"], x["id"]))
    return enriched


@router.get("/vendors/{vendor_id}/products", response_model=List[ProductResponse])
async def list_products(vendor_id: int, db: AsyncSession = Depends(get_db)):
    q = await db.execute(
        select(Product).where(
            Product.vendor_id == vendor_id, Product.is_available == True  # noqa: E712
        )
    )
    return q.scalars().all()


@router.get("/vendors/{vendor_id}")
async def get_vendor(vendor_id: int, db: AsyncSession = Depends(get_db)):
    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = v_q.scalars().first()
    if not v:
        raise HTTPException(status_code=404, detail="Vendor not found")
    return {
        "id": v.id,
        "name": v.name,
        "category": v.category,
        "description": v.description,
        "address": v.address,
        "image_url": v.image_url,
        "logo_url": v.logo_url,
        "rating": float(v.rating or 0),
        "delivery_fee": float(v.delivery_fee or 0),
        "eta_minutes": v.eta_minutes,
        "opening_time": v.opening_time,
        "closing_time": v.closing_time,
        "is_active": bool(v.is_active),
        "is_open": bool(v.is_open) if v.is_open is not None else True,
    }


@router.get("/ads")
async def list_ads(
    db: AsyncSession = Depends(get_db),
    lat: Optional[float] = None,
    lng: Optional[float] = None,
):
    """Retrieve active advertisements. If lat and lng are provided, filter ads
    so only those targeting a radius that includes the user are returned."""
    q = await db.execute(
        select(MarketAd)
        .join(MarketVendor, MarketAd.vendor_id == MarketVendor.id)
        .where(MarketAd.is_active == True, MarketVendor.is_active == True)  # noqa: E712
    )
    rows = q.scalars().all()
    has_origin = lat is not None and lng is not None
    res = []
    for ad in rows:
        vendor = ad.vendor
        if has_origin and vendor.lat is not None and vendor.lng is not None:
            distance_km = haversine_km(lat, lng, float(vendor.lat), float(vendor.lng))
            # check targeting radius
            radius = float(ad.radius_km)
            if distance_km > radius:
                continue
        res.append({
            "id": ad.id,
            "vendor_id": ad.vendor_id,
            "vendor_name": vendor.name,
            "image_url": ad.image_url,
            "radius_km": float(ad.radius_km),
        })
    return res


@router.post("/quote")
async def quote_delivery(
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Preview the delivery fee for a cart before checkout. Body:
    `{vendor_id, delivery_lat, delivery_lng, items: [{product_id, quantity}]}`.
    Returns distance/weight/fee and `in_range`. Mirrors the fee math in
    create_market_order so the customer sees the exact charge up front."""
    try:
        vendor_id = int(body["vendor_id"])
        drop_lat = float(body["delivery_lat"])
        drop_lng = float(body["delivery_lng"])
        items = body.get("items") or []
    except (KeyError, ValueError, TypeError):
        raise HTTPException(status_code=400, detail="vendor_id, delivery_lat, delivery_lng required")

    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    vendor = v_q.scalars().first()
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    if vendor.lat is None or vendor.lng is None:
        raise HTTPException(status_code=400, detail="Vendor location not set")

    lines = []
    for line in items:
        p_q = await db.execute(
            select(Product).where(
                Product.id == int(line["product_id"]),
                Product.vendor_id == vendor_id,
            )
        )
        product = p_q.scalars().first()
        if product:
            lines.append((product, int(line.get("quantity", 1))))

    q = delivery.quote(
        vendor.lat,
        vendor.lng,
        drop_lat,
        drop_lng,
        lines,
        vendor.delivery_radius_km,
        base_fee_override=Decimal(str(vendor.delivery_fee)) if vendor.delivery_fee else None,
    )
    return {
        "distance_km": q["distance_km"],
        "weight_kg": float(q["weight_kg"]),
        "delivery_fee": float(q["fee"]),
        "radius_km": float(q["radius_km"]),
        "in_range": q["in_range"],
    }


@router.post("/orders", response_model=MarketOrderResponse, status_code=201)
async def create_market_order(
    body: MarketOrderCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == body.vendor_id))
    vendor = v_q.scalars().first()
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")
    if not vendor.is_active:
        raise HTTPException(status_code=400, detail="Vendor is not currently accepting orders")
    if vendor.is_open is False:
        raise HTTPException(status_code=400, detail="Vendor is closed right now")
    if not _is_within_hours(vendor.opening_time, vendor.closing_time):
        raise HTTPException(
            status_code=400,
            detail=f"Vendor only accepts orders between {vendor.opening_time} and {vendor.closing_time}",
        )

    total = Decimal("0")
    lines = []
    for line in body.items:
        p_q = await db.execute(
            select(Product).where(
                Product.id == line.product_id,
                Product.vendor_id == body.vendor_id,
            )
        )
        product = p_q.scalars().first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product {line.product_id} not found")
        if not product.is_available:
            raise HTTPException(status_code=400, detail=f"'{product.name}' unavailable")
        if line.quantity < 1:
            raise HTTPException(status_code=400, detail="Quantity must be >= 1")
        # Stock check — reject if the vendor would oversell. Stock tracking
        # is opt-in: products that have never set stock (stock=0 AND never
        # decremented) are treated as "always in stock", same as the food
        # menu items which don't track inventory at all.
        if (product.stock_quantity or 0) > 0 and line.quantity > product.stock_quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Only {product.stock_quantity} of '{product.name}' left in stock",
            )
        line_total = Decimal(str(product.price)) * line.quantity
        total += line_total
        lines.append((product, line.quantity))

    # Distance + weight delivery fee. The vendor's own `delivery_fee`, if set,
    # overrides the engine's base fare. Hard-block drops outside the radius.
    delivery_distance_km = None
    total_weight_kg = None
    if vendor.lat is not None and vendor.lng is not None:
        q = delivery.quote(
            vendor.lat,
            vendor.lng,
            body.delivery_lat,
            body.delivery_lng,
            lines,
            vendor.delivery_radius_km,
            base_fee_override=Decimal(str(vendor.delivery_fee)) if vendor.delivery_fee else None,
        )
        if not q["in_range"]:
            raise HTTPException(
                status_code=400,
                detail=f"Delivery address is outside {vendor.name}'s {q['radius_km']}km delivery range",
            )
        base_delivery_fee = q["fee"]
        delivery_distance_km = Decimal(str(q["distance_km"]))
        total_weight_kg = q["weight_kg"]
    else:
        base_delivery_fee = (
            Decimal(str(vendor.delivery_fee)) if (vendor.delivery_fee or 0) > 0 else Decimal("150")
        )

    # BRD: RW-03 — Gold delivery discount.
    from ...services import loyalty_service as L
    discounted_delivery_fee = await L.gold_delivery_fee(db, customer, base_delivery_fee)
    gold_discount = (base_delivery_fee - discounted_delivery_fee).quantize(Decimal("0.01"))
    delivery_fee = discounted_delivery_fee

    # Optional market promo.
    promo_discount = Decimal("0")
    promo_code_applied = None
    if body.promo_code:
        from ...models import PromoCode
        p_q = await db.execute(select(PromoCode).where(PromoCode.code == body.promo_code.upper()))
        p = p_q.scalars().first()
        if p and p.is_active and p.category in ("all", "market") and (
            p.usage_limit is None or p.used_count < p.usage_limit
        ):
            if p.discount_type == "percentage":
                promo_discount = (total * Decimal(str(p.discount_value)) / Decimal("100")).quantize(Decimal("0.01"))
                if p.max_discount:
                    promo_discount = min(promo_discount, Decimal(str(p.max_discount)))
            else:
                promo_discount = Decimal(str(p.discount_value))
            promo_code_applied = p.code

    subtotal_before_points = max(Decimal("0.00"), total + delivery_fee - promo_discount)

    # BRD: RW-02 — quote redemption.
    redeem_pts, redeem_value, _redeem_reason = await L.quote_redemption(
        db, customer, int(body.redeem_points or 0), subtotal_before_points
    )

    final = max(Decimal("0.00"), subtotal_before_points - redeem_value)

    if body.payment_method == "wallet" and (customer.wallet_balance or Decimal(0)) < final:
        raise HTTPException(status_code=400, detail="Insufficient wallet balance")
    elif body.payment_method and body.payment_method.startswith("card_"):
        try:
            card_id = int(body.payment_method.split("_")[1])
        except (ValueError, IndexError):
            card_id = None
        if not card_id:
            raise HTTPException(status_code=400, detail="Invalid card selection")
        card_q = await db.execute(
            select(CustomerCard).where(CustomerCard.id == card_id, CustomerCard.customer_id == customer.id)
        )
        card = card_q.scalars().first()
        if not card:
            raise HTTPException(status_code=400, detail="Card not found")

    order_ref = "MK" + secrets.token_hex(4).upper()
    order = MarketOrder(
        order_ref=order_ref,
        customer_id=customer.id,
        vendor_id=vendor.id,
        status=MarketOrderStatus.PENDING,
        total_amount=total,
        delivery_fee=delivery_fee,
        redeem_points=redeem_pts,
        redeem_discount=redeem_value,
        gold_discount=gold_discount,
        final_amount=final,
        delivery_address=body.delivery_address,
        delivery_lat=Decimal(str(body.delivery_lat)),
        delivery_lng=Decimal(str(body.delivery_lng)),
        delivery_distance_km=delivery_distance_km,
        total_weight_kg=total_weight_kg,
        payment_method=body.payment_method,
        payment_status="pending",
        instructions=body.instructions,
    )
    db.add(order)
    await db.flush()

    # BRD: RW-02 — deduct redeemed points.
    if order.redeem_points and order.redeem_points > 0:
        await L.redeem_points(
            db, customer,
            points=int(order.redeem_points),
            source_kind="market_order",
            source_id=order.id,
            description=f"Redeemed on {order.order_ref}",
        )

    if promo_code_applied:
        from ...models import PromoCode
        bump_q = await db.execute(select(PromoCode).where(PromoCode.code == promo_code_applied))
        bp = bump_q.scalars().first()
        if bp:
            bp.used_count = (bp.used_count or 0) + 1

    for product, qty in lines:
        db.add(
            MarketOrderItem(
                order_id=order.id,
                product_id=product.id,
                quantity=qty,
                price_at_order=product.price,
            )
        )
        # Decrement stock when tracked. Auto-mark unavailable when we hit zero
        # so customers stop seeing the product before the vendor restocks.
        if (product.stock_quantity or 0) > 0:
            product.stock_quantity = max(0, (product.stock_quantity or 0) - qty)
            if product.stock_quantity == 0:
                product.is_available = False

    if body.payment_method == "wallet":
        from ...models import WalletTransaction

        customer.wallet_balance = (customer.wallet_balance or Decimal(0)) - final
        db.add(
            WalletTransaction(
                user_id=user.id,
                amount=final,
                type="debit",
                description=f"Market order {order_ref}",
                reference_id=order_ref,
                balance_after=customer.wallet_balance,
            )
        )
        order.payment_status = "paid"
    elif body.payment_method and body.payment_method.startswith("card_"):
        card_id = int(body.payment_method.split("_")[1])
        card_q = await db.execute(
            select(CustomerCard).where(CustomerCard.id == card_id)
        )
        card = card_q.scalars().first()
        if card:
            charge_res = await payhere_service.charge_tokenized_card(
                customer_token=card.customer_token,
                amount=final,
                order_id=order_ref,
                items=f"Market order {order_ref}",
            )
            if not charge_res.get("success"):
                raise HTTPException(status_code=400, detail=f"Card charge failed: {charge_res.get('message')}")
            
            order.payment_status = "paid"
            pay_rec = Payment(
                customer_id=customer.id,
                amount=final,
                payment_method=f"{card.card_type} ({card.card_no[-4:]})",
                transaction_id=charge_res.get("transaction_id"),
                payment_gateway_response=charge_res.get("message"),
                status="paid",
            )
            db.add(pay_rec)

    await db.commit()
    await db.refresh(order)

    # Notify vendor owner (the PickMe-style gated dispatch). If no owner is
    # set (legacy seeded vendors), the customer order still works but the
    # rider broadcast won't fire until a vendor manually marks ready —
    # legacy vendors should be backfilled with owners via admin.
    items_count = sum(qty for _, qty in lines)
    if vendor.owner_id is not None:
        await manager.send(
            vendor.owner_id,
            "new_market_order",
            {
                "market_order_id": order.id,
                "order_ref": order.order_ref,
                "vendor_id": vendor.id,
                "items_count": items_count,
                "final_amount": float(order.final_amount or 0),
                "delivery_fee": float(delivery_fee),
                "payment_method": order.payment_method,
                "customer_name": user.full_name,
                "customer_phone": user.phone_number,
                "delivery_address": order.delivery_address,
                "instructions": order.instructions,
            },
        )
        db.add(
            Notification(
                user_id=vendor.owner_id,
                title="New market order",
                body=f"{items_count} item(s) • Rs.{int(order.final_amount or 0)} • {order.order_ref}",
                type="new_market_order",
                data=f'{{"market_order_id":{order.id}}}',
            )
        )
        await db.commit()

    return MarketOrderResponse(
        id=order.id,
        order_ref=order.order_ref,
        status=order.status.value,
        total_amount=float(order.total_amount or 0),
        delivery_fee=float(order.delivery_fee or 0),
        final_amount=float(order.final_amount or 0),
        delivery_address=order.delivery_address or "",
        payment_method=order.payment_method or "",
        payment_status=order.payment_status or "",
        delivery_distance_km=float(order.delivery_distance_km) if order.delivery_distance_km is not None else None,
        total_weight_kg=float(order.total_weight_kg) if order.total_weight_kg is not None else None,
        delivery_mode=order.delivery_mode,
        created_at=order.created_at,
    )


@router.get("/orders", response_model=List[MarketOrderResponse])
async def list_my_market_orders(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = cust_q.scalars().first()
    if not c:
        return []
    q = await db.execute(
        select(MarketOrder)
        .where(MarketOrder.customer_id == c.id)
        .order_by(MarketOrder.id.desc())
    )
    rows = q.scalars().all()
    return [
        MarketOrderResponse(
            id=o.id,
            order_ref=o.order_ref,
            status=o.status.value,
            total_amount=float(o.total_amount or 0),
            delivery_fee=float(o.delivery_fee or 0),
            final_amount=float(o.final_amount or 0),
            delivery_address=o.delivery_address or "",
            payment_method=o.payment_method or "",
            payment_status=o.payment_status or "",
            delivery_distance_km=float(o.delivery_distance_km) if o.delivery_distance_km is not None else None,
            total_weight_kg=float(o.total_weight_kg) if o.total_weight_kg is not None else None,
            delivery_mode=o.delivery_mode,
            created_at=o.created_at,
            cancellation_reason=o.cancellation_reason,
        )
        for o in rows
    ]


# ---------------------------------------------------------------------------
# Driver dispatch endpoints — mirror /food/orders/{id}/accept|decline|status
# ---------------------------------------------------------------------------

async def _get_driver(db: AsyncSession, user: User) -> Driver:
    if user.role != UserRole.DRIVER:
        raise HTTPException(status_code=403, detail="Driver role required")
    q = await db.execute(select(Driver).where(Driver.user_id == user.id))
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver profile not found")
    return d


@router.post("/orders/{order_id}/accept")
async def accept_market_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """First driver wins. Subsequent callers get HTTP 409."""
    driver = await _get_driver(db, user)
    if not driver.is_approved:
        raise HTTPException(status_code=403, detail="Account not approved")

    q = await db.execute(select(MarketOrder).where(MarketOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.driver_id is not None or order.status != MarketOrderStatus.READY_FOR_PICKUP:
        raise HTTPException(
            status_code=409,
            detail="This order has already been taken, picked up, or cancelled",
        )

    order.driver_id = driver.id
    await db.commit()
    await db.refresh(order)

    # Dismiss other riders that received the broadcast
    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == order.vendor_id))
    vendor = v_q.scalars().first()
    if vendor and vendor.lat is not None and vendor.lng is not None:
        others = await find_all_nearby_drivers(
            db,
            float(vendor.lat),
            float(vendor.lng),
            vehicle_type=None,
            max_distance_km=10,
            exclude_driver_id=driver.id,
        )
        for od in others:
            await manager.send(
                od.user_id,
                "ride_taken",
                {"market_order_id": order.id, "order_ref": order.order_ref},
            )

    cust_q = await db.execute(select(Customer).where(Customer.id == order.customer_id))
    c = cust_q.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "market_order_update",
            {"market_order_id": order.id, "status": order.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Rider on the way",
                body=f"{user.full_name or 'A rider'} accepted your order {order.order_ref}",
                type="market_order_update",
            )
        )
        await db.commit()

    # Tell vendor owner the rider has been assigned
    if vendor and vendor.owner_id:
        await manager.send(
            vendor.owner_id,
            "market_order_update",
            {"market_order_id": order.id, "status": order.status.value, "driver_id": driver.id},
        )

    return {
        "ok": True,
        "market_order_id": order.id,
        "order_ref": order.order_ref,
        "status": order.status.value,
    }


@router.post("/orders/{order_id}/decline")
async def decline_market_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Per-driver dismissal; the order stays open for the next rider."""
    await _get_driver(db, user)
    q = await db.execute(select(MarketOrder).where(MarketOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return {"ok": True, "status": order.status.value}


_DRIVER_MARKET_TRANSITIONS = {
    MarketOrderStatus.READY_FOR_PICKUP: {MarketOrderStatus.OUT_FOR_DELIVERY, MarketOrderStatus.CANCELLED},
    MarketOrderStatus.OUT_FOR_DELIVERY: {MarketOrderStatus.DELIVERED, MarketOrderStatus.CANCELLED},
}


@router.patch("/orders/{order_id}/status")
async def update_market_order_status(
    order_id: int,
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    driver = await _get_driver(db, user)
    new_status_raw = (body.get("status") or "").strip()
    try:
        new_status = MarketOrderStatus(new_status_raw)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Unknown status '{new_status_raw}'")

    q = await db.execute(select(MarketOrder).where(MarketOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.driver_id != driver.id:
        raise HTTPException(status_code=403, detail="Not your order")

    allowed = _DRIVER_MARKET_TRANSITIONS.get(order.status, set())
    if new_status not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot transition {order.status.value} -> {new_status.value}",
        )

    now = datetime.now(timezone.utc)
    order.status = new_status
    if new_status == MarketOrderStatus.OUT_FOR_DELIVERY:
        order.picked_up_at = now
    elif new_status == MarketOrderStatus.DELIVERED:
        order.delivered_at = now
        order.payment_status = "paid"
        # BRD: RW-01 — award loyalty points on delivery.
        from ...services.loyalty_service import award_points as _award
        cq = await db.execute(select(Customer).where(Customer.id == order.customer_id))
        c_for_pts = cq.scalars().first()
        if c_for_pts and order.final_amount:
            await _award(
                db, c_for_pts,
                spend_amount=order.final_amount,
                source_kind="market_order",
                source_id=order.id,
                description=f"Earned on {order.order_ref}",
            )
    elif new_status == MarketOrderStatus.CANCELLED and order.redeem_points and order.redeem_points > 0:
        # BRD: RW-02 — refund redeemed points on cancellation.
        cq = await db.execute(select(Customer).where(Customer.id == order.customer_id))
        cust_refund = cq.scalars().first()
        if cust_refund:
            cust_refund.loyalty_points = int(cust_refund.loyalty_points or 0) + int(order.redeem_points)
            from ...models import LoyaltyTransaction
            db.add(LoyaltyTransaction(
                customer_id=cust_refund.id,
                points=int(order.redeem_points),
                kind="adjust",
                source_kind="market_order",
                source_id=order.id,
                description=f"Refund — {order.order_ref} cancelled",
                balance_after=cust_refund.loyalty_points,
            ))
            order.redeem_points = 0
            order.redeem_discount = Decimal("0.00")

    await db.commit()
    await db.refresh(order)

    cust_q = await db.execute(select(Customer).where(Customer.id == order.customer_id))
    c = cust_q.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "market_order_update",
            {"market_order_id": order.id, "status": order.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title=f"Order {order.status.value.replace('_', ' ').title()}",
                body=f"Order {order.order_ref} is now {order.status.value.replace('_', ' ')}",
                type="market_order_update",
            )
        )
        await db.commit()
    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == order.vendor_id))
    vendor = v_q.scalars().first()
    if vendor and vendor.owner_id:
        await manager.send(
            vendor.owner_id,
            "market_order_update",
            {"market_order_id": order.id, "status": order.status.value},
        )

    return {"ok": True, "status": order.status.value}


@router.get("/orders/active")
async def get_active_market_order(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Driver's currently-in-progress market delivery, mirroring /food/orders/active."""
    driver_active = (
        MarketOrderStatus.READY_FOR_PICKUP,
        MarketOrderStatus.OUT_FOR_DELIVERY,
    )
    if user.role != UserRole.DRIVER:
        return None
    driver = await _get_driver(db, user)
    q = await db.execute(
        select(MarketOrder)
        .where(MarketOrder.driver_id == driver.id, MarketOrder.status.in_(driver_active))
        .order_by(MarketOrder.id.desc())
    )
    o = q.scalars().first()
    if not o:
        return None

    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == o.vendor_id))
    vendor = v_q.scalars().first()
    cust_q = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cust_q.scalars().first()
    cust_user = None
    if c:
        u_q = await db.execute(select(User).where(User.id == c.user_id))
        cust_user = u_q.scalars().first()

    return {
        "id": o.id,
        "order_ref": o.order_ref,
        "status": o.status.value,
        "vendor_id": o.vendor_id,
        "customer_id": o.customer_id,
        "driver_id": o.driver_id,
        "vendor_name": vendor.name if vendor else None,
        "vendor_address": vendor.address if vendor else None,
        "vendor_phone": vendor.phone_number if vendor else None,
        "pickup_lat": float(vendor.lat) if vendor and vendor.lat is not None else None,
        "pickup_lng": float(vendor.lng) if vendor and vendor.lng is not None else None,
        "delivery_address": o.delivery_address,
        "delivery_lat": float(o.delivery_lat) if o.delivery_lat else None,
        "delivery_lng": float(o.delivery_lng) if o.delivery_lng else None,
        "customer_name": cust_user.full_name if cust_user else None,
        "customer_phone": cust_user.phone_number if cust_user else None,
        "final_amount": float(o.final_amount or 0),
        "delivery_fee": float(o.delivery_fee or 0),
        "payment_method": o.payment_method,
        "payment_status": o.payment_status,
        "instructions": o.instructions,
    }


@router.post("/orders/{order_id}/cancel")
async def cancel_market_order(
    order_id: int,
    body: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Allow customer to cancel their own market order, but only if it's still PENDING."""
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    q = await db.execute(select(MarketOrder).where(MarketOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.customer_id != customer.id:
        raise HTTPException(status_code=403, detail="Not your order")

    if order.status != MarketOrderStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel an order in status {order.status.value}. Only pending orders can be cancelled.",
        )

    reason = (body.get("reason") or "Customer cancelled the order").strip()
    order.status = MarketOrderStatus.CANCELLED
    order.cancellation_reason = reason

    # Wallet refund
    if order.payment_method == "wallet" and order.payment_status == "paid":
        customer.wallet_balance = (customer.wallet_balance or Decimal(0)) + (order.final_amount or Decimal(0))
        from ...models import WalletTransaction
        db.add(
            WalletTransaction(
                user_id=user.id,
                amount=order.final_amount,
                type="credit",
                description=f"Refund — Customer cancelled market order {order.order_ref}",
                reference_id=order.order_ref,
                balance_after=customer.wallet_balance,
            )
        )
        order.payment_status = "refunded"

    # Loyalty points refund
    if order.redeem_points and order.redeem_points > 0:
        customer.loyalty_points = int(customer.loyalty_points or 0) + int(order.redeem_points)
        from ...models import LoyaltyTransaction
        db.add(LoyaltyTransaction(
            customer_id=customer.id,
            points=int(order.redeem_points),
            kind="adjust",
            source_kind="market_order",
            source_id=order.id,
            description=f"Refund — Customer cancelled market order {order.order_ref}",
            balance_after=customer.loyalty_points,
        ))
        order.redeem_points = 0
        order.redeem_discount = Decimal("0.00")

    await db.commit()
    await db.refresh(order)

    # Notify customer via WebSocket and in-app notification
    await manager.send(
        user.id,
        "market_order_update",
        {"market_order_id": order.id, "status": order.status.value},
    )
    db.add(
        Notification(
            user_id=user.id,
            title="Order Cancelled",
            body=f"You cancelled order {order.order_ref}",
            type="market_order_update",
        )
    )

    # Notify vendor owner so the pending order disappears from their portal
    v_q = await db.execute(select(MarketVendor).where(MarketVendor.id == order.vendor_id))
    vendor = v_q.scalars().first()
    if vendor and vendor.owner_id:
        await manager.send(
            vendor.owner_id,
            "market_order_update",
            {
                "market_order_id": order.id,
                "status": order.status.value,
                "reason": "Customer cancelled the order",
            },
        )
        db.add(
            Notification(
                user_id=vendor.owner_id,
                title="Order Cancelled by Customer",
                body=f"Order {order.order_ref} was cancelled by the customer",
                type="market_order_update",
            )
        )

    await db.commit()
    return {"ok": True, "status": order.status.value}


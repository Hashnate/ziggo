"""Food delivery endpoints (PickMe Food equivalent)."""
from datetime import datetime, timezone
from decimal import Decimal
from typing import List, Optional
import secrets

from fastapi import APIRouter, Body, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_, func
from sqlalchemy.orm import selectinload

from ...database import get_db
from ...models import (
    Driver,
    Restaurant,
    MenuItem,
    MenuCategory,
    FoodOrder,
    FoodOrderItem,
    FoodOrderStatus,
    Customer,
    Notification,
    User,
    UserRole,
    CustomerCard,
    Payment,
    FoodBanner,
    FoodCategory,
    FoodCollection,
    FoodDeal,
    FavoriteRestaurant,
)
from ...services.fare_service import haversine_km
from ...schemas.food_schema import (
    RestaurantResponse,
    MenuItemResponse,
    MenuCategoryResponse,
    FoodOrderCreate,
    FoodOrderResponse,
)
from ...services.auth_service import get_current_user, require_role
from ...services.matching_service import find_all_nearby_drivers
from ...services.ws_manager import manager
from ...services import payhere_service

router = APIRouter()


async def _broadcast_to_riders(
    db: AsyncSession,
    order: "FoodOrder",
    r: "Restaurant",
    customer_user: "User",
    items_count: int,
    delivery_fee: Decimal,
) -> None:
    """Broadcast a food order to every nearby online rider.

    Called from two places:
      • the legacy shim in create_food_order (restaurant has no owner)
      • restaurant.py /orders/{id}/ready (the normal path under P2)
    """
    if r.lat is None or r.lng is None:
        await manager.send(
            customer_user.id,
            "no_drivers_available",
            {"food_order_id": order.id, "order_ref": order.order_ref},
        )
        return

    nearby = await find_all_nearby_drivers(
        db,
        float(r.lat),
        float(r.lng),
        vehicle_type=None,
        max_distance_km=10,
    )

    # Driver earnings = delivery fee * (1 - 0.20)
    driver_earnings = float(delivery_fee) * 0.80

    food_request_payload = {
        "is_food": True,
        "food_order_id": order.id,
        "order_ref": order.order_ref,
        "restaurant_id": r.id,
        "restaurant_name": r.name,
        "restaurant_image": r.image_url,
        # Reuse pickup/drop keys so _RideRequestSheet renders without a
        # separate code path: restaurant is the pickup, customer is the drop.
        "pickup_address": r.address or r.name,
        "pickup_lat": float(r.lat),
        "pickup_lng": float(r.lng),
        "drop_address": order.delivery_address,
        "drop_lat": float(order.delivery_lat),
        "drop_lng": float(order.delivery_lng),
        "items_count": items_count,
        "fare": float(order.final_amount or 0),
        "driver_earnings": driver_earnings,
        "delivery_fee": float(delivery_fee),
        "service_type": "food",
        "payment_method": order.payment_method,
        "customer_name": customer_user.full_name,
        "customer_phone": customer_user.phone_number,
        "expires_in_seconds": 30,
        "instructions": order.instructions,
    }

    for d in nearby:
        await manager.send(d.user_id, "new_ride_request", food_request_payload)
        db.add(
            Notification(
                user_id=d.user_id,
                title="New food delivery",
                body=f"{r.name} → {order.delivery_address} • Rs.{int(order.final_amount or 0)}",
                type="food_request",
                data=f'{{"food_order_id":{order.id}}}',
            )
        )

    if not nearby:
        await manager.send(
            customer_user.id,
            "no_drivers_available",
            {"food_order_id": order.id, "order_ref": order.order_ref},
        )


def _is_within_hours(opening: Optional[str], closing: Optional[str]) -> bool:
    """Cheap HH:MM range check using server local time. Returns True when no
    hours are configured (always-open fallback) or when 'now' falls inside
    [opening, closing). Handles cross-midnight ranges (e.g. 20:00 → 02:00)."""
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
    # Cross-midnight window
    return cur >= o or cur < c


def _restaurant_summary(
    r: "Restaurant", is_open_now: bool, distance_km: Optional[float] = None
) -> dict:
    return {
        "id": r.id,
        "name": r.name,
        "description": r.description,
        "address": r.address,
        "cuisine": r.cuisine,
        "image_url": r.image_url,
        "rating": float(r.rating or 0),
        "delivery_fee": float(r.delivery_fee or 0),
        "opening_time": r.opening_time,
        "closing_time": r.closing_time,
        "eta_minutes": r.eta_minutes,
        "is_active": bool(r.is_active),
        "is_open": bool(r.is_open),
        "is_open_now": is_open_now,
        "distance_km": round(distance_km, 2) if distance_km is not None else None,
    }


@router.get("/home")
async def food_home(db: AsyncSession = Depends(get_db)):
    """Aggregated home-screen layout: carousel banners, cuisine categories,
    curated collections, and promo-linked deals — all admin-managed at
    /admin/food-home and seeded on first boot. One round-trip so the Flutter
    home renders in a single call."""
    banners_q = await db.execute(
        select(FoodBanner)
        .where(FoodBanner.is_active == True)  # noqa: E712
        .order_by(FoodBanner.display_order, FoodBanner.id)
    )
    cats_q = await db.execute(
        select(FoodCategory)
        .where(FoodCategory.is_active == True)  # noqa: E712
        .order_by(FoodCategory.display_order, FoodCategory.id)
    )
    cols_q = await db.execute(
        select(FoodCollection)
        .where(FoodCollection.is_active == True)  # noqa: E712
        .order_by(FoodCollection.display_order, FoodCollection.id)
    )
    deals_q = await db.execute(
        select(FoodDeal)
        .options(selectinload(FoodDeal.promo_code))
        .where(FoodDeal.is_active == True)  # noqa: E712
        .order_by(FoodDeal.display_order, FoodDeal.id)
    )

    return {
        "banners": [
            {
                "id": b.id,
                "title": b.title,
                "image_url": b.image_url,
                "link_type": b.link_type,
                "link_value": b.link_value,
            }
            for b in banners_q.scalars().all()
        ],
        "categories": [
            {"id": c.id, "name": c.name, "icon_url": c.icon_url}
            for c in cats_q.scalars().all()
        ],
        "collections": [
            {"id": c.id, "name": c.name, "icon": c.icon, "color": c.color}
            for c in cols_q.scalars().all()
        ],
        "deals": [
            {
                "id": d.id,
                "title": d.title,
                "subtitle": d.subtitle,
                "image_url": d.image_url,
                "color": d.color,
                "promo_id": d.promo_code_id,
                "promo_code": d.promo_code.code if d.promo_code else None,
                "link_type": d.link_type,
                "link_value": d.link_value,
            }
            for d in deals_q.scalars().all()
        ],
    }


@router.get("/restaurants")
async def list_restaurants(
    db: AsyncSession = Depends(get_db),
    category_id: Optional[int] = None,
    collection_id: Optional[int] = None,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    q: Optional[str] = None,
):
    """List active restaurants, currently-open ones first. Optional filters:
    `category_id` / `collection_id` narrow to a tagged or curated set; `q`
    searches name/cuisine; `lat`+`lng` attach `distance_km` and order
    nearest-first. Returns `is_open_now` for the UI."""
    stmt = select(Restaurant).where(Restaurant.is_active == True)  # noqa: E712
    if category_id is not None:
        stmt = stmt.where(
            Restaurant.food_categories.any(FoodCategory.id == category_id)
        )
    if collection_id is not None:
        stmt = stmt.where(
            Restaurant.collections.any(FoodCollection.id == collection_id)
        )
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Restaurant.name.ilike(like),
                Restaurant.cuisine.ilike(like),
                Restaurant.items.any(MenuItem.name.ilike(like))
            )
        )

    rows = (await db.execute(stmt.order_by(Restaurant.id))).scalars().all()

    has_origin = lat is not None and lng is not None
    enriched = []
    for r in rows:
        within = _is_within_hours(r.opening_time, r.closing_time)
        is_open_now = bool(r.is_open) and within
        if not is_open_now:
            continue
        distance_km = None
        if has_origin:
            if r.lat is None or r.lng is None:
                continue
            distance_km = haversine_km(lat, lng, float(r.lat), float(r.lng))
            if distance_km > 10.0:
                continue
        enriched.append(_restaurant_summary(r, is_open_now, distance_km))

    # Open first; then nearest-first when an origin was supplied, else by id.
    enriched.sort(
        key=lambda x: (
            not x["is_open_now"],
            x["distance_km"] if x["distance_km"] is not None else float("inf"),
            x["id"],
        )
    )
    return enriched


@router.get("/restaurants/{restaurant_id}")
async def get_restaurant(restaurant_id: int, db: AsyncSession = Depends(get_db)):
    q = await db.execute(
        select(Restaurant)
        .options(
            selectinload(Restaurant.categories),
            selectinload(Restaurant.items),
        )
        .where(Restaurant.id == restaurant_id)
    )
    r = q.scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    within = _is_within_hours(r.opening_time, r.closing_time)

    # Popular Picks = the restaurant's most-ordered available items, derived
    # from real order history (no static flag). Empty until orders exist.
    available_ids = {it.id for it in r.items if it.is_available}
    pop_q = await db.execute(
        select(
            FoodOrderItem.menu_item_id,
            func.sum(FoodOrderItem.quantity).label("qty"),
        )
        .join(FoodOrder, FoodOrder.id == FoodOrderItem.order_id)
        .where(FoodOrder.restaurant_id == restaurant_id)
        .group_by(FoodOrderItem.menu_item_id)
        .order_by(func.sum(FoodOrderItem.quantity).desc())
    )
    popular_item_ids = [
        mid for (mid, _qty) in pop_q.all() if mid in available_ids
    ][:6]

    return {
        "id": r.id,
        "name": r.name,
        "description": r.description,
        "address": r.address,
        "cuisine": r.cuisine,
        "image_url": r.image_url,
        "rating": float(r.rating or 0),
        "delivery_fee": float(r.delivery_fee or 0),
        "opening_time": r.opening_time,
        "closing_time": r.closing_time,
        "eta_minutes": r.eta_minutes,
        "is_open": bool(r.is_open),
        "is_open_now": bool(r.is_open) and within,
        "popular_item_ids": popular_item_ids,
        "categories": [
            {"id": c.id, "name": c.name, "description": c.description}
            for c in sorted(r.categories, key=lambda x: x.display_order or 0)
        ],
        "items": [
            {
                "id": it.id,
                "name": it.name,
                "description": it.description,
                "price": float(it.price),
                "image_url": it.image_url,
                "is_available": it.is_available,
                "is_veg": it.is_veg,
                "prep_time_min": it.prep_time_min,
                "category_id": it.category_id,
            }
            for it in r.items
        ],
    }


@router.get("/restaurants/{restaurant_id}/menu", response_model=List[MenuItemResponse])
async def get_menu(restaurant_id: int, db: AsyncSession = Depends(get_db)):
    q = await db.execute(
        select(MenuItem)
        .where(MenuItem.restaurant_id == restaurant_id, MenuItem.is_available == True)  # noqa: E712
    )
    return q.scalars().all()


@router.post("/quote")
async def quote_delivery(
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Preview the delivery fee for a cart before checkout. Body:
    `{restaurant_id, delivery_lat, delivery_lng}`."""
    try:
        restaurant_id = int(body["restaurant_id"])
        drop_lat = float(body["delivery_lat"])
        drop_lng = float(body["delivery_lng"])
    except (KeyError, ValueError, TypeError):
        raise HTTPException(status_code=400, detail="restaurant_id, delivery_lat, delivery_lng required")

    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    r_q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = r_q.scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    if r.lat is None or r.lng is None:
        raise HTTPException(status_code=400, detail="Restaurant location not set")

    from ...services.fare_service import haversine_km
    from decimal import Decimal, ROUND_HALF_UP

    items = body.get("items") or []
    items_subtotal = Decimal("0.00")
    for item_data in items:
        try:
            item_id = int(item_data["menu_item_id"])
            qty = int(item_data["quantity"])
            iq = await db.execute(select(MenuItem).where(MenuItem.id == item_id))
            mitem = iq.scalars().first()
            if mitem:
                items_subtotal += Decimal(str(mitem.price)) * qty
        except Exception:
            pass

    dist_km = haversine_km(float(r.lat), float(r.lng), drop_lat, drop_lng)
    pickup_pct = r.pickup_fee if r.pickup_fee is not None else Decimal("70.00")
    per_km = r.per_km_rate if r.per_km_rate is not None else Decimal("40.00")
    boost_pct = r.boost if r.boost is not None else Decimal("0.00")
    
    pickup = items_subtotal * (pickup_pct / Decimal("100"))
    boost_val = items_subtotal * (boost_pct / Decimal("100"))
    
    base_delivery_fee = pickup + per_km * Decimal(str(dist_km)) + boost_val
    base_delivery_fee = base_delivery_fee.quantize(Decimal("1"), rounding=ROUND_HALF_UP)

    from ...services import loyalty_service as L
    discounted_delivery_fee = await L.gold_delivery_fee(db, customer, base_delivery_fee)
    
    return {
        "distance_km": dist_km,
        "delivery_fee": float(discounted_delivery_fee)
    }



@router.post("/orders", response_model=FoodOrderResponse, status_code=201)
async def create_food_order(
    body: FoodOrderCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    r_q = await db.execute(select(Restaurant).where(Restaurant.id == body.restaurant_id))
    r = r_q.scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    if not r.is_active:
        raise HTTPException(status_code=400, detail="Restaurant is not currently accepting orders")
    if r.is_open is False:
        raise HTTPException(status_code=400, detail="Restaurant is closed right now")
    if not _is_within_hours(r.opening_time, r.closing_time):
        raise HTTPException(
            status_code=400,
            detail=f"Restaurant only accepts orders between {r.opening_time} and {r.closing_time}",
        )

    total = Decimal("0")
    line_items = []
    for line in body.items:
        item_q = await db.execute(
            select(MenuItem).where(
                MenuItem.id == line.menu_item_id,
                MenuItem.restaurant_id == body.restaurant_id,
            )
        )
        item = item_q.scalars().first()
        if not item:
            raise HTTPException(
                status_code=400,
                detail=f"Menu item {line.menu_item_id} not found in this restaurant",
            )
        if not item.is_available:
            raise HTTPException(
                status_code=400,
                detail=f"Item '{item.name}' is currently unavailable",
            )
        if line.quantity < 1:
            raise HTTPException(status_code=400, detail="Quantity must be >= 1")
        line_total = Decimal(str(item.price)) * line.quantity
        total += line_total
        line_items.append((item, line.quantity, item.price, line.notes))

    from ...services.loyalty_service import gold_delivery_fee
    if body.is_self_pickup:
        base_delivery_fee = Decimal("0")
        gold_discount = Decimal("0")
        delivery_fee = Decimal("0")
    else:
        from ...services.fare_service import haversine_km
        from decimal import ROUND_HALF_UP
        if r.lat is not None and r.lng is not None and body.delivery_lat is not None and body.delivery_lng is not None:
            dist_km = haversine_km(float(r.lat), float(r.lng), float(body.delivery_lat), float(body.delivery_lng))
            pickup_pct = r.pickup_fee if r.pickup_fee is not None else Decimal("70.00")
            per_km = r.per_km_rate if r.per_km_rate is not None else Decimal("40.00")
            boost_pct = r.boost if r.boost is not None else Decimal("0.00")
            
            pickup = total * (pickup_pct / Decimal("100"))
            boost_val = total * (boost_pct / Decimal("100"))
            
            base_delivery_fee = pickup + per_km * Decimal(str(dist_km)) + boost_val
            base_delivery_fee = base_delivery_fee.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
        else:
            base_delivery_fee = total * (Decimal(str(r.delivery_fee or 0)) / Decimal("100"))

        # BRD: RW-03 — Gold member gets the configured delivery-fee discount.
        from ...services import loyalty_service as L
        discounted_delivery_fee = await L.gold_delivery_fee(db, customer, base_delivery_fee)
        gold_discount = (base_delivery_fee - discounted_delivery_fee).quantize(Decimal("0.01"))
        delivery_fee = discounted_delivery_fee

    # Optional promo discount (applied to items subtotal, not delivery)
    promo_discount = Decimal("0")
    promo_code_applied = None
    if body.promo_code:
        from ...models import PromoCode
        p_q = await db.execute(select(PromoCode).where(PromoCode.code == body.promo_code.upper()))
        p = p_q.scalars().first()
        if p and p.is_active and p.category in ("all", "food") and (
            p.usage_limit is None or p.used_count < p.usage_limit
        ):
            if p.discount_type == "percentage":
                promo_discount = (total * Decimal(str(p.discount_value)) / Decimal("100")).quantize(Decimal("0.01"))
                if p.max_discount:
                    promo_discount = min(promo_discount, Decimal(str(p.max_discount)))
            else:
                promo_discount = Decimal(str(p.discount_value))
            promo_code_applied = p.code

    subtotal_before_points = total + delivery_fee - promo_discount
    subtotal_before_points = max(Decimal("0.00"), subtotal_before_points)

    # BRD: RW-02 — quote redemption (clamps to balance, min, max%).
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

    order_ref = "FO" + secrets.token_hex(4).upper()
    order = FoodOrder(
        order_ref=order_ref,
        customer_id=customer.id,
        restaurant_id=r.id,
        status=FoodOrderStatus.PENDING,
        total_amount=total,
        delivery_fee=delivery_fee,
        tax_amount=Decimal("0"),
        discount_amount=promo_discount,
        redeem_points=redeem_pts,
        redeem_discount=redeem_value,
        gold_discount=gold_discount,
        final_amount=final,
        delivery_address=body.delivery_address if not body.is_self_pickup else "Self Pickup",
        delivery_lat=Decimal(str(body.delivery_lat)) if (body.delivery_lat is not None and not body.is_self_pickup) else r.lat,
        delivery_lng=Decimal(str(body.delivery_lng)) if (body.delivery_lng is not None and not body.is_self_pickup) else r.lng,
        is_self_pickup=body.is_self_pickup,
        payment_method=body.payment_method,
        payment_status="pending",
        instructions=body.instructions,
    )
    db.add(order)
    await db.flush()

    # BRD: RW-02 — deduct redeemed points at order time (refunded on cancel).
    if order.redeem_points and order.redeem_points > 0:
        await L.redeem_points(
            db, customer,
            points=int(order.redeem_points),
            source_kind="food_order",
            source_id=order.id,
            description=f"Redeemed on {order.order_ref}",
        )

    # Bump promo usage counter
    if promo_code_applied:
        from ...models import PromoCode
        bump_q = await db.execute(select(PromoCode).where(PromoCode.code == promo_code_applied))
        bp = bump_q.scalars().first()
        if bp:
            bp.used_count = (bp.used_count or 0) + 1

    for item, qty, price, notes in line_items:
        db.add(
            FoodOrderItem(
                order_id=order.id,
                menu_item_id=item.id,
                quantity=qty,
                price_at_order=price,
                notes=notes,
            )
        )

    # Wallet debit
    if body.payment_method == "wallet":
        from ...models import WalletTransaction

        customer.wallet_balance = (customer.wallet_balance or Decimal(0)) - final
        db.add(
            WalletTransaction(
                user_id=user.id,
                amount=final,
                type="debit",
                description=f"Food order {order_ref}",
                reference_id=order_ref,
                balance_after=customer.wallet_balance,
            )
        )
        order.payment_status = "paid"
    elif body.payment_method and body.payment_method.startswith("card_"):
        # We checked validity above, so `card` exists
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
                items=f"Food order {order_ref}",
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

    # ---- Notify the restaurant owner (the new dispatch gate) ----------------
    # PickMe-style flow: order goes to the restaurant first. Driver dispatch
    # fires later, when the restaurant taps "Mark Ready" (see
    # /restaurant/orders/{id}/ready). Until then, the order sits in PENDING
    # and the customer's timeline shows "Waiting for restaurant".
    items_count = sum(qty for _, qty, _, _ in line_items)
    if r.owner_id is not None:
        await manager.send(
            r.owner_id,
            "new_food_order",
            {
                "food_order_id": order.id,
                "order_ref": order.order_ref,
                "restaurant_id": r.id,
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
                user_id=r.owner_id,
                title="New food order",
                body=f"{items_count} item(s) • Rs.{int(order.final_amount or 0)} • {order.order_ref}",
                type="new_food_order",
                data=f'{{"food_order_id":{order.id}}}',
            )
        )
        await db.commit()
    else:
        # Backward-compat shim for legacy/seeded restaurants with no owner_id.
        # Without an owner, no one can accept — auto-flow through to
        # READY_FOR_PICKUP and broadcast to nearby riders immediately so the
        # demo flow still works against old data. New self-registered
        # restaurants always have an owner_id, so they take the gated path.
        now = datetime.now(timezone.utc)
        order.status = FoodOrderStatus.READY_FOR_PICKUP
        order.confirmed_at = now
        order.ready_at = now
        await db.commit()
        if not order.is_self_pickup:
            await _broadcast_to_riders(db, order, r, user, items_count, delivery_fee)
        else:
            await manager.send(
                user.id,
                "order_update",
                {"food_order_id": order.id, "status": order.status.value},
            )
        await db.commit()

    return FoodOrderResponse(
        id=order.id,
        order_ref=order.order_ref,
        status=order.status.value,
        total_amount=float(order.total_amount),
        delivery_fee=float(order.delivery_fee),
        final_amount=float(order.final_amount),
        delivery_address=order.delivery_address,
        payment_method=order.payment_method,
        payment_status=order.payment_status,
        created_at=order.created_at,
        is_self_pickup=order.is_self_pickup,
        items=[],
    )


@router.get("/orders/active")
async def get_active_food_order(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Return the caller's currently-in-progress food order (driver or customer).

    Customer view spans the full lifecycle (PENDING through OUT_FOR_DELIVERY).
    Driver view is narrower — under P2 a driver only owns the order from
    READY_FOR_PICKUP onwards.
    """
    customer_active = (
        FoodOrderStatus.PENDING,
        FoodOrderStatus.CONFIRMED,
        FoodOrderStatus.PREPARING,
        FoodOrderStatus.READY_FOR_PICKUP,
        FoodOrderStatus.OUT_FOR_DELIVERY,
    )
    driver_active = (
        FoodOrderStatus.CONFIRMED,
        FoodOrderStatus.PREPARING,
        FoodOrderStatus.READY_FOR_PICKUP,
        FoodOrderStatus.OUT_FOR_DELIVERY,
    )
    if user.role == UserRole.DRIVER:
        driver = await _get_driver(db, user)
        q = await db.execute(
            select(FoodOrder)
            .where(FoodOrder.driver_id == driver.id, FoodOrder.status.in_(driver_active))
            .order_by(FoodOrder.id.desc())
        )
    elif user.role == UserRole.CUSTOMER:
        cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
        customer = cust_q.scalars().first()
        if not customer:
            return None
        q = await db.execute(
            select(FoodOrder)
            .where(FoodOrder.customer_id == customer.id, FoodOrder.status.in_(customer_active))
            .order_by(FoodOrder.id.desc())
        )
    else:
        return None

    o = q.scalars().first()
    if not o:
        return None

    # Join restaurant + customer user so the driver UI can render pickup info,
    # navigate-to coordinates, and a tappable customer phone number.
    r_q = await db.execute(select(Restaurant).where(Restaurant.id == o.restaurant_id))
    r = r_q.scalars().first()
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
        "restaurant_id": o.restaurant_id,
        "customer_id": o.customer_id,
        "driver_id": o.driver_id,
        "restaurant_name": r.name if r else None,
        "restaurant_address": r.address if r else None,
        "restaurant_phone": r.phone_number if r else None,
        "pickup_lat": float(r.lat) if r and r.lat is not None else None,
        "pickup_lng": float(r.lng) if r and r.lng is not None else None,
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
        "customer_rating": o.customer_rating,
        "customer_feedback": o.customer_feedback,
        "is_self_pickup": o.is_self_pickup,
    }


@router.get("/orders/{order_id}")
async def get_food_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Retrieve a single food order by ID (customer or driver)."""
    q = await db.execute(select(FoodOrder).where(FoodOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # Access control: only the ordering customer or the assigned driver can view it.
    if user.role == UserRole.CUSTOMER:
        cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
        customer = cust_q.scalars().first()
        if not customer or order.customer_id != customer.id:
            raise HTTPException(status_code=403, detail="Not your order")
    elif user.role == UserRole.DRIVER:
        drv_q = await db.execute(select(Driver).where(Driver.user_id == user.id))
        driver = drv_q.scalars().first()
        if not driver or order.driver_id != driver.id:
            raise HTTPException(status_code=403, detail="Not your assigned order")
    else:
        raise HTTPException(status_code=403, detail="Forbidden")

    return {
        "id": order.id,
        "order_ref": order.order_ref,
        "status": order.status.value,
        "customer_rating": order.customer_rating,
        "customer_feedback": order.customer_feedback,
    }


@router.get("/orders", response_model=List[FoodOrderResponse])
async def list_my_food_orders(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        return []
    from sqlalchemy.orm import joinedload
    q = await db.execute(
        select(FoodOrder)
        .options(joinedload(FoodOrder.restaurant))
        .where(FoodOrder.customer_id == customer.id)
        .order_by(FoodOrder.id.desc())
    )
    rows = q.scalars().all()
    return [
        FoodOrderResponse(
            id=o.id,
            order_ref=o.order_ref,
            status=o.status.value,
            total_amount=float(o.total_amount or 0),
            delivery_fee=float(o.delivery_fee or 0),
            final_amount=float(o.final_amount or 0),
            delivery_address=o.delivery_address or "",
            payment_method=o.payment_method or "",
            payment_status=o.payment_status or "",
            created_at=o.created_at,
            is_self_pickup=o.is_self_pickup,
            restaurant_name=o.restaurant.name if o.restaurant else None,
            restaurant_address=o.restaurant.address if o.restaurant else None,
        )
        for o in rows
    ]


@router.get("/orders/{order_id}/details")
async def get_my_food_order_details(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if user.role not in (UserRole.CUSTOMER, UserRole.DRIVER):
        raise HTTPException(status_code=403, detail="Unauthorized")

    if user.role == UserRole.CUSTOMER:
        cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
        customer = cust_q.scalars().first()
        if not customer:
            raise HTTPException(status_code=404, detail="Customer not found")
        customer_id = customer.id
        driver_id = None
    else:
        drv_q = await db.execute(select(Driver).where(Driver.user_id == user.id))
        driver = drv_q.scalars().first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")
        customer_id = None
        driver_id = driver.id

    conditions = [FoodOrder.id == order_id]
    if customer_id:
        conditions.append(FoodOrder.customer_id == customer_id)
    if driver_id:
        conditions.append(FoodOrder.driver_id == driver_id)

    oq = await db.execute(select(FoodOrder).where(*conditions))
    order = oq.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    items_q = await db.execute(select(FoodOrderItem).where(FoodOrderItem.order_id == order.id))
    raw_items = items_q.scalars().all()

    menu_ids = [i.menu_item_id for i in raw_items if i.menu_item_id is not None]
    menu_by_id = {}
    if menu_ids:
        mq = await db.execute(select(MenuItem).where(MenuItem.id.in_(menu_ids)))
        menu_by_id = {m.id: m for m in mq.scalars().all()}

    items_details = []
    for it in raw_items:
        m = menu_by_id.get(it.menu_item_id)
        items_details.append({
            "name": m.name if m else "Removed item",
            "quantity": it.quantity,
            "price_at_order": float(it.price_at_order)
        })

    r_q = await db.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
    r = r_q.scalars().first()

    return {
        "items": items_details,
        "restaurant_name": r.name if r else "Unknown Restaurant",
        "restaurant_address": r.address if r else "Unknown Address",
    }


# ---------------------------------------------------------------------------
# Favorites — per-customer restaurant bookmarks (heart toggle on the home card)
# ---------------------------------------------------------------------------

async def _require_customer(db: AsyncSession, user: User) -> Customer:
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    return customer


@router.get("/favorites")
async def list_favorites(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """The caller's favorited restaurants (same summary shape as /restaurants)."""
    customer = await _require_customer(db, user)
    fav_q = await db.execute(
        select(Restaurant)
        .join(FavoriteRestaurant, FavoriteRestaurant.restaurant_id == Restaurant.id)
        .where(FavoriteRestaurant.customer_id == customer.id)
        .order_by(FavoriteRestaurant.id.desc())
    )
    out = []
    for r in fav_q.scalars().all():
        within = _is_within_hours(r.opening_time, r.closing_time)
        out.append(_restaurant_summary(r, bool(r.is_open) and within))
    return out


@router.post("/favorites/{restaurant_id}", status_code=201)
async def add_favorite(
    restaurant_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Idempotent — re-adding an existing favorite is a no-op."""
    customer = await _require_customer(db, user)
    r_q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    if not r_q.scalars().first():
        raise HTTPException(status_code=404, detail="Restaurant not found")
    existing = await db.execute(
        select(FavoriteRestaurant).where(
            FavoriteRestaurant.customer_id == customer.id,
            FavoriteRestaurant.restaurant_id == restaurant_id,
        )
    )
    if not existing.scalars().first():
        db.add(FavoriteRestaurant(customer_id=customer.id, restaurant_id=restaurant_id))
        await db.commit()
    return {"ok": True, "restaurant_id": restaurant_id, "is_favorite": True}


@router.delete("/favorites/{restaurant_id}")
async def remove_favorite(
    restaurant_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    customer = await _require_customer(db, user)
    fav_q = await db.execute(
        select(FavoriteRestaurant).where(
            FavoriteRestaurant.customer_id == customer.id,
            FavoriteRestaurant.restaurant_id == restaurant_id,
        )
    )
    fav = fav_q.scalars().first()
    if fav:
        await db.delete(fav)
        await db.commit()
    return {"ok": True, "restaurant_id": restaurant_id, "is_favorite": False}


# ---------------------------------------------------------------------------
# Driver dispatch endpoints — mirror /bookings/{id}/accept|decline|status
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
async def accept_food_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """First driver to call this wins. Subsequent callers get HTTP 409."""
    driver = await _get_driver(db, user)
    if not driver.is_approved:
        raise HTTPException(status_code=403, detail="Account not approved")

    q = await db.execute(select(FoodOrder).where(FoodOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # P2: only claimable once the restaurant has marked the order ready.
    # Driver claim doesn't change the order status — it stays READY_FOR_PICKUP
    # until the driver later taps "Picked up" (→ OUT_FOR_DELIVERY).
    if order.driver_id is not None or order.status != FoodOrderStatus.READY_FOR_PICKUP:
        raise HTTPException(
            status_code=409,
            detail="This order has already been taken, picked up, or cancelled",
        )

    order.driver_id = driver.id
    await db.commit()
    await db.refresh(order)

    # Get restaurant for the dismiss broadcast (same proximity query)
    r_q = await db.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
    r = r_q.scalars().first()
    if r and r.lat is not None and r.lng is not None:
        others = await find_all_nearby_drivers(
            db,
            float(r.lat),
            float(r.lng),
            vehicle_type=None,
            max_distance_km=10,
            exclude_driver_id=driver.id,
        )
        for od in others:
            await manager.send(
                od.user_id,
                "ride_taken",
                {"food_order_id": order.id, "order_ref": order.order_ref},
            )

    # Tell the customer a rider accepted
    cust_q = await db.execute(select(Customer).where(Customer.id == order.customer_id))
    c = cust_q.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "order_update",
            {"food_order_id": order.id, "status": order.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Rider on the way",
                body=f"{user.full_name or 'A rider'} accepted your order {order.order_ref}",
                type="order_update",
            )
        )
        await db.commit()

    return {
        "ok": True,
        "food_order_id": order.id,
        "order_ref": order.order_ref,
        "status": order.status.value,
    }


@router.post("/orders/{order_id}/decline")
async def decline_food_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Per-driver dismissal. Under broadcast dispatch the order stays open for
    any other driver to accept — there's nothing to forward."""
    await _get_driver(db, user)
    q = await db.execute(select(FoodOrder).where(FoodOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return {"ok": True, "status": order.status.value}


# What the driver is allowed to advance to from each state. Under P2 the
# restaurant owns the CONFIRMED→READY transition, so a driver can only act
# from READY_FOR_PICKUP onwards.
_DRIVER_FOOD_TRANSITIONS = {
    FoodOrderStatus.READY_FOR_PICKUP: {FoodOrderStatus.OUT_FOR_DELIVERY, FoodOrderStatus.CANCELLED},
    FoodOrderStatus.OUT_FOR_DELIVERY: {FoodOrderStatus.DELIVERED, FoodOrderStatus.CANCELLED},
}


@router.patch("/orders/{order_id}/status")
async def update_food_order_status(
    order_id: int,
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Assigned driver advances the order. Customer is notified on every step."""
    driver = await _get_driver(db, user)
    new_status_raw = (body.get("status") or "").strip()
    try:
        new_status = FoodOrderStatus(new_status_raw)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Unknown status '{new_status_raw}'")

    from sqlalchemy.orm import joinedload
    q = await db.execute(
        select(FoodOrder)
        .options(joinedload(FoodOrder.restaurant))
        .where(FoodOrder.id == order_id)
    )
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.driver_id != driver.id:
        raise HTTPException(status_code=403, detail="Not your order")

    allowed = _DRIVER_FOOD_TRANSITIONS.get(order.status, set())
    if new_status not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot transition {order.status.value} -> {new_status.value}",
        )

    now = datetime.now(timezone.utc)
    order.status = new_status
    if new_status == FoodOrderStatus.OUT_FOR_DELIVERY:
        order.picked_up_at = now
    elif new_status == FoodOrderStatus.DELIVERED:
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
                source_kind="food_order",
                source_id=order.id,
                description=f"Earned on {order.order_ref}",
            )
        
        # Calculate driver earnings and update driver profile stats
        from ...services.finance_service import _food_split
        driver_earnings, _ = _food_split(order)
        if order.driver_id:
            dq = await db.execute(select(Driver).where(Driver.id == order.driver_id))
            drv = dq.scalars().first()
            if drv:
                drv.total_earnings = (drv.total_earnings or Decimal(0)) + Decimal(str(driver_earnings))
                drv.today_earnings = (drv.today_earnings or Decimal(0)) + Decimal(str(driver_earnings))
                drv.today_rides = (drv.today_rides or 0) + 1

                # Check driver incentives (daily bonus and cycle bonus) from SystemSettings
                from ...models import DriverPayout, SystemSettings, Booking, BookingStatus, MarketOrder, MarketOrderStatus
                from app.services.finance_service import evaluate_and_award_driver_incentives
                await evaluate_and_award_driver_incentives(db, drv.id)
        
        # Check and deactivate driver if outstanding commission exceeds limit
        if order.driver_id:
            from ...services.finance_service import check_and_deactivate_driver
            await check_and_deactivate_driver(db, order.driver_id)
            
        # Check and deactivate restaurant if outstanding commission exceeds limit
        from ...services.finance_service import check_and_deactivate_restaurant
        await check_and_deactivate_restaurant(db, order.restaurant_id)
    elif new_status == FoodOrderStatus.CANCELLED and order.redeem_points and order.redeem_points > 0:
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
                source_kind="food_order",
                source_id=order.id,
                description=f"Refund — {order.order_ref} cancelled",
                balance_after=cust_refund.loyalty_points,
            ))
            order.redeem_points = 0
            order.redeem_discount = Decimal("0.00")

    await db.commit()
    await db.refresh(order)

    # Notify both customer AND restaurant owner so the merchant panel sees
    # the rider's progress.
    cust_q = await db.execute(select(Customer).where(Customer.id == order.customer_id))
    c = cust_q.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "order_update",
            {"food_order_id": order.id, "status": order.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title=f"Order {order.status.value.replace('_', ' ').title()}",
                body=f"Order {order.order_ref} is now {order.status.value.replace('_', ' ')}",
                type="order_update",
            )
        )
        await db.commit()
    r_q = await db.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
    r = r_q.scalars().first()
    if r and r.owner_id:
        await manager.send(
            r.owner_id,
            "order_update",
            {"food_order_id": order.id, "status": order.status.value},
        )
    if order.driver_id:
        drv_q = await db.execute(select(Driver).where(Driver.id == order.driver_id))
        drv = drv_q.scalars().first()
        if drv:
            await manager.send(
                drv.user_id,
                "order_update",
                {"food_order_id": order.id, "status": order.status.value},
            )

    return {"ok": True, "status": order.status.value}




@router.post("/orders/{order_id}/cancel")
async def cancel_food_order(
    order_id: int,
    body: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Allow customer to cancel their own food order, but only if it's still PENDING."""
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    q = await db.execute(select(FoodOrder).where(FoodOrder.id == order_id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.customer_id != customer.id:
        raise HTTPException(status_code=403, detail="Not your order")

    if order.status != FoodOrderStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel an order in status {order.status.value}. Only pending orders can be cancelled.",
        )

    reason = (body.get("reason") or "Customer cancelled the order").strip()
    order.status = FoodOrderStatus.CANCELLED
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
                description=f"Refund — Customer cancelled food order {order.order_ref}",
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
            source_kind="food_order",
            source_id=order.id,
            description=f"Refund — Customer cancelled food order {order.order_ref}",
            balance_after=customer.loyalty_points,
        ))
        order.redeem_points = 0
        order.redeem_discount = Decimal("0.00")

    await db.commit()
    await db.refresh(order)

    # Notify customer via WebSocket and in-app notification
    await manager.send(
        user.id,
        "order_update",
        {"food_order_id": order.id, "status": order.status.value},
    )
    db.add(
        Notification(
            user_id=user.id,
            title="Order Cancelled",
            body=f"You cancelled order {order.order_ref}",
            type="order_update",
        )
    )

    # Notify restaurant owner so the pending order disappears from their portal
    r_q = await db.execute(select(Restaurant).where(Restaurant.id == order.restaurant_id))
    restaurant = r_q.scalars().first()
    if restaurant and restaurant.owner_id:
        await manager.send(
            restaurant.owner_id,
            "order_update",
            {
                "food_order_id": order.id,
                "status": order.status.value,
                "reason": "Customer cancelled the order",
            },
        )
        db.add(
            Notification(
                user_id=restaurant.owner_id,
                title="Order Cancelled by Customer",
                body=f"Order {order.order_ref} was cancelled by the customer",
                type="order_update",
            )
        )

    await db.commit()
    return {"ok": True, "status": order.status.value}


@router.post("/orders/{order_id}/rate")
async def rate_food_order(
    order_id: int,
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Customer rates a delivered food order (1-5 stars + optional text feedback).

    Silently allows re-rating so the customer can correct an accidental tap.
    """
    rating = body.get("rating")
    if not isinstance(rating, int) or not (1 <= rating <= 5):
        raise HTTPException(status_code=400, detail="rating must be an integer between 1 and 5")
    feedback = (body.get("feedback") or "").strip() or None

    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    q = await db.execute(select(FoodOrder).where(FoodOrder.id == order_id, FoodOrder.customer_id == customer.id))
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.status != FoodOrderStatus.DELIVERED:
        raise HTTPException(status_code=400, detail="Only delivered orders can be rated")

    order.customer_rating = rating
    order.customer_feedback = feedback
    await db.commit()

    # Notify the assigned driver via WebSocket so the driver rating screen
    # updates in real-time without having to wait for the next poll cycle.
    if order.driver_id:
        from ...models import Driver as _Driver
        dq = await db.execute(select(_Driver).where(_Driver.id == order.driver_id))
        drv = dq.scalars().first()
        if drv:
            await manager.send(
                drv.user_id,
                "food_order_rated",
                {
                    "food_order_id": order.id,
                    "order_ref": order.order_ref,
                    "customer_rating": rating,
                    "customer_feedback": feedback,
                },
            )

    return {"ok": True, "customer_rating": rating}


@router.post("/orders/{order_id}/complete")
async def complete_self_pickup_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Self-pickup only: Customer marks their order as DELIVERED/completed."""
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    q = await db.execute(
        select(FoodOrder)
        .where(FoodOrder.id == order_id, FoodOrder.customer_id == customer.id)
    )
    order = q.scalars().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if not order.is_self_pickup:
        raise HTTPException(status_code=400, detail="Only self-pickup orders can be completed by the customer")

    if order.status != FoodOrderStatus.READY_FOR_PICKUP:
        raise HTTPException(
            status_code=400,
            detail=f"Order must be READY_FOR_PICKUP to complete (current: {order.status.value})",
        )

    order.status = FoodOrderStatus.DELIVERED
    order.delivered_at = datetime.now(timezone.utc)
    order.payment_status = "paid"

    # award loyalty points
    if order.final_amount:
        from ...services.loyalty_service import award_points as _award
        await _award(
            db, customer,
            spend_amount=order.final_amount,
            source_kind="food_order",
            source_id=order.id,
            description=f"Earned on {order.order_ref}",
        )

    # notify restaurant owner / customer update
    await manager.send(
        customer.user_id,
        "order_update",
        {"food_order_id": order.id, "status": order.status.value},
    )
    await db.commit()
    return {"ok": True, "status": order.status.value}

"""Restaurant-owner portal endpoints.

The restaurant owner registers their restaurant after OTP-verifying as role=
restaurant_owner. The new Restaurant row is created with `is_active=False`
(pending admin approval) and `owner_id` pointing to the current user. Once
admin flips `is_active=True` via `/admin/restaurants`, the restaurant becomes
visible to customers and starts receiving orders.
"""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import os
import secrets
from typing import List, Optional

from fastapi import APIRouter, Body, Depends, File, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select

from ...database import get_db
from ...models import (
    Customer,
    FoodOrder,
    FoodOrderItem,
    FoodOrderStatus,
    MenuCategory,
    MenuItem,
    Notification,
    Restaurant,
    User,
    WalletTransaction,
)
from ...schemas.restaurant_schema import (
    MenuCategoryCreate,
    MenuCategoryUpdate,
    MenuItemCreate,
    MenuItemUpdate,
    RestaurantProfileUpdate,
    RestaurantRegisterRequest,
    RestaurantProfileResponse,
)
from ...services.auth_service import require_role
from ...services.ws_manager import manager

router = APIRouter()

# ---------------------------------------------------------------------------
# Image upload — files land under ziggo_admin_panel/static/uploads/{kind}/
# (peer of the backend `app/` package) and are served by the /static mount in
# main.py, so URLs are stable across the customer + merchant apps.
# ---------------------------------------------------------------------------
# /app/app/api/v1/restaurant.py → parents[3] = /app
_REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
_UPLOAD_BASE = os.path.join(_REPO_ROOT, "ziggo_admin_panel", "static", "uploads")
_ALLOWED_IMG_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
_MAX_IMG_BYTES = 5 * 1024 * 1024


async def _save_image(photo: UploadFile, kind: str) -> str:
    if not photo or not photo.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in _ALLOWED_IMG_EXTS:
        raise HTTPException(status_code=400, detail="Image must be JPG, PNG, or WEBP")
    data = await photo.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(data) > _MAX_IMG_BYTES:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB")
    target_dir = os.path.join(_UPLOAD_BASE, kind)
    os.makedirs(target_dir, exist_ok=True)
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(target_dir, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/{kind}/{fname}"


def _to_response(r: Restaurant) -> RestaurantProfileResponse:
    return RestaurantProfileResponse(
        id=r.id,
        name=r.name,
        description=r.description,
        address=r.address,
        lat=float(r.lat) if r.lat is not None else None,
        lng=float(r.lng) if r.lng is not None else None,
        phone_number=r.phone_number,
        image_url=r.image_url,
        cuisine=r.cuisine,
        opening_time=r.opening_time,
        closing_time=r.closing_time,
        delivery_fee=float(r.delivery_fee or 0),
        eta_minutes=r.eta_minutes,
        rating=float(r.rating or 0),
        is_active=bool(r.is_active),
        is_open=bool(r.is_open) if r.is_open is not None else True,
        is_approved=bool(r.is_active),
        created_at=r.created_at,
    )


async def _get_owned_restaurant(
    db: AsyncSession, user: User
) -> Optional[Restaurant]:
    q = await db.execute(select(Restaurant).where(Restaurant.owner_id == user.id))
    return q.scalars().first()


@router.post(
    "/register",
    response_model=RestaurantProfileResponse,
    status_code=201,
)
async def register_restaurant(
    body: RestaurantRegisterRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """DEPRECATED — self-registration disabled. Restaurants are now created
    only by admin via /admin/restaurants/new. Owner logs in with the phone
    number the admin set up for them.
    """
    raise HTTPException(
        status_code=403,
        detail="Restaurants are created by Ziggo admin. Contact your account manager.",
    )

    # ---- below is unreachable; kept for reference / re-enable path ----
    existing = await _get_owned_restaurant(db, user)
    if existing is not None:
        raise HTTPException(
            status_code=409,
            detail="You already have a registered restaurant",
        )

    r = Restaurant(
        owner_id=user.id,
        name=body.name.strip(),
        description=body.description,
        address=body.address.strip(),
        lat=Decimal(str(body.lat)),
        lng=Decimal(str(body.lng)),
        phone_number=(body.phone_number or user.phone_number),
        cuisine=body.cuisine,
        opening_time=body.opening_time,
        closing_time=body.closing_time,
        delivery_fee=Decimal(str(body.delivery_fee)) if body.delivery_fee is not None else Decimal("0"),
        eta_minutes=body.eta_minutes or 30,
        image_url=body.image_url,
        is_active=False,  # admin approval gate
        is_open=True,
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    return _to_response(r)


@router.post("/online")
async def toggle_online(
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Owner flips `is_open`. While false, new orders to this restaurant are
    still allowed by the backend (UI prevents this client-side), but in the
    next phase we'll plug a check at order-creation time."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    r.is_open = bool(body.get("is_open", False))
    await db.commit()
    await db.refresh(r)
    return {"ok": True, "is_open": r.is_open}


@router.get("/me", response_model=Optional[RestaurantProfileResponse])
async def get_my_restaurant(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Owner fetches their restaurant profile.

    Returns null if they haven't registered yet — the Flutter UI uses that to
    decide between showing the home portal and the registration form.
    """
    r = await _get_owned_restaurant(db, user)
    if r is None:
        return None
    return _to_response(r)


# ---------------------------------------------------------------------------
# Order workflow — restaurant owner gates the order before riders see it.
# ---------------------------------------------------------------------------

def _order_to_dict(o: FoodOrder, cust_user: Optional[User] = None, comm_pct: float = 20.0) -> dict:
    return {
        "id": o.id,
        "order_ref": o.order_ref,
        "status": o.status.value,
        "customer_id": o.customer_id,
        "driver_id": o.driver_id,
        "total_amount": float(o.total_amount or 0),
        "delivery_fee": float(o.delivery_fee or 0),
        "final_amount": float(o.final_amount or 0),
        "commission_percentage": comm_pct,
        "delivery_address": o.delivery_address,
        "delivery_lat": float(o.delivery_lat) if o.delivery_lat is not None else None,
        "delivery_lng": float(o.delivery_lng) if o.delivery_lng is not None else None,
        "payment_method": o.payment_method,
        "payment_status": o.payment_status,
        "instructions": o.instructions,
        "created_at": o.created_at,
        "confirmed_at": o.confirmed_at,
        "ready_at": o.ready_at,
        "picked_up_at": o.picked_up_at,
        "delivered_at": o.delivered_at,
        "customer_name": cust_user.full_name if cust_user else None,
        "customer_phone": cust_user.phone_number if cust_user else None,
    }


_PENDING_BUCKET = (FoodOrderStatus.PENDING,)
_ACTIVE_BUCKET = (
    FoodOrderStatus.CONFIRMED,
    FoodOrderStatus.PREPARING,
    FoodOrderStatus.READY_FOR_PICKUP,
    FoodOrderStatus.OUT_FOR_DELIVERY,
)
_HISTORY_BUCKET = (FoodOrderStatus.DELIVERED, FoodOrderStatus.CANCELLED)


@router.get("/orders")
async def list_my_orders(
    status: str = "pending",
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """List orders for the owner's restaurant. `status` picks the bucket:
    `pending` (waiting for accept), `active` (CONFIRMED..OUT_FOR_DELIVERY),
    or `history` (DELIVERED/CANCELLED)."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")

    bucket = {
        "pending": _PENDING_BUCKET,
        "active": _ACTIVE_BUCKET,
        "history": _HISTORY_BUCKET,
    }.get(status)
    if bucket is None:
        raise HTTPException(
            status_code=400,
            detail="status must be one of: pending, active, history",
        )

    q = await db.execute(
        select(FoodOrder)
        .where(FoodOrder.restaurant_id == r.id, FoodOrder.status.in_(bucket))
        .order_by(FoodOrder.id.desc())
        .limit(100)
    )
    orders = q.scalars().all()
    if not orders:
        return []

    # Resolve customer phones in a single query so the merchant UI can call
    # without N+1.
    cust_ids = list({o.customer_id for o in orders if o.customer_id})
    user_by_id: dict[int, User] = {}
    if cust_ids:
        cq = await db.execute(select(Customer).where(Customer.id.in_(cust_ids)))
        cust_user_ids = [c.user_id for c in cq.scalars().all()]
        cust_to_user: dict[int, int] = {
            c.id: c.user_id for c in (await db.execute(select(Customer).where(Customer.id.in_(cust_ids)))).scalars().all()
        }
        if cust_user_ids:
            uq = await db.execute(select(User).where(User.id.in_(cust_user_ids)))
            users = uq.scalars().all()
            user_by_id = {u.id: u for u in users}
        # build mapping customer_id → User
        cust_to_user_obj: dict[int, User] = {
            cid: user_by_id.get(uid) for cid, uid in cust_to_user.items()
        }
    else:
        cust_to_user_obj = {}

    comm_pct = float(r.commission_percentage) if r.commission_percentage is not None else 20.0
    return [_order_to_dict(o, cust_to_user_obj.get(o.customer_id), comm_pct) for o in orders]


async def _refund_wallet_if_needed(
    db: AsyncSession, order: FoodOrder, reason: str
) -> None:
    """Credit the customer's wallet back if they paid via wallet."""
    if order.payment_method != "wallet" or order.payment_status != "paid":
        return
    cq = await db.execute(select(Customer).where(Customer.id == order.customer_id))
    customer = cq.scalars().first()
    if not customer:
        return
    customer.wallet_balance = (customer.wallet_balance or Decimal(0)) + (
        order.final_amount or Decimal(0)
    )
    db.add(
        WalletTransaction(
            user_id=customer.user_id,
            amount=order.final_amount,
            type="credit",
            description=f"Refund for {reason}: order {order.order_ref}",
            reference_id=order.order_ref,
            balance_after=customer.wallet_balance,
        )
    )
    order.payment_status = "refunded"


async def _load_owner_scoped_order(
    db: AsyncSession, user: User, order_id: int
) -> tuple[Restaurant, FoodOrder]:
    """Load the order + verify the caller actually owns the restaurant. 403s
    if the order belongs to someone else's restaurant."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    q = await db.execute(select(FoodOrder).where(FoodOrder.id == order_id))
    o = q.scalars().first()
    if not o:
        raise HTTPException(status_code=404, detail="Order not found")
    if o.restaurant_id != r.id:
        raise HTTPException(status_code=403, detail="Not your order")
    return r, o


@router.post("/orders/{order_id}/accept")
async def accept_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """PENDING → CONFIRMED. Restaurant has agreed to cook the order."""
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != FoodOrderStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot accept an order in status {o.status.value}",
        )
    o.status = FoodOrderStatus.CONFIRMED
    o.confirmed_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(o)

    # Notify customer
    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "order_update",
            {"food_order_id": o.id, "status": o.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Order confirmed",
                body=f"The restaurant is preparing your order {o.order_ref}",
                type="order_update",
            )
        )
        await db.commit()
    return {"ok": True, "status": o.status.value}


@router.post("/orders/{order_id}/reject")
async def reject_order(
    order_id: int,
    body: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """PENDING → CANCELLED + wallet refund + customer notification."""
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != FoodOrderStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot reject an order in status {o.status.value}",
        )
    reason = (body.get("reason") or "Restaurant unable to accept").strip()
    o.status = FoodOrderStatus.CANCELLED
    o.cancellation_reason = reason
    await _refund_wallet_if_needed(db, o, reason="restaurant rejected")
    await db.commit()
    await db.refresh(o)

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "order_update",
            {
                "food_order_id": o.id,
                "status": o.status.value,
                "reason": reason,
            },
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Order rejected",
                body=f"Order {o.order_ref}: {reason}",
                type="order_update",
            )
        )
        await db.commit()
    return {"ok": True, "status": o.status.value}


@router.post("/orders/{order_id}/ready")
async def mark_order_ready(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """CONFIRMED → READY_FOR_PICKUP. **This is where rider dispatch fires.**"""
    # food.py imports we need here to avoid circular import at module load
    from .food import _broadcast_to_riders

    r, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status not in (FoodOrderStatus.CONFIRMED, FoodOrderStatus.PREPARING):
        raise HTTPException(
            status_code=400,
            detail=f"Order must be CONFIRMED to mark ready (current: {o.status.value})",
        )
    o.status = FoodOrderStatus.READY_FOR_PICKUP
    o.ready_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(o)

    # Notify customer ("Your food is ready, finding a rider")
    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    customer_user: Optional[User] = None
    if c:
        u_q = await db.execute(select(User).where(User.id == c.user_id))
        customer_user = u_q.scalars().first()
        await manager.send(
            c.user_id,
            "order_update",
            {"food_order_id": o.id, "status": o.status.value},
        )

    # Broadcast to nearby riders
    items_count_q = await db.execute(
        select(FoodOrder).where(FoodOrder.id == o.id)
    )
    # Total item count: pull from food_order_items
    from ...models import FoodOrderItem
    items_q = await db.execute(
        select(FoodOrderItem).where(FoodOrderItem.order_id == o.id)
    )
    items = items_q.scalars().all()
    items_count = sum(i.quantity for i in items) if items else 1

    if customer_user is not None:
        await _broadcast_to_riders(
            db,
            o,
            r,
            customer_user,
            items_count,
            Decimal(str(o.delivery_fee or 0)),
        )
    await db.commit()
    return {"ok": True, "status": o.status.value}


# ---------------------------------------------------------------------------
# Single-order detail (with line items so the merchant knows what to cook)
# ---------------------------------------------------------------------------


@router.get("/orders/{order_id}")
async def get_order_detail(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Full order payload for the merchant: line items joined to menu items,
    plus customer + bill summary. Owner-scoped — 403 if the order is on
    someone else's restaurant."""
    r, o = await _load_owner_scoped_order(db, user, order_id)

    items_q = await db.execute(
        select(FoodOrderItem).where(FoodOrderItem.order_id == o.id)
    )
    raw_items = items_q.scalars().all()

    menu_ids = [i.menu_item_id for i in raw_items if i.menu_item_id is not None]
    menu_by_id: dict[int, MenuItem] = {}
    if menu_ids:
        mq = await db.execute(select(MenuItem).where(MenuItem.id.in_(menu_ids)))
        menu_by_id = {m.id: m for m in mq.scalars().all()}

    cust_user: Optional[User] = None
    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        uq = await db.execute(select(User).where(User.id == c.user_id))
        cust_user = uq.scalars().first()

    line_items = []
    for it in raw_items:
        m = menu_by_id.get(it.menu_item_id)
        line_items.append(
            {
                "menu_item_id": it.menu_item_id,
                "name": m.name if m else "Removed item",
                "quantity": it.quantity,
                "price_at_order": float(it.price_at_order or 0),
                "line_total": float((it.price_at_order or Decimal(0)) * it.quantity),
                "is_veg": bool(m.is_veg) if m else False,
                "notes": it.notes,
            }
        )

    comm_pct = float(r.commission_percentage) if r.commission_percentage is not None else 20.0
    base = _order_to_dict(o, cust_user, comm_pct)
    base["items"] = line_items
    return base


# ---------------------------------------------------------------------------
# Today's stats — the dashboard counters at the top of the home screen
# ---------------------------------------------------------------------------


@router.get("/stats/today")
async def stats_today(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Counts + revenue for orders created today (UTC). Excludes cancelled
    orders from the revenue line but keeps them in the count so the merchant
    can spot a high-rejection day."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")

    now = datetime.now(timezone.utc)
    start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)

    q = await db.execute(
        select(FoodOrder).where(
            FoodOrder.restaurant_id == r.id,
            FoodOrder.created_at >= start_of_day,
        )
    )
    orders = q.scalars().all()

    delivered = [o for o in orders if o.status == FoodOrderStatus.DELIVERED]
    cancelled = [o for o in orders if o.status == FoodOrderStatus.CANCELLED]
    in_flight = [
        o
        for o in orders
        if o.status
        not in (FoodOrderStatus.DELIVERED, FoodOrderStatus.CANCELLED)
    ]
    revenue = sum(
        (o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0))
        for o in delivered
    )

    return {
        "today_orders": len(orders),
        "today_delivered": len(delivered),
        "today_cancelled": len(cancelled),
        "today_in_flight": len(in_flight),
        "today_revenue": float(revenue),
        "is_open": bool(r.is_open),
        "is_approved": bool(r.is_active),
    }


# ---------------------------------------------------------------------------
# Menu — categories
# ---------------------------------------------------------------------------


def _category_to_dict(c: MenuCategory) -> dict:
    return {
        "id": c.id,
        "name": c.name,
        "description": c.description,
        "display_order": c.display_order or 0,
        "is_active": bool(c.is_active),
    }


@router.get("/categories")
async def list_categories(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    q = await db.execute(
        select(MenuCategory)
        .where(MenuCategory.restaurant_id == r.id)
        .order_by(MenuCategory.display_order.asc(), MenuCategory.id.asc())
    )
    return [_category_to_dict(c) for c in q.scalars().all()]


@router.post("/categories", status_code=201)
async def create_category(
    body: MenuCategoryCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    c = MenuCategory(
        restaurant_id=r.id,
        name=body.name.strip(),
        description=body.description,
        display_order=body.display_order or 0,
        is_active=True,
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return _category_to_dict(c)


async def _load_owned_category(
    db: AsyncSession, user: User, category_id: int
) -> MenuCategory:
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    q = await db.execute(select(MenuCategory).where(MenuCategory.id == category_id))
    c = q.scalars().first()
    if c is None:
        raise HTTPException(status_code=404, detail="Category not found")
    if c.restaurant_id != r.id:
        raise HTTPException(status_code=403, detail="Not your category")
    return c


@router.patch("/categories/{category_id}")
async def update_category(
    category_id: int,
    body: MenuCategoryUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    c = await _load_owned_category(db, user, category_id)
    if body.name is not None:
        c.name = body.name.strip()
    if body.description is not None:
        c.description = body.description
    if body.display_order is not None:
        c.display_order = body.display_order
    if body.is_active is not None:
        c.is_active = body.is_active
    await db.commit()
    await db.refresh(c)
    return _category_to_dict(c)


@router.delete("/categories/{category_id}")
async def delete_category(
    category_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    c = await _load_owned_category(db, user, category_id)
    # Detach items from this category instead of deleting them — owner can
    # re-bucket them after.
    upd = await db.execute(
        select(MenuItem).where(MenuItem.category_id == c.id)
    )
    for it in upd.scalars().all():
        it.category_id = None
    await db.delete(c)
    await db.commit()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Menu — items
# ---------------------------------------------------------------------------


def _item_to_dict(it: MenuItem) -> dict:
    return {
        "id": it.id,
        "category_id": it.category_id,
        "name": it.name,
        "description": it.description,
        "price": float(it.price or 0),
        "image_url": it.image_url,
        "is_available": bool(it.is_available),
        "is_veg": bool(it.is_veg),
        "prep_time_min": it.prep_time_min,
    }


@router.get("/items")
async def list_items(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    q = await db.execute(
        select(MenuItem)
        .where(MenuItem.restaurant_id == r.id)
        .order_by(MenuItem.category_id.asc(), MenuItem.id.asc())
    )
    return [_item_to_dict(it) for it in q.scalars().all()]


@router.post("/items", status_code=201)
async def create_item(
    body: MenuItemCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")

    if body.category_id is not None:
        cq = await db.execute(
            select(MenuCategory).where(MenuCategory.id == body.category_id)
        )
        c = cq.scalars().first()
        if c is None or c.restaurant_id != r.id:
            raise HTTPException(status_code=400, detail="Invalid category")

    it = MenuItem(
        restaurant_id=r.id,
        category_id=body.category_id,
        name=body.name.strip(),
        description=body.description,
        price=Decimal(str(body.price)),
        image_url=body.image_url,
        is_available=body.is_available,
        is_veg=body.is_veg,
        prep_time_min=body.prep_time_min,
    )
    db.add(it)
    await db.commit()
    await db.refresh(it)
    return _item_to_dict(it)


async def _load_owned_item(
    db: AsyncSession, user: User, item_id: int
) -> MenuItem:
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    q = await db.execute(select(MenuItem).where(MenuItem.id == item_id))
    it = q.scalars().first()
    if it is None:
        raise HTTPException(status_code=404, detail="Item not found")
    if it.restaurant_id != r.id:
        raise HTTPException(status_code=403, detail="Not your item")
    return it


@router.patch("/items/{item_id}")
async def update_item(
    item_id: int,
    body: MenuItemUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    it = await _load_owned_item(db, user, item_id)
    if body.category_id is not None:
        if body.category_id != 0:
            cq = await db.execute(
                select(MenuCategory).where(MenuCategory.id == body.category_id)
            )
            c = cq.scalars().first()
            if c is None or c.restaurant_id != it.restaurant_id:
                raise HTTPException(status_code=400, detail="Invalid category")
            it.category_id = body.category_id
        else:
            it.category_id = None
    if body.name is not None:
        it.name = body.name.strip()
    if body.description is not None:
        it.description = body.description
    if body.price is not None:
        it.price = Decimal(str(body.price))
    if body.image_url is not None:
        it.image_url = body.image_url
    if body.is_available is not None:
        it.is_available = body.is_available
    if body.is_veg is not None:
        it.is_veg = body.is_veg
    if body.prep_time_min is not None:
        it.prep_time_min = body.prep_time_min
    await db.commit()
    await db.refresh(it)
    return _item_to_dict(it)


@router.delete("/items/{item_id}")
async def delete_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    it = await _load_owned_item(db, user, item_id)
    await db.delete(it)
    await db.commit()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Profile editing
# ---------------------------------------------------------------------------


@router.patch("/profile", response_model=RestaurantProfileResponse)
async def update_profile(
    body: RestaurantProfileUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Owner-side edits for hours, fee, address, etc. Updating address requires
    BOTH lat+lng (so the dispatch radius stays consistent)."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")

    if body.address is not None and (body.lat is None or body.lng is None):
        raise HTTPException(
            status_code=400,
            detail="Updating address requires lat and lng (re-pick on the map)",
        )

    if body.name is not None:
        r.name = body.name.strip()
    if body.description is not None:
        r.description = body.description
    if body.address is not None:
        r.address = body.address.strip()
        r.lat = Decimal(str(body.lat))
        r.lng = Decimal(str(body.lng))
    if body.phone_number is not None:
        r.phone_number = body.phone_number
    if body.cuisine is not None:
        r.cuisine = body.cuisine
    if body.opening_time is not None:
        r.opening_time = body.opening_time
    if body.closing_time is not None:
        r.closing_time = body.closing_time
    if body.delivery_fee is not None:
        r.delivery_fee = Decimal(str(body.delivery_fee))
    if body.eta_minutes is not None:
        r.eta_minutes = body.eta_minutes

    await db.commit()
    await db.refresh(r)
    return _to_response(r)


# ---------------------------------------------------------------------------
# Image upload endpoints (multipart)
# ---------------------------------------------------------------------------


@router.post("/cover-image", response_model=RestaurantProfileResponse)
async def upload_cover(
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Upload (or replace) the restaurant cover image. Customers see this on
    the restaurant list + detail pages."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")
    url = await _save_image(photo, "restaurants")
    r.image_url = url
    await db.commit()
    await db.refresh(r)
    return _to_response(r)


@router.post("/items/{item_id}/image")
async def upload_item_image(
    item_id: int,
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Upload (or replace) the menu item photo."""
    it = await _load_owned_item(db, user, item_id)
    url = await _save_image(photo, "menu_items")
    it.image_url = url
    await db.commit()
    await db.refresh(it)
    return _item_to_dict(it)


# ---------------------------------------------------------------------------
# Earnings — weekly + monthly breakdowns
# ---------------------------------------------------------------------------


@router.get("/earnings")
async def get_earnings(
    period: str = "week",
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """Per-day revenue series + headline totals. `period` is one of:
    `week` (last 7 days incl. today) or `month` (last 30 days)."""
    r = await _get_owned_restaurant(db, user)
    if r is None:
        raise HTTPException(status_code=404, detail="Register your restaurant first")

    days = 7 if period == "week" else 30 if period == "month" else 7
    now = datetime.now(timezone.utc)
    start = (now - timedelta(days=days - 1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )

    q = await db.execute(
        select(FoodOrder).where(
            FoodOrder.restaurant_id == r.id,
            FoodOrder.created_at >= start,
        )
    )
    orders = q.scalars().all()

    series: dict[str, dict[str, float]] = {}
    for i in range(days):
        d = (start + timedelta(days=i)).strftime("%Y-%m-%d")
        series[d] = {"revenue": 0.0, "orders": 0, "delivered": 0}

    total_revenue = Decimal("0")
    total_orders = 0
    total_delivered = 0
    total_cancelled = 0
    for o in orders:
        if o.created_at is None:
            continue
        day_key = o.created_at.astimezone(timezone.utc).strftime("%Y-%m-%d")
        bucket = series.get(day_key)
        if not bucket:
            continue
        bucket["orders"] = bucket["orders"] + 1
        total_orders += 1
        if o.status == FoodOrderStatus.DELIVERED:
            rev = (o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0))
            bucket["revenue"] = float(Decimal(str(bucket["revenue"])) + rev)
            bucket["delivered"] = bucket["delivered"] + 1
            total_revenue += rev
            total_delivered += 1
        elif o.status == FoodOrderStatus.CANCELLED:
            total_cancelled += 1

    return {
        "period": period if period in ("week", "month") else "week",
        "days": [
            {
                "date": d,
                "revenue": round(v["revenue"], 2),
                "orders": int(v["orders"]),
                "delivered": int(v["delivered"]),
            }
            for d, v in series.items()
        ],
        "total_revenue": float(total_revenue),
        "total_orders": total_orders,
        "total_delivered": total_delivered,
        "total_cancelled": total_cancelled,
        "average_order_value": (
            float(total_revenue / total_delivered) if total_delivered else 0
        ),
    }


# ---------------------------------------------------------------------------
# "Mark preparing" — CONFIRMED → PREPARING (kitchen visibility step)
# ---------------------------------------------------------------------------


@router.post("/orders/{order_id}/preparing")
async def mark_preparing(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("restaurant_owner")),
):
    """CONFIRMED → PREPARING. Optional intermediate step PickMe uses to signal
    that the kitchen has actually started cooking."""
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != FoodOrderStatus.CONFIRMED:
        raise HTTPException(
            status_code=400,
            detail=f"Order must be CONFIRMED to mark preparing (current: {o.status.value})",
        )
    o.status = FoodOrderStatus.PREPARING
    await db.commit()
    await db.refresh(o)

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "order_update",
            {"food_order_id": o.id, "status": o.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Your food is being prepared",
                body=f"The chef has started cooking your order {o.order_ref}",
                type="order_update",
            )
        )
        await db.commit()
    return {"ok": True, "status": o.status.value}

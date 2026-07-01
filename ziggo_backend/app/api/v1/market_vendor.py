"""Market-vendor portal endpoints.

The vendor account is created upfront by the admin (see admin_panel/routes.py
`/admin/market/new`). The admin form takes a phone number, finds or creates a
User with role=market_owner, then creates the MarketVendor row with
`is_active=False` so the admin has a final approval step (same flow as
restaurants). Once approved, the owner OTP-logs in as market_owner and lands
on the vendor portal.
"""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import os
import secrets
from typing import Optional

from fastapi import APIRouter, Body, Depends, File, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...database import get_db
from ...models import (
    Customer,
    MarketOrder,
    MarketOrderItem,
    MarketOrderStatus,
    MarketVendor,
    Notification,
    Product,
    User,
    UserRole,
    WalletTransaction,
    MarketAd,
)
from ...schemas.market_schema import (
    MarketVendorProfileResponse,
    MarketVendorProfileUpdate,
    MarketVendorRegisterRequest,
    ProductCreate,
    ProductUpdate,
)
from ...services.auth_service import require_role
from ...services.matching_service import find_all_nearby_drivers
from ...services.ws_manager import manager
from ...services import market_delivery_service as delivery

router = APIRouter()


# ---------------------------------------------------------------------------
# Image upload (shared with restaurant uploads dir layout — now under
# top-level ziggo_admin_panel/, peer of the backend `app/` package).
# ---------------------------------------------------------------------------
# /app/app/api/v1/market_vendor.py → parents[3] = /app
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


def _to_response(v: MarketVendor) -> MarketVendorProfileResponse:
    return MarketVendorProfileResponse(
        id=v.id,
        name=v.name,
        description=v.description,
        category=v.category,
        address=v.address,
        lat=float(v.lat) if v.lat is not None else None,
        lng=float(v.lng) if v.lng is not None else None,
        phone_number=v.phone_number,
        image_url=v.image_url,
        logo_url=v.logo_url,
        opening_time=v.opening_time,
        closing_time=v.closing_time,
        delivery_fee=float(v.delivery_fee or 0),
        eta_minutes=v.eta_minutes,
        rating=float(v.rating or 0),
        is_active=bool(v.is_active),
        is_open=bool(v.is_open) if v.is_open is not None else True,
        is_approved=bool(v.is_active),
        delivery_radius_km=float(v.delivery_radius_km) if v.delivery_radius_km is not None else None,
        self_delivery=bool(v.self_delivery),
        marketplace_delivery=bool(v.marketplace_delivery),
        created_at=v.created_at,
    )


async def _get_owned_vendor(
    db: AsyncSession, user: User
) -> Optional[MarketVendor]:
    q = await db.execute(select(MarketVendor).where(MarketVendor.owner_id == user.id))
    return q.scalars().first()


@router.get("/me", response_model=Optional[MarketVendorProfileResponse])
async def get_my_vendor(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        return None
    return _to_response(v)


@router.post(
    "/register",
    response_model=MarketVendorProfileResponse,
    status_code=201,
)
async def register_vendor(
    body: MarketVendorRegisterRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    """DEPRECATED — self-registration disabled. Market stalls are now created
    only by admin via /admin/market/new. Owner logs in with the phone number
    the admin set up for them.
    """
    raise HTTPException(
        status_code=403,
        detail="Market stalls are created by Ziggo admin. Contact your account manager.",
    )

    # ---- below is unreachable; kept for reference / re-enable path ----
    existing = await _get_owned_vendor(db, user)
    if existing is not None:
        raise HTTPException(
            status_code=409,
            detail="You already have a registered market stall",
        )

    v = MarketVendor(
        owner_id=user.id,
        name=body.name.strip(),
        description=body.description,
        category=body.category,
        address=body.address.strip(),
        lat=Decimal(str(body.lat)),
        lng=Decimal(str(body.lng)),
        phone_number=(body.phone_number or user.phone_number),
        opening_time=body.opening_time,
        closing_time=body.closing_time,
        delivery_fee=Decimal(str(body.delivery_fee)) if body.delivery_fee is not None else Decimal("0"),
        eta_minutes=body.eta_minutes or 40,
        image_url=body.image_url,
        is_active=False,  # admin approval gate
        is_open=True,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    return _to_response(v)


@router.post("/online")
async def toggle_online(
    body: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    v.is_open = bool(body.get("is_open", False))
    await db.commit()
    await db.refresh(v)
    return {"ok": True, "is_open": v.is_open}


@router.patch("/profile", response_model=MarketVendorProfileResponse)
async def update_profile(
    body: MarketVendorProfileUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")

    if body.address is not None and (body.lat is None or body.lng is None):
        raise HTTPException(
            status_code=400,
            detail="Updating address requires lat and lng (re-pick on the map)",
        )

    if body.name is not None:
        v.name = body.name.strip()
    if body.description is not None:
        v.description = body.description
    if body.category is not None:
        v.category = body.category
    if body.address is not None:
        v.address = body.address.strip()
        v.lat = Decimal(str(body.lat))
        v.lng = Decimal(str(body.lng))
    if body.phone_number is not None:
        v.phone_number = body.phone_number
    if body.opening_time is not None:
        v.opening_time = body.opening_time
    if body.closing_time is not None:
        v.closing_time = body.closing_time
    if body.delivery_fee is not None:
        v.delivery_fee = Decimal(str(body.delivery_fee))
    if body.eta_minutes is not None:
        v.eta_minutes = body.eta_minutes
    if body.delivery_radius_km is not None:
        v.delivery_radius_km = Decimal(str(body.delivery_radius_km))
    if body.self_delivery is not None:
        v.self_delivery = body.self_delivery
    if body.marketplace_delivery is not None:
        v.marketplace_delivery = body.marketplace_delivery

    await db.commit()
    await db.refresh(v)
    return _to_response(v)


@router.post("/cover-image", response_model=MarketVendorProfileResponse)
async def upload_cover(
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    url = await _save_image(photo, "market_vendors")
    v.image_url = url
    await db.commit()
    await db.refresh(v)
    return _to_response(v)


@router.post("/logo-image", response_model=MarketVendorProfileResponse)
async def upload_logo(
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    url = await _save_image(photo, "market_vendors")
    v.logo_url = url
    await db.commit()
    await db.refresh(v)
    return _to_response(v)


@router.get("/ads")
async def list_my_ads(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    q = await db.execute(select(MarketAd).where(MarketAd.vendor_id == v.id))
    rows = q.scalars().all()
    return [
        {
            "id": ad.id,
            "vendor_id": ad.vendor_id,
            "image_url": ad.image_url,
            "radius_km": float(ad.radius_km),
            "is_active": ad.is_active,
            "created_at": ad.created_at,
        }
        for ad in rows
    ]


@router.post("/ads", status_code=201)
async def upload_ad(
    photo: UploadFile = File(...),
    radius_km: float = 5.0,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    url = await _save_image(photo, "market_ads")
    ad = MarketAd(
        vendor_id=v.id,
        image_url=url,
        radius_km=Decimal(str(radius_km)),
        is_active=True,
    )
    db.add(ad)
    await db.commit()
    await db.refresh(ad)
    return {
        "id": ad.id,
        "vendor_id": ad.vendor_id,
        "image_url": ad.image_url,
        "radius_km": float(ad.radius_km),
        "is_active": ad.is_active,
    }


@router.delete("/ads/{ad_id}")
async def delete_ad(
    ad_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    ad_q = await db.execute(
        select(MarketAd).where(MarketAd.id == ad_id, MarketAd.vendor_id == v.id)
    )
    ad = ad_q.scalars().first()
    if not ad:
        raise HTTPException(status_code=404, detail="Ad not found")
    await db.delete(ad)
    await db.commit()
    return {"ok": True}


# ---------------------------------------------------------------------------
# Products
# ---------------------------------------------------------------------------


def _product_to_dict(p: Product) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "description": p.description,
        "price": float(p.price or 0),
        "original_price": float(p.original_price) if p.original_price is not None else None,
        "stock_quantity": int(p.stock_quantity or 0),
        "unit": p.unit,
        "category": p.category,
        "is_popular": bool(p.is_popular),
        "image_url": p.image_url,
        "is_available": bool(p.is_available),
        "weight_kg": float(p.weight_kg) if p.weight_kg is not None else None,
    }


@router.get("/products")
async def list_products(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    q = await db.execute(
        select(Product).where(Product.vendor_id == v.id).order_by(Product.id.asc())
    )
    return [_product_to_dict(p) for p in q.scalars().all()]


@router.post("/products", status_code=201)
async def create_product(
    body: ProductCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    p = Product(
        vendor_id=v.id,
        name=body.name.strip(),
        description=body.description,
        price=Decimal(str(body.price)),
        original_price=Decimal(str(body.original_price))
        if body.original_price is not None
        else None,
        stock_quantity=body.stock_quantity,
        unit=body.unit,
        category=(body.category or "").strip() or None,
        is_popular=body.is_popular,
        image_url=body.image_url,
        is_available=body.is_available,
        weight_kg=Decimal(str(body.weight_kg)) if body.weight_kg is not None else None,
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return _product_to_dict(p)


async def _load_owned_product(
    db: AsyncSession, user: User, product_id: int
) -> Product:
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    q = await db.execute(select(Product).where(Product.id == product_id))
    p = q.scalars().first()
    if p is None:
        raise HTTPException(status_code=404, detail="Product not found")
    if p.vendor_id != v.id:
        raise HTTPException(status_code=403, detail="Not your product")
    return p


@router.patch("/products/{product_id}")
async def update_product(
    product_id: int,
    body: ProductUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    p = await _load_owned_product(db, user, product_id)
    if body.name is not None:
        p.name = body.name.strip()
    if body.description is not None:
        p.description = body.description
    if body.price is not None:
        p.price = Decimal(str(body.price))
    if body.original_price is not None:
        p.original_price = (
            Decimal(str(body.original_price)) if body.original_price > 0 else None
        )
    if body.stock_quantity is not None:
        p.stock_quantity = body.stock_quantity
    if body.unit is not None:
        p.unit = body.unit
    if body.category is not None:
        p.category = body.category.strip() or None
    if body.is_popular is not None:
        p.is_popular = body.is_popular
    if body.image_url is not None:
        p.image_url = body.image_url
    if body.is_available is not None:
        p.is_available = body.is_available
    if body.weight_kg is not None:
        p.weight_kg = Decimal(str(body.weight_kg)) if body.weight_kg > 0 else None
    await db.commit()
    await db.refresh(p)
    return _product_to_dict(p)


@router.delete("/products/{product_id}")
async def delete_product(
    product_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    p = await _load_owned_product(db, user, product_id)
    await db.delete(p)
    await db.commit()
    return {"ok": True}


@router.post("/products/{product_id}/image")
async def upload_product_image(
    product_id: int,
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    p = await _load_owned_product(db, user, product_id)
    url = await _save_image(photo, "products")
    p.image_url = url
    await db.commit()
    await db.refresh(p)
    return _product_to_dict(p)


# ---------------------------------------------------------------------------
# Orders — same buckets as the restaurant portal
# ---------------------------------------------------------------------------


def _order_to_dict(o: MarketOrder, cust_user: Optional[User] = None, comm_pct: float = 20.0) -> dict:
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
        "delivery_mode": o.delivery_mode,
        "delivery_distance_km": float(o.delivery_distance_km) if o.delivery_distance_km is not None else None,
        "total_weight_kg": float(o.total_weight_kg) if o.total_weight_kg is not None else None,
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


_PENDING_BUCKET = (MarketOrderStatus.PENDING,)
_ACTIVE_BUCKET = (
    MarketOrderStatus.CONFIRMED,
    MarketOrderStatus.PROCESSING,
    MarketOrderStatus.READY_FOR_PICKUP,
    MarketOrderStatus.OUT_FOR_DELIVERY,
    MarketOrderStatus.SHIPPED,  # legacy mirror
)
_HISTORY_BUCKET = (MarketOrderStatus.DELIVERED, MarketOrderStatus.CANCELLED)


@router.get("/orders")
async def list_my_orders(
    status: str = "pending",
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")

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
        select(MarketOrder)
        .where(MarketOrder.vendor_id == v.id, MarketOrder.status.in_(bucket))
        .order_by(MarketOrder.id.desc())
        .limit(100)
    )
    orders = q.scalars().all()
    if not orders:
        return []

    cust_ids = list({o.customer_id for o in orders if o.customer_id})
    cust_to_user: dict[int, User] = {}
    if cust_ids:
        cq = await db.execute(select(Customer).where(Customer.id.in_(cust_ids)))
        customers = cq.scalars().all()
        user_ids = [c.user_id for c in customers]
        uq = await db.execute(select(User).where(User.id.in_(user_ids)))
        user_by_id = {u.id: u for u in uq.scalars().all()}
        cust_to_user = {c.id: user_by_id.get(c.user_id) for c in customers}

    comm_pct = float(v.commission_percentage) if v.commission_percentage is not None else 20.0
    return [_order_to_dict(o, cust_to_user.get(o.customer_id), comm_pct) for o in orders]


async def _load_owner_scoped_order(
    db: AsyncSession, user: User, order_id: int
) -> tuple[MarketVendor, MarketOrder]:
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")
    q = await db.execute(select(MarketOrder).where(MarketOrder.id == order_id))
    o = q.scalars().first()
    if not o:
        raise HTTPException(status_code=404, detail="Order not found")
    if o.vendor_id != v.id:
        raise HTTPException(status_code=403, detail="Not your order")
    return v, o


@router.get("/orders/{order_id}")
async def get_order_detail(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v, o = await _load_owner_scoped_order(db, user, order_id)

    items_q = await db.execute(
        select(MarketOrderItem).where(MarketOrderItem.order_id == o.id)
    )
    raw_items = items_q.scalars().all()
    product_ids = [i.product_id for i in raw_items if i.product_id is not None]
    product_by_id: dict[int, Product] = {}
    if product_ids:
        pq = await db.execute(select(Product).where(Product.id.in_(product_ids)))
        product_by_id = {p.id: p for p in pq.scalars().all()}

    cust_user: Optional[User] = None
    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        uq = await db.execute(select(User).where(User.id == c.user_id))
        cust_user = uq.scalars().first()

    line_items = []
    for it in raw_items:
        p = product_by_id.get(it.product_id)
        line_items.append(
            {
                "product_id": it.product_id,
                "name": p.name if p else "Removed product",
                "quantity": it.quantity,
                "price_at_order": float(it.price_at_order or 0),
                "line_total": float(
                    (it.price_at_order or Decimal(0)) * it.quantity
                ),
                "unit": p.unit if p else None,
            }
        )

    comm_pct = float(v.commission_percentage) if v.commission_percentage is not None else 20.0
    base = _order_to_dict(o, cust_user, comm_pct)
    base["items"] = line_items
    return base


async def _refund_wallet_if_needed(
    db: AsyncSession, order: MarketOrder, reason: str
) -> None:
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


@router.post("/orders/{order_id}/accept")
async def accept_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != MarketOrderStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot accept an order in status {o.status.value}",
        )
    o.status = MarketOrderStatus.CONFIRMED
    o.confirmed_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(o)

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "market_order_update",
            {"market_order_id": o.id, "status": o.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Order confirmed",
                body=f"The store is packing your order {o.order_ref}",
                type="market_order_update",
            )
        )
        await db.commit()
    return {"ok": True, "status": o.status.value}


@router.post("/orders/{order_id}/reject")
async def reject_order(
    order_id: int,
    body: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != MarketOrderStatus.PENDING:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot reject an order in status {o.status.value}",
        )
    reason = (body.get("reason") or "Vendor unable to accept").strip()
    o.status = MarketOrderStatus.CANCELLED
    o.cancellation_reason = reason
    await _refund_wallet_if_needed(db, o, reason="vendor rejected")
    await db.commit()
    await db.refresh(o)

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "market_order_update",
            {
                "market_order_id": o.id,
                "status": o.status.value,
                "reason": reason,
            },
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Order rejected",
                body=f"Order {o.order_ref}: {reason}",
                type="market_order_update",
            )
        )
        await db.commit()
    return {"ok": True, "status": o.status.value}


@router.post("/orders/{order_id}/preparing")
async def mark_preparing(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    """CONFIRMED → PROCESSING (vendor is packing)."""
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != MarketOrderStatus.CONFIRMED:
        raise HTTPException(
            status_code=400,
            detail=f"Order must be CONFIRMED to mark packing (current: {o.status.value})",
        )
    o.status = MarketOrderStatus.PROCESSING
    await db.commit()
    await db.refresh(o)

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "market_order_update",
            {"market_order_id": o.id, "status": o.status.value},
        )
    return {"ok": True, "status": o.status.value}


async def _broadcast_market_to_riders(
    db: AsyncSession,
    order: MarketOrder,
    vendor: MarketVendor,
    customer_user: User,
    items_count: int,
    delivery_fee: Decimal,
) -> None:
    async def _alert_vendor(msg: str) -> None:
        """Tell the merchant their broadcast couldn't reach anyone, so they
        know the order is stuck and can retry / contact support."""
        if vendor.owner_id is None:
            return
        await manager.send(
            vendor.owner_id,
            "no_riders_for_market_order",
            {
                "market_order_id": order.id,
                "order_ref": order.order_ref,
                "reason": msg,
            },
        )
        db.add(
            Notification(
                user_id=vendor.owner_id,
                title="No riders available",
                body=f"Order {order.order_ref}: {msg}",
                type="no_riders_for_market_order",
                data=f'{{"market_order_id":{order.id}}}',
            )
        )

    if vendor.lat is None or vendor.lng is None:
        await manager.send(
            customer_user.id,
            "no_drivers_available",
            {"market_order_id": order.id, "order_ref": order.order_ref},
        )
        await _alert_vendor("Vendor location is missing — set lat/lng in profile.")
        return

    nearby = await find_all_nearby_drivers(
        db,
        float(vendor.lat),
        float(vendor.lng),
        vehicle_type=None,
        max_distance_km=float(delivery.vendor_radius_km(vendor.delivery_radius_km)),
    )

    # Driver earnings = delivery fee * (1 - 0.20)
    driver_earnings = float(delivery_fee) * 0.80

    payload = {
        "is_market": True,
        "market_order_id": order.id,
        "order_ref": order.order_ref,
        "vendor_id": vendor.id,
        "vendor_name": vendor.name,
        "vendor_image": vendor.image_url,
        "pickup_address": vendor.address or vendor.name,
        "pickup_lat": float(vendor.lat),
        "pickup_lng": float(vendor.lng),
        "drop_address": order.delivery_address,
        "drop_lat": float(order.delivery_lat) if order.delivery_lat else None,
        "drop_lng": float(order.delivery_lng) if order.delivery_lng else None,
        "items_count": items_count,
        "fare": float(order.final_amount or 0),
        "driver_earnings": driver_earnings,
        "delivery_fee": float(delivery_fee),
        "service_type": "market",
        "payment_method": order.payment_method,
        "customer_name": customer_user.full_name,
        "customer_phone": customer_user.phone_number,
        "expires_in_seconds": 30,
        "instructions": order.instructions,
    }

    for d in nearby:
        await manager.send(d.user_id, "new_ride_request", payload)
        db.add(
            Notification(
                user_id=d.user_id,
                title="New market delivery",
                body=f"{vendor.name} → {order.delivery_address} • Rs.{int(order.final_amount or 0)}",
                type="market_request",
                data=f'{{"market_order_id":{order.id}}}',
            )
        )

    if not nearby:
        await manager.send(
            customer_user.id,
            "no_drivers_available",
            {"market_order_id": order.id, "order_ref": order.order_ref},
        )
        await _alert_vendor(
            "No riders are online within 10km of your stall. Try again in a few minutes."
        )


@router.post("/orders/{order_id}/rebroadcast")
async def rebroadcast_to_riders(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    """Re-fire the rider broadcast for an order that's stuck at
    READY_FOR_PICKUP with no driver_id. Useful when the first broadcast
    found no riders in range (e.g. vendor just opened, or all riders were
    offline at the time). Errors if the order has already been claimed."""
    v, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status != MarketOrderStatus.READY_FOR_PICKUP:
        raise HTTPException(
            status_code=400,
            detail=f"Order must be READY_FOR_PICKUP to rebroadcast (current: {o.status.value})",
        )
    if o.driver_id is not None:
        raise HTTPException(
            status_code=400,
            detail="A rider has already accepted this order.",
        )

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    cust_user: Optional[User] = None
    if c:
        uq = await db.execute(select(User).where(User.id == c.user_id))
        cust_user = uq.scalars().first()

    items_q = await db.execute(
        select(MarketOrderItem).where(MarketOrderItem.order_id == o.id)
    )
    items_count = sum(i.quantity for i in items_q.scalars().all()) or 1

    if cust_user is not None:
        await _broadcast_market_to_riders(
            db, o, v, cust_user, items_count, Decimal(str(o.delivery_fee or 0))
        )
    await db.commit()
    return {"ok": True, "status": o.status.value}


def _resolve_delivery_mode(vendor: MarketVendor, requested: Optional[str]) -> str:
    """Decide how a ready order is delivered, honouring the vendor's flags.

    - only marketplace_delivery → "marketplace"
    - only self_delivery        → "self"
    - both enabled              → the vendor MUST pick (`requested`); this is
      the per-order "deliver it yourself, or find a rider?" prompt.
    """
    requested = (requested or "").strip().lower() or None
    if requested and requested not in ("self", "marketplace"):
        raise HTTPException(status_code=400, detail="delivery_mode must be 'self' or 'marketplace'")

    can_self = bool(vendor.self_delivery)
    # If neither flag is set (legacy vendors), fall back to marketplace so the
    # order can still be delivered.
    can_market = bool(vendor.marketplace_delivery) or not can_self

    if requested == "self" and not can_self:
        raise HTTPException(status_code=400, detail="Self-delivery is not enabled for this store")
    if requested == "marketplace" and not can_market:
        raise HTTPException(status_code=400, detail="Marketplace delivery is not enabled for this store")

    if can_self and can_market:
        if not requested:
            raise HTTPException(
                status_code=400,
                detail="Choose delivery_mode: 'self' (deliver it yourself) or 'marketplace' (find a rider)",
            )
        return requested
    return "self" if can_self else "marketplace"


@router.post("/orders/{order_id}/ready")
async def mark_ready(
    order_id: int,
    body: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    """PROCESSING/CONFIRMED → READY_FOR_PICKUP.

    `delivery_mode` in the body decides dispatch: "marketplace" broadcasts to
    nearby riders (the default flow); "self" means the vendor delivers it and
    no rider broadcast fires. When the store has both options enabled, the
    caller must pass one — this is the per-order self-deliver-or-find-a-rider
    decision.
    """
    v, o = await _load_owner_scoped_order(db, user, order_id)
    if o.status not in (MarketOrderStatus.CONFIRMED, MarketOrderStatus.PROCESSING):
        raise HTTPException(
            status_code=400,
            detail=f"Order must be CONFIRMED or PROCESSING to mark ready (current: {o.status.value})",
        )
    mode = _resolve_delivery_mode(v, body.get("delivery_mode"))

    o.status = MarketOrderStatus.READY_FOR_PICKUP
    o.ready_at = datetime.now(timezone.utc)
    o.delivery_mode = mode
    await db.commit()
    await db.refresh(o)

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    cust_user: Optional[User] = None
    if c:
        uq = await db.execute(select(User).where(User.id == c.user_id))
        cust_user = uq.scalars().first()
        await manager.send(
            c.user_id,
            "market_order_update",
            {"market_order_id": o.id, "status": o.status.value, "delivery_mode": mode},
        )

    if mode == "self":
        # Vendor delivers — no rider broadcast. Vendor advances the order via
        # /out-for-delivery and /delivered.
        if c:
            db.add(
                Notification(
                    user_id=c.user_id,
                    title="Order ready",
                    body=f"{v.name} is delivering your order {o.order_ref}",
                    type="market_order_update",
                )
            )
            await db.commit()
        return {"ok": True, "status": o.status.value, "delivery_mode": mode}

    items_q = await db.execute(
        select(MarketOrderItem).where(MarketOrderItem.order_id == o.id)
    )
    items_count = sum(i.quantity for i in items_q.scalars().all()) or 1

    if cust_user is not None:
        await _broadcast_market_to_riders(
            db, o, v, cust_user, items_count, Decimal(str(o.delivery_fee or 0))
        )
    await db.commit()
    return {"ok": True, "status": o.status.value, "delivery_mode": mode}


async def _notify_market_status(db: AsyncSession, o: MarketOrder, title: str) -> None:
    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c = cq.scalars().first()
    if not c:
        return
    await manager.send(
        c.user_id,
        "market_order_update",
        {"market_order_id": o.id, "status": o.status.value},
    )
    db.add(
        Notification(
            user_id=c.user_id,
            title=title,
            body=f"Order {o.order_ref} is now {o.status.value.replace('_', ' ')}",
            type="market_order_update",
        )
    )


@router.post("/orders/{order_id}/out-for-delivery")
async def vendor_out_for_delivery(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    """Self-delivery only: READY_FOR_PICKUP → OUT_FOR_DELIVERY, driven by the
    vendor instead of a rider."""
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.delivery_mode != "self":
        raise HTTPException(status_code=400, detail="This order is delivered by a marketplace rider")
    if o.status != MarketOrderStatus.READY_FOR_PICKUP:
        raise HTTPException(
            status_code=400,
            detail=f"Order must be READY_FOR_PICKUP (current: {o.status.value})",
        )
    o.status = MarketOrderStatus.OUT_FOR_DELIVERY
    o.picked_up_at = datetime.now(timezone.utc)
    await _notify_market_status(db, o, "Out for delivery")
    await db.commit()
    return {"ok": True, "status": o.status.value}


@router.post("/orders/{order_id}/delivered")
async def vendor_delivered(
    order_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    """Self-delivery only: OUT_FOR_DELIVERY → DELIVERED, driven by the vendor.
    Awards loyalty points, same as the rider-completed path."""
    _, o = await _load_owner_scoped_order(db, user, order_id)
    if o.delivery_mode != "self":
        raise HTTPException(status_code=400, detail="This order is delivered by a marketplace rider")
    if o.status != MarketOrderStatus.OUT_FOR_DELIVERY:
        raise HTTPException(
            status_code=400,
            detail=f"Order must be OUT_FOR_DELIVERY (current: {o.status.value})",
        )
    o.status = MarketOrderStatus.DELIVERED
    o.delivered_at = datetime.now(timezone.utc)
    o.payment_status = "paid"

    cq = await db.execute(select(Customer).where(Customer.id == o.customer_id))
    c_for_pts = cq.scalars().first()
    if c_for_pts and o.final_amount:
        from ...services.loyalty_service import award_points as _award
        await _award(
            db, c_for_pts,
            spend_amount=o.final_amount,
            source_kind="market_order",
            source_id=o.id,
            description=f"Earned on {o.order_ref}",
        )
    await _notify_market_status(db, o, "Delivered")
    await db.commit()
    return {"ok": True, "status": o.status.value}


# ---------------------------------------------------------------------------
# Stats + earnings
# ---------------------------------------------------------------------------


@router.get("/stats/today")
async def stats_today(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")

    now = datetime.now(timezone.utc)
    start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    q = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == v.id,
            MarketOrder.created_at >= start_of_day,
        )
    )
    orders = q.scalars().all()
    delivered = [o for o in orders if o.status == MarketOrderStatus.DELIVERED]
    cancelled = [o for o in orders if o.status == MarketOrderStatus.CANCELLED]
    in_flight = [
        o
        for o in orders
        if o.status
        not in (MarketOrderStatus.DELIVERED, MarketOrderStatus.CANCELLED)
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
        "is_open": bool(v.is_open),
        "is_approved": bool(v.is_active),
    }


@router.get("/earnings")
async def get_earnings(
    period: str = "week",
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("market_owner", "restaurant_owner")),
):
    v = await _get_owned_vendor(db, user)
    if v is None:
        raise HTTPException(status_code=404, detail="Vendor account not found")

    days = 7 if period == "week" else 30 if period == "month" else 7
    now = datetime.now(timezone.utc)
    start = (now - timedelta(days=days - 1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )

    q = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == v.id,
            MarketOrder.created_at >= start,
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
        if o.status == MarketOrderStatus.DELIVERED:
            rev = (o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0))
            bucket["revenue"] = float(Decimal(str(bucket["revenue"])) + rev)
            bucket["delivered"] = bucket["delivered"] + 1
            total_revenue += rev
            total_delivered += 1
        elif o.status == MarketOrderStatus.CANCELLED:
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

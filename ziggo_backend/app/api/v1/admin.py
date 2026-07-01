"""JSON admin API. The HTML admin panel and JSON admin both use these handlers."""
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from ...database import get_db
from ...models import (
    User,
    UserRole,
    Customer,
    Driver,
    DriverStatus,
    Booking,
    BookingStatus,
)
from ...schemas import AdminDriverCreateRequest
from ...services.auth_service import require_role

router = APIRouter()


@router.get("/stats")
async def admin_stats(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    customers = (await db.execute(select(func.count(Customer.id)))).scalar()
    drivers = (await db.execute(select(func.count(Driver.id)))).scalar()
    bookings = (await db.execute(select(func.count(Booking.id)))).scalar()
    online_drivers = (
        await db.execute(select(func.count(Driver.id)).where(Driver.is_online == True))  # noqa: E712
    ).scalar()
    revenue = (
        await db.execute(
            select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
                Booking.status == BookingStatus.COMPLETED
            )
        )
    ).scalar()
    pending_drivers = (
        await db.execute(
            select(func.count(Driver.id)).where(Driver.status == DriverStatus.PENDING)
        )
    ).scalar()

    return {
        "total_customers": customers,
        "total_drivers": drivers,
        "total_bookings": bookings,
        "online_drivers": online_drivers,
        "pending_drivers": pending_drivers,
        "total_revenue": float(revenue or 0),
    }


@router.post("/drivers")
async def create_driver(
    body: AdminDriverCreateRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    """Admin creates a driver manually (e.g., adding a fleet driver)."""
    if body.vehicle_type not in {"bike", "tuk", "car", "van", "truck"}:
        raise HTTPException(status_code=400, detail="Invalid vehicle_type")

    # Phone uniqueness
    existing = (
        await db.execute(select(User).where(User.phone_number == body.phone_number))
    ).scalars().first()
    if existing:
        raise HTTPException(status_code=409, detail="Phone number already registered")

    # Doc uniqueness
    for field, value in [
        (Driver.nic_number, body.nic_number),
        (Driver.license_number, body.license_number),
        (Driver.vehicle_number, body.vehicle_number),
    ]:
        if (await db.execute(select(Driver).where(field == value))).scalars().first():
            raise HTTPException(status_code=409, detail=f"{field.key} '{value}' already in use")

    user = User(
        phone_number=body.phone_number,
        role=UserRole.DRIVER,
        full_name=body.full_name,
        email=body.email,
        is_active=True,
    )
    db.add(user)
    await db.flush()

    now = datetime.now(timezone.utc)
    driver = Driver(
        user_id=user.id,
        nic_number=body.nic_number,
        license_number=body.license_number,
        vehicle_type=body.vehicle_type,
        vehicle_number=body.vehicle_number,
        vehicle_model=body.vehicle_model,
        vehicle_color=body.vehicle_color,
        is_approved=body.auto_approve,
        is_online=False,
        status=DriverStatus.APPROVED if body.auto_approve else DriverStatus.PENDING,
        approved_at=now if body.auto_approve else None,
        acceptance_rate=Decimal("100"),
        today_earnings=Decimal("0"),
        total_earnings=Decimal("0"),
        today_rides=0,
    )
    db.add(driver)
    await db.commit()
    await db.refresh(driver)
    return {"id": driver.id, "user_id": user.id, "is_approved": driver.is_approved}


@router.post("/drivers/{driver_id}/approve")
async def approve_driver(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver not found")
    d.is_approved = True
    d.status = DriverStatus.APPROVED
    d.approved_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}


@router.post("/drivers/{driver_id}/suspend")
async def suspend_driver(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver not found")
    d.is_approved = False
    d.is_online = False
    d.status = DriverStatus.SUSPENDED
    await db.commit()
    return {"ok": True}


@router.get("/referrals")
async def get_all_referrals(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    from ...models import ReferralBonus, User
    from sqlalchemy.orm import joinedload
    q = await db.execute(
        select(ReferralBonus)
        .options(joinedload(ReferralBonus.referrer), joinedload(ReferralBonus.referred))
        .order_by(ReferralBonus.created_at.desc())
        .limit(500)
    )
    bonuses = q.scalars().all()
    results = []
    for b in bonuses:
        results.append({
            "id": b.id,
            "referrer": {
                "id": b.referrer.id if b.referrer else None,
                "name": b.referrer.full_name if b.referrer else None,
                "phone": b.referrer.phone_number if b.referrer else None,
            },
            "referred": {
                "id": b.referred.id if b.referred else None,
                "name": b.referred.full_name if b.referred else None,
                "phone": b.referred.phone_number if b.referred else None,
            },
            "amount": float(b.referrer_amount),
            "status": b.status.value,
            "created_at": b.created_at,
            "paid_at": b.paid_at,
        })
    return results

@router.post("/pay-restaurant/{restaurant_id}")
async def pay_restaurant(
    restaurant_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    from ...models import Restaurant, FoodOrder, FoodOrderStatus, WalletTransaction, Customer
    import secrets
    
    q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = q.scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Restaurant not found")
        
    oq = await db.execute(
        select(FoodOrder).where(
            FoodOrder.restaurant_id == r.id,
            FoodOrder.status == FoodOrderStatus.DELIVERED
        )
    )
    orders = oq.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(r.commission_percentage)) if r.commission_percentage is not None else Decimal("20.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")
    
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == r.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == r.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    if net_owed_to_admin >= Decimal("0"):
        raise HTTPException(status_code=400, detail="Admin does not owe this restaurant anything.")
        
    admin_owes_vendor = -net_owed_to_admin
    
    ref = "SETTLE" + secrets.token_hex(4).upper()
    
    cq = await db.execute(select(Customer).where(Customer.user_id == r.owner_id))
    c = cq.scalars().first()
    if c:
        c.wallet_balance = (c.wallet_balance or Decimal("0")) + admin_owes_vendor
        
    tx = WalletTransaction(
        user_id=r.owner_id,
        amount=admin_owes_vendor,
        type="settlement_payment",
        description="Admin Settlement Payment",
        reference_id=ref,
        balance_after=(c.wallet_balance if c else admin_owes_vendor)
    )
    db.add(tx)
    await db.commit()
    
    return {"ok": True, "paid_amount": float(admin_owes_vendor)}


@router.post("/pay-vendor/{vendor_id}")
async def pay_vendor(
    vendor_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    from ...models import MarketVendor, MarketOrder, MarketOrderStatus, WalletTransaction, Customer
    import secrets
    
    q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = q.scalars().first()
    if not v:
        raise HTTPException(status_code=404, detail="Vendor not found")
        
    oq = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == v.id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = oq.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(v.commission_percentage)) if v.commission_percentage is not None else Decimal("10.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")
    
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == v.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == v.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    if net_owed_to_admin >= Decimal("0"):
        raise HTTPException(status_code=400, detail="Admin does not owe this vendor anything.")
        
    admin_owes_vendor = -net_owed_to_admin
    
    ref = "SETTLE" + secrets.token_hex(4).upper()
    
    cq = await db.execute(select(Customer).where(Customer.user_id == v.owner_id))
    c = cq.scalars().first()
    if c:
        c.wallet_balance = (c.wallet_balance or Decimal("0")) + admin_owes_vendor
        
    tx = WalletTransaction(
        user_id=v.owner_id,
        amount=admin_owes_vendor,
        type="settlement_payment",
        description="Admin Settlement Payment",
        reference_id=ref,
        balance_after=(c.wallet_balance if c else admin_owes_vendor)
    )
    db.add(tx)
    await db.commit()
    
    return {"ok": True, "paid_amount": float(admin_owes_vendor)}

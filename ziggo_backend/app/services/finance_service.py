"""Aggregations powering the admin finance pages.

All queries are intentionally Python-side (after fetching scalar rows) to keep
SQLite-compatible — no DB-engine-specific GROUP BY tricks. Volumes are small
enough that this scales fine for the demo.

Commission model:
  - Rides / parcels    : Booking.platform_fee column (set by fare engine).
                         Driver keeps Booking.driver_earnings.
  - Food orders        : 20% of FoodOrder.delivery_fee  → platform commission
                         80% of FoodOrder.delivery_fee  → rider
                         (FoodOrder.final_amount - delivery_fee) → restaurant
  - Market orders      : same split as food — vendor gets items total, rider
                         gets 80% of delivery_fee, platform keeps the 20%.
"""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import joinedload
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import (
    Booking,
    BookingStatus,
    Customer,
    Driver,
    FoodOrder,
    FoodOrderStatus,
    MarketOrder,
    MarketOrderStatus,
    MarketVendor,
    Restaurant,
    User,
    WalletTransaction,
)

# Platform's share of delivery_fee for food/market. Matches the 20% complement
# of the 80% driver share used in food.py / market_vendor.py broadcasts.
_PLATFORM_DELIVERY_CUT = Decimal("0.20")


def _dec(v) -> Decimal:
    return Decimal(str(v)) if v is not None else Decimal("0")


def _food_split(o) -> tuple[Decimal, Decimal]:
    # Returns (driver_earnings, platform_fee)
    df = _dec(o.delivery_fee)
    item_total = _dec(o.final_amount) - df
    
    comm_pct = o.restaurant.commission_percentage if (o.restaurant and o.restaurant.commission_percentage is not None) else Decimal("20.00")
    
    driver_app_usage_charge = (df * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))
    driver_earn = df - driver_app_usage_charge
    
    restaurant_comm = (item_total * (comm_pct / Decimal("100"))).quantize(Decimal("0.01"))
    platform_cut = driver_app_usage_charge + restaurant_comm
    
    return driver_earn, platform_cut


def _market_split(o) -> tuple[Decimal, Decimal]:
    # Returns (driver_earnings, platform_fee)
    df = _dec(o.delivery_fee)
    item_total = _dec(o.final_amount) - df
    
    comm_pct = o.vendor.commission_percentage if (o.vendor and o.vendor.commission_percentage is not None) else Decimal("20.00")
    
    driver_app_usage_charge = (df * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))
    driver_earn = df - driver_app_usage_charge
    
    vendor_comm = (item_total * (comm_pct / Decimal("100"))).quantize(Decimal("0.01"))
    platform_cut = driver_app_usage_charge + vendor_comm
    
    return driver_earn, platform_cut


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _start_of_today_utc() -> datetime:
    n = _now_utc()
    return n.replace(hour=0, minute=0, second=0, microsecond=0)


def _start_of_week_utc() -> datetime:
    today = _start_of_today_utc()
    return today - timedelta(days=today.weekday())


def _start_of_month_utc() -> datetime:
    n = _now_utc()
    return n.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


# ---------------------------------------------------------------------------
# Platform-wide overview
# ---------------------------------------------------------------------------


async def overview(db: AsyncSession) -> dict:
    """Headline KPIs across every service line."""
    # Rides + flash parcels — split by Booking.is_flash
    bq = await db.execute(select(Booking))
    bookings = bq.scalars().all()

    ride_gmv = Decimal("0")
    flash_gmv = Decimal("0")
    ride_commission = Decimal("0")
    flash_commission = Decimal("0")
    driver_ride_payouts = Decimal("0")
    ride_completed = 0
    flash_completed = 0
    ride_cancelled = 0
    flash_cancelled = 0

    for b in bookings:
        is_flash = bool(getattr(b, "is_flash", False))
        if b.status == BookingStatus.COMPLETED:
            amt = _dec(b.final_amount or b.fare_amount)
            fee = _dec(b.platform_fee)
            drv = _dec(b.driver_earnings)
            if is_flash:
                flash_gmv += amt
                flash_commission += fee
                flash_completed += 1
            else:
                ride_gmv += amt
                ride_commission += fee
                ride_completed += 1
            driver_ride_payouts += drv
        elif b.status == BookingStatus.CANCELLED:
            if is_flash:
                flash_cancelled += 1
            else:
                ride_cancelled += 1

    # Food
    fq = await db.execute(select(FoodOrder).options(joinedload(FoodOrder.restaurant)))
    food_orders = fq.scalars().all()
    food_gmv = Decimal("0")
    food_delivery_revenue = Decimal("0")
    food_commission = Decimal("0")
    food_completed = 0
    food_cancelled = 0
    for o in food_orders:
        if o.status == FoodOrderStatus.DELIVERED:
            food_gmv += _dec(o.final_amount)
            df = _dec(o.delivery_fee)
            food_delivery_revenue += df
            _, platform_cut = _food_split(o)
            food_commission += platform_cut
            food_completed += 1
        elif o.status == FoodOrderStatus.CANCELLED:
            food_cancelled += 1

    # Market
    mq = await db.execute(select(MarketOrder).options(joinedload(MarketOrder.vendor)))
    market_orders = mq.scalars().all()
    market_gmv = Decimal("0")
    market_delivery_revenue = Decimal("0")
    market_commission = Decimal("0")
    market_completed = 0
    market_cancelled = 0
    for o in market_orders:
        if o.status == MarketOrderStatus.DELIVERED:
            market_gmv += _dec(o.final_amount)
            df = _dec(o.delivery_fee)
            market_delivery_revenue += df
            _, platform_cut = _market_split(o)
            market_commission += platform_cut
            market_completed += 1
        elif o.status == MarketOrderStatus.CANCELLED:
            market_cancelled += 1

    # Wallet — total customer credit on the platform's books
    cq = await db.execute(select(Customer))
    customers = cq.scalars().all()
    wallet_held = sum((_dec(c.wallet_balance) for c in customers), Decimal("0"))

    tq = await db.execute(select(WalletTransaction))
    txns = tq.scalars().all()
    topups = sum(
        (_dec(t.amount) for t in txns if (t.type or "").lower() == "credit"),
        Decimal("0"),
    )
    spends = sum(
        (_dec(t.amount) for t in txns if (t.type or "").lower() == "debit"),
        Decimal("0"),
    )

    # Active counts
    drv_q = await db.execute(select(Driver))
    drivers_all = drv_q.scalars().all()
    rest_q = await db.execute(select(Restaurant))
    restaurants_all = rest_q.scalars().all()
    vendor_q = await db.execute(select(MarketVendor))
    vendors_all = vendor_q.scalars().all()

    total_gmv = ride_gmv + flash_gmv + food_gmv + market_gmv
    total_commission = (
        ride_commission + flash_commission + food_commission + market_commission
    )

    return {
        "gmv": {
            "rides": float(ride_gmv),
            "flash": float(flash_gmv),
            "food": float(food_gmv),
            "market": float(market_gmv),
            "total": float(total_gmv),
        },
        "commission": {
            "rides": float(ride_commission),
            "flash": float(flash_commission),
            "food": float(food_commission),
            "market": float(market_commission),
            "total": float(total_commission),
        },
        "driver_payouts_rides": float(driver_ride_payouts),
        "completed": {
            "rides": ride_completed,
            "flash": flash_completed,
            "food": food_completed,
            "market": market_completed,
        },
        "cancelled": {
            "rides": ride_cancelled,
            "flash": flash_cancelled,
            "food": food_cancelled,
            "market": market_cancelled,
        },
        "wallet": {
            "held": float(wallet_held),
            "lifetime_topups": float(topups),
            "lifetime_spend": float(spends),
        },
        "counts": {
            "customers": len(customers),
            "drivers": len(drivers_all),
            "restaurants": len(restaurants_all),
            "vendors": len(vendors_all),
        },
    }


# ---------------------------------------------------------------------------
# Driver financials
# ---------------------------------------------------------------------------


async def driver_finance_table(db: AsyncSession) -> list[dict]:
    """One row per driver — total earnings (rides + food + market delivery
    share), plus today / week / month buckets."""
    today = _start_of_today_utc()
    week = _start_of_week_utc()
    month = _start_of_month_utc()

    dq = await db.execute(select(Driver))
    drivers = dq.scalars().all()
    if not drivers:
        return []

    user_ids = [d.user_id for d in drivers if d.user_id]
    uq = await db.execute(select(User).where(User.id.in_(user_ids))) if user_ids else None
    user_by_id = {u.id: u for u in (uq.scalars().all() if uq else [])}

    # Bookings keyed by driver_id
    bq = await db.execute(select(Booking))
    bookings = bq.scalars().all()
    by_driver_b: dict[int, list[Booking]] = {}
    for b in bookings:
        if b.driver_id is None:
            continue
        by_driver_b.setdefault(b.driver_id, []).append(b)

    # Food orders keyed by driver_id
    fq = await db.execute(select(FoodOrder).options(joinedload(FoodOrder.restaurant)))
    food = fq.scalars().all()
    by_driver_f: dict[int, list[FoodOrder]] = {}
    for o in food:
        if o.driver_id is None:
            continue
        by_driver_f.setdefault(o.driver_id, []).append(o)

    # Market orders keyed by driver_id
    mq = await db.execute(select(MarketOrder).options(joinedload(MarketOrder.vendor)))
    market = mq.scalars().all()
    by_driver_m: dict[int, list[MarketOrder]] = {}
    for o in market:
        if o.driver_id is None:
            continue
        by_driver_m.setdefault(o.driver_id, []).append(o)

    rows: list[dict] = []
    for d in drivers:
        u = user_by_id.get(d.user_id or 0)
        b_list = by_driver_b.get(d.id, [])
        f_list = by_driver_f.get(d.id, [])
        m_list = by_driver_m.get(d.id, [])

        total = Decimal("0")
        today_earn = Decimal("0")
        week_earn = Decimal("0")
        month_earn = Decimal("0")
        ride_count = 0
        food_count = 0
        market_count = 0

        for b in b_list:
            if b.status != BookingStatus.COMPLETED:
                continue
            earn = _dec(b.driver_earnings)
            total += earn
            
            ride_count += 1
            ts = b.completed_at or b.booked_at
            if ts is not None:
                ts_aware = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
                if ts_aware >= today:
                    today_earn += earn
                if ts_aware >= week:
                    week_earn += earn
                if ts_aware >= month:
                    month_earn += earn

        for o in f_list:
            if o.status != FoodOrderStatus.DELIVERED:
                continue
            earn, _ = _food_split(o)
            total += earn
            food_count += 1
            ts = o.delivered_at or o.created_at
            if ts is not None:
                ts_aware = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
                if ts_aware >= today:
                    today_earn += earn
                if ts_aware >= week:
                    week_earn += earn
                if ts_aware >= month:
                    month_earn += earn

        for o in m_list:
            if o.status != MarketOrderStatus.DELIVERED:
                continue
            earn, _ = _market_split(o)
            total += earn
            market_count += 1
            ts = o.delivered_at or o.created_at
            if ts is not None:
                ts_aware = ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
                if ts_aware >= today:
                    today_earn += earn
                if ts_aware >= week:
                    week_earn += earn
                if ts_aware >= month:
                    month_earn += earn

        outstanding = await get_driver_outstanding_commission(db, d.id)
        rows.append({
            "driver_id": d.id,
            "user_id": d.user_id,
            "name": u.full_name if u else None,
            "phone": u.phone_number if u else None,
            "vehicle_type": d.vehicle_type,
            "is_online": bool(d.is_online),
            "status": d.status.value if d.status else None,
            "rating": float(u.rating or 0) if u else 0,
            "total_earnings": float(total),
            "today": float(today_earn),
            "this_week": float(week_earn),
            "this_month": float(month_earn),
            "rides": ride_count,
            "food_deliveries": food_count,
            "market_deliveries": market_count,
            "last_location_update": d.last_location_update.isoformat() if d.last_location_update else None,
            "settlement_amount": float(outstanding),
        })

    rows.sort(key=lambda r: r["total_earnings"], reverse=True)
    return rows


async def driver_finance_detail(db: AsyncSession, driver_id: int) -> Optional[dict]:
    dq = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = dq.scalars().first()
    if d is None:
        return None
    u = None
    if d.user_id:
        uq = await db.execute(select(User).where(User.id == d.user_id))
        u = uq.scalars().first()

    bq = await db.execute(
        select(Booking).where(Booking.driver_id == d.id).order_by(Booking.id.desc()).limit(200)
    )
    bookings = bq.scalars().all()

    fq = await db.execute(
        select(FoodOrder).options(joinedload(FoodOrder.restaurant)).where(FoodOrder.driver_id == d.id).order_by(FoodOrder.id.desc()).limit(200)
    )
    foods = fq.scalars().all()

    mq = await db.execute(
        select(MarketOrder).options(joinedload(MarketOrder.vendor)).where(MarketOrder.driver_id == d.id).order_by(MarketOrder.id.desc()).limit(200)
    )
    markets = mq.scalars().all()

    transactions: list[dict] = []
    for b in bookings:
        transactions.append({
            "kind": "Flash parcel" if getattr(b, "is_flash", False) else "Ride",
            "ref": b.booking_ref,
            "amount": float(_dec(b.driver_earnings)),
            "customer_paid": float(_dec(b.final_amount or b.fare_amount)),
            "platform_fee": float(_dec(b.platform_fee)),
            "status": b.status.value if b.status else "",
            "payment": b.payment_method or "",
            "when": (b.completed_at or b.booked_at).isoformat() if (b.completed_at or b.booked_at) else "",
        })
    for o in foods:
        earn, platform_fee = _food_split(o)
        transactions.append({
            "kind": "Food delivery",
            "ref": o.order_ref,
            "amount": float(earn),
            "customer_paid": float(_dec(o.final_amount)),
            "platform_fee": float(platform_fee),
            "status": o.status.value if o.status else "",
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })
    for o in markets:
        earn, platform_fee = _market_split(o)
        transactions.append({
            "kind": "Market delivery",
            "ref": o.order_ref,
            "amount": float(earn),
            "customer_paid": float(_dec(o.final_amount)),
            "platform_fee": float(platform_fee),
            "status": o.status.value if o.status else "",
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })
    transactions.sort(key=lambda x: x["when"], reverse=True)

    completed_amt = sum(
        (t["amount"] for t in transactions if t["status"] in ("completed", "delivered")),
        0.0,
    )
    platform_paid = sum(
        (t["platform_fee"] for t in transactions if t["status"] in ("completed", "delivered")),
        0.0,
    )

    outstanding = await get_driver_outstanding_commission(db, d.id)

    return {
        "driver": {
            "id": d.id,
            "user_id": d.user_id,
            "name": u.full_name if u else None,
            "phone": u.phone_number if u else None,
            "vehicle_type": d.vehicle_type,
            "vehicle_number": d.vehicle_number,
            "rating": float(u.rating or 0) if u else 0,
            "status": d.status.value if d.status else None,
            "is_online": bool(d.is_online),
            "total_earnings": float(_dec(d.total_earnings)),
            "today_earnings": float(_dec(d.today_earnings)),
            "today_rides": int(d.today_rides or 0),
            "settlement_amount": float(outstanding),
        },
        "totals": {
            "lifetime_earnings": float(completed_amt),
            "lifetime_platform_paid": float(platform_paid),
            "rides": sum(1 for t in transactions if t["kind"] == "Ride" and t["status"] == "completed"),
            "flash": sum(1 for t in transactions if t["kind"] == "Flash parcel" and t["status"] == "completed"),
            "food": sum(1 for t in transactions if t["kind"] == "Food delivery" and t["status"] == "delivered"),
            "market": sum(1 for t in transactions if t["kind"] == "Market delivery" and t["status"] == "delivered"),
        },
        "transactions": transactions[:100],
    }


# ---------------------------------------------------------------------------
# Customer financials
# ---------------------------------------------------------------------------


async def customer_finance_table(db: AsyncSession) -> list[dict]:
    cq = await db.execute(select(Customer))
    customers = cq.scalars().all()
    if not customers:
        return []
    user_ids = [c.user_id for c in customers if c.user_id]
    uq = await db.execute(select(User).where(User.id.in_(user_ids))) if user_ids else None
    user_by_id = {u.id: u for u in (uq.scalars().all() if uq else [])}

    bq = await db.execute(select(Booking))
    bookings = bq.scalars().all()
    by_cust_b: dict[int, list[Booking]] = {}
    for b in bookings:
        if b.customer_id is None:
            continue
        by_cust_b.setdefault(b.customer_id, []).append(b)

    fq = await db.execute(select(FoodOrder).options(joinedload(FoodOrder.restaurant)))
    foods = fq.scalars().all()
    by_cust_f: dict[int, list[FoodOrder]] = {}
    for o in foods:
        if o.customer_id is None:
            continue
        by_cust_f.setdefault(o.customer_id, []).append(o)

    mq = await db.execute(select(MarketOrder).options(joinedload(MarketOrder.vendor)))
    markets = mq.scalars().all()
    by_cust_m: dict[int, list[MarketOrder]] = {}
    for o in markets:
        if o.customer_id is None:
            continue
        by_cust_m.setdefault(o.customer_id, []).append(o)

    rows: list[dict] = []
    for c in customers:
        u = user_by_id.get(c.user_id or 0)
        b_list = by_cust_b.get(c.id, [])
        f_list = by_cust_f.get(c.id, [])
        m_list = by_cust_m.get(c.id, [])

        ride_spend = sum(
            (_dec(b.final_amount or b.fare_amount)
             for b in b_list
             if b.status == BookingStatus.COMPLETED and not getattr(b, "is_flash", False)),
            Decimal("0"),
        )
        flash_spend = sum(
            (_dec(b.final_amount or b.fare_amount)
             for b in b_list
             if b.status == BookingStatus.COMPLETED and getattr(b, "is_flash", False)),
            Decimal("0"),
        )
        food_spend = sum(
            (_dec(o.final_amount) for o in f_list if o.status == FoodOrderStatus.DELIVERED),
            Decimal("0"),
        )
        market_spend = sum(
            (_dec(o.final_amount) for o in m_list if o.status == MarketOrderStatus.DELIVERED),
            Decimal("0"),
        )

        rows.append({
            "customer_id": c.id,
            "user_id": c.user_id,
            "name": u.full_name if u else None,
            "phone": u.phone_number if u else None,
            "wallet_balance": float(_dec(c.wallet_balance)),
            "gold_member": bool(c.gold_member),
            "ride_spend": float(ride_spend),
            "flash_spend": float(flash_spend),
            "food_spend": float(food_spend),
            "market_spend": float(market_spend),
            "total_spend": float(ride_spend + flash_spend + food_spend + market_spend),
            "rides": sum(1 for b in b_list if b.status == BookingStatus.COMPLETED and not getattr(b, "is_flash", False)),
            "flash": sum(1 for b in b_list if b.status == BookingStatus.COMPLETED and getattr(b, "is_flash", False)),
            "food_orders": sum(1 for o in f_list if o.status == FoodOrderStatus.DELIVERED),
            "market_orders": sum(1 for o in m_list if o.status == MarketOrderStatus.DELIVERED),
        })

    rows.sort(key=lambda r: r["total_spend"], reverse=True)
    return rows


async def customer_finance_detail(db: AsyncSession, customer_id: int) -> Optional[dict]:
    cq = await db.execute(select(Customer).where(Customer.id == customer_id))
    c = cq.scalars().first()
    if c is None:
        return None
    u = None
    if c.user_id:
        uq = await db.execute(select(User).where(User.id == c.user_id))
        u = uq.scalars().first()

    # Wallet transactions
    tq = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.user_id == c.user_id)
        .order_by(WalletTransaction.id.desc())
        .limit(100)
    )
    txns = tq.scalars().all()

    bq = await db.execute(
        select(Booking).where(Booking.customer_id == c.id).order_by(Booking.id.desc()).limit(100)
    )
    bookings = bq.scalars().all()
    fq = await db.execute(
        select(FoodOrder).where(FoodOrder.customer_id == c.id).order_by(FoodOrder.id.desc()).limit(100)
    )
    foods = fq.scalars().all()
    mq = await db.execute(
        select(MarketOrder).where(MarketOrder.customer_id == c.id).order_by(MarketOrder.id.desc()).limit(100)
    )
    markets = mq.scalars().all()

    timeline: list[dict] = []
    for b in bookings:
        timeline.append({
            "kind": "Flash parcel" if getattr(b, "is_flash", False) else "Ride",
            "ref": b.booking_ref,
            "amount": float(_dec(b.final_amount or b.fare_amount)),
            "status": b.status.value if b.status else "",
            "payment": b.payment_method or "",
            "when": (b.completed_at or b.booked_at).isoformat() if (b.completed_at or b.booked_at) else "",
        })
    for o in foods:
        timeline.append({
            "kind": "Food",
            "ref": o.order_ref,
            "amount": float(_dec(o.final_amount)),
            "status": o.status.value if o.status else "",
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })
    for o in markets:
        timeline.append({
            "kind": "Market",
            "ref": o.order_ref,
            "amount": float(_dec(o.final_amount)),
            "status": o.status.value if o.status else "",
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })
    timeline.sort(key=lambda x: x["when"], reverse=True)

    return {
        "customer": {
            "id": c.id,
            "user_id": c.user_id,
            "name": u.full_name if u else None,
            "phone": u.phone_number if u else None,
            "wallet_balance": float(_dec(c.wallet_balance)),
            "gold_member": bool(c.gold_member),
        },
        "wallet_transactions": [
            {
                "id": t.id,
                "type": t.type,
                "amount": float(_dec(t.amount)),
                "balance_after": float(_dec(t.balance_after)),
                "description": t.description,
                "reference_id": t.reference_id,
                "when": t.created_at.isoformat() if t.created_at else "",
            }
            for t in txns
        ],
        "orders": timeline[:200],
        "totals": {
            "total_orders": len(timeline),
            "total_spend": sum(o["amount"] for o in timeline if o["status"] in ("completed", "delivered")),
        },
    }


# ---------------------------------------------------------------------------
# Restaurant financials
# ---------------------------------------------------------------------------


async def restaurant_finance_table(db: AsyncSession) -> list[dict]:
    rq = await db.execute(select(Restaurant))
    restaurants = rq.scalars().all()
    if not restaurants:
        return []

    fq = await db.execute(select(FoodOrder).options(joinedload(FoodOrder.restaurant)))
    foods = fq.scalars().all()
    by_r: dict[int, list[FoodOrder]] = {}
    for o in foods:
        if o.restaurant_id is None:
            continue
        by_r.setdefault(o.restaurant_id, []).append(o)

    rows: list[dict] = []
    for r in restaurants:
        f_list = by_r.get(r.id, [])
        items_revenue = Decimal("0")
        platform_commission = Decimal("0")
        delivery_fee_total = Decimal("0")
        delivered = 0
        cancelled = 0
        pending = 0
        for o in f_list:
            if o.status == FoodOrderStatus.DELIVERED:
                items_revenue += _dec(o.final_amount) - _dec(o.delivery_fee)
                delivery_fee_total += _dec(o.delivery_fee)
                _, platform_cut = _food_split(o)
                platform_commission += platform_cut
                delivered += 1
            elif o.status == FoodOrderStatus.CANCELLED:
                cancelled += 1
            else:
                pending += 1

        rows.append({
            "restaurant_id": r.id,
            "name": r.name,
            "cuisine": r.cuisine,
            "is_active": bool(r.is_active),
            "is_open": bool(r.is_open) if r.is_open is not None else True,
            "owner_id": r.owner_id,
            "items_revenue": float(items_revenue),
            "delivery_fees_collected": float(delivery_fee_total),
            "platform_commission": float(platform_commission),
            "delivered": delivered,
            "cancelled": cancelled,
            "pending_or_active": pending,
        })
    rows.sort(key=lambda r: r["items_revenue"], reverse=True)
    return rows


async def restaurant_finance_detail(db: AsyncSession, restaurant_id: int) -> Optional[dict]:
    rq = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = rq.scalars().first()
    if r is None:
        return None
    owner = None
    if r.owner_id:
        oq = await db.execute(select(User).where(User.id == r.owner_id))
        owner = oq.scalars().first()

    fq = await db.execute(
        select(FoodOrder).options(joinedload(FoodOrder.restaurant))
        .where(FoodOrder.restaurant_id == r.id)
        .order_by(FoodOrder.id.desc())
        .limit(200)
    )
    foods = fq.scalars().all()

    items_revenue = Decimal("0")
    delivery_fee_total = Decimal("0")
    platform_commission = Decimal("0")
    delivered_count = 0
    cancelled_count = 0

    orders_view: list[dict] = []
    for o in foods:
        df = _dec(o.delivery_fee)
        _, cm = _food_split(o)
        items = _dec(o.final_amount) - df
        if o.status == FoodOrderStatus.DELIVERED:
            items_revenue += items
            delivery_fee_total += df
            platform_commission += cm
            delivered_count += 1
        elif o.status == FoodOrderStatus.CANCELLED:
            cancelled_count += 1

        orders_view.append({
            "ref": o.order_ref,
            "status": o.status.value if o.status else "",
            "items_total": float(items),
            "delivery_fee": float(df),
            "platform_cut": float(cm),
            "vendor_net": float(items),
            "customer_paid": float(_dec(o.final_amount)),
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })

    return {
        "restaurant": {
            "id": r.id,
            "name": r.name,
            "cuisine": r.cuisine,
            "address": r.address,
            "phone": r.phone_number,
            "is_active": bool(r.is_active),
            "is_open": bool(r.is_open) if r.is_open is not None else True,
            "rating": float(_dec(r.rating)),
            "delivery_fee": float(_dec(r.delivery_fee)),
            "owner_name": owner.full_name if owner else None,
            "owner_phone": owner.phone_number if owner else None,
        },
        "totals": {
            "items_revenue": float(items_revenue),
            "delivery_fees_collected": float(delivery_fee_total),
            "platform_commission": float(platform_commission),
            "delivered": delivered_count,
            "cancelled": cancelled_count,
        },
        "orders": orders_view[:200],
    }


# ---------------------------------------------------------------------------
# Market vendor financials
# ---------------------------------------------------------------------------


async def vendor_finance_table(db: AsyncSession) -> list[dict]:
    vq = await db.execute(select(MarketVendor))
    vendors = vq.scalars().all()
    if not vendors:
        return []

    mq = await db.execute(select(MarketOrder).options(joinedload(MarketOrder.vendor)))
    orders = mq.scalars().all()
    by_v: dict[int, list[MarketOrder]] = {}
    for o in orders:
        if o.vendor_id is None:
            continue
        by_v.setdefault(o.vendor_id, []).append(o)

    rows: list[dict] = []
    for v in vendors:
        olist = by_v.get(v.id, [])
        items_revenue = Decimal("0")
        delivery_fee_total = Decimal("0")
        platform_commission = Decimal("0")
        delivered = 0
        cancelled = 0
        pending = 0
        for o in olist:
            if o.status == MarketOrderStatus.DELIVERED:
                items_revenue += _dec(o.final_amount) - _dec(o.delivery_fee)
                delivery_fee_total += _dec(o.delivery_fee)
                _, platform_cut = _food_split(o)
                platform_commission += platform_cut
                delivered += 1
            elif o.status == MarketOrderStatus.CANCELLED:
                cancelled += 1
            else:
                pending += 1

        rows.append({
            "vendor_id": v.id,
            "name": v.name,
            "category": v.category,
            "is_active": bool(v.is_active),
            "is_open": bool(v.is_open) if v.is_open is not None else True,
            "owner_id": v.owner_id,
            "items_revenue": float(items_revenue),
            "delivery_fees_collected": float(delivery_fee_total),
            "platform_commission": float(platform_commission),
            "delivered": delivered,
            "cancelled": cancelled,
            "pending_or_active": pending,
        })
    rows.sort(key=lambda r: r["items_revenue"], reverse=True)
    return rows


async def vendor_finance_detail(db: AsyncSession, vendor_id: int) -> Optional[dict]:
    vq = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = vq.scalars().first()
    if v is None:
        return None
    owner = None
    if v.owner_id:
        oq = await db.execute(select(User).where(User.id == v.owner_id))
        owner = oq.scalars().first()

    mq = await db.execute(
        select(MarketOrder).options(joinedload(MarketOrder.vendor))
        .where(MarketOrder.vendor_id == v.id)
        .order_by(MarketOrder.id.desc())
        .limit(200)
    )
    orders = mq.scalars().all()

    items_revenue = Decimal("0")
    delivery_fee_total = Decimal("0")
    platform_commission = Decimal("0")
    delivered_count = 0
    cancelled_count = 0

    orders_view: list[dict] = []
    for o in orders:
        df = _dec(o.delivery_fee)
        _, cm = _food_split(o)
        items = _dec(o.final_amount) - df
        if o.status == MarketOrderStatus.DELIVERED:
            items_revenue += items
            delivery_fee_total += df
            platform_commission += cm
            delivered_count += 1
        elif o.status == MarketOrderStatus.CANCELLED:
            cancelled_count += 1

        orders_view.append({
            "ref": o.order_ref,
            "status": o.status.value if o.status else "",
            "items_total": float(items),
            "delivery_fee": float(df),
            "platform_cut": float(cm),
            "vendor_net": float(items),
            "customer_paid": float(_dec(o.final_amount)),
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })

    return {
        "vendor": {
            "id": v.id,
            "name": v.name,
            "category": v.category,
            "address": v.address,
            "phone": v.phone_number,
            "is_active": bool(v.is_active),
            "is_open": bool(v.is_open) if v.is_open is not None else True,
            "rating": float(_dec(v.rating)),
            "delivery_fee": float(_dec(v.delivery_fee)),
            "owner_name": owner.full_name if owner else None,
            "owner_phone": owner.phone_number if owner else None,
        },
        "totals": {
            "items_revenue": float(items_revenue),
            "delivery_fees_collected": float(delivery_fee_total),
            "platform_commission": float(platform_commission),
            "delivered": delivered_count,
            "cancelled": cancelled_count,
        },
        "orders": orders_view[:200],
    }


async def get_withdrawals_data(db: AsyncSession, page: int = 1, page_size: int = 10) -> dict:
    from app.models import DriverPayout
    # Fetch all driver payouts grouped by driver
    pq = await db.execute(select(DriverPayout))
    payouts = pq.scalars().all()
    payout_by_driver: dict[int, Decimal] = {}
    for p in payouts:
        payout_by_driver[p.driver_id] = payout_by_driver.get(p.driver_id, Decimal("0")) + _dec(p.amount)

    # Use the existing driver_finance_table code to calculate total earnings dynamically
    all_driver_rows = await driver_finance_table(db)
    
    rows = []
    total_pending_all = Decimal("0")
    
    for r in all_driver_rows:
        drv_id = r["driver_id"]
        earned = Decimal(str(r["total_earnings"]))
        paid = payout_by_driver.get(drv_id, Decimal("0"))
        pending = earned - paid
        if pending < 0:
            pending = Decimal("0")
        total_pending_all += pending
        
        rows.append({
            "driver_id": drv_id,
            "name": r["name"] or f"Driver #{drv_id}",
            "phone": r["phone"] or "",
            "vehicle_type": r["vehicle_type"] or "",
            "earned": float(earned),
            "paid": float(paid),
            "pending": float(pending),
            "settlement_amount": r.get("settlement_amount", 0.0),
        })

    # Pagination
    total_drivers = len(rows)
    total_pages = max(1, (total_drivers + page_size - 1) // page_size)
    page = max(1, min(page, total_pages))
    
    start_idx = (page - 1) * page_size
    end_idx = min(start_idx + page_size, total_drivers)
    
    paginated_rows = rows[start_idx:end_idx]
    
    # Recent payouts history
    from sqlalchemy.orm import selectinload
    hist_q = await db.execute(
        select(DriverPayout)
        .options(selectinload(DriverPayout.user))
        .order_by(DriverPayout.created_at.desc())
        .limit(50)
    )
    history = hist_q.scalars().all()

    page_range = list(range(1, total_pages + 1))
    
    return {
        "total_pending": float(total_pending_all),
        "rows": paginated_rows,
        "history": history,
        "total_pages": total_pages,
        "start_idx": start_idx + 1 if total_drivers > 0 else 0,
        "end_idx": end_idx,
        "total_drivers": total_drivers,
        "page": page,
        "page_range": page_range,
    }


async def execute_driver_payout(db: AsyncSession, driver_id: int, amount: Decimal, note: str) -> None:
    from app.models import DriverPayout, Driver
    dq = await db.execute(select(Driver).where(Driver.id == driver_id))
    driver = dq.scalars().first()
    if not driver:
        raise ValueError("Driver not found")
        
    payout = DriverPayout(
        driver_id=driver.id,
        user_id=driver.user_id,
        amount=amount,
        description=note,
    )
    db.add(payout)
    await db.commit()


async def get_driver_outstanding_commission(db: AsyncSession, driver_id: int) -> Decimal:
    """Calculate unpaid outstanding commission driver owes platform from cash bookings/orders."""
    from app.models import Booking, BookingStatus, FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus, DriverPayout
    
    # 1. Platform fee from completed cash bookings
    bq = await db.execute(
        select(Booking).where(
            Booking.driver_id == driver_id,
            Booking.status == BookingStatus.COMPLETED,
            Booking.payment_method == "cash"
        )
    )
    cash_bookings = bq.scalars().all()
    cash_booking_commission = sum((_dec(b.platform_fee) for b in cash_bookings), Decimal("0"))
    
    # 2. Platform fee from completed cash food orders
    fq = await db.execute(
        select(FoodOrder).options(joinedload(FoodOrder.restaurant)).where(
            FoodOrder.driver_id == driver_id,
            FoodOrder.status == FoodOrderStatus.DELIVERED,
            FoodOrder.payment_method == "cash"
        )
    )
    cash_foods = fq.scalars().all()
    cash_food_commission = Decimal("0")
    for o in cash_foods:
        df = _dec(o.delivery_fee)
        _, cut = _food_split(o)
        cash_food_commission += cut
        
    # 3. Platform fee from completed cash market orders
    mq = await db.execute(
        select(MarketOrder).options(joinedload(MarketOrder.vendor)).where(
            MarketOrder.driver_id == driver_id,
            MarketOrder.status == MarketOrderStatus.DELIVERED,
            MarketOrder.payment_method == "cash"
        )
    )
    cash_markets = mq.scalars().all()
    cash_market_commission = Decimal("0")
    for o in cash_markets:
        df = _dec(o.delivery_fee)
        _, cut = _market_split(o)
        cash_market_commission += cut
        
    total_owed = cash_booking_commission + cash_food_commission + cash_market_commission
    
    # 4. Total settled by driver (DriverPayout rows with settlement descriptions)
    pq = await db.execute(
        select(DriverPayout).where(
            DriverPayout.driver_id == driver_id
        )
    )
    payouts = pq.scalars().all()
    total_settled = Decimal("0")
    for p in payouts:
        desc = (p.description or "").lower()
        if "commission settled" in desc or "commission settlement" in desc:
            total_settled += _dec(p.amount)
            
    outstanding = total_owed - total_settled
    return max(Decimal("0"), outstanding)


async def check_and_deactivate_driver(db: AsyncSession, driver_id: int) -> bool:
    """Check driver's outstanding commission against system settings.
    If they exceed the limit, change status to SUSPENDED and turn offline.
    Otherwise, if they were SUSPENDED and are now below the limit, restore status to APPROVED.
    """
    from app.models import Driver, DriverStatus, SystemSettings
    
    dq = await db.execute(select(Driver).where(Driver.id == driver_id))
    drv = dq.scalars().first()
    if not drv:
        return False
        
    outstanding = await get_driver_outstanding_commission(db, driver_id)
    
    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    max_limit = Decimal("1000.00")
    if ss and ss.max_settle_amount is not None:
        max_limit = ss.max_settle_amount
        
    if outstanding > max_limit:
        if drv.status != DriverStatus.SUSPENDED:
            drv.status = DriverStatus.SUSPENDED
            drv.is_online = False
            await db.commit()
            
            # Publish to ws so admin map updates instantly
            from app.services.ws_manager import manager
            await manager.publish("admin_live", "driver_status_update", {
                "id": drv.id,
                "is_online": False,
                "lat": float(drv.current_lat) if drv.current_lat is not None else None,
                "lng": float(drv.current_lng) if drv.current_lng is not None else None,
            })
            print(f"[deactivation] Driver {driver_id} suspended. Outstanding: {outstanding}, Limit: {max_limit}")
        return True
    else:
        if drv.status == DriverStatus.SUSPENDED:
            drv.status = DriverStatus.APPROVED
            await db.commit()
            print(f"[reactivation] Driver {driver_id} reactivated. Outstanding: {outstanding}")
        return False


async def get_driver_earnings_summary(db: AsyncSession, driver_id: int) -> dict:
    """Lifetime money split for a single driver, for the in-app Earnings page.
    Modified to return current outstanding commission under 'commission'."""
    from app.models import DriverPayout

    bq = await db.execute(
        select(Booking).where(
            Booking.driver_id == driver_id,
            Booking.status == BookingStatus.COMPLETED,
        )
    )
    bookings = bq.scalars().all()

    # Classify bookings
    passenger_bookings = [b for b in bookings if not b.is_flash and not b.is_courier]
    delivery_bookings = [b for b in bookings if b.is_flash or b.is_courier]

    ride_collected = sum((_dec(b.final_amount or b.fare_amount) for b in passenger_bookings), Decimal("0"))
    ride_earnings = sum((_dec(b.driver_earnings) for b in passenger_bookings), Decimal("0"))
    ride_count = len(passenger_bookings)

    fq = await db.execute(
        select(FoodOrder).options(joinedload(FoodOrder.restaurant)).where(
            FoodOrder.driver_id == driver_id,
            FoodOrder.status == FoodOrderStatus.DELIVERED,
        )
    )
    foods = fq.scalars().all()
    mq = await db.execute(
        select(MarketOrder).options(joinedload(MarketOrder.vendor)).where(
            MarketOrder.driver_id == driver_id,
            MarketOrder.status == MarketOrderStatus.DELIVERED,
        )
    )
    markets = mq.scalars().all()

    delivery_collected = sum((_dec(b.final_amount or b.fare_amount) for b in delivery_bookings), Decimal("0"))
    delivery_earnings = sum((_dec(b.driver_earnings) for b in delivery_bookings), Decimal("0"))

    for o in [*foods, *markets]:
        df = _dec(o.delivery_fee)
        if hasattr(o, "restaurant_id"):
            earn, _ = _food_split(o)
        else:
            earn, _ = _market_split(o)
        delivery_collected += df
        delivery_earnings += earn
    delivery_count = len(delivery_bookings) + len(foods) + len(markets)

    collected = ride_collected + delivery_collected
    earnings = ride_earnings + delivery_earnings

    pq = await db.execute(select(DriverPayout).where(DriverPayout.driver_id == driver_id))
    paid = sum((_dec(p.amount) for p in pq.scalars().all()), Decimal("0"))
    pending = earnings - paid
    if pending < 0:
        pending = Decimal("0")

    outstanding = await get_driver_outstanding_commission(db, driver_id)

    from app.models import SystemSettings
    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    max_limit = 1000.0
    if ss and ss.max_settle_amount is not None:
        max_limit = float(ss.max_settle_amount)

    return {
        "collected": float(collected),
        "commission": float(collected - earnings),
        "outstanding_commission": float(outstanding),
        "earnings": float(earnings),
        "paid": float(paid),
        "pending": float(pending),
        "trips": ride_count + delivery_count,
        "rides": ride_count,
        "deliveries": delivery_count,
        "max_settle_amount": max_limit,
    }


async def get_driver_payout_stats(db: AsyncSession, driver_id: int) -> dict:
    from app.models import DriverPayout, Booking, FoodOrder, MarketOrder
    bq = await db.execute(
        select(Booking)
        .where(Booking.driver_id == driver_id, Booking.status == BookingStatus.COMPLETED)
    )
    ride_earn = sum((_dec(b.driver_earnings) for b in bq.scalars().all()), Decimal("0"))

    fq = await db.execute(
        select(FoodOrder).options(joinedload(FoodOrder.restaurant))
        .where(FoodOrder.driver_id == driver_id, FoodOrder.status == FoodOrderStatus.DELIVERED)
    )
    food_earn = sum((_food_split(o)[0] for o in fq.scalars().all()), Decimal("0"))

    mq = await db.execute(
        select(MarketOrder).options(joinedload(MarketOrder.vendor))
        .where(MarketOrder.driver_id == driver_id, MarketOrder.status == MarketOrderStatus.DELIVERED)
    )
    market_earn = sum((_market_split(o)[0] for o in mq.scalars().all()), Decimal("0"))

    total_earned = ride_earn + food_earn + market_earn

    pq = await db.execute(select(DriverPayout).where(DriverPayout.driver_id == driver_id))
    total_paid = sum((_dec(p.amount) for p in pq.scalars().all()), Decimal("0"))

    pending = total_earned - total_paid
    if pending < 0:
        pending = Decimal("0")

    return {
        "earned": float(total_earned),
        "paid": float(total_paid),
        "pending": float(pending),
    }

async def evaluate_and_award_driver_incentives(db: AsyncSession, driver_id: int) -> None:
    """Evaluate active DriverIncentives and award the driver if they exactly hit the target."""
    from app.models import Driver, DriverIncentive, DriverPayout, Notification, Booking, BookingStatus, FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus
    from datetime import datetime, timedelta, timezone
    from sqlalchemy import select, func
    from decimal import Decimal

    dq = await db.execute(select(Driver).where(Driver.id == driver_id))
    drv = dq.scalars().first()
    if not drv:
        return
        
    iq = await db.execute(select(DriverIncentive).where(DriverIncentive.is_active == True))
    incentives = iq.scalars().all()
    if not incentives:
        return

    colombo_tz = timezone(timedelta(hours=5, minutes=30))
    now_colombo = datetime.now(colombo_tz)
    midnight_colombo = datetime(now_colombo.year, now_colombo.month, now_colombo.day, tzinfo=colombo_tz)

    for inc in incentives:
        limit_days = inc.limit_days or 1
        if limit_days <= 1:
            rides_completed = drv.today_rides or 0
        else:
            start_date_colombo = midnight_colombo - timedelta(days=limit_days - 1)
            start_date_utc = start_date_colombo.astimezone(timezone.utc)
            
            b_count = (await db.execute(select(func.count(Booking.id)).where(Booking.driver_id == drv.id, Booking.status == BookingStatus.COMPLETED, Booking.completed_at >= start_date_utc))).scalar() or 0
            f_count = (await db.execute(select(func.count(FoodOrder.id)).where(FoodOrder.driver_id == drv.id, FoodOrder.status == FoodOrderStatus.DELIVERED, FoodOrder.delivered_at >= start_date_utc))).scalar() or 0
            m_count = (await db.execute(select(func.count(MarketOrder.id)).where(MarketOrder.driver_id == drv.id, MarketOrder.status == MarketOrderStatus.DELIVERED, MarketOrder.delivered_at >= start_date_utc))).scalar() or 0
            
            rides_completed = b_count + f_count + m_count
            
        # ONLY award if they exactly hit the requirement on this ride
        if rides_completed == inc.trips_required:
            amt = Decimal(str(inc.reward_amount or 0))
            if amt > 0:
                drv.total_earnings += amt
                drv.today_earnings += amt
                db.add(DriverPayout(
                    driver_id=drv.id,
                    user_id=drv.user_id,
                    amount=amt,
                    description=f"{inc.title} Bonus ({inc.trips_required} trips completed)"
                ))
                db.add(Notification(
                    user_id=drv.user_id,
                    title="Incentive Unlocked!",
                    body=f"Congratulations! You completed {inc.trips_required} trips and earned a bonus of Rs.{amt:,.2f}.",
                    type="payment"
                ))

async def get_restaurant_outstanding_commission(db: AsyncSession, restaurant_id: int) -> Decimal:
    from app.models import FoodOrder, FoodOrderStatus, WalletTransaction, Restaurant
    
    rq = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = rq.scalars().first()
    if not r or not r.owner_id:
        return Decimal("0")

    q = await db.execute(
        select(FoodOrder).where(
            FoodOrder.restaurant_id == restaurant_id,
            FoodOrder.status == FoodOrderStatus.DELIVERED
        )
    )
    orders = q.scalars().all()
    
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
    
    return max(Decimal("0"), net_owed_to_admin)


async def check_and_deactivate_restaurant(db: AsyncSession, restaurant_id: int) -> bool:
    from app.models import Restaurant
    
    rq = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = rq.scalars().first()
    if not r:
        return False
        
    outstanding = await get_restaurant_outstanding_commission(db, restaurant_id)
    max_limit = r.max_settle_amount if r.max_settle_amount is not None else Decimal("1000.00")
        
    if outstanding > max_limit:
        if r.is_active:
            r.is_active = False
            await db.commit()
            print(f"[deactivation] Restaurant {restaurant_id} deactivated. Outstanding: {outstanding}, Limit: {max_limit}")
        return True
    else:
        if not r.is_active:
            r.is_active = True
            await db.commit()
            print(f"[reactivation] Restaurant {restaurant_id} reactivated. Outstanding: {outstanding}")
        return False


async def get_market_outstanding_commission(db, vendor_id: int):
    from sqlalchemy import select
    from decimal import Decimal
    from app.models import MarketOrder, MarketOrderStatus, WalletTransaction, MarketVendor
    
    vq = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = vq.scalars().first()
    if not v or not v.owner_id:
        return Decimal("0")

    q = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == vendor_id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = q.scalars().all()
    
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
    
    return max(Decimal("0"), net_owed_to_admin)


async def check_and_deactivate_market_vendor(db, vendor_id: int) -> bool:
    from sqlalchemy import select
    from decimal import Decimal
    from app.models import MarketVendor
    
    vq = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = vq.scalars().first()
    if not v:
        return False
        
    outstanding = await get_market_outstanding_commission(db, vendor_id)
    max_limit = v.max_settle_amount if v.max_settle_amount is not None else Decimal("1000.00")
        
    if outstanding > max_limit:
        if v.is_active:
            v.is_active = False
            await db.commit()
            print(f"[deactivation] MarketVendor {vendor_id} deactivated. Outstanding: {outstanding}, Limit: {max_limit}")
        return True
    else:
        if not v.is_active:
            v.is_active = True
            await db.commit()
            print(f"[reactivation] MarketVendor {vendor_id} reactivated. Outstanding: {outstanding}")
        return False

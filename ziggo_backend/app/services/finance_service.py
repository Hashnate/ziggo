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
            amt = _dec(b.final_amount or b.total_amount)
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
    fq = await db.execute(select(FoodOrder))
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
            food_commission += (df * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))
            food_completed += 1
        elif o.status == FoodOrderStatus.CANCELLED:
            food_cancelled += 1

    # Market
    mq = await db.execute(select(MarketOrder))
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
            market_commission += (df * _PLATFORM_DELIVERY_CUT).quantize(
                Decimal("0.01")
            )
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
    fq = await db.execute(select(FoodOrder))
    food = fq.scalars().all()
    by_driver_f: dict[int, list[FoodOrder]] = {}
    for o in food:
        if o.driver_id is None:
            continue
        by_driver_f.setdefault(o.driver_id, []).append(o)

    # Market orders keyed by driver_id
    mq = await db.execute(select(MarketOrder))
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
            ts = b.completed_at or b.created_at
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
            earn = (_dec(o.delivery_fee) * (Decimal("1") - _PLATFORM_DELIVERY_CUT)).quantize(Decimal("0.01"))
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
            earn = (_dec(o.delivery_fee) * (Decimal("1") - _PLATFORM_DELIVERY_CUT)).quantize(Decimal("0.01"))
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
        select(FoodOrder).where(FoodOrder.driver_id == d.id).order_by(FoodOrder.id.desc()).limit(200)
    )
    foods = fq.scalars().all()

    mq = await db.execute(
        select(MarketOrder).where(MarketOrder.driver_id == d.id).order_by(MarketOrder.id.desc()).limit(200)
    )
    markets = mq.scalars().all()

    transactions: list[dict] = []
    for b in bookings:
        transactions.append({
            "kind": "Flash parcel" if getattr(b, "is_flash", False) else "Ride",
            "ref": b.booking_ref,
            "amount": float(_dec(b.driver_earnings)),
            "customer_paid": float(_dec(b.final_amount or b.total_amount)),
            "platform_fee": float(_dec(b.platform_fee)),
            "status": b.status.value if b.status else "",
            "payment": b.payment_method or "",
            "when": (b.completed_at or b.created_at).isoformat() if (b.completed_at or b.created_at) else "",
        })
    for o in foods:
        earn = (_dec(o.delivery_fee) * (Decimal("1") - _PLATFORM_DELIVERY_CUT)).quantize(Decimal("0.01"))
        transactions.append({
            "kind": "Food delivery",
            "ref": o.order_ref,
            "amount": float(earn),
            "customer_paid": float(_dec(o.final_amount)),
            "platform_fee": float((_dec(o.delivery_fee) * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))),
            "status": o.status.value if o.status else "",
            "payment": o.payment_method or "",
            "when": (o.delivered_at or o.created_at).isoformat() if (o.delivered_at or o.created_at) else "",
        })
    for o in markets:
        earn = (_dec(o.delivery_fee) * (Decimal("1") - _PLATFORM_DELIVERY_CUT)).quantize(Decimal("0.01"))
        transactions.append({
            "kind": "Market delivery",
            "ref": o.order_ref,
            "amount": float(earn),
            "customer_paid": float(_dec(o.final_amount)),
            "platform_fee": float((_dec(o.delivery_fee) * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))),
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

    fq = await db.execute(select(FoodOrder))
    foods = fq.scalars().all()
    by_cust_f: dict[int, list[FoodOrder]] = {}
    for o in foods:
        if o.customer_id is None:
            continue
        by_cust_f.setdefault(o.customer_id, []).append(o)

    mq = await db.execute(select(MarketOrder))
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
            (_dec(b.final_amount or b.total_amount)
             for b in b_list
             if b.status == BookingStatus.COMPLETED and not getattr(b, "is_flash", False)),
            Decimal("0"),
        )
        flash_spend = sum(
            (_dec(b.final_amount or b.total_amount)
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
            "amount": float(_dec(b.final_amount or b.total_amount)),
            "status": b.status.value if b.status else "",
            "payment": b.payment_method or "",
            "when": (b.completed_at or b.created_at).isoformat() if (b.completed_at or b.created_at) else "",
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

    fq = await db.execute(select(FoodOrder))
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
                platform_commission += (
                    _dec(o.delivery_fee) * _PLATFORM_DELIVERY_CUT
                ).quantize(Decimal("0.01"))
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
        select(FoodOrder)
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
        cm = (df * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))
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

    mq = await db.execute(select(MarketOrder))
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
                platform_commission += (
                    _dec(o.delivery_fee) * _PLATFORM_DELIVERY_CUT
                ).quantize(Decimal("0.01"))
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
        select(MarketOrder)
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
        cm = (df * _PLATFORM_DELIVERY_CUT).quantize(Decimal("0.01"))
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

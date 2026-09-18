"""Background task that auto-cancels stale PENDING food orders.

When a customer places a food order the order sits in PENDING until the
restaurant taps Accept. If the restaurant never responds, the customer
shouldn't be stuck on a "waiting" screen forever — so we sweep every 30 s and
cancel anything older than `STALE_AFTER_SECONDS`. Wallet payments are
refunded; cash orders are simply marked CANCELLED.
"""
import asyncio
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from sqlalchemy import select, update, func

from ..database import AsyncSessionLocal
from ..models import (
    Booking,
    BookingStatus,
    Customer,
    FoodOrder,
    FoodOrderStatus,
    Notification,
    WalletTransaction,
    Driver,
    SystemSettings,
)
from .ws_manager import manager
from .loyalty_service import refund_redeemed_points

# Customer-visible timeout. 5 minutes matches the locked design decision.
STALE_AFTER_SECONDS = 300
BOOKING_SEARCH_TIMEOUT_SECONDS = 120
TICK_SECONDS = 30


async def _check_and_reset_daily_stats(db) -> None:
    colombo_tz = timezone(timedelta(hours=5, minutes=30))
    today_str = datetime.now(colombo_tz).strftime("%Y-%m-%d")

    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    if ss is None:
        return

    last_date = ss.last_daily_reset_date
    if last_date == today_str:
        return

    # First run after this column was introduced: adopt today as the baseline
    # without resetting, so deploying mid-day doesn't wipe drivers' earnings.
    if last_date:
        print(f"[daily_reset] Date changed from {last_date} to {today_str}. Resetting driver daily stats.")
        await db.execute(
            update(Driver).values(today_rides=0, today_earnings=Decimal("0.00"))
        )

    ss.last_daily_reset_date = today_str
    await db.commit()


async def _run_once() -> None:
    async with AsyncSessionLocal() as db:
        try:
            await _check_and_reset_daily_stats(db)
        except Exception as e:
            print(f"[auto_cancel] failed to check/reset daily stats: {e!r}")

    # 1. Sweep stale PENDING food orders
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=STALE_AFTER_SECONDS)
    async with AsyncSessionLocal() as db:
        q = await db.execute(
            select(FoodOrder).where(
                FoodOrder.status == FoodOrderStatus.PENDING,
                FoodOrder.created_at < cutoff,
            )
        )
        stale = q.scalars().all()
        if stale:
            cancelled = 0
            for order in stale:
                order.status = FoodOrderStatus.CANCELLED
                order.cancellation_reason = "Restaurant did not respond in 5 minutes"

                # Wallet refund
                if order.payment_method == "wallet" and order.payment_status == "paid":
                    cq = await db.execute(
                        select(Customer).where(Customer.id == order.customer_id)
                    )
                    customer = cq.scalars().first()
                    if customer:
                        customer.wallet_balance = (
                            customer.wallet_balance or Decimal(0)
                        ) + (order.final_amount or Decimal(0))
                        db.add(
                            WalletTransaction(
                                user_id=customer.user_id,
                                amount=order.final_amount,
                                type="credit",
                                description=(
                                    f"Refund for auto-cancelled food order "
                                    f"{order.order_ref}"
                                ),
                                reference_id=order.order_ref,
                                balance_after=customer.wallet_balance,
                            )
                        )
                        order.payment_status = "refunded"

                await refund_redeemed_points(
                    db, order,
                    source_kind="food_order",
                    description=f"Refund — {order.order_ref} auto-cancelled",
                )

                # Notify customer
                cq = await db.execute(
                    select(Customer).where(Customer.id == order.customer_id)
                )
                c = cq.scalars().first()
                if c:
                    await manager.send(
                        c.user_id,
                        "order_update",
                        {
                            "food_order_id": order.id,
                            "status": order.status.value,
                            "reason": "auto_cancel",
                        },
                    )
                    db.add(
                        Notification(
                            user_id=c.user_id,
                            title="Order auto-cancelled",
                            body=(
                                f"Order {order.order_ref} was cancelled because the "
                                "restaurant didn't respond. Wallet payments have "
                                "been refunded."
                            ),
                            type="order_update",
                        )
                    )
                cancelled += 1
            await db.commit()
            print(f"[auto_cancel] cancelled {cancelled} stale PENDING food order(s)")

    # 2. Sweep stale SEARCHING ride & delivery bookings older than 2 minutes.
    # The clock starts when dispatch actually began, which for a scheduled ride
    # is dispatch_started_at, not booked_at.
    now_sweep = datetime.now(timezone.utc)
    booking_cutoff = now_sweep - timedelta(seconds=BOOKING_SEARCH_TIMEOUT_SECONDS)
    async with AsyncSessionLocal() as db:
        search_started = func.coalesce(Booking.dispatch_started_at, Booking.booked_at)
        bq = await db.execute(
            select(Booking).where(
                Booking.status == BookingStatus.SEARCHING,
                search_started < booking_cutoff,
                (Booking.scheduled_at.is_(None) | (Booking.scheduled_dispatch_sent == True)),
            )
        )
        stale_bookings = bq.scalars().all()
        if stale_bookings:
            cancelled_b = 0
            for b in stale_bookings:
                # Claim the booking atomically. GET /bookings/active runs this
                # same timeout check on the customer's 5s poll, so without the
                # status guard both can refund the same booking.
                claim = await db.execute(
                    update(Booking)
                    .where(
                        Booking.id == b.id,
                        Booking.status == BookingStatus.SEARCHING,
                    )
                    .values(
                        status=BookingStatus.CANCELLED,
                        cancelled_by="system",
                        cancellation_reason="No driver available within search window",
                        cancelled_at=datetime.now(timezone.utc),
                    )
                    .execution_options(synchronize_session=False)
                )
                if claim.rowcount == 0:
                    continue

                # Refund wallet payments if paid
                if b.payment_method == "wallet" and b.payment_status == "paid":
                    cq = await db.execute(
                        select(Customer)
                        .where(Customer.id == b.customer_id)
                        .with_for_update()
                        .execution_options(populate_existing=True)
                    )
                    customer = cq.scalars().first()
                    if customer:
                        customer.wallet_balance = (
                            customer.wallet_balance or Decimal(0)
                        ) + (b.final_amount or Decimal(0))
                        db.add(
                            WalletTransaction(
                                user_id=customer.user_id,
                                amount=b.final_amount,
                                type="credit",
                                description=f"Refund for auto-cancelled booking {b.booking_ref}",
                                reference_id=b.booking_ref,
                                balance_after=customer.wallet_balance,
                            )
                        )
                        await db.execute(
                            update(Booking)
                            .where(Booking.id == b.id)
                            .values(payment_status="refunded")
                            .execution_options(synchronize_session=False)
                        )

                await refund_redeemed_points(
                    db, b,
                    source_kind="booking",
                    description=f"Refund — {b.booking_ref} auto-cancelled",
                )

                cq = await db.execute(
                    select(Customer).where(Customer.id == b.customer_id)
                )
                c = cq.scalars().first()
                if c:
                    await manager.send(
                        c.user_id,
                        "no_drivers_available",
                        {"booking_id": b.id, "booking_ref": b.booking_ref},
                    )
                    await manager.send(
                        c.user_id,
                        "booking_update",
                        {"booking_id": b.id, "status": "cancelled", "reason": "search_timeout"},
                    )
                    db.add(
                        Notification(
                            user_id=c.user_id,
                            title="Ride search timed out",
                            body="No nearby driver accepted the ride. Please try booking again.",
                            type="ride_update",
                            data=f'{{"booking_id":{b.id}}}',
                        )
                    )
                cancelled_b += 1
            await db.commit()
            print(f"[auto_cancel] cancelled {cancelled_b} stale SEARCHING booking(s)")



async def auto_cancel_loop() -> None:
    """Long-running asyncio task. Survives individual sweep failures."""
    while True:
        try:
            await _run_once()
        except Exception as e:  # noqa: BLE001 — sweep must never die
            print(f"[auto_cancel] sweep error: {e!r}")
        await asyncio.sleep(TICK_SECONDS)

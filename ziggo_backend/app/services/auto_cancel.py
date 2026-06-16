"""Background task that auto-cancels stale PENDING food orders.

When a customer places a food order the order sits in PENDING until the
restaurant taps Accept. If the restaurant never responds, the customer
shouldn't be stuck on a "waiting" screen forever — so we sweep every 30 s and
cancel anything older than `STALE_AFTER_SECONDS`. Wallet payments are
refunded; cash orders are simply marked CANCELLED.
"""
import os
import asyncio
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from sqlalchemy import select, update

from ..database import AsyncSessionLocal
from ..models import (
    Customer,
    FoodOrder,
    FoodOrderStatus,
    Notification,
    WalletTransaction,
    Driver,
)
from .ws_manager import manager

# Customer-visible timeout. 5 minutes matches the locked design decision.
STALE_AFTER_SECONDS = 300
TICK_SECONDS = 30


async def _check_and_reset_daily_stats(db) -> None:
    colombo_tz = timezone(timedelta(hours=5, minutes=30))
    today_str = datetime.now(colombo_tz).strftime("%Y-%m-%d")
    
    file_path = "last_reset_date.txt"
    
    last_date = None
    if os.path.exists(file_path):
        try:
            with open(file_path, "r") as f:
                last_date = f.read().strip()
        except Exception:
            pass
            
    if not last_date:
        try:
            with open(file_path, "w") as f:
                f.write(today_str)
        except Exception:
            pass
        return
        
    if last_date != today_str:
        print(f"[daily_reset] Date changed from {last_date} to {today_str}. Resetting driver daily stats.")
        await db.execute(
            update(Driver).values(today_rides=0, today_earnings=Decimal("0.00"))
        )
        await db.commit()
        
        try:
            with open(file_path, "w") as f:
                f.write(today_str)
        except Exception:
            pass


async def _run_once() -> None:
    async with AsyncSessionLocal() as db:
        try:
            await _check_and_reset_daily_stats(db)
        except Exception as e:
            print(f"[auto_cancel] failed to check/reset daily stats: {e!r}")

    cutoff = datetime.now(timezone.utc) - timedelta(seconds=STALE_AFTER_SECONDS)
    async with AsyncSessionLocal() as db:
        q = await db.execute(
            select(FoodOrder).where(
                FoodOrder.status == FoodOrderStatus.PENDING,
                FoodOrder.created_at < cutoff,
            )
        )
        stale = q.scalars().all()
        if not stale:
            return
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


async def auto_cancel_loop() -> None:
    """Long-running asyncio task. Survives individual sweep failures."""
    while True:
        try:
            await _run_once()
        except Exception as e:  # noqa: BLE001 — sweep must never die
            print(f"[auto_cancel] sweep error: {e!r}")
        await asyncio.sleep(TICK_SECONDS)

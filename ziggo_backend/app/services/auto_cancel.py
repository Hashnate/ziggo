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

from sqlalchemy import select

from ..database import AsyncSessionLocal
from ..models import (
    Customer,
    FoodOrder,
    FoodOrderStatus,
    Notification,
    WalletTransaction,
)
from .ws_manager import manager

# Customer-visible timeout. 5 minutes matches the locked design decision.
STALE_AFTER_SECONDS = 300
TICK_SECONDS = 30


async def _run_once() -> None:
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

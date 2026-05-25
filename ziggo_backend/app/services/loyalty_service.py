"""Loyalty points engine (BRD: RW-01, RW-02, RS-07, AD-13).

All earn/redeem math runs through this one module so the booking, food,
and market checkout flows stay thin. Admin-tuned settings come from the
singleton `system_settings` row.

Rules (defaults):
- 1 point per Rs.10 spent  (configurable via `loyalty_earn_rupees_per_point`)
- 1 point worth Rs.0.50    (configurable via `loyalty_value_per_point`)
- Min 100 points to redeem (configurable via `loyalty_min_redeem_points`)
- Max 20% of order can be paid with points (configurable via `loyalty_max_redeem_order_pct`)
"""
from __future__ import annotations

from decimal import Decimal
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import Customer, LoyaltyTransaction, SystemSettings


_SETTINGS_CACHE: dict[str, SystemSettings] = {}


async def _settings(db: AsyncSession) -> SystemSettings:
    """Pulls the singleton settings row each call (no caching — it's one cheap query)."""
    q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    s = q.scalars().first()
    if not s:
        # Fall back to defaults if the row hasn't been created yet — the
        # admin /settings GET creates it lazily, but tests/seeds might hit
        # us first.
        s = SystemSettings(id=1)
        db.add(s)
        await db.commit()
        await db.refresh(s)
    return s


# ---------- Read helpers (used by fare estimate, checkout previews) ----------

async def points_earnable_for(db: AsyncSession, amount: Decimal | float | int) -> int:
    """How many points the customer would earn for spending `amount` rupees.

    Used to populate the per-vehicle 'Earn N points' badge (BRD: RS-07).
    """
    s = await _settings(db)
    rate = Decimal(str(s.loyalty_earn_rupees_per_point or 0))
    if rate <= 0:
        return 0
    amt = Decimal(str(amount or 0))
    return int(amt // rate)


async def value_of(db: AsyncSession, points: int) -> Decimal:
    """Rupee value of `points` at the current redemption rate."""
    s = await _settings(db)
    return (Decimal(points or 0) * Decimal(str(s.loyalty_value_per_point or 0))).quantize(Decimal("0.01"))


async def quote_redemption(
    db: AsyncSession, customer: Customer, requested_points: int, order_amount: Decimal | float
) -> tuple[int, Decimal, Optional[str]]:
    """Resolve how many points actually get redeemed for this order.

    Returns `(actual_points, discount_rupees, reason)`. `reason` is non-None
    only when the request was clamped or rejected, so the caller can surface
    a hint to the customer.

    Caps applied (in order):
    - Customer's actual balance.
    - `loyalty_max_redeem_order_pct` of the order total.
    - Must be at least `loyalty_min_redeem_points` to count at all.
    """
    requested = max(0, int(requested_points or 0))
    if requested == 0:
        return 0, Decimal("0.00"), None

    s = await _settings(db)
    balance = int(customer.loyalty_points or 0)

    reason = None
    if requested > balance:
        requested = balance
        reason = f"Only {balance} points available"

    order_amt = Decimal(str(order_amount or 0))
    max_pct = Decimal(str(s.loyalty_max_redeem_order_pct or 0))
    value_per_point = Decimal(str(s.loyalty_value_per_point or 0))
    if value_per_point <= 0:
        return 0, Decimal("0.00"), "Redemption disabled"

    max_value = (order_amt * max_pct / Decimal("100")).quantize(Decimal("0.01"))
    requested_value = (Decimal(requested) * value_per_point).quantize(Decimal("0.01"))
    if requested_value > max_value:
        capped_points = int(max_value / value_per_point)
        requested = capped_points
        requested_value = (Decimal(capped_points) * value_per_point).quantize(Decimal("0.01"))
        reason = f"Capped at {max_pct}% of order ({max_value} Rs.)"

    min_points = int(s.loyalty_min_redeem_points or 0)
    if requested < min_points:
        return 0, Decimal("0.00"), f"Need at least {min_points} points to redeem"

    return requested, requested_value, reason


# ---------- Write helpers (must be called inside the caller's commit) ----------

async def award_points(
    db: AsyncSession,
    customer: Customer,
    *,
    spend_amount: Decimal | float | int,
    source_kind: str,
    source_id: int,
    description: Optional[str] = None,
) -> int:
    """Credit points for a completed transaction.

    Caller is responsible for `db.commit()` — we just mutate the session.
    Returns the number of points actually credited (0 if the order is too
    small to round up to a single point).
    """
    points = await points_earnable_for(db, spend_amount)
    if points <= 0:
        return 0
    return await _post_ledger(
        db, customer,
        delta=points, kind="earn",
        source_kind=source_kind, source_id=source_id,
        description=description or f"Earned on {source_kind} #{source_id}",
    )


async def redeem_points(
    db: AsyncSession,
    customer: Customer,
    *,
    points: int,
    source_kind: str,
    source_id: int,
    description: Optional[str] = None,
) -> int:
    """Debit `points` for a redemption applied at checkout.

    Assumes the caller already ran `quote_redemption` so this is safe to
    deduct. If the balance is somehow short we deduct only what's available
    and return the actual amount taken.
    """
    if points <= 0:
        return 0
    points = min(points, int(customer.loyalty_points or 0))
    if points == 0:
        return 0
    return await _post_ledger(
        db, customer,
        delta=-points, kind="redeem",
        source_kind=source_kind, source_id=source_id,
        description=description or f"Redeemed on {source_kind} #{source_id}",
    )


async def _post_ledger(
    db: AsyncSession,
    customer: Customer,
    *,
    delta: int,
    kind: str,
    source_kind: str,
    source_id: int,
    description: str,
) -> int:
    customer.loyalty_points = int(customer.loyalty_points or 0) + delta
    db.add(LoyaltyTransaction(
        customer_id=customer.id,
        points=delta,
        kind=kind,
        source_kind=source_kind,
        source_id=source_id,
        description=description,
        balance_after=customer.loyalty_points,
    ))
    return abs(delta)


# ---------- Gold membership helpers (BRD: RW-03) ----------

def is_gold_active(customer: Customer) -> bool:
    """Customer is Gold if the flag is set AND not expired."""
    if not customer:
        return False
    if not getattr(customer, "gold_member", False):
        return False
    from datetime import datetime, timezone
    exp = getattr(customer, "gold_expires_at", None)
    if exp is None:
        return False
    return exp > datetime.now(timezone.utc)


async def gold_delivery_fee(
    db: AsyncSession, customer: Customer, base_fee: Decimal | float | int
) -> Decimal:
    """Returns the delivery fee a customer should be charged.

    Non-Gold customers pay the base fee. Gold members get the configured
    percentage off — defaults to 50% (BRD: RW-03). Driver earnings still
    flow off the base fee on the merchant/driver side; the discount is
    Ziggo's cost.
    """
    base = Decimal(str(base_fee or 0))
    if not is_gold_active(customer):
        return base
    s = await _settings(db)
    pct = Decimal(str(s.gold_delivery_discount_pct or 0))
    discounted = (base * (Decimal("100") - pct) / Decimal("100")).quantize(Decimal("0.01"))
    return max(Decimal("0.00"), discounted)

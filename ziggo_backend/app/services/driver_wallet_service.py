"""Driver bonus wallet.

An admin gives drivers bonus money (one driver, one vehicle type or every
approved driver), each gift with its own expiry date. Drivers can't withdraw
it: it only pays the commission they owe Ziggo, automatically, as soon as they
owe some, soonest-expiring money first. Whatever is unused after the expiry
date (Sri Lanka day, inclusive) is lost.

A payment is a driver_payouts row of kind "wallet_payment", which lifts the
driver's running balance (see finance_service) but never above zero, so bonus
money can't turn into a pending payout.
"""
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Iterable, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..models import Driver, DriverPayout, DriverWalletCredit, DriverWalletGrant, Notification, User
from .finance_service import WALLET_PAYMENT, get_driver_outstanding_commission
from .launch_service import today_lk

ZERO = Decimal("0")
CENT = Decimal("0.01")
PAYMENT_DESCRIPTION = "Commission paid from bonus wallet"


def _dec(v) -> Decimal:
    return Decimal(str(v)) if v is not None else ZERO


def remaining(c: DriverWalletCredit) -> Decimal:
    return max(ZERO, _dec(c.amount) - _dec(c.used_amount))


def status_of(c: DriverWalletCredit, on: Optional[date] = None) -> str:
    """active | used | expired | cancelled"""
    if c.cancelled_at is not None:
        return "cancelled"
    if remaining(c) <= 0:
        return "used"
    if c.expires_on < (on or today_lk()):
        return "expired"
    return "active"


async def _usable_credits(db: AsyncSession, driver_id: int, fresh: bool = False) -> list[DriverWalletCredit]:
    q = (
        select(DriverWalletCredit)
        .where(
            DriverWalletCredit.driver_id == driver_id,
            DriverWalletCredit.cancelled_at == None,  # noqa: E711
            DriverWalletCredit.expires_on >= today_lk(),
            DriverWalletCredit.used_amount < DriverWalletCredit.amount,
        )
        .order_by(DriverWalletCredit.expires_on, DriverWalletCredit.id)
    )
    if fresh:
        q = q.execution_options(populate_existing=True)
    return list((await db.execute(q)).scalars().all())


async def available(db: AsyncSession, driver_id: int) -> Decimal:
    return sum((remaining(c) for c in await _usable_credits(db, driver_id)), ZERO)


async def pay_commission(db: AsyncSession, driver_id: int) -> Decimal:
    """Pay whatever the driver owes Ziggo from their unexpired bonus money.
    Commits when it pays something; returns the amount paid."""
    if not await _usable_credits(db, driver_id):
        return ZERO
    # Lock the driver so two jobs finishing at once can't both spend the same debt.
    driver = (
        await db.execute(select(Driver).where(Driver.id == driver_id).with_for_update())
    ).scalars().first()
    if driver is None:
        return ZERO
    owed = (await get_driver_outstanding_commission(db, driver_id)).quantize(CENT)
    if owed <= 0:
        return ZERO
    left = owed
    for c in await _usable_credits(db, driver_id, fresh=True):
        take = min(remaining(c), left)
        c.used_amount = _dec(c.used_amount) + take
        left -= take
        if left <= 0:
            break
    paid = owed - left
    if paid <= 0:
        return ZERO
    db.add(DriverPayout(
        driver_id=driver.id,
        user_id=driver.user_id,
        amount=paid,
        kind=WALLET_PAYMENT,
        description=PAYMENT_DESCRIPTION,
    ))
    await db.commit()
    return paid


async def settle(db: AsyncSession, driver_ids: Iterable[int]) -> Decimal:
    """Pay these drivers' commission from their wallets, then lift any
    commission block that is now paid off."""
    from .finance_service import check_and_deactivate_driver

    total = ZERO
    for driver_id in sorted(set(driver_ids)):
        paid = await pay_commission(db, driver_id)
        if paid > 0:
            total += paid
            await check_and_deactivate_driver(db, driver_id)
        else:
            await db.commit()  # release the driver row lock before the next one
    return total


# ---------------------------------------------------------------------------
# Admin actions
# ---------------------------------------------------------------------------


async def eligible_drivers(db: AsyncSession, vehicle_type: str = "") -> list[Driver]:
    """Approved drivers, including those blocked for unpaid commission (they
    keep their approval); not pending, rejected or admin-suspended ones."""
    q = select(Driver).where(Driver.is_approved == True)  # noqa: E712
    if vehicle_type:
        q = q.where(Driver.vehicle_type == vehicle_type)
    return list((await db.execute(q.order_by(Driver.id))).scalars().all())


async def give(
    db: AsyncSession,
    *,
    drivers: list[Driver],
    amount: Decimal,
    expires_on: date,
    note: str,
    audience: str,
    admin_id: Optional[int] = None,
) -> DriverWalletGrant:
    grant = DriverWalletGrant(
        note=note,
        amount=amount,
        expires_on=expires_on,
        audience=audience,
        drivers_count=len(drivers),
        created_by_id=admin_id,
    )
    db.add(grant)
    await db.flush()
    for d in drivers:
        db.add(DriverWalletCredit(
            grant_id=grant.id, driver_id=d.id, amount=amount, used_amount=ZERO, expires_on=expires_on,
        ))
        db.add(Notification(
            user_id=d.user_id,
            title="Bonus added to your wallet",
            body=(f"Rs.{amount:,.2f} ({note}) was added to your bonus wallet. It pays your Ziggo "
                  f"commission automatically until {expires_on:%d %b %Y}."),
            type="wallet",
        ))
    await db.commit()
    await settle(db, [d.id for d in drivers])
    return grant


async def change_expiry(db: AsyncSession, credits: list[DriverWalletCredit], expires_on: date) -> None:
    for c in credits:
        if c.cancelled_at is None:
            c.expires_on = expires_on
    await db.commit()
    # Money brought back from expiry pays any commission owed straight away.
    await settle(db, [c.driver_id for c in credits])


async def cancel(db: AsyncSession, credits: list[DriverWalletCredit]) -> Decimal:
    """Remove what is left of these credits. Commission already paid stays paid."""
    removed = ZERO
    now = datetime.now(timezone.utc)
    for c in credits:
        if c.cancelled_at is None and remaining(c) > 0:
            removed += remaining(c)
            c.cancelled_at = now
    await db.commit()
    return removed


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------


def _totals(credits: Iterable[DriverWalletCredit], on: date) -> dict:
    t = {"given": ZERO, "used": ZERO, "available": ZERO, "lost": ZERO}
    for c in credits:
        t["given"] += _dec(c.amount)
        t["used"] += _dec(c.used_amount)
        if status_of(c, on) == "active":
            t["available"] += remaining(c)
        else:
            t["lost"] += remaining(c)
    return {k: float(v) for k, v in t.items()}


def _credit_row(c: DriverWalletCredit, on: date) -> dict:
    return {
        "id": c.id,
        "grant_id": c.grant_id,
        "note": c.grant.note if c.grant else "",
        "amount": float(_dec(c.amount)),
        "used": float(_dec(c.used_amount)),
        "remaining": float(remaining(c)),
        "expires_on": c.expires_on.isoformat(),
        "days_left": (c.expires_on - on).days,
        "status": status_of(c, on),
        "given_at": c.created_at.isoformat() if c.created_at else None,
    }


async def driver_wallet(db: AsyncSession, driver_id: int) -> dict:
    """Everything the driver's Wallet screen and the admin driver page show."""
    on = today_lk()
    credits = (await db.execute(
        select(DriverWalletCredit)
        .options(selectinload(DriverWalletCredit.grant))
        .where(DriverWalletCredit.driver_id == driver_id)
        .order_by(DriverWalletCredit.created_at.desc(), DriverWalletCredit.id.desc())
    )).scalars().all()
    active = sorted((c for c in credits if status_of(c, on) == "active"), key=lambda c: (c.expires_on, c.id))
    next_expiry = None
    if active:
        first = active[0].expires_on
        next_expiry = {
            "date": first.isoformat(),
            "days_left": (first - on).days,
            "amount": float(sum((remaining(c) for c in active if c.expires_on == first), ZERO)),
        }
    payments = (await db.execute(
        select(DriverPayout)
        .where(DriverPayout.driver_id == driver_id, DriverPayout.kind == WALLET_PAYMENT)
        .order_by(DriverPayout.created_at.desc(), DriverPayout.id.desc())
        .limit(100)
    )).scalars().all()
    return {
        "available": float(sum((remaining(c) for c in active), ZERO)),
        "next_expiry": next_expiry,
        "commission_due": float(await get_driver_outstanding_commission(db, driver_id)),
        "totals": _totals(credits, on),
        "credits": [_credit_row(c, on) for c in credits],
        "payments": [
            {"amount": float(_dec(p.amount)), "at": p.created_at.isoformat() if p.created_at else None}
            for p in payments
        ],
        "withdrawable": False,
    }


async def grants_overview(db: AsyncSession) -> dict:
    on = today_lk()
    grants = (await db.execute(
        select(DriverWalletGrant)
        .options(selectinload(DriverWalletGrant.credits), selectinload(DriverWalletGrant.created_by))
        .order_by(DriverWalletGrant.created_at.desc(), DriverWalletGrant.id.desc())
    )).scalars().all()
    rows = []
    for g in grants:
        live = [c for c in g.credits if c.cancelled_at is None]
        rows.append({
            "grant": g,
            "totals": _totals(g.credits, on),
            "active_drivers": sum(1 for c in g.credits if status_of(c, on) == "active"),
            "own_expiry": sum(1 for c in live if c.expires_on != g.expires_on),
            "expired": g.expires_on < on,
            "days_left": (g.expires_on - on).days,
            "cancelled": bool(g.credits) and not live,
            "by": g.created_by.full_name if g.created_by else None,
        })
    all_credits = [c for g in grants for c in g.credits]
    return {"rows": rows, "totals": _totals(all_credits, on), "today": on}


async def describe_audience(db: AsyncSession, audience: str) -> str:
    if audience == "all":
        return "All drivers"
    if audience.startswith("vehicle:"):
        return f"All {audience.split(':', 1)[1]} drivers"
    if audience.startswith("driver:"):
        d = (await db.execute(
            select(Driver).options(selectinload(Driver.user)).where(Driver.id == int(audience.split(":", 1)[1]))
        )).scalars().first()
        u: Optional[User] = d.user if d else None
        return (u.full_name or u.phone_number) if u else "One driver"
    return audience

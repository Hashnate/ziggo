"""Driver bonus wallet.

Bonus money only pays commission, automatically and soonest-expiring first; it
never becomes a pending payout, expired or removed money is never used, and a
driver blocked for commission is unblocked once the wallet pays enough.
"""
from datetime import timedelta
from decimal import Decimal

from sqlalchemy import delete, select

import app.models  # noqa: F401  (registers every table for create_all)
from app.api.v1.driver import get_my_wallet
from app.database import AsyncSessionLocal, Base, engine
from app.models import (
    Booking, BookingStatus, Customer, Driver, DriverPayout, DriverStatus, DriverWalletCredit,
    DriverWalletGrant, Notification, User, UserRole,
)
from app.services import driver_wallet_service as wallet
from app.services.finance_service import (
    _driver_commission_limit, check_and_deactivate_driver, get_driver_balance, get_driver_payout_stats,
    get_withdrawals_data,
)
from app.services.launch_service import today_lk
from app.services.ws_manager import manager

PHONES = ["0779990401", "0779990402", "0779990403", "0779990404"]


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_(PHONES))
    drivers = select(Driver.id).where(Driver.user_id.in_(users))
    grants = select(DriverWalletCredit.grant_id).where(DriverWalletCredit.driver_id.in_(drivers))
    await db.execute(delete(DriverWalletGrant).where(DriverWalletGrant.id.in_(grants)))
    await db.execute(delete(DriverPayout).where(DriverPayout.driver_id.in_(drivers)))
    await db.execute(delete(Booking).where(Booking.driver_id.in_(drivers)))
    await db.execute(delete(Notification).where(Notification.user_id.in_(users)))
    await db.execute(delete(Driver).where(Driver.user_id.in_(users)))
    await db.execute(delete(Customer).where(Customer.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


class Rides:
    def __init__(self, db, customer_id):
        self.db, self.customer_id, self.n = db, customer_id, 0

    async def complete(self, driver_id, paid, earned, method="cash"):
        """A finished job, then what the app runs after every job."""
        self.n += 1
        self.db.add(Booking(
            booking_ref=f"ZGWALLET{self.n:02d}", customer_id=self.customer_id, driver_id=driver_id,
            service_type="tuk", status=BookingStatus.COMPLETED, payment_method=method,
            pickup_lat=6.9147, pickup_lng=79.8778, pickup_address="Borella",
            drop_lat=6.8649, drop_lng=79.8997, drop_address="Nugegoda",
            fare_amount=Decimal(paid), final_amount=Decimal(paid), driver_earnings=Decimal(earned),
        ))
        await self.db.commit()
        await check_and_deactivate_driver(self.db, driver_id)


async def _credits(db, driver_id):
    rows = await db.execute(
        select(DriverWalletCredit).where(DriverWalletCredit.driver_id == driver_id)
        .order_by(DriverWalletCredit.id).execution_options(populate_existing=True)
    )
    return rows.scalars().all()


async def test_bonus_wallet_pays_commission_only(monkeypatch):
    async def quiet(*a, **k):
        pass

    monkeypatch.setattr(manager, "publish", quiet)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    today = today_lk()
    D = Decimal
    try:
        await _run(today, D)
    finally:
        await engine.dispose()


async def _run(today, D):
    async with AsyncSessionLocal() as db:
        await _clean(db)
        try:
            cust_user = User(phone_number=PHONES[0], role=UserRole.CUSTOMER, full_name="Amali")
            a_user = User(phone_number=PHONES[1], role=UserRole.DRIVER, full_name="Nimal")
            b_user = User(phone_number=PHONES[2], role=UserRole.DRIVER, full_name="Kamal")
            c_user = User(phone_number=PHONES[3], role=UserRole.DRIVER, full_name="Sunil")
            db.add_all([cust_user, a_user, b_user, c_user])
            await db.flush()
            customer = Customer(user_id=cust_user.id)
            a = Driver(user_id=a_user.id, status=DriverStatus.APPROVED, is_approved=True, vehicle_type="tuk")
            b = Driver(user_id=b_user.id, status=DriverStatus.APPROVED, is_approved=True, vehicle_type="tuk")
            c = Driver(user_id=c_user.id, status=DriverStatus.SUSPENDED, is_approved=False, vehicle_type="tuk")
            db.add_all([customer, a, b, c])
            await db.commit()
            rides = Rides(db, customer.id)

            ids = {d.id for d in await wallet.eligible_drivers(db, "tuk")}
            assert {a.id, b.id} <= ids and c.id not in ids, "admin-suspended drivers get no bonus"

            # A owes 100 commission; a 300 bonus pays it at once.
            await rides.complete(a.id, "1000", "900")
            assert await get_driver_balance(db, a.id) == D("-100")
            g1 = await wallet.give(db, drivers=[a], amount=D("300"), expires_on=today + timedelta(days=10),
                                   note="Avurudu bonus", audience=f"driver:{a.id}")
            assert await get_driver_balance(db, a.id) == 0
            assert await wallet.available(db, a.id) == D("200")
            note = (await db.execute(select(Notification).where(Notification.user_id == a_user.id))).scalars().all()
            assert [n.type for n in note] == ["wallet"] and "Rs.300.00" in note[0].body

            # A bonus ending sooner is spent first.
            await wallet.give(db, drivers=[a], amount=D("100"), expires_on=today, note="Today only",
                              audience=f"driver:{a.id}")
            assert await wallet.available(db, a.id) == D("300"), "nothing owed, nothing spent"
            await rides.complete(a.id, "500", "300")          # owes 200
            c1, c2 = await _credits(db, a.id)
            assert (c1.used_amount, c2.used_amount) == (D("200"), D("100"))
            assert await get_driver_balance(db, a.id) == 0

            # Expired money isn't used; bringing it back makes it usable again.
            await wallet.give(db, drivers=[a], amount=D("1000"), expires_on=today - timedelta(days=1),
                              note="Old", audience=f"driver:{a.id}")
            await rides.complete(a.id, "100", "50")           # owes 50
            c1, c2, c3 = await _credits(db, a.id)
            assert (c1.used_amount, c3.used_amount) == (D("250"), D("0"))
            assert await wallet.available(db, a.id) == D("50")
            await wallet.change_expiry(db, [c3], today + timedelta(days=5))
            assert await wallet.available(db, a.id) == D("1050")

            # Card earnings are owed to the driver; the wallet never adds to a payout.
            await rides.complete(a.id, "400", "400", method="card")
            assert await get_driver_balance(db, a.id) == D("400")
            assert (await get_driver_payout_stats(db, a.id))["pending"] == 400.0
            assert await wallet.available(db, a.id) == D("1050")

            # Removing a bonus loses what's left; commission already paid stays paid.
            removed = await wallet.cancel(db, [c1])
            assert removed == D("50") and await wallet.available(db, a.id) == D("1000")
            assert await get_driver_balance(db, a.id) == D("400")

            # The driver's wallet screen.
            view = await get_my_wallet(db, a_user)
            assert view["available"] == 1000.0 and view["withdrawable"] is False
            assert view["next_expiry"] == {"date": (today + timedelta(days=5)).isoformat(), "days_left": 5, "amount": 1000.0}
            assert [r["status"] for r in view["credits"]] == ["active", "used", "cancelled"]
            assert sum(p["amount"] for p in view["payments"]) == 350.0
            assert view["totals"]["used"] == 350.0 and view["totals"]["lost"] == 50.0

            # B is blocked for commission over the limit; the bonus pays enough to unblock.
            limit = await _driver_commission_limit(db)
            await rides.complete(b.id, str(limit + 600), "100")    # owes limit + 500
            await db.refresh(b)
            assert b.status == DriverStatus.SUSPENDED
            await wallet.give(db, drivers=[b], amount=D("600"), expires_on=today, note="Help", audience="all")
            await db.refresh(b)
            assert b.status == DriverStatus.APPROVED and await get_driver_balance(db, b.id) == D("-" + str(limit - 100))

            history = (await get_withdrawals_data(db))["history"]
            assert not [h for h in history if h.kind == "wallet_payment"], "wallet payments aren't payouts"
        finally:
            await _clean(db)

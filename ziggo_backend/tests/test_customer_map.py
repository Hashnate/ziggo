"""Admin Customer Map (Phase 2, feature 01, stage D): the recency score, where each
customer is drawn, and the phone-reveal log."""
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import delete, select

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from app.models import AdminPhoneReveal, Booking, BookingStatus, Customer, Driver, DriverStatus, User, UserRole
from app.services import customer_map_service as cms

PHONES = [f"07799902{i:02d}" for i in range(1, 9)]
LK = timezone(timedelta(hours=5, minutes=30))
NOW = datetime(2026, 10, 24, 12, 0, tzinfo=LK)


@pytest.mark.parametrize("last_ride, score", [
    (None, 0),
    (NOW, 100),
    (NOW.replace(hour=0, minute=5), 100),                       # earlier the same Sri Lanka day
    (datetime(2026, 10, 23, 18, 45, tzinfo=timezone.utc), 100),  # 00:15 on the 24th in Sri Lanka
    (NOW - timedelta(days=1), 98),
    (NOW - timedelta(days=30), 50),
    (NOW - timedelta(days=59), 2),
    (NOW - timedelta(days=60), 0),
    (NOW - timedelta(days=400), 0),
    (datetime(2026, 10, 23, 12, 0), 98),                         # naive values are UTC
])
def test_recency_score(last_ride, score):
    assert cms.recency_score(last_ride, NOW) == score


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_(PHONES))
    customers = select(Customer.id).where(Customer.user_id.in_(users))
    await db.execute(delete(AdminPhoneReveal).where(AdminPhoneReveal.admin_user_id.in_(users)))
    await db.execute(delete(Booking).where(Booking.customer_id.in_(customers)))
    await db.execute(delete(Driver).where(Driver.user_id.in_(users)))
    await db.execute(delete(Customer).where(Customer.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


def _booking(ref, customer_id, status, lat, lng, driver_id=None, **extra):
    return Booking(booking_ref=ref, customer_id=customer_id, driver_id=driver_id, service_type="tuk", status=status,
                   pickup_lat=lat, pickup_lng=lng, pickup_address=f"Pickup {ref}", drop_lat=6.86, drop_lng=79.89,
                   drop_address="Nugegoda", payment_method="cash", **extra)


async def test_feed_and_reveals():
    now = datetime.now(timezone.utc)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                users = []
                for i, phone in enumerate(PHONES[:6]):
                    role = UserRole.DRIVER if i == 4 else UserRole.ADMIN if i == 5 else UserRole.CUSTOMER
                    u = User(phone_number=phone, role=role, full_name=f"Map {i}",
                             admin_role="admin" if role == UserRole.ADMIN else None)
                    db.add(u)
                    await db.flush()
                    users.append(u)
                amal, bimal, chamari, dilini = (Customer(user_id=u.id) for u in users[:4])
                driver = Driver(user_id=users[4].id, status=DriverStatus.APPROVED, is_approved=True,
                                current_lat=6.95, current_lng=79.85)
                admin = users[5]
                db.add_all([amal, bimal, chamari, dilini, driver])
                await db.flush()

                db.add_all([
                    _booking("ZGTESTCM01", amal.id, BookingStatus.COMPLETED, 6.91, 79.86,
                             completed_at=now - timedelta(days=10)),
                    _booking("FLTESTCM01", amal.id, BookingStatus.COMPLETED, 6.92, 79.87, is_flash=True,
                             completed_at=now - timedelta(days=1)),
                ])
                await db.flush()
                db.add(_booking("ZGTESTCM02", amal.id, BookingStatus.CANCELLED, 6.93, 79.88))
                await db.flush()
                waiting = _booking("ZGTESTCM03", bimal.id, BookingStatus.ACCEPTED, 6.90, 79.85, driver.id,
                                   passenger_sharing=True, passenger_lat=6.9011, passenger_lng=79.8511,
                                   passenger_location_at=now - timedelta(seconds=5))
                riding = _booking("ZGTESTCM04", chamari.id, BookingStatus.STARTED, 6.89, 79.84, driver.id)
                stale = _booking("ZGTESTCM05", dilini.id, BookingStatus.ARRIVED, 6.88, 79.83,
                                 passenger_sharing=True, passenger_lat=6.8811, passenger_lng=79.8311,
                                 passenger_location_at=now - timedelta(seconds=61))
                later = _booking("ZGTESTCM06", dilini.id, BookingStatus.SEARCHING, 6.87, 79.82,
                                 scheduled_at=now + timedelta(days=2), scheduled_dispatch_sent=False)
                db.add_all([waiting, riding, stale, later])
                await db.commit()

                trips = {t["booking_ref"]: t for t in await cms.active_trips(db, now)}
                assert "ZGTESTCM06" not in trips, "a scheduled ride is not active until dispatch starts"
                assert (trips["ZGTESTCM03"]["source"], trips["ZGTESTCM03"]["lat"]) == ("live", 6.9011)
                assert (trips["ZGTESTCM04"]["source"], trips["ZGTESTCM04"]["lat"]) == ("driver", 6.95)
                assert (trips["ZGTESTCM05"]["source"], trips["ZGTESTCM05"]["lat"]) == ("pickup", 6.88), \
                    "a stale live point falls back to the pickup"
                assert trips["ZGTESTCM03"]["name"] == "Map 1"
                assert "phone" not in str(trips), "the feed carries no phone numbers"

                feed = await cms.customer_dots(db, now)
                dots = {d["id"]: d for d in feed["customers"]}
                a = dots[amal.id]
                assert (a["lat"], a["booking_ref"], a["booking_status"]) == (6.93, "ZGTESTCM02", "cancelled"), \
                    "drawn at the pickup of the latest booking, whatever its status"
                assert a["score"] == 83, "scored on the last completed ride; the newer parcel doesn't count"
                assert dots[dilini.id]["score"] == 0 and dots[dilini.id]["last_ride_at"] is None
                assert "phone" not in str(feed)
                totals = feed["totals"]
                assert totals["never_booked"] == totals["customers"] - totals["booked"]
                assert totals["recent"] + totals["lapsing"] + totals["inactive"] == len(feed["customers"])

                assert await cms.reveal_phone(db, admin, 999999) is None
                shown = await cms.reveal_phone(db, admin, amal.id, waiting.id)
                assert shown == {"customer_id": amal.id, "name": "Map 0", "phone": PHONES[0]}
                await cms.reveal_phone(db, admin, bimal.id, waiting.id)
                log = (await db.execute(
                    select(AdminPhoneReveal.customer_id, AdminPhoneReveal.booking_id, AdminPhoneReveal.admin_name)
                    .where(AdminPhoneReveal.admin_user_id == admin.id)
                    .order_by(AdminPhoneReveal.id)
                )).all()
                assert log == [(amal.id, None, "Map 5"), (bimal.id, waiting.id, "Map 5")], \
                    "every reveal is logged; a booking that isn't the customer's is dropped"
                recent = await cms.recent_reveals(db, limit=2)
                assert [(r["customer"], r["booking_ref"]) for r in recent] == [("Map 1", "ZGTESTCM03"), ("Map 0", None)]
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()

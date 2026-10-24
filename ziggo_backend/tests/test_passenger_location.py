"""Customer live location while waiting for pickup (Phase 2, feature 01, stage A).

The customer shares per booking. Only the latest point is kept, only the booking's
driver and the admin map are sent it, and it is wiped when the trip starts or ends,
when sharing stops, or when it stops updating.
"""
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlalchemy import delete, select, update

import app.models  # noqa: F401  (registers every table for create_all)
from app.api.v1.bookings import (
    get_active_booking,
    share_passenger_location,
    stop_passenger_location,
    update_booking_status,
)
from app.database import AsyncSessionLocal, Base, engine
from app.models import Booking, BookingStatus, Customer, Driver, DriverStatus, User, UserRole
from app.schemas import BookingStatusUpdate, PassengerLocationUpdate
from app.services import passenger_location_service
from app.services.ws_manager import manager

PHONES = [f"07799901{i:02d}" for i in range(1, 4)]
NOW = datetime.now(timezone.utc)


def _booking(status=BookingStatus.ACCEPTED, sharing=True, age=5):
    return SimpleNamespace(status=status, passenger_sharing=sharing, passenger_lat=6.9, passenger_lng=79.86,
                           passenger_location_at=NOW - timedelta(seconds=age))


@pytest.mark.parametrize("booking, live", [
    (_booking(), True),
    (_booking(BookingStatus.SEARCHING), True),
    (_booking(BookingStatus.ARRIVED, age=59), True),
    (_booking(age=61), False),                      # stale points are never shown as live
    (_booking(BookingStatus.STARTED), False),       # the trip is under way
    (_booking(BookingStatus.CANCELLED), False),
    (_booking(sharing=False), False),
])
def test_live_point(booking, live):
    assert (passenger_location_service.live_point(booking, NOW) is not None) == live


def test_too_soon():
    assert passenger_location_service.too_soon(_booking(age=1), NOW)
    assert not passenger_location_service.too_soon(_booking(age=3), NOW)
    assert not passenger_location_service.too_soon(_booking(age=1, sharing=False), NOW)


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_(PHONES))
    customers = select(Customer.id).where(Customer.user_id.in_(users))
    await db.execute(delete(Booking).where(Booking.customer_id.in_(customers)))
    await db.execute(delete(Driver).where(Driver.user_id.in_(users)))
    await db.execute(delete(Customer).where(Customer.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


def _ride(ref, customer_id, driver_id=None, status=BookingStatus.ACCEPTED, **extra):
    return Booking(booking_ref=ref, customer_id=customer_id, driver_id=driver_id, service_type="tuk", status=status,
                   pickup_lat=6.9147, pickup_lng=79.8778, pickup_address="Borella", drop_lat=6.8649,
                   drop_lng=79.8997, drop_address="Nugegoda", payment_method="cash", **extra)


async def test_sharing_end_to_end(monkeypatch):
    sent, published = [], []

    async def fake_send(user_id, event, payload):
        sent.append((user_id, event, payload))

    async def fake_publish(topic, event, payload):
        published.append((topic, event, payload))

    monkeypatch.setattr(manager, "send", fake_send)
    monkeypatch.setattr(manager, "publish", fake_publish)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                users = []
                for phone, role in [(PHONES[0], UserRole.CUSTOMER), (PHONES[1], UserRole.CUSTOMER),
                                    (PHONES[2], UserRole.DRIVER)]:
                    u = User(phone_number=phone, role=role, full_name=phone)
                    db.add(u)
                    await db.flush()
                    users.append(u)
                amali, other = Customer(user_id=users[0].id), Customer(user_id=users[1].id)
                driver = Driver(user_id=users[2].id, status=DriverStatus.APPROVED, is_approved=True)
                db.add_all([amali, other, driver])
                await db.flush()
                ride = _ride("ZGTESTPL01", amali.id, driver.id)
                parcel = _ride("FLTESTPL01", amali.id, status=BookingStatus.SEARCHING, is_flash=True)
                db.add_all([ride, parcel])
                await db.commit()
                amali_user, other_user, driver_user = users
                here = PassengerLocationUpdate(lat=6.9150, lng=79.8780)

                with pytest.raises(HTTPException) as e:
                    await share_passenger_location(ride.id, here, db, other_user)
                assert e.value.status_code == 404, "only the booking's own customer can share on it"
                with pytest.raises(HTTPException) as e:
                    await share_passenger_location(parcel.id, here, db, amali_user)
                assert e.value.status_code == 400, "rides only"

                res = await share_passenger_location(ride.id, here, db, amali_user)
                assert res["sharing"] is True
                assert sent == [(driver_user.id, "passenger_location_update",
                                 {"booking_id": ride.id, "lat": 6.915, "lng": 79.878, "at": res["at"]})]
                assert [(t, ev, p["customer_id"], p["status"]) for t, ev, p in published] == \
                    [("admin_customers", "customer_location_update", amali.id, "accepted")]
                assert "phone" not in str(published), "the admin channel carries no phone numbers"

                sent.clear()
                published.clear()
                again = await share_passenger_location(ride.id, PassengerLocationUpdate(lat=6.92, lng=79.88), db,
                                                       amali_user)
                assert again["at"] == res["at"] and not sent and not published, "points 2 s apart are ignored"

                active = await get_active_booking(db, driver_user)
                assert active.passenger_sharing is True
                assert (active.passenger_location["lat"], active.passenger_location["lng"]) == (6.915, 79.878)

                await db.execute(update(Booking).where(Booking.id == ride.id)
                                 .values(passenger_location_at=datetime.now(timezone.utc) - timedelta(seconds=61)))
                await db.commit()
                active = await get_active_booking(db, driver_user)
                assert active.passenger_location is None, "a stale point is not shown"
                await share_passenger_location(ride.id, here, db, amali_user)

                await update_booking_status(ride.id, BookingStatusUpdate(status=BookingStatus.ARRIVED), db,
                                            driver_user)
                await db.refresh(ride)
                assert ride.passenger_sharing is True, "still waiting for pickup"
                published.clear()
                await update_booking_status(ride.id, BookingStatusUpdate(status=BookingStatus.STARTED, otp=ride.otp),
                                            db, driver_user)
                await db.refresh(ride)
                assert (ride.passenger_sharing, ride.passenger_lat, ride.passenger_location_at) == (False, None, None), \
                    "the trip starting wipes the point"
                assert ("admin_customers", "customer_location_stopped", {"booking_id": ride.id}) in published
                with pytest.raises(HTTPException) as e:
                    await share_passenger_location(ride.id, here, db, amali_user)
                assert e.value.status_code == 409

                second = _ride("ZGTESTPL02", amali.id, driver.id)
                db.add(second)
                await db.commit()
                await share_passenger_location(second.id, here, db, amali_user)
                sent.clear()
                assert await stop_passenger_location(second.id, db, amali_user) == {"sharing": False}
                await db.refresh(second)
                assert (second.passenger_sharing, second.passenger_lat) == (False, None)
                assert sent == [(driver_user.id, "passenger_location_stopped", {"booking_id": second.id})]
                sent.clear()
                await stop_passenger_location(second.id, db, amali_user)
                assert not sent, "stopping twice tells nobody again"

                old = datetime.now(timezone.utc) - timedelta(minutes=11)
                fresh = datetime.now(timezone.utc)
                leftovers = [
                    _ride("ZGTESTPL03", amali.id, status=BookingStatus.SEARCHING, passenger_sharing=True,
                          passenger_lat=6.9, passenger_lng=79.8, passenger_location_at=old),
                    _ride("ZGTESTPL04", amali.id, status=BookingStatus.COMPLETED, passenger_sharing=True,
                          passenger_lat=6.9, passenger_lng=79.8, passenger_location_at=fresh),
                    _ride("ZGTESTPL05", amali.id, status=BookingStatus.SEARCHING, passenger_sharing=True,
                          passenger_lat=6.9, passenger_lng=79.8, passenger_location_at=fresh),
                ]
                db.add_all(leftovers)
                await db.commit()
                await passenger_location_service.forget_stale(db)
                kept = dict((await db.execute(
                    select(Booking.booking_ref, Booking.passenger_lat).where(Booking.booking_ref.like("ZGTESTPL0%"))
                )).all())
                assert kept["ZGTESTPL03"] is None, "a point that stopped updating is deleted"
                assert kept["ZGTESTPL04"] is None, "a point left on a finished trip is deleted"
                assert kept["ZGTESTPL05"] is not None, "a fresh point while searching is kept"
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()

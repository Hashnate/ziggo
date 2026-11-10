"""A ride cancelled after a driver accepted it tells the other side who cancelled and why.

The customer's booking_update carries the reason and who cancelled (the driver's already did),
so the app can keep the ride screen open on it. The side that did not cancel also gets a
notification with the reason.
"""
import pytest
from sqlalchemy import delete, select

import app.models  # noqa: F401  (registers every table for create_all)
from app.api.v1.bookings import update_booking_status
from app.database import AsyncSessionLocal, Base, engine
from app.models import Booking, BookingStatus, Customer, Driver, DriverStatus, Notification, User, UserRole
from app.schemas import BookingStatusUpdate
from app.services import fcm_service
from app.services.ws_manager import manager

PHONES = ["0779990301", "0779990302"]


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_(PHONES))
    customers = select(Customer.id).where(Customer.user_id.in_(users))
    await db.execute(delete(Booking).where(Booking.customer_id.in_(customers)))
    await db.execute(delete(Notification).where(Notification.user_id.in_(users)))
    await db.execute(delete(Driver).where(Driver.user_id.in_(users)))
    await db.execute(delete(Customer).where(Customer.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


def _ride(ref, customer_id, driver_id, status):
    return Booking(booking_ref=ref, customer_id=customer_id, driver_id=driver_id, service_type="tuk", status=status,
                   pickup_lat=6.9147, pickup_lng=79.8778, pickup_address="Borella", drop_lat=6.8649,
                   drop_lng=79.8997, drop_address="Nugegoda", payment_method="cash")


async def _notices(db, user_id):
    rows = await db.execute(select(Notification.title, Notification.body).where(Notification.user_id == user_id))
    return rows.all()


async def test_cancel_after_accept_tells_the_other_side_why(monkeypatch):
    sent = []

    async def fake_send(user_id, event, payload):
        sent.append((user_id, event, payload))

    async def fake_publish(topic, event, payload):
        pass

    monkeypatch.setattr(manager, "send", fake_send)
    monkeypatch.setattr(manager, "publish", fake_publish)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                cust_user = User(phone_number=PHONES[0], role=UserRole.CUSTOMER, full_name="Amali")
                drv_user = User(phone_number=PHONES[1], role=UserRole.DRIVER, full_name="Nimal")
                db.add_all([cust_user, drv_user])
                await db.flush()
                customer = Customer(user_id=cust_user.id)
                driver = Driver(user_id=drv_user.id, status=DriverStatus.APPROVED, is_approved=True)
                db.add_all([customer, driver])
                await db.flush()
                by_driver = _ride("ZGTESTCN01", customer.id, driver.id, BookingStatus.ACCEPTED)
                by_customer = _ride("ZGTESTCN02", customer.id, driver.id, BookingStatus.ARRIVED)
                db.add_all([by_driver, by_customer])
                await db.commit()

                res = await update_booking_status(
                    by_driver.id,
                    BookingStatusUpdate(status=BookingStatus.CANCELLED, reason="Vehicle / mechanical issue"),
                    db, drv_user,
                )
                assert (res.cancelled_by, res.cancellation_reason) == ("driver", "Vehicle / mechanical issue")
                to_customer = [p for uid, ev, p in sent if uid == cust_user.id and ev == "booking_update"]
                assert to_customer == [{
                    "booking_id": by_driver.id, "status": "cancelled", "otp": None, "booking_ref": "ZGTESTCN01",
                    "reason": "Vehicle / mechanical issue", "cancelled_by": "driver",
                }]
                assert fcm_service._format("booking_update", to_customer[0]) == \
                    ("Ride Cancelled by Driver", "Reason: Vehicle / mechanical issue")
                assert await _notices(db, cust_user.id) == [(
                    "Ride Cancelled by Driver",
                    "Booking ZGTESTCN01 was cancelled by your driver. Reason: Vehicle / mechanical issue",
                )]
                assert await _notices(db, drv_user.id) == [], "the driver who cancelled is not told about it"

                sent.clear()
                res = await update_booking_status(
                    by_customer.id,
                    BookingStatusUpdate(status=BookingStatus.CANCELLED, reason="Changed my mind"),
                    db, cust_user,
                )
                assert res.cancelled_by == "customer"
                to_driver = [p for uid, ev, p in sent if uid == drv_user.id and ev == "booking_update"]
                assert [(p["status"], p["reason"], p["cancelled_by"]) for p in to_driver] == \
                    [("cancelled", "Changed my mind", "customer")]
                assert await _notices(db, drv_user.id) == [(
                    "Ride Cancelled by Customer",
                    "Booking ZGTESTCN02 was cancelled by customer. Reason: Changed my mind",
                )]
                assert len(await _notices(db, cust_user.id)) == 1, "the customer who cancelled gets no new notice"
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()


@pytest.mark.parametrize("payload, expected", [
    ({"status": "cancelled", "cancelled_by": "admin", "reason": "Duplicate booking"},
     ("Ride Cancelled", "Reason: Duplicate booking")),
    ({"status": "cancelled", "cancelled_by": "driver"}, ("Ride Cancelled", "The driver has cancelled the ride.")),
])
def test_push_text(payload, expected):
    assert fcm_service._format("booking_update", payload) == expected


async def test_admin_cancel_active_booking(monkeypatch):
    import json
    import sys
    sys.path.append("/app")
    from ziggo_admin_panel.routes import admin_cancel_booking
    from starlette.requests import Request

    sent = []
    published = []

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
                cust_user = User(phone_number=PHONES[0], role=UserRole.CUSTOMER, full_name="Amali")
                drv_user = User(phone_number=PHONES[1], role=UserRole.DRIVER, full_name="Nimal")
                admin_user = User(phone_number="0700000000", role=UserRole.ADMIN, full_name="Admin")
                db.add_all([cust_user, drv_user, admin_user])
                await db.flush()
                customer = Customer(user_id=cust_user.id)
                driver = Driver(user_id=drv_user.id, status=DriverStatus.APPROVED, is_approved=True)
                db.add_all([customer, driver])
                await db.flush()
                active_ride = _ride("ZGTESTCN03", customer.id, driver.id, BookingStatus.ACCEPTED)
                db.add(active_ride)
                await db.commit()

                # Mock request
                scope = {
                    "type": "http",
                    "method": "POST",
                    "headers": [(b"content-type", b"application/json")],
                }
                async def receive():
                    return {"type": "http.request", "body": json.dumps({"reason": "Customer called support"}).encode("utf-8")}
                req = Request(scope, receive)

                resp = await admin_cancel_booking(active_ride.id, req, db, admin_user)
                assert resp.status_code == 200
                data = json.loads(resp.body.decode("utf-8"))
                assert data["ok"] is True
                assert data["status"] == "cancelled"

                # Check DB status
                await db.refresh(active_ride)
                assert active_ride.status == BookingStatus.CANCELLED
                assert active_ride.cancelled_by == "admin"
                assert active_ride.cancellation_reason == "Customer called support"

                # Check customer WS event
                to_customer = [p for uid, ev, p in sent if uid == cust_user.id and ev == "booking_update"]
                assert len(to_customer) == 1
                assert to_customer[0]["status"] == "cancelled"
                assert to_customer[0]["cancelled_by"] == "admin"

                # Check driver WS event
                to_driver = [p for uid, ev, p in sent if uid == drv_user.id and ev == "booking_update"]
                assert len(to_driver) == 1
                assert to_driver[0]["status"] == "cancelled"
                assert to_driver[0]["cancelled_by"] == "admin"

                # Check notifications
                assert await _notices(db, cust_user.id) == [(
                    "Ride Cancelled by Admin",
                    "Booking ZGTESTCN03 was cancelled by Ziggo Admin. Reason: Customer called support",
                )]
                assert await _notices(db, drv_user.id) == [(
                    "Ride Cancelled by Admin",
                    "Booking ZGTESTCN03 was cancelled by Ziggo Admin. Reason: Customer called support",
                )]

                # Check admin_live publish event
                admin_events = [p for top, ev, p in published if top == "admin_live" and ev == "booking_status_update"]
                assert len(admin_events) == 1
                assert admin_events[0]["booking_id"] == active_ride.id
                assert admin_events[0]["status"] == "cancelled"

                # Test cannot cancel already cancelled booking
                resp_again = await admin_cancel_booking(active_ride.id, req, db, admin_user)
                assert resp_again.status_code == 400

            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()


async def test_admin_driver_redirect():
    import sys
    sys.path.append("/app")
    from ziggo_admin_panel.routes import admin_driver_detail_redirect
    from starlette.requests import Request

    scope = {
        "type": "http",
        "method": "GET",
        "path": "/admin/drivers/270",
        "query_string": b"return_to=%2Fadmin%2Fwithdrawals",
        "headers": [],
    }
    req = Request(scope)
    resp = await admin_driver_detail_redirect(270, req)
    assert resp.status_code == 303
    assert resp.headers["location"] == "/admin/drivers/270/edit?return_to=%2Fadmin%2Fwithdrawals"


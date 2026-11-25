"""One road route per booking leg, worked out on the server and shared by the driver and
customer apps (services/route_service.py, api/v1/booking_routes.py).

Google is replaced by a fake that records every route asked for and answers with a
straight line between the first and last point.
"""
import asyncio
import time

import pytest
from fastapi import HTTPException
from sqlalchemy import delete, select, update

import app.models  # noqa: F401  (registers every table for create_all)
from app.api.v1.booking_routes import get_booking_route
from app.api.v1.bookings import update_booking_status
from app.database import AsyncSessionLocal, Base, engine
from app.models import (
    Booking, BookingDispatchLog, BookingStatus, BookingStop, Customer, Driver, DriverStatus, User, UserRole,
)
from app.schemas import BookingStatusUpdate
from app.services import maps_service, route_service
from app.services.ws_manager import manager

PHONES = [f"07799902{i:02d}" for i in range(1, 6)]
PICKUP = (6.9147, 79.8778)   # Borella
STOP = (6.89, 79.885)
DROP = (6.8649, 79.8997)     # Nugegoda
DRIVER_AT = (6.923, 79.87)


def _encode(points):
    """Google's encoded polyline format."""
    out, last_lat, last_lng = [], 0, 0
    for lat, lng in points:
        ilat, ilng = round(lat * 1e5), round(lng * 1e5)
        for delta in (ilat - last_lat, ilng - last_lng):
            v = ~(delta << 1) if delta < 0 else delta << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        last_lat, last_lng = ilat, ilng
    return "".join(out)


class _FakeGoogle:
    def __init__(self):
        self.asked = []

    async def route(self, points):
        self.asked.append([tuple(p) for p in points])
        return {"polyline": _encode([points[0], points[-1]]), "distance_m": 1000, "duration_s": 120,
                "steps": [{"instruction": "Head south", "maneuver": "", "distance_m": 1000, "duration_s": 120,
                           "start": list(points[0]), "end": list(points[-1])}]}


def test_encode_matches_decode():
    pts = [(6.9147, 79.8778), (6.8649, 79.8997), (6.89, 79.885)]
    assert maps_service.decode_polyline(_encode(pts)) == pts


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_(PHONES))
    customers = select(Customer.id).where(Customer.user_id.in_(users))
    drivers = select(Driver.id).where(Driver.user_id.in_(users))
    await db.execute(delete(BookingDispatchLog).where(BookingDispatchLog.driver_id.in_(drivers)))
    await db.execute(delete(Booking).where(Booking.customer_id.in_(customers)))
    await db.execute(delete(Driver).where(Driver.user_id.in_(users)))
    await db.execute(delete(Customer).where(Customer.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


def _ride(ref, customer_id, status=BookingStatus.SEARCHING, driver_id=None, **extra):
    return Booking(booking_ref=ref, customer_id=customer_id, driver_id=driver_id, service_type="tuk", status=status,
                   pickup_lat=PICKUP[0], pickup_lng=PICKUP[1], pickup_address="Borella",
                   drop_lat=DROP[0], drop_lng=DROP[1], drop_address="Nugegoda", payment_method="cash", **extra)


async def test_booking_route_lifecycle(monkeypatch):
    google = _FakeGoogle()
    monkeypatch.setattr(route_service.maps_service, "route", google.route)
    sent = []

    async def fake_send(user_id, event, payload):
        sent.append((user_id, event, payload))

    async def fake_publish(*args, **kwargs):
        return None

    monkeypatch.setattr(manager, "send", fake_send)
    monkeypatch.setattr(manager, "publish", fake_publish)
    for name in ("_off_count", "_last_reroute", "_failures", "_decoded", "_locks"):
        monkeypatch.setattr(route_service, name, {})

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                users = []
                roles = [UserRole.CUSTOMER, UserRole.CUSTOMER, UserRole.DRIVER, UserRole.DRIVER, UserRole.DRIVER]
                for phone, role in zip(PHONES, roles):
                    u = User(phone_number=phone, role=role, full_name=phone)
                    db.add(u)
                    await db.flush()
                    users.append(u)
                amali_u, other_u, d1_u, d2_u, d3_u = users
                amali, other = Customer(user_id=amali_u.id), Customer(user_id=other_u.id)
                d1 = Driver(user_id=d1_u.id, status=DriverStatus.APPROVED, is_approved=True, is_online=True,
                            current_lat=DRIVER_AT[0], current_lng=DRIVER_AT[1])
                d2 = Driver(user_id=d2_u.id, status=DriverStatus.APPROVED, is_approved=True, is_online=True,
                            current_lat=6.95, current_lng=79.9)
                d3 = Driver(user_id=d3_u.id, status=DriverStatus.APPROVED, is_approved=True, is_online=False)
                db.add_all([amali, other, d1, d2, d3])
                await db.flush()
                ride = _ride("ZGTESTRT01", amali.id, stop_count=1)
                db.add(ride)
                await db.flush()
                db.add(BookingStop(booking_id=ride.id, order_index=1, lat=STOP[0], lng=STOP[1], address="Kirulapone"))
                await db.commit()

                # Who may see the route
                assert await route_service.can_see(db, ride, amali_u)
                assert not await route_service.can_see(db, ride, other_u)
                assert await route_service.can_see(db, ride, d1_u), "an online driver may preview a searching ride"
                assert not await route_service.can_see(db, ride, d3_u), "an offline driver who wasn't offered it may not"
                db.add(BookingDispatchLog(booking_id=ride.id, driver_id=d3.id))
                await db.commit()
                assert await route_service.can_see(db, ride, d3_u), "a driver it was offered to may"
                with pytest.raises(HTTPException) as e:
                    await get_booking_route(ride.id, db, other_u)
                assert e.value.status_code == 403

                # The request popup: one trip route for every driver shown the request
                first = await get_booking_route(ride.id, db, d1_u)
                assert first["leg"] == "trip" and first["route"] and first["version"] == 1
                assert google.asked == [[PICKUP, STOP, DROP]]
                assert await get_booking_route(ride.id, db, d3_u) == first
                assert len(google.asked) == 1

                # Accepted: driver -> pickup, worked out once for both apps
                ride.status, ride.driver_id = BookingStatus.ACCEPTED, d1.id
                ride.driver_accepted_lat, ride.driver_accepted_lng = DRIVER_AT
                await db.commit()
                assert not await route_service.can_see(db, ride, d2_u), "once accepted, only its own driver"
                to_pickup = await get_booking_route(ride.id, db, amali_u)
                assert to_pickup["leg"] == "to_pickup" and to_pickup["route"] and to_pickup["version"] == 2
                assert google.asked[-1] == [DRIVER_AT, PICKUP]
                assert await get_booking_route(ride.id, db, d1_u) == to_pickup
                assert len(google.asked) == 2

                # Off route: two updates in a row more than 60 m away
                on_route = (6.91885, 79.8739)
                off_route = (6.92085, 79.8739)  # about 150 m from the line
                await route_service.check_off_route(db, d1, *on_route)
                await route_service.check_off_route(db, d1, *off_route)
                assert not route_service._tasks, "one update off the route is not enough"
                d1.current_lat, d1.current_lng = off_route
                await db.commit()
                await route_service.check_off_route(db, d1, *off_route)
                assert len(route_service._tasks) == 1
                await asyncio.gather(*list(route_service._tasks))
                await db.refresh(ride)
                live = ride.trip_route["live"]
                assert (live["leg"], live["reroutes"], ride.trip_route["version"]) == ("to_pickup", 1, 3)
                assert google.asked[-1] == [off_route, PICKUP], "the new route starts where the driver is"
                assert sorted((u, p["version"]) for u, ev, p in sent if ev == "route_changed") == \
                    sorted([(d1_u.id, 3), (amali_u.id, 3)])

                asked = len(google.asked)
                for _ in range(3):
                    await route_service.check_off_route(db, d1, 6.93, 79.88)
                assert not route_service._tasks and len(google.asked) == asked, "at most one new route a minute"
                route_service._last_reroute[ride.id] = time.monotonic() - 61
                await db.execute(update(Booking).where(Booking.id == ride.id).values(trip_route={
                    **ride.trip_route, "live": {**live, "reroutes": route_service.MAX_REROUTES}}))
                await db.commit()
                await db.refresh(ride)
                await route_service.check_off_route(db, d1, 6.93, 79.88)
                await route_service.check_off_route(db, d1, 6.93, 79.88)
                assert not route_service._tasks, "no more than MAX_REROUTES per leg"

                # A driver still finishing another trip: no route to the next pickup yet
                busy = _ride("ZGTESTRT02", other.id, status=BookingStatus.STARTED, driver_id=d2.id)
                queued = _ride("ZGTESTRT03", amali.id, status=BookingStatus.ACCEPTED, driver_id=d2.id)
                db.add_all([busy, queued])
                await db.commit()
                waiting = await get_booking_route(queued.id, db, d2_u)
                assert (waiting["leg"], waiting["route"]) == ("to_pickup", None)
                assert len(google.asked) == asked

                # Arrived: the stored route is kept and nothing is asked
                d1.current_lat, d1.current_lng = 6.9148, 79.8779  # at the pickup
                await db.commit()
                await update_booking_status(ride.id, BookingStatusUpdate(status=BookingStatus.ARRIVED), db, d1_u)
                await db.refresh(ride)
                arrived = await get_booking_route(ride.id, db, amali_u)
                assert arrived["leg"] == "to_pickup" and arrived["route"] == ride.trip_route["live"]["route"]
                assert len(google.asked) == asked

                # Started at the pickup: the trip route from the popup is reused
                version = ride.trip_route["version"]
                resp = await update_booking_status(
                    ride.id, BookingStatusUpdate(status=BookingStatus.STARTED, otp=ride.otp), db, d1_u)
                await db.refresh(ride)
                assert ride.trip_route["live"] is None and ride.trip_route["version"] == version + 1
                assert resp.route_version == version + 1, "the 5-second polls see the change"
                trip = await get_booking_route(ride.id, db, amali_u)
                assert trip["leg"] == "to_drop" and trip["route"] == first["route"]
                assert len(google.asked) == asked

                # A new destination drops the routes and tells both apps
                sent.clear()
                route_service.destination_changed(ride)
                await db.commit()
                await route_service.tell_apps(db, ride)
                assert ride.trip_route["trip"] is None and ride.trip_route["live"] is None
                assert sorted((u, ev) for u, ev, p in sent) == sorted([(d1_u.id, "route_changed"),
                                                                        (amali_u.id, "route_changed")])
                d1.current_lat, d1.current_lng = 6.905, 79.88  # away from the pickup now
                await db.commit()
                again = await get_booking_route(ride.id, db, d1_u)
                assert again["leg"] == "to_drop" and google.asked[-1] == [(6.905, 79.88), STOP, DROP]

                # Finished trips keep no route
                queued.status = BookingStatus.CANCELLED
                route_service.after_status_change(queued)
                assert queued.trip_route is None
                await db.execute(update(Booking).where(Booking.id == busy.id).values(
                    status=BookingStatus.COMPLETED, trip_route={"version": 1, "trip": None, "live": None}))
                await db.commit()
                assert await route_service.forget_finished(db) >= 1
                kept = dict((await db.execute(
                    select(Booking.booking_ref, Booking.trip_route).where(Booking.booking_ref.like("ZGTESTRT0%"))
                )).all())
                assert kept["ZGTESTRT02"] is None, "a finished trip's route is deleted"
                assert kept["ZGTESTRT01"] is not None, "a trip under way keeps its route"
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()

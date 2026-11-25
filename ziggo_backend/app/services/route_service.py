"""One road route per booking leg, worked out on this server and shared by the driver
and customer apps. They used to ask Google again every time the driver moved 20 m;
now the phones shrink the line themselves and a new route is fetched only when the
driver really leaves it (check_off_route).

bookings.trip_route = {
    "version": n,   # goes up whenever the route the apps draw changes
    "trip": route,  # pickup -> stops -> drop: shown in the driver's request popup, and
                    # reused for the trip when the driver starts at the pickup
    "live": {"leg": "to_pickup" | "to_drop", "route": route, "reroutes": n},
}
A route is {polyline, distance_m, duration_s, steps} from maps_service.route.

Kept only while the trip is on (Google's terms allow keeping coordinates for a limited
time): cleared when it completes or is cancelled (after_status_change), and by the
auto-cancel sweep (forget_finished) for every other way a booking ends.
"""
import asyncio
import time
from typing import Optional

from sqlalchemy import case, null, select, update

from ..database import AsyncSessionLocal
from ..models import Booking, BookingDispatchLog, BookingStatus, BookingStop, Customer, Driver, DriverStatus, User, UserRole
from . import maps_service
from .fare_service import haversine_km
from .ws_manager import manager

LEGS = {
    BookingStatus.ACCEPTED: "to_pickup",
    BookingStatus.ARRIVED: "to_pickup",
    BookingStatus.STARTED: "to_drop",
}
ACTIVE = (BookingStatus.SEARCHING, BookingStatus.ACCEPTED, BookingStatus.ARRIVED, BookingStatus.STARTED)
# No "request" or "cancel" in the name: the driver app treats events named like that
# as ride requests or cancellations. Not mapped in fcm_service, so it sends no push.
EVENT = "route_changed"

AT_POINT_KM = 0.05            # closer than this to where it's going: nothing to draw
START_AT_PICKUP_KM = 0.2      # starting the trip this close to the pickup reuses the trip route
OFF_ROUTE_M = 60
OFF_ROUTE_UPDATES = 2         # location updates in a row (the driver app sends one every 10 s)
REROUTE_GAP_SECONDS = 60
MAX_REROUTES = 15             # per leg
RETRY_AFTER_FAILURE_SECONDS = 30

_locks: dict[int, asyncio.Lock] = {}
_off_count: dict[int, int] = {}
_last_reroute: dict[int, float] = {}
_failures: dict[tuple[int, str], float] = {}
_decoded: dict[int, tuple[int, list]] = {}
_tasks: set = set()


def version(b: Booking) -> int:
    return int((b.trip_route or {}).get("version") or 0)


def _lock(booking_id: int) -> asyncio.Lock:
    if len(_locks) > 5000:
        for key in [k for k, lock in _locks.items() if not lock.locked()]:
            _locks.pop(key, None)
    return _locks.setdefault(booking_id, asyncio.Lock())


def _forget(booking_id: int) -> None:
    _off_count.pop(booking_id, None)
    _last_reroute.pop(booking_id, None)
    _decoded.pop(booking_id, None)
    for key in [k for k in _failures if k[0] == booking_id]:
        _failures.pop(key, None)


def _recently_failed(booking_id: int, leg: str) -> bool:
    at = _failures.get((booking_id, leg))
    return at is not None and time.monotonic() - at < RETRY_AFTER_FAILURE_SECONDS


def _point(lat, lng) -> Optional[tuple[float, float]]:
    if lat is None or lng is None:
        return None
    return float(lat), float(lng)


def _km(a: tuple[float, float], b: tuple[float, float]) -> float:
    return haversine_km(a[0], a[1], b[0], b[1])


async def _stops(db, b: Booking, remaining_only: bool = False) -> list[tuple[float, float]]:
    q = await db.execute(
        select(BookingStop).where(BookingStop.booking_id == b.id).order_by(BookingStop.order_index)
    )
    stops = [s for s in q.scalars().all() if s.lat is not None and s.lng is not None]
    if remaining_only:
        stops = [s for s in stops if s.departed_at is None]
    return [(float(s.lat), float(s.lng)) for s in stops]


async def _driver_point(db, b: Booking) -> Optional[tuple[float, float]]:
    if b.driver_id:
        q = await db.execute(select(Driver.current_lat, Driver.current_lng).where(Driver.id == b.driver_id))
        row = q.first()
        if row and row[0] is not None and row[1] is not None:
            return float(row[0]), float(row[1])
    return _point(b.driver_accepted_lat, b.driver_accepted_lng)


async def _finishing_prior_trip(db, b: Booking) -> bool:
    """Same rule as the booking response's is_driver_completing_prior_trip."""
    if not b.driver_id or b.status != BookingStatus.ACCEPTED:
        return False
    q = await db.execute(
        select(Booking.id).where(
            Booking.driver_id == b.driver_id,
            Booking.id != b.id,
            Booking.status.in_((BookingStatus.STARTED, BookingStatus.ARRIVED)),
        ).limit(1)
    )
    return q.scalars().first() is not None


def _answer(b: Booking, leg: Optional[str], route: Optional[dict]) -> dict:
    return {"booking_id": b.id, "version": version(b), "leg": leg, "route": route}


def _store_live(b: Booking, leg: str, route: dict, reroutes: int) -> None:
    data = dict(b.trip_route or {})
    data["live"] = {"leg": leg, "route": route, "reroutes": reroutes}
    data["version"] = int(data.get("version") or 0) + 1
    b.trip_route = data


async def can_see(db, b: Booking, user: User) -> bool:
    """The booking's customer, its driver, an admin, or, while it is still looking for
    a driver, a driver it can be offered to (the request already shows them the
    addresses)."""
    q = await db.execute(select(Customer.id).where(Customer.user_id == user.id))
    customer_id = q.scalars().first()
    if customer_id is not None and b.customer_id == customer_id:
        return True
    q = await db.execute(select(Driver).where(Driver.user_id == user.id))
    driver = q.scalars().first()
    if driver is not None:
        if b.driver_id == driver.id:
            return True
        if b.status == BookingStatus.SEARCHING:
            if driver.is_online and driver.status == DriverStatus.APPROVED:
                return True
            q = await db.execute(
                select(BookingDispatchLog.id).where(
                    BookingDispatchLog.booking_id == b.id,
                    BookingDispatchLog.driver_id == driver.id,
                ).limit(1)
            )
            if q.scalars().first() is not None:
                return True
    return user.role == UserRole.ADMIN


async def _trip_points(db, b: Booking) -> Optional[list[tuple[float, float]]]:
    pickup = _point(b.pickup_lat, b.pickup_lng)
    drop = _point(b.drop_lat, b.drop_lng)
    if pickup is None or drop is None:
        return None
    stops = await _stops(db, b)
    if not stops and _km(pickup, drop) < AT_POINT_KM:
        return None  # e.g. a rental with no destination
    return [pickup, *stops, drop]


async def _work_out_leg(db, b: Booking, leg: str) -> Optional[dict]:
    if _recently_failed(b.id, leg):
        return None
    origin = await _driver_point(db, b)
    pickup = _point(b.pickup_lat, b.pickup_lng)
    drop = _point(b.drop_lat, b.drop_lng)
    if pickup is None or drop is None:
        return None
    if leg == "to_pickup":
        if origin is None or _km(origin, pickup) < AT_POINT_KM:
            return None
        points = [origin, pickup]
    else:
        all_stops = await _stops(db, b)
        stops_left = await _stops(db, b, remaining_only=True)
        trip = (b.trip_route or {}).get("trip")
        at_pickup = origin is None or _km(origin, pickup) <= START_AT_PICKUP_KM
        if trip and at_pickup and len(stops_left) == len(all_stops):
            return trip
        start = origin or pickup
        if not stops_left and _km(start, drop) < AT_POINT_KM:
            return None
        points = [start, *stops_left, drop]
    found = await maps_service.route(points)
    if found is None:
        _failures[(b.id, leg)] = time.monotonic()
    return found


async def route_for(db, b: Booking) -> dict:
    """The route the apps should draw for this booking now, worked out at most once per
    leg: {"booking_id", "version", "leg": "trip" | "to_pickup" | "to_drop" | None, "route"}."""
    async with _lock(b.id):
        await db.refresh(b)
        data = b.trip_route or {}
        if b.status == BookingStatus.SEARCHING:
            trip = data.get("trip")
            if not trip and not _recently_failed(b.id, "trip"):
                points = await _trip_points(db, b)
                trip = await maps_service.route(points) if points else None
                if trip:
                    b.trip_route = {**data, "trip": trip, "version": version(b) + 1}
                    await db.commit()
                elif points:
                    _failures[(b.id, "trip")] = time.monotonic()
            return _answer(b, "trip", trip)

        leg = LEGS.get(b.status)
        if leg is None:
            return _answer(b, None, None)
        live = data.get("live") or {}
        if live.get("leg") == leg and live.get("route"):
            return _answer(b, leg, live["route"])
        if b.status == BookingStatus.ARRIVED:
            return _answer(b, leg, None)  # the driver is at the pickup: nothing new to draw
        if leg == "to_pickup" and await _finishing_prior_trip(db, b):
            return _answer(b, leg, None)  # worked out once the prior trip ends
        found = await _work_out_leg(db, b, leg)
        if found is None:
            return _answer(b, leg, None)
        _store_live(b, leg, found, reroutes=0)
        await db.commit()
        return _answer(b, leg, found)


def after_status_change(b: Booking) -> None:
    """Called by update_booking_status before it commits: a finished trip keeps no
    route, and a started trip gets its new leg on the apps' next request."""
    if b.status not in ACTIVE:
        if b.trip_route is not None:
            b.trip_route = None
        _forget(b.id)
    elif b.status == BookingStatus.STARTED and (b.trip_route or {}).get("live"):
        data = dict(b.trip_route)
        data["live"] = None
        data["version"] = int(data.get("version") or 0) + 1
        b.trip_route = data
        _forget(b.id)


def destination_changed(b: Booking) -> None:
    """Called before the new destination is committed: drop the routes it changes."""
    if not b.trip_route:
        return
    data = dict(b.trip_route)
    data["trip"] = None
    if (data.get("live") or {}).get("leg") == "to_drop":
        data["live"] = None
    data["version"] = int(data.get("version") or 0) + 1
    b.trip_route = data
    _forget(b.id)


async def tell_apps(db, b: Booking) -> None:
    """Tell the driver's and customer's apps to fetch the booking's route again."""
    if not version(b):
        return
    user_ids = []
    if b.driver_id:
        q = await db.execute(select(Driver.user_id).where(Driver.id == b.driver_id))
        user_ids.append(q.scalars().first())
    if b.customer_id:
        q = await db.execute(select(Customer.user_id).where(Customer.id == b.customer_id))
        user_ids.append(q.scalars().first())
    payload = {"booking_id": b.id, "version": version(b)}
    for user_id in user_ids:
        if user_id:
            await manager.send(user_id, EVENT, payload)


def _route_points(booking_id: int, ver: int, route: dict) -> list:
    hit = _decoded.get(booking_id)
    if hit and hit[0] == ver:
        return hit[1]
    points = maps_service.decode_polyline(route.get("polyline") or "")
    _decoded[booking_id] = (ver, points)
    return points


async def check_off_route(db, driver: Driver, lat: float, lng: float) -> None:
    """Called on every driver location update. When the driver has been more than
    OFF_ROUTE_M from the drawn route on OFF_ROUTE_UPDATES updates in a row, a new route
    is worked out in the background (at most once a minute, MAX_REROUTES per leg)."""
    q = await db.execute(
        select(Booking)
        .where(
            Booking.driver_id == driver.id,
            Booking.status.in_((BookingStatus.STARTED, BookingStatus.ACCEPTED)),
            Booking.trip_route.isnot(None),
        )
        .order_by(case((Booking.status == BookingStatus.STARTED, 0), else_=1), Booking.id)
        .limit(1)
    )
    b = q.scalars().first()
    if b is None:
        return
    data = b.trip_route or {}
    live = data.get("live") or {}
    leg = LEGS.get(b.status)
    route = live.get("route")
    if not route or live.get("leg") != leg:
        return
    points = _route_points(b.id, int(data.get("version") or 0), route)
    if maps_service.distance_to_route_m(lat, lng, points) <= OFF_ROUTE_M:
        _off_count.pop(b.id, None)
        return
    count = _off_count.get(b.id, 0) + 1
    _off_count[b.id] = count
    if count < OFF_ROUTE_UPDATES or int(live.get("reroutes") or 0) >= MAX_REROUTES:
        return
    now = time.monotonic()
    last = _last_reroute.get(b.id)
    if last is not None and now - last < REROUTE_GAP_SECONDS:
        return
    _last_reroute[b.id] = now
    _off_count.pop(b.id, None)
    task = asyncio.create_task(_reroute(b.id, leg))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def _reroute(booking_id: int, leg: str) -> None:
    try:
        async with AsyncSessionLocal() as db:
            async with _lock(booking_id):
                q = await db.execute(select(Booking).where(Booking.id == booking_id))
                b = q.scalars().first()
                if b is None or LEGS.get(b.status) != leg:
                    return
                live = (b.trip_route or {}).get("live") or {}
                if live.get("leg") != leg:
                    return
                origin = await _driver_point(db, b)
                pickup = _point(b.pickup_lat, b.pickup_lng)
                drop = _point(b.drop_lat, b.drop_lng)
                if origin is None or pickup is None or drop is None:
                    return
                if leg == "to_pickup":
                    points = [origin, pickup]
                else:
                    points = [origin, *await _stops(db, b, remaining_only=True), drop]
                if _km(origin, points[-1]) < AT_POINT_KM and len(points) == 2:
                    return
                found = await maps_service.route(points)
                if found is None:
                    return
                _store_live(b, leg, found, reroutes=int(live.get("reroutes") or 0) + 1)
                await db.commit()
                await tell_apps(db, b)
    except Exception as e:
        print(f"[route] re-route of booking {booking_id} failed: {e!r}")


async def forget_finished(db) -> int:
    """Auto-cancel sweep: delete the routes of bookings that are no longer on."""
    res = await db.execute(
        update(Booking)
        .where(Booking.trip_route.isnot(None), Booking.status.notin_(ACTIVE))
        .values(trip_route=null())
        .execution_options(synchronize_session=False)
    )
    await db.commit()
    if len(_off_count) > 2000 or len(_last_reroute) > 2000 or len(_decoded) > 2000 or len(_failures) > 2000:
        _off_count.clear()
        _last_reroute.clear()
        _decoded.clear()
        _failures.clear()
    return res.rowcount

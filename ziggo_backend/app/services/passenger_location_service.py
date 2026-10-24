"""Customer live location for the driver and the admin map (Phase 2, feature 01).

Sharing is per booking and off until the customer turns it on in the app. Only the
latest point is kept, on the booking itself, and only while the ride waits for its
pickup (searching, accepted, arrived). It is wiped when the customer stops sharing,
the trip starts or ends, or no new point has arrived for FORGET_AFTER_MINUTES.
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, update

from ..models import Booking, BookingStatus

PRE_PICKUP = (BookingStatus.SEARCHING, BookingStatus.ACCEPTED, BookingStatus.ARRIVED)
DRIVER_SEES = (BookingStatus.ACCEPTED, BookingStatus.ARRIVED)
LIVE_SECONDS = 60           # an older point is never shown as live
FORGET_AFTER_MINUTES = 10   # an older point is deleted by the auto-cancel sweep
MIN_INTERVAL_SECONDS = 2    # points closer together than this are ignored

ADMIN_TOPIC = "admin_customers"
CUSTOMER_MAP_ROLES = ("superadmin", "admin")

RIDES_ONLY = "Live location sharing is for rides only."
TRIP_UNDERWAY = "Location sharing ends once the trip starts."

CLEARED = {
    "passenger_sharing": False,
    "passenger_lat": None,
    "passenger_lng": None,
    "passenger_location_at": None,
}


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def clear(booking) -> bool:
    """Wipe the customer's point. True if there was one, so the driver can be told."""
    had = bool(booking.passenger_sharing or booking.passenger_location_at)
    for field, value in CLEARED.items():
        setattr(booking, field, value)
    return had


def too_soon(booking, now: datetime) -> bool:
    at = booking.passenger_location_at
    return bool(booking.passenger_sharing and at and (now - _aware(at)).total_seconds() < MIN_INTERVAL_SECONDS)


def live_point(booking, now: datetime | None = None) -> dict | None:
    """The customer's point while it is fresh enough to show as live, else None."""
    at = booking.passenger_location_at
    if not booking.passenger_sharing or booking.status not in PRE_PICKUP or at is None or booking.passenger_lat is None:
        return None
    at = _aware(at)
    if ((now or datetime.now(timezone.utc)) - at).total_seconds() > LIVE_SECONDS:
        return None
    return {"lat": float(booking.passenger_lat), "lng": float(booking.passenger_lng), "at": at.isoformat()}


async def forget_stale(db) -> int:
    """Delete points from trips that have moved on, or that stopped updating."""
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=FORGET_AFTER_MINUTES)
    res = await db.execute(
        update(Booking)
        .where(
            or_(Booking.passenger_sharing == True, Booking.passenger_location_at.isnot(None)),  # noqa: E712
            or_(Booking.status.notin_(PRE_PICKUP), Booking.passenger_location_at < cutoff),
        )
        .values(**CLEARED)
        .execution_options(synchronize_session=False)
    )
    await db.commit()
    return res.rowcount

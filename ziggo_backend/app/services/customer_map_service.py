"""Admin Customer Map (Phase 2, feature 01).

Active trips are drawn where the customer is now: the point she or he shares
while waiting for pickup (while fresh), else the pickup, or the driver's
position once the trip is under way. Every other customer who has booked is
drawn at the pickup of her or his latest booking, coloured by a 0-100 score of
how recently she or he last completed a ride: 100 today, falling a little each
day to 0 at SCORE_DAYS days (or never). The feed carries no phone numbers; each
phone an admin reveals is logged.
"""
from datetime import datetime, timedelta, timezone

from sqlalchemy import func, or_, select

from ..models import AdminPhoneReveal, Booking, BookingStatus, Customer, Driver, User
from . import passenger_location_service

SCORE_DAYS = 60
ACTIVE = (BookingStatus.SEARCHING, BookingStatus.ACCEPTED, BookingStatus.ARRIVED, BookingStatus.STARTED)
_LK = timezone(timedelta(hours=5, minutes=30))


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _iso(dt: datetime | None) -> str | None:
    return _aware(dt).isoformat() if dt else None


def recency_score(last_ride_at: datetime | None, now: datetime) -> int:
    """100 if the last completed ride was today (Sri Lanka time), 0 at SCORE_DAYS days or never."""
    if last_ride_at is None:
        return 0
    days = (now.astimezone(_LK).date() - _aware(last_ride_at).astimezone(_LK).date()).days
    return max(0, min(100, round(100 * (1 - days / SCORE_DAYS))))


async def active_trips(db, now: datetime) -> list[dict]:
    """Bookings under way or waiting for pickup. Scheduled rides count once dispatch starts."""
    rows = (await db.execute(
        select(Booking, User.full_name, Driver.current_lat, Driver.current_lng, Driver.last_location_update)
        .join(Customer, Customer.id == Booking.customer_id)
        .join(User, User.id == Customer.user_id)
        .outerjoin(Driver, Driver.id == Booking.driver_id)
        .where(
            Booking.status.in_(ACTIVE),
            or_(Booking.scheduled_at.is_(None), Booking.scheduled_dispatch_sent == True),  # noqa: E712
        )
        .order_by(Booking.id)
    )).all()
    trips = []
    for b, name, d_lat, d_lng, d_seen in rows:
        lat, lng, source, at = float(b.pickup_lat), float(b.pickup_lng), "pickup", None
        if b.status == BookingStatus.STARTED:
            if d_lat is not None and d_lng is not None:
                lat, lng, source, at = float(d_lat), float(d_lng), "driver", _iso(d_seen)
        else:
            live = passenger_location_service.live_point(b, now)
            if live:
                lat, lng, source, at = live["lat"], live["lng"], "live", live["at"]
        trips.append({
            "booking_id": b.id,
            "booking_ref": b.booking_ref,
            "customer_id": b.customer_id,
            "name": name or "Customer",
            "status": b.status.value,
            "service_type": b.service_type,
            "is_parcel": bool(b.is_flash or b.is_courier),
            "pickup_address": b.pickup_address,
            "lat": lat,
            "lng": lng,
            "source": source,
            "at": at,
        })
    return trips


async def customer_dots(db, now: datetime) -> dict:
    """Every customer who has booked, at the pickup of the latest booking, with the score.
    The page hides the ones that also have an active trip."""
    latest = (
        select(Booking.customer_id.label("cid"), func.max(Booking.id).label("bid"))
        .where(Booking.customer_id.isnot(None))
        .group_by(Booking.customer_id)
        .subquery()
    )
    last_ride = (
        select(
            Booking.customer_id.label("cid"),
            func.max(func.coalesce(Booking.completed_at, Booking.booked_at)).label("done"),
        )
        .where(
            Booking.status == BookingStatus.COMPLETED,
            Booking.is_flash.isnot(True),
            Booking.is_courier.isnot(True),
        )
        .group_by(Booking.customer_id)
        .subquery()
    )
    rows = (await db.execute(
        select(
            Customer.id, User.full_name, Booking.booking_ref, Booking.status, Booking.booked_at,
            Booking.pickup_lat, Booking.pickup_lng, last_ride.c.done,
        )
        .join(User, User.id == Customer.user_id)
        .join(latest, latest.c.cid == Customer.id)
        .join(Booking, Booking.id == latest.c.bid)
        .outerjoin(last_ride, last_ride.c.cid == Customer.id)
        .order_by(Customer.id)
    )).all()
    total = (await db.execute(select(func.count(Customer.id)))).scalar() or 0

    dots, bands = [], {"recent": 0, "lapsing": 0, "inactive": 0}
    for cid, name, ref, status, booked_at, lat, lng, done in rows:
        if lat is None or lng is None:
            continue
        score = recency_score(done, now)
        bands["recent" if score >= 67 else "lapsing" if score >= 34 else "inactive"] += 1
        dots.append({
            "id": cid,
            "name": name or "Customer",
            "lat": float(lat),
            "lng": float(lng),
            "score": score,
            "last_ride_at": _iso(done),
            "booking_ref": ref,
            "booking_status": status.value if status else None,
            "booked_at": _iso(booked_at),
        })
    return {
        "customers": dots,
        "totals": {
            "customers": total,
            "booked": len(rows),
            "never_booked": max(0, total - len(rows)),
            **bands,
        },
    }


async def reveal_phone(db, admin: User, customer_id: int, booking_id: int | None = None) -> dict | None:
    """The customer's phone, after writing who asked for it to the log. None if no such customer."""
    row = (await db.execute(
        select(User.full_name, User.phone_number)
        .join(Customer, Customer.user_id == User.id)
        .where(Customer.id == customer_id)
    )).first()
    if row is None:
        return None
    if booking_id is not None:
        owner = (await db.execute(select(Booking.customer_id).where(Booking.id == booking_id))).scalar()
        if owner != customer_id:
            booking_id = None
    db.add(AdminPhoneReveal(
        admin_user_id=admin.id,
        admin_name=admin.full_name or admin.phone_number,
        customer_id=customer_id,
        customer_name=row.full_name,
        booking_id=booking_id,
    ))
    await db.commit()
    return {"customer_id": customer_id, "name": row.full_name or "Customer", "phone": row.phone_number}


async def recent_reveals(db, limit: int = 50) -> list[dict]:
    rows = (await db.execute(
        select(AdminPhoneReveal, Booking.booking_ref)
        .outerjoin(Booking, Booking.id == AdminPhoneReveal.booking_id)
        .order_by(AdminPhoneReveal.id.desc())
        .limit(limit)
    )).all()
    return [
        {
            "at": r.created_at,
            "admin": r.admin_name or "Admin",
            "customer": r.customer_name or "Customer",
            "customer_id": r.customer_id,
            "booking_ref": ref,
        }
        for r, ref in rows
    ]

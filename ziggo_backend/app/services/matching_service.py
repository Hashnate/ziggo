"""Driver matching: pick the nearest online + approved driver of the right vehicle type."""
from typing import List, Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ..models import (
    Driver,
    DriverStatus,
    Booking,
    BookingStatus,
    FoodOrder,
    FoodOrderStatus,
    MarketOrder,
    MarketOrderStatus,
)
from .fare_service import haversine_km


_ACTIVE_RIDE = (BookingStatus.ACCEPTED, BookingStatus.ARRIVED, BookingStatus.STARTED)
_DONE_FOOD = (FoodOrderStatus.DELIVERED, FoodOrderStatus.CANCELLED)
_DONE_MARKET = (MarketOrderStatus.DELIVERED, MarketOrderStatus.CANCELLED)


async def busy_driver_ids(db: AsyncSession) -> set[int]:
    """Drivers currently on any job. Kept for food/market or general checks."""
    ids: set[int] = set()
    q = await db.execute(
        select(Booking.driver_id).where(
            Booking.driver_id.is_not(None),
            Booking.status.in_(_ACTIVE_RIDE),
        )
    )
    ids.update(i for i in q.scalars().all() if i is not None)
    q = await db.execute(
        select(FoodOrder.driver_id).where(
            FoodOrder.driver_id.is_not(None),
            FoodOrder.status.not_in(_DONE_FOOD),
        )
    )
    ids.update(i for i in q.scalars().all() if i is not None)
    q = await db.execute(
        select(MarketOrder.driver_id).where(
            MarketOrder.driver_id.is_not(None),
            MarketOrder.status.not_in(_DONE_MARKET),
        )
    )
    ids.update(i for i in q.scalars().all() if i is not None)
    return ids


async def strictly_busy_driver_ids(db: AsyncSession) -> set[int]:
    """Drivers who CANNOT be offered any ride under any circumstances:
    - Busy with Food or Market deliveries
    - Heading to pickup or at pickup (ACCEPTED or ARRIVED)
    - Already holding 2 active bookings (1 active trip + 1 queued trip)
    """
    from sqlalchemy import func
    ids: set[int] = set()

    # Food orders
    q_food = await db.execute(
        select(FoodOrder.driver_id).where(
            FoodOrder.driver_id.is_not(None),
            FoodOrder.status.not_in(_DONE_FOOD),
        )
    )
    ids.update(i for i in q_food.scalars().all() if i is not None)

    # Market orders
    q_market = await db.execute(
        select(MarketOrder.driver_id).where(
            MarketOrder.driver_id.is_not(None),
            MarketOrder.status.not_in(_DONE_MARKET),
        )
    )
    ids.update(i for i in q_market.scalars().all() if i is not None)

    # Drivers in ACCEPTED or ARRIVED (not mid-trip yet)
    q_pre_trip = await db.execute(
        select(Booking.driver_id).where(
            Booking.driver_id.is_not(None),
            Booking.status.in_((BookingStatus.ACCEPTED, BookingStatus.ARRIVED)),
        )
    )
    ids.update(i for i in q_pre_trip.scalars().all() if i is not None)

    # Drivers with 2 or more active rides (already full queue)
    q_multi = await db.execute(
        select(Booking.driver_id)
        .where(
            Booking.driver_id.is_not(None),
            Booking.status.in_(_ACTIVE_RIDE),
        )
        .group_by(Booking.driver_id)
        .having(func.count(Booking.id) >= 2)
    )
    ids.update(i for i in q_multi.scalars().all() if i is not None)

    return ids


async def get_mid_trip_drivers(db: AsyncSession) -> dict[int, Booking]:
    """Return a mapping of {driver_id: current_booking} for drivers who are
    currently in-progress with a passenger (BookingStatus.STARTED) and are
    eligible for a back-to-back queued ride."""
    strictly_busy = await strictly_busy_driver_ids(db)
    q = await db.execute(
        select(Booking).where(
            Booking.driver_id.is_not(None),
            Booking.status == BookingStatus.STARTED,
        )
    )
    bookings = q.scalars().all()
    mid_trip: dict[int, Booking] = {}
    for b in bookings:
        if b.driver_id and b.driver_id not in strictly_busy:
            mid_trip[b.driver_id] = b
    return mid_trip


async def can_driver_accept_ride(db: AsyncSession, driver_id: int) -> tuple[bool, bool, str]:
    """Check if a driver can accept a ride.
    Returns: (allowed: bool, is_back_to_back: bool, reason: str)
    """
    # Food orders
    q_food = await db.execute(
        select(FoodOrder.id).where(
            FoodOrder.driver_id == driver_id,
            FoodOrder.status.not_in(_DONE_FOOD),
        )
    )
    if q_food.scalars().first():
        return False, False, "Finish your active food delivery before accepting another job"

    # Market orders
    q_market = await db.execute(
        select(MarketOrder.id).where(
            MarketOrder.driver_id == driver_id,
            MarketOrder.status.not_in(_DONE_MARKET),
        )
    )
    if q_market.scalars().first():
        return False, False, "Finish your active market delivery before accepting another job"

    # Active bookings
    q_rides = await db.execute(
        select(Booking).where(
            Booking.driver_id == driver_id,
            Booking.status.in_(_ACTIVE_RIDE),
        )
    )
    active_rides = q_rides.scalars().all()

    if not active_rides:
        # Idle driver
        return True, False, ""

    if len(active_rides) >= 2:
        return False, False, "You already have an active trip and a queued ride"

    single_ride = active_rides[0]
    if single_ride.status == BookingStatus.STARTED:
        # Mid-trip with passenger! Eligible for back-to-back queue.
        return True, True, ""
    elif single_ride.status in (BookingStatus.ACCEPTED, BookingStatus.ARRIVED):
        return False, False, "Finish picking up your passenger before accepting another ride"

    return False, False, "Finish your current trip before accepting another ride"


async def find_nearest_driver(
    db: AsyncSession,
    pickup_lat: float,
    pickup_lng: float,
    vehicle_type: str,
    max_distance_km: float = 10.0,
    exclude_driver_id: Optional[int] = None,
) -> Optional[Driver]:
    q = await db.execute(
        select(Driver).where(
            Driver.is_online == True,  # noqa: E712
            Driver.status == DriverStatus.APPROVED,
            Driver.vehicle_type == vehicle_type,
        )
    )
    candidates = q.scalars().all()
    busy = await busy_driver_ids(db)

    nearest: Optional[Driver] = None
    nearest_dist = float("inf")
    skipped_no_loc = 0
    too_far = 0
    for d in candidates:
        if exclude_driver_id is not None and d.id == exclude_driver_id:
            continue
        if d.id in busy:
            continue
        if d.current_lat is None or d.current_lng is None:
            skipped_no_loc += 1
            continue
        dist = haversine_km(
            pickup_lat, pickup_lng, float(d.current_lat), float(d.current_lng)
        )
        if dist > max_distance_km:
            too_far += 1
            continue
        if dist < nearest_dist:
            nearest = d
            nearest_dist = dist
    print(
        f"[match] type={vehicle_type} candidates={len(candidates)} "
        f"no_location={skipped_no_loc} too_far(>{max_distance_km}km)={too_far} "
        f"→ driver_id={nearest.id if nearest else None} "
        f"dist={'%.2f' % nearest_dist if nearest else '-'}km"
    )
    return nearest


async def find_all_nearby_drivers(
    db: AsyncSession,
    pickup_lat: float,
    pickup_lng: float,
    vehicle_type: Optional[str] = None,
    max_distance_km: float = 10.0,
    exclude_driver_id: Optional[int] = None,
    allow_back_to_back: bool = False,
) -> List[Driver]:
    """Return every online + approved driver within `max_distance_km` of the
    pickup, sorted nearest-first. If `vehicle_type` is set, also filter by it.

    Used for broadcast dispatch: every driver in range is pinged simultaneously
    and the first to tap Accept wins the ride.
    If `allow_back_to_back` is True, drivers currently in-progress with a ride
    (BookingStatus.STARTED) whose drop-off is near the pickup are also included.
    """
    stmt = select(Driver).where(
        Driver.is_online == True,  # noqa: E712
        Driver.status == DriverStatus.APPROVED,
    )
    if vehicle_type:
        stmt = stmt.where(Driver.vehicle_type == vehicle_type)
    q = await db.execute(stmt)
    candidates = q.scalars().all()

    if allow_back_to_back:
        strictly_busy = await strictly_busy_driver_ids(db)
        mid_trip_map = await get_mid_trip_drivers(db)
    else:
        strictly_busy = await busy_driver_ids(db)
        mid_trip_map = {}

    in_range: List[tuple[float, Driver]] = []
    skipped_no_loc = 0
    too_far = 0
    skipped_busy = 0
    b2b_count = 0

    for d in candidates:
        if exclude_driver_id is not None and d.id == exclude_driver_id:
            continue
        if d.id in strictly_busy:
            skipped_busy += 1
            continue

        if d.id in mid_trip_map:
            current_b = mid_trip_map[d.id]
            # Dropoff coordinates of the current ride represent where the driver will be freed up
            drop_lat = float(current_b.drop_lat) if current_b.drop_lat is not None else None
            drop_lng = float(current_b.drop_lng) if current_b.drop_lng is not None else None
            curr_lat = float(d.current_lat) if d.current_lat is not None else None
            curr_lng = float(d.current_lng) if d.current_lng is not None else None

            # Calculate distance from destination or current GPS location
            dists = []
            if drop_lat is not None and drop_lng is not None:
                dists.append(haversine_km(pickup_lat, pickup_lng, drop_lat, drop_lng))
            if curr_lat is not None and curr_lng is not None:
                dists.append(haversine_km(pickup_lat, pickup_lng, curr_lat, curr_lng))

            if not dists:
                skipped_no_loc += 1
                continue

            dist = min(dists)
            if dist > max_distance_km:
                too_far += 1
                continue

            # Flag driver as back-to-back candidate
            d._is_back_to_back = True
            d._current_drop_address = current_b.drop_address
            d._current_booking_id = current_b.id
            in_range.append((dist, d))
            b2b_count += 1
        else:
            # Idle driver
            if d.current_lat is None or d.current_lng is None:
                skipped_no_loc += 1
                continue
            dist = haversine_km(
                pickup_lat, pickup_lng, float(d.current_lat), float(d.current_lng)
            )
            if dist > max_distance_km:
                too_far += 1
                continue
            d._is_back_to_back = False
            d._current_drop_address = None
            d._current_booking_id = None
            in_range.append((dist, d))

    in_range.sort(key=lambda t: t[0])
    print(
        f"[match-all] type={vehicle_type} candidates={len(candidates)} "
        f"busy={skipped_busy} b2b={b2b_count} no_location={skipped_no_loc} "
        f"too_far(>{max_distance_km}km)={too_far} → broadcasting to {len(in_range)} driver(s)"
    )
    return [d for _, d in in_range]

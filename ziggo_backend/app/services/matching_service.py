"""Driver matching: pick the nearest online + approved driver of the right vehicle type."""
from typing import List, Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ..models import Driver, DriverStatus
from .fare_service import haversine_km


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

    nearest: Optional[Driver] = None
    nearest_dist = float("inf")
    skipped_no_loc = 0
    too_far = 0
    for d in candidates:
        if exclude_driver_id is not None and d.id == exclude_driver_id:
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
) -> List[Driver]:
    """Return every online + approved driver within `max_distance_km` of the
    pickup, sorted nearest-first. If `vehicle_type` is set, also filter by it.

    Used for broadcast dispatch: every driver in range is pinged simultaneously
    and the first to tap Accept wins the ride. Food orders pass
    `vehicle_type=None` so any rider in range can take them.
    """
    stmt = select(Driver).where(
        Driver.is_online == True,  # noqa: E712
        Driver.status == DriverStatus.APPROVED,
    )
    if vehicle_type:
        stmt = stmt.where(Driver.vehicle_type == vehicle_type)
    q = await db.execute(stmt)
    candidates = q.scalars().all()

    in_range: List[tuple[float, Driver]] = []
    skipped_no_loc = 0
    too_far = 0
    for d in candidates:
        if exclude_driver_id is not None and d.id == exclude_driver_id:
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
        in_range.append((dist, d))

    in_range.sort(key=lambda t: t[0])
    print(
        f"[match-all] type={vehicle_type} candidates={len(candidates)} "
        f"no_location={skipped_no_loc} too_far(>{max_distance_km}km)={too_far} "
        f"→ broadcasting to {len(in_range)} driver(s)"
    )
    return [d for _, d in in_range]

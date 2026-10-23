"""Commission-free launch locations (Phase 2, feature 02).

launch_location_for() answers: does a job of this service, starting at this
point today, fall inside an active launch location? The caller then waives
Ziggo's commission for it. Customer prices never change.
"""
from datetime import date, datetime, timedelta, timezone
from typing import Iterable, Optional

from shapely.geometry import Point, Polygon
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .district_service import district_for

LAUNCH_SERVICES = ("rides", "parcels", "food", "market")
_LK = timezone(timedelta(hours=5, minutes=30))


def today_lk() -> date:
    return datetime.now(_LK).date()


def service_of_booking(is_flash: bool, is_courier: bool) -> str:
    return "parcels" if (is_flash or is_courier) else "rides"


def status_of(loc, on: Optional[date] = None) -> str:
    """upcoming | active | ended | off"""
    on = on or today_lk()
    if not loc.is_active:
        return "off"
    if on < loc.start_date:
        return "upcoming"
    if on > loc.end_date:
        return "ended"
    return "active"


def covers(loc, lat: float, lng: float, district: Optional[str] = None) -> bool:
    if loc.kind == "district":
        return bool(loc.district) and (district or district_for(lat, lng)) == loc.district
    pts = loc.coordinates or []
    if len(pts) < 3:
        return False
    return Polygon([(float(p["lng"]), float(p["lat"])) for p in pts]).covers(Point(float(lng), float(lat)))


def match(locations: Iterable, lat, lng, service: str, on: Optional[date] = None):
    """The first active location covering the point for this service, else None."""
    if lat is None or lng is None:
        return None
    on = on or today_lk()
    district = None
    for loc in locations:
        if service not in (loc.services or []) or status_of(loc, on) != "active":
            continue
        if loc.kind == "district" and district is None:
            district = district_for(lat, lng)
        if covers(loc, lat, lng, district):
            return loc
    return None


async def launch_location_for(db: AsyncSession, lat, lng, service: str, on: Optional[date] = None):
    from ..models import LaunchLocation

    on = on or today_lk()
    q = await db.execute(select(LaunchLocation).where(
        LaunchLocation.is_active == True,  # noqa: E712
        LaunchLocation.start_date <= on, LaunchLocation.end_date >= on,
    ).order_by(LaunchLocation.id))
    return match(q.scalars().all(), lat, lng, service, on)

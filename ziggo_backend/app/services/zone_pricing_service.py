"""Geographic Zone Pricing & Dispatch Overrides Service.

Provides sub-millisecond point-in-polygon spatial detection for custom fare zones,
caching active polygon geometries in memory with fast bounding box rejection.
"""
import asyncio
import math
from typing import Optional, Any, Union
from shapely.geometry import Point, Polygon, LineString, MultiLineString, GeometryCollection
from shapely.prepared import prep
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import CustomFareZone

# Thread/coroutine-safe in-memory cache
_cache_lock = asyncio.Lock()
# List of (zone_id, (min_lat, min_lng, max_lat, max_lng), prepared_poly, zone_dict_or_obj)
_cached_zone_entries: Optional[list[dict]] = None


def invalidate_custom_fare_zone_cache() -> None:
    """Invalidate the spatial zone cache whenever zones are created, modified, or deleted."""
    global _cached_zone_entries
    _cached_zone_entries = None


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Accurate Great-Circle Haversine distance in kilometers."""
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng / 2) ** 2
    return 2 * r * math.asin(math.sqrt(max(0.0, min(1.0, a))))


def _geom_haversine_km(geom: Any) -> float:
    """Sum haversine lengths of all LineString components in a Shapely geometry."""
    total = 0.0
    if isinstance(geom, LineString):
        coords = list(geom.coords)
        for (lng1, lat1), (lng2, lat2) in zip(coords, coords[1:]):
            total += _haversine_km(lat1, lng1, lat2, lng2)
    elif isinstance(geom, (MultiLineString, GeometryCollection)):
        for g in geom.geoms:
            if isinstance(g, LineString):
                coords = list(g.coords)
                for (lng1, lat1), (lng2, lat2) in zip(coords, coords[1:]):
                    total += _haversine_km(lat1, lng1, lat2, lng2)
    return total


def _build_polygon_entry(zone: CustomFareZone) -> Optional[dict]:
    """Compile a zone's polygon into a bounding-box and Shapely prepared geometry."""
    coords = zone.coordinates or []
    if not isinstance(coords, list) or len(coords) < 3:
        return None

    try:
        pts = []
        lats, lngs = [], []
        for p in coords:
            lat_f = float(p.get("lat", 0.0))
            lng_f = float(p.get("lng", 0.0))
            lats.append(lat_f)
            lngs.append(lng_f)
            pts.append((lng_f, lat_f))  # Shapely takes (x, y) = (lng, lat)

        raw_poly = Polygon(pts)
        if not raw_poly.is_valid:
            raw_poly = raw_poly.buffer(0)
            if not raw_poly.is_valid:
                return None

        prepared_poly = prep(raw_poly)
        bbox = (min(lats), min(lngs), max(lats), max(lngs))
        return {
            "id": zone.id,
            "name": zone.name,
            "bbox": bbox,
            "prepared": prepared_poly,
            "raw_poly": raw_poly,
            "rates": zone.rates or {},
            "exempt_peak_surge": bool(zone.exempt_peak_surge),
            "zone": zone,
        }
    except Exception:
        return None


async def _get_or_load_cached_entries(db: AsyncSession) -> list[dict]:
    """Retrieve or build the prepared active zone entries."""
    global _cached_zone_entries
    if _cached_zone_entries is not None:
        return _cached_zone_entries

    async with _cache_lock:
        if _cached_zone_entries is not None:
            return _cached_zone_entries

        # Order by id DESC so most recently created zones take precedence in overlaps
        q = await db.execute(
            select(CustomFareZone)
            .where(CustomFareZone.is_active == True)  # noqa: E712
            .order_by(CustomFareZone.id.desc())
        )
        zones = q.scalars().all()

        entries = []
        for z in zones:
            entry = _build_polygon_entry(z)
            if entry:
                entries.append(entry)

        _cached_zone_entries = entries
        return _cached_zone_entries


async def find_custom_zone_for_point(
    db: AsyncSession, lat: Optional[float], lng: Optional[float]
) -> Optional[CustomFareZone]:
    """Return the active CustomFareZone covering the pickup point, or None."""
    if lat is None or lng is None:
        return None

    try:
        lat_f = float(lat)
        lng_f = float(lng)
    except (ValueError, TypeError):
        return None

    entries = await _get_or_load_cached_entries(db)
    pt = Point(lng_f, lat_f)

    for e in entries:
        min_lat, min_lng, max_lat, max_lng = e["bbox"]
        # Fast bounding box rejection
        if not (min_lat <= lat_f <= max_lat and min_lng <= lng_f <= max_lng):
            continue
        # Precise point-in-polygon check
        if e["prepared"].covers(pt):
            zone = e["zone"]
            setattr(zone, "_polygon", e.get("raw_poly"))
            return zone

    return None


async def get_custom_zone_polygon(
    db: AsyncSession, zone_id: int
) -> Optional[Polygon]:
    """Return the Shapely Polygon for a given custom zone id (cached or DB)."""
    if not zone_id:
        return None
    entries = await _get_or_load_cached_entries(db)
    for e in entries:
        if e["id"] == zone_id:
            return e.get("raw_poly")

    # Fallback to DB if zone was deactivated or cache refreshed
    q = await db.execute(
        select(CustomFareZone).where(CustomFareZone.id == zone_id)
    )
    z = q.scalars().first()
    if z:
        entry = _build_polygon_entry(z)
        if entry:
            return entry.get("raw_poly")
    return None


def split_route_distance(
    raw_poly: Optional[Polygon],
    pickup_lat: float,
    pickup_lng: float,
    drop_lat: float,
    drop_lng: float,
    stops: Optional[list] = None,
    total_distance_km: float = 0.0,
) -> tuple[float, float]:
    """Splits total_distance_km into (inside_distance_km, outside_distance_km).

    If dropoff (and all intermediate stops) are inside the custom zone polygon,
    returns (total_distance_km, 0.0).
    If the dropoff is outside, splits the path using Shapely LineString intersection
    and computes the proportional inside and outside distances accurately.
    """
    if total_distance_km <= 0.0:
        return 0.0, 0.0
    if raw_poly is None:
        return 0.0, round(total_distance_km, 2)

    try:
        drop_lat_f = float(drop_lat)
        drop_lng_f = float(drop_lng)
        p_lat_f = float(pickup_lat)
        p_lng_f = float(pickup_lng)
    except (ValueError, TypeError):
        return round(total_distance_km, 2), 0.0

    # If dropoff is 0,0 or omitted (e.g. open trip / rental), entire trip stays inside
    if drop_lat_f == 0.0 and drop_lng_f == 0.0:
        return round(total_distance_km, 2), 0.0

    try:
        drop_pt = Point(drop_lng_f, drop_lat_f)
        all_inside = raw_poly.covers(drop_pt)
        if stops and all_inside:
            for s in stops:
                s_lat = float(s.get("lat", 0.0))
                s_lng = float(s.get("lng", 0.0))
                if not raw_poly.covers(Point(s_lng, s_lat)):
                    all_inside = False
                    break

        if all_inside:
            return round(total_distance_km, 2), 0.0

        # Route crosses outside the zone
        pts = [(p_lng_f, p_lat_f)]
        if stops:
            for s in stops:
                pts.append((float(s.get("lng", 0.0)), float(s.get("lat", 0.0))))
        pts.append((drop_lng_f, drop_lat_f))

        line = LineString(pts)
        inter = line.intersection(raw_poly)
        straight_inside_km = _geom_haversine_km(inter)
        straight_total_km = sum(
            _haversine_km(lat1, lng1, lat2, lng2)
            for (lng1, lat1), (lng2, lat2) in zip(pts, pts[1:])
        )

        if straight_total_km <= 0.0:
            return 0.0, round(total_distance_km, 2)

        ratio = min(1.0, max(0.0, straight_inside_km / straight_total_km))
        inside_km = round(total_distance_km * ratio, 2)
        outside_km = max(0.0, round(total_distance_km - inside_km, 2))
        return inside_km, outside_km
    except Exception as e:
        import logging
        logging.getLogger(__name__).warning(f"split_route_distance fallback: {e}")
        return 0.0, round(total_distance_km, 2)



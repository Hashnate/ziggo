"""Google Maps web services, called only from this server.

The apps used to call Google directly, with a key built into the app, every time a
driver moved 20 m or a map stopped moving. Now they ask /api/v1/maps/* and
/api/v1/bookings/{id}/route, so the key stays here, one answer serves both apps,
and every call is logged as `[maps] <api> <status> <ms>` for counting.

Google's terms allow keeping coordinates for a limited time: routes are kept here
for ROUTE_CACHE_SECONDS, and on a booking only while its trip is on
(route_service). Addresses are not kept.
"""
import asyncio
import math
import re
import time
from typing import Optional

import httpx

from ..config import settings

DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json"
AUTOCOMPLETE_URL = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
DETAILS_URL = "https://maps.googleapis.com/maps/api/place/details/json"

TIMEOUT_SECONDS = 6.0
ROUTE_CACHE_SECONDS = 30 * 60
MAX_CACHED_ROUTES = 5000
GEOCODE_MAX_KM = 10          # Google sometimes ranks a far-away place first (Kinniya -> Hanoi)
AUTOCOMPLETE_RADIUS_M = 50000
# Sri Lanka with a margin. Nothing outside it is asked of Google.
LK_MIN_LAT, LK_MAX_LAT, LK_MIN_LNG, LK_MAX_LNG = 5.5, 10.2, 79.2, 82.2

_route_cache: dict[tuple, tuple[float, dict]] = {}
_route_inflight: dict[tuple, asyncio.Future] = {}
_hits: dict[tuple, list[float]] = {}

_TAGS = re.compile(r"<[^>]+>")
_SPACES = re.compile(r"\s+")
_PLUS_CODE = re.compile(r"^[A-Z0-9]{4,8}\+[A-Z0-9]{2,7}\b")


def enabled() -> bool:
    return bool(settings.MAPS_PROXY_ENABLED and settings.GOOGLE_MAPS_API_KEY)


def in_sri_lanka(lat: float, lng: float) -> bool:
    return LK_MIN_LAT <= lat <= LK_MAX_LAT and LK_MIN_LNG <= lng <= LK_MAX_LNG


def over_limit(user_id: int, kind: str, per_hour: int) -> bool:
    """True when this user already made `per_hour` calls of this kind in the last hour."""
    now = time.monotonic()
    key = (user_id, kind)
    recent = [t for t in _hits.get(key, ()) if now - t < 3600]
    if len(recent) >= per_hour:
        _hits[key] = recent
        return True
    if len(_hits) > 20000:
        _hits.clear()
    recent.append(now)
    _hits[key] = recent
    return False


async def _call(api: str, url: str, params: dict) -> Optional[dict]:
    """One Google request. Returns the answer when its status is OK or ZERO_RESULTS."""
    if not enabled():
        return None
    started = time.monotonic()
    status = "?"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            resp = await client.get(url, params={**params, "key": settings.GOOGLE_MAPS_API_KEY})
        data = resp.json()
        status = str(data.get("status") or resp.status_code)
        if status in ("OK", "ZERO_RESULTS"):
            return data
        print(f"[maps] {api} refused: {status} {str(data.get('error_message') or '')[:160]}")
        return None
    except Exception as e:
        status = type(e).__name__
        return None
    finally:
        print(f"[maps] {api} {status} {int((time.monotonic() - started) * 1000)}ms")


def _ll(point: tuple[float, float]) -> str:
    return f"{point[0]:.7f},{point[1]:.7f}"


def _clean_instruction(html: str) -> str:
    return _SPACES.sub(" ", _TAGS.sub(" ", html or "")).strip()


def _parse_route(data: Optional[dict]) -> Optional[dict]:
    routes = (data or {}).get("routes") or []
    if not routes:
        return None
    r = routes[0]
    legs = r.get("legs") or []
    polyline = (r.get("overview_polyline") or {}).get("points") or ""
    if not polyline or not legs:
        return None
    steps = []
    for leg in legs:
        for s in leg.get("steps") or []:
            start = s.get("start_location") or {}
            end = s.get("end_location") or {}
            if start.get("lat") is None or end.get("lat") is None:
                continue
            steps.append({
                "instruction": _clean_instruction(s.get("html_instructions") or ""),
                "maneuver": s.get("maneuver") or "",
                "distance_m": int((s.get("distance") or {}).get("value") or 0),
                "duration_s": int((s.get("duration") or {}).get("value") or 0),
                "start": [float(start["lat"]), float(start["lng"])],
                "end": [float(end["lat"]), float(end["lng"])],
            })
    return {
        "polyline": polyline,
        "distance_m": sum(int((leg.get("distance") or {}).get("value") or 0) for leg in legs),
        "duration_s": sum(int((leg.get("duration") or {}).get("value") or 0) for leg in legs),
        "steps": steps,
    }


async def route(points: list[tuple[float, float]]) -> Optional[dict]:
    """Driving route through `points` in order (start, stops, end), or None.

    {"polyline": <Google encoded polyline>, "distance_m", "duration_s",
     "steps": [{instruction, maneuver, distance_m, duration_s, start: [lat, lng], end}]}
    The same points (rounded to about 11 m) within 30 minutes share one Google call,
    including calls that arrive while the first one is still waiting for Google.
    """
    if len(points) < 2:
        return None
    key = tuple((round(lat, 4), round(lng, 4)) for lat, lng in points)
    hit = _route_cache.get(key)
    if hit and hit[0] > time.monotonic():
        return hit[1]
    waiting = _route_inflight.get(key)
    if waiting is not None:
        return await asyncio.shield(waiting)

    future = asyncio.get_running_loop().create_future()
    _route_inflight[key] = future
    result = None
    try:
        params = {"origin": _ll(points[0]), "destination": _ll(points[-1]), "mode": "driving"}
        if len(points) > 2:
            params["waypoints"] = "|".join(_ll(p) for p in points[1:-1])
        result = _parse_route(await _call("directions", DIRECTIONS_URL, params))
        if result:
            if len(_route_cache) >= MAX_CACHED_ROUTES:
                _route_cache.clear()
            _route_cache[key] = (time.monotonic() + ROUTE_CACHE_SECONDS, result)
        return result
    finally:
        _route_inflight.pop(key, None)
        if not future.done():
            future.set_result(result)


def _near(result: dict, lat: float, lng: float) -> bool:
    from .fare_service import haversine_km

    loc = (result.get("geometry") or {}).get("location") or {}
    return (
        loc.get("lat") is not None
        and loc.get("lng") is not None
        and haversine_km(lat, lng, loc["lat"], loc["lng"]) <= GEOCODE_MAX_KM
    )


def _strip_plus_code(address: str) -> str:
    if _PLUS_CODE.match(address):
        address = _PLUS_CODE.sub("", address).strip()
        if address.startswith(","):
            address = address[1:].strip()
    return address


async def reverse_geocode(lat: float, lng: float) -> Optional[str]:
    """A readable address for a point (same rules the app used): results more than
    10 km away are ignored, plus codes are skipped or stripped, and if nothing is left
    the address is built from the road and area names."""
    data = await _call("geocode", GEOCODE_URL, {"latlng": f"{lat},{lng}"})
    results = [r for r in (data or {}).get("results") or [] if _near(r, lat, lng)]
    for r in results:
        if "plus_code" in (r.get("types") or []):
            continue
        address = _strip_plus_code(r.get("formatted_address") or "")
        if address:
            return address
    if not results:
        return None
    found: dict[str, str] = {}
    for c in results[0].get("address_components") or []:
        name = c.get("long_name") or ""
        if not name:
            continue
        for kind in ("route", "neighborhood", "sublocality", "locality"):
            if kind in (c.get("types") or []):
                found.setdefault(kind, name)
    primary = found.get("route") or found.get("neighborhood") or found.get("sublocality") or found.get("locality")
    secondary = found.get("locality") or found.get("sublocality") or found.get("neighborhood")
    if not primary:
        return None
    return f"{primary}, {secondary}" if secondary and secondary != primary else primary


async def autocomplete(text: str, session: Optional[str], near: Optional[tuple[float, float]]) -> list[dict]:
    """Place suggestions in Sri Lanka, biased to `near`. One search (same session
    token, ending with place_location) is billed by Google as a single session."""
    params = {"input": text, "components": "country:lk"}
    if session:
        params["sessiontoken"] = session
    if near:
        params["location"] = _ll(near)
        params["radius"] = AUTOCOMPLETE_RADIUS_M
    data = await _call("autocomplete", AUTOCOMPLETE_URL, params)
    predictions = []
    for p in (data or {}).get("predictions") or []:
        shown = p.get("structured_formatting") or {}
        predictions.append({
            "place_id": p.get("place_id") or "",
            "main_text": shown.get("main_text") or p.get("description") or "",
            "secondary_text": shown.get("secondary_text") or "",
        })
    return predictions


async def place_location(place_id: str, session: Optional[str]) -> Optional[tuple[float, float]]:
    """Coordinates of a place picked from the suggestions."""
    params = {"place_id": place_id, "fields": "geometry"}
    if session:
        params["sessiontoken"] = session
    data = await _call("place", DETAILS_URL, params)
    loc = (((data or {}).get("result") or {}).get("geometry") or {}).get("location") or {}
    if loc.get("lat") is None or loc.get("lng") is None:
        return None
    return float(loc["lat"]), float(loc["lng"])


def decode_polyline(encoded: str) -> list[tuple[float, float]]:
    """Google's encoded polyline format -> [(lat, lng), ...]."""
    points: list[tuple[float, float]] = []
    index = lat = lng = 0
    length = len(encoded)
    while index < length:
        for is_lng in (False, True):
            shift = result = 0
            while True:
                if index >= length:
                    return points
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if is_lng:
                lng += delta
            else:
                lat += delta
        points.append((lat / 1e5, lng / 1e5))
    return points


def distance_to_route_m(lat: float, lng: float, points: list[tuple[float, float]]) -> float:
    """Metres from a point to the nearest part of a route (flat-earth, fine at city scale)."""
    if not points:
        return math.inf
    kx = 111320.0 * math.cos(math.radians(lat))
    ky = 110540.0

    def xy(p):
        return (p[1] - lng) * kx, (p[0] - lat) * ky

    if len(points) == 1:
        x, y = xy(points[0])
        return math.hypot(x, y)
    best = math.inf
    ax, ay = xy(points[0])
    for p in points[1:]:
        bx, by = xy(p)
        dx, dy = bx - ax, by - ay
        seg = dx * dx + dy * dy
        t = 0.0 if seg == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / seg))
        best = min(best, math.hypot(ax + t * dx, ay + t * dy))
        ax, ay = bx, by
    return best

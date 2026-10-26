"""Road distance for fares, from Google's Directions API (used by fare_service._trip_route
while SystemSettings.road_distance_enabled is on).

A straight line undercharges: roads wind, and around Kinniya's lagoon a 1.1 km hop is
3.6 km by road. Answers are kept for CACHE_SECONDS per route (points rounded to about
11 m), so the vehicle cards, the booking and the re-price at accept share one lookup.
Any failure returns None and the fare falls back to the straight line, so a booking
never fails because Google is slow or the key is wrong.
"""
import time
from typing import Optional

import httpx

from ..config import settings

DIRECTIONS_URL = "https://maps.googleapis.com/maps/api/directions/json"
CACHE_SECONDS = 30 * 60
TIMEOUT_SECONDS = 4.0
MAX_CACHED = 5000

_cache: dict[tuple, tuple[float, float]] = {}  # route key -> (expires at, km)


def _key(points: list[tuple[float, float]]) -> tuple:
    return tuple((round(lat, 4), round(lng, 4)) for lat, lng in points)


def _latlng(p: tuple[float, float]) -> str:
    return f"{p[0]:.7f},{p[1]:.7f}"


async def road_km(points: list[tuple[float, float]]) -> Optional[float]:
    """Driving distance in km along `points` (pickup, stops in order, drop), or None."""
    if len(points) < 2:
        return None
    key = _key(points)
    now = time.monotonic()
    hit = _cache.get(key)
    if hit and hit[0] > now:
        return hit[1]
    api_key = settings.GOOGLE_MAPS_API_KEY
    if not api_key:
        return None

    params = {"origin": _latlng(points[0]), "destination": _latlng(points[-1]), "mode": "driving", "key": api_key}
    if len(points) > 2:
        params["waypoints"] = "|".join(_latlng(p) for p in points[1:-1])
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS) as client:
            data = (await client.get(DIRECTIONS_URL, params=params)).json()
        if data.get("status") != "OK":
            print(f"[road] no route: {data.get('status')} {data.get('error_message', '')[:120]}")
            return None
        metres = sum(leg["distance"]["value"] for leg in data["routes"][0]["legs"])
    except Exception as e:
        print(f"[road] lookup failed: {type(e).__name__}")
        return None

    km = metres / 1000.0
    if len(_cache) >= MAX_CACHED:
        _cache.clear()
    _cache[key] = (now + CACHE_SECONDS, km)
    return km

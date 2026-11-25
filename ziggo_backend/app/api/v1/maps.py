"""Google Maps for the apps, through this server (see services/maps_service.py).

A login is needed: guests use the app's built-in landmarks instead. When Google
fails or maps are switched off the answer is empty, never an error, so the app falls
back to its offline behaviour. Each user has an hourly limit per kind of call.
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from ...models import User
from ...services import maps_service
from ...services.auth_service import get_current_user

router = APIRouter()

LIMITS = {"route": 120, "geocode": 300, "autocomplete": 600, "place": 200}
OUTSIDE = "Only places in Sri Lanka are supported."


class MapPoint(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)


class RouteRequest(BaseModel):
    points: List[MapPoint] = Field(..., min_length=2, max_length=12)


def _check_limit(user: User, kind: str) -> None:
    if maps_service.over_limit(user.id, kind, LIMITS[kind]):
        raise HTTPException(status_code=429, detail="Too many map requests. Please try again later.")


@router.post("/route")
async def maps_route(body: RouteRequest, user: User = Depends(get_current_user)):
    """Road route through the points in order: {"route": {polyline, distance_m,
    duration_s, steps} | null}."""
    points = [(p.lat, p.lng) for p in body.points]
    if not all(maps_service.in_sri_lanka(lat, lng) for lat, lng in points):
        raise HTTPException(status_code=400, detail=OUTSIDE)
    _check_limit(user, "route")
    return {"route": await maps_service.route(points)}


@router.get("/reverse-geocode")
async def maps_reverse_geocode(
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    user: User = Depends(get_current_user),
):
    """{"address": str | null}"""
    if not maps_service.in_sri_lanka(lat, lng):
        raise HTTPException(status_code=400, detail=OUTSIDE)
    _check_limit(user, "geocode")
    return {"address": await maps_service.reverse_geocode(lat, lng)}


@router.get("/autocomplete")
async def maps_autocomplete(
    input: str = Query(..., min_length=1, max_length=200),
    session: Optional[str] = Query(None, max_length=64),
    lat: Optional[float] = Query(None, ge=-90, le=90),
    lng: Optional[float] = Query(None, ge=-180, le=180),
    user: User = Depends(get_current_user),
):
    """{"predictions": [{place_id, main_text, secondary_text}]}"""
    text = input.strip()
    if len(text) < 2:
        return {"predictions": []}
    _check_limit(user, "autocomplete")
    near = (lat, lng) if lat is not None and lng is not None and maps_service.in_sri_lanka(lat, lng) else None
    return {"predictions": await maps_service.autocomplete(text, session, near)}


@router.get("/place")
async def maps_place(
    place_id: str = Query(..., min_length=1, max_length=300),
    session: Optional[str] = Query(None, max_length=64),
    user: User = Depends(get_current_user),
):
    """{"location": {"lat", "lng"} | null}"""
    _check_limit(user, "place")
    found = await maps_service.place_location(place_id, session)
    return {"location": {"lat": found[0], "lng": found[1]} if found else None}

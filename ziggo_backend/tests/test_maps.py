"""Google Maps through the server (services/maps_service.py, api/v1/maps.py).

Google is never called: httpx.AsyncClient is replaced by a fake that answers from
canned replies and records every request.
"""
import asyncio
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.api.v1 import maps as maps_api
from app.services import fcm_service, maps_service, route_service

DIRECTIONS = {
    "status": "OK",
    "routes": [{
        "overview_polyline": {"points": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"},
        "legs": [
            {"distance": {"value": 1200}, "duration": {"value": 180}, "steps": [
                {"html_instructions": "Head <b>north</b> on <b>Galle Rd</b>", "distance": {"value": 700},
                 "duration": {"value": 100}, "start_location": {"lat": 6.9, "lng": 79.85},
                 "end_location": {"lat": 6.906, "lng": 79.85}},
                {"html_instructions": 'Turn <b>right</b> onto X<div style="font-size:0.9em">On the left</div>',
                 "maneuver": "turn-right", "distance": {"value": 500}, "duration": {"value": 80},
                 "start_location": {"lat": 6.906, "lng": 79.85}, "end_location": {"lat": 6.906, "lng": 79.855}},
            ]},
            {"distance": {"value": 300}, "duration": {"value": 60}, "steps": [
                {"html_instructions": "Continue", "distance": {"value": 300}, "duration": {"value": 60},
                 "start_location": {"lat": 6.906, "lng": 79.855}, "end_location": {"lat": 6.907, "lng": 79.857}},
            ]},
        ],
    }],
}


class _Google:
    """Stands in for httpx.AsyncClient. Replies are looked up by URL."""

    def __init__(self):
        self.replies = {}
        self.calls = []

    def __call__(self, *args, **kwargs):
        return self

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def get(self, url, params=None):
        self.calls.append((url, dict(params or {})))
        await asyncio.sleep(0)
        reply = self.replies[url]
        if isinstance(reply, Exception):
            raise reply
        return SimpleNamespace(status_code=200, json=lambda: reply)


@pytest.fixture
def google(monkeypatch):
    fake = _Google()
    monkeypatch.setattr(maps_service.httpx, "AsyncClient", fake)
    monkeypatch.setattr(maps_service.settings, "GOOGLE_MAPS_API_KEY", "test-key")
    monkeypatch.setattr(maps_service.settings, "MAPS_PROXY_ENABLED", True)
    monkeypatch.setattr(maps_service, "_route_cache", {})
    monkeypatch.setattr(maps_service, "_route_inflight", {})
    monkeypatch.setattr(maps_service, "_hits", {})
    return fake


def test_decode_polyline():
    # Google's documented example.
    assert maps_service.decode_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@") == [
        (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
    assert maps_service.decode_polyline("") == []


def test_distance_to_route():
    line = [(6.900, 79.850), (6.910, 79.850)]
    assert maps_service.distance_to_route_m(6.905, 79.850, line) < 1
    off = maps_service.distance_to_route_m(6.905, 79.85091, line)  # about 100 m east
    assert 95 < off < 105
    beyond = maps_service.distance_to_route_m(6.911, 79.850, line)  # past the end
    assert 105 < beyond < 115
    assert maps_service.distance_to_route_m(6.9, 79.85, []) == float("inf")


async def test_route_is_parsed_and_shared(google):
    google.replies[maps_service.DIRECTIONS_URL] = DIRECTIONS
    points = [(6.9, 79.85), (6.905, 79.852), (6.907, 79.857)]
    r = await maps_service.route(points)
    assert r["polyline"] == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    assert (r["distance_m"], r["duration_s"]) == (1500, 240), "summed over every leg"
    assert [s["instruction"] for s in r["steps"]] == [
        "Head north on Galle Rd", "Turn right onto X On the left", "Continue"]
    assert r["steps"][1]["maneuver"] == "turn-right"
    assert r["steps"][0]["start"] == [6.9, 79.85]
    (url, params), = google.calls
    assert params["origin"] == "6.9000000,79.8500000" and params["destination"] == "6.9070000,79.8570000"
    assert params["waypoints"] == "6.9050000,79.8520000"
    assert params["key"] == "test-key" and params["mode"] == "driving"

    again = await maps_service.route([(6.90001, 79.85001), (6.905, 79.852), (6.907, 79.857)])
    assert again == r and len(google.calls) == 1, "points within about 11 m share the cached answer"

    google.calls.clear()
    other = [(7.2, 80.6), (7.3, 80.7)]
    first, second = await asyncio.gather(maps_service.route(other), maps_service.route(other))
    assert first == second and len(google.calls) == 1, "a second ask while Google answers the first waits for it"


async def test_route_failures(google, monkeypatch):
    google.replies[maps_service.DIRECTIONS_URL] = {"status": "REQUEST_DENIED", "error_message": "key"}
    points = [(6.9, 79.85), (6.95, 79.9)]
    assert await maps_service.route(points) is None
    assert await maps_service.route(points) is None
    assert len(google.calls) == 2, "failures are not cached"

    google.replies[maps_service.DIRECTIONS_URL] = {"status": "ZERO_RESULTS", "routes": []}
    assert await maps_service.route(points) is None

    google.replies[maps_service.DIRECTIONS_URL] = TimeoutError("slow")
    assert await maps_service.route(points) is None

    google.calls.clear()
    monkeypatch.setattr(maps_service.settings, "MAPS_PROXY_ENABLED", False)
    assert await maps_service.route(points) is None
    monkeypatch.setattr(maps_service.settings, "MAPS_PROXY_ENABLED", True)
    monkeypatch.setattr(maps_service.settings, "GOOGLE_MAPS_API_KEY", None)
    assert await maps_service.route(points) is None
    assert google.calls == [], "switched off or no key: Google is not asked"
    assert await maps_service.route([(6.9, 79.85)]) is None


def _place(lat, lng, address, types=("street_address",), components=()):
    return {"geometry": {"location": {"lat": lat, "lng": lng}}, "formatted_address": address,
            "types": list(types), "address_components": list(components)}


async def test_reverse_geocode(google):
    google.replies[maps_service.GEOCODE_URL] = {"status": "OK", "results": [
        _place(21.03, 105.85, "Hang Bai, Hanoi"),                        # far away: ignored
        _place(6.9001, 79.8501, "G52J+XF5, Sri Lanka", types=("plus_code",)),
        _place(6.9002, 79.8502, "G52J+XF5, Galle Rd, Colombo"),
    ]}
    assert await maps_service.reverse_geocode(6.9, 79.85) == "Galle Rd, Colombo"
    assert google.calls[0][1]["latlng"] == "6.9,79.85"

    google.replies[maps_service.GEOCODE_URL] = {"status": "OK", "results": [
        _place(6.9001, 79.8501, "", components=[
            {"long_name": "Galle Rd", "types": ["route"]},
            {"long_name": "Second Rd", "types": ["route"]},
            {"long_name": "Colombo", "types": ["locality", "political"]},
        ]),
    ]}
    assert await maps_service.reverse_geocode(6.9, 79.85) == "Galle Rd, Colombo", "built from the first road and area"

    google.replies[maps_service.GEOCODE_URL] = {"status": "ZERO_RESULTS", "results": []}
    assert await maps_service.reverse_geocode(6.9, 79.85) is None


async def test_autocomplete_and_place(google):
    google.replies[maps_service.AUTOCOMPLETE_URL] = {"status": "OK", "predictions": [
        {"place_id": "p1", "description": "Maradana, Colombo",
         "structured_formatting": {"main_text": "Maradana", "secondary_text": "Colombo"}},
        {"place_id": "p2", "description": "Borella"},
    ]}
    found = await maps_service.autocomplete("mara", "tok-1", (6.93, 79.86))
    assert found == [
        {"place_id": "p1", "main_text": "Maradana", "secondary_text": "Colombo"},
        {"place_id": "p2", "main_text": "Borella", "secondary_text": ""},
    ]
    params = google.calls[-1][1]
    assert params["sessiontoken"] == "tok-1" and params["components"] == "country:lk"
    assert params["location"] == "6.9300000,79.8600000" and params["radius"] == 50000

    await maps_service.autocomplete("mara", None, None)
    assert "sessiontoken" not in google.calls[-1][1] and "location" not in google.calls[-1][1]

    google.replies[maps_service.DETAILS_URL] = {"status": "OK", "result": {"geometry": {"location": {"lat": 6.93, "lng": 79.86}}}}
    assert await maps_service.place_location("p1", "tok-1") == (6.93, 79.86)
    params = google.calls[-1][1]
    assert params["fields"] == "geometry" and params["sessiontoken"] == "tok-1"


async def test_endpoints(google, monkeypatch):
    user = SimpleNamespace(id=42)
    google.replies[maps_service.DIRECTIONS_URL] = DIRECTIONS
    body = maps_api.RouteRequest(points=[{"lat": 6.9, "lng": 79.85}, {"lat": 6.95, "lng": 79.9}])
    assert (await maps_api.maps_route(body, user))["route"]["distance_m"] == 1500

    with pytest.raises(HTTPException) as e:
        await maps_api.maps_route(maps_api.RouteRequest(points=[{"lat": 6.9, "lng": 79.85}, {"lat": 51.5, "lng": -0.1}]), user)
    assert e.value.status_code == 400, "only Sri Lanka"
    with pytest.raises(HTTPException) as e:
        await maps_api.maps_reverse_geocode(21.03, 105.85, user)
    assert e.value.status_code == 400

    monkeypatch.setitem(maps_api.LIMITS, "route", 1)  # this user already made 1 route call
    with pytest.raises(HTTPException) as e:
        await maps_api.maps_route(body, user)
    assert e.value.status_code == 429, "the hourly limit per user"
    assert (await maps_api.maps_route(body, SimpleNamespace(id=43)))["route"], "other users are not affected"

    calls = len(google.calls)
    assert await maps_api.maps_autocomplete("a", None, None, None, user) == {"predictions": []}
    assert len(google.calls) == calls, "one letter is not searched"

    google.replies[maps_service.DETAILS_URL] = {"status": "NOT_FOUND"}
    assert await maps_api.maps_place("nope", None, user) == {"location": None}


def test_login_required():
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from app.api.v1 import booking_routes

    app = FastAPI()
    app.include_router(maps_api.router, prefix="/api/v1/maps")
    app.include_router(booking_routes.router, prefix="/api/v1/bookings")
    client = TestClient(app)
    assert client.get("/api/v1/maps/reverse-geocode", params={"lat": 6.9, "lng": 79.85}).status_code == 401
    assert client.post("/api/v1/maps/route", json={"points": []}).status_code in (401, 422)
    assert client.get("/api/v1/bookings/1/route").status_code == 401


def test_app_version_is_noted():
    from app.api.v1.auth import OLD_APP_VERSION, _note_app_version
    from app.models import UserRole

    user = SimpleNamespace(role=UserRole.CUSTOMER, app_version=None, app_platform=None)
    new_app = SimpleNamespace(headers={"x-app-version": "1.1.5", "x-app-platform": "Android"})
    assert _note_app_version(user, new_app)
    assert (user.app_version, user.app_platform) == ("1.1.5", "android")
    assert not _note_app_version(user, new_app), "nothing to save when nothing changed"
    assert _note_app_version(user, SimpleNamespace(headers={})) and user.app_version == OLD_APP_VERSION
    admin = SimpleNamespace(role=UserRole.ADMIN, app_version=None, app_platform=None)
    assert not _note_app_version(admin, SimpleNamespace(headers={})) and admin.app_version is None


def test_route_event_sends_no_push_and_no_ride_request():
    assert fcm_service._format(route_service.EVENT, {"booking_id": 1, "version": 2}) == ("", "")
    assert "request" not in route_service.EVENT and "cancel" not in route_service.EVENT

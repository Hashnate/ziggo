"""Road distance for ride and flash parcel fares.

While the switch is on, the distance comes from Google's road route (stubbed here),
is never shorter than the straight line and also drives the time estimate; if Google
fails the fare uses the straight line. Off, nothing changes. Rates come from
fare_cases.install(): tuk base 80, per-km 55, per-minute 3, minimum 150, at 10:15.
"""
from types import SimpleNamespace

import pytest
from sqlalchemy import select

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from app.models import SystemSettings
from app.services import road_distance_service as rds
from app.services.fare_service import calculate_fare, calculate_fares_bulk, estimate_duration_min, haversine_km
from fare_cases import frozen_clock, install

FORT = (6.9344, 79.8428)
GALLE_FACE = (6.9271, 79.8612)
BORELLA = (6.9147, 79.8778)
PARTS = ("distance_km", "duration_min", "fare_amount", "final_amount", "platform_fee", "driver_earnings",
         "distance_source")


class _Google:
    """Stands in for road_distance_service.road_km and records what it was asked."""

    def __init__(self, km):
        self.km = km
        self.asked = []

    async def __call__(self, points):
        self.asked.append(points)
        return self.km(points) if callable(self.km) else self.km


async def _switch(db, on: bool):
    ss = (await db.execute(select(SystemSettings).where(SystemSettings.id == 1))).scalars().first()
    ss.road_distance_enabled = on
    await db.commit()


async def _quote(db, service_type, pickup, drop, **kw):
    with frozen_clock("10:15"):
        booking = await calculate_fare(db, service_type, *pickup, *drop, **kw)
        card = (await calculate_fares_bulk(db, [service_type], *pickup, *drop, **kw))[service_type]
    return booking, card


async def test_fares_use_the_road_route(monkeypatch):
    straight = haversine_km(*FORT, *GALLE_FACE)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await install(db, "base")
            await _switch(db, False)
            google = _Google(5.0)
            monkeypatch.setattr(rds, "road_km", google)

            off, off_card = await _quote(db, "tuk", FORT, GALLE_FACE)
            assert "distance_source" not in off and google.asked == [], "switched off: no lookup, no new key"
            assert off["distance_km"] == round(straight, 2) and off_card["fare_amount"] == off["fare_amount"]

            await _switch(db, True)
            on, card = await _quote(db, "tuk", FORT, GALLE_FACE)
            assert (on["distance_km"], on["distance_source"]) == (5.0, "road")
            assert on["duration_min"] == estimate_duration_min(5.0) == 12, "the time estimate follows the road"
            assert all(on.get(k) == card.get(k) for k in PARTS), "the vehicle card shows the booking's price"
            expected = 55 * (5.0 - straight) + 3 * (12 - off["duration_min"])
            assert on["fare_amount"] - off["fare_amount"] == pytest.approx(expected, abs=0.02), \
                "same rates, only the distance and time change"
            assert google.asked[0] == [FORT, GALLE_FACE]

            google.asked.clear()
            stop = {"lat": BORELLA[0], "lng": BORELLA[1], "address": "Borella"}
            await calculate_fare(db, "tuk", *FORT, *GALLE_FACE, stops=[stop])
            assert google.asked == [[FORT, BORELLA, GALLE_FACE]], "stops are passed through in order"

            google.km = 0.5
            short, _ = await _quote(db, "tuk", FORT, GALLE_FACE)
            assert short["distance_km"] == round(straight, 2) and short["distance_source"] == "road", \
                "never shorter than the straight line"

            google.km = None
            down, down_card = await _quote(db, "tuk", FORT, GALLE_FACE)
            assert down["distance_source"] == "straight" and down_card["distance_source"] == "straight"
            assert all(down[k] == off[k] for k in PARTS if k != "distance_source"), \
                "Google failing prices the straight line, as before"

            google.km = 5.0
            flash, _ = await _quote(db, "bike", FORT, GALLE_FACE, is_flash=True, parcel_weight_kg=2.0)
            assert flash["distance_km"] == 5.0 and flash["distance_source"] == "road", "flash parcels too"

            google.asked.clear()
            courier, _ = await _quote(db, "bike", FORT, GALLE_FACE, is_courier=True, parcel_weight_kg=3.0)
            rental, _ = await _quote(db, "tuk", FORT, FORT, is_rental=True, rental_hours=3)
            assert "distance_source" not in courier and "distance_source" not in rental and google.asked == [], \
                "courier and rental are priced as before, without a lookup"
            await _switch(db, False)
    finally:
        await engine.dispose()


class _Client:
    """Stands in for httpx.AsyncClient inside road_distance_service."""
    replies: list = []
    sent: list = []

    def __init__(self, timeout=None):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def get(self, url, params=None):
        _Client.sent.append(params)
        reply = _Client.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return SimpleNamespace(json=lambda: reply)


def _route_reply(*metres):
    return {"status": "OK", "routes": [{"legs": [{"distance": {"value": m}} for m in metres]}]}


async def test_google_lookup(monkeypatch):
    monkeypatch.setattr(rds.httpx, "AsyncClient", _Client)
    monkeypatch.setattr(rds.settings, "GOOGLE_MAPS_API_KEY", "test-key")
    monkeypatch.setattr(rds, "_cache", {})
    _Client.sent = []

    _Client.replies = [_route_reply(1200, 2448)]
    assert await rds.road_km([FORT, BORELLA, GALLE_FACE]) == 3.648, "legs are added up"
    sent = _Client.sent[-1]
    assert (sent["origin"], sent["waypoints"], sent["destination"], sent["mode"]) == (
        "6.9344000,79.8428000", "6.9147000,79.8778000", "6.9271000,79.8612000", "driving")

    assert await rds.road_km([(6.93441, 79.84281), BORELLA, GALLE_FACE]) == 3.648
    assert len(_Client.sent) == 1, "a route within ~11 m of a recent one is answered from the cache"

    _Client.replies = [{"status": "ZERO_RESULTS"}, TimeoutError(), _route_reply(900)]
    assert await rds.road_km([FORT, GALLE_FACE]) is None, "no route"
    assert await rds.road_km([FORT, GALLE_FACE]) is None, "Google too slow"
    assert await rds.road_km([FORT, GALLE_FACE]) == 0.9, "failures aren't cached"
    assert "waypoints" not in _Client.sent[-1]

    monkeypatch.setattr(rds.settings, "GOOGLE_MAPS_API_KEY", "")
    assert await rds.road_km([BORELLA, FORT]) is None, "no key: straight line"
    assert await rds.road_km([FORT]) is None

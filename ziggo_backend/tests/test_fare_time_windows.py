"""The exact minutes when peak hours, the system surge and surge zones switch on and off.

Expectations are written out by hand from the rules in fare_cases.install(),
not recorded from the engine. Current behaviour: peak hours and the system
surge window include their start and exclude their end; surge zones include
both their start and their end minute. Vehicle cards must agree with booking.
"""
import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from app.services.fare_service import calculate_fare, calculate_fares_bulk
from fare_cases import ROUTES, frozen_clock, install

# Colombo time: (tuk peak, bike peak, system surge, zones at a Fort pickup, zones at a Nugegoda pickup)
EXPECTED = {
    "06:59": (0, 0, 1.0, 100, 0),
    "07:00": (40, 40, 1.0, 100, 0),     # all-vehicle peak 07:00-09:30 starts
    "09:29": (40, 40, 1.0, 100, 0),
    "09:30": (0, 0, 1.0, 100, 0),       # ...and ends
    "16:59": (0, 0, 1.0, 100, 0),
    "17:00": (60, 0, 1.5, 150, 0),      # tuk peak, system surge 17-20 and the Fort evening zone start
    "17:59": (60, 0, 1.5, 150, 0),
    "18:00": (85, 25, 1.5, 150, 0),     # all-vehicle peak 18:00-18:30 adds 25
    "18:29": (85, 25, 1.5, 150, 0),
    "18:30": (60, 0, 1.5, 150, 0),
    "18:59": (60, 0, 1.5, 150, 0),
    "19:00": (0, 0, 1.5, 150, 0),       # tuk peak 17:00-19:00 ends
    "19:59": (0, 0, 1.5, 150, 0),
    "20:00": (0, 0, 1.0, 150, 0),       # surge ends, but the zone still counts its end minute
    "20:01": (0, 0, 1.0, 100, 0),
    "21:59": (0, 0, 1.0, 100, 0),
    "22:00": (0, 0, 1.0, 100, 30),      # Nugegoda night zone 22:00-02:00 starts
    "22:59": (0, 0, 1.0, 100, 30),
    "23:00": (0, 30, 1.0, 100, 30),     # bike overnight peak 23:00-02:00 starts
    "23:59": (0, 30, 1.0, 100, 30),
    "00:00": (0, 30, 1.0, 100, 30),     # across midnight
    "01:59": (0, 30, 1.0, 100, 30),
    "02:00": (0, 0, 1.0, 100, 30),      # peak ends, the zone still counts its end minute
    "02:01": (0, 0, 1.0, 100, 0),
}
# System surge window 22-02 (x1.3) in the "overnight" setup.
OVERNIGHT_SURGE = {"21:59": 1.0, "22:00": 1.3, "23:59": 1.3, "00:00": 1.3, "01:59": 1.3, "02:00": 1.0}
PARTS = ("peak_surcharge", "zone_surcharge", "surge_multiplier", "final_amount")


async def _quote(db, service_type, route, at):
    (pickup_lat, pickup_lng), (drop_lat, drop_lng) = ROUTES[route]
    with frozen_clock(at):
        booking = await calculate_fare(db, service_type, pickup_lat, pickup_lng, drop_lat, drop_lng)
        card = (await calculate_fares_bulk(db, [service_type], pickup_lat, pickup_lng, drop_lat, drop_lng))[service_type]
    return booking, card


async def test_time_windows_switch_on_and_off_on_the_exact_minute():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    wrong = []
    try:
        async with AsyncSessionLocal() as db:
            await install(db, "base")
            for at, expected in EXPECTED.items():
                quotes = [await _quote(db, st, route, at)
                          for st, route in (("tuk", "fort_short"), ("bike", "fort_short"), ("tuk", "nugegoda_medium"))]
                (tuk, _), (bike, _), (tuk_nugegoda, _) = quotes
                got = (tuk["peak_surcharge"], bike["peak_surcharge"], tuk["surge_multiplier"],
                       tuk["zone_surcharge"], tuk_nugegoda["zone_surcharge"])
                if got != expected:
                    wrong.append(f"{at}: expected (tuk peak, bike peak, surge, Fort zones, Nugegoda zones) "
                                 f"{expected}, got {got}")
                for booking, card in quotes:
                    if any(booking[k] != card[k] for k in PARTS):
                        wrong.append(f"{at}: vehicle card differs from booking: "
                                     f"{ {k: (card[k], booking[k]) for k in PARTS} }")
            await install(db, "overnight_surge_no_loyalty")
            for at, surge in OVERNIGHT_SURGE.items():
                tuk, card = await _quote(db, "tuk", "fort_short", at)
                if tuk["surge_multiplier"] != surge or card["surge_multiplier"] != surge:
                    wrong.append(f"{at}: overnight surge expected x{surge}, got booking x{tuk['surge_multiplier']}, "
                                 f"card x{card['surge_multiplier']}")
    finally:
        await engine.dispose()
    assert not wrong, f"{len(wrong)} time-window checks failed:\n" + "\n".join(wrong)

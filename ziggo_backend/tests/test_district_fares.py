"""District base fares (Phase 2, feature 04).

Only the base fare can differ per district; the pickup's district decides, and only a
switched-on fare whose period covers today counts. A booking being re-priced keeps the
base fare it was booked with. Expected differences are worked out by hand from
fare_cases.install() (tuk: base 80, per-km 55, min 150, no surge or category discount at
10:15).
"""
from datetime import timedelta
from decimal import Decimal

from sqlalchemy import delete

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from app.models import DistrictFare
from app.services.fare_service import calculate_fare, calculate_fares_bulk
from app.services.launch_service import today_lk
from fare_cases import frozen_clock, install

FORT = (6.9344, 79.8428)            # Colombo
FORT_NEXT_DOOR = (6.9350, 79.8430)  # ~70 m away, far below the minimum fare
GALLE_FACE = (6.9271, 79.8612)      # Colombo
NEGOMBO = (7.2008, 79.8737)         # Gampaha
KANDY = (7.2906, 80.6337)           # Kandy
PERADENIYA = (7.2690, 80.5970)      # Kandy
PARTS = ("fare_amount", "discount_amount", "final_amount", "platform_fee", "driver_earnings",
         "district", "district_base_fare")


async def _quote(db, service_type, pickup, drop, **kw):
    with frozen_clock("10:15"):
        booking = await calculate_fare(db, service_type, *pickup, *drop, **kw)
        if kw:
            return booking, None
        card = (await calculate_fares_bulk(db, [service_type], *pickup, *drop))[service_type]
    return booking, card


def _same_price(booking, card):
    return all(booking.get(k) == card.get(k) for k in PARTS)


async def _fares(db, *rows):
    """Replace every district fare with rows of (district, vehicle, base, start, end, on)."""
    await db.execute(delete(DistrictFare))
    for district, st, base, start, end, on in rows:
        db.add(DistrictFare(district=district, service_type=st, base_fare=Decimal(base),
                            start_date=start, end_date=end, is_active=on))
    await db.commit()


async def test_district_base_fares():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    wrong = []

    def expect(label, ok, detail=""):
        if not ok:
            wrong.append(f"{label}: {detail}")

    today = today_lk()
    day = timedelta(days=1)
    try:
        async with AsyncSessionLocal() as db:
            await install(db, "base")
            trips = {
                "tuk in Colombo": ("tuk", FORT, GALLE_FACE),
                "tuk Colombo -> Kandy": ("tuk", FORT, KANDY),
                "tuk in Gampaha (no district fare)": ("tuk", NEGOMBO, (7.2100, 79.8400)),
                "tuk 70 m (minimum fare)": ("tuk", FORT, FORT_NEXT_DOOR),
                "car in Colombo (same as national)": ("car", FORT, GALLE_FACE),
                "car in Kandy": ("car", KANDY, PERADENIYA),
                "car Kandy -> Colombo": ("car", KANDY, FORT),
            }
            await _fares(db)
            off = {name: await _quote(db, *t) for name, t in trips.items()}
            courier_off, _ = await _quote(db, "bike", FORT, GALLE_FACE, is_courier=True, parcel_weight_kg=3.0)
            rental_off, _ = await _quote(db, "tuk", FORT, FORT, is_rental=True, rental_hours=3)
            for name, (booking, card) in off.items():
                expect(f"no district fares, {name}", "district" not in booking and _same_price(booking, card),
                       "district fare used or card differs")

            await _fares(db, ("Colombo", "tuk", "120", today, today + 6 * day, True),
                         ("Colombo", "car", "200", today - 3 * day, today, True),
                         ("Kandy", "car", "260", today, today, True))
            on = {name: await _quote(db, *t) for name, t in trips.items()}
            for name, (booking, card) in on.items():
                expect(f"active fares, {name}: card = booking", _same_price(booking, card),
                       f"card { {k: card.get(k) for k in PARTS} } vs booking { {k: booking.get(k) for k in PARTS} }")

            def diff(name, now=on):
                return round(now[name][0]["fare_amount"] - off[name][0]["fare_amount"], 2)

            b = on["tuk in Colombo"][0]
            expect("tuk in Colombo uses Colombo's base fare",
                   b.get("district") == "Colombo" and b.get("district_base_fare") == 120 and diff("tuk in Colombo") == 40,
                   f"district {b.get('district')}, base {b.get('district_base_fare')}, fare +{diff('tuk in Colombo')} (expected +40)")
            expect("a trip starting in Colombo uses Colombo's fare even when it ends in Kandy",
                   on["tuk Colombo -> Kandy"][0].get("district") == "Colombo" and diff("tuk Colombo -> Kandy") == 40,
                   f"+{diff('tuk Colombo -> Kandy')}")
            g = on["tuk in Gampaha (no district fare)"][0]
            expect("a district without its own fare stays national",
                   "district" not in g and g == off["tuk in Gampaha (no district fare)"][0], str(g))
            m_on, m_off = on["tuk 70 m (minimum fare)"][0], off["tuk 70 m (minimum fare)"][0]
            expect("on a very short trip the national minimum fare still decides",
                   m_on["fare_amount"] == m_off["fare_amount"] == 150 + m_off["zone_surcharge"],
                   f"{m_off['fare_amount']} -> {m_on['fare_amount']} (minimum 150 + zone {m_off['zone_surcharge']})")
            expect("a period ending today still counts today; a fare equal to the national one changes only the record",
                   diff("car in Colombo (same as national)") == 0
                   and on["car in Colombo (same as national)"][0].get("district_base_fare") == 200)
            k = on["car in Kandy"][0]
            expect("a one-day period counts on its day",
                   k.get("district") == "Kandy" and k.get("district_base_fare") == 260 and diff("car in Kandy") > 0,
                   f"district {k.get('district')}, fare +{diff('car in Kandy')}")
            expect("Kandy -> Colombo is priced with Kandy's fare",
                   on["car Kandy -> Colombo"][0].get("district") == "Kandy"
                   and diff("car Kandy -> Colombo") == diff("car in Kandy"))

            courier_on, _ = await _quote(db, "bike", FORT, GALLE_FACE, is_courier=True, parcel_weight_kg=3.0)
            rental_on, _ = await _quote(db, "tuk", FORT, FORT, is_rental=True, rental_hours=3)
            expect("courier keeps national rates", courier_on == courier_off, f"{courier_off} -> {courier_on}")
            expect("rental keeps national rates", rental_on == rental_off, f"{rental_off} -> {rental_on}")

            await _fares(db, ("Colombo", "tuk", "120", today + day, today + 6 * day, True),
                         ("Colombo", "car", "260", today - 6 * day, today - day, True),
                         ("Kandy", "car", "260", today, today + day, False))
            later = {name: await _quote(db, *t) for name, t in trips.items()}
            expect("a period that starts tomorrow doesn't count yet",
                   "district" not in later["tuk in Colombo"][0] and diff("tuk in Colombo", later) == 0)
            expect("after the end date the national base fare is back by itself",
                   "district" not in later["car in Colombo (same as national)"][0])
            expect("a switched-off fare doesn't count", "district" not in later["car in Kandy"][0])

            await _fares(db, ("Colombo", "tuk", "120", None, None, True),
                         ("Colombo", "tuk", "100", today - day, today + day, True))
            both, _ = await _quote(db, "tuk", FORT, GALLE_FACE)
            expect("missing dates mean no limit; if two periods overlap, the one starting later wins",
                   both.get("district_base_fare") == 100, str(both.get("district_base_fare")))

            await _fares(db)
            kept, _ = await _quote(db, "tuk", FORT, GALLE_FACE, district_fare=("Colombo", 120.0))
            expect("re-pricing keeps the fare the trip was booked with after its period ended",
                   kept.get("district") == "Colombo" and kept.get("district_base_fare") == 120
                   and round(kept["fare_amount"] - off["tuk in Colombo"][0]["fare_amount"], 2) == 40,
                   str({k: kept.get(k) for k in PARTS}))
            await _fares(db, ("Colombo", "tuk", "120", today, today, True))
            none, _ = await _quote(db, "tuk", FORT, GALLE_FACE, district_fare=())
            expect("a trip booked without one stays national when a period starts mid-trip",
                   "district" not in none and none["fare_amount"] == off["tuk in Colombo"][0]["fare_amount"])
            await _fares(db)
    finally:
        await engine.dispose()
    assert not wrong, f"{len(wrong)} district fare checks failed:\n" + "\n".join(wrong)

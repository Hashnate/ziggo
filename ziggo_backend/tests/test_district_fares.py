"""District base fares and per-km rates (Phase 2, feature 04).

Base fares and per-km rates can differ per district; the pickup's district decides (Option A: origin-based),
and only a switched-on fare whose period covers today counts. A booking being re-priced keeps the
rates it was booked with. Expected differences are worked out by hand from
fare_cases.install() (tuk: base 80, per-km 55, min 150, pickup_fee 10%, no surge or category discount at 10:15).
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
         "district", "district_base_fare", "district_per_km_rate")


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
    """Replace every district fare with rows of (district, vehicle, base, start, end, on) or
    (district, vehicle, base, per_km, start, end, on)."""
    await db.execute(delete(DistrictFare))
    for r in rows:
        if len(r) == 7:
            district, st, base, per_km, start, end, on = r
            b_val = Decimal(str(base)) if base is not None else None
            k_val = Decimal(str(per_km)) if per_km is not None else None
        else:
            district, st, base, start, end, on = r
            b_val = Decimal(str(base)) if base is not None else None
            k_val = None
        db.add(DistrictFare(district=district, service_type=st, base_fare=b_val,
                            per_km_rate=k_val, start_date=start, end_date=end, is_active=on))
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

            # Test 1: Base fare configurations
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

            # Test 2: District Per-KM rate (Option A: origin-based)
            # National tuk per-km is 55. Set Colombo tuk per-km to 75 (+20/km), base_fare=None (national base 80)
            await _fares(db, ("Colombo", "tuk", None, "75", today, today + 3 * day, True))
            km_on = {name: await _quote(db, *t) for name, t in trips.items()}
            for name, (booking, card) in km_on.items():
                expect(f"per_km active, {name}: card = booking", _same_price(booking, card),
                       f"card { {k: card.get(k) for k in PARTS} } vs booking { {k: booking.get(k) for k in PARTS} }")

            b_km = km_on["tuk in Colombo"][0]
            dist_col = b_km["distance_km"]
            expected_km_diff = round(dist_col * 20, 2)
            actual_km_diff = round(b_km["fare_amount"] - off["tuk in Colombo"][0]["fare_amount"], 2)
            expect("tuk in Colombo uses Colombo's per-km rate (Rs. 75/km)",
                   b_km.get("district") == "Colombo"
                   and b_km.get("district_per_km_rate") == 75
                   and b_km.get("district_base_fare") is None
                   and abs(actual_km_diff - expected_km_diff) <= 0.15,
                   f"district {b_km.get('district')}, per_km {b_km.get('district_per_km_rate')}, diff {actual_km_diff} vs expected {expected_km_diff}")

            # Cross-district trip: Colombo -> Kandy (origin dictates rate for all km)
            cross_trip = km_on["tuk Colombo -> Kandy"][0]
            cross_dist = cross_trip["distance_km"]
            expected_cross_diff = round(cross_dist * 20, 2)
            actual_cross_diff = round(cross_trip["fare_amount"] - off["tuk Colombo -> Kandy"][0]["fare_amount"], 2)
            expect("Option A origin-based: Colombo -> Kandy uses Colombo per-km for the whole trip",
                   cross_trip.get("district") == "Colombo"
                   and cross_trip.get("district_per_km_rate") == 75
                   and abs(actual_cross_diff - expected_cross_diff) <= 0.20,
                   f"cross diff {actual_cross_diff} vs expected {expected_cross_diff}")

            # Test 3: Both Base Fare and Per-KM rate together
            await _fares(db, ("Colombo", "tuk", "100", "75", today, today + 3 * day, True))
            both_on, both_card = await _quote(db, "tuk", FORT, GALLE_FACE)
            expect("both base and per-km: card = booking", _same_price(both_on, both_card), "card differs from booking")
            expect("both base and per-km applied together",
                   both_on.get("district") == "Colombo"
                   and both_on.get("district_base_fare") == 100
                   and both_on.get("district_per_km_rate") == 75
                   and abs(round(both_on["fare_amount"] - off["tuk in Colombo"][0]["fare_amount"], 2) - (20 + actual_km_diff)) <= 0.05,
                   f"fare {both_on.get('fare_amount')}")

            # Test 4: Driver pickup fee scales with district per-km rate
            # Bike has pickup_fee=20%. Set Colombo bike per_km to 60 (national 40).
            await _fares(db, ("Colombo", "bike", None, "60", today, today + 3 * day, True))
            with frozen_clock("10:15"):
                drv_quote = await calculate_fare(db, "bike", *FORT, *GALLE_FACE,
                                                 driver_accepted_lat=FORT[0] + 0.01, driver_accepted_lng=FORT[1])
                expect("pickup fee uses district per-km rate",
                       drv_quote.get("pickup_fee") > 0 and drv_quote.get("district_per_km_rate") == 60,
                       f"pickup fee: {drv_quote.get('pickup_fee')}")

            # Test 5: Re-pricing keeps booked district per-km rate
            await _fares(db)  # remove active district fares
            kept_km, _ = await _quote(db, "tuk", FORT, GALLE_FACE, district_fare=("Colombo", None, 75.0))
            expect("re-pricing keeps the per-km rate the trip was booked with after period ended",
                   kept_km.get("district") == "Colombo"
                   and kept_km.get("district_per_km_rate") == 75
                   and abs(round(kept_km["fare_amount"] - off["tuk in Colombo"][0]["fare_amount"], 2) - actual_km_diff) <= 0.05,
                   str({k: kept_km.get(k) for k in PARTS}))

            kept_both, _ = await _quote(db, "tuk", FORT, GALLE_FACE, district_fare=("Colombo", 100.0, 75.0))
            expect("re-pricing keeps both base fare and per-km rate",
                   kept_both.get("district") == "Colombo"
                   and kept_both.get("district_base_fare") == 100
                   and kept_both.get("district_per_km_rate") == 75,
                   str({k: kept_both.get(k) for k in PARTS}))

            # Test 6: Inactive periods and date limits
            await _fares(db, ("Colombo", "tuk", "120", today + day, today + 6 * day, True),
                         ("Colombo", "car", "260", today - 6 * day, today - day, True),
                         ("Kandy", "car", "260", today, today + day, False))
            later = {name: await _quote(db, *t) for name, t in trips.items()}
            expect("a period that starts tomorrow doesn't count yet",
                   "district" not in later["tuk in Colombo"][0] and diff("tuk in Colombo", later) == 0)
            expect("after the end date the national rates are back by themselves",
                   "district" not in later["car in Colombo (same as national)"][0])
            expect("a switched-off fare doesn't count", "district" not in later["car in Kandy"][0])

            await _fares(db)
    finally:
        await engine.dispose()
    assert not wrong, f"{len(wrong)} district fare checks failed:\n" + "\n".join(wrong)

"""Commission-free trips in launch locations (Phase 2, feature 02).

Customers pay exactly the same; Ziggo's commission becomes 0 and the driver gets
it. A booking keeps the decision made when it was booked (launch_location_id),
so re-pricing after the period ends doesn't bring the commission back.
"""
from datetime import timedelta

from sqlalchemy import delete

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from app.models import LaunchLocation
from app.services.fare_service import calculate_fare, calculate_fares_bulk
from app.services.launch_service import today_lk
from fare_cases import frozen_clock, install

FORT, GALLE_FACE = (6.9344, 79.8428), (6.9271, 79.8612)    # Colombo
NEGOMBO, NEGOMBO_2 = (7.2008, 79.8737), (7.2100, 79.8400)  # Gampaha
PARTS = ("fare_amount", "discount_amount", "final_amount", "platform_fee", "driver_earnings",
         "commission_free", "launch_location_id", "commission_waived")


async def _quote(db, st, pickup, drop, **kw):
    with frozen_clock("10:15"):
        return await calculate_fare(db, st, *pickup, *drop, **kw)


async def _card(db, st, pickup, drop, **kw):
    with frozen_clock("10:15"):
        return (await calculate_fares_bulk(db, [st], *pickup, *drop, **kw))[st]


async def test_commission_free_trips():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    wrong = []

    def expect(label, ok, detail=""):
        if not ok:
            wrong.append(f"{label}: {detail}")

    today = today_lk()
    try:
        async with AsyncSessionLocal() as db:
            await install(db, "base")
            await db.execute(delete(LaunchLocation))
            await db.commit()
            cases = {
                "tuk ride in Colombo": ("tuk", FORT, GALLE_FACE, {}),
                "flash parcel in Colombo": ("bike", FORT, GALLE_FACE, {"is_flash": True, "parcel_weight_kg": 2.0}),
                "courier in Colombo": ("bike", FORT, GALLE_FACE, {"is_courier": True, "parcel_weight_kg": 3.0}),
                "car rental in Colombo": ("car", FORT, FORT, {"is_rental": True, "rental_hours": 3}),
                "tuk ride in Gampaha": ("tuk", NEGOMBO, NEGOMBO_2, {}),
            }
            before = {k: await _quote(db, st, p, d, **kw) for k, (st, p, d, kw) in cases.items()}
            for k, q in before.items():
                expect(f"no launch location, {k}", "commission_free" not in q and q["platform_fee"] > 0, str(q.get("platform_fee")))

            colombo = LaunchLocation(name="Colombo launch", kind="district", district="Colombo",
                                     start_date=today - timedelta(days=3), end_date=today + timedelta(days=3),
                                     services=["rides"], is_active=True)
            db.add(colombo)
            await db.commit()
            during = {k: await _quote(db, st, p, d, **kw) for k, (st, p, d, kw) in cases.items()}

            for k in ("tuk ride in Colombo", "car rental in Colombo"):
                b, a = before[k], during[k]
                expect(f"{k}: Ziggo takes nothing", a["platform_fee"] == 0, f"fee {a['platform_fee']}")
                expect(f"{k}: customer pays the same", a["final_amount"] == b["final_amount"],
                       f"{b['final_amount']} -> {a['final_amount']}")
                expect(f"{k}: driver gets the commission", round(a["driver_earnings"] - b["driver_earnings"], 2)
                       == round(b["platform_fee"], 2), f"{b['driver_earnings']} -> {a['driver_earnings']}")
                expect(f"{k}: quote names the location and the amount waived",
                       a.get("commission_free") == "Colombo launch" and a.get("launch_location_id") == colombo.id
                       and abs(a.get("commission_waived", 0) - b["platform_fee"]) < 0.01, str({x: a.get(x) for x in PARTS}))
            for k in ("flash parcel in Colombo", "courier in Colombo"):
                expect(f"{k}: parcels not ticked, unchanged", during[k] == before[k])
            expect("Gampaha ride, outside the area, unchanged", during["tuk ride in Gampaha"] == before["tuk ride in Gampaha"])

            card = await _card(db, "tuk", FORT, GALLE_FACE)
            expect("vehicle card shows the same commission-free price",
                   all(card.get(x) == during["tuk ride in Colombo"].get(x) for x in PARTS),
                   str({x: (card.get(x), during["tuk ride in Colombo"].get(x)) for x in PARTS}))

            colombo.services = ["rides", "parcels"]
            await db.commit()
            for k in ("flash parcel in Colombo", "courier in Colombo"):
                st, p, d, kw = cases[k]
                q = await _quote(db, st, p, d, **kw)
                expect(f"{k}: parcels ticked, commission-free", q["platform_fee"] == 0
                       and q["final_amount"] == before[k]["final_amount"], str(q["platform_fee"]))

            # A booking re-priced keeps the decision it was booked with.
            free_id = colombo.id
            colombo.end_date = today - timedelta(days=1)          # the period has ended
            await db.commit()
            ended = await _quote(db, "tuk", FORT, GALLE_FACE)
            expect("after the period, new trips pay commission again", ended == before["tuk ride in Colombo"])
            kept = await _quote(db, "tuk", FORT, GALLE_FACE, launch_location_id=free_id)
            expect("a trip booked during the period stays free when re-priced later",
                   kept["platform_fee"] == 0 and kept.get("launch_location_id") == free_id)
            colombo.end_date = today + timedelta(days=3)
            await db.commit()
            not_free = await _quote(db, "tuk", FORT, GALLE_FACE, launch_location_id=0)
            expect("a trip booked before the period stays as booked when re-priced during it",
                   not_free == before["tuk ride in Colombo"])
            await db.delete(colombo)
            await db.commit()
            gone = await _quote(db, "tuk", FORT, GALLE_FACE, launch_location_id=free_id)
            expect("deleting the location doesn't charge trips already booked in it", gone["platform_fee"] == 0)

            colombo2 = LaunchLocation(name="Off", kind="district", district="Colombo", start_date=today, end_date=today,
                                      services=["rides"], is_active=False)
            db.add(colombo2)
            await db.commit()
            expect("a switched-off location does nothing",
                   await _quote(db, "tuk", FORT, GALLE_FACE) == before["tuk ride in Colombo"])
            await db.execute(delete(LaunchLocation))
            await db.commit()
    finally:
        await engine.dispose()
    assert not wrong, f"{len(wrong)} launch-location trip checks failed:\n" + "\n".join(wrong)

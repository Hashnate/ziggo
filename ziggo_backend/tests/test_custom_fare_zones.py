"""Unit and integration tests for Geographic Zone Pricing & Dispatch Overrides.

Covers:
1. Spatial point-in-polygon engine (inside, outside, bounding-box checks)
2. Per-vehicle pricing overrides (base fare, min fare, per-km rate)
3. Total exemption from dynamic surge and peak-hour surcharges
4. Strict origin-based pricing (pickup inside vs pickup outside)
5. Dynamic driver dispatch search radius resolution
6. Bulk calculation consistency with single calculation
7. Re-pricing immutability (locked snapshot rates preserved)
"""
import pytest
from decimal import Decimal

from sqlalchemy import delete, select
from app.database import AsyncSessionLocal, Base, engine
from app.models import CustomFareZone, FareSetting, PeakHourSetting, SystemSettings, Booking
from app.services.zone_pricing_service import (
    find_custom_zone_for_point,
    invalidate_custom_fare_zone_cache,
)
from app.services.fare_service import calculate_fare, calculate_fares_bulk
from app.api.v1.bookings import get_search_radius_for_service, _booked_custom_zone


# Colombo Fort test polygon
FORT_POLYGON = [
    {"lat": 6.9300, "lng": 79.8400},
    {"lat": 6.9400, "lng": 79.8400},
    {"lat": 6.9400, "lng": 79.8600},
    {"lat": 6.9300, "lng": 79.8600},
]
POINT_INSIDE_FORT = (6.9350, 79.8500)
POINT_OUTSIDE_FORT = (6.9000, 79.8700)   # Colombo 07 / Cinnamon Gardens
POINT_FAR_AWAY = (7.2906, 80.6337)      # Kandy


@pytest.fixture(autouse=True)
async def db_teardown():
    yield
    try:
        async with AsyncSessionLocal() as db:
            await db.execute(delete(CustomFareZone).where(CustomFareZone.name.in_(["Colombo Fort Tourist Zone", "Split Test Zone"])))
            await db.commit()
    except Exception:
        pass
    invalidate_custom_fare_zone_cache()
    await engine.dispose()


@pytest.mark.asyncio
async def test_all_custom_fare_zone_features():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as db:
        # 1. Setup base settings (upsert to avoid duplicate key conflicts)
        fs_tuk = (await db.execute(select(FareSetting).where(FareSetting.service_type == "tuk"))).scalar_one_or_none()
        if not fs_tuk:
            fs_tuk = FareSetting(service_type="tuk", display_name="Tuk-Tuk")
            db.add(fs_tuk)
        fs_tuk.base_fare = Decimal("100.00")
        fs_tuk.per_km_rate = Decimal("80.00")
        fs_tuk.per_minute_rate = Decimal("3.00")
        fs_tuk.min_fare = Decimal("100.00")
        fs_tuk.search_radius_km = 10
        fs_tuk.surge_multiplier = Decimal("1.50")
        fs_tuk.is_active = True

        fs_car = (await db.execute(select(FareSetting).where(FareSetting.service_type == "car"))).scalar_one_or_none()
        if not fs_car:
            fs_car = FareSetting(service_type="car", display_name="Car")
            db.add(fs_car)
        fs_car.base_fare = Decimal("200.00")
        fs_car.per_km_rate = Decimal("120.00")
        fs_car.per_minute_rate = Decimal("4.00")
        fs_car.min_fare = Decimal("200.00")
        fs_car.search_radius_km = 10
        fs_car.surge_multiplier = Decimal("1.50")
        fs_car.is_active = True

        ss = (await db.execute(select(SystemSettings).where(SystemSettings.id == 1))).scalar_one_or_none()
        if not ss:
            ss = SystemSettings(id=1)
            db.add(ss)
        ss.commission_rate = Decimal("15.00")
        ss.surge_start_hour = 0
        ss.surge_end_hour = 24
        ss.surge_multiplier = Decimal("1.80")
        ss.driver_search_radius_km = 15

        peak_24 = (await db.execute(select(PeakHourSetting).where(
            PeakHourSetting.vehicle_category == None,  # noqa: E711
            PeakHourSetting.start_time == "00:00",
            PeakHourSetting.end_time == "23:59",
            PeakHourSetting.is_active == True,
        ))).scalar_one_or_none()
        created_test_peak = False
        if not peak_24:
            peak_24 = PeakHourSetting(
                start_hour=0, end_hour=24,
                start_time="00:00", end_time="23:59",
                extra_amount=Decimal("75.00"), is_active=True,
            )
            db.add(peak_24)
            await db.commit()
            await db.refresh(peak_24)
            created_test_peak = True

        zone = CustomFareZone(
            name="Colombo Fort Tourist Zone",
            coordinates=FORT_POLYGON,
            color="#2563eb",
            is_active=True,
            exempt_peak_surge=True,
            rates={
                "tuk": {"base_fare": 200.0, "min_fare": 250.0, "search_radius_km": 3.0},
                "car": {"base_fare": 450.0, "min_fare": 500.0, "search_radius_km": 7.0},
            },
        )
        db.add(zone)
        await db.commit()
        await db.refresh(zone)

        # -------------------------------------------------------------
        # Part A: Spatial Detection
        # -------------------------------------------------------------
        matched = await find_custom_zone_for_point(db, POINT_INSIDE_FORT[0], POINT_INSIDE_FORT[1])
        assert matched is not None, "Point inside Fort should match"
        assert matched.id == zone.id

        outside = await find_custom_zone_for_point(db, POINT_OUTSIDE_FORT[0], POINT_OUTSIDE_FORT[1])
        assert outside is None, "Point outside Fort should return None"

        # -------------------------------------------------------------
        # Part B: Origin-Based Fare Overrides & Peak/Surge Exemption
        # -------------------------------------------------------------
        fare_inside_tuk = await calculate_fare(
            db, "tuk",
            pickup_lat=POINT_INSIDE_FORT[0], pickup_lng=POINT_INSIDE_FORT[1],
            drop_lat=POINT_OUTSIDE_FORT[0], drop_lng=POINT_OUTSIDE_FORT[1],
        )
        assert fare_inside_tuk["surge_multiplier"] == 1.0, "Surge must be strictly 1.0x inside zone"
        assert fare_inside_tuk["peak_surcharge"] == 0.0, "Peak surcharge must be 0.0 inside zone"
        assert fare_inside_tuk["custom_fare_zone_id"] == zone.id
        assert fare_inside_tuk["exempt_peak_surge"] is True
        assert fare_inside_tuk["fare_amount"] >= 250.0, "Min fare guarantee must be respected"

        # Pickup outside Fort: normal pricing + surge + peak applies
        fare_outside_tuk = await calculate_fare(
            db, "tuk",
            pickup_lat=POINT_OUTSIDE_FORT[0], pickup_lng=POINT_OUTSIDE_FORT[1],
            drop_lat=POINT_INSIDE_FORT[0], drop_lng=POINT_INSIDE_FORT[1],
        )
        assert fare_outside_tuk["surge_multiplier"] == 1.80, "Outside pickup should adopt active system surge"
        assert fare_outside_tuk["peak_surcharge"] == 75.00, "Outside pickup should adopt active peak surcharge"
        assert "custom_fare_zone_id" not in fare_outside_tuk

        # -------------------------------------------------------------
        # Part C: Dynamic Search Radius Resolution
        # -------------------------------------------------------------
        r_tuk_inside = await get_search_radius_for_service(
            db, "tuk", POINT_INSIDE_FORT[0], POINT_INSIDE_FORT[1]
        )
        assert r_tuk_inside == 3, f"Expected 3 km radius for tuk in zone, got {r_tuk_inside}"

        r_car_inside = await get_search_radius_for_service(
            db, "car", POINT_INSIDE_FORT[0], POINT_INSIDE_FORT[1]
        )
        assert r_car_inside == 7, f"Expected 7 km radius for car in zone, got {r_car_inside}"

        r_tuk_outside = await get_search_radius_for_service(
            db, "tuk", POINT_OUTSIDE_FORT[0], POINT_OUTSIDE_FORT[1]
        )
        assert r_tuk_outside != 3, "Outside zone should not adopt zone search radius"

        # -------------------------------------------------------------
        # Part D: Bulk Quotes Match Single Quote
        # -------------------------------------------------------------
        bulk = await calculate_fares_bulk(
            db, ["tuk", "car"],
            pickup_lat=POINT_INSIDE_FORT[0], pickup_lng=POINT_INSIDE_FORT[1],
            drop_lat=POINT_OUTSIDE_FORT[0], drop_lng=POINT_OUTSIDE_FORT[1],
        )
        single_car = await calculate_fare(
            db, "car",
            pickup_lat=POINT_INSIDE_FORT[0], pickup_lng=POINT_INSIDE_FORT[1],
            drop_lat=POINT_OUTSIDE_FORT[0], drop_lng=POINT_OUTSIDE_FORT[1],
        )
        assert bulk["car"]["final_amount"] == single_car["final_amount"]
        assert bulk["car"]["custom_fare_zone_id"] == zone.id
        assert bulk["tuk"]["custom_fare_zone_id"] == zone.id

        # -------------------------------------------------------------
        # Part E: Re-pricing Immutability
        # -------------------------------------------------------------
        booking = Booking(
            booking_ref="ZGIMMUTABLE01",
            service_type="tuk",
            pickup_lat=Decimal(str(POINT_INSIDE_FORT[0])),
            pickup_lng=Decimal(str(POINT_INSIDE_FORT[1])),
            drop_lat=Decimal(str(POINT_OUTSIDE_FORT[0])),
            drop_lng=Decimal(str(POINT_OUTSIDE_FORT[1])),
            custom_fare_zone_id=zone.id,
            fare_breakdown={
                "custom_fare_zone_id": zone.id,
                "custom_fare_zone_name": zone.name,
                "custom_zone_rate": {"base_fare": 300.0, "min_fare": 350.0},
                "exempt_peak_surge": True,
            },
        )
        override = _booked_custom_zone(booking)
        assert override["id"] == zone.id
        assert override["rates"]["tuk"]["base_fare"] == 300.0
        assert override["exempt_peak_surge"] is True

        # Re-price with override even to a far away destination
        recalculated = await calculate_fare(
            db, "tuk",
            pickup_lat=POINT_INSIDE_FORT[0], pickup_lng=POINT_INSIDE_FORT[1],
            drop_lat=POINT_FAR_AWAY[0], drop_lng=POINT_FAR_AWAY[1],
            custom_zone_override=override,
        )
        assert recalculated["custom_fare_zone_id"] == zone.id
        assert recalculated["surge_multiplier"] == 1.0
        assert recalculated["peak_surcharge"] == 0.0

        # -------------------------------------------------------------
        # Part F: Boundary-crossing Distance Split (Inside vs Outside)
        # -------------------------------------------------------------
        # Create a zone with flat / custom per-km rate (e.g. 0.0 inside)
        zone_split = CustomFareZone(
            name="Split Test Zone",
            coordinates=FORT_POLYGON,
            color="#10b981",
            is_active=True,
            exempt_peak_surge=True,
            rates={
                "tuk": {"base_fare": 200.0, "min_fare": 200.0, "search_radius_km": 3.0, "per_km_rate": 0.0},
            },
        )
        db.add(zone_split)
        await db.commit()
        await db.refresh(zone_split)
        invalidate_custom_fare_zone_cache()

        # Trip 1: Wholly inside the zone
        point_inside_2 = (6.9320, 79.8450)
        fare_all_inside = await calculate_fare(
            db, "tuk",
            pickup_lat=POINT_INSIDE_FORT[0], pickup_lng=POINT_INSIDE_FORT[1],
            drop_lat=point_inside_2[0], drop_lng=point_inside_2[1],
        )
        assert fare_all_inside["custom_fare_zone_id"] == zone_split.id
        assert fare_all_inside["zone_outside_km"] == 0.0, "Outside distance must be 0 for trips inside zone"
        assert fare_all_inside["zone_per_km_rate"] == 0.0
        assert fare_all_inside["regular_per_km_rate"] in (80.0, 100.0)

        # Trip 2: Starts inside zone, drops off outside
        fare_cross = await calculate_fare(
            db, "tuk",
            pickup_lat=POINT_INSIDE_FORT[0], pickup_lng=POINT_INSIDE_FORT[1],
            drop_lat=POINT_OUTSIDE_FORT[0], drop_lng=POINT_OUTSIDE_FORT[1],
        )
        assert fare_cross["custom_fare_zone_id"] == zone_split.id
        assert fare_cross["zone_inside_km"] > 0.0, "Inside distance must be > 0"
        assert fare_cross["zone_outside_km"] > 0.0, "Outside distance must be > 0"
        assert round(fare_cross["zone_inside_km"] + fare_cross["zone_outside_km"], 2) == fare_cross["distance_km"]
        assert fare_cross["zone_per_km_rate"] == 0.0
        assert fare_cross["regular_per_km_rate"] in (80.0, 100.0)
        # The fare must include the regular per-km charge for the outside distance:
        reg_rate = fare_cross["regular_per_km_rate"]
        expected_outside_charge = fare_cross["zone_outside_km"] * reg_rate
        assert fare_cross["fare_amount"] >= 200.0 + expected_outside_charge - 1.0

        if created_test_peak and peak_24:
            await db.delete(peak_24)
            await db.commit()

"""Pricing setup and trip scenarios for the fare-engine golden tests.

The setup is made up (no production values), but it reaches every pricing
branch: per-category rates and minimum fares, category discounts, boosts,
pickup fees, passenger deductibles, the 0% and unset commission fallbacks,
missing and inactive categories, the system surge window, peak hours (one
running overnight, some per category), time-limited and overlapping surge
zones, flash weight tiers, promo codes (capped and uncapped percentages,
fixed, used up, inactive, unknown, lower-case), rentals, courier parcels,
multi-stop and return trips, nearest-driver pickup fees and loyalty
redemption. Every scenario runs on a frozen clock, so results repeat exactly.
"""
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from unittest import mock

from sqlalchemy import delete, null, select

from app.models import (
    Booking, BookingStatus, Customer, Driver, DriverStatus, FareSetting,
    FlashWeightTier, PeakHourSetting, PromoCode, SurgeZone, SystemSettings, User, UserRole,
)
from app.services.fare_service import calculate_fare, calculate_fares_bulk

COLOMBO = timezone(timedelta(hours=5, minutes=30))
DAY = (2026, 5, 15)
TIMES = ["10:15", "08:00", "18:10", "23:30", "01:00"]

FORT = (6.9344, 79.8428)
NUGEGODA = (6.8649, 79.8997)
ROUTES = {
    "fort_short": (FORT, (6.9271, 79.8612)),
    "nugegoda_medium": (NUGEGODA, (6.9147, 79.8778)),
    "fort_to_kandy": (FORT, (7.2906, 80.6337)),
}
ONE_STOP = [{"lat": 6.9000, "lng": 79.8550, "address": "Stop A"}]
TWO_STOPS = ONE_STOP + [{"lat": 6.8800, "lng": 79.8700, "address": "Stop B"}]
PACKAGES = [{"weight_kg": 1.0}, {"weight_kg": 6.0}]
SERVICE_TYPES = ["tuk", "bike", "car", "van", "mini", "moto scooter", "truck", "mover"]
PROMOS = ["PCT20", "PCT10", "FLAT100", "USEDUP", "INACTIVE", "NOPE", "pct20"]

# service_type: base, per_km, per_min, min_fare, commission %, surge, pickup fee %,
# boost, passenger deductible %, category discount %, search radius, hourly rental,
# active. "van" has 0% and "mini" no commission, which both fall back to the system
# rate; "truck" is inactive; "mover" has no row at all.
FARE_ROWS = {
    "tuk": (80, 55, 3, 150, "7.30", "1.00", 0, 0, 0, 0, 5, 650, True),
    "bike": (50, 40, 2, 100, "7.30", "1.00", 20, 10, 0, 0, None, None, True),
    "car": (200, 170, 4, 250, "10.30", "1.25", 0, 0, 5, 10, 8, 1400, True),
    "van": (400, 300, 5, 400, "0", "1.00", 0, 25, 0, 0, 12, 2000, True),
    "mini": (130, 120, 3, 130, None, "1.00", 50, 0, "2.5", 15, 6, None, True),
    "moto scooter": (48, 46, 2, 48, "7.30", "1.00", 0, 0, 0, 0, 4, None, True),
    "truck": (550, 350, 6, 550, "10.30", "1.00", 0, 0, 0, 0, None, None, False),
    "courier": (80, 77, 0, 0, "9.50", "1.00", 0, 0, 0, 0, None, None, True),
}


def _square(lat0, lat1, lng0, lng1):
    return [{"lat": lat0, "lng": lng0}, {"lat": lat0, "lng": lng1},
            {"lat": lat1, "lng": lng1}, {"lat": lat1, "lng": lng0}]


def _north(point, km):
    return (point[0] + km / 111.32, point[1])


async def install(db, variant: str = "base") -> None:
    """Replace all pricing data with the fixed setup for `variant`."""
    for model in (Booking, Driver, Customer, User, PromoCode, FlashWeightTier,
                  SurgeZone, PeakHourSetting, FareSetting, SystemSettings):
        await db.execute(delete(model))

    overnight = variant == "overnight_surge_no_loyalty"
    db.add(SystemSettings(
        id=1, commission_rate=Decimal("12.50"),
        surge_start_hour=22 if overnight else 17, surge_end_hour=2 if overnight else 20,
        surge_multiplier=Decimal("1.30") if overnight else Decimal("1.50"),
        multi_stop_fee_per_stop=Decimal("50"), multi_stop_max_count=2,
        loyalty_is_active=not overnight, loyalty_earn_rupees_per_point=Decimal("10"),
        loyalty_value_per_point=Decimal("0.50"), loyalty_min_redeem_points=100,
        loyalty_max_redeem_order_pct=Decimal("20"),
    ))
    for order, (st, r) in enumerate(FARE_ROWS.items()):
        if st == "courier" and variant == "no_courier_row":
            continue
        db.add(FareSetting(
            service_type=st, display_name=st.title(), display_order=order,
            base_fare=Decimal(r[0]), per_km_rate=Decimal(r[1]), per_minute_rate=Decimal(r[2]),
            # null() rather than None: None would let the column default (15%) fill it in.
            min_fare=Decimal(r[3]), platform_fee_percent=null() if r[4] is None else Decimal(r[4]),
            surge_multiplier=Decimal(r[5]), pickup_fee=Decimal(r[6]), boost=Decimal(r[7]),
            passenger_deductible=Decimal(str(r[8])), discount_percentage=Decimal(r[9]),
            search_radius_km=r[10], rental_hourly_rate=None if r[11] is None else Decimal(r[11]),
            is_active=r[12],
        ))
    for start, end, extra, category, active in [
        ("07:00", "09:30", 40, None, True), ("17:00", "19:00", 60, "tuk", True),
        ("23:00", "02:00", 30, "bike", True), ("12:00", "14:00", 99, None, False),
        (None, None, 77, None, True), ("18:00", "18:30", 25, None, True),
    ]:
        db.add(PeakHourSetting(start_time=null() if start is None else start,
                               end_time=null() if end is None else end, extra_amount=Decimal(extra),
                               vehicle_category=category, is_active=active))
    for name, coords, extra, start, end, active in [
        ("Fort", _square(6.925, 6.945, 79.835, 79.855), 100, None, None, True),
        ("Fort evening", _square(6.920, 6.950, 79.830, 79.860), 50, "17:00", "20:00", True),
        ("Nugegoda nights", _square(6.850, 6.880, 79.890, 79.910), 30, "22:00", "02:00", True),
        ("Fort inactive", _square(6.925, 6.945, 79.835, 79.855), 999, None, None, False),
        ("Too few points", [{"lat": 6.93, "lng": 79.84}, {"lat": 6.94, "lng": 79.85}], 500, None, None, True),
        ("Broken", [{"x": 1}, {"x": 2}, {"x": 3}], 500, None, None, True),
    ]:
        db.add(SurgeZone(name=name, coordinates=coords, flat_extra_charge=Decimal(extra),
                         start_time=start, end_time=end, is_active=active))
    for order, (lo, hi, rep, fee, active) in enumerate([
        (0, 2, "1", 0, True), (2, 5, "3.5", 50, True), (5, 10, "7.5", 120, True),
        (10, None, "15", 250, True), (0, 100, "50", 999, False),
    ]):
        db.add(FlashWeightTier(label=f"tier {order}", min_weight_kg=Decimal(lo),
                               max_weight_kg=None if hi is None else Decimal(hi),
                               representative_weight_kg=Decimal(rep), surcharge=Decimal(fee),
                               display_order=order, is_active=active))
    for code, kind, value, cap, limit, used, active in [
        ("PCT20", "percentage", 20, 150, None, 0, True), ("PCT10", "percentage", 10, None, None, 0, True),
        ("FLAT100", "fixed", 100, None, None, 0, True), ("USEDUP", "percentage", 50, None, 5, 5, True),
        ("INACTIVE", "fixed", 500, None, None, 0, False),
    ]:
        db.add(PromoCode(code=code, category="rides", discount_type=kind, discount_value=Decimal(value),
                         max_discount=None if cap is None else Decimal(cap),
                         usage_limit=limit, used_count=used, is_active=active))

    rider = User(phone_number="0000000001", role=UserRole.CUSTOMER, full_name="Test rider")
    db.add(rider)
    await db.flush()
    customer = Customer(user_id=rider.id, loyalty_points=500)
    db.add(customer)
    # Online, approved drivers near the pickups, plus ones the search must skip:
    # busy, offline, pending, without a location, too far, and a vehicle type
    # stored in a different letter case.
    drivers = {}
    for key, vtype, status, online, where in [
        ("tuk_1km", "tuk", DriverStatus.APPROVED, True, _north(FORT, 1.0)),
        ("tuk_busy", "tuk", DriverStatus.APPROVED, True, _north(FORT, 0.4)),
        ("bike_3km", "bike", DriverStatus.APPROVED, True, _north(FORT, 3.0)),
        ("car_far", "car", DriverStatus.APPROVED, True, _north(FORT, 20.0)),
        ("scooter_caps", "Moto Scooter", DriverStatus.APPROVED, True, _north(FORT, 0.8)),
        ("van_no_gps", "van", DriverStatus.APPROVED, True, None),
        ("mini_offline", "mini", DriverStatus.APPROVED, False, _north(FORT, 0.2)),
        ("car_pending", "car", DriverStatus.PENDING, True, _north(FORT, 0.5)),
        ("tuk_nugegoda", "tuk", DriverStatus.APPROVED, True, _north(NUGEGODA, 2.0)),
    ]:
        user = User(phone_number=f"00010000{len(drivers):02d}", role=UserRole.DRIVER, full_name=key)
        db.add(user)
        await db.flush()
        driver = Driver(user_id=user.id, vehicle_type=vtype, status=status, is_online=online,
                        is_approved=status == DriverStatus.APPROVED,
                        current_lat=None if where is None else Decimal(str(round(where[0], 7))),
                        current_lng=None if where is None else Decimal(str(round(where[1], 7))))
        db.add(driver)
        await db.flush()
        drivers[key] = driver
    db.add(Booking(booking_ref="ZGBUSY0001", customer_id=customer.id, driver_id=drivers["tuk_busy"].id,
                   service_type="tuk", status=BookingStatus.ACCEPTED))
    await db.commit()


@contextmanager
def frozen_clock(hhmm: str):
    """Make datetime.now() return `hhmm` Colombo time on a fixed day."""
    hour, minute = map(int, hhmm.split(":"))
    instant = datetime(*DAY, hour, minute, tzinfo=COLOMBO)

    class FrozenDatetime(datetime):
        @classmethod
        def now(cls, tz=None):
            if tz is None:
                return instant.replace(tzinfo=None)
            return instant.astimezone(tz)

    with mock.patch("datetime.datetime", FrozenDatetime):
        yield


def build_cases() -> list[dict]:
    """Every scenario, as plain data: variant, function, time and keyword args."""
    cases = []

    def add(variant, fn, at, name, kwargs):
        cases.append({"id": f"{variant}|{fn}|{at}|{name}", "variant": variant, "fn": fn,
                      "time": at, "kwargs": kwargs})

    def trip(route, **extra):
        pickup, drop = ROUTES[route]
        return {"pickup_lat": pickup[0], "pickup_lng": pickup[1],
                "drop_lat": drop[0], "drop_lng": drop[1], **extra}

    def scenarios():
        for route in ROUTES:
            pickup = ROUTES[route][0]
            yield f"{route}", trip(route)
            near = _north(pickup, 1.5)
            yield f"{route}+driver", trip(route, driver_accepted_lat=near[0], driver_accepted_lng=near[1])
        yield "return", trip("fort_short", trip_type="return")
        yield "one_stop", trip("fort_short", stops=ONE_STOP)
        yield "two_stops", trip("fort_short", stops=TWO_STOPS)
        for code in PROMOS:
            yield f"promo_{code}", trip("fort_short", promo=code)
        for kg in (0.5, 3.0, 7.0, 12.0):
            yield f"flash_{kg}kg", trip("nugegoda_medium", is_flash=True, parcel_weight_kg=kg)
        for points in (150, 50, 1000):
            yield f"redeem_{points}", trip("fort_short", customer="rider", redeem_points=points)
        for hours in (None, 3):
            yield f"rental_{hours}h", trip("fort_short", is_rental=True, rental_hours=hours)
            yield f"rental_{hours}h_PCT20", trip("fort_short", is_rental=True, rental_hours=hours, promo="PCT20")
        yield "courier_3kg", trip("fort_to_kandy", is_courier=True, parcel_weight_kg=3.0)
        yield "courier_packages", trip("fort_to_kandy", is_courier=True, packages=PACKAGES)
        yield "courier_PCT10", trip("nugegoda_medium", is_courier=True, parcel_weight_kg=8.0, promo="PCT10")

    for variant, keep in [
        ("base", lambda name: True),
        ("no_courier_row", lambda name: name.startswith("courier")),
        ("overnight_surge_no_loyalty", lambda name: not name.startswith(("promo_", "flash_"))),
    ]:
        for at in TIMES:
            for name, kwargs in scenarios():
                if not keep(name):
                    continue
                for st in SERVICE_TYPES:
                    add(variant, "single", at, f"{st}|{name}", {"service_type": st, **kwargs})
                bulk = {k: v for k, v in kwargs.items() if not k.startswith("driver_accepted")}
                if name.endswith("+driver"):
                    continue
                add(variant, "bulk", at, name, {"service_types": list(SERVICE_TYPES), **bulk})
    return cases


async def run_case(db, case: dict):
    """Run one scenario through the current fare engine and return a JSON-safe result."""
    kwargs = dict(case["kwargs"])
    if kwargs.pop("customer", None) == "rider":
        kwargs["customer"] = (await db.execute(select(Customer))).scalars().first()
    with frozen_clock(case["time"]):
        try:
            if case["fn"] == "single":
                service_type = kwargs.pop("service_type")
                coords = [kwargs.pop(k) for k in ("pickup_lat", "pickup_lng", "drop_lat", "drop_lng")]
                return await calculate_fare(db, service_type, *coords, **kwargs)
            return await calculate_fares_bulk(db, **kwargs)
        except Exception as e:  # recorded so a changed failure mode also shows up
            return {"error": type(e).__name__}

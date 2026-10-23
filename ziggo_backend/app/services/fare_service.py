"""Fare estimation + distance helpers.

calculate_fare (one vehicle type: estimates, bookings, completion) and
calculate_fares_bulk (every vehicle card at once) share the pricing rules
below, so each rule is written once and a vehicle card always shows the same
price, pickup fee and loyalty points as booking that vehicle. The golden tests
in tests/test_fare_golden.py check both.
"""
from dataclasses import dataclass, field
from decimal import Decimal
from math import radians, sin, cos, asin, sqrt
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from shapely.geometry import Point, Polygon

from ..models import FareSetting, FlashWeightTier, PromoCode, SurgeZone
from ..api.v1.surge_zones import is_time_in_range
from .district_service import district_for
from .promo_service import usable_promo_query

# Fallback fare table (used if DB has no row yet for a service type)
DEFAULTS = {
    "bike":  {"base": 60,  "per_km": 35,  "per_min": 2, "min": 100},
    "tuk":   {"base": 80,  "per_km": 55,  "per_min": 3, "min": 150},
    "car":   {"base": 150, "per_km": 80,  "per_min": 4, "min": 250},
    "van":   {"base": 250, "per_km": 120, "per_min": 5, "min": 400},
    "truck": {"base": 500, "per_km": 200, "per_min": 6, "min": 750},
}

# Hourly rental rates (LKR/hour). Per-vehicle, deliberately separate from the
# per-km ride pricing because rentals are time-bound, not distance-bound.
RENTAL_HOURLY = {
    "bike":  400,
    "tuk":   600,
    "car":   1200,
    "van":   1800,
    "truck": 2500,
}

# Courier (island-wide, 2-3 day, CityPak-style) pricing. Unlike rides/flash
# the fare is weight-led, not distance-led: a flat handling base + the parcel
# weight surcharge (reused from FlashWeightTier), plus a small per-km component
# so cross-island parcels cost a little more than across-town ones.
COURIER_BASE = 250.0          # flat handling fee (LKR)
COURIER_PER_KM = 6.0          # gentle distance component (LKR/km)
# SLA: nearby parcels land in 2 days, longer hauls in 3.
COURIER_FAST_MAX_KM = 30.0

EARTH_KM = 6371.0


def courier_eta_days(distance_km: float) -> int:
    """Promised delivery window in days, by haul distance."""
    return 2 if distance_km <= COURIER_FAST_MAX_KM else 3


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
    dlat = lat2 - lat1
    dlng = lng2 - lng1
    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlng / 2) ** 2
    return 2 * EARTH_KM * asin(sqrt(a))


def estimate_duration_min(distance_km: float) -> int:
    """Assume a city-traffic average of 25 km/h. Returns minutes (min 5)."""
    return max(5, round(distance_km / 25.0 * 60))


RETURN_TRIP_MULTIPLIER = 2.1


@dataclass
class _Rules:
    """Everything a fare depends on besides the trip itself, read once per request."""
    settings: object                  # SystemSettings row, or None
    sys_commission: float
    fare_settings: dict               # service_type -> FareSetting
    peaks: list
    hhmm: str                         # Colombo time, for peak-hour windows
    zones: list                       # active surge zones whose time window is open
    promo: Optional[PromoCode]
    flash_tiers: list
    system_surge: Optional[float]     # system surge multiplier while its window is open
    district: Optional[str] = None    # pickup district, only looked up while district fares are on
    district_base_fares: dict = field(default_factory=dict)  # service_type -> that district's base fare


async def _load_rules(db: AsyncSession, service_types: list[str], promo: Optional[str],
                      need_flash_tiers: bool, pickup: Optional[tuple] = None) -> _Rules:
    from ..models import DistrictFare, PeakHourSetting, SystemSettings
    from datetime import datetime, timezone, timedelta

    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    sys_commission = float(ss.commission_rate) if (ss and ss.commission_rate is not None) else 15.0

    setting_q = await db.execute(select(FareSetting).where(FareSetting.service_type.in_(service_types)))
    fare_settings = {s.service_type: s for s in setting_q.scalars().all()}
    peak_q = await db.execute(select(PeakHourSetting).where(PeakHourSetting.is_active == True))  # noqa: E712
    zone_q = await db.execute(select(SurgeZone).where(SurgeZone.is_active == True))  # noqa: E712

    promo_row = None
    if promo:
        promo_q = await db.execute(usable_promo_query(promo.upper()))
        promo_row = promo_q.scalars().first()

    flash_tiers = []
    if need_flash_tiers:
        flash_q = await db.execute(
            select(FlashWeightTier)
            .where(FlashWeightTier.is_active == True)  # noqa: E712
            .order_by(FlashWeightTier.display_order, FlashWeightTier.id)
        )
        flash_tiers = flash_q.scalars().all()

    # Dynamic surge pricing window check from SystemSettings
    now_colombo = datetime.now(timezone(timedelta(hours=5, minutes=30)))
    system_surge = None
    if ss and ss.surge_start_hour is not None and ss.surge_end_hour is not None:
        start, end = ss.surge_start_hour, ss.surge_end_hour
        if start <= end:
            in_surge = start <= now_colombo.hour < end
        else:
            in_surge = now_colombo.hour >= start or now_colombo.hour < end
        if in_surge:
            system_surge = float(ss.surge_multiplier or 1.0)

    # Surge zone windows use the server's local clock (Asia/Colombo in the containers).
    now_local = datetime.now()
    open_zones = [z for z in zone_q.scalars().all() if is_time_in_range(z.start_time, z.end_time, now_local)]

    # District base fares (Phase 2, feature 04): the pickup's district decides.
    district, district_base_fares = None, {}
    if ss is not None and ss.district_fares_enabled and pickup is not None:
        district = district_for(*pickup)
        if district:
            df_q = await db.execute(select(DistrictFare).where(
                DistrictFare.district == district, DistrictFare.service_type.in_(service_types)))
            district_base_fares = {r.service_type: float(r.base_fare) for r in df_q.scalars().all()}

    return _Rules(
        settings=ss, sys_commission=sys_commission, fare_settings=fare_settings,
        peaks=peak_q.scalars().all(), hhmm=now_colombo.strftime("%H:%M"), zones=open_zones,
        promo=promo_row, flash_tiers=flash_tiers, system_surge=system_surge,
        district=district, district_base_fares=district_base_fares,
    )


def _platform_pct(setting, sys_commission: float) -> float:
    # A category commission of 0 counts as unset and falls back to the system rate.
    if setting and setting.platform_fee_percent is not None and float(setting.platform_fee_percent) > 0:
        return float(setting.platform_fee_percent)
    return sys_commission


def _promo_discount(p, amount: float) -> float:
    if p.discount_type == "percentage":
        discount = amount * (float(p.discount_value) / 100.0)
        if p.max_discount:
            discount = min(discount, float(p.max_discount))
        return discount
    return float(p.discount_value)


def _apply_promo(p, amount: float) -> tuple[float, Optional[str]]:
    """Discount on `amount` and the applied code, or (0.0, None) if the promo can't be used."""
    if p and p.is_active and (p.usage_limit is None or p.used_count < p.usage_limit):
        return _promo_discount(p, amount), p.code
    return 0.0, None


def _flash_surcharge(tiers, weight_kg: float) -> float:
    """Surcharge of the active tier whose [min, max) band covers `weight_kg`.

    The top tier may have ``max_weight_kg is None`` (open-ended). Returns 0 if
    no tier matches.
    """
    for t in tiers:
        min_w = float(t.min_weight_kg or 0)
        max_w = float(t.max_weight_kg) if t.max_weight_kg is not None else None
        if weight_kg >= min_w and (max_w is None or weight_kg < max_w):
            return float(t.surcharge or 0)
    return 0.0


def _route(pickup_lat, pickup_lng, drop_lat, drop_lng, stops) -> tuple[list, float, int]:
    """Clean stops, total distance and estimated duration of pickup → stops → drop.

    BRD: CD-19 — sum of leg distances when intermediate stops are present.
    Stops are an ordered list between pickup and drop; legs cover every
    consecutive pair. With 2 stops the route is pickup→stop1→stop2→drop.
    """
    waypoints = [(pickup_lat, pickup_lng)]
    clean_stops = []
    if stops:
        for st in stops:
            lat = st.get("lat") if isinstance(st, dict) else None
            lng = st.get("lng") if isinstance(st, dict) else None
            if lat is None or lng is None:
                continue
            clean_stops.append({
                "lat": float(lat),
                "lng": float(lng),
                "address": (st.get("address") if isinstance(st, dict) else None) or "",
            })
            waypoints.append((float(lat), float(lng)))
    waypoints.append((drop_lat, drop_lng))

    distance_km = 0.0
    for (a_lat, a_lng), (b_lat, b_lng) in zip(waypoints, waypoints[1:]):
        distance_km += haversine_km(a_lat, a_lng, b_lat, b_lng)
    return clean_stops, distance_km, estimate_duration_min(distance_km)


def _zone_surcharge(rules: _Rules, pickup_lat: float, pickup_lng: float) -> float:
    """Geographic surge: flat charge of every open zone containing the pickup."""
    zone_surcharge = 0.0
    pickup_point = Point(pickup_lng, pickup_lat)
    for z in rules.zones:
        # Create a Shapely Polygon from the coordinates (lng, lat)
        try:
            poly_coords = [(float(pt["lng"]), float(pt["lat"])) for pt in z.coordinates]
            if len(poly_coords) >= 3:
                poly = Polygon(poly_coords)
                if poly.contains(pickup_point):
                    zone_surcharge += float(z.flat_extra_charge or 0.0)
        except Exception:
            pass
    return zone_surcharge


def _rental_fare(rules: _Rules, setting, service_type: str, rental_hours) -> dict:
    """Rental: hourly rate × hours; promo discount and platform-fee split still apply."""
    hours = max(1, int(rental_hours or 1))
    platform_pct = _platform_pct(setting, rules.sys_commission)
    # Use dynamic rental_hourly_rate if defined, otherwise fallback to RENTAL_HOURLY dictionary
    if setting and setting.rental_hourly_rate is not None:
        hourly = float(setting.rental_hourly_rate)
    else:
        hourly = float(RENTAL_HOURLY.get(service_type, RENTAL_HOURLY["car"]))
    fare = hourly * hours
    discount, promo_applied = _apply_promo(rules.promo, fare)
    final = max(0, fare - discount)
    platform_fee = fare * (platform_pct / 100.0)
    return {"hours": hours, "hourly": hourly, "fare": fare, "discount": discount, "promo_code": promo_applied,
            "final": final, "platform_fee": platform_fee, "driver_earnings": fare - platform_fee}


def _courier_fare(rules: _Rules, setting, pickup_lat, pickup_lng, drop_lat, drop_lng,
                  parcel_weight_kg, packages) -> dict:
    """Courier: handling base + parcel weight surcharge + a small per-km component."""
    platform_pct = _platform_pct(setting, rules.sys_commission)
    distance_km = haversine_km(pickup_lat, pickup_lng, drop_lat, drop_lng)
    weight_surcharge = 0.0
    if packages:
        for pkg in packages:
            pkg_weight = float(pkg.get("weight_kg") or 0.0) if isinstance(pkg, dict) else float(getattr(pkg, "weight_kg", 0.0))
            weight_surcharge += _flash_surcharge(rules.flash_tiers, pkg_weight)
    elif parcel_weight_kg is not None:
        weight_surcharge = _flash_surcharge(rules.flash_tiers, float(parcel_weight_kg))

    courier_base = float(setting.base_fare) if setting and setting.base_fare is not None else COURIER_BASE
    courier_per_km = float(setting.per_km_rate) if setting and setting.per_km_rate is not None else COURIER_PER_KM
    fare = courier_base + weight_surcharge + courier_per_km * distance_km
    discount, promo_applied = _apply_promo(rules.promo, fare)
    final = max(0, fare - discount)
    platform_fee = fare * (platform_pct / 100.0)
    return {"distance_km": distance_km, "eta_days": courier_eta_days(distance_km),
            "weight_surcharge": weight_surcharge, "fare": fare, "discount": discount,
            "promo_code": promo_applied, "final": final, "platform_fee": platform_fee,
            "driver_earnings": fare - platform_fee}


def _standard_fare(rules: _Rules, service_type: str, setting, route, pickup_distance_km: float,
                   zone_surcharge: float, is_flash: bool, parcel_weight_kg, trip_type: str) -> dict:
    """Rides and flash parcels."""
    clean_stops, distance_km, duration_min = route
    if setting:
        base = float(setting.base_fare or 0)
        per_km = float(setting.per_km_rate or 0)
        per_min = float(setting.per_minute_rate or 0)
        min_fare = float(setting.min_fare or 0)
        surge = float(setting.surge_multiplier or 1)
        boost_val = float(setting.boost or 0)
        passenger_deductible_pct = float(setting.passenger_deductible or 0)
        pickup_fee_pct = float(setting.pickup_fee or 0)
    else:
        d = DEFAULTS.get(service_type, DEFAULTS["car"])
        base, per_km, per_min, min_fare = d["base"], d["per_km"], d["per_min"], d["min"]
        surge = 1.0
        boost_val, passenger_deductible_pct, pickup_fee_pct = 0.0, 0.0, 0.0
    district_base = rules.district_base_fares.get(service_type)
    if district_base is not None:
        base = district_base
    platform_pct = _platform_pct(setting, rules.sys_commission)

    # Pickup fee: a percentage of the per-km charge for the driver's distance to the pickup
    base_pickup_fee = pickup_distance_km * per_km
    pickup_fee_val = base_pickup_fee * (pickup_fee_pct / 100.0)

    if rules.system_surge is not None:
        surge = rules.system_surge

    raw = (base + per_km * distance_km + per_min * duration_min) * surge
    fare_val = max(raw, min_fare)
    fare_val_original = fare_val

    # Apply category discount percentage before applying anything else
    if setting and setting.discount_percentage:
        discount_pct = float(setting.discount_percentage)
        if discount_pct > 0:
            category_discount = fare_val * (discount_pct / 100.0)
            fare_val = max(0.0, fare_val - category_discount)

    fare_val += boost_val
    fare_val_original += boost_val
    fare_val += pickup_fee_val
    fare_val_original += pickup_fee_val

    # Peak hours surcharge check
    peak_surcharge = 0.0
    for ap in rules.peaks:
        if ap.vehicle_category and ap.vehicle_category != service_type:
            continue
        in_peak = False
        start = ap.start_time
        end = ap.end_time
        if start and end:
            if start <= end:
                in_peak = start <= rules.hhmm < end
            else:
                in_peak = rules.hhmm >= start or rules.hhmm < end
        if in_peak:
            peak_surcharge += float(ap.extra_amount or 0.0)
    fare_val += peak_surcharge
    fare_val_original += peak_surcharge

    fare_val += zone_surcharge
    fare_val_original += zone_surcharge

    # BRD: CD-19 — per-stop fee compensates the driver for the detour.
    stop_fee_total = 0.0
    if clean_stops:
        ss = rules.settings
        per_stop = float(ss.multi_stop_fee_per_stop) if ss and ss.multi_stop_fee_per_stop is not None else 50.0
        stop_fee_total = per_stop * len(clean_stops)
    fare_val += stop_fee_total
    fare_val_original += stop_fee_total

    flash_surcharge = 0.0
    if is_flash and parcel_weight_kg is not None:
        flash_surcharge = _flash_surcharge(rules.flash_tiers, float(parcel_weight_kg))
        fare_val += flash_surcharge
        fare_val_original += flash_surcharge

    if trip_type == "return":
        # Customer travels the route twice; fare gets a small return discount
        # (1.8x instead of 2x) to reflect that the driver doesn't drive empty back.
        fare_val *= RETURN_TRIP_MULTIPLIER
        fare_val_original *= RETURN_TRIP_MULTIPLIER
        distance_km *= 2
        duration_min = round(duration_min * 2)

    discount = 0.0
    discount_original = 0.0
    promo_applied = None
    p = rules.promo
    if p and p.is_active and (p.usage_limit is None or p.used_count < p.usage_limit):
        discount = _promo_discount(p, fare_val)
        discount_original = _promo_discount(p, fare_val_original)
        promo_applied = p.code

    feeable_amount = max(0.0, fare_val - boost_val)
    app_usage_charges = feeable_amount * (platform_pct / 100.0)
    driver_earnings = max(0.0, fare_val - app_usage_charges)

    final_pre_deductible = max(0.0, fare_val - discount)
    passenger_deductible_val = final_pre_deductible * (passenger_deductible_pct / 100.0)
    gross_total = final_pre_deductible + passenger_deductible_val
    deductions = app_usage_charges + passenger_deductible_val

    final_pre_deductible_original = max(0.0, fare_val_original - discount_original)
    passenger_deductible_val_original = final_pre_deductible_original * (passenger_deductible_pct / 100.0)
    gross_total_original = final_pre_deductible_original + passenger_deductible_val_original

    result = {
        "distance_km": round(distance_km, 2),
        "pickup_distance_km": round(pickup_distance_km, 2),
        "duration_min": round(duration_min),
        "fare_amount": round(fare_val, 2),
        "discount_amount": round(discount, 2),
        "final_amount": round(gross_total, 2),
        "original_amount": round(gross_total_original, 2),
        "platform_fee": round(app_usage_charges, 2),
        "driver_earnings": round(driver_earnings, 2),
        "promo_code": promo_applied,
        "surge_multiplier": surge,
        "flash_surcharge": round(flash_surcharge, 2),
        "peak_surcharge": round(peak_surcharge, 2),
        "zone_surcharge": round(zone_surcharge, 2),
        # BRD: CD-19 — surface multi-stop snapshot so the UI can render it
        "stop_count": len(clean_stops),
        "stops_fee": round(stop_fee_total, 2),
        # Snapshot keys
        "pickup_fee": round(pickup_fee_val, 2),
        "boost": round(boost_val, 2),
        "passenger_deductible": round(passenger_deductible_val, 2),
        "app_usage_charges": round(app_usage_charges, 2),
        "deductions": round(deductions, 2),
    }
    if district_base is not None:
        result["district"] = rules.district
        result["district_base_fare"] = round(district_base, 2)
    return result


async def calculate_fare(
    db: AsyncSession,
    service_type: str,
    pickup_lat: float,
    pickup_lng: float,
    drop_lat: float,
    drop_lng: float,
    promo: Optional[str] = None,
    trip_type: str = "one_way",
    is_flash: bool = False,
    parcel_weight_kg: Optional[float] = None,
    is_rental: bool = False,
    rental_hours: Optional[int] = None,
    is_courier: bool = False,
    packages: Optional[list] = None,
    # BRD: RW-01 (earn) + RW-02 (redeem) + RS-07 (display)
    customer=None,
    redeem_points: int = 0,
    # BRD: CD-19 / BE-16 / BR-9 — intermediate stops
    # Each stop is {"lat": float, "lng": float, "address": str?}.
    stops: Optional[list] = None,
    driver_accepted_lat: Optional[float] = None,
    driver_accepted_lng: Optional[float] = None,
) -> dict:
    rules = await _load_rules(
        db, [service_type, "courier"], promo,
        need_flash_tiers=(is_flash and parcel_weight_kg is not None) or is_courier,
        pickup=(pickup_lat, pickup_lng),
    )

    if is_rental:
        r = _rental_fare(rules, rules.fare_settings.get(service_type), service_type, rental_hours)
        rental_dict = {
            "distance_km": 0.0,
            "pickup_distance_km": 0.0,
            "duration_min": r["hours"] * 60,
            "fare_amount": round(r["fare"], 2),
            "discount_amount": round(r["discount"], 2),
            "final_amount": round(r["final"], 2),
            "platform_fee": round(r["platform_fee"], 2),
            "driver_earnings": round(r["driver_earnings"], 2),
            "promo_code": r["promo_code"],
            "surge_multiplier": 1.0,
            "flash_surcharge": 0.0,
            "hourly_rate": r["hourly"],
            "rental_hours": r["hours"],
        }
        return await _enrich_with_loyalty(db, rental_dict, customer, redeem_points)

    if is_courier:
        c = _courier_fare(rules, rules.fare_settings.get("courier"), pickup_lat, pickup_lng,
                          drop_lat, drop_lng, parcel_weight_kg, packages)
        courier_dict = {
            "distance_km": round(c["distance_km"], 2),
            "pickup_distance_km": 0.0,
            "duration_min": round(c["eta_days"] * 24 * 60),
            "fare_amount": round(c["fare"], 2),
            "discount_amount": round(c["discount"], 2),
            "final_amount": round(c["final"], 2),
            "platform_fee": round(c["platform_fee"], 2),
            "driver_earnings": round(c["driver_earnings"], 2),
            "promo_code": c["promo_code"],
            "surge_multiplier": 1.0,
            "flash_surcharge": round(c["weight_surcharge"], 2),
            "courier_eta_days": c["eta_days"],
        }
        return await _enrich_with_loyalty(db, courier_dict, customer, redeem_points)

    setting = rules.fare_settings.get(service_type)
    pickup_distance_km = 0.0
    if driver_accepted_lat is not None and driver_accepted_lng is not None:
        pickup_distance_km = haversine_km(driver_accepted_lat, driver_accepted_lng, pickup_lat, pickup_lng)
    else:
        from .matching_service import find_nearest_driver
        search_radius = float(setting.search_radius_km) if (setting and setting.search_radius_km is not None) else 10.0
        nearest = await find_nearest_driver(db, pickup_lat, pickup_lng, service_type, max_distance_km=search_radius)
        if nearest and nearest.current_lat is not None and nearest.current_lng is not None:
            pickup_distance_km = haversine_km(float(nearest.current_lat), float(nearest.current_lng), pickup_lat, pickup_lng)

    fare_dict = _standard_fare(
        rules, service_type, setting, _route(pickup_lat, pickup_lng, drop_lat, drop_lng, stops),
        pickup_distance_km, _zone_surcharge(rules, pickup_lat, pickup_lng), is_flash, parcel_weight_kg, trip_type,
    )
    return await _enrich_with_loyalty(db, fare_dict, customer, redeem_points)


def to_decimal(x: float) -> Decimal:
    return Decimal(str(round(x, 2)))


async def _enrich_with_loyalty(
    db: AsyncSession,
    fare: dict,
    customer,
    redeem_points: int,
) -> dict:
    """Add points-earnable + apply redemption to a fare dict.

    Always populates `points_earnable` (computed from `final_amount` before
    redemption — what you'd earn from the cash side of the transaction).
    If `customer` + `redeem_points > 0`, also clamps the redemption via
    `loyalty_service.quote_redemption` and reduces `final_amount` /
    `platform_fee` / `driver_earnings` accordingly.
    """
    from . import loyalty_service as L

    # Set defaults for new snapshot fields if not present (e.g. on courier / rental paths)
    if "pickup_fee" not in fare:
        fare["pickup_fee"] = 0.0
    if "boost" not in fare:
        fare["boost"] = 0.0
    if "passenger_deductible" not in fare:
        fare["passenger_deductible"] = 0.0
    if "app_usage_charges" not in fare:
        fare["app_usage_charges"] = float(fare.get("platform_fee", 0))
    if "deductions" not in fare:
        fare["deductions"] = float(fare.get("app_usage_charges", 0)) + float(fare.get("passenger_deductible", 0))

    # `final_amount` here is post-promo, pre-redemption.
    pre_redemption_final = float(fare.get("final_amount", 0))
    pre_redemption_original = float(fare.get("original_amount", pre_redemption_final))
    earnable = await L.points_earnable_for(db, pre_redemption_final)

    actual_points = 0
    redeem_discount = 0.0
    redeem_reason = None

    if customer is not None and (redeem_points or 0) > 0:
        pts, val, reason = await L.quote_redemption(
            db, customer, int(redeem_points), Decimal(str(pre_redemption_final))
        )
        actual_points = pts
        redeem_discount = float(val)
        redeem_reason = reason

        if actual_points > 0:
            new_final = max(0.0, pre_redemption_final - redeem_discount)
            fare["final_amount"] = round(new_final, 2)
            fare["original_amount"] = round(max(0.0, pre_redemption_original - redeem_discount), 2)

    fare["points_earnable"] = earnable
    fare["redeem_points_used"] = actual_points
    fare["redeem_discount"] = round(redeem_discount, 2)
    fare["redeem_reason"] = redeem_reason
    return fare


async def calculate_fares_bulk(
    db: AsyncSession,
    service_types: list[str],
    pickup_lat: float,
    pickup_lng: float,
    drop_lat: float,
    drop_lng: float,
    promo: Optional[str] = None,
    trip_type: str = "one_way",
    is_flash: bool = False,
    parcel_weight_kg: Optional[float] = None,
    is_rental: bool = False,
    rental_hours: Optional[int] = None,
    is_courier: bool = False,
    packages: Optional[list] = None,
    customer=None,
    redeem_points: int = 0,
    stops: Optional[list] = None,
) -> dict[str, dict]:
    """High-performance bulk fare calculator that batches all DB queries into a single round."""
    from ..models import Driver, DriverStatus
    from .matching_service import busy_driver_ids

    rules = await _load_rules(
        db, list(set(service_types + (["courier"] if is_courier else []))), promo,
        need_flash_tiers=(is_flash and parcel_weight_kg is not None) or is_courier,
        pickup=(pickup_lat, pickup_lng),
    )

    # Nearest free online driver of each vehicle type, found once for all cards.
    # Types match exactly, as in dispatch and calculate_fare, so each card's pickup
    # fee is the one the booking would charge.
    busy = await busy_driver_ids(db)
    drv_q = await db.execute(
        select(Driver.id, Driver.vehicle_type, Driver.current_lat, Driver.current_lng).where(
            Driver.is_online == True,  # noqa: E712
            Driver.status == DriverStatus.APPROVED,
        )
    )
    nearest_dist_by_type: dict[str, float] = {}
    for d in drv_q.all():
        if d.id in busy or d.current_lat is None or d.current_lng is None:
            continue
        dist = haversine_km(float(d.current_lat), float(d.current_lng), pickup_lat, pickup_lng)
        if d.vehicle_type not in nearest_dist_by_type or dist < nearest_dist_by_type[d.vehicle_type]:
            nearest_dist_by_type[d.vehicle_type] = dist

    route = _route(pickup_lat, pickup_lng, drop_lat, drop_lng, stops)
    zone_surcharge = _zone_surcharge(rules, pickup_lat, pickup_lng)

    def flat_estimate(service_type: str, fields: dict, platform_fee: float, passenger_pays: float) -> dict:
        # Rentals and courier carry no surcharges; their snapshot keys are zero.
        return {
            "service_type": service_type,
            **fields,
            "original_amount": round(passenger_pays, 2),
            "peak_surcharge": 0.0,
            "zone_surcharge": 0.0,
            "stop_count": 0,
            "stops_fee": 0.0,
            "pickup_fee": 0.0,
            "boost": 0.0,
            "passenger_deductible": 0.0,
            "app_usage_charges": round(platform_fee, 2),
            "deductions": round(platform_fee, 2),
        }

    results: dict[str, dict] = {}

    for service_type in service_types:
        try:
            if is_rental:
                r = _rental_fare(rules, rules.fare_settings.get(service_type), service_type, rental_hours)
                fare_dict = flat_estimate(service_type, {
                    "distance_km": 0.0,
                    "pickup_distance_km": 0.0,
                    "duration_min": r["hours"] * 60,
                    "fare_amount": round(r["fare"], 2),
                    "discount_amount": round(r["discount"], 2),
                    "final_amount": round(r["final"], 2),
                    "platform_fee": round(r["platform_fee"], 2),
                    "driver_earnings": round(r["driver_earnings"], 2),
                    "promo_code": r["promo_code"],
                    "surge_multiplier": 1.0,
                    "flash_surcharge": 0.0,
                }, r["platform_fee"], r["final"])
            elif is_courier:
                c = _courier_fare(rules, rules.fare_settings.get("courier"), pickup_lat, pickup_lng,
                                  drop_lat, drop_lng, parcel_weight_kg, packages)
                fare_dict = flat_estimate(service_type, {
                    "distance_km": round(c["distance_km"], 2),
                    "pickup_distance_km": 0.0,
                    "duration_min": round(c["eta_days"] * 24 * 60),
                    "fare_amount": round(c["fare"], 2),
                    "discount_amount": round(c["discount"], 2),
                    "final_amount": round(c["final"], 2),
                    "platform_fee": round(c["platform_fee"], 2),
                    "driver_earnings": round(c["driver_earnings"], 2),
                    "promo_code": c["promo_code"],
                    "surge_multiplier": 1.0,
                    "flash_surcharge": round(c["weight_surcharge"], 2),
                    "courier_eta_days": c["eta_days"],
                }, c["platform_fee"], c["final"])
            else:
                # Standard Ride / Flash Calculation
                setting = rules.fare_settings.get(service_type)
                search_radius = float(setting.search_radius_km) if (setting and setting.search_radius_km is not None) else 10.0
                pickup_distance_km = 0.0
                d_dist = nearest_dist_by_type.get(service_type)
                if d_dist is not None and d_dist <= search_radius:
                    pickup_distance_km = d_dist
                fare_dict = {
                    "service_type": service_type,
                    **_standard_fare(rules, service_type, setting, route, pickup_distance_km,
                                     zone_surcharge, is_flash, parcel_weight_kg, trip_type),
                }

            # Same loyalty points and redemption as booking this vehicle.
            results[service_type] = await _enrich_with_loyalty(db, fare_dict, customer, redeem_points)
        except Exception as e:
            import logging
            logging.error(f"Error calculating bulk fare for {service_type}: {e}", exc_info=True)
            continue

    return results

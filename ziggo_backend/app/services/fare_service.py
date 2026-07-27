"""Fare estimation + distance helpers."""
from decimal import Decimal
from math import radians, sin, cos, asin, sqrt
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from shapely.geometry import Point, Polygon

from ..models import FareSetting, FlashWeightTier, PromoCode, SurgeZone
from ..api.v1.surge_zones import is_time_in_range

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


RETURN_TRIP_MULTIPLIER = 1.8


async def _flash_surcharge(db: AsyncSession, weight_kg: float) -> float:
    """Look up the admin-configured surcharge for a parcel weight.

    Finds the active tier whose [min, max) band covers the given weight. The
    top tier may have ``max_weight_kg is None`` (open-ended). Returns 0 if no
    matching tier is configured.
    """
    q = await db.execute(
        select(FlashWeightTier)
        .where(FlashWeightTier.is_active == True)  # noqa: E712
        .order_by(FlashWeightTier.display_order, FlashWeightTier.id)
    )
    tiers = q.scalars().all()
    for t in tiers:
        min_w = float(t.min_weight_kg or 0)
        max_w = float(t.max_weight_kg) if t.max_weight_kg is not None else None
        if weight_kg >= min_w and (max_w is None or weight_kg < max_w):
            return float(t.surcharge or 0)
    return 0.0


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
    from ..models import SystemSettings
    from datetime import datetime, timezone, timedelta
    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    sys_commission = float(ss.commission_rate) if (ss and ss.commission_rate is not None) else 15.0

    # Rental: short-circuit the distance-based math. Fare = hourly * hours,
    # promo discount still applies, platform-fee split still applies.
    if is_rental:
        hours = max(1, int(rental_hours or 1))
        setting_q = await db.execute(
            select(FareSetting).where(FareSetting.service_type == service_type)
        )
        setting = setting_q.scalars().first()
        platform_pct = float(setting.platform_fee_percent) if (setting and setting.platform_fee_percent is not None and float(setting.platform_fee_percent) > 0) else sys_commission
        
        # Use dynamic rental_hourly_rate if defined, otherwise fallback to RENTAL_HOURLY dictionary
        if setting and setting.rental_hourly_rate is not None:
            hourly = float(setting.rental_hourly_rate)
        else:
            hourly = float(RENTAL_HOURLY.get(service_type, RENTAL_HOURLY["car"]))
            
        fare = hourly * hours

        discount = 0.0
        promo_applied = None
        if promo:
            promo_q = await db.execute(
                select(PromoCode).where(PromoCode.code == promo.upper())
            )
            p = promo_q.scalars().first()
            if p and p.is_active and (
                p.usage_limit is None or p.used_count < p.usage_limit
            ):
                if p.discount_type == "percentage":
                    discount = fare * (float(p.discount_value) / 100.0)
                    if p.max_discount:
                        discount = min(discount, float(p.max_discount))
                else:
                    discount = float(p.discount_value)
                promo_applied = p.code

        final = max(0, fare - discount)
        platform_fee = final * (platform_pct / 100.0)
        passenger_pays = final + platform_fee
        driver_earnings = passenger_pays - platform_fee

        rental_dict = {
            "distance_km": 0.0,
            "pickup_distance_km": 0.0,
            "duration_min": hours * 60,
            "fare_amount": round(fare, 2),
            "discount_amount": round(discount, 2),
            "final_amount": round(passenger_pays, 2),
            "platform_fee": round(platform_fee, 2),
            "driver_earnings": round(driver_earnings, 2),
            "promo_code": promo_applied,
            "surge_multiplier": 1.0,
            "flash_surcharge": 0.0,
            "hourly_rate": hourly,
            "rental_hours": hours,
        }
        return await _enrich_with_loyalty(db, rental_dict, customer, redeem_points)

    if is_courier:
        setting_q = await db.execute(
            select(FareSetting).where(FareSetting.service_type == "courier")
        )
        setting = setting_q.scalars().first()
        platform_pct = float(setting.platform_fee_percent) if (setting and setting.platform_fee_percent is not None and float(setting.platform_fee_percent) > 0) else sys_commission

        distance_km = haversine_km(pickup_lat, pickup_lng, drop_lat, drop_lng)
        weight_surcharge = 0.0
        if packages:
            for pkg in packages:
                pkg_weight = float(pkg.get("weight_kg") or 0.0) if isinstance(pkg, dict) else float(getattr(pkg, "weight_kg", 0.0))
                weight_surcharge += await _flash_surcharge(db, pkg_weight)
        elif parcel_weight_kg is not None:
            weight_surcharge = await _flash_surcharge(db, float(parcel_weight_kg))
        
        courier_base = float(setting.base_fare) if setting and setting.base_fare is not None else COURIER_BASE
        courier_per_km = float(setting.per_km_rate) if setting and setting.per_km_rate is not None else COURIER_PER_KM
        
        fare = courier_base + weight_surcharge + courier_per_km * distance_km
        eta_days = courier_eta_days(distance_km)

        discount = 0.0
        promo_applied = None
        if promo:
            promo_q = await db.execute(
                select(PromoCode).where(PromoCode.code == promo.upper())
            )
            p = promo_q.scalars().first()
            if p and p.is_active and (
                p.usage_limit is None or p.used_count < p.usage_limit
            ):
                if p.discount_type == "percentage":
                    discount = fare * (float(p.discount_value) / 100.0)
                    if p.max_discount:
                        discount = min(discount, float(p.max_discount))
                else:
                    discount = float(p.discount_value)
                promo_applied = p.code

        final = max(0, fare - discount)
        platform_fee = final * (platform_pct / 100.0)
        passenger_pays = final + platform_fee
        driver_earnings = passenger_pays - platform_fee

        courier_dict = {
            "distance_km": round(distance_km, 2),
            "pickup_distance_km": 0.0,
            "duration_min": round(eta_days * 24 * 60),
            "fare_amount": round(fare, 2),
            "discount_amount": round(discount, 2),
            "final_amount": round(passenger_pays, 2),
            "platform_fee": round(platform_fee, 2),
            "driver_earnings": round(driver_earnings, 2),
            "promo_code": promo_applied,
            "surge_multiplier": 1.0,
            "flash_surcharge": round(weight_surcharge, 2),
            "courier_eta_days": eta_days,
        }
        return await _enrich_with_loyalty(db, courier_dict, customer, redeem_points)

    # BRD: CD-19 — sum of leg distances when intermediate stops are present.
    # Stops are an ordered list between pickup and drop; legs cover every
    # consecutive pair. With 2 stops the route is pickup→stop1→stop2→drop.
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
    duration_min = estimate_duration_min(distance_km)
    setting_q = await db.execute(
        select(FareSetting).where(FareSetting.service_type == service_type)
    )
    setting = setting_q.scalars().first()

    if setting:
        base = float(setting.base_fare or 0)
        per_km = float(setting.per_km_rate or 0)
        per_min = float(setting.per_minute_rate or 0)
        min_fare = float(setting.min_fare or 0)
        platform_pct = float(setting.platform_fee_percent) if (setting.platform_fee_percent is not None and float(setting.platform_fee_percent) > 0) else sys_commission
        surge = float(setting.surge_multiplier or 1)
        boost_val = float(setting.boost or 0)
        passenger_deductible_pct = float(setting.passenger_deductible or 0)
        pickup_fee_pct = float(setting.pickup_fee or 0)
    else:
        d = DEFAULTS.get(service_type, DEFAULTS["car"])
        base, per_km, per_min, min_fare = d["base"], d["per_km"], d["per_min"], d["min"]
        platform_pct = sys_commission
        surge = 1.0
        boost_val, passenger_deductible_pct, pickup_fee_pct = 0.0, 0.0, 0.0

    pickup_distance_km = 0.0
    if driver_accepted_lat is not None and driver_accepted_lng is not None:
        pickup_distance_km = haversine_km(driver_accepted_lat, driver_accepted_lng, pickup_lat, pickup_lng)
    else:
        from .matching_service import find_nearest_driver
        search_radius = float(setting.search_radius_km) if (setting and setting.search_radius_km is not None) else 10.0
        nearest = await find_nearest_driver(db, pickup_lat, pickup_lng, service_type, max_distance_km=search_radius)
        if nearest and nearest.current_lat is not None and nearest.current_lng is not None:
            pickup_distance_km = haversine_km(float(nearest.current_lat), float(nearest.current_lng), pickup_lat, pickup_lng)
    
    # Recalculate pickup fee as percentage of distance * per_km rate
    base_pickup_fee = pickup_distance_km * per_km
    pickup_fee_val = base_pickup_fee * (pickup_fee_pct / 100.0)

    # Dynamic surge pricing window check from SystemSettings
    if ss:
        start = ss.surge_start_hour
        end = ss.surge_end_hour
        mult = float(ss.surge_multiplier or 1.0)
        
        colombo_tz = timezone(timedelta(hours=5, minutes=30))
        current_hour = datetime.now(colombo_tz).hour
        
        in_surge = False
        if start is not None and end is not None:
            if start <= end:
                in_surge = start <= current_hour < end
            else:
                in_surge = current_hour >= start or current_hour < end
                
        if in_surge:
            surge = mult

    raw = (base + per_km * distance_km + per_min * duration_min) * surge
    fare_val = max(raw, min_fare)
    
    # Apply category discount percentage before applying anything else
    if setting and setting.discount_percentage:
        discount_pct = float(setting.discount_percentage)
        if discount_pct > 0:
            category_discount = fare_val * (discount_pct / 100.0)
            fare_val = max(0.0, fare_val - category_discount)

    fare_val += boost_val
    fare_val += pickup_fee_val

    # Peak hours surcharge check
    peak_surcharge = 0.0
    from ..models import PeakHourSetting
    peak_q = await db.execute(select(PeakHourSetting).where(PeakHourSetting.is_active == True))
    active_peaks = peak_q.scalars().all()
    if active_peaks:
        colombo_tz = timezone(timedelta(hours=5, minutes=30))
        current_time_str = datetime.now(colombo_tz).strftime("%H:%M")
        for ap in active_peaks:
            if ap.vehicle_category and ap.vehicle_category != service_type:
                continue
            in_peak = False
            start = ap.start_time
            end = ap.end_time
            if start and end:
                if start <= end:
                    in_peak = start <= current_time_str < end
                else:
                    in_peak = current_time_str >= start or current_time_str < end
            if in_peak:
                peak_surcharge += float(ap.extra_amount or 0.0)
        fare_val += peak_surcharge
        
    # Geographic Surge Zones check
    zone_surcharge = 0.0
    zone_q = await db.execute(select(SurgeZone).where(SurgeZone.is_active == True))
    active_zones = zone_q.scalars().all()
    if active_zones:
        now_local = datetime.now()
        pickup_point = Point(pickup_lng, pickup_lat)
        for z in active_zones:
            if is_time_in_range(z.start_time, z.end_time, now_local):
                # Create a Shapely Polygon from the coordinates (lng, lat)
                try:
                    poly_coords = [(float(pt["lng"]), float(pt["lat"])) for pt in z.coordinates]
                    if len(poly_coords) >= 3:
                        poly = Polygon(poly_coords)
                        if poly.contains(pickup_point):
                            zone_surcharge += float(z.flat_extra_charge or 0.0)
                except Exception:
                    pass
        fare_val += zone_surcharge


    # BRD: CD-19 — per-stop fee compensates the driver for the detour.
    stop_fee_total = 0.0
    if clean_stops:
        per_stop = float(ss.multi_stop_fee_per_stop) if ss and ss.multi_stop_fee_per_stop is not None else 50.0
        stop_fee_total = per_stop * len(clean_stops)
        fare_val += stop_fee_total

    flash_surcharge = 0.0
    if is_flash and parcel_weight_kg is not None:
        flash_surcharge = await _flash_surcharge(db, float(parcel_weight_kg))
        fare_val += flash_surcharge

    is_return = trip_type == "return"
    if is_return:
        # Customer travels the route twice; fare gets a small return discount
        # (1.8x instead of 2x) to reflect that the driver doesn't drive empty back.
        fare_val *= RETURN_TRIP_MULTIPLIER
        distance_km *= 2
        duration_min = round(duration_min * 2)

    discount = 0.0
    promo_applied = None
    if promo:
        promo_q = await db.execute(select(PromoCode).where(PromoCode.code == promo.upper()))
        p = promo_q.scalars().first()
        if p and p.is_active and (p.usage_limit is None or p.used_count < p.usage_limit):
            if p.discount_type == "percentage":
                discount = fare_val * (float(p.discount_value) / 100.0)
                if p.max_discount:
                    discount = min(discount, float(p.max_discount))
            else:
                discount = float(p.discount_value)
            promo_applied = p.code

    final_pre_deductible = max(0.0, fare_val - discount)
    passenger_deductible_val = final_pre_deductible * (passenger_deductible_pct / 100.0)
    feeable_amount = max(0.0, final_pre_deductible - boost_val)
    app_usage_charges = feeable_amount * (platform_pct / 100.0)
    
    gross_total = final_pre_deductible + passenger_deductible_val + app_usage_charges
    deductions = app_usage_charges + passenger_deductible_val
    driver_earnings = gross_total - deductions

    fare_dict = {
        "distance_km": round(distance_km, 2),
        "pickup_distance_km": round(pickup_distance_km, 2),
        "duration_min": round(duration_min),
        "fare_amount": round(fare_val, 2),
        "discount_amount": round(discount, 2),
        "final_amount": round(gross_total, 2),
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
            # Platform fee + driver earnings recompute against the new final.
            # We preserve the ratio implied by the original numbers so a
            # missing FareSetting doesn't change the split here.
            if pre_redemption_final > 0:
                platform_ratio = float(fare.get("platform_fee", 0)) / pre_redemption_final
            else:
                platform_ratio = 0.0
            new_platform = round(new_final * platform_ratio, 2)
            fare["final_amount"] = round(new_final, 2)
            fare["platform_fee"] = new_platform
            fare["app_usage_charges"] = new_platform
            fare["deductions"] = round(new_platform + float(fare.get("passenger_deductible", 0)), 2)
            fare["driver_earnings"] = round(new_final - fare["deductions"], 2)

    fare["points_earnable"] = earnable
    fare["redeem_points_used"] = actual_points
    fare["redeem_discount"] = round(redeem_discount, 2)
    fare["redeem_reason"] = redeem_reason
    return fare


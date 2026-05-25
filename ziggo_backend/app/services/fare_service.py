"""Fare estimation + distance helpers."""
from decimal import Decimal
from math import radians, sin, cos, asin, sqrt
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ..models import FareSetting, FlashWeightTier, PromoCode

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

EARTH_KM = 6371.0


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
    # BRD: RW-01 (earn) + RW-02 (redeem) + RS-07 (display)
    customer=None,
    redeem_points: int = 0,
    # BRD: CD-19 / BE-16 / BR-9 — intermediate stops
    # Each stop is {"lat": float, "lng": float, "address": str?}.
    stops: Optional[list] = None,
) -> dict:
    # Rental: short-circuit the distance-based math. Fare = hourly * hours,
    # promo discount still applies, platform-fee split still applies.
    if is_rental:
        hours = max(1, int(rental_hours or 1))
        setting_q = await db.execute(
            select(FareSetting).where(FareSetting.service_type == service_type)
        )
        setting = setting_q.scalars().first()
        platform_pct = float(setting.platform_fee_percent or 15) if setting else 15.0
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
        driver_earnings = final - platform_fee

        rental_dict = {
            "distance_km": 0.0,
            "duration_min": hours * 60,
            "fare_amount": round(fare, 2),
            "discount_amount": round(discount, 2),
            "final_amount": round(final, 2),
            "platform_fee": round(platform_fee, 2),
            "driver_earnings": round(driver_earnings, 2),
            "promo_code": promo_applied,
            "surge_multiplier": 1.0,
            "flash_surcharge": 0.0,
            "hourly_rate": hourly,
            "rental_hours": hours,
        }
        return await _enrich_with_loyalty(db, rental_dict, customer, redeem_points)

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
        platform_pct = float(setting.platform_fee_percent or 15)
        surge = float(setting.surge_multiplier or 1)
    else:
        d = DEFAULTS.get(service_type, DEFAULTS["car"])
        base, per_km, per_min, min_fare = d["base"], d["per_km"], d["per_min"], d["min"]
        platform_pct, surge = 15.0, 1.0

    raw = (base + per_km * distance_km + per_min * duration_min) * surge
    fare = max(raw, min_fare)

    # BRD: CD-19 — per-stop fee compensates the driver for the detour.
    stop_fee_total = 0.0
    if clean_stops:
        from ..models import SystemSettings
        ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
        ss = ss_q.scalars().first()
        per_stop = float(ss.multi_stop_fee_per_stop) if ss and ss.multi_stop_fee_per_stop is not None else 50.0
        stop_fee_total = per_stop * len(clean_stops)
        fare += stop_fee_total

    flash_surcharge = 0.0
    if is_flash and parcel_weight_kg is not None:
        flash_surcharge = await _flash_surcharge(db, float(parcel_weight_kg))
        fare += flash_surcharge

    is_return = trip_type == "return"
    if is_return:
        # Customer travels the route twice; fare gets a small return discount
        # (1.8x instead of 2x) to reflect that the driver doesn't drive empty back.
        fare *= RETURN_TRIP_MULTIPLIER
        distance_km *= 2
        duration_min = round(duration_min * 2)

    discount = 0.0
    promo_applied = None
    if promo:
        promo_q = await db.execute(select(PromoCode).where(PromoCode.code == promo.upper()))
        p = promo_q.scalars().first()
        if p and p.is_active and (p.usage_limit is None or p.used_count < p.usage_limit):
            if p.discount_type == "percentage":
                discount = fare * (float(p.discount_value) / 100.0)
                if p.max_discount:
                    discount = min(discount, float(p.max_discount))
            else:
                discount = float(p.discount_value)
            promo_applied = p.code

    final = max(0, fare - discount)
    platform_fee = final * (platform_pct / 100.0)
    driver_earnings = final - platform_fee

    base_dict = {
        "distance_km": round(distance_km, 2),
        "duration_min": duration_min,
        "fare_amount": round(fare, 2),
        "discount_amount": round(discount, 2),
        "final_amount": round(final, 2),
        "platform_fee": round(platform_fee, 2),
        "driver_earnings": round(driver_earnings, 2),
        "promo_code": promo_applied,
        "surge_multiplier": surge,
        "flash_surcharge": round(flash_surcharge, 2),
        # BRD: CD-19 — surface multi-stop snapshot so the UI can render it
        "stop_count": len(clean_stops),
        "stops_fee": round(stop_fee_total, 2),
    }
    return await _enrich_with_loyalty(db, base_dict, customer, redeem_points)


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
            fare["driver_earnings"] = round(new_final - new_platform, 2)

    fare["points_earnable"] = earnable
    fare["redeem_points_used"] = actual_points
    fare["redeem_discount"] = round(redeem_discount, 2)
    fare["redeem_reason"] = redeem_reason
    return fare

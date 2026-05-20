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

        return {
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

    distance_km = haversine_km(pickup_lat, pickup_lng, drop_lat, drop_lng)
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

    return {
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
    }


def to_decimal(x: float) -> Decimal:
    return Decimal(str(round(x, 2)))

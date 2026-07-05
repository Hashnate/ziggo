"""Market delivery fee engine — distance + weight based.

fee = base_fee + per_km * max(0, distance_km - free_km)
    + ceil(max(0, weight_kg - free_weight_kg)) * per_kg_over
fee = clamp(fee, min_fee, max_fee)

Rates are module constants (admin-tunable later, mirroring fare_service's
DEFAULTS). All money is Decimal, rounded to whole rupees.
"""
from decimal import Decimal, ROUND_HALF_UP
from math import ceil
from typing import Iterable, Optional, Tuple

from .fare_service import haversine_km

# --- Tunable rates (LKR) ----------------------------------------------------
BASE_FEE = Decimal("120")        # covers the first FREE_KM
FREE_KM = Decimal("2")
PER_KM = Decimal("40")
FREE_WEIGHT_KG = Decimal("5")    # weight surcharge kicks in above this
PER_KG_OVER = Decimal("30")      # per whole kg over FREE_WEIGHT_KG
MIN_FEE = Decimal("120")
MAX_FEE = Decimal("600")

# Fallbacks for missing data.
DEFAULT_ITEM_WEIGHT_KG = Decimal("0.5")
DEFAULT_RADIUS_KM = Decimal("8")


def vendor_radius_km(delivery_radius_km) -> Decimal:
    """Effective delivery radius for a vendor, with the default fallback."""
    if delivery_radius_km is None or Decimal(str(delivery_radius_km)) <= 0:
        return DEFAULT_RADIUS_KM
    return Decimal(str(delivery_radius_km))


def order_weight_kg(lines: Iterable[Tuple[object, int]]) -> Decimal:
    """Sum (product.weight_kg or default) * qty over (product, qty) pairs."""
    total = Decimal("0")
    for product, qty in lines:
        w = getattr(product, "weight_kg", None)
        per_unit = Decimal(str(w)) if w is not None else DEFAULT_ITEM_WEIGHT_KG
        total += per_unit * Decimal(int(qty))
    return total


def compute_delivery_fee(
    distance_km: float,
    weight_kg: Decimal,
    base_fee_override: Optional[Decimal] = None,
    pickup_fee: Optional[Decimal] = None,
    per_km_rate: Optional[Decimal] = None,
    boost: Optional[Decimal] = None,
    items_subtotal: Decimal = Decimal("0.00"),
) -> Decimal:
    """Distance + weight delivery fee, clamped and rounded to whole rupees.

    `base_fee_override` lets a vendor's own `delivery_fee` replace BASE_FEE
    while still layering distance and weight on top.
    """
    if pickup_fee is not None:
        base = items_subtotal * (pickup_fee / Decimal("100"))
    else:
        if base_fee_override and base_fee_override > 0:
            base = items_subtotal * (base_fee_override / Decimal("100"))
        else:
            base = BASE_FEE
    per_km = per_km_rate if per_km_rate is not None else PER_KM
    boost_val = items_subtotal * (boost / Decimal("100")) if boost is not None else Decimal("0")
    dist = Decimal(str(max(0.0, distance_km)))

    distance_fee = base + per_km * max(Decimal("0"), dist - FREE_KM) + boost_val

    over = max(Decimal("0"), weight_kg - FREE_WEIGHT_KG)
    weight_extra = Decimal(ceil(over)) * PER_KG_OVER

    fee = distance_fee + weight_extra
    fee = max(MIN_FEE, min(MAX_FEE, fee))
    return fee.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


def quote(
    vendor_lat,
    vendor_lng,
    drop_lat: float,
    drop_lng: float,
    lines: Iterable[Tuple[object, int]],
    delivery_radius_km,
    base_fee_override: Optional[Decimal] = None,
    pickup_fee: Optional[Decimal] = None,
    per_km_rate: Optional[Decimal] = None,
    boost: Optional[Decimal] = None,
) -> dict:
    """Full quote: distance, weight, fee, and whether the drop is in range.

    Returns floats/Decimal in a dict; callers decide whether to hard-block on
    `in_range`. Raises ValueError if the vendor has no coordinates.
    """
    if vendor_lat is None or vendor_lng is None:
        raise ValueError("Vendor has no location set")

    distance_km = haversine_km(
        float(vendor_lat), float(vendor_lng), float(drop_lat), float(drop_lng)
    )
    weight = order_weight_kg(lines)
    items_subtotal = Decimal("0.00")
    for product, qty in lines:
        items_subtotal += Decimal(str(getattr(product, "price", 0))) * Decimal(int(qty))
    fee = compute_delivery_fee(
        distance_km,
        weight,
        base_fee_override=base_fee_override,
        pickup_fee=pickup_fee,
        per_km_rate=per_km_rate,
        boost=boost,
        items_subtotal=items_subtotal,
    )
    radius = vendor_radius_km(delivery_radius_km)

    return {
        "distance_km": round(distance_km, 2),
        "weight_kg": weight,
        "fee": fee,
        "radius_km": radius,
        "in_range": Decimal(str(distance_km)) <= radius,
    }

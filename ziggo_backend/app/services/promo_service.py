"""Promo code lookups shared by every checkout."""
from sqlalchemy import func, select

from ..models import (
    Booking,
    BookingStatus,
    EventOrder,
    EventOrderStatus,
    FoodOrder,
    FoodOrderStatus,
    MarketOrder,
    MarketOrderStatus,
    PromoCode,
)

# Promo category -> (orders it covers, their cancelled status, their "done" status).
# Rides covers every booking: rides, flash, courier, rental and scan-and-go.
_SURFACES = {
    "rides": (Booking, BookingStatus.CANCELLED, BookingStatus.COMPLETED),
    "food": (FoodOrder, FoodOrderStatus.CANCELLED, FoodOrderStatus.DELIVERED),
    "market": (MarketOrder, MarketOrderStatus.CANCELLED, MarketOrderStatus.DELIVERED),
    "events": (EventOrder, EventOrderStatus.CANCELLED, EventOrderStatus.CONFIRMED),
}


def usable_promo_query(code: str):
    """Select the promo with this code, only while now is inside its valid_from / valid_to window.

    Same window rule as the customer-facing promo list in misc.py, so a code
    stops working exactly when it disappears from that list.
    """
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    return select(PromoCode).where(
        PromoCode.code == code,
        (PromoCode.valid_from == None) | (PromoCode.valid_from <= now),  # noqa: E711
        (PromoCode.valid_to == None) | (PromoCode.valid_to >= now),  # noqa: E711
    )


def promo_vehicles(p) -> list[str]:
    return [v.strip() for v in (p.vehicle_types or "").split(",") if v.strip()]


async def counted_uses(db, p, customer_id=None) -> int:
    """Uses of promo `p` that count toward its limits, overall or for one customer.

    With return_use_on_cancel, cancelled bookings/orders don't count. The
    overall figure starts from the stored used_count rather than counting
    orders, because food/market orders only record their code since
    per-customer limits were added.
    """
    if customer_id is None and not p.return_use_on_cancel:
        return p.used_count or 0
    n = 0
    for model, cancelled, _ in _SURFACES.values():
        q = select(func.count()).select_from(model).where(model.promo_code == p.code)
        if customer_id is None:
            q = q.where(model.status == cancelled)
        else:
            q = q.where(model.customer_id == customer_id)
            if p.return_use_on_cancel:
                q = q.where(model.status != cancelled)
        n += (await db.execute(q)).scalar() or 0
    if customer_id is None:
        return max(0, (p.used_count or 0) - n)
    return n


async def is_new_customer(db, customer_id: int, category: str) -> bool:
    """No completed booking / delivered order in the promo's category ("all" = any)."""
    surfaces = [_SURFACES[category]] if category in _SURFACES else _SURFACES.values()
    for model, _, done in surfaces:
        q = select(model.id).where(model.customer_id == customer_id, model.status == done).limit(1)
        if (await db.execute(q)).first():
            return False
    return True


async def usable_promo(db, code, surface: str, customer_id=None, locked: bool = False):
    """The promo with this code if this customer can use it at this checkout, else None.

    `surface` is rides | food | market | events. Checks the date window,
    Active, category, the total and per-customer limits and new-customers-only;
    the order value and vehicle are checked by `promo_applies`, since one lookup
    can price several vehicles. `locked` is for re-pricing a booking that
    already took the code: it then only has to exist.
    """
    if not code:
        return None
    code = code.upper()
    if locked:
        return (await db.execute(select(PromoCode).where(PromoCode.code == code))).scalars().first()
    p = (await db.execute(usable_promo_query(code))).scalars().first()
    if p is None or not p.is_active or (p.category or "all") not in ("all", surface):
        return None
    if p.usage_limit is not None and await counted_uses(db, p) >= p.usage_limit:
        return None
    if p.per_customer_limit is not None or p.new_customers_only:
        if customer_id is None:
            return None
        if p.per_customer_limit is not None and await counted_uses(db, p, customer_id) >= p.per_customer_limit:
            return None
        if p.new_customers_only and not await is_new_customer(db, customer_id, p.category or "all"):
            return None
    return p


def promo_applies(p, amount, locked: bool = False, vehicle=None) -> bool:
    """Whether promo `p` (from `usable_promo`) can be used on an order worth `amount` before any discount.

    A locked promo (already on the booking) stays applied even if it has since
    been switched off, hit a limit (the booking's own use can be the one that
    hit it), or the final fare dropped under the minimum order.
    """
    if p is None:
        return False
    if locked:
        return True
    if vehicle and p.vehicle_types and vehicle not in promo_vehicles(p):
        return False
    return float(amount) >= float(p.min_order_amount or 0)

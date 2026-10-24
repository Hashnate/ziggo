"""Promo code lookups shared by every checkout."""
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional

from sqlalchemy import func, select

from ..models import (
    Booking,
    BookingStatus,
    EventOrder,
    EventOrderStatus,
    FareSetting,
    FoodOrder,
    FoodOrderStatus,
    MarketOrder,
    MarketOrderStatus,
    PromoCode,
)

_SL = timezone(timedelta(hours=5, minutes=30))
_SURFACE_LABELS = {"rides": "rides", "food": "food orders", "market": "Mart orders", "events": "event tickets"}

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


@dataclass
class PromoCheck:
    """Result of `check_promo`: the promo, or why the customer can't use it here."""
    promo: Optional[PromoCode]
    reason: Optional[str] = None
    surface: str = "rides"
    locked: bool = False
    vehicle_names: dict = field(default_factory=dict)

    def refusal(self, amount, vehicle=None) -> Optional[str]:
        """Why the code doesn't apply to an order worth `amount` before any discount, or None if it does."""
        if self.promo is None:
            return self.reason
        if self.locked:
            return None
        return _fit_refusal(self.promo, amount, vehicle, self.surface, self.vehicle_names)


def _fit_refusal(p, amount, vehicle, surface, vehicle_names) -> Optional[str]:
    if vehicle and p.vehicle_types and vehicle not in promo_vehicles(p):
        names = ", ".join(vehicle_names.get(v, v) for v in promo_vehicles(p))
        return f"This code is only for {names}."
    minimum = float(p.min_order_amount or 0)
    if float(amount) < minimum:
        what = "fare" if surface == "rides" else "order"
        return f"This code needs a minimum {what} of Rs.{minimum:,.0f}."
    return None


async def check_promo(db, code, surface: str, customer_id=None, locked: bool = False) -> PromoCheck:
    """Whether this customer can use this code at this checkout, and if not, why.

    `surface` is rides | food | market | events. Checks the date window,
    Active, category, the total and per-customer limits and new-customers-only;
    the order value and vehicle are checked by `PromoCheck.refusal`, since one
    lookup can price several vehicles. `locked` is for re-pricing a booking
    that already took the code: it then only has to exist. Reasons are shown
    to the customer as they are.
    """
    if not code:
        return PromoCheck(None, "Enter a promo code.", surface)
    p = (await db.execute(select(PromoCode).where(PromoCode.code == code.strip().upper()))).scalars().first()
    if p is None:
        return PromoCheck(None, "We couldn't find this promo code.", surface)
    names = {}
    if p.vehicle_types:
        rows = await db.execute(select(FareSetting.service_type, FareSetting.display_name))
        names = {st: dn or st for st, dn in rows.all()}
    check = PromoCheck(p, None, surface, locked, names)
    if locked:
        return check

    def no(reason):
        return PromoCheck(None, reason, surface)

    now = datetime.now(timezone.utc)
    if p.valid_from and p.valid_from > now:
        return no(f"This code starts on {p.valid_from.astimezone(_SL):%d %b}.")
    if p.valid_to and p.valid_to < now:
        return no("This code has expired.")
    if not p.is_active:
        return no("This code isn't active right now.")
    category = p.category or "all"
    if category not in ("all", surface):
        return no(f"This code is for {_SURFACE_LABELS.get(category, category)} only.")
    if p.usage_limit is not None and await counted_uses(db, p) >= p.usage_limit:
        return no("This code has been fully used.")
    if p.per_customer_limit is not None or p.new_customers_only:
        if customer_id is None:
            return no("Log in as a customer to use this code.")
        if p.per_customer_limit is not None and await counted_uses(db, p, customer_id) >= p.per_customer_limit:
            if p.per_customer_limit == 1:
                return no("You've already used this code.")
            return no(f"You've already used this code {p.per_customer_limit} times.")
        if p.new_customers_only and not await is_new_customer(db, customer_id, category):
            return no("This code is for new customers only.")
    return check


async def usable_promo(db, code, surface: str, customer_id=None, locked: bool = False):
    """The promo with this code if this customer can use it at this checkout, else None (see `check_promo`)."""
    return (await check_promo(db, code, surface, customer_id, locked)).promo


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
    return _fit_refusal(p, amount, vehicle, "rides", {}) is None


def promo_discount(p, amount: Decimal) -> Decimal:
    """Discount on a food / market / event order worth `amount`: percentage (capped) or fixed."""
    if p.discount_type == "percentage":
        discount = (amount * Decimal(str(p.discount_value)) / Decimal("100")).quantize(Decimal("0.01"))
        if p.max_discount:
            discount = min(discount, Decimal(str(p.max_discount)))
        return discount
    return Decimal(str(p.discount_value))

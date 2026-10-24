"""Promo code lookups shared by every checkout."""
from sqlalchemy import select

from ..models import PromoCode


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


def booking_promo_query(code: str, locked: bool = False):
    """`locked` is for re-pricing a booking that already took the code: the
    customer keeps it to the end of the trip, so the date window no longer
    matters (see `promo_applies`)."""
    if locked:
        return select(PromoCode).where(PromoCode.code == code)
    return usable_promo_query(code)


def promo_applies(p, amount, locked: bool = False) -> bool:
    """Whether promo `p` can be used on an order worth `amount` before any discount.

    A locked promo (already on the booking) stays applied even if it has since
    been switched off, hit its usage limit (the booking's own use can be the
    one that hit it), or the final fare dropped under the minimum order.
    """
    if p is None:
        return False
    if locked:
        return True
    if not p.is_active:
        return False
    if p.usage_limit is not None and (p.used_count or 0) >= p.usage_limit:
        return False
    return float(amount) >= float(p.min_order_amount or 0)

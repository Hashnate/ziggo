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

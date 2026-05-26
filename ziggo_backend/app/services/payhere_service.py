"""PayHere — Sri Lankan card + wallet gateway.

When PAYHERE_MERCHANT_ID is empty this module's `is_enabled()` returns False
and the API layer returns 503 from /payments/payhere/* endpoints. The wallet
top-up flow auto-falls back to the existing mock direct-credit path.

Docs: https://support.payhere.lk/api-&-mobile-sdk/checkout-api

Flow:
  1. Client POSTs /payments/payhere/checkout with {amount, purpose}.
     We return a fully-signed payload + the hosted-checkout URL.
  2. Client opens the URL in a WebView; user pays on PayHere.
  3. PayHere POSTs to our /payments/payhere/notify (server-to-server).
  4. We verify the md5 signature, credit the wallet, mark the txn done.
  5. Client polls /payments/payhere/status/<order_id> or watches WS.
"""
from __future__ import annotations

import hashlib
from decimal import Decimal
from typing import Optional

from ..config import settings


CHECKOUT_URL_SANDBOX = "https://sandbox.payhere.lk/pay/checkout"
CHECKOUT_URL_LIVE = "https://www.payhere.lk/pay/checkout"


def is_enabled() -> bool:
    return bool(
        settings.PAYHERE_MERCHANT_ID
        and settings.PAYHERE_MERCHANT_SECRET
    )


def checkout_url() -> str:
    return CHECKOUT_URL_LIVE if (settings.PAYHERE_MODE or "").lower() == "live" else CHECKOUT_URL_SANDBOX


def _md5_upper(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest().upper()


def build_checkout_payload(
    *,
    order_id: str,
    amount: Decimal,
    currency: str = "LKR",
    items: str,
    first_name: str,
    last_name: str,
    email: str,
    phone: str,
    address: str = "",
    city: str = "Colombo",
    country: str = "Sri Lanka",
    return_url: str = "",
    cancel_url: str = "",
) -> dict:
    """Build the form fields expected by PayHere's hosted checkout.

    Signature per docs:
      hash = MD5( merchant_id + order_id + amount + currency + MD5(secret) )
    Amount must be formatted to 2 decimals.
    """
    if not is_enabled():
        raise RuntimeError("PayHere is not configured")

    amount_str = f"{Decimal(amount):.2f}"
    inner = _md5_upper(settings.PAYHERE_MERCHANT_SECRET or "")
    hash_value = _md5_upper(
        f"{settings.PAYHERE_MERCHANT_ID}{order_id}{amount_str}{currency}{inner}"
    )

    return {
        "url": checkout_url(),
        "fields": {
            "merchant_id": settings.PAYHERE_MERCHANT_ID,
            "return_url": return_url,
            "cancel_url": cancel_url,
            "notify_url": settings.PAYHERE_NOTIFY_URL or "",
            "order_id": order_id,
            "items": items,
            "currency": currency,
            "amount": amount_str,
            "first_name": first_name,
            "last_name": last_name,
            "email": email,
            "phone": phone,
            "address": address,
            "city": city,
            "country": country,
            "hash": hash_value,
        },
    }


def verify_notification(
    *,
    merchant_id: str,
    order_id: str,
    payhere_amount: str,
    payhere_currency: str,
    status_code: str,
    md5sig: str,
) -> bool:
    """Verify the md5sig posted by PayHere to /notify.

    Per docs:
      md5sig = MD5( merchant_id + order_id + payhere_amount + payhere_currency
                    + status_code + MD5(secret) )
    Returns True iff the signature matches AND the merchant_id matches the
    configured one. Caller still has to check status_code == "2" for success.
    """
    if not is_enabled():
        return False
    if merchant_id != settings.PAYHERE_MERCHANT_ID:
        return False
    inner = _md5_upper(settings.PAYHERE_MERCHANT_SECRET or "")
    expected = _md5_upper(
        f"{merchant_id}{order_id}{payhere_amount}{payhere_currency}{status_code}{inner}"
    )
    return expected == md5sig.upper()


# PayHere status_code values (per docs):
#   2  → success
#   0  → pending
#  -1  → cancelled
#  -2  → failed
#  -3  → chargedback
STATUS_SUCCESS = "2"
STATUS_PENDING = "0"
STATUS_CANCELLED = "-1"
STATUS_FAILED = "-2"
STATUS_CHARGEDBACK = "-3"


def status_label(code: str) -> str:
    return {
        STATUS_SUCCESS: "success",
        STATUS_PENDING: "pending",
        STATUS_CANCELLED: "cancelled",
        STATUS_FAILED: "failed",
        STATUS_CHARGEDBACK: "chargedback",
    }.get(code, f"unknown ({code})")

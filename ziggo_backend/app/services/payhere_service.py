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

PREAPPROVE_URL_SANDBOX = "https://sandbox.payhere.lk/pay/preapprove"
PREAPPROVE_URL_LIVE = "https://www.payhere.lk/pay/preapprove"


def is_enabled() -> bool:
    return bool(
        settings.PAYHERE_MERCHANT_ID
        and settings.PAYHERE_MERCHANT_SECRET
    )


def preapprove_url() -> str:
    return PREAPPROVE_URL_LIVE if (settings.PAYHERE_MODE or "").lower() == "live" else PREAPPROVE_URL_SANDBOX


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


def build_preapprove_payload(
    *,
    order_id: str,
    items: str = "Add Card",
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
    """Build form fields for PayHere Pre-approval API.
    Uses LKR and 0.00 amount for pre-authorization.
    """
    if not is_enabled():
        raise RuntimeError("PayHere is not configured")

    amount_str = "0.00"
    currency = "LKR"
    inner = _md5_upper(settings.PAYHERE_MERCHANT_SECRET or "")
    hash_value = _md5_upper(
        f"{settings.PAYHERE_MERCHANT_ID}{order_id}{amount_str}{currency}{inner}"
    )

    return {
        "url": preapprove_url(),
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


async def charge_tokenized_card(
    *,
    customer_token: str,
    amount: Decimal,
    order_id: str,
    items: str,
    currency: str = "LKR",
) -> dict:
    """Charge a pre-approved card token via PayHere Automated Charging API.
    Falls back to mock mode if App credentials are not configured.
    """
    import base64
    import httpx
    import secrets

    app_id = settings.PAYHERE_APP_ID
    app_secret = settings.PAYHERE_APP_SECRET

    if not app_id or not app_secret:
        # Mock mode fallback for development/testing
        print(f"[payhere] MOCK charge card token={customer_token[:8]}... amount={amount} order_id={order_id}")
        return {
            "success": True,
            "transaction_id": f"MOCK-TXN-{secrets.token_hex(6).upper()}",
            "status_code": "2",
            "message": "Simulated card charge success (Mock Mode)",
        }

    mode = (settings.PAYHERE_MODE or "sandbox").lower()
    base_url = "https://www.payhere.lk" if mode == "live" else "https://sandbox.payhere.lk"
    
    token_url = f"{base_url}/merchant/v1/oauth/token"
    charge_url = f"{base_url}/merchant/v1/payment/charge"

    # 1. Fetch OAuth access token
    auth_str = f"{app_id}:{app_secret}"
    b64_auth = base64.b64encode(auth_str.encode()).decode()

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            token_resp = await client.post(
                token_url,
                headers={"Authorization": f"Basic {b64_auth}"},
                data={"grant_type": "client_credentials"},
            )
            token_resp.raise_for_status()
            access_token = token_resp.json().get("access_token")
            if not access_token:
                return {"success": False, "message": "Failed to retrieve access token"}
        except Exception as e:
            print(f"[payhere] oauth failed: {e}")
            return {"success": False, "message": f"OAuth failed: {str(e)}"}

        # 2. Call Charging API
        payload = {
            "type": "PAYMENT",
            "customer_token": customer_token,
            "amount": float(amount),
            "currency": currency,
            "order_id": order_id,
            "items": items,
        }

        try:
            charge_resp = await client.post(
                charge_url,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json"
                },
                json=payload,
            )
            charge_resp.raise_for_status()
            res_data = charge_resp.json()
            
            # PayHere Charging API returns status: 1 or 2 on success
            status_val = res_data.get("status")
            msg_val = res_data.get("msg") or res_data.get("message") or "Success"
            
            # The inner data block has payment details
            data_block = res_data.get("data") or {}
            payment_id = data_block.get("payment_id") or f"TXN-{secrets.token_hex(4).upper()}"
            
            if status_val in (1, 2) or "success" in str(msg_val).lower():
                return {
                    "success": True,
                    "transaction_id": str(payment_id),
                    "message": str(msg_val),
                }
            else:
                return {
                    "success": False,
                    "message": f"Declined: {msg_val} (status={status_val})",
                }
        except Exception as e:
            print(f"[payhere] automated charging failed: {e}")
            return {"success": False, "message": f"Charge API call failed: {str(e)}"}

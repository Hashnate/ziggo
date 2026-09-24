"""iPay — Sri Lankan payment gateway (LOLC / LankaPay).

When IPAY_MERCHANT_ID is empty, `is_enabled()` returns False and the API
layer returns 503 from /payments/ipay/* endpoints. The wallet top-up flow
auto-falls back to the existing mock direct-credit path.

Flow:
  1. Client POSTs /payments/ipay/checkout with {amount, purpose}.
     We return a fully-signed payload + the hosted-checkout URL.
  2. Client opens the URL in a WebView; user pays on iPay.
  3. iPay POSTs to our /payments/ipay/notify (server-to-server webhook).
  4. We verify the SHA256/HMAC signature, credit the wallet, mark the txn done.
  5. Client polls /payments/ipay/status/<order_id> or watches WebSocket.
"""
from __future__ import annotations

import hashlib
import hmac
from decimal import Decimal
from typing import Optional

from ..config import settings


CHECKOUT_URL_SANDBOX = "https://sandbox.ipay.lk/ipg/checkout"
CHECKOUT_URL_LIVE = "https://www.ipay.lk/ipg/checkout"

PREAPPROVE_URL_SANDBOX = "https://sandbox.ipay.lk/ipg/token/register"
PREAPPROVE_URL_LIVE = "https://www.ipay.lk/ipg/token/register"

STATUS_SUCCESS = "2"
STATUS_PENDING = "0"
STATUS_CANCELLED = "-1"
STATUS_FAILED = "-2"
STATUS_CHARGEDBACK = "-3"


def is_enabled() -> bool:
    """Returns True if iPay is configured (or fallback PayHere credentials exist)."""
    return bool(
        (settings.IPAY_MERCHANT_ID and (settings.IPAY_SECRET_KEY or settings.IPAY_API_KEY))
        or (settings.PAYHERE_MERCHANT_ID and settings.PAYHERE_MERCHANT_SECRET)
    )


def merchant_id() -> str:
    return settings.IPAY_MERCHANT_ID or settings.PAYHERE_MERCHANT_ID or ""


def secret_key() -> str:
    return settings.IPAY_SECRET_KEY or settings.IPAY_API_KEY or settings.PAYHERE_MERCHANT_SECRET or ""


def mode() -> str:
    return (settings.IPAY_MODE or settings.PAYHERE_MODE or "sandbox").lower()


def notify_url() -> str:
    return settings.IPAY_NOTIFY_URL or settings.PAYHERE_NOTIFY_URL or ""


def checkout_url() -> str:
    return CHECKOUT_URL_LIVE if mode() == "live" else CHECKOUT_URL_SANDBOX


def preapprove_url() -> str:
    return PREAPPROVE_URL_LIVE if mode() == "live" else PREAPPROVE_URL_SANDBOX


def _generate_signature(data: str, key: str) -> str:
    """Generate HMAC-SHA256 signature encoded as uppercase hex string."""
    return hmac.new(key.encode("utf-8"), data.encode("utf-8"), hashlib.sha256).hexdigest().upper()


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
    """Build form fields and signature expected by iPay's hosted checkout."""
    if not is_enabled():
        raise RuntimeError("iPay is not configured")

    m_id = merchant_id()
    sec = secret_key()
    amount_str = f"{Decimal(amount):.2f}"

    raw_signature_payload = f"{m_id}{order_id}{amount_str}{currency}"
    signature = _generate_signature(raw_signature_payload, sec)

    return {
        "url": checkout_url(),
        "fields": {
            "merchant_id": m_id,
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
            "return_url": return_url or settings.IPAY_REDIRECT_URL or "",
            "cancel_url": cancel_url or settings.IPAY_CANCEL_URL or "",
            "notify_url": notify_url(),
            "signature": signature,
            "hash": signature,
        },
    }


def verify_notification(
    *,
    merchant_id_val: str,
    order_id: str,
    ipay_amount: str,
    ipay_currency: str,
    status_code: str,
    signature: str,
) -> bool:
    """Verify notification webhook signature posted by iPay."""
    if not is_enabled():
        return False

    m_id = merchant_id()
    if merchant_id_val != m_id:
        return False

    sec = secret_key()
    # Support both HMAC-SHA256 and MD5 compatibility
    expected_hmac = _generate_signature(
        f"{m_id}{order_id}{ipay_amount}{ipay_currency}{status_code}", sec
    )

    inner_md5 = hashlib.md5(sec.encode("utf-8")).hexdigest().upper()
    expected_md5 = hashlib.md5(
        f"{m_id}{order_id}{ipay_amount}{ipay_currency}{status_code}{inner_md5}".encode("utf-8")
    ).hexdigest().upper()

    sig_upper = signature.upper()
    return sig_upper == expected_hmac or sig_upper == expected_md5


def status_label(code: str) -> str:
    return {
        STATUS_SUCCESS: "success",
        STATUS_PENDING: "pending",
        STATUS_CANCELLED: "cancelled",
        STATUS_FAILED: "failed",
        STATUS_CHARGEDBACK: "chargedback",
        "SUCCESS": "success",
        "1": "success",
    }.get(str(code), f"unknown ({code})")


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
    """Build form fields for iPay Card Tokenization / Pre-approval."""
    if not is_enabled():
        raise RuntimeError("iPay is not configured")

    m_id = merchant_id()
    sec = secret_key()
    amount_str = "0.00"
    currency = "LKR"

    raw_signature_payload = f"{m_id}{order_id}{amount_str}{currency}"
    signature = _generate_signature(raw_signature_payload, sec)

    return {
        "url": preapprove_url(),
        "fields": {
            "merchant_id": m_id,
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
            "return_url": return_url or settings.IPAY_REDIRECT_URL or "",
            "cancel_url": cancel_url or settings.IPAY_CANCEL_URL or "",
            "notify_url": notify_url(),
            "signature": signature,
            "hash": signature,
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
    """Charge a saved card token via iPay Direct Token API.
    Falls back to mock mode if App credentials are not configured.
    """
    import base64
    import httpx
    import secrets

    app_id = settings.IPAY_APP_ID or settings.IPAY_MERCHANT_ID or settings.PAYHERE_APP_ID
    app_secret = settings.IPAY_APP_SECRET or settings.IPAY_SECRET_KEY or settings.PAYHERE_APP_SECRET

    if not app_id or not app_secret:
        # Mock mode fallback for development/testing
        print(f"[ipay] MOCK charge card token={customer_token[:8]}... amount={amount} order_id={order_id}")
        return {
            "success": True,
            "transaction_id": f"IPAY-MOCK-{secrets.token_hex(6).upper()}",
            "status_code": "2",
            "message": "Simulated iPay card charge success (Mock Mode)",
        }

    gateway_mode = mode()
    base_url = "https://www.ipay.lk" if gateway_mode == "live" else "https://sandbox.ipay.lk"
    charge_url = f"{base_url}/api/v1/payment/charge-token"

    payload = {
        "merchant_id": merchant_id(),
        "customer_token": customer_token,
        "amount": float(amount),
        "currency": currency,
        "order_id": order_id,
        "items": items,
    }

    sig_data = f"{merchant_id()}{order_id}{float(amount):.2f}{currency}"
    payload["signature"] = _generate_signature(sig_data, app_secret)

    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            charge_resp = await client.post(
                charge_url,
                headers={
                    "Authorization": f"Bearer {app_secret}",
                    "Content-Type": "application/json",
                    "X-Merchant-ID": merchant_id(),
                },
                json=payload,
            )
            charge_resp.raise_for_status()
            res_data = charge_resp.json()

            status_val = res_data.get("status") or res_data.get("status_code")
            msg_val = res_data.get("msg") or res_data.get("message") or "Success"
            payment_id = (
                res_data.get("transaction_id")
                or res_data.get("payment_id")
                or res_data.get("data", {}).get("payment_id")
                or f"IPAY-TXN-{secrets.token_hex(4).upper()}"
            )

            if str(status_val) in ("1", "2", "SUCCESS", "200") or "success" in str(msg_val).lower():
                return {
                    "success": True,
                    "transaction_id": str(payment_id),
                    "message": str(msg_val),
                }
            else:
                return {
                    "success": False,
                    "message": f"Declined by iPay: {msg_val} (status={status_val})",
                }
        except Exception as e:
            print(f"[ipay] charge failed: {e}")
            return {"success": False, "message": f"iPay Charge API error: {str(e)}"}

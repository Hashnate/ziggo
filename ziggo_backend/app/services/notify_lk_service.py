"""Notify.lk SMS gateway (Sri Lanka).

Used for real OTP delivery in production. When NOTIFY_LK_* settings are
empty this module is a no-op — OTP keeps landing in the uvicorn console
via the existing print() in auth_service.py, which is what DEV_MODE relies
on. So the rest of the app keeps working with zero changes whether the
gateway is configured or not.

API reference: https://notify.lk/api/v1/send-sms
"""
from __future__ import annotations

import httpx

from ..config import settings


_ENDPOINT = "https://app.notify.lk/api/v1/send"


def _enabled() -> bool:
    return bool(
        settings.NOTIFY_LK_USER_ID
        and settings.NOTIFY_LK_API_KEY
        and settings.NOTIFY_LK_SENDER_ID
    )


def _normalize(phone: str) -> str:
    """Notify.lk wants E.164 without the leading + (e.g. 947XXXXXXXX).

    The app stores numbers either as '0771234567' or '+94771234567'.
    Convert both to '94771234567'.
    """
    p = phone.strip().replace(" ", "").replace("-", "")
    if p.startswith("+"):
        p = p[1:]
    if p.startswith("0"):
        p = "94" + p[1:]
    return p


async def send_otp(phone_number: str, code: str) -> bool:
    """Fire-and-forget OTP send. Returns True on HTTP 200.

    Errors are logged but never raised — OTP delivery failure must not block
    the auth flow (the code is also returned via DEV_MODE / printed to logs).
    """
    if not _enabled():
        return False

    to = _normalize(phone_number)
    msg = f"Your Ziggo verification code is {code}. It expires in 5 minutes."
    params = {
        "user_id": settings.NOTIFY_LK_USER_ID,
        "api_key": settings.NOTIFY_LK_API_KEY,
        "sender_id": settings.NOTIFY_LK_SENDER_ID,
        "to": to,
        "message": msg,
    }
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            r = await client.get(_ENDPOINT, params=params)
        ok = r.status_code == 200 and '"status":"success"' in r.text
        if not ok:
            print(f"[notify.lk] failed for {to}: HTTP {r.status_code} {r.text[:200]}")
        else:
            print(f"[notify.lk] sent OTP to {to}")
        return ok
    except Exception as e:
        print(f"[notify.lk] exception sending to {to}: {type(e).__name__}: {e}")
        return False

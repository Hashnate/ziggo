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
from sqlalchemy.ext.asyncio import AsyncSession

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


async def send_otp(phone_number: str, code: str, site_name: str) -> bool:
    """OTP send via Notify.lk. Returns True on HTTP 200.

    Errors are logged but never raised — OTP delivery failure must not block
    the auth flow (the code is also returned via DEV_MODE / printed to logs).
    """
    if not _enabled():
        return False

    to = _normalize(phone_number)
    msg = f"<#> Your {site_name} verification code is {code}. It expires in 5 minutes."
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


def _is_unicode(text: str) -> bool:
    """Check if text contains characters outside GSM standard charset (e.g. Sinhala, Tamil, emojis)."""
    return any(ord(c) > 127 for c in text)


def _split_sms_message(msg: str, is_unicode: bool) -> list[str]:
    """Split message into segments if it exceeds Notify.lk maximum limit (603 chars for Unicode)."""
    max_len = 550 if is_unicode else 900
    if len(msg) <= max_len:
        return [msg]

    paragraphs = msg.split("\n")
    chunks: list[str] = []
    curr = ""
    for p in paragraphs:
        candidate = (curr + "\n" + p).strip() if curr else p
        if len(candidate) <= max_len:
            curr = candidate
        else:
            if curr:
                chunks.append(curr)
                curr = p
            else:
                words = p.split(" ")
                for w in words:
                    cand_w = (curr + " " + w).strip() if curr else w
                    if len(cand_w) <= max_len:
                        curr = cand_w
                    else:
                        if curr:
                            chunks.append(curr)
                        curr = w
    if curr:
        chunks.append(curr)

    if len(chunks) > 1:
        return [f"({i+1}/{len(chunks)})\n{c}" for i, c in enumerate(chunks)]
    return chunks


async def send_sms(phone_number: str, message: str) -> bool:
    """Send arbitrary SMS via Notify.lk gateway. Automatically splits long messages exceeding 603 chars."""
    if not _enabled():
        print("[notify.lk] SMS gateway credentials not configured")
        return False

    to = _normalize(phone_number)
    if not to or len(to) < 9:
        print(f"[notify.lk] skipped sending SMS, invalid phone: {phone_number}")
        return False

    is_uni = _is_unicode(message)
    parts = _split_sms_message(message, is_uni)

    all_ok = True
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            for part in parts:
                params = {
                    "user_id": settings.NOTIFY_LK_USER_ID,
                    "api_key": settings.NOTIFY_LK_API_KEY,
                    "sender_id": settings.NOTIFY_LK_SENDER_ID,
                    "to": to,
                    "message": part,
                }
                if is_uni:
                    params["type"] = "unicode"

                r = await client.get(_ENDPOINT, params=params)
                ok = r.status_code == 200 and '"status":"success"' in r.text
                if not ok:
                    print(f"[notify.lk] failed for {to}: HTTP {r.status_code} {r.text[:200]}")
                    all_ok = False
                else:
                    print(f"[notify.lk] sent SMS part to {to} (unicode={is_uni}, len={len(part)})")
        return all_ok
    except Exception as e:
        print(f"[notify.lk] exception sending to {to}: {type(e).__name__}: {e}")
        return False


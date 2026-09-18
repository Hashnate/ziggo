"""APNs VoIP (PushKit) pushes — the iOS half of the incoming-ride "call".

Android gets its call-style alert from a data-only FCM message that wakes
`firebaseMessagingBackgroundHandler` and draws a full-screen intent. iOS has no
equivalent: `fullScreenIntent` doesn't exist there, and a normal push is a
banner that respects silent mode. The only way to ring a locked iPhone like
Uber/PickMe do is a PushKit VoIP push that the app reports to CallKit.

Firebase can't send those — VoIP pushes must go straight to Apple, over HTTP/2,
addressed to the `<bundle-id>.voip` topic with `apns-push-type: voip`. So this
module talks to APNs directly using token-based auth (a .p8 key).

Unconfigured is a supported state: `is_enabled()` returns False and every send
is a no-op, so iOS drivers simply keep getting the ordinary FCM banner.

IMPORTANT (iOS 13+): every VoIP push the device receives MUST result in the app
reporting an incoming call to CallKit. If the app doesn't, iOS kills it and
eventually stops delivering VoIP pushes altogether. Only send these for events
that genuinely present a call screen — currently `new_ride_request` only.
"""
from __future__ import annotations

import json
import time
import uuid
from typing import Any, Optional

import httpx
import jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..models import User

_PROD_HOST = "https://api.push.apple.com"
_SANDBOX_HOST = "https://api.sandbox.push.apple.com"

# Apple rejects tokens older than 1 hour and refuses refreshes more often than
# every 20 minutes. 50 minutes sits safely between the two.
_TOKEN_TTL_SECONDS = 50 * 60

_auth_key: Optional[str] = None
_cached_jwt: Optional[str] = None
_cached_jwt_at: float = 0.0
_client: Optional[httpx.AsyncClient] = None


def is_enabled() -> bool:
    return bool(
        settings.APNS_AUTH_KEY_PATH
        and settings.APNS_KEY_ID
        and settings.APNS_TEAM_ID
        and settings.APNS_BUNDLE_ID
    )


def _load_auth_key() -> Optional[str]:
    global _auth_key
    if _auth_key is not None:
        return _auth_key
    try:
        with open(settings.APNS_AUTH_KEY_PATH, "r") as f:
            _auth_key = f.read()
    except Exception as e:
        print(f"[apns] cannot read auth key at {settings.APNS_AUTH_KEY_PATH}: {e!r}")
        return None
    return _auth_key


def _provider_token() -> Optional[str]:
    """Signed ES256 JWT, cached until it approaches Apple's 1-hour limit."""
    global _cached_jwt, _cached_jwt_at
    now = time.time()
    if _cached_jwt and (now - _cached_jwt_at) < _TOKEN_TTL_SECONDS:
        return _cached_jwt

    key = _load_auth_key()
    if not key:
        return None
    try:
        _cached_jwt = jwt.encode(
            {"iss": settings.APNS_TEAM_ID, "iat": int(now)},
            key,
            algorithm="ES256",
            headers={"kid": settings.APNS_KEY_ID},
        )
        _cached_jwt_at = now
    except Exception as e:
        print(f"[apns] failed to sign provider token: {e!r}")
        return None
    return _cached_jwt


def _http() -> httpx.AsyncClient:
    """One long-lived HTTP/2 client — APNs expects connection reuse."""
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(
            http2=True,
            timeout=httpx.Timeout(10.0, connect=5.0),
        )
    return _client


async def aclose() -> None:
    global _client
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None


async def send_voip(device_token: str, payload: dict[str, Any]) -> bool:
    """Deliver one VoIP push. Returns True only on a 200 from Apple."""
    if not is_enabled():
        return False
    token = _provider_token()
    if not token:
        return False

    host = _SANDBOX_HOST if settings.APNS_USE_SANDBOX else _PROD_HOST
    url = f"{host}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": f"{settings.APNS_BUNDLE_ID}.voip",
        "apns-push-type": "voip",
        "apns-priority": "10",
        # A ride offer is worthless once the 30 s window closes — tell Apple
        # not to retry it later.
        "apns-expiration": "0",
    }
    try:
        resp = await _http().post(url, headers=headers, content=json.dumps(payload))
    except Exception as e:
        print(f"[apns] voip send failed: {type(e).__name__}: {e}")
        return False

    if resp.status_code == 200:
        return True

    reason = ""
    try:
        reason = (resp.json() or {}).get("reason", "")
    except Exception:
        reason = resp.text[:200]
    # BadDeviceToken / Unregistered mean the token is dead — the app will
    # re-register a fresh one on next launch.
    print(f"[apns] voip rejected status={resp.status_code} reason={reason}")
    return False


async def send_ride_call(db: AsyncSession, user_id: int, payload: dict[str, Any]) -> bool:
    """Ring `user_id`'s iPhone with an incoming-call screen for a ride offer."""
    if not is_enabled():
        return False

    q = await db.execute(select(User.voip_token).where(User.id == user_id))
    device_token = q.scalars().first()
    if not device_token:
        return False

    # Mirrors CallKitParams on the Flutter side. `id` must be a stable UUID per
    # call so accept/decline map back to the right booking.
    body = {
        "id": payload.get("call_uuid") or str(uuid.uuid4()),
        "nameCaller": payload.get("customer_name") or "Ziggo customer",
        "handle": payload.get("pickup_address") or "New ride request",
        "type": 0,
        "extra": {
            k: v
            for k, v in payload.items()
            if isinstance(v, (str, int, float, bool))
        },
    }
    ok = await send_voip(device_token, body)
    print(f"[apns] voip ride call user_id={user_id} ok={ok}")
    return ok

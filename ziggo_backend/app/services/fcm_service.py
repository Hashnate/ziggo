"""Firebase Cloud Messaging — server-side push integration.

The Flutter app opens a WebSocket for realtime events; FCM is the safety net
that delivers when the WS is unavailable (driver phone asleep, OS killed the
app, carrier NAT closed the TCP).

Design:
  • init() runs once at uvicorn startup. Reads the service-account JSON from
    FIREBASE_CREDENTIALS_PATH. If the file is missing or malformed, we log a
    warning and leave the SDK uninitialised — every send call short-circuits
    to a no-op so the rest of the app keeps working.
  • send_to_user(db, user_id, ...) looks up User.notification_token and fires
    a single push. Stale-token errors automatically clear the token from the
    DB so we don't keep retrying dead devices.
  • Anywhere the code already calls `manager.send(user_id, event, payload)`,
    a parallel FCM call is automatically piggybacked via ws_manager.
"""
from __future__ import annotations

import asyncio
import json
import os
from typing import Iterable, Optional

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import AsyncSessionLocal
from ..models import User

# Lazy/conditional imports — firebase_admin is heavy and we want the rest of
# the app to import cleanly even if the package isn't installed yet (e.g.
# during a dev run before `pip install` has been re-run).
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    _firebase_lib_available = True
except ImportError:
    firebase_admin = None  # type: ignore
    credentials = None     # type: ignore
    messaging = None       # type: ignore
    _firebase_lib_available = False


_initialized = False
_init_error: Optional[str] = None


def init() -> None:
    """Initialise the Firebase Admin SDK from the service-account JSON.

    Safe to call multiple times — second call is a no-op. Never raises; if
    init fails we log and leave the SDK uninitialised. is_configured() will
    then return False and every send_* call short-circuits cleanly.
    """
    global _initialized, _init_error

    if _initialized:
        return
    if not _firebase_lib_available:
        _init_error = "firebase-admin not installed (pip install firebase-admin)"
        print(f"[fcm] disabled: {_init_error}")
        return

    path = settings.FIREBASE_CREDENTIALS_PATH
    if not path:
        _init_error = "FIREBASE_CREDENTIALS_PATH not set"
        print(f"[fcm] disabled: {_init_error}")
        return
    if not os.path.isfile(path):
        _init_error = f"credentials file not found at {path}"
        print(f"[fcm] disabled: {_init_error}")
        return

    try:
        cred = credentials.Certificate(path)
        firebase_admin.initialize_app(cred)
        _initialized = True
        print(f"[fcm] initialised from {path}")
    except Exception as e:                       # noqa: BLE001 — never block startup
        _init_error = f"init failed: {e}"
        print(f"[fcm] disabled: {_init_error}")


def is_configured() -> bool:
    """True iff push delivery is wired and ready."""
    return _initialized


async def _send_to_token(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> tuple[bool, Optional[str]]:
    """Send a single push. Returns (ok, error_code_or_none)."""
    if not _initialized:
        return False, "NOT_INITIALIZED"
    try:
        data_payload = {k: str(v) for k, v in (data or {}).items()}
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data_payload,
            token=token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="ziggo_default",
                    sound="default",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", content_available=True),
                ),
            ),
        )
        # firebase-admin is sync; run in a worker thread so we don't block the loop.
        await asyncio.to_thread(messaging.send, message)
        return True, None
    except Exception as e:                       # noqa: BLE001
        code = getattr(e, "code", None) or e.__class__.__name__
        return False, str(code)


_DEAD_TOKEN_CODES = {
    "registration-token-not-registered",
    "invalid-argument",
    "invalid-registration-token",
    "UnregisteredError",
    "InvalidArgumentError",
}


async def send_to_user(
    db: AsyncSession,
    user_id: int,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Look up the user's FCM token and push. Returns True on success."""
    if not _initialized:
        return False
    q = await db.execute(select(User).where(User.id == user_id))
    user = q.scalars().first()
    token = (user.notification_token or "").strip() if user else ""
    if not token:
        return False
    ok, err = await _send_to_token(token, title, body, data)
    if not ok and err and any(d in err for d in _DEAD_TOKEN_CODES):
        # Clear the dead token so we stop retrying.
        await db.execute(
            update(User).where(User.id == user_id).values(notification_token=None)
        )
        await db.commit()
        print(f"[fcm] cleared dead token for user_id={user_id} ({err})")
    return ok


async def send_to_users(
    db: AsyncSession,
    user_ids: Iterable[int],
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> int:
    """Bulk push. Returns delivery count."""
    if not _initialized:
        return 0
    delivered = 0
    for uid in user_ids:
        if await send_to_user(db, uid, title, body, data):
            delivered += 1
    return delivered


# ---------------------------------------------------------------------------
# fire_and_forget_to_user_id — used by ws_manager to piggyback FCM on every
# WS broadcast without forcing existing handlers to pass a DB session.
# Opens its own short-lived AsyncSession so it doesn't share the caller's
# transaction.
# ---------------------------------------------------------------------------

# Map well-known WS event names to a user-facing title.
_EVENT_TITLES = {
    "new_ride_request": "New ride request",
    "booking_update": "Ride update",
    "no_drivers_available": "No drivers found",
    "booking_paid": "Payment received",
    "wallet_topup": "Wallet topped up",
    "gold_activated": "Gold activated",
    "food_order_paid": "Food order paid",
    "market_order_paid": "Market order paid",
    "food_order_update": "Food order update",
    "market_order_update": "Market order update",
    "emergency_alert": "Emergency alert",
    "admin_message": "Message",
    "trip_share_request": "Trip share request",
}


def _summary_body(event: str, payload: dict) -> str:
    if event == "new_ride_request":
        addr = payload.get("pickup_address") or "your current location"
        return f"Pickup at {addr}"
    if event == "booking_update":
        s = payload.get("status")
        ref = payload.get("booking_ref") or payload.get("booking_id")
        return f"Booking {ref} is now {s}"
    if event in ("wallet_topup", "booking_paid"):
        amt = payload.get("amount") or payload.get("new_balance")
        return f"Rs.{amt} processed"
    if event == "admin_message":
        return str(payload.get("body") or payload.get("title") or "Open the app for details")
    snippet = json.dumps(payload, default=str)
    return snippet[:120]


async def fire_and_forget_to_user_id(
    user_id: int,
    event: str,
    payload: dict,
) -> None:
    """Best-effort FCM push triggered from inside ws_manager.send. Swallows
    every error — the only goal is "don't break the WS path"."""
    if not _initialized:
        return
    try:
        async with AsyncSessionLocal() as db:
            await send_to_user(
                db,
                user_id,
                title=_EVENT_TITLES.get(event, "Ziggo"),
                body=_summary_body(event, payload),
                data={"event": event, **payload},
            )
    except Exception as e:                       # noqa: BLE001
        print(f"[fcm] fire_and_forget failed for user_id={user_id} event={event}: {e}")

"""Firebase Cloud Messaging — server-side push notifications.

Activated when FIREBASE_CREDENTIALS_PATH points at a valid service-account
JSON file. When unset or invalid, every public function is a graceful no-op
and the rest of the app keeps working unchanged. The WebSocket channel
remains the primary realtime path; FCM is the fallback for backgrounded /
killed apps where the WS is dead.

Public API:
  init()                          — called once at FastAPI startup
  is_enabled()                    — quick guard for hot paths
  send_to_user(db, user_id, ...)  — look up the token and push
  fire_and_forget(user_id, ...)   — fire from sync contexts (ws_manager hook)
"""
from __future__ import annotations

import asyncio
import os
from typing import Iterable, Optional

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import AsyncSessionLocal
from ..models import User


# Heavy import — keep behind a guard so the rest of the app boots without it.
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    _firebase_lib_available = True
except Exception:
    firebase_admin = None  # type: ignore
    credentials = None  # type: ignore
    messaging = None  # type: ignore
    _firebase_lib_available = False


_initialized: bool = False
_init_error: Optional[str] = None
# Error substrings that mean "this token is dead, stop trying" — used so we
# can null the column and stop retrying on every event.
_DEAD_TOKEN_CODES = ("UNREGISTERED", "registration-token-not-registered", "INVALID_ARGUMENT")


def init() -> None:
    """Initialise the Firebase Admin SDK. Safe to call repeatedly."""
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
    except Exception as e:
        _init_error = f"{type(e).__name__}: {e}"
        print(f"[fcm] disabled: init failed — {_init_error}")


def is_enabled() -> bool:
    return _initialized


async def _send_to_token(
    token: str,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> tuple[bool, Optional[str]]:
    """Returns (ok, error_string). firebase-admin is sync — run in a thread."""
    if not _initialized:
        return False, "not initialised"
    msg = messaging.Message(
        token=token,
        notification=messaging.Notification(title=title, body=body),
        data={k: str(v) for k, v in (data or {}).items()},
    )
    try:
        await asyncio.to_thread(messaging.send, msg)
        return True, None
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"


async def send_to_user(
    db: AsyncSession,
    user_id: int,
    title: str,
    body: str,
    data: Optional[dict] = None,
) -> bool:
    """Look up the user's stored FCM token and push. Returns True on success."""
    if not _initialized:
        return False
    q = await db.execute(select(User).where(User.id == user_id))
    user = q.scalars().first()
    token = (user.notification_token or "").strip() if user else ""
    if not token:
        return False
    ok, err = await _send_to_token(token, title, body, data)
    if not ok and err and any(c in err for c in _DEAD_TOKEN_CODES):
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
    if not _initialized:
        return 0
    delivered = 0
    for uid in user_ids:
        if await send_to_user(db, uid, title, body, data):
            delivered += 1
    return delivered


def fire_and_forget(user_id: int, event: str, payload: dict) -> None:
    """Sync entry-point used by ws_manager.send() to piggyback FCM on every
    WS event. Owns its own DB session so it doesn't borrow the request one."""
    if not _initialized:
        return

    title, body = _format(event, payload)
    if not title:
        return  # event doesn't warrant a notification

    async def _run() -> None:
        async with AsyncSessionLocal() as db:
            await send_to_user(db, user_id, title, body, {"event": event, **{k: v for k, v in payload.items() if isinstance(v, (str, int, float, bool))}})

    try:
        asyncio.create_task(_run())
    except RuntimeError:
        # No running loop — nothing we can do from a fully-sync context.
        pass


# Map WS events → user-visible notification text. Add new entries as new
# realtime events are introduced. Events not in this map skip FCM entirely
# (they still go via WebSocket as normal).
def _format(event: str, payload: dict) -> tuple[str, str]:
    if event == "new_ride_request":
        ref = payload.get("booking_ref", "")
        return ("New ride request", f"Tap to accept — booking {ref}")
    if event == "booking_update":
        status = payload.get("status", "")
        if status == "accepted":
            return ("Driver assigned", "A driver has accepted your ride.")
        if status == "arrived":
            return ("Driver has arrived", "Your driver is at the pickup point.")
        if status == "started":
            return ("Ride started", "Enjoy your trip!")
        if status == "completed":
            return ("Ride completed", "Thanks for riding with Ziggo.")
        if status == "cancelled":
            return ("Ride cancelled", "Your ride has been cancelled.")
    if event == "no_drivers_available":
        return ("No drivers found", "We couldn't find a driver nearby. Please try again.")
    if event == "food_order_update":
        status = payload.get("status", "")
        return ("Order update", f"Your food order is now {status}.")
    if event == "market_order_update":
        status = payload.get("status", "")
        return ("Order update", f"Your market order is now {status}.")
    return ("", "")

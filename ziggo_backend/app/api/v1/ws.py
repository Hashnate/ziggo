"""WebSocket endpoint for live ride/booking updates.

The Flutter app connects to /ws?token=<jwt> after login, then listens for events.
The admin live-tracking page connects to /ws/admin (auth via the ziggo_admin
cookie set during admin login).
"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from itsdangerous import URLSafeSerializer, BadSignature
from jose import jwt, JWTError
from sqlalchemy import select

from ...config import settings
from ...database import AsyncSessionLocal
from ...models import User, UserRole
from ...services.auth_service import ALGORITHM
from ...services.passenger_location_service import ADMIN_TOPIC, CUSTOMER_MAP_ROLES
from ...services.ws_manager import manager

router = APIRouter()

# Same salt as admin_panel/routes.py — keeps the admin session cookie compatible.
_admin_serializer = URLSafeSerializer(settings.SECRET_KEY, salt="ziggo-admin")


@router.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: str = Query(...)):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        phone = payload.get("sub")
        if not phone:
            await websocket.close(code=4401)
            return
    except JWTError:
        await websocket.close(code=4401)
        return

    async with AsyncSessionLocal() as db:
        q = await db.execute(select(User).where(User.phone_number == phone))
        user = q.scalars().first()
        if not user:
            await websocket.close(code=4404)
            return
        user_id = user.id

    await manager.connect(user_id, websocket)
    try:
        while True:
            # Receive pings or client-side messages; we don't act on them.
            await websocket.receive_text()
    except WebSocketDisconnect:
        await manager.disconnect(user_id, websocket)
    except Exception:
        await manager.disconnect(user_id, websocket)


async def _cookie_admin(websocket: WebSocket):
    """The admin behind the `ziggo_admin` cookie that admin_panel sets at login, or
    None after closing the socket."""
    cookie = websocket.cookies.get("ziggo_admin")
    if not cookie:
        await websocket.close(code=4401)
        return None
    try:
        data = _admin_serializer.loads(cookie)
        uid = int(data.get("uid"))
    except (BadSignature, ValueError, TypeError):
        await websocket.close(code=4401)
        return None

    async with AsyncSessionLocal() as db:
        q = await db.execute(
            select(User).where(User.id == uid, User.role == UserRole.ADMIN)
        )
        admin = q.scalars().first()
    if not admin:
        await websocket.close(code=4403)
        return None
    return admin


async def _serve_topic(websocket: WebSocket, topic: str) -> None:
    await websocket.accept()
    await manager.subscribe(topic, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await manager.unsubscribe(topic, websocket)
    except Exception:
        await manager.unsubscribe(topic, websocket)


@router.websocket("/ws/admin")
async def ws_admin(websocket: WebSocket):
    """Admin live-tracking channel.

    Subscribed sockets receive `driver_location_update` events whenever a
    driver POSTs a new GPS fix.
    """
    if await _cookie_admin(websocket) is None:
        return
    await _serve_topic(websocket, "admin_live")


@router.websocket("/ws/admin/customers")
async def ws_admin_customers(websocket: WebSocket):
    """Customer map channel (Phase 2, feature 01): `customer_location_update` and
    `customer_location_stopped` while customers share their location. Super admins
    and admins only."""
    admin = await _cookie_admin(websocket)
    if admin is None:
        return
    if (admin.admin_role or "admin") not in CUSTOMER_MAP_ROLES:
        await websocket.close(code=4403)
        return
    await _serve_topic(websocket, ADMIN_TOPIC)

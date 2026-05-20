"""WebSocket endpoint for live ride/booking updates.

The Flutter app connects to /ws?token=<jwt> after login, then listens for events.
"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError
from sqlalchemy import select

from ...config import settings
from ...database import AsyncSessionLocal
from ...models import User
from ...services.auth_service import ALGORITHM
from ...services.ws_manager import manager

router = APIRouter()


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

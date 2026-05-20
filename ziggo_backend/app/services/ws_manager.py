"""In-memory WebSocket pub/sub for ride/order updates.

Each user has a per-user channel; the API can broadcast a dict to a user when
a ride status changes. The Flutter app opens a WS to /ws/{user_id} and listens.
"""
from collections import defaultdict
from typing import Dict, Set
import asyncio
import json

from fastapi import WebSocket


class WSManager:
    def __init__(self) -> None:
        self._connections: Dict[int, Set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()

    async def connect(self, user_id: int, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            self._connections[user_id].add(ws)

    async def disconnect(self, user_id: int, ws: WebSocket) -> None:
        async with self._lock:
            self._connections[user_id].discard(ws)
            if not self._connections[user_id]:
                self._connections.pop(user_id, None)

    async def send(self, user_id: int, event: str, payload: dict) -> None:
        async with self._lock:
            targets = list(self._connections.get(user_id, ()))
        msg = json.dumps({"event": event, "data": payload}, default=str)
        delivered = 0
        for ws in targets:
            try:
                await ws.send_text(msg)
                delivered += 1
            except Exception:
                pass
        # Visible in uvicorn logs — tells you the user was/wasn't reachable.
        print(f"[ws] → user_id={user_id} event={event} sockets={len(targets)} delivered={delivered}")

    async def broadcast(self, user_ids, event: str, payload: dict) -> None:
        for uid in user_ids:
            await self.send(uid, event, payload)


manager = WSManager()

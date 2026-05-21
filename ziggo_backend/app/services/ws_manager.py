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
        # Named broadcast channels (e.g. "admin_live") that aren't keyed by user.
        self._topics: Dict[str, Set[WebSocket]] = defaultdict(set)
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

    # -- topic channels (used by admin pages like live-tracking) -------------

    async def subscribe(self, topic: str, ws: WebSocket) -> None:
        """Caller is responsible for ws.accept() before subscribing.

        We don't accept here so the endpoint can do auth checks first.
        """
        async with self._lock:
            self._topics[topic].add(ws)

    async def unsubscribe(self, topic: str, ws: WebSocket) -> None:
        async with self._lock:
            self._topics[topic].discard(ws)
            if not self._topics[topic]:
                self._topics.pop(topic, None)

    async def publish(self, topic: str, event: str, payload: dict) -> None:
        async with self._lock:
            targets = list(self._topics.get(topic, ()))
        msg = json.dumps({"event": event, "data": payload}, default=str)
        delivered = 0
        for ws in targets:
            try:
                await ws.send_text(msg)
                delivered += 1
            except Exception:
                pass
        print(f"[ws] topic={topic} event={event} sockets={len(targets)} delivered={delivered}")


manager = WSManager()

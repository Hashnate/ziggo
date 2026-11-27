"""Live tracking page & feed driver count consistency tests."""
import re
import sys
from pathlib import Path
from types import SimpleNamespace

for _candidate in (str(Path(__file__).resolve().parents[2]), "/app"):
    if Path(_candidate, "ziggo_admin_panel").is_dir() and _candidate not in sys.path:
        sys.path.append(_candidate)

import httpx
from fastapi import FastAPI, Request
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, get_db
from app.models import Driver, DriverStatus, User, UserRole
from ziggo_admin_panel import routes as admin_routes


def _build_test_app(session_factory) -> FastAPI:
    app = FastAPI()
    app.include_router(admin_routes.router, prefix="/admin")

    async def _fake_admin(request: Request):
        admin = SimpleNamespace(
            id=1,
            role=UserRole.ADMIN,
            admin_role="superadmin",
            phone_number="0700000000",
            full_name="Test Admin",
            email="admin@ziggo.com",
        )
        request.state.admin = admin
        return admin

    async def _override_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[admin_routes.current_admin] = _fake_admin
    return app


def _extract_span(html: str, element_id: str) -> str:
    m = re.search(rf'id="{re.escape(element_id)}"[^>]*>([^<]*)<', html)
    assert m is not None, f"element #{element_id} not found in HTML"
    return m.group(1).strip()


async def test_live_tracking_counts_only_approved_drivers():
    local_engine = create_async_engine(settings.DATABASE_URL, future=True)
    session_factory = async_sessionmaker(local_engine, class_=AsyncSession, expire_on_commit=False)
    phones = [f"0779900{i:03d}" for i in range(6)]
    try:
        async with local_engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

        async with session_factory() as db:
            await db.execute(delete(User).where(User.phone_number.in_(phones)))
            await db.commit()

            specs = [
                (DriverStatus.APPROVED, True, True),
                (DriverStatus.APPROVED, True, False),
                (DriverStatus.APPROVED, True, False),
                (DriverStatus.PENDING, False, False),
                (DriverStatus.REJECTED, False, False),
                (DriverStatus.SUSPENDED, False, False),
            ]
            for idx, (status, is_approved, is_online) in enumerate(specs):
                user = User(
                    phone_number=phones[idx],
                    role=UserRole.DRIVER,
                    full_name=f"LT Driver {idx}",
                )
                db.add(user)
                await db.flush()
                db.add(Driver(
                    user_id=user.id,
                    nic_number=f"9900000{idx}V",
                    license_number=f"LICLT{idx:03d}",
                    vehicle_type="car",
                    vehicle_number=f"CARLT{idx:03d}",
                    status=status,
                    is_approved=is_approved,
                    is_online=is_online,
                ))
            await db.commit()

        app = _build_test_app(session_factory)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://127.0.0.1") as client:
            page_resp = await client.get("/admin/live-tracking")
            assert page_resp.status_code == 200
            html = page_resp.text
            assert _extract_span(html, "statOnline") == "1"
            assert _extract_span(html, "statOffline") == "2"
            assert _extract_span(html, "statTotal") == "3"
            assert _extract_span(html, "liveOnlineLabel") == "1"
            assert _extract_span(html, "listOnlineCount") == "1"
            assert _extract_span(html, "listOfflineCount") == "2"

            feed_resp = await client.get("/admin/live-tracking/feed")
            assert feed_resp.status_code == 200
            feed = feed_resp.json()
            assert feed["totals"]["online"] == 1
            assert feed["totals"]["offline"] == 2
            assert feed["totals"]["total"] == 3
            assert len(feed["drivers"]) == 3
    finally:
        async with session_factory() as db:
            await db.execute(delete(User).where(User.phone_number.in_(phones)))
            await db.commit()
        await local_engine.dispose()

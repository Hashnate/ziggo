"""App version control & force/soft update tests (admin panel + /misc/app-version)."""
import re
import sys
from pathlib import Path
from types import SimpleNamespace

for _candidate in (str(Path(__file__).resolve().parents[2]), "/app"):
    if Path(_candidate, "ziggo_admin_panel").is_dir() and _candidate not in sys.path:
        sys.path.append(_candidate)

import httpx
import pytest
from fastapi import FastAPI, Request
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import app.models  # noqa: F401
from app.api.v1 import misc as misc_api
from app.config import settings
from app.database import Base, get_db
from app.models import SystemSettings, UserRole
from app.services.app_version_service import (
    api_version_value,
    is_disabled_version,
    normalize_app_version,
    parse_admin_version_input,
    validate_store_url,
)
from ziggo_admin_panel import routes as admin_routes


def _dart_compare_versions(v1: str, v2: str) -> int:
    """Exact Python mirror of Dart AppUpdateService._compareVersions."""
    def _parse(v: str) -> list[int]:
        out = []
        for seg in v.split("."):
            head = seg.split("+")[0]
            try:
                out.append(int(head))
            except ValueError:
                out.append(0)
        return out

    p1, p2 = _parse(v1), _parse(v2)
    for i in range(max(len(p1), len(p2))):
        a = p1[i] if i < len(p1) else 0
        b = p2[i] if i < len(p2) else 0
        if a != b:
            return -1 if a < b else 1
    return 0


def _dart_update_action(current_version: str, platform_payload: dict) -> str:
    """Exact Python mirror of Dart AppUpdateService.checkForUpdates decision tree."""
    raw_min = platform_payload.get("min_version")
    min_ver = raw_min.strip() if isinstance(raw_min, str) else "1.0.0"
    raw_latest = platform_payload.get("latest_version")
    latest_ver = raw_latest.strip() if isinstance(raw_latest, str) else current_version

    if _dart_compare_versions(current_version, min_ver) < 0:
        return "force"
    if _dart_compare_versions(current_version, latest_ver) < 0:
        return "soft"
    return "none"


def test_version_helper_normalization_and_validation():
    assert normalize_app_version(" 1.1.5 ") == "1.1.5"
    assert normalize_app_version("v1.1.5+39") == "1.1.5"
    assert normalize_app_version("V2.0.1") == "2.0.1"
    assert normalize_app_version("") == ""
    assert normalize_app_version(None) == ""

    assert is_disabled_version("")
    assert is_disabled_version(None)
    assert is_disabled_version("0")
    assert is_disabled_version("0.0")
    assert is_disabled_version("0.0.0")
    assert is_disabled_version("v0")
    assert not is_disabled_version("1.0.0")
    assert not is_disabled_version("0.0.1")

    assert parse_admin_version_input("", "Android Min") == ""
    assert parse_admin_version_input("   ", "Android Min") == ""
    assert parse_admin_version_input("0", "Android Min") == "0"
    assert parse_admin_version_input("0.0.0", "Android Min") == "0.0.0"
    assert parse_admin_version_input("v1.1.5+39", "Android Min") == "1.1.5"

    with pytest.raises(ValueError):
        parse_admin_version_input("abc", "Android Min")
    with pytest.raises(ValueError):
        parse_admin_version_input("1.2.3-beta", "Android Min")
    with pytest.raises(ValueError):
        parse_admin_version_input("1." * 11 + "1", "Android Min")

    assert api_version_value(None) == "0"
    assert api_version_value("") == "0"
    assert api_version_value("0") == "0"
    assert api_version_value("0.0.0") == "0"
    assert api_version_value("v1.1.5+39") == "1.1.5"
    assert api_version_value("bad") == "0"

    assert validate_store_url("", "https://example.com", "Play") == "https://example.com"
    assert validate_store_url("https://play.google.com/store", "https://example.com", "Play") == "https://play.google.com/store"
    with pytest.raises(ValueError):
        validate_store_url("javascript:alert(1)", "https://example.com", "Play")


def _build_test_app(session_factory) -> FastAPI:
    app = FastAPI()
    app.include_router(misc_api.router, prefix="/api/v1")
    app.include_router(admin_routes.router, prefix="/admin")

    async def _fake_superadmin(request: Request):
        admin = SimpleNamespace(
            id=1,
            role=UserRole.ADMIN,
            admin_role="superadmin",
            phone_number="0700000000",
            full_name="Test Admin",
        )
        request.state.admin = admin
        return admin

    async def _override_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[admin_routes.require_superadmin] = _fake_superadmin
    return app


def _multipart_fields(**overrides) -> list[tuple[str, tuple[None, str]]]:
    base = {
        "active_tab": "appversion",
        "site_name": "Ziggo",
        "admin_email": "admin@ziggo.com",
        "contact_phone": "",
        "contact_email": "",
        "address": "",
        "app_min_version_android": "",
        "app_latest_version_android": "",
        "app_min_version_ios": "",
        "app_latest_version_ios": "",
        "app_update_title": "Update Available",
        "app_update_message": "A new version is out.",
        "app_force_update_message": "Please update now.",
        "app_play_store_url": "https://play.google.com/store/apps/details?id=lk.ziggo.app",
        "app_app_store_url": "https://apps.apple.com/app/ziggo-app/id6778739956",
    }
    base.update(overrides)
    return [(k, (None, v)) for k, v in base.items()]


def _extract_input_value(html: str, name: str) -> str:
    m = re.search(rf'<input[^>]*name="{re.escape(name)}"[^>]*value="([^"]*)"', html)
    assert m is not None, f"input {name} not found in HTML"
    return m.group(1)


async def test_admin_settings_and_app_version_lifecycle():
    local_engine = create_async_engine(settings.DATABASE_URL, future=True)
    session_factory = async_sessionmaker(local_engine, class_=AsyncSession, expire_on_commit=False)
    try:
        async with local_engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

        app = _build_test_app(session_factory)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://127.0.0.1") as client:
            # Start with no SystemSettings row: API returns '0' so nothing prompts
            r0 = await client.get("/api/v1/misc/app-version")
            assert r0.status_code == 200
            assert "no-store" in r0.headers.get("cache-control", "")
            assert r0.json()["android"]["min_version"] == "0"
            assert r0.json()["android"]["latest_version"] == "0"
            assert _dart_update_action("1.0.0", r0.json()["android"]) == "none"

            # 1) Save empty strings via multipart/form-data (must NOT snap back to 1.0.0 / 1.0.15)
            save_empty = await client.post(
                "/admin/settings",
                files=_multipart_fields(
                    app_min_version_android="",
                    app_latest_version_android="",
                    app_min_version_ios="",
                    app_latest_version_ios="",
                ),
                follow_redirects=False,
            )
            assert save_empty.status_code == 303
            assert "saved=1" in save_empty.headers["location"]

            html_empty = (await client.get("/admin/settings")).text
            assert _extract_input_value(html_empty, "app_min_version_android") == ""
            assert _extract_input_value(html_empty, "app_latest_version_android") == ""
            assert _extract_input_value(html_empty, "app_min_version_ios") == ""
            assert _extract_input_value(html_empty, "app_latest_version_ios") == ""

            api_empty = (await client.get("/api/v1/misc/app-version")).json()
            for plat in ("android", "ios"):
                assert api_empty[plat]["min_version"] == "0"
                assert api_empty[plat]["latest_version"] == "0"
                for app_ver in ("0.9.0", "1.0.0", "1.0.15", "1.1.4", "1.1.5"):
                    assert _dart_update_action(app_ver, api_empty[plat]) == "none"

            # 2) Save '0' and '0.0.0': must remain disabled for all app versions
            save_zero = await client.post(
                "/admin/settings",
                files=_multipart_fields(
                    app_min_version_android="0",
                    app_latest_version_android="0.0.0",
                    app_min_version_ios="0",
                    app_latest_version_ios="0",
                ),
                follow_redirects=False,
            )
            assert save_zero.status_code == 303
            html_zero = (await client.get("/admin/settings")).text
            assert _extract_input_value(html_zero, "app_min_version_android") == "0"
            assert _extract_input_value(html_zero, "app_latest_version_android") == "0.0.0"

            api_zero = (await client.get("/api/v1/misc/app-version")).json()
            assert api_zero["android"]["min_version"] == "0"
            assert api_zero["android"]["latest_version"] == "0"
            assert _dart_update_action("1.0.0", api_zero["android"]) == "none"
            assert _dart_update_action("1.1.5", api_zero["ios"]) == "none"

            # 3) Force update only (min='v1.1.5+39' normalized to '1.1.5', latest='')
            save_force = await client.post(
                "/admin/settings",
                files=_multipart_fields(
                    app_min_version_android="v1.1.5+39",
                    app_latest_version_android="",
                    app_min_version_ios="1.1.5",
                    app_latest_version_ios="0",
                ),
                follow_redirects=False,
            )
            assert save_force.status_code == 303
            api_force = (await client.get("/api/v1/misc/app-version")).json()
            assert api_force["android"]["min_version"] == "1.1.5"
            assert api_force["android"]["latest_version"] == "0"
            assert _dart_update_action("1.1.4", api_force["android"]) == "force"
            assert _dart_update_action("1.1.5", api_force["android"]) == "none"
            assert _dart_update_action("1.1.6", api_force["android"]) == "none"

            # 4) Soft update only (min='', latest='1.1.6')
            save_soft = await client.post(
                "/admin/settings",
                files=_multipart_fields(
                    app_min_version_android="",
                    app_latest_version_android="1.1.6",
                    app_min_version_ios="0",
                    app_latest_version_ios="1.1.6",
                ),
                follow_redirects=False,
            )
            assert save_soft.status_code == 303
            api_soft = (await client.get("/api/v1/misc/app-version")).json()
            assert api_soft["android"]["min_version"] == "0"
            assert api_soft["android"]["latest_version"] == "1.1.6"
            assert _dart_update_action("0.9.0", api_soft["android"]) == "soft"
            assert _dart_update_action("1.1.5", api_soft["android"]) == "soft"
            assert _dart_update_action("1.1.6", api_soft["android"]) == "none"

            # 5) Both Force & Soft active (min='1.1.4', latest='1.1.6')
            save_both = await client.post(
                "/admin/settings",
                files=_multipart_fields(
                    app_min_version_android="1.1.4",
                    app_latest_version_android="1.1.6",
                    app_min_version_ios="1.1.4",
                    app_latest_version_ios="1.1.6",
                ),
                follow_redirects=False,
            )
            assert save_both.status_code == 303
            api_both = (await client.get("/api/v1/app-version")).json()
            assert _dart_update_action("1.1.3", api_both["android"]) == "force"
            assert _dart_update_action("1.1.4", api_both["android"]) == "soft"
            assert _dart_update_action("1.1.5", api_both["android"]) == "soft"
            assert _dart_update_action("1.1.6", api_both["android"]) == "none"

            # 6) Invalid version or bad URL must redirect with error and NOT clobber DB
            bad_ver = await client.post(
                "/admin/settings",
                files=_multipart_fields(app_min_version_android="not-a-version"),
                follow_redirects=False,
            )
            assert bad_ver.status_code == 303
            assert "error=" in bad_ver.headers["location"]

            bad_url = await client.post(
                "/admin/settings",
                files=_multipart_fields(
                    app_min_version_android="1.1.4",
                    app_play_store_url="javascript:alert(1)",
                ),
                follow_redirects=False,
            )
            assert bad_url.status_code == 303
            assert "error=" in bad_url.headers["location"]

            async with session_factory() as db:
                s = (await db.execute(select(SystemSettings).where(SystemSettings.id == 1))).scalars().first()
                assert s is not None
                assert s.app_min_version_android == "1.1.4"
                assert s.app_latest_version_android == "1.1.6"
                assert s.app_play_store_url == "https://play.google.com/store/apps/details?id=lk.ziggo.app"

            # 7) Partial POST omitting version fields preserves existing DB values
            partial = await client.post(
                "/admin/settings",
                files=[("active_tab", (None, "general")), ("site_name", (None, "Ziggo"))],
                follow_redirects=False,
            )
            assert partial.status_code == 303
            assert "saved=1" in partial.headers["location"]
            api_after_partial = (await client.get("/api/v1/misc/app-version")).json()
            assert api_after_partial["android"]["min_version"] == "1.1.4"
            assert api_after_partial["android"]["latest_version"] == "1.1.6"
    finally:
        async with session_factory() as db:
            await db.execute(delete(SystemSettings).where(SystemSettings.id == 1))
            await db.commit()
        await local_engine.dispose()

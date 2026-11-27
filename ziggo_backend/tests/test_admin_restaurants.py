"""Regression tests for admin restaurant list/edit modal values."""
import sys
from decimal import Decimal

import pytest
from sqlalchemy import delete, select
from starlette.requests import Request

import app.models  # noqa: F401
from app.database import AsyncSessionLocal, Base, engine
from app.models import Restaurant, User, UserRole

TEST_ADMIN_PHONE = "0779990400"
TEST_OWNER_PHONE = "0779990401"


def _make_request(path: str = "/admin/restaurants") -> Request:
    scope = {
        "type": "http",
        "method": "GET",
        "path": path,
        "headers": [],
        "query_string": b"",
        "state": {},
    }
    req = Request(scope)
    req.state.admin = None
    return req


async def _clean(db):
    owners = select(User.id).where(User.phone_number.in_([TEST_ADMIN_PHONE, TEST_OWNER_PHONE]))
    await db.execute(delete(Restaurant).where(Restaurant.owner_id.in_(owners)))
    await db.execute(delete(User).where(User.phone_number.in_([TEST_ADMIN_PHONE, TEST_OWNER_PHONE])))
    await db.commit()


async def test_admin_restaurants_preserves_rates_and_zeroes():
    if "/app" not in sys.path:
        sys.path.append("/app")
    from ziggo_admin_panel.routes import admin_restaurant_edit, admin_restaurant_new_submit, admin_restaurants

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                admin = User(phone_number=TEST_ADMIN_PHONE, role=UserRole.ADMIN, full_name="Test Admin")
                owner = User(phone_number=TEST_OWNER_PHONE, role=UserRole.RESTAURANT_OWNER, full_name="Owner")
                db.add_all([admin, owner])
                await db.flush()

                rest = Restaurant(
                    name="Kattankudy Kitchen",
                    owner_id=owner.id,
                    delivery_fee=Decimal("10.00"),
                    pickup_fee=Decimal("70.00"),
                    per_km_rate=Decimal("40.00"),
                    boost=Decimal("0.00"),
                    commission_percentage=Decimal("20.00"),
                    max_settle_amount=Decimal("1000.00"),
                )
                db.add(rest)
                await db.commit()
                await db.refresh(rest)

                # Update rates via edit handler
                resp = await admin_restaurant_edit(
                    restaurant_id=rest.id,
                    owner_phone=TEST_OWNER_PHONE,
                    owner_full_name="Owner",
                    name="Kattankudy Kitchen",
                    description="",
                    cuisine="Sri Lankan",
                    address="Main St",
                    lat=7.7172,
                    lng=81.7000,
                    phone_number=TEST_OWNER_PHONE,
                    image=None,
                    opening_time="09:00",
                    closing_time="22:00",
                    delivery_fee=0.0,
                    eta_minutes=25,
                    pickup_fee=10.0,
                    per_km_rate=50.0,
                    boost=5.5,
                    commission_percentage=10.3,
                    max_settle_amount=2500.0,
                    db=db,
                    _=admin,
                )
                assert resp.status_code == 303

                # Listing page must pass saved values (not defaults) into openEditRestaurant(...)
                page_resp = await admin_restaurants(
                    request=_make_request(),
                    page=1,
                    search="Kattankudy Kitchen",
                    status="all",
                    db=db,
                    _=admin,
                )
                html = page_resp.body.decode("utf-8")
                expected_tail = '0.0, 25, "0779990401", "Owner", 7.7172, 81.7, "", 10.0, 50.0, 5.5, 10.3, 2500.0)'
                assert expected_tail in html

                # Explicit 0 values must not fall back to 70 / 40 / 20 / 1000
                await admin_restaurant_edit(
                    restaurant_id=rest.id,
                    owner_phone=TEST_OWNER_PHONE,
                    owner_full_name="Owner",
                    name="Kattankudy Kitchen",
                    description="",
                    cuisine="Sri Lankan",
                    address="Main St",
                    lat=7.7172,
                    lng=81.7000,
                    phone_number=TEST_OWNER_PHONE,
                    image=None,
                    opening_time="09:00",
                    closing_time="22:00",
                    delivery_fee=0.0,
                    eta_minutes=25,
                    pickup_fee=0.0,
                    per_km_rate=0.0,
                    boost=0.0,
                    commission_percentage=0.0,
                    max_settle_amount=0.0,
                    db=db,
                    _=admin,
                )
                page_resp_zero = await admin_restaurants(
                    request=_make_request(),
                    page=1,
                    search="Kattankudy Kitchen",
                    status="all",
                    db=db,
                    _=admin,
                )
                html_zero = page_resp_zero.body.decode("utf-8")
                assert '0.0, 25, "0779990401", "Owner", 7.7172, 81.7, "", 0.0, 0.0, 0.0, 0.0, 0.0)' in html_zero

                # Validation error echo on /restaurants/new preserves max_settle_amount and zeroes
                new_err_resp = await admin_restaurant_new_submit(
                    request=_make_request("/admin/restaurants/new"),
                    owner_phone="bad",
                    owner_full_name="Owner",
                    name="Shop 2",
                    description="",
                    cuisine="Sri Lankan",
                    address="Main St",
                    lat=7.7172,
                    lng=81.7000,
                    phone_number="",
                    image=None,
                    opening_time="09:00",
                    closing_time="22:00",
                    delivery_fee=0.0,
                    eta_minutes=30,
                    pickup_fee=0.0,
                    per_km_rate=0.0,
                    boost=0.0,
                    commission_percentage=0.0,
                    max_settle_amount=1500.0,
                    db=db,
                    _=admin,
                )
                err_html = new_err_resp.body.decode("utf-8")
                assert 'name="max_settle_amount"' in err_html
                assert 'value="1500.0"' in err_html
                assert 'name="pickup_fee" type="number" step="0.01" min="0" max="100" required value="0.0"' in err_html
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()

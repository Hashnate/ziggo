"""Test registration uniqueness checks on /auth/check-phone and /auth/send-otp."""
import pytest
from fastapi import HTTPException
from sqlalchemy import delete, select

import app.models  # noqa: F401
from app.api.v1.auth import check_phone, send_otp
from app.database import AsyncSessionLocal, Base, engine
from app.models import Customer, User, UserRole
from app.schemas import OTPRequest

TEST_PHONE = "0770099881"
NEW_PHONE = "0770099882"


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_([TEST_PHONE, NEW_PHONE]))
    await db.execute(delete(Customer).where(Customer.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_([TEST_PHONE, NEW_PHONE])))
    await db.commit()


async def test_auth_registration_flow():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                # 1. Setup existing user
                u = User(phone_number=TEST_PHONE, role=UserRole.CUSTOMER, full_name="Existing Customer", is_active=True)
                db.add(u)
                await db.commit()

                # 2. Test check_phone
                resp_existing = await check_phone(TEST_PHONE, db)
                assert resp_existing["registered"] is True
                assert resp_existing["role"] == "customer"

                resp_new = await check_phone(NEW_PHONE, db)
                assert resp_new["registered"] is False

                # 3. Test send_otp with purpose="register" rejects existing user
                req_dup = OTPRequest(phone_number=TEST_PHONE, purpose="register")
                with pytest.raises(HTTPException) as exc_info:
                    await send_otp(req_dup, db)
                assert exc_info.value.status_code == 409
                assert "already registered" in exc_info.value.detail.lower()

                # 4. Test send_otp with purpose="register" allows new user
                req_new = OTPRequest(phone_number=NEW_PHONE, purpose="register")
                resp_new_otp = await send_otp(req_new, db)
                assert resp_new_otp.message == "OTP sent successfully"

                # 5. Test send_otp with login/none allows existing user
                req_login = OTPRequest(phone_number=TEST_PHONE, purpose="login")
                resp_login = await send_otp(req_login, db)
                assert resp_login.message == "OTP sent successfully"
            finally:
                await _clean(db)
    finally:
        await engine.dispose()

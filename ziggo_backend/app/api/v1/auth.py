from datetime import timedelta

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...config import settings
from ...database import get_db
from ...models import User, UserRole, Customer, Driver
from ...schemas import OTPRequest, OTPVerify, OTPResponse, Token, UserResponse
from ...services.auth_service import (
    create_access_token,
    create_and_send_otp,
    verify_otp_code,
    get_current_user,
)

router = APIRouter()


@router.post("/send-otp", response_model=OTPResponse)
async def send_otp(request: OTPRequest, db: AsyncSession = Depends(get_db)):
    code = await create_and_send_otp(db, request.phone_number)
    return OTPResponse(
        message="OTP sent successfully",
        dev_otp=code if settings.DEV_MODE else None,
    )


@router.post("/verify-otp", response_model=Token)
async def verify_otp(request: OTPVerify, db: AsyncSession = Depends(get_db)):
    ok = await verify_otp_code(db, request.phone_number, request.otp)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired OTP",
        )

    result = await db.execute(select(User).where(User.phone_number == request.phone_number))
    user = result.scalars().first()

    if not user:
        user = User(
            phone_number=request.phone_number,
            role=request.role,
            full_name=request.full_name.strip() if request.full_name else None,
            is_active=True,
        )
        db.add(user)
        await db.flush()

        if request.role == UserRole.CUSTOMER:
            db.add(Customer(user_id=user.id))
        elif request.role == UserRole.DRIVER:
            db.add(Driver(user_id=user.id))

        await db.commit()
        await db.refresh(user)
    else:
        # Existing user — block role mismatches loudly so a customer who
        # tries to "register as driver" with the same phone doesn't end up
        # silently logged in as their original role.
        #
        # Exception: the welcome-screen "Run a restaurant" card sends
        # restaurant_owner even when the user is actually market_owner (one
        # card covers both merchant kinds). Treat merchant<->merchant as a
        # match and just use the stored role.
        merchant_roles = {UserRole.RESTAURANT_OWNER, UserRole.MARKET_OWNER}
        roles_match = user.role == request.role or (
            user.role in merchant_roles and request.role in merchant_roles
        )
        if not roles_match:
            raise HTTPException(
                status_code=409,
                detail=f"Phone already registered as {user.role.value}",
            )

    expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    token = create_access_token(
        data={"sub": user.phone_number, "role": user.role.value},
        expires_delta=expires,
    )
    return Token(access_token=token, user_id=user.id, role=user.role)


@router.put("/fcm-token")
async def update_fcm_token(
    payload: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Persist the device's FCM registration token.

    The Flutter app calls this after `firebase_messaging.getToken()` succeeds
    AND any time the token rotates. Stored on `User.notification_token` and
    used by fcm_service.send_to_user.

    Body: {"token": "<fcm-registration-token>"} — empty/None clears it.
    """
    token = (payload.get("token") or "").strip() or None
    user.notification_token = token
    await db.commit()
    return {"ok": True, "saved": bool(token)}


@router.get("/me", response_model=UserResponse)
async def get_me(user: User = Depends(get_current_user)):
    return user

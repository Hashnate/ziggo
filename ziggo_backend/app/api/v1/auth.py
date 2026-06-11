from datetime import timedelta

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

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

    result = await db.execute(
        select(User)
        .where(User.phone_number == request.phone_number)
        .options(
            selectinload(User.customer_profile),
            selectinload(User.driver_profile),
        )
    )
    user = result.scalars().first()
    is_new = user is None

    if user and not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has been deactivated. Please contact support.",
        )

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
        # Existing user — handle role switching.
        #
        # Customer <-> Driver: allow the same phone to operate as both.
        # When a customer logs in as driver (or vice versa), auto-create
        # the missing profile and switch the active role.
        #
        # Merchant roles: the welcome-screen "Run a restaurant" card sends
        # restaurant_owner even when the user is actually market_owner (one
        # card covers both merchant kinds). Treat merchant<->merchant as a
        # match and just use the stored role.
        merchant_roles = {UserRole.RESTAURANT_OWNER, UserRole.MARKET_OWNER}
        switchable_roles = {UserRole.CUSTOMER, UserRole.DRIVER}

        roles_match = user.role == request.role or (
            user.role in merchant_roles and request.role in merchant_roles
        )

        if not roles_match:
            # Allow customer <-> driver switching
            if user.role in switchable_roles and request.role in switchable_roles:
                # Auto-create the missing profile for the requested role
                if request.role == UserRole.DRIVER and not user.driver_profile:
                    db.add(Driver(user_id=user.id))
                elif request.role == UserRole.CUSTOMER and not user.customer_profile:
                    db.add(Customer(user_id=user.id))

                # Switch the user's active role
                user.role = request.role
                await db.commit()
                await db.refresh(user)
            else:
                raise HTTPException(
                    status_code=409,
                    detail=f"Phone already registered as {user.role.value}",
                )

    expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    token = create_access_token(
        data={"sub": user.phone_number, "role": user.role.value},
        expires_delta=expires,
    )
    return Token(access_token=token, user_id=user.id, role=user.role, is_new=is_new)


@router.put("/fcm-token")
async def update_fcm_token(
    payload: dict = Body(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Save the device's FCM token on the user row.

    The Flutter app calls this after `FirebaseMessaging.getToken()` succeeds
    AND any time the token rotates. An empty/null token clears it (useful on
    logout so the device stops receiving pushes for a different user).
    Body: {"token": "<fcm-registration-token>" | null}
    """
    token = (payload.get("token") or "").strip() or None
    user.notification_token = token
    await db.commit()
    return {"ok": True, "saved": bool(token)}


@router.get("/me", response_model=UserResponse)
async def get_me(user: User = Depends(get_current_user)):
    # BRD: CD-34 — attach profile completeness so the mobile widget can render.
    from ...services.auth_service import compute_profile_completeness
    return UserResponse(
        id=user.id,
        phone_number=user.phone_number,
        full_name=user.full_name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        profile_photo=user.profile_photo,
        rating=float(user.rating) if user.rating is not None else None,
        total_rides=user.total_rides,
        profile_completeness=compute_profile_completeness(user),
    )

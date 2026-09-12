from datetime import timedelta

from fastapi import APIRouter, Body, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from ...config import settings
from ...database import get_db
from ...models import User, UserRole, Customer, Driver
from ...schemas import OTPRequest, OTPVerify, OTPResponse, Token, UserResponse, SwitchRoleRequest
from ...services.auth_service import (
    create_access_token,
    create_and_send_otp,
    verify_otp_code,
    get_current_user,
)

router = APIRouter()


@router.post("/send-otp", response_model=OTPResponse)
async def send_otp(request: OTPRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(User).where(User.phone_number == request.phone_number)
    )
    user = result.scalars().first()
    if user and getattr(user, "is_preregistered", False):
        user.is_preregistered = False
        await db.commit()
        await db.refresh(user)

        expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        token = create_access_token(
            data={"sub": user.phone_number, "role": user.role.value},
            expires_delta=expires,
        )
        return OTPResponse(
            message="OTP bypassed for pre-registered user",
            otp_bypass=True,
            access_token=token,
            user_id=user.id,
            role=user.role,
        )

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
        switchable_roles = {
            UserRole.CUSTOMER,
            UserRole.DRIVER,
            UserRole.RESTAURANT_OWNER,
            UserRole.MARKET_OWNER,
        }

        roles_match = user.role == request.role

        if not roles_match:
            # Allow switching among switchable roles (customer, driver, restaurant_owner, market_owner)
            if user.role in switchable_roles and request.role in switchable_roles:
                # Auto-create the missing profile for the requested role
                if request.role == UserRole.DRIVER and not user.driver_profile:
                    db.add(Driver(user_id=user.id))
                elif request.role == UserRole.CUSTOMER and not user.customer_profile:
                    db.add(Customer(user_id=user.id))

                # If switching to customer (passenger), ensure the driver profile goes offline
                if request.role == UserRole.CUSTOMER and user.driver_profile:
                    user.driver_profile.is_online = False

                # Switch the user's active role
                user.role = request.role
                await db.commit()
                await db.refresh(user)
            else:
                if user.role == UserRole.RESTAURANT_OWNER:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="This phone number is registered to a Restaurant. Please log in using the 'Run a Restaurant' portal.",
                    )
                if user.role == UserRole.MARKET_OWNER:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="This phone number is registered to a Market. Please log in using the 'Manage Market Place' portal.",
                    )
                if request.role in {UserRole.RESTAURANT_OWNER, UserRole.MARKET_OWNER}:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail=f"This account is registered as a {user.role.value}. Please register your merchant account or contact support.",
                    )
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"Phone already registered as {user.role.value}",
                )

    expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    token = create_access_token(
        data={"sub": user.phone_number, "role": user.role.value},
        expires_delta=expires,
    )
    return Token(access_token=token, user_id=user.id, role=user.role, is_new=is_new)


@router.post("/switch-role", response_model=Token)
async def switch_role(
    request: SwitchRoleRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Switch the active role between switchable roles (customer, driver, etc.).
    
    Auto-provisions the required profile (Customer or Driver) if it doesn't exist,
    takes the driver offline when switching to customer mode, and returns a new
    JWT token scoped to the target role.
    """
    switchable_roles = {
        UserRole.CUSTOMER,
        UserRole.DRIVER,
        UserRole.RESTAURANT_OWNER,
        UserRole.MARKET_OWNER,
    }
    if request.role not in switchable_roles:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Role '{request.role.value}' is not switchable.",
        )

    # 1. Profile auto-creation & state transition
    if request.role == UserRole.CUSTOMER:
        cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
        customer_prof = cq.scalars().first()
        if not customer_prof:
            customer_prof = Customer(user_id=user.id)
            db.add(customer_prof)

        # If switching to customer, take driver profile offline
        dq = await db.execute(select(Driver).where(Driver.user_id == user.id))
        driver_prof = dq.scalars().first()
        if driver_prof:
            driver_prof.is_online = False

    elif request.role == UserRole.DRIVER:
        dq = await db.execute(select(Driver).where(Driver.user_id == user.id))
        driver_prof = dq.scalars().first()
        if not driver_prof:
            driver_prof = Driver(user_id=user.id)
            db.add(driver_prof)

    # 2. Update user's active role
    user.role = request.role
    await db.commit()
    await db.refresh(user)

    expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    token = create_access_token(
        data={"sub": user.phone_number, "role": user.role.value},
        expires_delta=expires,
    )
    return Token(access_token=token, user_id=user.id, role=user.role, is_new=False)


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
async def get_me(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user)
):
    if not user.referral_code:
        from ...models.user import generate_referral_code
        user.referral_code = generate_referral_code()
        db.add(user)
        await db.commit()
        await db.refresh(user)

    # Check driver profile existence
    dq = await db.execute(select(Driver).where(Driver.user_id == user.id))
    has_driver = dq.scalars().first() is not None

    # Check customer profile existence
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    has_customer = cq.scalars().first() is not None

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
        referral_code=user.referral_code,
        referred_by_user_id=user.referred_by_user_id,
        profile_completeness=compute_profile_completeness(user),
        has_driver_profile=has_driver,
        has_customer_profile=has_customer,
    )

"""OTP, JWT, and current-user helpers."""
from datetime import datetime, timedelta, timezone
from typing import Optional
import random

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from ..config import settings
from ..database import get_db
from ..models import OTPCode, User

ALGORITHM = "HS256"
OTP_TTL_MINUTES = 5

oauth2_scheme = OAuth2PasswordBearer(tokenUrl=f"{settings.API_V1_STR}/auth/verify-otp", auto_error=False)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=ALGORITHM)


def generate_otp() -> str:
    """Always a random 6-digit code. In DEV_MODE the code is also returned to
    the client so the OTP screen can auto-fill it (no SMS provider needed)."""
    return f"{random.randint(0, 999999):06d}"


async def create_and_send_otp(db: AsyncSession, phone_number: str) -> str:
    """Generate an OTP, store it with TTL, and 'send' it (logs in dev)."""
    code = generate_otp()
    expires = datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES)

    # Invalidate any previous unused OTPs for this phone
    await db.execute(
        update(OTPCode)
        .where(OTPCode.phone_number == phone_number, OTPCode.is_used == False)  # noqa: E712
        .values(is_used=True)
    )

    db.add(OTPCode(phone_number=phone_number, code=code, expires_at=expires))
    await db.commit()

    print(f"[OTP] {phone_number} -> {code} (expires in {OTP_TTL_MINUTES} min)")

    # Fire-and-forget real-SMS via Notify.lk. No-op when env vars are empty.
    # We query system settings here in the request scope, then fire the SMS call
    # in the background so slow gateway APIs do not cause client-side connection timeouts.
    from ..models import SystemSettings
    from . import notify_lk_service
    import asyncio
    try:
        ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
        ss = ss_q.scalars().first()
        sms_enabled = ss.sms_notifications_enabled if ss else True
        site_name = ss.site_name if (ss and ss.site_name) else "Ziggo"

        if sms_enabled and notify_lk_service._enabled():
            asyncio.create_task(notify_lk_service.send_otp(phone_number, code, site_name))
        elif not sms_enabled:
            print(f"[notify.lk] skip sending SMS: SMS notifications disabled in system settings")
    except Exception as e:
        print(f"[OTP] notify.lk background dispatch skipped: {type(e).__name__}: {e}")

    return code


async def verify_otp_code(db: AsyncSession, phone_number: str, code: str) -> bool:
    # App Store Reviewer test account bypass
    if phone_number in ["0752572722", "0772000001"] and code == "123456":
        return True
        
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(OTPCode).where(
            OTPCode.phone_number == phone_number,
            OTPCode.code == code,
            OTPCode.is_used == False,  # noqa: E712
            OTPCode.expires_at > now,
        ).order_by(OTPCode.id.desc())
    )
    otp = result.scalars().first()
    if not otp:
        return False
    otp.is_used = True
    await db.commit()
    return True


from fastapi import Depends, HTTPException, status, Request

async def get_current_user(
    request: Request,
    token: Optional[str] = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    # First check for API Bearer token
    if token:
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
            phone: Optional[str] = payload.get("sub")
            if not phone:
                raise JWTError("missing sub")
            result = await db.execute(select(User).where(User.phone_number == phone))
            user = result.scalars().first()
        except JWTError:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
            
    # Then fallback to admin UI cookie session
    elif request.cookies.get("ziggo_admin"):
        from itsdangerous import URLSafeSerializer, BadSignature
        _serializer = URLSafeSerializer(settings.SECRET_KEY, salt="ziggo-admin")
        cookie_token = request.cookies.get("ziggo_admin")
        try:
            data = _serializer.loads(cookie_token)
            uid = int(data.get("uid"))
            result = await db.execute(select(User).where(User.id == uid))
            user = result.scalars().first()
        except (BadSignature, ValueError, TypeError):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
            
    else:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def require_role(*roles: str):
    """Dependency factory to gate routes by role."""

    async def _checker(user: User = Depends(get_current_user)) -> User:
        if user.role.value not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return user

    return _checker


# BRD: CD-34 — what counts toward "your profile is N% complete"
# Each entry is (field_key, accessor on User). The list is the source of
# truth — change weights by adding/removing entries.
_PROFILE_FIELDS = [
    ("full_name", lambda u: bool((u.full_name or "").strip())),
    ("email", lambda u: bool((u.email or "").strip())),
    ("profile_photo", lambda u: bool((u.profile_photo or "").strip())),
]


def compute_profile_completeness(user) -> dict:
    """Return a dict matching ProfileCompleteness schema for any User."""
    completed = []
    missing = []
    for key, has in _PROFILE_FIELDS:
        if has(user):
            completed.append(key)
        else:
            missing.append(key)
    total = len(_PROFILE_FIELDS)
    percent = round(100 * len(completed) / total) if total else 0
    return {"percent": percent, "completed": completed, "missing": missing}

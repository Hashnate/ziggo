from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...database import get_db
from ...models import Driver, DriverStatus, User
from ...schemas import (
    DriverLocationUpdate,
    DriverOnlineToggle,
    DriverProfileResponse,
    DriverRegisterRequest,
)
from ...services.auth_service import get_current_user, require_role
from ...services.fare_service import haversine_km

router = APIRouter()


VALID_VEHICLE_TYPES = {"bike", "tuk", "car", "van", "truck"}


async def _get_driver(db: AsyncSession, user: User) -> Driver:
    q = await db.execute(select(Driver).where(Driver.user_id == user.id))
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver profile not found")
    return d


def _is_complete(d: Driver) -> bool:
    return all(
        [
            d.vehicle_type,
            d.vehicle_number,
            d.license_number,
            d.nic_number,
        ]
    )


def _to_response(user: User, d: Driver) -> DriverProfileResponse:
    return DriverProfileResponse(
        id=d.id,
        full_name=user.full_name,
        phone_number=user.phone_number,
        profile_photo=user.profile_photo,
        vehicle_type=d.vehicle_type,
        vehicle_number=d.vehicle_number,
        vehicle_model=d.vehicle_model,
        vehicle_color=d.vehicle_color,
        nic_number=d.nic_number,
        license_number=d.license_number,
        is_online=d.is_online,
        is_approved=d.is_approved,
        profile_complete=_is_complete(d),
        status=d.status.value if d.status else None,
        rating=float(user.rating) if user.rating else None,
        today_earnings=float(d.today_earnings or 0),
        today_rides=d.today_rides or 0,
        total_earnings=float(d.total_earnings or 0),
        acceptance_rate=float(d.acceptance_rate or 100),
    )


@router.get("/nearby")
async def list_nearby_drivers(
    lat: float = Query(...),
    lng: float = Query(...),
    radius_km: float = Query(5.0, ge=0.5, le=30.0),
    vehicle_type: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Return online + approved drivers within `radius_km` of the given point.

    Used by the customer map to render moving vehicle pins around the pickup.
    Returns minimal data — id, vehicle_type, coords, distance — no PII.
    """
    stmt = select(Driver).where(
        Driver.is_online == True,  # noqa: E712
        Driver.status == DriverStatus.APPROVED,
    )
    if vehicle_type:
        stmt = stmt.where(Driver.vehicle_type == vehicle_type)
    q = await db.execute(stmt)
    drivers = q.scalars().all()

    out = []
    for d in drivers:
        if d.current_lat is None or d.current_lng is None:
            continue
        dist = haversine_km(lat, lng, float(d.current_lat), float(d.current_lng))
        if dist > radius_km:
            continue
        out.append({
            "id": d.id,
            "vehicle_type": d.vehicle_type,
            "lat": float(d.current_lat),
            "lng": float(d.current_lng),
            "distance_km": round(dist, 2),
        })
    out.sort(key=lambda r: r["distance_km"])
    return out


@router.get("/me", response_model=DriverProfileResponse)
async def get_my_driver_profile(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    d = await _get_driver(db, user)
    return _to_response(user, d)


@router.post("/register", response_model=DriverProfileResponse)
async def register_driver(
    body: DriverRegisterRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Submitted right after the driver's first OTP login.

    Collects vehicle + license + NIC details so the admin has enough info to
    approve the driver. Until this is done, the driver cannot go online.
    """
    if body.vehicle_type not in VALID_VEHICLE_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"vehicle_type must be one of {sorted(VALID_VEHICLE_TYPES)}",
        )

    d = await _get_driver(db, user)

    # Update user
    user.full_name = body.full_name
    if body.email:
        user.email = body.email

    # Uniqueness check for nic, license, vehicle_number (allow re-submit by same driver)
    for field, value in [
        (Driver.nic_number, body.nic_number),
        (Driver.license_number, body.license_number),
        (Driver.vehicle_number, body.vehicle_number),
    ]:
        clash = (
            await db.execute(select(Driver).where(field == value, Driver.id != d.id))
        ).scalars().first()
        if clash:
            raise HTTPException(
                status_code=409,
                detail=f"{field.key} '{value}' already registered to another driver",
            )

    d.nic_number = body.nic_number
    d.license_number = body.license_number
    d.vehicle_type = body.vehicle_type
    d.vehicle_number = body.vehicle_number
    d.vehicle_model = body.vehicle_model
    d.vehicle_color = body.vehicle_color
    # Stay in PENDING; admin will approve.
    if d.status == DriverStatus.PENDING:
        pass

    await db.commit()
    await db.refresh(d)
    await db.refresh(user)
    return _to_response(user, d)


@router.post("/location")
async def update_location(
    body: DriverLocationUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    d = await _get_driver(db, user)
    d.current_lat = Decimal(str(body.lat))
    d.current_lng = Decimal(str(body.lng))
    d.last_location_update = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}


@router.post("/online")
async def toggle_online(
    body: DriverOnlineToggle,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    d = await _get_driver(db, user)
    if body.is_online:
        if not _is_complete(d):
            raise HTTPException(
                status_code=400,
                detail="Complete your driver registration first.",
            )
        if not d.is_approved:
            raise HTTPException(
                status_code=403,
                detail="Your account is pending admin approval.",
            )
    d.is_online = body.is_online
    await db.commit()
    return {"is_online": d.is_online}

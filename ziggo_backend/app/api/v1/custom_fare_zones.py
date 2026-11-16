from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from typing import List

from ...database import get_db
from ...models import CustomFareZone, User
from ...schemas.misc_schema import (
    CustomFareZoneCreate,
    CustomFareZoneUpdate,
    CustomFareZoneResponse,
)
from ...services.auth_service import require_role, get_current_user
from ...services.zone_pricing_service import invalidate_custom_fare_zone_cache

router = APIRouter()


@router.post("", response_model=CustomFareZoneResponse, status_code=status.HTTP_201_CREATED)
async def create_custom_fare_zone(
    body: CustomFareZoneCreate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    if not body.coordinates or len(body.coordinates) < 3:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Zone must have at least 3 coordinate points to form a polygon",
        )

    zone = CustomFareZone(
        name=body.name.strip(),
        coordinates=body.coordinates,
        color=body.color or "#2563eb",
        is_active=body.is_active,
        exempt_peak_surge=body.exempt_peak_surge,
        rates=body.rates or {},
    )
    db.add(zone)
    await db.commit()
    await db.refresh(zone)
    invalidate_custom_fare_zone_cache()
    return zone


@router.get("/admin", response_model=List[CustomFareZoneResponse])
async def list_custom_fare_zones_admin(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(CustomFareZone).order_by(desc(CustomFareZone.id)))
    return q.scalars().all()


@router.get("/active", response_model=List[CustomFareZoneResponse])
async def list_active_custom_fare_zones(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    q = await db.execute(
        select(CustomFareZone)
        .where(CustomFareZone.is_active == True)  # noqa: E712
        .order_by(desc(CustomFareZone.id))
    )
    return q.scalars().all()


@router.get("/{zone_id}", response_model=CustomFareZoneResponse)
async def get_custom_fare_zone(
    zone_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(CustomFareZone).where(CustomFareZone.id == zone_id))
    zone = q.scalars().first()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")
    return zone


@router.put("/{zone_id}", response_model=CustomFareZoneResponse)
async def update_custom_fare_zone(
    zone_id: int,
    body: CustomFareZoneUpdate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(CustomFareZone).where(CustomFareZone.id == zone_id))
    zone = q.scalars().first()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")

    if body.name is not None:
        zone.name = body.name.strip()
    if body.coordinates is not None:
        if len(body.coordinates) < 3:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Zone must have at least 3 coordinate points to form a polygon",
            )
        zone.coordinates = body.coordinates
    if body.color is not None:
        zone.color = body.color
    if body.is_active is not None:
        zone.is_active = body.is_active
    if body.exempt_peak_surge is not None:
        zone.exempt_peak_surge = body.exempt_peak_surge
    if body.rates is not None:
        zone.rates = body.rates

    await db.commit()
    await db.refresh(zone)
    invalidate_custom_fare_zone_cache()
    return zone


@router.patch("/{zone_id}/toggle-active", response_model=CustomFareZoneResponse)
async def toggle_custom_fare_zone_active(
    zone_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(CustomFareZone).where(CustomFareZone.id == zone_id))
    zone = q.scalars().first()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")

    zone.is_active = not bool(zone.is_active)
    await db.commit()
    await db.refresh(zone)
    invalidate_custom_fare_zone_cache()
    return zone


@router.delete("/{zone_id}")
async def delete_custom_fare_zone(
    zone_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(CustomFareZone).where(CustomFareZone.id == zone_id))
    zone = q.scalars().first()
    if not zone:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")

    await db.delete(zone)
    await db.commit()
    invalidate_custom_fare_zone_cache()
    return {"ok": True, "deleted_id": zone_id}


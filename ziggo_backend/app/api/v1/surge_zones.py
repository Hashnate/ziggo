from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from datetime import datetime, timezone
import json

from ...database import get_db
from ...models import SurgeZone, User
from ...schemas.misc_schema import SurgeZoneCreate, SurgeZoneUpdate, SurgeZoneResponse
from ...services.auth_service import require_role, get_current_user

router = APIRouter()

# Admin routes
@router.post("", response_model=SurgeZoneResponse)
async def create_surge_zone(
    body: SurgeZoneCreate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    zone = SurgeZone(
        name=body.name,
        coordinates=body.coordinates,
        flat_extra_charge=body.flat_extra_charge,
        start_time=body.start_time,
        end_time=body.end_time,
        is_active=body.is_active,
        color=body.color,
    )
    db.add(zone)
    await db.commit()
    await db.refresh(zone)
    return zone

@router.get("/admin", response_model=List[SurgeZoneResponse])
async def list_surge_zones_admin(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(SurgeZone).order_by(SurgeZone.id.desc()))
    return q.scalars().all()

@router.put("/{zone_id}", response_model=SurgeZoneResponse)
async def update_surge_zone(
    zone_id: int,
    body: SurgeZoneUpdate,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(SurgeZone).where(SurgeZone.id == zone_id))
    zone = q.scalars().first()
    if not zone:
        raise HTTPException(status_code=404, detail="Zone not found")
    
    if body.name is not None:
        zone.name = body.name
    if body.coordinates is not None:
        zone.coordinates = body.coordinates
    if body.flat_extra_charge is not None:
        zone.flat_extra_charge = body.flat_extra_charge
    if body.start_time is not None:
        zone.start_time = body.start_time
    if body.end_time is not None:
        zone.end_time = body.end_time
    if body.is_active is not None:
        zone.is_active = body.is_active
    if body.color is not None:
        zone.color = body.color
        
    await db.commit()
    await db.refresh(zone)
    return zone

@router.delete("/{zone_id}")
async def delete_surge_zone(
    zone_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_role("admin")),
):
    q = await db.execute(select(SurgeZone).where(SurgeZone.id == zone_id))
    zone = q.scalars().first()
    if not zone:
        raise HTTPException(status_code=404, detail="Zone not found")
    await db.delete(zone)
    await db.commit()
    return {"ok": True}

# Public / App route
def is_time_in_range(start_time_str: str | None, end_time_str: str | None, now: datetime) -> bool:
    if not start_time_str or not end_time_str:
        return True # Active all the time if no time limits set
    
    try:
        sh, sm = map(int, start_time_str.split(":"))
        eh, em = map(int, end_time_str.split(":"))
        
        start_minutes = sh * 60 + sm
        end_minutes = eh * 60 + em
        current_minutes = now.hour * 60 + now.minute
        
        if start_minutes <= end_minutes:
            return start_minutes <= current_minutes <= end_minutes
        else:
            # Crosses midnight
            return current_minutes >= start_minutes or current_minutes <= end_minutes
    except Exception:
        return True

@router.get("/active", response_model=List[SurgeZoneResponse])
async def list_active_surge_zones(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    # Fetch all active zones
    q = await db.execute(select(SurgeZone).where(SurgeZone.is_active == True))
    all_active_zones = q.scalars().all()
    
    # Filter by time
    now = datetime.now() # Server local time, assuming it matches the expected timezone
    
    active_now = []
    for z in all_active_zones:
        if is_time_in_range(z.start_time, z.end_time, now):
            active_now.append(z)
            
    return active_now

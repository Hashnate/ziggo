"""Public, no-auth trip viewer for emergency contacts (BRD: CD-17 + CD-31).

Anyone with the share token can see the trip's last-known position,
status, ETA. The token is rotated whenever the rider re-shares.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from ...database import get_db
from ...models import Booking, Driver, User

router = APIRouter()


@router.get("/trip/share/{token}")
async def view_shared_trip(token: str, db: AsyncSession = Depends(get_db)):
    if not token or len(token) < 8:
        raise HTTPException(status_code=400, detail="Invalid share token")

    q = await db.execute(
        select(Booking)
        .options(selectinload(Booking.driver).selectinload(Driver.user))
        .where(Booking.share_token == token)
    )
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Share link is invalid or expired")

    driver = b.driver
    driver_user: User | None = driver.user if driver else None

    return {
        "booking_ref": b.booking_ref,
        "status": b.status.value if b.status else None,
        "pickup_address": b.pickup_address,
        "drop_address": b.drop_address,
        "distance_km": float(b.distance_km or 0),
        "duration_min": b.duration_min,
        "service_type": b.service_type,
        "started_at": b.started_at.isoformat() if b.started_at else None,
        "completed_at": b.completed_at.isoformat() if b.completed_at else None,
        # Driver's last-known live location while the trip is active.
        "driver": (
            {
                "name": (driver_user.full_name if driver_user else "") or "Driver",
                "vehicle_type": driver.vehicle_type,
                "vehicle_number": driver.vehicle_number,
                "lat": float(driver.current_lat) if driver.current_lat is not None else None,
                "lng": float(driver.current_lng) if driver.current_lng is not None else None,
                "last_seen": (
                    driver.last_location_update.isoformat()
                    if driver.last_location_update is not None
                    else None
                ),
            }
            if driver
            else None
        ),
    }

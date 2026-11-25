"""GET /bookings/{id}/route: the road route the driver and customer apps draw for a
booking (see services/route_service.py). Mounted under /bookings next to bookings.py."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...database import get_db
from ...models import Booking, User
from ...services import route_service
from ...services.auth_service import get_current_user

router = APIRouter()


@router.get("/{booking_id}/route")
async def get_booking_route(
    booking_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    if not await route_service.can_see(db, b, user):
        raise HTTPException(status_code=403, detail="Not your booking")
    return await route_service.route_for(db, b)

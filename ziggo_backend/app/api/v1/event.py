"""Events / ticketing — read-only public list + detail for the customer app.

Purchase pipeline is not wired yet (the customer app shows a "contact organizer"
CTA on tap). Admin creates events via /admin/events.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ...database import get_db
from ...models import Event

router = APIRouter()


def _serialize_event(e: Event, include_tiers: bool = False) -> dict:
    out = {
        "id": e.id,
        "name": e.name,
        "description": e.description,
        "venue": e.venue,
        "city": e.city,
        "image_url": e.image_url,
        "organizer_name": e.organizer_name,
        "organizer_phone": e.organizer_phone,
        "starts_at": e.starts_at.isoformat() if e.starts_at else None,
        "ends_at": e.ends_at.isoformat() if e.ends_at else None,
    }
    if include_tiers:
        out["tiers"] = [
            {
                "id": t.id,
                "name": t.name,
                "price": float(t.price or 0),
                "capacity": t.capacity,
                "description": t.description,
            }
            for t in e.tiers
        ]
        # Headline price = cheapest tier
        if e.tiers:
            out["from_price"] = float(min(t.price for t in e.tiers))
    else:
        # For list view, surface the cheapest price so cards can show "from Rs.X"
        # without us shipping the whole tier array.
        if e.tiers:
            out["from_price"] = float(min(t.price for t in e.tiers))
        else:
            out["from_price"] = None
    return out


@router.get("")
async def list_events(
    city: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    """List published, upcoming events. Optional ?city=Colombo filter."""
    now = datetime.now(timezone.utc)
    stmt = (
        select(Event)
        .options(selectinload(Event.tiers))
        .where(Event.is_published == True, Event.starts_at >= now)  # noqa: E712
        .order_by(Event.starts_at)
    )
    if city:
        stmt = stmt.where(Event.city == city)
    rows = (await db.execute(stmt)).scalars().all()
    return [_serialize_event(e) for e in rows]


@router.get("/{event_id}")
async def get_event(event_id: int, db: AsyncSession = Depends(get_db)):
    q = await db.execute(
        select(Event)
        .options(selectinload(Event.tiers))
        .where(Event.id == event_id)
    )
    e = q.scalars().first()
    if e is None or not e.is_published:
        raise HTTPException(status_code=404, detail="Event not found")
    return _serialize_event(e, include_tiers=True)

"""Public (unauthenticated) endpoints for the marketing website.

Isolated from the authed API. Currently exposes a fare estimate that reuses
the same fare engine (admin-editable FareSetting) as /bookings/estimate, but
without auth, promo, loyalty, or booking creation — so the public site can
show real per-km/base pricing.
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import Boolean, Column, DateTime, Integer, String, Text, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ...database import Base, get_db
from ...models import (
    Booking,
    BookingStatus,
    Driver,
    DriverStatus,
    FareSetting,
    MarketVendor,
    Restaurant,
    User,
    UserRole,
)
from ...services.fare_service import calculate_fare

router = APIRouter()


class PublicEstimateRequest(BaseModel):
    service_type: str
    pickup_lat: float
    pickup_lng: float
    drop_lat: float
    drop_lng: float


@router.post("/estimate")
async def public_estimate(
    req: PublicEstimateRequest,
    db: AsyncSession = Depends(get_db),
):
    fare = await calculate_fare(
        db,
        req.service_type,
        req.pickup_lat,
        req.pickup_lng,
        req.drop_lat,
        req.drop_lng,
    )
    return {
        "service_type": req.service_type,
        "distance_km": fare["distance_km"],
        "duration_min": fare["duration_min"],
        "fare_amount": fare["fare_amount"],
        "final_amount": fare["final_amount"],
    }


@router.get("/stats")
async def public_stats(db: AsyncSession = Depends(get_db)):
    """Live counts for the marketing site hero. Read-only aggregates."""
    drivers_online = (
        await db.execute(
            select(func.count(Driver.id)).where(Driver.is_online == True)  # noqa: E712
        )
    ).scalar() or 0
    drivers_total = (
        await db.execute(
            select(func.count(Driver.id)).where(Driver.status == DriverStatus.APPROVED)
        )
    ).scalar() or 0
    rides_completed = (
        await db.execute(
            select(func.count(Booking.id)).where(Booking.status == BookingStatus.COMPLETED)
        )
    ).scalar() or 0
    avg_rating = (
        await db.execute(
            select(func.avg(User.rating)).where(
                User.role == UserRole.DRIVER, User.rating > 0
            )
        )
    ).scalar()
    restaurants = (
        await db.execute(select(func.count(Restaurant.id)))
    ).scalar() or 0
    vendors = (
        await db.execute(select(func.count(MarketVendor.id)))
    ).scalar() or 0
    # Partner satisfaction = combined avg rating across restaurants + vendors.
    r_sum, r_cnt = (
        await db.execute(
            select(func.coalesce(func.sum(Restaurant.rating), 0), func.count(Restaurant.id)).where(
                Restaurant.rating > 0
            )
        )
    ).first()
    v_sum, v_cnt = (
        await db.execute(
            select(func.coalesce(func.sum(MarketVendor.rating), 0), func.count(MarketVendor.id)).where(
                MarketVendor.rating > 0
            )
        )
    ).first()
    total_cnt = (r_cnt or 0) + (v_cnt or 0)
    partner_rating = (
        round(float((r_sum or 0) + (v_sum or 0)) / total_cnt, 1) if total_cnt else None
    )
    return {
        "drivers_online": drivers_online,
        "drivers_total": drivers_total,
        "rides_completed": rides_completed,
        "avg_rating": round(float(avg_rating), 1) if avg_rating else None,
        "restaurants": restaurants,
        "vendors": vendors,
        "partner_rating": partner_rating,
    }


@router.get("/earnings")
async def public_earnings(
    service_type: str,
    hours: int = 40,
    db: AsyncSession = Depends(get_db),
):
    """Driver per-hour earnings derived from the real fare engine (admin rates
    + platform-fee split) and the real average completed-trip distance.
    Frontend multiplies per_hour by the chosen hours.
    """
    AVG_IDLE_MIN = 15.0  # tuned: realistic gap between trips (pickup + repositioning)
    # A) Real average completed-trip distance from the DB (fallback 8 km).
    avg_km = (
        await db.execute(
            select(func.avg(Booking.distance_km)).where(
                Booking.status == BookingStatus.COMPLETED,
                Booking.distance_km.isnot(None),
            )
        )
    ).scalar()
    avg_km = float(avg_km) if avg_km else 8.0
    # Build a trip of that length (≈ avg_km along latitude: 1° lat ≈ 111 km).
    delta_lat = avg_km / 111.0
    fare = await calculate_fare(
        db, service_type, 6.9000, 79.8600, 6.9000 + delta_lat, 79.8600
    )
    per_trip = float(fare.get("driver_earnings") or 0)
    trip_min = float(fare.get("duration_min") or 20)
    trips_per_hour = 60.0 / (trip_min + AVG_IDLE_MIN)
    per_hour = per_trip * trips_per_hour
    hours = max(1, min(int(hours), 80))
    weekly = round(per_hour * hours)
    return {
        "service_type": service_type,
        "per_hour": round(per_hour),
        "avg_trip_km": round(avg_km, 1),
        "hours": hours,
        "weekly": weekly,
        "monthly": weekly * 4,
    }


@router.get("/categories")
async def public_categories(db: AsyncSession = Depends(get_db)):
    """Active vehicle categories (from admin-managed FareSetting rows) so public
    forms — e.g. the driver application — can list the same categories as admin."""
    rows = (
        await db.execute(
            select(FareSetting)
            .where(FareSetting.is_active == True)  # noqa: E712
            .order_by(FareSetting.display_order, FareSetting.id)
        )
    ).scalars().all()
    return [
        {
            "service_type": c.service_type,
            "name": c.display_name or c.service_type,
            "image_url": c.image_url,
            "promo_message": c.promo_message,
            "passenger_deductible": float(c.passenger_deductible) if c.passenger_deductible else 0.0,
            "discount_percentage": float(c.discount_percentage) if c.discount_percentage else 0.0,
        }
        for c in rows
    ]


@router.get("/service-stats")
async def public_service_stats(
    service: str,
    db: AsyncSession = Depends(get_db),
):
    """Real, admin-editable pricing for a single service (e.g. truck), so the
    marketing service pages can show the live "from" fare. Read-only."""
    fs = (
        await db.execute(
            select(FareSetting).where(FareSetting.service_type == service)
        )
    ).scalars().first()
    base_fare = float(fs.base_fare) if fs and fs.base_fare is not None else None
    min_fare = float(fs.min_fare) if fs and fs.min_fare is not None else None
    # "from" price = the lowest a customer actually pays = the minimum fare
    # (falls back to the base/flagfall if no minimum is set).
    from_fare = min_fare or base_fare
    return {
        "service_type": service,
        "from_fare": from_fare,
        "base_fare": base_fare,
        "min_fare": min_fare,
        "display_name": fs.display_name if fs else None,
        "is_active": bool(fs.is_active) if fs else False,
    }


class ContactMessage(Base):
    """Submissions from the public website "Send a message" form. Isolated
    table — intentionally NOT linked to users or the support-ticket
    (complaints) system, so it touches nothing else in the backend."""

    __tablename__ = "contact_messages"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(120), nullable=False)
    email = Column(String(200), nullable=False)
    subject = Column(String(200))
    message = Column(Text, nullable=False)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class DriverApplication(Base):
    """Submissions from the public "Apply to drive" form. Isolated table — not
    linked to the real driver onboarding/users tables, so it touches nothing
    else in the backend."""

    __tablename__ = "driver_applications"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(120), nullable=False)
    mobile = Column(String(40), nullable=False)
    city = Column(String(80))
    vehicle_type = Column(String(40))
    nic = Column(String(40))
    status = Column(String(20), default="new")
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class PublicDriverApplicationRequest(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=120)
    mobile: str = Field(..., min_length=4, max_length=40)
    city: str | None = Field(None, max_length=80)
    vehicle_type: str | None = Field(None, max_length=40)
    nic: str | None = Field(None, max_length=40)


@router.post("/driver-application")
async def public_driver_application(
    req: PublicDriverApplicationRequest,
    db: AsyncSession = Depends(get_db),
):
    """Persist a driver application from the public Apply-to-drive form. No auth;
    isolated from the rest of the API."""
    row = DriverApplication(
        full_name=req.full_name.strip(),
        mobile=req.mobile.strip(),
        city=(req.city or "").strip() or None,
        vehicle_type=(req.vehicle_type or "").strip() or None,
        nic=(req.nic or "").strip() or None,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {
        "ok": True,
        "id": row.id,
        "message": "Thanks! We'll reach out within 48 hours.",
    }


class PublicContactRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    email: str = Field(..., min_length=3, max_length=200)
    subject: str | None = Field(None, max_length=200)
    message: str = Field(..., min_length=1, max_length=5000)


@router.post("/contact")
async def public_contact(
    req: PublicContactRequest,
    db: AsyncSession = Depends(get_db),
):
    """Persist a contact-form submission. No auth; isolated from the rest of
    the API. Admins can read the contact_messages table directly."""
    row = ContactMessage(
        name=req.name.strip(),
        email=req.email.strip(),
        subject=(req.subject or "").strip() or None,
        message=req.message.strip(),
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {
        "ok": True,
        "id": row.id,
        "message": "Thanks! We'll get back to you within 24 hours.",
    }

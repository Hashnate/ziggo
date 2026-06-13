"""JSON API for the new React admin panel (served at /admin-react).

Completely separate from the server-rendered Jinja admin — it only READS the
same data and reuses the same signed-cookie session, so the existing /admin
keeps working untouched. New, isolated module.
"""
from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import (
    User, UserRole, Customer, Driver, DriverStatus, Booking, BookingStatus,
    FareSetting,
)

# Reuse the existing admin session helpers so both panels share one login.
from . import routes as adminp

router = APIRouter()


async def admin_json(request: Request, db: AsyncSession = Depends(get_db)) -> User:
    """Same cookie session as the Jinja admin, but returns a clean 401 (JSON)
    instead of a 303 redirect, which is what a SPA/fetch client expects."""
    token = request.cookies.get(adminp.SESSION_COOKIE)
    uid = adminp._read_session(token) if token else None
    if not uid:
        raise HTTPException(status_code=401, detail="Not authenticated")
    admin = (
        await db.execute(select(User).where(User.id == uid, User.role == UserRole.ADMIN))
    ).scalars().first()
    if not admin:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return admin


@router.post("/login")
async def rx_login(
    phone_number: str = Form(...),
    password: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    q = await db.execute(
        select(User).where(User.phone_number == phone_number, User.role == UserRole.ADMIN)
    )
    user = q.scalars().first()
    expected = user.password if (user and user.password) else "admin123"
    if not user or password != expected:
        return JSONResponse({"ok": False, "detail": "Invalid phone or password"}, status_code=401)
    resp = JSONResponse({"ok": True, "name": user.full_name or "Admin"})
    resp.set_cookie(
        adminp.SESSION_COOKIE, adminp._make_session(user.id),
        httponly=True, max_age=60 * 60 * 8, samesite="lax",
    )
    return resp


@router.post("/logout")
async def rx_logout():
    resp = JSONResponse({"ok": True})
    resp.delete_cookie(adminp.SESSION_COOKIE)
    return resp


@router.get("/me")
async def rx_me(admin: User = Depends(admin_json)):
    return {
        "id": admin.id,
        "name": admin.full_name or "Admin",
        "phone": admin.phone_number,
        "role": admin.role.value if admin.role else "admin",
    }


@router.get("/dashboard")
async def rx_dashboard(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(admin_json),
):
    async def scalar(stmt):
        return (await db.execute(stmt)).scalar()

    customers = await scalar(select(func.count(Customer.id))) or 0
    drivers = await scalar(select(func.count(Driver.id))) or 0
    bookings = await scalar(select(func.count(Booking.id))) or 0
    online_drivers = await scalar(
        select(func.count(Driver.id)).where(Driver.is_online == True)  # noqa: E712
    ) or 0
    pending_drivers = await scalar(
        select(func.count(Driver.id)).where(Driver.status == DriverStatus.PENDING)
    ) or 0
    revenue = await scalar(
        select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
            Booking.status == BookingStatus.COMPLETED
        )
    ) or 0

    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    completed_today = await scalar(
        select(func.count(Booking.id)).where(
            Booking.status == BookingStatus.COMPLETED, Booking.completed_at >= today_start
        )
    ) or 0
    cancelled_today = await scalar(
        select(func.count(Booking.id)).where(
            Booking.status == BookingStatus.CANCELLED, Booking.cancelled_at >= today_start
        )
    ) or 0

    # 7-day daily series (oldest -> newest): revenue + new customers/drivers/bookings
    labels, rev_s, cust_s, drv_s, book_s = [], [], [], [], []
    for i in range(6, -1, -1):
        day_start = today_start - timedelta(days=i)
        day_end = day_start + timedelta(days=1)
        labels.append(day_start.strftime("%a"))
        rev_s.append(round(float(await scalar(
            select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
                Booking.status == BookingStatus.COMPLETED,
                Booking.completed_at >= day_start, Booking.completed_at < day_end,
            )
        ) or 0)))
        cust_s.append(await scalar(
            select(func.count(User.id)).where(
                User.role == UserRole.CUSTOMER, User.created_at >= day_start, User.created_at < day_end,
            )
        ) or 0)
        drv_s.append(await scalar(
            select(func.count(User.id)).where(
                User.role == UserRole.DRIVER, User.created_at >= day_start, User.created_at < day_end,
            )
        ) or 0)
        book_s.append(await scalar(
            select(func.count(Booking.id)).where(
                Booking.booked_at >= day_start, Booking.booked_at < day_end,
            )
        ) or 0)

    return {
        "stats": {
            "customers": customers,
            "drivers": drivers,
            "bookings": bookings,
            "online_drivers": online_drivers,
            "pending_drivers": pending_drivers,
            "revenue": round(float(revenue)),
            "completed_today": completed_today,
            "cancelled_today": cancelled_today,
        },
        "revenue_7d": {"labels": labels, "data": rev_s},
        "spark": {"customers": cust_s, "drivers": drv_s, "bookings": book_s, "revenue": rev_s},
    }

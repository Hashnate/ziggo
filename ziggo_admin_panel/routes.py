"""Server-rendered admin panel with real DB queries + simple session auth."""
from datetime import datetime, timezone, timedelta
import os
from decimal import Decimal

from fastapi import APIRouter, Request, Form, Depends, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from itsdangerous import URLSafeSerializer, BadSignature
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc
from sqlalchemy.orm import selectinload

from app.config import settings
from app.database import get_db
from app.models import (
    User,
    UserRole,
    Customer,
    Driver,
    DriverStatus,
    Booking,
    BookingStatus,
)

router = APIRouter()

current_dir = os.path.dirname(os.path.abspath(__file__))
templates = Jinja2Templates(directory=os.path.join(current_dir, "templates"))

UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "drivers")
os.makedirs(UPLOAD_DIR, exist_ok=True)
CATEGORY_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "categories")
os.makedirs(CATEGORY_UPLOAD_DIR, exist_ok=True)
VEHICLE_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "vehicles")
os.makedirs(VEHICLE_UPLOAD_DIR, exist_ok=True)
BRANDING_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "branding")
os.makedirs(BRANDING_UPLOAD_DIR, exist_ok=True)
ALLOWED_PHOTO_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".avif"}
MAX_PHOTO_BYTES = 5 * 1024 * 1024  # 5 MB

DOC_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "driver_docs")
os.makedirs(DOC_UPLOAD_DIR, exist_ok=True)
ALLOWED_DOC_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".pdf", ".avif"}
MAX_DOC_BYTES = 8 * 1024 * 1024  # 8 MB


async def _save_uploaded_photo(photo: UploadFile | None) -> str | None:
    """Save an uploaded driver photo and return its public URL path.

    Returns None if no file was uploaded. Raises HTTPException for invalid type

    or oversize files so the admin sees a clear error.
    """
    if photo is None or not photo.filename:
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        raise HTTPException(status_code=400, detail="Image must be JPG, PNG, WEBP, or AVIF")
    data = await photo.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/drivers/{fname}"


async def _save_uploaded_doc(doc: UploadFile | None, doc_type: str) -> str | None:
    if doc is None or not doc.filename:
        return None
    ext = os.path.splitext(doc.filename)[1].lower()
    if ext not in ALLOWED_DOC_EXTS:
        raise HTTPException(status_code=400, detail="Document must be JPG, PNG, WEBP, PDF, or AVIF")
    data = await doc.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_DOC_BYTES:
        raise HTTPException(status_code=400, detail="Document must be under 25 MB")
    import secrets
    fname = f"{doc_type}_{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(DOC_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/driver_docs/{fname}"


async def _save_vendor_doc(doc: UploadFile | None, doc_type: str) -> str | None:
    if doc is None or not doc.filename:
        return None
    ext = os.path.splitext(doc.filename)[1].lower()
    if ext not in ALLOWED_DOC_EXTS:
        raise HTTPException(status_code=400, detail="Document must be JPG, PNG, WEBP, PDF, or AVIF")
    data = await doc.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_DOC_BYTES:
        raise HTTPException(status_code=400, detail="Document must be under 8 MB")
    import secrets
    fname = f"{doc_type}_{secrets.token_hex(8)}{ext}"
    vendor_docs_dir = os.path.join(current_dir, "static", "uploads", "vendor_docs")
    os.makedirs(vendor_docs_dir, exist_ok=True)
    fpath = os.path.join(vendor_docs_dir, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/vendor_docs/{fname}"


async def _save_category_image(photo: UploadFile | None) -> str | None:
    if photo is None or not photo.filename:
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        raise HTTPException(status_code=400, detail="Image must be JPG, PNG, WEBP, or AVIF")
    data = await photo.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(CATEGORY_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/categories/{fname}"


async def _save_vehicle_photo(photo: UploadFile | None) -> str | None:
    if photo is None or not photo.filename:
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        raise HTTPException(status_code=400, detail="Photo must be JPG, PNG, WEBP, or AVIF")
    data = await photo.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Photo must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(VEHICLE_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/vehicles/{fname}"


# Favicons are allowed to be .ico in addition to the usual image types.
ALLOWED_BRANDING_EXTS = ALLOWED_PHOTO_EXTS | {".ico", ".svg"}


async def _save_branding_asset(asset: UploadFile | None, label: str) -> str | None:
    if asset is None or not asset.filename:
        return None
    ext = os.path.splitext(asset.filename)[1].lower()
    if ext not in ALLOWED_BRANDING_EXTS:
        raise HTTPException(
            status_code=400, detail=f"{label} must be JPG, PNG, WEBP, AVIF, SVG or ICO"
        )
    data = await asset.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail=f"{label} must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(BRANDING_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/branding/{fname}"

SESSION_COOKIE = "ziggo_admin"
_serializer = URLSafeSerializer(settings.SECRET_KEY, salt="ziggo-admin")


def _make_session(user_id: int) -> str:
    return _serializer.dumps({"uid": user_id})


def _read_session(token: str):
    try:
        data = _serializer.loads(token)
        return int(data.get("uid"))
    except (BadSignature, ValueError, TypeError):
        return None


class _AdminRedirect(Exception):
    """Raised by current_admin when the session is missing/invalid.

    Caught by an exception handler that returns a real 303 RedirectResponse.
    """


class _AdminForbidden(Exception):
    """Raised by role checks when the authenticated admin lacks permissions."""


async def current_admin(request: Request, db: AsyncSession = Depends(get_db)) -> User:
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        raise _AdminRedirect()
    uid = _read_session(token)
    if not uid:
        raise _AdminRedirect()
    q = await db.execute(select(User).where(User.id == uid, User.role == UserRole.ADMIN))
    admin = q.scalars().first()
    if not admin:
        raise _AdminRedirect()
    request.state.admin = admin
    return admin


async def require_superadmin(request: Request, admin: User = Depends(current_admin)) -> User:
    if (admin.admin_role or "admin") != "superadmin":
        raise _AdminForbidden()
    return admin


async def require_superadmin_or_admin(request: Request, admin: User = Depends(current_admin)) -> User:
    if (admin.admin_role or "admin") not in ("superadmin", "admin"):
        raise _AdminForbidden()
    return admin


# ---------- Auth ----------
_FAILED_LOGIN_ATTEMPTS: dict[str, int] = {}


@router.get("/login", response_class=HTMLResponse)
async def admin_login_get(request: Request):
    return templates.TemplateResponse(request, "login.html", {"request": request, "error": None})


@router.post("/login")
async def admin_login_post(
    request: Request,
    phone_number: str = Form(...),
    password: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    """Dev login: phone + 'admin123'. Seed script creates admin@0700000000 by default."""
    s = await _get_or_create_settings(db)
    max_attempts = s.max_login_attempts or 5
    attempts = _FAILED_LOGIN_ATTEMPTS.get(phone_number, 0)
    if attempts >= max_attempts:
        return templates.TemplateResponse(
            request, "login.html",
            {"request": request, "error": "Account locked due to too many failed attempts. Contact support."},
            status_code=403,
        )

    q = await db.execute(
        select(User).where(User.phone_number == phone_number, User.role == UserRole.ADMIN)
    )
    user = q.scalars().first()
    expected = user.password if (user and user.password) else "admin123"
    if not user or password != expected:
        _FAILED_LOGIN_ATTEMPTS[phone_number] = attempts + 1
        return templates.TemplateResponse(
            request, "login.html",
            {"request": request, "error": "Invalid credentials"},
            status_code=401,
        )
    
    _FAILED_LOGIN_ATTEMPTS[phone_number] = 0
    resp = RedirectResponse(url="/admin/dashboard", status_code=303)
    timeout_mins = s.session_timeout_minutes or 30
    resp.set_cookie(SESSION_COOKIE, _make_session(user.id), httponly=True, max_age=60 * timeout_mins)
    return resp


@router.get("/logout")
async def admin_logout():
    resp = RedirectResponse(url="/admin/login", status_code=303)
    resp.delete_cookie(SESSION_COOKIE)
    return resp


@router.post("/forgot-password/send-otp")
async def admin_forgot_password_send_otp(
    phone_number: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    from app.services.auth_service import create_and_send_otp
    q = await db.execute(
        select(User).where(User.phone_number == phone_number, User.role == UserRole.ADMIN)
    )
    user = q.scalars().first()
    if not user:
        return {"ok": False, "detail": "Admin phone number not found"}
    
    code = await create_and_send_otp(db, phone_number)
    return {
        "ok": True,
        "message": "OTP sent successfully",
        "dev_otp": code if settings.DEV_MODE else None,
    }


@router.post("/forgot-password/reset")
async def admin_forgot_password_reset(
    phone_number: str = Form(...),
    otp: str = Form(...),
    new_password: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    from app.services.auth_service import verify_otp_code
    s = await _get_or_create_settings(db)
    min_len = s.min_password_length or 6
    if len(new_password) < min_len:
        return {"ok": False, "detail": f"Password must be at least {min_len} characters long"}

    q = await db.execute(
        select(User).where(User.phone_number == phone_number, User.role == UserRole.ADMIN)
    )
    user = q.scalars().first()
    if not user:
        return {"ok": False, "detail": "Admin phone number not found"}
    
    ok = await verify_otp_code(db, phone_number, otp)
    if not ok:
        return {"ok": False, "detail": "Invalid or expired OTP"}
    
    user.password = new_password
    await db.commit()
    return {"ok": True, "message": "Password reset successful"}


# ---------- Pages ----------
@router.get("/dashboard", response_class=HTMLResponse)
async def admin_dashboard(
    request: Request,
    days: int = 7,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from datetime import timedelta
    from app.models import FareSetting

    if days not in (7, 30):
        days = 7

    customers = (await db.execute(select(func.count(Customer.id)))).scalar()
    drivers = (await db.execute(select(func.count(Driver.id)))).scalar()
    bookings = (await db.execute(select(func.count(Booking.id)))).scalar()
    online_drivers = (
        await db.execute(select(func.count(Driver.id)).where(Driver.is_online == True))  # noqa: E712
    ).scalar()
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    completed_today = (
        await db.execute(
            select(func.count(Booking.id)).where(
                Booking.status == BookingStatus.COMPLETED, Booking.completed_at >= today_start
            )
        )
    ).scalar()
    cancelled_today = (
        await db.execute(
            select(func.count(Booking.id)).where(
                Booking.status == BookingStatus.CANCELLED, Booking.cancelled_at >= today_start
            )
        )
    ).scalar()
    pending_drivers = (
        await db.execute(select(func.count(Driver.id)).where(Driver.status == DriverStatus.PENDING))
    ).scalar()
    # Total revenue across ALL streams (rides + flash, food, market, gold)
    from app.models import FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus, WalletTransaction
    from sqlalchemy import cast as _cast, Date as _Date
    _rev_rides = (await db.execute(select(func.coalesce(func.sum(Booking.final_amount), 0)).where(Booking.status == BookingStatus.COMPLETED))).scalar() or 0
    _rev_food = (await db.execute(select(func.coalesce(func.sum(FoodOrder.final_amount), 0)).where(FoodOrder.status == FoodOrderStatus.DELIVERED))).scalar() or 0
    _rev_market = (await db.execute(select(func.coalesce(func.sum(MarketOrder.final_amount), 0)).where(MarketOrder.status == MarketOrderStatus.DELIVERED))).scalar() or 0
    _rev_gold = (await db.execute(select(func.coalesce(func.sum(WalletTransaction.amount), 0)).where(WalletTransaction.reference_id == "GOLD"))).scalar() or 0
    revenue = float(_rev_rides) + float(_rev_food) + float(_rev_market) + float(_rev_gold)
    avg_surge = (
        await db.execute(
            select(func.coalesce(func.avg(FareSetting.surge_multiplier), 1))
        )
    ).scalar()

    # Daily revenue for the last N days — across ALL streams
    window_start = today_start - timedelta(days=days - 1)
    window_end = today_start + timedelta(days=1)
    rev_by_day = {}

    def _acc_rev(day, amt):
        rev_by_day[day.isoformat()] = rev_by_day.get(day.isoformat(), 0.0) + float(amt or 0)

    for day, amt in (await db.execute(
        select(_cast(Booking.booked_at, _Date), func.coalesce(func.sum(Booking.final_amount), 0))
        .where(Booking.status == BookingStatus.COMPLETED, Booking.booked_at >= window_start, Booking.booked_at < window_end)
        .group_by(_cast(Booking.booked_at, _Date))
    )).all():
        _acc_rev(day, amt)
    for day, amt in (await db.execute(
        select(_cast(FoodOrder.created_at, _Date), func.coalesce(func.sum(FoodOrder.final_amount), 0))
        .where(FoodOrder.status == FoodOrderStatus.DELIVERED, FoodOrder.created_at >= window_start, FoodOrder.created_at < window_end)
        .group_by(_cast(FoodOrder.created_at, _Date))
    )).all():
        _acc_rev(day, amt)
    for day, amt in (await db.execute(
        select(_cast(MarketOrder.created_at, _Date), func.coalesce(func.sum(MarketOrder.final_amount), 0))
        .where(MarketOrder.status == MarketOrderStatus.DELIVERED, MarketOrder.created_at >= window_start, MarketOrder.created_at < window_end)
        .group_by(_cast(MarketOrder.created_at, _Date))
    )).all():
        _acc_rev(day, amt)
    for day, amt in (await db.execute(
        select(_cast(WalletTransaction.created_at, _Date), func.coalesce(func.sum(WalletTransaction.amount), 0))
        .where(WalletTransaction.reference_id == "GOLD", WalletTransaction.created_at >= window_start, WalletTransaction.created_at < window_end)
        .group_by(_cast(WalletTransaction.created_at, _Date))
    )).all():
        _acc_rev(day, amt)

    labels = []
    data = []
    for i in range(days - 1, -1, -1):
        day_start = today_start - timedelta(days=i)
        if days == 30:
            labels.append(day_start.strftime("%b %d"))
        else:
            labels.append(day_start.strftime("%a"))
        data.append(rev_by_day.get(day_start.date().isoformat(), 0.0))

    return templates.TemplateResponse(
        request, "dashboard.html",
        {
            "request": request,
            "active_page": "dashboard",
            "days": days,
            "stats": {
                "total_customers": customers,
                "total_drivers": drivers,
                "total_bookings": bookings,
                "online_drivers": online_drivers,
                "completed_today": completed_today,
                "cancelled_today": cancelled_today,
                "pending_drivers": pending_drivers,
                "revenue": float(revenue or 0),
                "avg_surge": float(avg_surge or 1),
                "revenue_chart_labels": labels,
                "revenue_chart_data": data,
            },
        },
    )


@router.get("/drivers", response_class=HTMLResponse)
async def admin_drivers(
    request: Request,
    page: int = 1,
    status: str = "all",
    search: str = "",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from sqlalchemy import or_

    limit = 50
    offset = (page - 1) * limit

    # Build filter conditions
    where_clauses = []
    
    # Status filter
    if status == "online":
        where_clauses.append(Driver.is_online == True)
    elif status == "offline":
        where_clauses.append(Driver.is_online == False)
        where_clauses.append(Driver.is_approved == True)
    elif status == "pending":
        where_clauses.append(Driver.status == DriverStatus.PENDING)
        
    # Search filter
    if search:
        search_term = f"%{search.strip()}%"
        where_clauses.append(
            or_(
                User.full_name.ilike(search_term),
                User.phone_number.ilike(search_term),
                User.email.ilike(search_term),
                Driver.vehicle_number.ilike(search_term),
                Driver.vehicle_model.ilike(search_term),
            )
        )

    # Base query for drivers
    stmt = (
        select(Driver)
        .join(User, Driver.user_id == User.id)
    )
    if where_clauses:
        stmt = stmt.where(*where_clauses)

    # Total count of all drivers in system (for stats bar)
    total_all = (await db.execute(select(func.count(Driver.id)))).scalar() or 0

    # Total count under current filters (for list pagination)
    count_stmt = select(func.count(Driver.id)).join(User, Driver.user_id == User.id)
    if where_clauses:
        count_stmt = count_stmt.where(*where_clauses)
    total = (await db.execute(count_stmt)).scalar() or 0
    total_pages = (total + limit - 1) // limit

    # Query matching records
    q = await db.execute(
        stmt.options(selectinload(Driver.user))
        .order_by(Driver.id.desc())
        .offset(offset)
        .limit(limit)
    )
    drivers = q.scalars().all()
    for drv in drivers:
        drv.settlement_amount = float(await fin.get_driver_outstanding_commission(db, drv.id))

    online = (
        await db.execute(select(func.count(Driver.id)).where(Driver.is_online == True))  # noqa: E712
    ).scalar() or 0
    pending = (
        await db.execute(
            select(func.count(Driver.id)).where(Driver.status == DriverStatus.PENDING)
        )
    ).scalar() or 0
    avg_rating_q = await db.execute(
        select(func.coalesce(func.avg(User.rating), 0)).where(User.role == UserRole.DRIVER)
    )
    avg_rating = float(avg_rating_q.scalar() or 0)

    stats = {
        "total": total_all,
        "online": online,
        "online_pct": int(round((online / total_all * 100) if total_all else 0)),
        "pending": pending,
        "avg_rating": avg_rating,
    }

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "drivers.html",
        {
            "request": request,
            "active_page": "drivers",
            "drivers": drivers,
            "stats": stats,
            "page": page,
            "total_pages": total_pages,
            "total_drivers": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "status": status,
            "search": search,
        },
    )



@router.get("/drivers/export")
async def admin_drivers_export(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Download the driver list as CSV. Read-only export over the existing
    Driver/User tables — changes nothing else in the app."""
    import csv
    import io
    from fastapi.responses import Response

    q = await db.execute(
        select(Driver).options(selectinload(Driver.user)).order_by(Driver.id.desc())
    )
    drivers = q.scalars().all()

    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow([
        "ID", "Name", "Phone", "NIC", "License", "Vehicle Type", "Vehicle No",
        "Model", "Color", "Year", "Status", "Online", "Rating", "Total Rides",
        "Total Earnings",
    ])
    for d in drivers:
        u = d.user
        w.writerow([
            d.id,
            (u.full_name if u else "") or "",
            (u.phone_number if u else "") or "",
            d.nic_number or "",
            d.license_number or "",
            d.vehicle_type or "",
            d.vehicle_number or "",
            d.vehicle_model or "",
            d.vehicle_color or "",
            d.vehicle_year or "",
            d.status.value if d.status else "",
            "Yes" if d.is_online else "No",
            (u.rating if u else "") or "",
            (u.total_rides if u else "") or "",
            d.total_earnings if d.total_earnings is not None else 0,
        ])

    return Response(
        content=buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=ziggo-drivers.csv"},
    )


@router.get("/drivers/new", response_class=HTMLResponse)
async def admin_drivers_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    docs = []
    for kind, label in [
        ("nic_front", "NIC Front"),
        ("nic_back", "NIC Back"),
        ("license_front", "Driving License Front"),
        ("license_back", "Driving License Back"),
        ("vehicle_reg", "Vehicle Registration"),
        ("insurance", "Insurance"),
        ("year_license", "Year License"),
        ("eco_test", "Eco Test Report"),
        ("vehicle_front", "Vehicle Photo — Front"),
        ("vehicle_back", "Vehicle Photo — Back"),
        ("vehicle_side", "Vehicle Photo — Side"),
    ]:
        docs.append({
            "kind": kind,
            "label": label,
            "id": None,
            "document_url": None,
            "is_verified": False,
            "uploaded_at": None,
        })
    return templates.TemplateResponse(
        request, "driver_new.html",
        {"request": request, "active_page": "drivers", "error": None, "form": {}, "documents": docs},
    )


@router.post("/drivers/new")
async def admin_drivers_new_submit(
    request: Request,
    phone_number: str = Form(...),
    full_name: str = Form(...),
    email: str = Form(""),
    nic_number: str = Form(...),
    license_number: str = Form(...),
    vehicle_type: str = Form(...),
    vehicle_number: str = Form(...),
    vehicle_model: str = Form(...),
    vehicle_color: str = Form(...),
    is_approved: str = Form(""),
    relative_name: str = Form(""),
    relative_contact: str = Form(""),
    relative_relationship: str = Form(""),
    profile_photo: UploadFile | None = File(None),
    doc_nic_front: UploadFile | None = File(None),
    doc_nic_back: UploadFile | None = File(None),
    doc_license_front: UploadFile | None = File(None),
    doc_license_back: UploadFile | None = File(None),
    doc_vehicle_reg: UploadFile | None = File(None),
    doc_insurance: UploadFile | None = File(None),
    doc_year_license: UploadFile | None = File(None),
    doc_eco_test: UploadFile | None = File(None),
    doc_vehicle_front: UploadFile | None = File(None),
    doc_vehicle_back: UploadFile | None = File(None),
    doc_vehicle_side: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import UserRole

    form = {
        "phone_number": phone_number,
        "full_name": full_name,
        "email": email,
        "nic_number": nic_number,
        "license_number": license_number,
        "vehicle_type": vehicle_type,
        "vehicle_number": vehicle_number,
        "vehicle_model": vehicle_model,
        "vehicle_color": vehicle_color,
        "is_approved": is_approved,
        "relative_name": relative_name,
        "relative_contact": relative_contact,
        "relative_relationship": relative_relationship,
    }

    # Construct docs list in case of error
    docs = []
    for kind, label in [
        ("nic_front", "NIC Front"),
        ("nic_back", "NIC Back"),
        ("license_front", "Driving License Front"),
        ("license_back", "Driving License Back"),
        ("vehicle_reg", "Vehicle Registration"),
        ("insurance", "Insurance"),
        ("year_license", "Year License"),
        ("eco_test", "Eco Test Report"),
        ("vehicle_front", "Vehicle Photo — Front"),
        ("vehicle_back", "Vehicle Photo — Back"),
        ("vehicle_side", "Vehicle Photo — Side"),
    ]:
        docs.append({
            "kind": kind,
            "label": label,
            "id": None,
            "document_url": None,
            "is_verified": False,
            "uploaded_at": None,
        })

    if vehicle_type not in {"bike", "tuk", "car", "van", "truck"}:
        return templates.TemplateResponse(
            request, "driver_new.html",
            {"request": request, "active_page": "drivers", "error": "Invalid vehicle type", "form": form, "documents": docs},
            status_code=400,
        )

    existing = (
        await db.execute(select(User).where(User.phone_number == phone_number))
    ).scalars().first()
    if existing:
        return templates.TemplateResponse(
            request, "driver_new.html",
            {"request": request, "active_page": "drivers", "error": "Phone number already registered", "form": form, "documents": docs},
            status_code=409,
        )

    for field, value, label in [
        (Driver.nic_number, nic_number, "NIC"),
        (Driver.license_number, license_number, "License"),
        (Driver.vehicle_number, vehicle_number, "Vehicle number"),
    ]:
        if (await db.execute(select(Driver).where(field == value))).scalars().first():
            return templates.TemplateResponse(
                request, "driver_new.html",
                {"request": request, "active_page": "drivers", "error": f"{label} already in use", "form": form, "documents": docs},
                status_code=409,
            )

    from datetime import datetime, timezone
    from decimal import Decimal

    photo_url = await _save_uploaded_photo(profile_photo)

    user = User(
        phone_number=phone_number,
        role=UserRole.DRIVER,
        full_name=full_name,
        email=email or None,
        profile_photo=photo_url,
        is_active=True,
    )
    db.add(user)
    await db.flush()

    approved = (is_approved == "1" or is_approved == "on")
    driver = Driver(
        user_id=user.id,
        nic_number=nic_number,
        license_number=license_number,
        vehicle_type=vehicle_type,
        vehicle_number=vehicle_number,
        vehicle_model=vehicle_model,
        vehicle_color=vehicle_color,
        is_approved=approved,
        is_online=False,
        status=DriverStatus.APPROVED if approved else DriverStatus.PENDING,
        approved_at=datetime.now(timezone.utc) if approved else None,
        acceptance_rate=Decimal("100"),
        total_earnings=Decimal("0"),
        today_earnings=Decimal("0"),
        today_rides=0,
        relative_name=relative_name or None,
        relative_contact=relative_contact or None,
        relative_relationship=relative_relationship or None,
    )
    db.add(driver)
    await db.flush()

    from app.models import DriverDocument
    for kind in ("nic_front", "nic_back", "license_front", "license_back", "vehicle_reg", "insurance", "year_license", "eco_test", "vehicle_front", "vehicle_back", "vehicle_side"):
        file_input = locals().get(f"doc_{kind}")
        if file_input:
            url = await _save_uploaded_doc(file_input, kind)
            if url:
                doc = DriverDocument(
                    driver_id=driver.id,
                    document_type=kind,
                    document_url=url,
                    is_verified=False,
                )
                db.add(doc)

    await db.commit()

    return RedirectResponse(url="/admin/drivers", status_code=303)



@router.get("/drivers/{driver_id}/edit", response_class=HTMLResponse)
async def admin_drivers_edit_form(
    driver_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Driver).options(selectinload(Driver.user)).where(Driver.id == driver_id)
    )
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver not found")

    # BRD: load uploaded KYC documents so the admin can verify them inline
    from app.models import DriverDocument
    dq = await db.execute(
        select(DriverDocument).where(DriverDocument.driver_id == d.id)
    )
    docs_by_kind = {row.document_type: row for row in dq.scalars().all()}

    docs = []
    for kind, label in [
        ("nic_front", "NIC Front"),
        ("nic_back", "NIC Back"),
        ("license_front", "Driving License Front"),
        ("license_back", "Driving License Back"),
        ("vehicle_reg", "Vehicle Registration"),
        ("insurance", "Insurance"),
        ("year_license", "Year License"),
        ("eco_test", "Eco Test Report"),
        ("vehicle_front", "Vehicle Photo — Front"),
        ("vehicle_back", "Vehicle Photo — Back"),
        ("vehicle_side", "Vehicle Photo — Side"),
    ]:
        row = docs_by_kind.get(kind)
        docs.append({
            "kind": kind,
            "label": label,
            "id": row.id if row else None,
            "document_url": row.document_url if row else None,
            "is_verified": bool(row.is_verified) if row else False,
            "uploaded_at": row.uploaded_at if row else None,
        })

    return templates.TemplateResponse(
        request, "driver_edit.html",
        {
            "request": request,
            "active_page": "drivers",
            "driver": d,
            "user": d.user,
            "documents": docs,
            "error": None,
        },
    )


@router.post("/drivers/{driver_id}/edit")
async def admin_drivers_edit_submit(
    driver_id: int,
    request: Request,
    phone_number: str = Form(...),
    full_name: str = Form(...),
    email: str = Form(""),
    nic_number: str = Form(...),
    license_number: str = Form(...),
    vehicle_type: str = Form(...),
    vehicle_number: str = Form(...),
    vehicle_model: str = Form(...),
    vehicle_color: str = Form(...),
    is_approved: str = Form(""),
    remove_photo: str = Form(""),
    profile_photo: UploadFile | None = File(None),
    relative_name: str = Form(""),
    relative_contact: str = Form(""),
    relative_relationship: str = Form(""),
    doc_nic_front: UploadFile | None = File(None),
    doc_nic_back: UploadFile | None = File(None),
    doc_license_front: UploadFile | None = File(None),
    doc_license_back: UploadFile | None = File(None),
    doc_vehicle_reg: UploadFile | None = File(None),
    doc_insurance: UploadFile | None = File(None),
    doc_year_license: UploadFile | None = File(None),
    doc_eco_test: UploadFile | None = File(None),
    doc_vehicle_front: UploadFile | None = File(None),
    doc_vehicle_back: UploadFile | None = File(None),
    doc_vehicle_side: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Driver).options(selectinload(Driver.user)).where(Driver.id == driver_id)
    )
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver not found")
    user = d.user

    def _err(msg: str, status: int = 400):
        return templates.TemplateResponse(
            request, "driver_edit.html",
            {
                "request": request,
                "active_page": "drivers",
                "driver": d,
                "user": user,
                "documents": [],
                "error": msg,
            },
            status_code=status,
        )

    if vehicle_type not in {"bike", "tuk", "car", "van", "truck"}:
        return _err("Invalid vehicle type")

    # Phone-number uniqueness (excluding this user)
    if phone_number != user.phone_number:
        clash = (
            await db.execute(
                select(User).where(User.phone_number == phone_number, User.id != user.id)
            )
        ).scalars().first()
        if clash:
            return _err("Phone number already used by another account", status=409)

    # NIC / License / Vehicle number uniqueness (excluding this driver)
    for field, value, label in [
        (Driver.nic_number, nic_number, "NIC"),
        (Driver.license_number, license_number, "License"),
        (Driver.vehicle_number, vehicle_number, "Vehicle number"),
    ]:
        clash = (
            await db.execute(select(Driver).where(field == value, Driver.id != d.id))
        ).scalars().first()
        if clash:
            return _err(f"{label} already in use by another driver", status=409)

    # Photo handling: new upload wins; otherwise keep or clear based on remove_photo
    new_photo_url = await _save_uploaded_photo(profile_photo)
    if new_photo_url:
        user.profile_photo = new_photo_url
    elif remove_photo:
        user.profile_photo = None

    user.phone_number = phone_number
    user.full_name = full_name
    user.email = email or None

    d.nic_number = nic_number
    d.license_number = license_number
    d.vehicle_type = vehicle_type
    d.vehicle_number = vehicle_number
    d.vehicle_model = vehicle_model
    d.vehicle_color = vehicle_color
    d.relative_name = relative_name or None
    d.relative_contact = relative_contact or None
    d.relative_relationship = relative_relationship or None

    approved_now = bool(is_approved)
    if approved_now and not d.is_approved:
        d.is_approved = True
        d.status = DriverStatus.APPROVED
        d.approved_at = datetime.now(timezone.utc)
    elif not approved_now and d.is_approved:
        d.is_approved = False
        d.is_online = False
        d.status = DriverStatus.SUSPENDED

    from app.models import DriverDocument
    for kind in ("nic_front", "nic_back", "license_front", "license_back", "vehicle_reg", "insurance", "year_license", "eco_test", "vehicle_front", "vehicle_back", "vehicle_side"):
        file_input = locals().get(f"doc_{kind}")
        if file_input:
            url = await _save_uploaded_doc(file_input, kind)
            if url:
                exq = await db.execute(
                    select(DriverDocument).where(
                        DriverDocument.driver_id == d.id,
                        DriverDocument.document_type == kind,
                    )
                )
                existing = exq.scalars().first()
                if existing:
                    existing.document_url = url
                    existing.is_verified = False
                    existing.verified_by = None
                    existing.verified_at = None
                    existing.uploaded_at = datetime.now(timezone.utc)
                else:
                    doc = DriverDocument(
                        driver_id=d.id,
                        document_type=kind,
                        document_url=url,
                        is_verified=False,
                    )
                    db.add(doc)

    await db.commit()
    return RedirectResponse(url="/admin/drivers", status_code=303)


@router.post("/drivers/{driver_id}/approve")
async def approve_driver_form(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if d:
        d.is_approved = True
        d.status = DriverStatus.APPROVED
        d.approved_at = datetime.now(timezone.utc)
        await db.commit()
    return RedirectResponse(url="/admin/drivers", status_code=303)


@router.post("/drivers/{driver_id}/suspend")
async def suspend_driver_form(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if d:
        d.is_approved = False
        d.is_online = False
        d.status = DriverStatus.SUSPENDED
        await db.commit()
    return RedirectResponse(url="/admin/drivers", status_code=303)


@router.post("/drivers/{driver_id}/deactivate")
async def deactivate_driver_form(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Driver)
        .options(selectinload(Driver.user))
        .where(Driver.id == driver_id)
    )
    d = q.scalars().first()
    if d:
        d.is_approved = False
        d.is_online = False
        d.status = DriverStatus.SUSPENDED
        if d.user:
            d.user.is_active = False
        await db.commit()
    return RedirectResponse(url="/admin/drivers", status_code=303)


@router.post("/drivers/{driver_id}/activate")
async def activate_driver_form(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Driver)
        .options(selectinload(Driver.user))
        .where(Driver.id == driver_id)
    )
    d = q.scalars().first()
    if d:
        if d.user:
            d.user.is_active = True
        await db.commit()
    return RedirectResponse(url="/admin/drivers", status_code=303)


@router.get("/customers", response_class=HTMLResponse)
async def admin_customers(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(Customer.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Customer)
        .options(selectinload(Customer.user))
        .order_by(Customer.id.desc())
        .offset(offset)
        .limit(limit)
    )
    customers = q.scalars().all()

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "customers.html",
        {
            "request": request,
            "active_page": "customers",
            "customers": customers,
            "page": page,
            "total_pages": total_pages,
            "total_customers": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


# ─── Riders ──────────────────────────────────────────────────────────────────

@router.get("/riders", response_class=HTMLResponse)
async def admin_riders(
    request: Request,
    page: int = 1,
    status: str = "all",
    search: str = "",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from sqlalchemy import or_, and_
    from datetime import date

    limit = 50
    offset = (page - 1) * limit

    # Build filter conditions on the User join
    conditions = []
    if status == "active":
        conditions.append(User.is_active == True)
    elif status == "inactive":
        conditions.append(User.is_active == False)
    if search:
        s = f"%{search}%"
        conditions.append(
            or_(
                User.full_name.ilike(s),
                User.phone_number.ilike(s),
                User.email.ilike(s),
            )
        )

    base_stmt = (
        select(Customer)
        .join(Customer.user)
        .options(selectinload(Customer.user))
    )
    if conditions:
        base_stmt = base_stmt.where(and_(*conditions))

    total = (await db.execute(
        select(func.count()).select_from(base_stmt.subquery())
    )).scalar() or 0

    riders_q = await db.execute(
        base_stmt.order_by(Customer.id.desc()).offset(offset).limit(limit)
    )
    riders = riders_q.scalars().all()

    total_pages = (total + limit - 1) // limit
    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    # Stat counts (full table, ignore current filters)
    total_riders = (await db.execute(select(func.count(Customer.id)))).scalar() or 0
    active_riders = (
        await db.execute(
            select(func.count(Customer.id)).join(Customer.user).where(User.is_active == True)
        )
    ).scalar() or 0
    inactive_riders = total_riders - active_riders

    today = date.today()
    joined_today = (
        await db.execute(
            select(func.count(Customer.id)).join(Customer.user).where(func.date(User.created_at) == today)
        )
    ).scalar() or 0

    return templates.TemplateResponse(
        request, "riders.html",
        {
            "request": request,
            "active_page": "riders",
            "riders": riders,
            "page": page,
            "total_pages": total_pages,
            "total_riders": total_riders,
            "active_riders": active_riders,
            "inactive_riders": inactive_riders,
            "joined_today": joined_today,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "status": status,
            "search": search,
        },
    )


@router.get("/riders/export")
async def admin_riders_export(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    import csv
    import io
    from fastapi.responses import StreamingResponse

    q = await db.execute(
        select(Customer).options(selectinload(Customer.user)).order_by(Customer.id.desc())
    )
    riders = q.scalars().all()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "Name", "Email", "Phone", "Total Rides", "Wallet Balance", "Gold Member", "Status", "Joined"])
    for c in riders:
        u = c.user
        writer.writerow([
            c.id,
            u.full_name or "",
            u.email or "",
            u.phone_number or "",
            u.total_rides or 0,
            float(c.wallet_balance or 0),
            "Yes" if c.gold_member else "No",
            "Active" if u.is_active else "Inactive",
            u.created_at.strftime("%Y-%m-%d") if u.created_at else "",
        ])

    output.seek(0)
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=riders.csv"},
    )


@router.post("/riders/{customer_id}/deactivate")
async def admin_rider_deactivate(
    customer_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Customer).options(selectinload(Customer.user)).where(Customer.id == customer_id)
    )
    c = q.scalars().first()
    if c and c.user:
        c.user.is_active = False
        await db.commit()
    return RedirectResponse(url="/admin/riders", status_code=303)


@router.post("/riders/{customer_id}/activate")
async def admin_rider_activate(
    customer_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Customer).options(selectinload(Customer.user)).where(Customer.id == customer_id)
    )
    c = q.scalars().first()
    if c and c.user:
        c.user.is_active = True
        await db.commit()
    return RedirectResponse(url="/admin/riders", status_code=303)


@router.post("/riders/{customer_id}/delete")
async def admin_rider_delete(
    customer_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Customer).options(selectinload(Customer.user)).where(Customer.id == customer_id)
    )
    c = q.scalars().first()
    if c:
        user = c.user
        await db.delete(c)
        if user:
            await db.delete(user)
        await db.commit()
    return RedirectResponse(url="/admin/riders", status_code=303)


@router.get("/bookings", response_class=HTMLResponse)
async def admin_bookings(
    request: Request,
    page: int = 1,
    start: str = "",
    end: str = "",
    status: str = "all",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from sqlalchemy import and_

    limit = 50
    offset = (page - 1) * limit

    # Build query base. Rides exclude both parcel services (flash + courier),
    # each of which has its own admin page.
    base_where = [Booking.is_flash == False, Booking.is_courier == False]

    # Parse dates
    start_dt = None
    end_dt = None
    if start:
        try:
            start_dt = datetime.strptime(start.strip(), "%Y-%m-%d").replace(tzinfo=timezone.utc, hour=0, minute=0, second=0, microsecond=0)
            base_where.append(Booking.booked_at >= start_dt)
        except ValueError:
            pass
    if end:
        try:
            end_dt = datetime.strptime(end.strip(), "%Y-%m-%d").replace(tzinfo=timezone.utc, hour=23, minute=59, second=59, microsecond=0)
            base_where.append(Booking.booked_at <= end_dt)
        except ValueError:
            pass

    # Active bookings (not paginated, needed for live map tracking)
    active_statuses = [
        BookingStatus.SEARCHING,
        BookingStatus.ACCEPTED,
        BookingStatus.ARRIVED,
        BookingStatus.STARTED,
    ]
    active_q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.driver).selectinload(Driver.user),
        )
        .where(
            Booking.is_flash == False,
            Booking.is_courier == False,
            Booking.status.in_(active_statuses),
        )
        .order_by(desc(Booking.id))
    )
    active_bookings = active_q.scalars().all()

    # KPI summary stats (calculated based on date filters)
    stats_q = await db.execute(
        select(
            func.count(Booking.id),
            func.count(Booking.id).filter(Booking.status == BookingStatus.COMPLETED),
            func.count(Booking.id).filter(Booking.status == BookingStatus.CANCELLED),
            func.coalesce(func.sum(Booking.final_amount).filter(Booking.status == BookingStatus.COMPLETED), 0),
        )
        .where(and_(*base_where))
    )
    stat_total, stat_completed, stat_cancelled, stat_revenue = stats_q.one()

    # Table query conditions (base + optional status filter)
    table_where = list(base_where)
    if status and status != "all":
        table_where.append(Booking.status == status)

    # Total count of filtered bookings
    total_q = await db.execute(
        select(func.count(Booking.id)).where(and_(*table_where))
    )
    total_bookings = total_q.scalar() or 0
    total_pages = (total_bookings + limit - 1) // limit

    # Paginated bookings for the table
    q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.driver).selectinload(Driver.user),
        )
        .where(and_(*table_where))
        .order_by(desc(Booking.id))
        .offset(offset)
        .limit(limit)
    )
    bookings = q.scalars().all()

    start_idx = (page - 1) * limit + 1 if total_bookings > 0 else 0
    end_idx = min(page * limit, total_bookings)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "bookings.html",
        {
            "request": request,
            "active_page": "bookings",
            "bookings": bookings,
            "active_bookings": active_bookings,
            "page": page,
            "total_pages": total_pages,
            "total_bookings": total_bookings,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "start_date": start,
            "end_date": end,
            "status": status,
            "stat_total": stat_total,
            "stat_completed": stat_completed,
            "stat_cancelled": stat_cancelled,
            "stat_revenue": float(stat_revenue),
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY or "",
        },
    )



@router.get("/notifications", response_class=HTMLResponse)
async def admin_notifications(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Notification
    limit = 50
    offset = (page - 1) * limit

    # Total count of notifications
    total_q = await db.execute(select(func.count(Notification.id)))
    total_notifications = total_q.scalar() or 0
    total_pages = (total_notifications + limit - 1) // limit

    # Paginated notifications
    q = await db.execute(
        select(Notification)
        .options(selectinload(Notification.user))
        .order_by(desc(Notification.created_at))
        .offset(offset)
        .limit(limit)
    )
    notifications = q.scalars().all()

    # Unread count (global)
    unread_q = await db.execute(
        select(func.count(Notification.id)).where(Notification.is_read == False)
    )
    unread_count = unread_q.scalar() or 0

    # Group counts by type (global)
    type_q = await db.execute(
        select(Notification.type, func.count(Notification.id)).group_by(Notification.type)
    )
    by_type = {row[0] or "other": row[1] for row in type_q.all()}

    start_idx = (page - 1) * limit + 1 if total_notifications > 0 else 0
    end_idx = min(page * limit, total_notifications)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "notifications.html",
        {
            "request": request,
            "active_page": "notifications",
            "notifications": notifications,
            "unread_count": unread_count,
            "by_type": by_type,
            "page": page,
            "total_pages": total_pages,
            "total_notifications": total_notifications,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )




@router.get("/payments", response_class=HTMLResponse)
async def admin_payments(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Payment, Booking, Customer
    from decimal import Decimal

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(Payment.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Payment)
        .options(
            selectinload(Payment.booking)
            .selectinload(Booking.customer)
            .selectinload(Customer.user)
        )
        .order_by(Payment.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    payments = q.scalars().all()

    total_q = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0)).where(Payment.status == "completed")
    )
    total_val = total_q.scalar() or Decimal("0")

    cash_q = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0)).where(Payment.status == "completed", Payment.payment_method == "cash")
    )
    cash_val = cash_q.scalar() or Decimal("0")

    card_q = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0)).where(Payment.status == "completed", Payment.payment_method == "card")
    )
    card_val = card_q.scalar() or Decimal("0")

    wallet_q = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), 0)).where(Payment.status == "completed", Payment.payment_method == "wallet")
    )
    wallet_val = wallet_q.scalar() or Decimal("0")

    totals = {
        "total": float(total_val),
        "cash": float(cash_val),
        "card": float(card_val),
        "wallet": float(wallet_val),
    }

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "payments.html",
        {
            "request": request,
            "active_page": "payments",
            "payments": payments,
            "totals": totals,
            "page": page,
            "total_pages": total_pages,
            "total_payments": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



@router.get("/topups", response_class=HTMLResponse)
async def admin_topups(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import WalletTransaction, WalletTopupRequest
    from decimal import Decimal

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(WalletTransaction.id)).where(WalletTransaction.type == "credit"))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(WalletTransaction)
        .options(selectinload(WalletTransaction.user))
        .where(WalletTransaction.type == "credit")
        .order_by(WalletTransaction.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    topups = q.scalars().all()

    total_q = await db.execute(
        select(func.coalesce(func.sum(WalletTransaction.amount), 0)).where(WalletTransaction.type == "credit")
    )
    total_val = total_q.scalar() or Decimal("0")

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    req_q = await db.execute(
        select(WalletTopupRequest)
        .options(selectinload(WalletTopupRequest.user))
        .where(WalletTopupRequest.status == "pending")
        .order_by(WalletTopupRequest.created_at.asc())
    )
    pending_requests = req_q.scalars().all()

    items = []
    for r in pending_requests:
        items.append({
            "type": "request",
            "date": r.created_at,
            "user": r.user,
            "amount": float(r.amount),
            "status": r.status,
            "note": r.note,
            "id": r.id
        })
    for t in topups:
        items.append({
            "type": "transaction",
            "date": t.created_at,
            "user": t.user,
            "amount": float(t.amount),
            "balance_after": float(t.balance_after) if t.balance_after else None,
            "reference": t.reference_id,
            "note": t.description,
        })
    
    # Sort them descending by date
    items.sort(key=lambda x: x["date"].timestamp() if x["date"] else 0, reverse=True)

    return templates.TemplateResponse(
        request, "topups.html",
        {
            "request": request,
            "active_page": "topups",
            "items": items,
            "total": float(total_val),
            "count": total,
            "page": page,
            "total_pages": total_pages,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



@router.post("/topups/manual")
async def admin_topups_manual(
    user_phone: str = Form(...),
    amount: float = Form(...),
    note: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import User, WalletTransaction, Customer
    from decimal import Decimal

    user_q = await db.execute(select(User).where(User.phone_number == user_phone))
    u = user_q.scalars().first()
    if not u:
        raise HTTPException(status_code=404, detail="User not found")

    cust_q = await db.execute(select(Customer).where(Customer.user_id == u.id))
    c = cust_q.scalars().first()
    new_balance = Decimal("0")
    if c:
        c.wallet_balance = (c.wallet_balance or Decimal("0")) + Decimal(str(amount))
        new_balance = c.wallet_balance

    db.add(
        WalletTransaction(
            user_id=u.id,
            amount=Decimal(str(amount)),
            type="credit",
            description=note or "Manual top-up",
            reference_id="MANUAL",
            balance_after=new_balance,
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/topups", status_code=303)


@router.post("/topups/requests/{id}/approve")
async def admin_topups_approve(
    id: int,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    from app.models import WalletTopupRequest, Customer, WalletTransaction, Notification
    from decimal import Decimal

    q = await db.execute(select(WalletTopupRequest).options(selectinload(WalletTopupRequest.user)).where(WalletTopupRequest.id == id))
    req = q.scalars().first()
    if not req or req.status != "pending":
        raise HTTPException(status_code=404, detail="Request not found or not pending")

    req.status = "approved"
    req.approved_by_id = admin.id

    cust_q = await db.execute(select(Customer).where(Customer.user_id == req.user_id))
    c = cust_q.scalars().first()
    new_balance = Decimal("0")
    if c:
        c.wallet_balance = (c.wallet_balance or Decimal("0")) + req.amount
        new_balance = c.wallet_balance

    db.add(
        WalletTransaction(
            user_id=req.user_id,
            amount=req.amount,
            type="credit",
            description=req.note or "Wallet top-up (Approved)",
            reference_id="TOPUP_REQ",
            balance_after=new_balance,
        )
    )

    db.add(
        Notification(
            user_id=req.user_id,
            title="Top-up Approved",
            body=f"Your top-up request for Rs.{req.amount:,.2f} has been approved.",
            type="payment",
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/topups", status_code=303)


@router.post("/topups/requests/{id}/reject")
async def admin_topups_reject(
    id: int,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    from app.models import WalletTopupRequest, Notification

    q = await db.execute(select(WalletTopupRequest).where(WalletTopupRequest.id == id))
    req = q.scalars().first()
    if not req or req.status != "pending":
        raise HTTPException(status_code=404, detail="Request not found or not pending")

    req.status = "rejected"
    req.approved_by_id = admin.id

    db.add(
        Notification(
            user_id=req.user_id,
            title="Top-up Rejected",
            body=f"Your top-up request for Rs.{req.amount:,.2f} has been rejected.",
            type="payment",
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/topups", status_code=303)


@router.get("/flash", response_class=HTMLResponse)
async def admin_flash(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from datetime import timedelta  # noqa: F401 (kept for parity with dashboard)

    limit = 50
    offset = (page - 1) * limit

    total = (
        await db.execute(select(func.count(Booking.id)).where(Booking.is_flash == True))  # noqa: E712
    ).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.driver).selectinload(Driver.user),
        )
        .where(Booking.is_flash == True)  # noqa: E712
        .order_by(desc(Booking.id))
        .offset(offset)
        .limit(limit)
    )
    orders = q.scalars().all()

    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    
    # Active orders (not paginated, needed for live dashboard stats)
    active_q = await db.execute(
        select(func.count(Booking.id)).where(
            Booking.is_flash == True,  # noqa: E712
            Booking.status.in_([
                BookingStatus.SEARCHING,
                BookingStatus.ACCEPTED,
                BookingStatus.ARRIVED,
                BookingStatus.STARTED,
            ])
        )
    )
    active_count = active_q.scalar() or 0

    delivered_today = (
        await db.execute(
            select(func.count(Booking.id)).where(
                Booking.is_flash == True,  # noqa: E712
                Booking.status == BookingStatus.COMPLETED,
                Booking.completed_at >= today,
            )
        )
    ).scalar() or 0
    revenue = (
        await db.execute(
            select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
                Booking.is_flash == True,  # noqa: E712
                Booking.status == BookingStatus.COMPLETED,
            )
        )
    ).scalar() or 0

    stats = {
        "total": int(total),
        "active": active_count,
        "delivered_today": int(delivered_today),
        "revenue": float(revenue),
    }

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "flash.html",
        {
            "request": request,
            "active_page": "flash",
            "orders": orders,
            "stats": stats,
            "page": page,
            "total_pages": total_pages,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


@router.get("/courier", response_class=HTMLResponse)
async def admin_courier(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Island-wide courier (2-3 day, weight-priced) parcel deliveries.

    Mirrors /admin/flash but filters on is_courier instead of is_flash.
    """
    limit = 50
    offset = (page - 1) * limit

    total = (
        await db.execute(select(func.count(Booking.id)).where(Booking.is_courier == True))  # noqa: E712
    ).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.driver).selectinload(Driver.user),
        )
        .where(Booking.is_courier == True)  # noqa: E712
        .order_by(desc(Booking.id))
        .offset(offset)
        .limit(limit)
    )
    orders = q.scalars().all()

    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    active_count = (
        await db.execute(
            select(func.count(Booking.id)).where(
                Booking.is_courier == True,  # noqa: E712
                Booking.status.in_([
                    BookingStatus.SEARCHING,
                    BookingStatus.ACCEPTED,
                    BookingStatus.ARRIVED,
                    BookingStatus.STARTED,
                ]),
            )
        )
    ).scalar() or 0

    delivered_today = (
        await db.execute(
            select(func.count(Booking.id)).where(
                Booking.is_courier == True,  # noqa: E712
                Booking.status == BookingStatus.COMPLETED,
                Booking.completed_at >= today,
            )
        )
    ).scalar() or 0
    revenue = (
        await db.execute(
            select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
                Booking.is_courier == True,  # noqa: E712
                Booking.status == BookingStatus.COMPLETED,
            )
        )
    ).scalar() or 0

    stats = {
        "total": int(total),
        "active": active_count,
        "delivered_today": int(delivered_today),
        "revenue": float(revenue),
    }

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    from app.models import FareSetting
    setting_q = await db.execute(select(FareSetting).where(FareSetting.service_type == "courier"))
    setting = setting_q.scalars().first()
    courier_base = float(setting.base_fare) if setting and setting.base_fare is not None else 250.0
    courier_per_km = float(setting.per_km_rate) if setting and setting.per_km_rate is not None else 6.0
    courier_commission = float(setting.platform_fee_percent) if setting and setting.platform_fee_percent is not None else 15.0

    return templates.TemplateResponse(
        request, "courier.html",
        {
            "request": request,
            "active_page": "courier",
            "orders": orders,
            "stats": stats,
            "page": page,
            "total_pages": total_pages,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "courier_base": courier_base,
            "courier_per_km": courier_per_km,
            "courier_commission": courier_commission,
        },
    )

@router.post("/courier/settings")
async def admin_courier_settings_update(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting
    form = await request.form()
    base_fare = float(form.get("base_fare", 250.0))
    per_km_rate = float(form.get("per_km_rate", 6.0))
    platform_fee_percent = float(form.get("platform_fee_percent", 15.0))

    setting_q = await db.execute(select(FareSetting).where(FareSetting.service_type == "courier"))
    setting = setting_q.scalars().first()
    
    if not setting:
        setting = FareSetting(
            service_type="courier",
            display_name="Courier",
            is_active=True,
            base_fare=base_fare,
            per_km_rate=per_km_rate,
            platform_fee_percent=platform_fee_percent,
        )
        db.add(setting)
    else:
        setting.base_fare = base_fare
        setting.per_km_rate = per_km_rate
        setting.platform_fee_percent = platform_fee_percent
        
    await db.commit()
    return RedirectResponse(url="/admin/courier", status_code=303)


@router.get("/fare-settings", response_class=HTMLResponse)
async def admin_fare_settings(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_superadmin),
):
    from app.models import FareSetting

    q = await db.execute(select(FareSetting).order_by(FareSetting.display_order, FareSetting.id))
    return templates.TemplateResponse(
        request, "settings.html",
        {"request": request, "active_page": "fare-settings", "fares": q.scalars().all()},
    )


@router.post("/fare-settings/update")
async def admin_fare_settings_update(
    id: int = Form(...),
    base_fare: float = Form(...),
    per_km_rate: float = Form(...),
    per_minute_rate: float = Form(...),
    min_fare: float = Form(...),
    platform_fee_percent: float = Form(...),
    surge_multiplier: float = Form(...),
    pickup_fee: float = Form(0),
    boost: float = Form(0),
    passenger_deductible: float = Form(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_superadmin),
):
    from app.models import FareSetting
    from decimal import Decimal

    q = await db.execute(select(FareSetting).where(FareSetting.id == id))
    f = q.scalars().first()
    if f:
        f.base_fare = Decimal(str(base_fare))
        f.per_km_rate = Decimal(str(per_km_rate))
        f.per_minute_rate = Decimal(str(per_minute_rate))
        f.min_fare = Decimal(str(min_fare))
        f.platform_fee_percent = Decimal(str(platform_fee_percent))
        f.surge_multiplier = Decimal(str(surge_multiplier))
        f.pickup_fee = Decimal(str(pickup_fee))
        f.boost = Decimal(str(boost))
        f.passenger_deductible = Decimal(str(passenger_deductible))
        await db.commit()
    return RedirectResponse(url="/admin/fare-settings", status_code=303)


# ---------- System settings (admin → Settings) ----------
async def _get_or_create_settings(db: AsyncSession):
    from app.models import SystemSettings

    q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    s = q.scalars().first()
    if not s:
        s = SystemSettings(id=1)
        db.add(s)
        await db.commit()
        await db.refresh(s)
    return s


@router.get("/branding-assets")
async def admin_branding_assets(db: AsyncSession = Depends(get_db)):
    s = await _get_or_create_settings(db)
    return {
        "logo_url": s.logo_url or "/static/img/logo.jpeg",
        "favicon_url": s.favicon_url or "/static/img/logo.jpeg",
        "site_name": s.site_name or "Ziggo",
        "admin_email": s.admin_email or "admin@ziggo.com",
    }


@router.get("/settings", response_class=HTMLResponse)
async def admin_settings_get(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_superadmin),
):
    from app.models import DriverIncentive, PeakHourSetting
    s = await _get_or_create_settings(db)
    q = await db.execute(select(DriverIncentive).order_by(DriverIncentive.trips_required))
    incentives = q.scalars().all()
    peaks_q = await db.execute(select(PeakHourSetting).order_by(PeakHourSetting.id))
    peaks = peaks_q.scalars().all()
    return templates.TemplateResponse(
        request,
        "admin_settings.html",
        {
            "request": request,
            "active_page": "settings",
            "s": s,
            "incentives": incentives,
            "peaks": peaks,
            "saved": request.query_params.get("saved") == "1",
            "error": request.query_params.get("error"),
        },
    )



@router.post("/settings")
async def admin_settings_save(
    # General
    site_name: str = Form(""),
    admin_email: str = Form(""),
    contact_phone: str = Form(""),
    contact_email: str = Form(""),
    address: str = Form(""),
    # Pricing
    commission_rate: float = Form(15),
    max_settle_amount: float = Form(1000.0),
    driver_search_radius_km: int = Form(15),
    surge_start_hour: int = Form(17),
    surge_end_hour: int = Form(20),
    surge_multiplier: float = Form(1.5),
    cancellation_fee: float = Form(0),
    cancellation_grace_period_minutes: int = Form(3),
    rider_penalty: float = Form(0),
    # Security
    min_password_length: int = Form(6),
    session_timeout_minutes: int = Form(30),
    max_login_attempts: int = Form(5),
    password_reset_option: str = Form("email"),
    # Notifications (HTML checkboxes only submit when checked)
    email_notifications_enabled: str = Form(""),
    sms_notifications_enabled: str = Form(""),
    push_notifications_enabled: str = Form(""),
    # Driver incentives
    min_rides_daily_bonus: int = Form(15),
    daily_bonus_amount: float = Form(1000),
    commission_cycle_rides: int = Form(5),
    commission_per_cycle: float = Form(500),
    # Loyalty + membership (BRD: AD-13)
    loyalty_earn_rupees_per_point: float = Form(10),
    loyalty_value_per_point: float = Form(0.50),
    loyalty_min_redeem_points: int = Form(100),
    loyalty_max_redeem_order_pct: float = Form(20),
    gold_delivery_discount_pct: float = Form(50),
    # Multi-stop trips (BRD: CD-19 / BE-16 / BR-9)
    multi_stop_max_count: int = Form(2),
    multi_stop_free_minutes: int = Form(3),
    multi_stop_excess_per_minute: float = Form(5),
    multi_stop_fee_per_stop: float = Form(50),
    # Peak Hours
    peak_start_hour_1: str = Form("07:00"),
    peak_end_hour_1: str = Form("09:00"),
    peak_extra_amount_1: float = Form(50.00),
    peak_start_hour_2: str = Form("09:00"),
    peak_end_hour_2: str = Form("11:00"),
    peak_extra_amount_2: float = Form(50.00),
    peak_start_hour_3: str = Form("12:00"),
    peak_end_hour_3: str = Form("14:00"),
    peak_extra_amount_3: float = Form(50.00),
    peak_start_hour_4: str = Form("16:00"),
    peak_end_hour_4: str = Form("18:00"),
    peak_extra_amount_4: float = Form(50.00),
    peak_start_hour_5: str = Form("18:00"),
    peak_end_hour_5: str = Form("20:00"),
    peak_extra_amount_5: float = Form(50.00),
    peak_start_hour_6: str = Form("21:00"),
    peak_end_hour_6: str = Form("23:00"),
    peak_extra_amount_6: float = Form(50.00),
    # Branding
    logo: UploadFile | None = File(None),
    favicon: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_superadmin),
):
    from decimal import Decimal

    s = await _get_or_create_settings(db)
    s.site_name = site_name.strip() or "Ziggo"
    s.admin_email = admin_email.strip()
    
    cleaned_phone = contact_phone.strip()
    if cleaned_phone:
        import re
        if not re.match(r"^\d{10}$", cleaned_phone):
            import urllib.parse
            err_msg = "Contact phone must be a 10-digit login phone number (e.g. 0773095788)"
            return RedirectResponse(url=f"/admin/settings?error={urllib.parse.quote(err_msg)}", status_code=303)
        
        # Check if another user already has this phone number
        q_dup = await db.execute(select(User).where(User.phone_number == cleaned_phone, User.id != admin.id))
        dup_user = q_dup.scalars().first()
        if dup_user:
            import urllib.parse
            err_msg = f"Phone number {cleaned_phone} is already registered under another account (role: {dup_user.role.value}). Please use a different phone number."
            return RedirectResponse(url=f"/admin/settings?error={urllib.parse.quote(err_msg)}", status_code=303)
        
        # Update admin's login phone number
        admin.phone_number = cleaned_phone
    s.contact_phone = cleaned_phone
    s.contact_email = contact_email.strip()
    s.address = address.strip()
    s.commission_rate = Decimal(str(commission_rate))
    s.max_settle_amount = Decimal(str(max_settle_amount))
    s.driver_search_radius_km = max(1, int(driver_search_radius_km))
    s.surge_start_hour = max(0, min(23, int(surge_start_hour)))
    s.surge_end_hour = max(0, min(23, int(surge_end_hour)))
    s.surge_multiplier = Decimal(str(surge_multiplier))
    s.cancellation_fee = Decimal(str(cancellation_fee))
    s.cancellation_grace_period_minutes = max(0, int(cancellation_grace_period_minutes))
    s.rider_penalty = Decimal(str(rider_penalty))
    s.min_password_length = max(1, int(min_password_length))
    s.session_timeout_minutes = max(1, int(session_timeout_minutes))
    s.max_login_attempts = max(1, int(max_login_attempts))
    s.password_reset_option = password_reset_option
    s.email_notifications_enabled = email_notifications_enabled == "on"
    s.sms_notifications_enabled = sms_notifications_enabled == "on"
    s.push_notifications_enabled = push_notifications_enabled == "on"
    s.min_rides_daily_bonus = max(0, int(min_rides_daily_bonus))
    s.daily_bonus_amount = Decimal(str(daily_bonus_amount))
    s.commission_cycle_rides = max(0, int(commission_cycle_rides))
    s.commission_per_cycle = Decimal(str(commission_per_cycle))
    # BRD: AD-13 — loyalty + Gold settings
    s.loyalty_earn_rupees_per_point = Decimal(str(loyalty_earn_rupees_per_point))
    s.loyalty_value_per_point = Decimal(str(loyalty_value_per_point))
    s.loyalty_min_redeem_points = max(1, int(loyalty_min_redeem_points))
    s.loyalty_max_redeem_order_pct = Decimal(str(loyalty_max_redeem_order_pct))
    s.gold_delivery_discount_pct = Decimal(str(gold_delivery_discount_pct))
    # BRD: CD-19 — multi-stop policy
    s.multi_stop_max_count = max(0, min(5, int(multi_stop_max_count)))
    s.multi_stop_free_minutes = max(0, int(multi_stop_free_minutes))
    s.multi_stop_excess_per_minute = Decimal(str(multi_stop_excess_per_minute))
    s.multi_stop_fee_per_stop = Decimal(str(multi_stop_fee_per_stop))

    # Peak Hours saving
    from app.models import PeakHourSetting
    peaks_q = await db.execute(select(PeakHourSetting).order_by(PeakHourSetting.id))
    peaks = peaks_q.scalars().all()
    form_peaks = [
        (peak_start_hour_1, peak_end_hour_1, peak_extra_amount_1),
        (peak_start_hour_2, peak_end_hour_2, peak_extra_amount_2),
        (peak_start_hour_3, peak_end_hour_3, peak_extra_amount_3),
        (peak_start_hour_4, peak_end_hour_4, peak_extra_amount_4),
        (peak_start_hour_5, peak_end_hour_5, peak_extra_amount_5),
        (peak_start_hour_6, peak_end_hour_6, peak_extra_amount_6),
    ]
    peak_changed = False
    for idx, (sh, eh, amt) in enumerate(form_peaks):
        if idx < len(peaks):
            import re
            time_pat = re.compile(r"^\d{2}:\d{2}$")
            
            clean_sh = sh.strip() if isinstance(sh, str) else "09:00"
            clean_eh = eh.strip() if isinstance(eh, str) else "11:00"
            
            if not time_pat.match(clean_sh):
                try:
                    clean_sh = f"{int(clean_sh):02d}:00"
                except:
                    clean_sh = "09:00"
            if not time_pat.match(clean_eh):
                try:
                    clean_eh = f"{int(clean_eh):02d}:00"
                except:
                    clean_eh = "11:00"
                    
            try:
                new_sh = int(clean_sh.split(":")[0])
            except:
                new_sh = 9
            try:
                new_eh = int(clean_eh.split(":")[0])
            except:
                new_eh = 11

            new_amt = Decimal(str(amt))
            if (peaks[idx].start_time != clean_sh or 
                peaks[idx].end_time != clean_eh or 
                peaks[idx].extra_amount != new_amt):
                peak_changed = True
            
            peaks[idx].start_time = clean_sh
            peaks[idx].end_time = clean_eh
            peaks[idx].start_hour = new_sh
            peaks[idx].end_hour = new_eh
            peaks[idx].extra_amount = new_amt

    peak_active = any(p.is_active for p in peaks)
    if len(peaks) > 0:
        s.peak_is_active = peak_active
        s.peak_start_hour = peaks[0].start_hour
        s.peak_end_hour = peaks[0].end_hour
        s.peak_extra_amount = peaks[0].extra_amount

    # Notify drivers if peak hours are active and configuration changed
    if peak_active and peak_changed:
        from app.models import Driver
        drivers_q = await db.execute(select(Driver.user_id))
        driver_user_ids = [row[0] for row in drivers_q.all()]
        title = "Peak Hours Surcharge Active!"
        body = f"Get ready! Peak hours settings have been updated. Extra surcharges will apply during peak hours."
        
        # Save system notifications
        from app.models import Notification
        for uid in driver_user_ids:
            db.add(Notification(
                user_id=uid,
                title=title,
                body=body,
                type="system",
                data="{}"
            ))
        
        # Push notifications in background
        from app.services import fcm_service
        async def send_pushes():
            from app.database import AsyncSessionLocal
            async with AsyncSessionLocal() as push_db:
                await fcm_service.send_to_users(push_db, driver_user_ids, title, body, {"event": "peak_hours_active"})
        import asyncio
        asyncio.create_task(send_pushes())


    new_logo = await _save_branding_asset(logo, "Logo")
    if new_logo:
        s.logo_url = new_logo
    new_favicon = await _save_branding_asset(favicon, "Favicon")
    if new_favicon:
        s.favicon_url = new_favicon

    await db.commit()
    return RedirectResponse(url="/admin/settings?tab=pricing&saved=1", status_code=303)


@router.post("/settings/peak-hours/{id}/toggle")
async def admin_peak_hours_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_superadmin),
):
    from app.models import PeakHourSetting
    q = await db.execute(select(PeakHourSetting).where(PeakHourSetting.id == id))
    p = q.scalars().first()
    if not p:
        raise HTTPException(status_code=404, detail="Peak hour setting not found")
    p.is_active = not bool(p.is_active)
    await db.commit()
    return RedirectResponse(url="/admin/settings?tab=pricing&saved=1", status_code=303)



# ---------- Vehicle categories ----------
@router.get("/categories", response_class=HTMLResponse)
async def admin_categories(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting, Driver

    q = await db.execute(select(FareSetting).order_by(FareSetting.display_order, FareSetting.id))
    categories = q.scalars().all()
    # Per-category driver count, so admin sees impact before deleting
    counts_q = await db.execute(
        select(Driver.vehicle_type, func.count(Driver.id)).group_by(Driver.vehicle_type)
    )
    driver_counts = {vt: n for vt, n in counts_q.all()}
    return templates.TemplateResponse(
        request,
        "categories.html",
        {
            "request": request,
            "active_page": "categories",
            "categories": categories,
            "driver_counts": driver_counts,
        },
    )


def _safe_admin_next(next_url: str, default: str) -> str:
    """Only honor next= when it points back inside /admin/ — avoids open-redirects."""
    if next_url and next_url.startswith("/admin/"):
        return next_url
    return default



@router.post("/categories/new")
async def admin_categories_new(
    service_type: str = Form(...),
    display_name: str = Form(...),
    capacity: int = Form(0),
    description: str = Form(""),
    base_fare: float = Form(0),
    per_km_rate: float = Form(0),
    per_minute_rate: float = Form(0),
    min_fare: float = Form(0),
    platform_fee_percent: float = Form(15),
    surge_multiplier: float = Form(1.0),
    pickup_fee: float = Form(0),
    boost: float = Form(0),
    passenger_deductible: float = Form(0),
    promo_message: str = Form(""),
    discount_percentage: float = Form(0),
    search_radius_km: int | None = Form(None),
    is_active: str = Form("on"),
    is_truck: str = Form("off"),
    rental_hourly_rate: float | None = Form(None),
    image: UploadFile | None = File(None),
    preset_icon: str | None = Form(None),
    next: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting
    from decimal import Decimal

    key = service_type.strip().lower()
    if not key:
        raise HTTPException(status_code=400, detail="Service type is required")
    dup = await db.execute(select(FareSetting).where(FareSetting.service_type == key))
    if dup.scalars().first():
        raise HTTPException(status_code=400, detail=f"Category '{key}' already exists")

    if preset_icon:
        image_url = preset_icon
    else:
        image_url = await _save_category_image(image)

    max_order_q = await db.execute(select(func.max(FareSetting.display_order)))
    max_order = max_order_q.scalar() or 0

    db.add(
        FareSetting(
            service_type=key,
            display_name=display_name.strip() or key.title(),
            image_url=image_url,
            capacity=int(capacity or 0),
            description=description.strip() or None,
            promo_message=promo_message.strip() or None,
            discount_percentage=Decimal(str(discount_percentage)),
            is_active=(is_active == "on"),
            is_truck=(is_truck == "on"),
            base_fare=Decimal(str(base_fare)),
            per_km_rate=Decimal(str(per_km_rate)),
            per_minute_rate=Decimal(str(per_minute_rate)),
            min_fare=Decimal(str(min_fare)),
            platform_fee_percent=Decimal(str(platform_fee_percent)),
            surge_multiplier=Decimal(str(surge_multiplier)),
            pickup_fee=Decimal(str(pickup_fee)),
            boost=Decimal(str(boost)),
            passenger_deductible=Decimal(str(passenger_deductible)),
            search_radius_km=search_radius_km,
            rental_hourly_rate=Decimal(str(rental_hourly_rate)) if rental_hourly_rate is not None else None,
            display_order=max_order + 1,
        )
    )
    await db.commit()
    return RedirectResponse(url=_safe_admin_next(next, "/admin/categories"), status_code=303)


@router.post("/categories/{id}/edit")
async def admin_categories_edit(
    id: int,
    display_name: str = Form(...),
    capacity: int = Form(0),
    description: str = Form(""),
    base_fare: float = Form(0),
    per_km_rate: float = Form(0),
    per_minute_rate: float = Form(0),
    min_fare: float = Form(0),
    platform_fee_percent: float = Form(15),
    surge_multiplier: float = Form(1.0),
    pickup_fee: float = Form(0),
    boost: float = Form(0),
    passenger_deductible: float = Form(0),
    promo_message: str = Form(""),
    discount_percentage: float = Form(0),
    search_radius_km: int | None = Form(None),
    is_active: str = Form(""),
    is_truck: str = Form("off"),
    rental_hourly_rate: float | None = Form(None),
    image: UploadFile | None = File(None),
    preset_icon: str | None = Form(None),
    next: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting
    from decimal import Decimal

    q = await db.execute(select(FareSetting).where(FareSetting.id == id))
    f = q.scalars().first()
    if not f:
        raise HTTPException(status_code=404, detail="Category not found")
    f.display_name = display_name.strip() or f.service_type.title()
    f.capacity = int(capacity or 0)
    f.description = description.strip() or None
    f.promo_message = promo_message.strip() or None
    f.discount_percentage = Decimal(str(discount_percentage))
    f.is_active = (is_active == "on")
    f.is_truck = (is_truck == "on")
    f.base_fare = Decimal(str(base_fare))
    f.per_km_rate = Decimal(str(per_km_rate))
    f.per_minute_rate = Decimal(str(per_minute_rate))
    f.min_fare = Decimal(str(min_fare))
    f.platform_fee_percent = Decimal(str(platform_fee_percent))
    f.surge_multiplier = Decimal(str(surge_multiplier))
    f.pickup_fee = Decimal(str(pickup_fee))
    f.boost = Decimal(str(boost))
    f.passenger_deductible = Decimal(str(passenger_deductible))
    f.search_radius_km = search_radius_km
    f.rental_hourly_rate = Decimal(str(rental_hourly_rate)) if rental_hourly_rate is not None else None

    if preset_icon:
        f.image_url = preset_icon
    else:
        new_image = await _save_category_image(image)
        if new_image:
            f.image_url = new_image

    await db.commit()
    return RedirectResponse(url=_safe_admin_next(next, "/admin/categories"), status_code=303)


@router.post("/categories/{id}/delete")
async def admin_categories_delete(
    id: int,
    next: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting, Driver, Booking

    q = await db.execute(select(FareSetting).where(FareSetting.id == id))
    f = q.scalars().first()
    if not f:
        raise HTTPException(status_code=404, detail="Category not found")

    # Guard: refuse delete if drivers or bookings reference this vehicle_type.
    # The admin can deactivate instead.
    drv_count = await db.execute(
        select(func.count(Driver.id)).where(Driver.vehicle_type == f.service_type)
    )
    if drv_count.scalar_one() > 0:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete '{f.display_name or f.service_type}': drivers are assigned to this category. Deactivate it instead.",
        )
    bk_count = await db.execute(
        select(func.count(Booking.id)).where(Booking.service_type == f.service_type)
    )
    if bk_count.scalar_one() > 0:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete '{f.display_name or f.service_type}': bookings reference this category. Deactivate it instead.",
        )

    await db.delete(f)
    await db.commit()
    return RedirectResponse(url=_safe_admin_next(next, "/admin/categories"), status_code=303)


from pydantic import BaseModel


class ReorderCategoriesRequest(BaseModel):
    order: list[int]


@router.post("/categories/reorder")
async def admin_categories_reorder(
    payload: ReorderCategoriesRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting
    for index, category_id in enumerate(payload.order):
        q = await db.execute(select(FareSetting).where(FareSetting.id == category_id))
        f = q.scalars().first()
        if f:
            f.display_order = index
    await db.commit()
    return {"status": "success"}


# ---------- Services (table view of vehicle categories) ----------
@router.get("/services", response_class=HTMLResponse)
async def admin_services(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting

    q = await db.execute(select(FareSetting).order_by(FareSetting.display_order, FareSetting.id))
    categories = q.scalars().all()
    counts_q = await db.execute(
        select(Driver.vehicle_type, func.count(Driver.id)).group_by(Driver.vehicle_type)
    )
    driver_counts = {vt: n for vt, n in counts_q.all()}
    return templates.TemplateResponse(
        request,
        "services.html",
        {
            "request": request,
            "active_page": "services",
            "categories": categories,
            "driver_counts": driver_counts,
        },
    )


@router.post("/services/{id}/toggle")
async def admin_services_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting

    q = await db.execute(select(FareSetting).where(FareSetting.id == id))
    f = q.scalars().first()
    if not f:
        raise HTTPException(status_code=404, detail="Service not found")
    f.is_active = not bool(f.is_active)
    await db.commit()
    return RedirectResponse(url="/admin/services", status_code=303)


# ---------- Vehicles ----------
@router.get("/vehicles", response_class=HTMLResponse)
async def admin_vehicles(
    request: Request,
    page: int = 1,
    status: str = "",
    category: str = "",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FareSetting

    limit = 50
    offset = (page - 1) * limit

    q = select(Driver).options(selectinload(Driver.user)).order_by(Driver.id)
    count_q = select(func.count(Driver.id))

    if status:
        try:
            q = q.where(Driver.status == DriverStatus(status))
            count_q = count_q.where(Driver.status == DriverStatus(status))
        except ValueError:
            pass
    if category:
        q = q.where(Driver.vehicle_type == category)
        count_q = count_q.where(Driver.vehicle_type == category)

    total_filtered = (await db.execute(count_q)).scalar() or 0
    total_pages = (total_filtered + limit - 1) // limit

    q = q.offset(offset).limit(limit)
    result = await db.execute(q)
    vehicles = result.scalars().all()

    # Totals are unfiltered (the stat cards always show overall numbers).
    totals_q = await db.execute(select(Driver.status, func.count(Driver.id)).group_by(Driver.status))
    by_status = {s.value: n for s, n in totals_q.all()}
    total_vehicles = sum(by_status.values())
    pending = by_status.get(DriverStatus.PENDING.value, 0)
    verified = by_status.get(DriverStatus.APPROVED.value, 0)

    cats_q = await db.execute(
        select(FareSetting).where(FareSetting.is_active == True).order_by(FareSetting.display_order, FareSetting.id)  # noqa: E712
    )
    categories = cats_q.scalars().all()

    start_idx = (page - 1) * limit + 1 if total_filtered > 0 else 0
    end_idx = min(page * limit, total_filtered)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request,
        "vehicles.html",
        {
            "request": request,
            "active_page": "vehicles",
            "vehicles": vehicles,
            "categories": categories,
            "total_vehicles": total_vehicles,
            "pending_count": pending,
            "verified_count": verified,
            "category_count": len(categories),
            "filter_status": status,
            "filter_category": category,
            "statuses": [s.value for s in DriverStatus],
            "page": page,
            "total_pages": total_pages,
            "total_filtered": total_filtered,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



@router.post("/vehicles/{driver_id}/edit")
async def admin_vehicles_edit(
    driver_id: int,
    vehicle_type: str = Form(...),
    vehicle_number: str = Form(""),
    vehicle_model: str = Form(""),
    vehicle_color: str = Form(""),
    vehicle_year: str = Form(""),
    photo: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    # Plate uniqueness if changed
    plate = (vehicle_number or "").strip()
    if plate and plate != (d.vehicle_number or ""):
        dup = await db.execute(
            select(Driver).where(Driver.vehicle_number == plate, Driver.id != driver_id)
        )
        if dup.scalars().first():
            raise HTTPException(status_code=400, detail=f"Reg. number '{plate}' is already in use")

    d.vehicle_type = vehicle_type.strip().lower() or d.vehicle_type
    d.vehicle_number = plate or None
    d.vehicle_model = vehicle_model.strip() or None
    d.vehicle_color = vehicle_color.strip() or None
    d.vehicle_year = int(vehicle_year) if vehicle_year.strip().isdigit() else None
    new_photo = await _save_vehicle_photo(photo)
    if new_photo:
        d.vehicle_photo_url = new_photo
    await db.commit()
    return RedirectResponse(url="/admin/vehicles", status_code=303)


@router.post("/vehicles/{driver_id}/verify")
async def admin_vehicles_verify(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if d:
        d.is_approved = True
        d.status = DriverStatus.APPROVED
        d.approved_at = datetime.now(timezone.utc)
        await db.commit()
    return RedirectResponse(url="/admin/vehicles", status_code=303)


@router.post("/vehicles/{driver_id}/revoke")
async def admin_vehicles_revoke(
    driver_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    d = q.scalars().first()
    if d:
        d.is_approved = False
        d.is_online = False
        d.status = DriverStatus.SUSPENDED
        await db.commit()
    return RedirectResponse(url="/admin/vehicles", status_code=303)


# ---------- Flash pricing ----------
@router.get("/flash-pricing", response_class=HTMLResponse)
async def admin_flash_pricing(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FlashWeightTier

    q = await db.execute(
        select(FlashWeightTier).order_by(FlashWeightTier.display_order, FlashWeightTier.id)
    )
    return templates.TemplateResponse(
        request, "flash_pricing.html",
        {
            "request": request,
            "active_page": "flash-pricing",
            "tiers": q.scalars().all(),
        },
    )


@router.post("/flash-pricing/new")
async def admin_flash_pricing_new(
    label: str = Form(...),
    min_weight_kg: float = Form(...),
    max_weight_kg: str = Form(""),
    representative_weight_kg: float = Form(...),
    surcharge: float = Form(...),
    icon: str = Form("inventory_2"),
    display_order: int = Form(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import FlashWeightTier

    max_val = None
    if max_weight_kg.strip():
        try:
            max_val = Decimal(max_weight_kg.strip())
        except (ValueError, TypeError):
            max_val = None

    db.add(
        FlashWeightTier(
            label=label.strip(),
            min_weight_kg=Decimal(str(min_weight_kg)),
            max_weight_kg=max_val,
            representative_weight_kg=Decimal(str(representative_weight_kg)),
            surcharge=Decimal(str(surcharge)),
            icon=icon.strip() or "inventory_2",
            display_order=display_order,
            is_active=True,
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/flash-pricing", status_code=303)


@router.post("/flash-pricing/update")
async def admin_flash_pricing_update(
    id: int = Form(...),
    label: str = Form(...),
    min_weight_kg: float = Form(...),
    max_weight_kg: str = Form(""),
    representative_weight_kg: float = Form(...),
    surcharge: float = Form(...),
    icon: str = Form("inventory_2"),
    display_order: int = Form(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import FlashWeightTier

    q = await db.execute(select(FlashWeightTier).where(FlashWeightTier.id == id))
    t = q.scalars().first()
    if not t:
        raise HTTPException(status_code=404, detail="Tier not found")

    max_val = None
    if max_weight_kg.strip():
        try:
            max_val = Decimal(max_weight_kg.strip())
        except (ValueError, TypeError):
            max_val = None

    t.label = label.strip()
    t.min_weight_kg = Decimal(str(min_weight_kg))
    t.max_weight_kg = max_val
    t.representative_weight_kg = Decimal(str(representative_weight_kg))
    t.surcharge = Decimal(str(surcharge))
    t.icon = icon.strip() or "inventory_2"
    t.display_order = display_order
    await db.commit()
    return RedirectResponse(url="/admin/flash-pricing", status_code=303)


@router.post("/flash-pricing/{tier_id}/toggle")
async def admin_flash_pricing_toggle(
    tier_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FlashWeightTier

    q = await db.execute(select(FlashWeightTier).where(FlashWeightTier.id == tier_id))
    t = q.scalars().first()
    if t:
        t.is_active = not bool(t.is_active)
        await db.commit()
    return RedirectResponse(url="/admin/flash-pricing", status_code=303)


@router.post("/flash-pricing/{tier_id}/delete")
async def admin_flash_pricing_delete(
    tier_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FlashWeightTier

    q = await db.execute(select(FlashWeightTier).where(FlashWeightTier.id == tier_id))
    t = q.scalars().first()
    if t:
        await db.delete(t)
        await db.commit()
    return RedirectResponse(url="/admin/flash-pricing", status_code=303)


@router.get("/restaurants", response_class=HTMLResponse)
async def admin_restaurants(
    request: Request,
    page: int = 1,
    search: str = "",
    status: str = "all",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Restaurant

    limit = 50
    offset = (page - 1) * limit

    count_q = select(func.count(Restaurant.id))
    q = select(Restaurant)

    if search:
        count_q = count_q.where(Restaurant.name.ilike(f"%{search}%"))
        q = q.where(Restaurant.name.ilike(f"%{search}%"))
        
    if status == "active":
        count_q = count_q.where(Restaurant.is_active == True)
        q = q.where(Restaurant.is_active == True)
    elif status == "pending":
        count_q = count_q.where(Restaurant.is_active == False)
        q = q.where(Restaurant.is_active == False)

    total = (await db.execute(count_q)).scalar() or 0
    total_pages = (total + limit - 1) // limit

    # Order pending (is_active=False) first so owner self-registrations rise
    # to the top of the admin's attention. Within each group, newest first.
    q = q.order_by(Restaurant.is_active.asc(), Restaurant.id.desc()).offset(offset).limit(limit)
    result = await db.execute(q)
    restaurants = result.scalars().all()

    # Join the owner's phone and name so the admin can identify who registered each one.
    owner_ids = [r.owner_id for r in restaurants if r.owner_id]
    owner_info_by_id: dict[int, dict] = {}
    if owner_ids:
        u_q = await db.execute(select(User).where(User.id.in_(owner_ids)))
        owner_info_by_id = {u.id: {"phone": u.phone_number, "name": u.full_name} for u in u_q.scalars().all()}

    rows = [
        {
            "id": r.id,
            "name": r.name,
            "description": r.description,
            "cuisine": r.cuisine,
            "address": r.address,
            "phone_number": r.phone_number,
            "rating": r.rating,
            "delivery_fee": r.delivery_fee,
            "opening_time": r.opening_time,
            "closing_time": r.closing_time,
            "eta_minutes": r.eta_minutes,
            "is_active": r.is_active,
            "owner_id": r.owner_id,
            "owner_phone": owner_info_by_id.get(r.owner_id or 0, {}).get("phone"),
            "owner_full_name": owner_info_by_id.get(r.owner_id or 0, {}).get("name"),
            "lat": r.lat,
            "lng": r.lng,
            "image_url": r.image_url,
        }
        for r in restaurants
    ]

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "restaurants.html",
        {
            "request": request,
            "active_page": "restaurants",
            "restaurants": rows,
            "page": page,
            "total_pages": total_pages,
            "total_restaurants": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "search": search,
            "status": status,
        },
    )



@router.post("/restaurants/{restaurant_id}/edit")
async def admin_restaurant_edit(
    restaurant_id: int,
    owner_phone: str = Form(None),
    owner_full_name: str = Form(""),
    name: str = Form(...),
    description: str = Form(""),
    cuisine: str = Form(""),
    address: str = Form(""),
    lat: float = Form(6.9271),
    lng: float = Form(79.8612),
    phone_number: str = Form(""),
    image_url: str = Form(""),
    opening_time: str = Form(""),
    closing_time: str = Form(""),
    delivery_fee: float = Form(150),
    eta_minutes: int = Form(30),
    pickup_fee: float = Form(70.00),
    per_km_rate: float = Form(40.00),
    boost: float = Form(0.00),
    commission_percentage: float = Form(20.00),
    max_settle_amount: float = Form(1000.00),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import Restaurant, UserRole, User

    q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = q.scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    if owner_phone:
        phone = owner_phone.strip()
        if len(phone) != 10 or not phone.isdigit():
            raise HTTPException(status_code=400, detail="Owner phone must be exactly 10 digits.")
        
        # Locate or create the owner user.
        uq = await db.execute(select(User).where(User.phone_number == phone))
        owner = uq.scalars().first()
        if owner is None:
            owner = User(
                phone_number=phone,
                role=UserRole.RESTAURANT_OWNER,
                full_name=owner_full_name.strip() or None,
                is_active=True,
            )
            db.add(owner)
            await db.flush()
        else:
            if owner_full_name.strip():
                owner.full_name = owner_full_name.strip()
                
            existing = await db.execute(
                select(Restaurant).where(Restaurant.owner_id == owner.id, Restaurant.id != restaurant_id)
            )
            if existing.scalars().first() is not None:
                raise HTTPException(status_code=400, detail=f"User {phone} already owns a different restaurant.")
            
            from app.models import MarketVendor as _MV
            has_market = (
                await db.execute(
                    select(_MV).where(_MV.owner_id == owner.id)
                )
            ).scalars().first()
            if (
                owner.role in (UserRole.CUSTOMER, UserRole.MARKET_OWNER)
                and not has_market
            ):
                owner.role = UserRole.RESTAURANT_OWNER

        r.owner_id = owner.id

    r.name = name.strip() or r.name
    r.description = description.strip() or None
    r.cuisine = cuisine.strip() or None
    r.address = address.strip() or None
    r.lat = Decimal(str(lat))
    r.lng = Decimal(str(lng))
    r.phone_number = phone_number.strip() or r.phone_number
    r.image_url = image_url.strip() or r.image_url
    r.opening_time = opening_time.strip() or r.opening_time
    r.closing_time = closing_time.strip() or r.closing_time
    r.delivery_fee = Decimal(str(delivery_fee))
    r.eta_minutes = eta_minutes
    r.pickup_fee = Decimal(str(pickup_fee))
    r.per_km_rate = Decimal(str(per_km_rate))
    r.boost = Decimal(str(boost))
    r.commission_percentage = Decimal(str(commission_percentage))
    r.max_settle_amount = Decimal(str(max_settle_amount))
    await db.commit()
    return RedirectResponse(url="/admin/restaurants", status_code=303)


@router.post("/restaurants/{restaurant_id}/approve")
async def admin_restaurant_approve(
    restaurant_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Notification, Restaurant
    from app.services.ws_manager import manager

    q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = q.scalars().first()
    if r:
        was_pending = not bool(r.is_active)
        r.is_active = True
        await db.commit()
        # Push to the owner's app so they don't have to refresh.
        if was_pending and r.owner_id:
            await manager.send(
                r.owner_id,
                "restaurant_approved",
                {"restaurant_id": r.id, "name": r.name},
            )
            db.add(
                Notification(
                    user_id=r.owner_id,
                    title="Restaurant approved",
                    body=f"{r.name} is now live on Ziggo. You can start accepting orders.",
                    type="restaurant_approved",
                )
            )
            await db.commit()
    return RedirectResponse(url="/admin/restaurants", status_code=303)


@router.post("/restaurants/{restaurant_id}/suspend")
async def admin_restaurant_suspend(
    restaurant_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Notification, Restaurant
    from app.services.ws_manager import manager

    q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = q.scalars().first()
    if r:
        r.is_active = False
        # Force-close so any in-flight orders don't get accepted while suspended.
        if r.is_open is not None:
            r.is_open = False
        await db.commit()
        if r.owner_id:
            await manager.send(
                r.owner_id,
                "restaurant_suspended",
                {"restaurant_id": r.id, "name": r.name},
            )
            db.add(
                Notification(
                    user_id=r.owner_id,
                    title="Restaurant suspended",
                    body=f"{r.name} has been suspended by admin. Contact support for details.",
                    type="restaurant_suspended",
                )
            )
            await db.commit()
    return RedirectResponse(url="/admin/restaurants", status_code=303)


@router.get("/restaurants/new", response_class=HTMLResponse)
async def admin_restaurant_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    return templates.TemplateResponse(
        request, "restaurant_new.html",
        {"request": request, "active_page": "restaurants", "error": None, "form": {}},
    )


@router.post("/restaurants/new")
async def admin_restaurant_new_submit(
    request: Request,
    owner_phone: str = Form(...),
    owner_full_name: str = Form(""),
    name: str = Form(...),
    description: str = Form(""),
    cuisine: str = Form(""),
    address: str = Form(""),
    lat: float = Form(6.9271),
    lng: float = Form(79.8612),
    phone_number: str = Form(""),
    image_url: str = Form(""),
    opening_time: str = Form("09:00"),
    closing_time: str = Form("22:00"),
    delivery_fee: float = Form(150),
    eta_minutes: int = Form(30),
    pickup_fee: float = Form(70.00),
    per_km_rate: float = Form(40.00),
    boost: float = Form(0.00),
    commission_percentage: float = Form(20.00),
    max_settle_amount: float = Form(1000.00),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Admin pre-creates a restaurant. If the phone already belongs to a
    user, we reuse them (and bump customers up to restaurant_owner).
    Otherwise we create a fresh user with role=restaurant_owner."""
    from decimal import Decimal
    from app.models import Restaurant, UserRole

    form_echo = {
        "owner_phone": owner_phone,
        "owner_full_name": owner_full_name,
        "name": name,
        "description": description,
        "cuisine": cuisine,
        "address": address,
        "lat": lat,
        "lng": lng,
        "phone_number": phone_number,
        "image_url": image_url,
        "opening_time": opening_time,
        "closing_time": closing_time,
        "delivery_fee": delivery_fee,
        "eta_minutes": eta_minutes,
        "pickup_fee": pickup_fee,
        "per_km_rate": per_km_rate,
        "boost": boost,
        "commission_percentage": commission_percentage,
    }

    phone = owner_phone.strip()
    if len(phone) != 10 or not phone.isdigit():
        return templates.TemplateResponse(
            request, "restaurant_new.html",
            {
                "request": request,
                "active_page": "restaurants",
                "error": "Owner phone must be exactly 10 digits.",
                "form": form_echo,
            },
        )

    # Locate or create the owner user.
    uq = await db.execute(select(User).where(User.phone_number == phone))
    owner = uq.scalars().first()
    if owner is None:
        owner = User(
            phone_number=phone,
            role=UserRole.RESTAURANT_OWNER,
            full_name=owner_full_name.strip() or None,
            is_active=True,
        )
        db.add(owner)
        await db.flush()
    else:
        existing = await db.execute(
            select(Restaurant).where(Restaurant.owner_id == owner.id)
        )
        if existing.scalars().first() is not None:
            return templates.TemplateResponse(
                request, "restaurant_new.html",
                {
                    "request": request,
                    "active_page": "restaurants",
                    "error": f"User {phone} already owns a restaurant.",
                    "form": form_echo,
                },
            )
        # Promote when safe — plain customer OR a market_owner without a
        # market vendor (i.e. they never got onboarded for market). Avoid
        # touching drivers/admins or anyone with an active market vendor.
        from app.models import MarketVendor as _MV

        has_market = (
            await db.execute(
                select(_MV).where(_MV.owner_id == owner.id)
            )
        ).scalars().first()
        if (
            owner.role in (UserRole.CUSTOMER, UserRole.MARKET_OWNER)
            and not has_market
        ):
            owner.role = UserRole.RESTAURANT_OWNER
            if owner_full_name.strip() and not owner.full_name:
                owner.full_name = owner_full_name.strip()

    r = Restaurant(
        owner_id=owner.id,
        name=name.strip(),
        description=description.strip() or None,
        cuisine=cuisine.strip() or None,
        address=address.strip() or None,
        lat=Decimal(str(lat)),
        lng=Decimal(str(lng)),
        phone_number=phone_number.strip() or phone,
        image_url=image_url.strip() or None,
        opening_time=opening_time.strip() or None,
        closing_time=closing_time.strip() or None,
        delivery_fee=Decimal(str(delivery_fee)),
        eta_minutes=eta_minutes,
        pickup_fee=Decimal(str(pickup_fee)),
        per_km_rate=Decimal(str(per_km_rate)),
        boost=Decimal(str(boost)),
        commission_percentage=Decimal(str(commission_percentage)),
        max_settle_amount=Decimal(str(max_settle_amount)),
        rating=Decimal("4.5"),
        is_active=True,  # admin pre-creates as already-approved
        is_open=True,
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    return RedirectResponse(url=f"/admin/restaurants/{r.id}", status_code=303)


@router.post("/restaurants/{restaurant_id}/pay-settlement")
async def admin_restaurant_pay_settlement(
    restaurant_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Restaurant, FoodOrder, FoodOrderStatus, WalletTransaction, Customer
    import secrets
    
    q = await db.execute(select(Restaurant).where(Restaurant.id == restaurant_id))
    r = q.scalars().first()
    if not r:
        return RedirectResponse("/admin/restaurants", status_code=303)
        
    oq = await db.execute(
        select(FoodOrder).where(
            FoodOrder.restaurant_id == r.id,
            FoodOrder.status == FoodOrderStatus.DELIVERED
        )
    )
    orders = oq.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(r.commission_percentage)) if r.commission_percentage is not None else Decimal("20.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")
    
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == r.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == r.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    if net_owed_to_admin >= Decimal("0"):
        return RedirectResponse(f"/admin/restaurants/{restaurant_id}", status_code=303)
        
    admin_owes_vendor = -net_owed_to_admin
    
    ref = "SETTLE" + secrets.token_hex(4).upper()
    
    cq = await db.execute(select(Customer).where(Customer.user_id == r.owner_id))
    c = cq.scalars().first()
    if c:
        c.wallet_balance = (c.wallet_balance or Decimal("0")) + admin_owes_vendor
        
    tx = WalletTransaction(
        user_id=r.owner_id,
        amount=admin_owes_vendor,
        type="settlement_payment",
        description="Admin Settlement Payment",
        reference_id=ref,
        balance_after=(c.wallet_balance if c else admin_owes_vendor)
    )
    db.add(tx)
    await db.commit()
    
    return RedirectResponse(f"/admin/restaurants/{restaurant_id}", status_code=303)

@router.get("/restaurants/{restaurant_id}", response_class=HTMLResponse)
async def admin_restaurant_detail(
    restaurant_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Restaurant, MenuCategory, MenuItem, FoodCategory

    rq = await db.execute(
        select(Restaurant)
        .options(
            selectinload(Restaurant.categories),
            selectinload(Restaurant.items),
            selectinload(Restaurant.food_categories),
        )
        .where(Restaurant.id == restaurant_id)
    )
    restaurant = rq.scalars().first()
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    all_food_categories = (
        await db.execute(
            select(FoodCategory)
            .where(FoodCategory.is_active == True)  # noqa: E712
            .order_by(FoodCategory.display_order, FoodCategory.id)
        )
    ).scalars().all()
    selected_food_category_ids = {c.id for c in restaurant.food_categories}

    # Calculate Commission Outstanding
    from app.models import FoodOrder, FoodOrderStatus, WalletTransaction
    oq = await db.execute(
        select(FoodOrder).where(
            FoodOrder.restaurant_id == restaurant.id,
            FoodOrder.status == FoodOrderStatus.DELIVERED
        )
    )
    orders = oq.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(restaurant.commission_percentage)) if restaurant.commission_percentage is not None else Decimal("20.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")
    
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == restaurant.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == restaurant.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    admin_owes_vendor = Decimal("0")
    vendor_owes_admin = Decimal("0")
    if net_owed_to_admin > 0:
        vendor_owes_admin = net_owed_to_admin
    else:
        admin_owes_vendor = -net_owed_to_admin

    return templates.TemplateResponse(
        request, "restaurant_detail.html",
        {
            "request": request,
            "active_page": "restaurants",
            "restaurant": restaurant,
            "categories": sorted(restaurant.categories, key=lambda c: c.display_order or 0),
            "items": restaurant.items,
            "all_food_categories": all_food_categories,
            "selected_food_category_ids": selected_food_category_ids,
            "admin_owes_vendor": float(admin_owes_vendor),
            "vendor_owes_admin": float(vendor_owes_admin),
            "error": None,
        },
    )


@router.post("/restaurants/{restaurant_id}/categories/new")
async def admin_restaurant_add_category(
    restaurant_id: int,
    name: str = Form(...),
    display_order: int = Form(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MenuCategory

    db.add(
        MenuCategory(
            restaurant_id=restaurant_id,
            name=name.strip(),
            display_order=display_order,
            is_active=True,
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


@router.post("/restaurants/{restaurant_id}/items/new")
async def admin_restaurant_add_item(
    restaurant_id: int,
    name: str = Form(...),
    description: str = Form(""),
    price: float = Form(...),
    category_id: int = Form(...),
    image_url: str = Form(""),
    is_veg: str = Form(""),
    prep_time_min: int = Form(15),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import MenuItem

    db.add(
        MenuItem(
            restaurant_id=restaurant_id,
            category_id=category_id,
            name=name.strip(),
            description=description.strip() or None,
            price=Decimal(str(price)),
            image_url=image_url.strip() or None,
            is_available=True,
            is_veg=bool(is_veg),
            prep_time_min=prep_time_min,
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


@router.post("/restaurants/{restaurant_id}/categories/{category_id}/edit")
async def admin_restaurant_edit_category(
    restaurant_id: int,
    category_id: int,
    name: str = Form(...),
    display_order: int = Form(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MenuCategory
    cat = (await db.execute(select(MenuCategory).where(MenuCategory.id == category_id, MenuCategory.restaurant_id == restaurant_id))).scalars().first()
    if cat:
        cat.name = name.strip()
        cat.display_order = display_order
        await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


@router.post("/restaurants/{restaurant_id}/categories/{category_id}/delete")
async def admin_restaurant_delete_category(
    restaurant_id: int,
    category_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MenuCategory
    cat = (await db.execute(select(MenuCategory).where(MenuCategory.id == category_id, MenuCategory.restaurant_id == restaurant_id))).scalars().first()
    if cat:
        await db.delete(cat)
        await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


@router.post("/restaurants/{restaurant_id}/items/{item_id}/edit")
async def admin_restaurant_edit_item(
    restaurant_id: int,
    item_id: int,
    name: str = Form(...),
    description: str = Form(""),
    price: float = Form(...),
    category_id: int = Form(...),
    image_url: str = Form(""),
    is_veg: str = Form(""),
    prep_time_min: int = Form(15),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import MenuItem
    item = (await db.execute(select(MenuItem).where(MenuItem.id == item_id, MenuItem.restaurant_id == restaurant_id))).scalars().first()
    if item:
        item.name = name.strip()
        item.description = description.strip() or None
        item.price = Decimal(str(price))
        item.category_id = category_id
        item.image_url = image_url.strip() or None
        item.is_veg = bool(is_veg)
        item.prep_time_min = prep_time_min
        await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


@router.post("/restaurants/{restaurant_id}/items/{item_id}/delete")
async def admin_restaurant_delete_item(
    restaurant_id: int,
    item_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MenuItem
    item = (await db.execute(select(MenuItem).where(MenuItem.id == item_id, MenuItem.restaurant_id == restaurant_id))).scalars().first()
    if item:
        await db.delete(item)
        await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


# ---------- Market vendors ----------
@router.get("/market", response_class=HTMLResponse)
async def admin_market(
    request: Request,
    page: int = 1,
    search: str = "",
    status: str = "all",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketVendor

    limit = 50
    offset = (page - 1) * limit

    count_q = select(func.count(MarketVendor.id))
    q = select(MarketVendor)

    if search:
        count_q = count_q.where(MarketVendor.name.ilike(f"%{search}%"))
        q = q.where(MarketVendor.name.ilike(f"%{search}%"))
        
    if status == "active":
        count_q = count_q.where(MarketVendor.is_active == True)
        q = q.where(MarketVendor.is_active == True)
    elif status == "suspended":
        count_q = count_q.where(MarketVendor.is_active == False)
        q = q.where(MarketVendor.is_active == False)

    total = (await db.execute(count_q)).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = q.order_by(MarketVendor.id.desc()).offset(offset).limit(limit)
    result = await db.execute(q)
    vendors = result.scalars().all()

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "market.html",
        {
            "request": request,
            "active_page": "market",
            "vendors": vendors,
            "page": page,
            "total_pages": total_pages,
            "total_vendors": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "search": search,
            "status": status,
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY or "",
        },
    )



@router.get("/market/new", response_class=HTMLResponse)
async def admin_market_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    return templates.TemplateResponse(
        request, "market_new.html",
        {
            "request": request,
            "active_page": "market",
            "error": None,
            "form": {},
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY or "",
        },
    )


@router.post("/market/new")
async def admin_market_new_submit(
    request: Request,
    owner_phone: str = Form(...),
    owner_full_name: str = Form(""),
    owner_email: str = Form(...),
    name: str = Form(...),
    category: str = Form(""),
    description: str = Form(""),
    address: str = Form(""),
    lat: float = Form(6.9271),
    lng: float = Form(79.8612),
    phone_number: str = Form(""),
    image_url: str = Form(""),
    opening_time: str = Form("08:00"),
    closing_time: str = Form("22:00"),
    delivery_fee: float = Form(250.0),
    eta_minutes: int = Form(40),
    business_registration_number: str = Form(""),
    tax_vat_number: str = Form(""),
    self_delivery: str = Form("no"),
    marketplace_delivery: str = Form("yes"),
    delivery_radius_km: float = Form(None),
    average_prep_time_minutes: int = Form(30),
    bank_name: str = Form(""),
    account_holder_name: str = Form(""),
    account_number: str = Form(""),
    branch_name: str = Form(""),
    commission_percentage: float = Form(10.00),
    priority_level: str = Form("standard"),
    is_featured: str = Form("no"),
    vendor_status: str = Form("active"),
    pickup_fee: float = Form(70.00),
    per_km_rate: float = Form(40.00),
    boost: float = Form(0.00),
    nic_passport_copy: UploadFile = File(None),
    business_reg_cert: UploadFile = File(None),
    tax_cert: UploadFile = File(None),
    food_license: UploadFile = File(None),
    additional_documents: UploadFile = File(None),
    vendor_image: UploadFile = File(None),
    max_settle_amount: float = Form(1000.00),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Admin pre-creates a market vendor with comprehensive details."""
    from decimal import Decimal
    from app.models import MarketVendor, Restaurant, UserRole

    form_echo = {
        "owner_phone": owner_phone,
        "owner_full_name": owner_full_name,
        "owner_email": owner_email,
        "name": name,
        "category": category,
        "description": description,
        "address": address,
        "lat": lat,
        "lng": lng,
        "phone_number": phone_number,
        "image_url": image_url,
        "opening_time": opening_time,
        "closing_time": closing_time,
        "delivery_fee": delivery_fee,
        "eta_minutes": eta_minutes,
        "business_registration_number": business_registration_number,
        "tax_vat_number": tax_vat_number,
        "self_delivery": self_delivery,
        "marketplace_delivery": marketplace_delivery,
        "delivery_radius_km": delivery_radius_km,
        "average_prep_time_minutes": average_prep_time_minutes,
        "bank_name": bank_name,
        "account_holder_name": account_holder_name,
        "account_number": account_number,
        "branch_name": branch_name,
        "commission_percentage": commission_percentage,
        "priority_level": priority_level,
        "is_featured": is_featured,
        "vendor_status": vendor_status,
        "pickup_fee": pickup_fee,
        "per_km_rate": per_km_rate,
        "boost": boost,
    }

    phone = owner_phone.strip()
    if len(phone) != 10 or not phone.isdigit():
        return templates.TemplateResponse(
            request, "market_new.html",
            {
                "request": request,
                "active_page": "market",
                "error": "Owner phone must be exactly 10 digits.",
                "form": form_echo,
                "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY or "",
            },
        )

    # Locate or create the owner user.
    uq = await db.execute(select(User).where(User.phone_number == phone))
    owner = uq.scalars().first()
    if owner is None:
        owner = User(
            phone_number=phone,
            role=UserRole.MARKET_OWNER,
            full_name=owner_full_name.strip() or None,
            email=owner_email.strip() or None,
            is_active=True,
        )
        db.add(owner)
        await db.flush()
    else:
        # Check if they already own a vendor.
        from app.models import MarketVendor as _MV
        existing = await db.execute(select(_MV).where(_MV.owner_id == owner.id))
        if existing.scalars().first() is not None:
            return templates.TemplateResponse(
                request, "market_new.html",
                {
                    "request": request,
                    "active_page": "market",
                    "error": f"User {phone} already owns a market vendor.",
                    "form": form_echo,
                    "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY or "",
                },
            )
            
        # Promote them to market_owner if they are a customer (or restaurant_owner
        # but have no active restaurant).
        has_restaurant = (
            await db.execute(
                select(Restaurant).where(Restaurant.owner_id == owner.id)
            )
        ).scalars().first()
        if (
            owner.role in (UserRole.CUSTOMER, UserRole.RESTAURANT_OWNER)
            and not has_restaurant
        ):
            owner.role = UserRole.MARKET_OWNER
            if owner_full_name.strip() and not owner.full_name:
                owner.full_name = owner_full_name.strip()
            if owner_email.strip() and not owner.email:
                owner.email = owner_email.strip()

    # Save uploaded documents
    nic_url = await _save_vendor_doc(nic_passport_copy, "nic")
    biz_cert_url = await _save_vendor_doc(business_reg_cert, "biz_cert")
    tax_cert_url = await _save_vendor_doc(tax_cert, "tax_cert")
    food_lic_url = await _save_vendor_doc(food_license, "food_lic")
    add_docs_url = await _save_vendor_doc(additional_documents, "add_docs")
    vendor_img_url = await _save_vendor_doc(vendor_image, "vendor_image")

    is_active_val = (vendor_status == "active")
    is_open_val = is_active_val

    v = MarketVendor(
        owner_id=owner.id,
        name=name.strip(),
        category=category.strip() or None,
        description=description.strip() or None,
        address=address.strip() or None,
        lat=Decimal(str(lat)),
        lng=Decimal(str(lng)),
        phone_number=phone_number.strip() or phone,
        image_url=vendor_img_url or image_url.strip() or None,
        logo_url=vendor_img_url or None,
        opening_time=opening_time.strip() or None,
        closing_time=closing_time.strip() or None,
        delivery_fee=Decimal(str(delivery_fee)),
        eta_minutes=eta_minutes,
        rating=Decimal("4.3"),
        is_active=is_active_val,
        is_open=is_open_val,
        
        business_registration_number=business_registration_number.strip() or None,
        tax_vat_number=tax_vat_number.strip() or None,
        self_delivery=(self_delivery == "yes"),
        marketplace_delivery=(marketplace_delivery == "yes"),
        delivery_radius_km=Decimal(str(delivery_radius_km)) if delivery_radius_km is not None else None,
        average_prep_time_minutes=average_prep_time_minutes,
        bank_name=bank_name.strip() if bank_name else None,
        account_holder_name=account_holder_name.strip() if account_holder_name else None,
        account_number=account_number.strip() if account_number else None,
        branch_name=branch_name.strip() if branch_name else None,
        nic_passport_copy_url=nic_url,
        business_reg_cert_url=biz_cert_url,
        tax_cert_url=tax_cert_url,
        food_license_url=food_lic_url,
        additional_docs_url=add_docs_url,
        commission_percentage=Decimal(str(commission_percentage)),
        max_settle_amount=Decimal(str(max_settle_amount)),
        priority_level=priority_level.strip(),
        is_featured=(is_featured == "yes"),
        pickup_fee=Decimal(str(pickup_fee)),
        per_km_rate=Decimal(str(per_km_rate)),
        boost=Decimal(str(boost)),
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)

    return RedirectResponse(url="/admin/market", status_code=303)


@router.post("/market/{vendor_id}/pay-settlement")
async def admin_market_pay_settlement(
    vendor_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketVendor, MarketOrder, MarketOrderStatus, WalletTransaction, Customer
    import secrets
    
    q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = q.scalars().first()
    if not v:
        return RedirectResponse("/admin/market", status_code=303)
        
    oq = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == v.id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = oq.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(v.commission_percentage)) if v.commission_percentage is not None else Decimal("10.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")
    
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == v.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == v.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    if net_owed_to_admin >= Decimal("0"):
        return RedirectResponse(f"/admin/market/{vendor_id}", status_code=303)
        
    admin_owes_vendor = -net_owed_to_admin
    
    ref = "SETTLE" + secrets.token_hex(4).upper()
    
    cq = await db.execute(select(Customer).where(Customer.user_id == v.owner_id))
    c = cq.scalars().first()
    if c:
        c.wallet_balance = (c.wallet_balance or Decimal("0")) + admin_owes_vendor
        
    tx = WalletTransaction(
        user_id=v.owner_id,
        amount=admin_owes_vendor,
        type="settlement_payment",
        description="Admin Settlement Payment",
        reference_id=ref,
        balance_after=(c.wallet_balance if c else admin_owes_vendor)
    )
    db.add(tx)
    await db.commit()
    
    return RedirectResponse(f"/admin/market/{vendor_id}", status_code=303)

@router.get("/market/{vendor_id}", response_class=HTMLResponse)
async def admin_market_detail(
    vendor_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketVendor, Product

    vq = await db.execute(
        select(MarketVendor)
        .options(selectinload(MarketVendor.products))
        .where(MarketVendor.id == vendor_id)
    )
    vendor = vq.scalars().first()
    if not vendor:
        raise HTTPException(status_code=404, detail="Vendor not found")

    owner = None
    if vendor.owner_id:
        owner = (
            await db.execute(select(User).where(User.id == vendor.owner_id))
        ).scalars().first()

    # Calculate Commission Outstanding
    from app.models import MarketOrder, MarketOrderStatus, WalletTransaction
    oq = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == vendor.id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = oq.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(vendor.commission_percentage)) if vendor.commission_percentage is not None else Decimal("10.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")
    
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == vendor.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == vendor.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    admin_owes_vendor = Decimal("0")
    vendor_owes_admin = Decimal("0")
    if net_owed_to_admin > 0:
        vendor_owes_admin = net_owed_to_admin
    else:
        admin_owes_vendor = -net_owed_to_admin

    return templates.TemplateResponse(
        request, "market_detail.html",
        {
            "request": request,
            "active_page": "market",
            "vendor": vendor,
            "owner": owner,
            "products": vendor.products,
            "admin_owes_vendor": float(admin_owes_vendor),
            "vendor_owes_admin": float(vendor_owes_admin),
        },
    )


@router.post("/market/{vendor_id}/products/new")
async def admin_market_add_product(
    vendor_id: int,
    name: str = Form(...),
    description: str = Form(""),
    price: float = Form(...),
    unit: str = Form(""),
    stock_quantity: int = Form(0),
    weight_kg: str = Form(""),
    image_url: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import Product

    db.add(
        Product(
            vendor_id=vendor_id,
            name=name.strip(),
            description=description.strip() or None,
            price=Decimal(str(price)),
            unit=unit.strip() or None,
            stock_quantity=stock_quantity,
            weight_kg=Decimal(weight_kg.strip()) if weight_kg.strip() else None,
            image_url=image_url.strip() or None,
            is_available=True,
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/admin/market/{vendor_id}", status_code=303)


@router.post("/market/{vendor_id}/edit")
async def admin_market_vendor_edit(
    vendor_id: int,
    name: str = Form(...),
    category: str = Form(""),
    description: str = Form(""),
    address: str = Form(""),
    lat: float = Form(None),
    lng: float = Form(None),
    phone_number: str = Form(""),
    opening_time: str = Form(""),
    closing_time: str = Form(""),
    delivery_fee: float = Form(250),
    eta_minutes: int = Form(40),
    commission_percentage: float = Form(10.00),
    priority_level: str = Form("standard"),
    is_featured: str = Form("no"),
    bank_name: str = Form(""),
    account_holder_name: str = Form(""),
    account_number: str = Form(""),
    branch_name: str = Form(""),
    pickup_fee: float = Form(70.00),
    per_km_rate: float = Form(40.00),
    boost: float = Form(0.00),
    max_settle_amount: float = Form(1000.00),
    vendor_image: UploadFile = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from app.models import MarketVendor

    q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = q.scalars().first()
    if not v:
        raise HTTPException(status_code=404, detail="Vendor not found")

    v.name = name.strip() or v.name
    v.category = category.strip() or v.category
    v.description = description.strip() or None
    v.address = address.strip() or v.address
    if lat is not None:
        v.lat = Decimal(str(lat))
    if lng is not None:
        v.lng = Decimal(str(lng))
    
    vendor_img_url = await _save_vendor_doc(vendor_image, "vendor_image")
    if vendor_img_url:
        v.image_url = vendor_img_url
        v.logo_url = vendor_img_url
        
    if phone_number.strip():
        new_phone = phone_number.strip()
        v.phone_number = new_phone
        from app.models import User, UserRole
        uq = await db.execute(select(User).where(User.phone_number == new_phone))
        new_owner = uq.scalars().first()
        if new_owner is None:
            new_owner = User(
                phone_number=new_phone,
                role=UserRole.MARKET_OWNER,
                is_active=True,
            )
            db.add(new_owner)
            await db.flush()
        else:
            if new_owner.role in (UserRole.CUSTOMER, UserRole.RESTAURANT_OWNER):
                new_owner.role = UserRole.MARKET_OWNER
        v.owner_id = new_owner.id
    v.opening_time = opening_time.strip() or v.opening_time
    v.closing_time = closing_time.strip() or v.closing_time
    v.delivery_fee = Decimal(str(delivery_fee))
    v.eta_minutes = eta_minutes
    v.commission_percentage = Decimal(str(commission_percentage))
    v.priority_level = priority_level.strip() or v.priority_level
    v.is_featured = is_featured == "yes"
    v.pickup_fee = Decimal(str(pickup_fee))
    v.per_km_rate = Decimal(str(per_km_rate))
    v.boost = Decimal(str(boost))
    v.max_settle_amount = Decimal(str(max_settle_amount))
    if bank_name.strip():
        v.bank_name = bank_name.strip()
    if account_holder_name.strip():
        v.account_holder_name = account_holder_name.strip()
    if account_number.strip():
        v.account_number = account_number.strip()
    if branch_name.strip():
        v.branch_name = branch_name.strip()
    await db.commit()
    return RedirectResponse(url="/admin/market", status_code=303)


@router.post("/market/{vendor_id}/suspend")
async def admin_market_suspend(
    vendor_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Suspend a market vendor — sets is_active=False and forces is_open=False
    so customers stop seeing them immediately. Owner is notified by WS."""
    from app.models import MarketVendor, Notification
    from app.services.ws_manager import manager

    q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = q.scalars().first()
    if v:
        v.is_active = False
        if v.is_open is not None:
            v.is_open = False
        await db.commit()
        if v.owner_id:
            await manager.send(
                v.owner_id,
                "vendor_suspended",
                {"vendor_id": v.id, "name": v.name},
            )
            db.add(
                Notification(
                    user_id=v.owner_id,
                    title="Stall suspended",
                    body=f"{v.name} has been suspended by admin. Contact support for details.",
                    type="vendor_suspended",
                )
            )
            await db.commit()
    return RedirectResponse(url=f"/admin/market/{vendor_id}", status_code=303)


@router.post("/market/{vendor_id}/activate")
async def admin_market_activate(
    vendor_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Un-suspend a market vendor — sets is_active=True and notifies the owner."""
    from app.models import MarketVendor, Notification
    from app.services.ws_manager import manager

    q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = q.scalars().first()
    if v:
        was_suspended = not bool(v.is_active)
        v.is_active = True
        await db.commit()
        if was_suspended and v.owner_id:
            await manager.send(
                v.owner_id,
                "vendor_approved",
                {"vendor_id": v.id, "name": v.name},
            )
            db.add(
                Notification(
                    user_id=v.owner_id,
                    title="Stall reactivated",
                    body=f"{v.name} is live again on Ziggo Mart. You can accept orders now.",
                    type="vendor_approved",
                )
            )
            await db.commit()
    return RedirectResponse(url=f"/admin/market/{vendor_id}", status_code=303)


@router.post("/market/{vendor_id}/delete")
async def admin_market_delete(
    vendor_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Permanently delete a market vendor, associated products, and orders."""
    from sqlalchemy import delete
    from app.models import MarketVendor, Product, MarketOrder, MarketOrderItem

    q = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = q.scalars().first()
    if v:
        # Delete order items first
        order_ids_q = await db.execute(select(MarketOrder.id).where(MarketOrder.vendor_id == vendor_id))
        order_ids = order_ids_q.scalars().all()
        if order_ids:
            await db.execute(delete(MarketOrderItem).where(MarketOrderItem.order_id.in_(order_ids)))
            await db.execute(delete(MarketOrder).where(MarketOrder.id.in_(order_ids)))
        
        # Products are cascade deleted via relationship cascade
        await db.delete(v)
        await db.commit()
    return RedirectResponse(url="/admin/market", status_code=303)


# ===========================================================================
# Market Home layout — ads / deals
# (drives the customer Market home screen via GET /api/v1/market/ads & deals)
# ===========================================================================
MARKET_HOME_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "market_home")
os.makedirs(MARKET_HOME_UPLOAD_DIR, exist_ok=True)


async def _save_market_home_image(photo: UploadFile | None) -> str | None:
    if photo is None or not photo.filename:
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        raise HTTPException(status_code=400, detail="Image must be JPG, PNG, WEBP, or AVIF")
    data = await photo.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(MARKET_HOME_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/market_home/{fname}"


@router.get("/market-home", response_class=HTMLResponse)
async def admin_market_home(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketAd, MarketDeal, MarketVendor, PromoCode, MarketCategory
    from sqlalchemy.orm import selectinload

    ads = (
        await db.execute(
            select(MarketAd)
            .options(selectinload(MarketAd.vendor))
            .outerjoin(MarketVendor, MarketAd.vendor_id == MarketVendor.id)
            .order_by(MarketAd.display_order, MarketAd.id.desc())
        )
    ).scalars().all()

    deals = (
        await db.execute(
            select(MarketDeal)
            .options(selectinload(MarketDeal.promo_code))
            .order_by(MarketDeal.display_order, MarketDeal.id)
        )
    ).scalars().all()

    vendors = (
        await db.execute(
            select(MarketVendor).where(MarketVendor.is_active == True).order_by(MarketVendor.name)  # noqa: E712
        )
    ).scalars().all()

    promos = (
        await db.execute(
            select(PromoCode)
            .where(PromoCode.is_active == True, PromoCode.category.in_(["all", "market"]))  # noqa: E712
            .order_by(PromoCode.code)
        )
    ).scalars().all()

    categories = (
        await db.execute(
            select(MarketCategory)
            .order_by(MarketCategory.display_order, MarketCategory.id)
        )
    ).scalars().all()

    return templates.TemplateResponse(
        request,
        "market_home.html",
        {
            "request": request,
            "active_page": "market-home",
            "ads": ads,
            "deals": deals,
            "vendors": vendors,
            "promos": promos,
            "categories": categories,
        },
    )


# ---------- Categories ----------
@router.post("/market-home/categories/new")
async def admin_market_category_new(
    name: str = Form(...),
    color: str = Form("primary"),
    image_url: str = Form(""),
    display_order: int = Form(0),
    is_active: str = Form("off"),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketCategory

    if not name.strip():
        raise HTTPException(status_code=400, detail="Category name is required")
    url = await _save_market_home_image(image) or (image_url.strip() or None)
    db.add(
        MarketCategory(
            name=name.strip(),
            color=color.strip() or "primary",
            image_url=url,
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/categories/{id}/edit")
async def admin_market_category_edit(
    id: int,
    name: str = Form(...),
    color: str = Form("primary"),
    image_url: str = Form(""),
    display_order: int = Form(0),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketCategory

    c = (await db.execute(select(MarketCategory).where(MarketCategory.id == id))).scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Category not found")
    c.name = name.strip() or c.name
    c.color = color.strip() or "primary"
    c.display_order = int(display_order or 0)
    new_url = await _save_market_home_image(image)
    if new_url:
        c.image_url = new_url
    elif image_url.strip():
        c.image_url = image_url.strip()
    await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/categories/{id}/toggle")
async def admin_market_category_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketCategory

    c = (await db.execute(select(MarketCategory).where(MarketCategory.id == id))).scalars().first()
    if c:
        c.is_active = not c.is_active
        await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/categories/{id}/delete")
async def admin_market_category_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketCategory

    c = (await db.execute(select(MarketCategory).where(MarketCategory.id == id))).scalars().first()
    if c:
        await db.delete(c)
        await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


# ---------- Ads ----------
@router.post("/market-home/ads/new")
async def admin_market_ad_new(
    vendor_id: int | None = Form(None),
    radius_km: float = Form(5.0),
    image_url: str = Form(""),
    display_order: int = Form(0),
    is_active: str = Form("off"),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketAd

    url = await _save_market_home_image(image) or (image_url.strip() or None)
    if not url:
        raise HTTPException(status_code=400, detail="An ad image (upload or URL) is required")
    db.add(
        MarketAd(
            vendor_id=vendor_id if vendor_id and vendor_id > 0 else None,
            image_url=url,
            radius_km=Decimal(str(radius_km)),
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
            link_type=link_type,
            link_value=link_value.strip() or None,
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/ads/{id}/edit")
async def admin_market_ad_edit(
    id: int,
    vendor_id: int | None = Form(None),
    radius_km: float = Form(5.0),
    image_url: str = Form(""),
    display_order: int = Form(0),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketAd

    ad = (await db.execute(select(MarketAd).where(MarketAd.id == id))).scalars().first()
    if not ad:
        raise HTTPException(status_code=404, detail="Ad not found")
    ad.vendor_id = vendor_id if vendor_id and vendor_id > 0 else None
    ad.radius_km = Decimal(str(radius_km))
    ad.display_order = int(display_order or 0)
    ad.link_type = link_type
    ad.link_value = link_value.strip() or None
    new_url = await _save_market_home_image(image)
    if new_url:
        ad.image_url = new_url
    elif image_url.strip():
        ad.image_url = image_url.strip()
    await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/ads/{id}/toggle")
async def admin_market_ad_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketAd

    ad = (await db.execute(select(MarketAd).where(MarketAd.id == id))).scalars().first()
    if ad:
        ad.is_active = not ad.is_active
        await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/ads/{id}/delete")
async def admin_market_ad_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketAd

    ad = (await db.execute(select(MarketAd).where(MarketAd.id == id))).scalars().first()
    if ad:
        await db.delete(ad)
        await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


# ---------- Deals ----------
@router.post("/market-home/deals/new")
async def admin_market_deal_new(
    title: str = Form(...),
    subtitle: str = Form(""),
    color: str = Form("primary"),
    promo_code_id: str = Form(""),
    image_url: str = Form(""),
    display_order: int = Form(0),
    is_active: str = Form("off"),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    graphic_style: str = Form("custom"),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketDeal

    if not title.strip():
        raise HTTPException(status_code=400, detail="Deal title is required")

    if graphic_style != "custom":
        url = graphic_style
    else:
        url = await _save_market_home_image(image) or (image_url.strip() or None)

    db.add(
        MarketDeal(
            title=title.strip(),
            subtitle=subtitle.strip() or None,
            color=color.strip() or "primary",
            promo_code_id=int(promo_code_id) if promo_code_id.strip() else None,
            image_url=url,
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
            link_type=link_type,
            link_value=link_value.strip() or None,
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/deals/{id}/edit")
async def admin_market_deal_edit(
    id: int,
    title: str = Form(...),
    subtitle: str = Form(""),
    color: str = Form("primary"),
    promo_code_id: str = Form(""),
    image_url: str = Form(""),
    display_order: int = Form(0),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    graphic_style: str = Form("custom"),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketDeal

    d = (await db.execute(select(MarketDeal).where(MarketDeal.id == id))).scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Deal not found")
    d.title = title.strip() or d.title
    d.subtitle = subtitle.strip() or None
    d.color = color.strip() or "primary"
    d.promo_code_id = int(promo_code_id) if promo_code_id.strip() else None
    d.display_order = int(display_order or 0)
    d.link_type = link_type
    d.link_value = link_value.strip() or None

    if graphic_style != "custom":
        d.image_url = graphic_style
    else:
        new_url = await _save_market_home_image(image)
        if new_url:
            d.image_url = new_url
        elif image_url.strip():
            d.image_url = image_url.strip()

    await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/deals/{id}/toggle")
async def admin_market_deal_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketDeal

    d = (await db.execute(select(MarketDeal).where(MarketDeal.id == id))).scalars().first()
    if d:
        d.is_active = not d.is_active
        await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


@router.post("/market-home/deals/{id}/delete")
async def admin_market_deal_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import MarketDeal

    d = (await db.execute(select(MarketDeal).where(MarketDeal.id == id))).scalars().first()
    if d:
        await db.delete(d)
        await db.commit()
    return RedirectResponse(url="/admin/market-home", status_code=303)


# ---------- Reports / Insight & Analytics ----------
def _parse_iso_date_or(default_dt, raw: str):
    if not raw:
        return default_dt
    try:
        return datetime.strptime(raw.strip(), "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        return default_dt


async def _reports_aggregate(db: AsyncSession, start_dt: datetime, end_dt_exclusive: datetime, type: str = "summary") -> dict:
    """Aggregate bookings between [start_dt, end_dt_exclusive) bucketed by day."""
    from decimal import Decimal as D
    from sqlalchemy import cast, Date, distinct

    bucket = cast(Booking.booked_at, Date).label("day")

    if type == "earnings":
        # Per-day earnings rollup for COMPLETED bookings
        q = await db.execute(
            select(
                bucket,
                func.count(Booking.id),
                func.coalesce(func.sum(Booking.final_amount), 0),
                func.coalesce(func.sum(Booking.platform_fee), 0),
                func.coalesce(func.sum(Booking.driver_earnings), 0),
                func.coalesce(func.sum(Booking.waiting_charge), 0),
                func.coalesce(func.sum(Booking.discount_amount), 0),
                func.coalesce(func.sum(Booking.redeem_discount), 0),
            )
            .where(
                Booking.booked_at >= start_dt,
                Booking.booked_at < end_dt_exclusive,
                Booking.status == BookingStatus.COMPLETED
            )
            .group_by(bucket)
            .order_by(bucket)
        )
        
        rows_by_day = {}
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            rows_by_day[cur.isoformat()] = {
                "date": cur.isoformat(),
                "gross": 0.0,
                "driver_earnings": 0.0,
                "commission": 0.0,
                "waiting_charge": 0.0,
                "discount": 0.0,
            }
            cur = cur + timedelta(days=1)

        overall = {
            "gross": 0.0,
            "driver_earnings": 0.0,
            "commission": 0.0,
            "waiting_charge": 0.0,
            "promo_discount": 0.0,
            "redeem_discount": 0.0,
        }
        for day, count, gross, commission, driver_earn, wait_chg, promo, redeem in q.all():
            key = day.isoformat()
            r = rows_by_day.setdefault(key, {
                "date": key, "gross": 0.0, "driver_earnings": 0.0, "commission": 0.0, "waiting_charge": 0.0, "discount": 0.0
            })
            r["gross"] = float(gross)
            r["driver_earnings"] = float(driver_earn)
            r["commission"] = float(commission)
            r["waiting_charge"] = float(wait_chg)
            r["discount"] = float(promo + redeem)
            
            overall["gross"] += float(gross)
            overall["driver_earnings"] += float(driver_earn)
            overall["commission"] += float(commission)
            overall["waiting_charge"] += float(wait_chg)
            overall["promo_discount"] += float(promo)
            overall["redeem_discount"] += float(redeem)

        rows_sorted = sorted(rows_by_day.values(), key=lambda r: r["date"], reverse=True)
        trend = [
            {"date": r["date"], "gross": r["gross"], "commission": r["commission"]}
            for r in rows_sorted
        ]
        trend.reverse()

        return {
            "totals": {
                "admin_net": overall["commission"],
                "gross_bookings": overall["gross"],
                "driver_earnings": overall["driver_earnings"],
                "waiting_charge": overall["waiting_charge"],
                "promo_discount": overall["promo_discount"],
                "redeem_discount": overall["redeem_discount"],
                "total_discount": overall["promo_discount"] + overall["redeem_discount"],
            },
            "trend": trend,
            "rows": rows_sorted,
        }

    elif type == "revenue":
        # Full revenue breakdown across every stream: Rides, Flash delivery,
        # Food, Marketplace and Gold subscriptions.
        from app.models import (
            FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus,
            MarketVendor, WalletTransaction, SystemSettings,
        )

        # Platform commission rate for food (no per-order field) — use the
        # configured global rate, falling back to 15%.
        food_rate = (await db.execute(select(SystemSettings.commission_rate).limit(1))).scalar()
        food_rate = float(food_rate) / 100.0 if food_rate is not None else 0.15

        rows_by_day = {}
        days_list = []
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            k = cur.isoformat()
            rows_by_day[k] = {
                "date": k, "rides": 0.0, "delivery": 0.0, "food": 0.0,
                "market": 0.0, "gold": 0.0, "commission": 0.0,
            }
            days_list.append(k)
            cur = cur + timedelta(days=1)

        svc = {s: {"gmv": 0.0, "orders": 0, "commission": 0.0}
               for s in ("rides", "delivery", "food", "market", "gold")}

        def _add(day_key, stream, gross, comm, orders):
            r = rows_by_day.get(day_key)
            if r is None:
                return
            r[stream] += float(gross)
            r["commission"] += float(comm)
            svc[stream]["gmv"] += float(gross)
            svc[stream]["commission"] += float(comm)
            svc[stream]["orders"] += int(orders)

        # Rides + Flash deliveries (bookings)
        bday = cast(Booking.booked_at, Date)
        qb = await db.execute(
            select(bday, Booking.is_flash, func.count(Booking.id),
                   func.coalesce(func.sum(Booking.final_amount), 0),
                   func.coalesce(func.sum(Booking.platform_fee), 0))
            .where(Booking.booked_at >= start_dt, Booking.booked_at < end_dt_exclusive,
                   Booking.status == BookingStatus.COMPLETED)
            .group_by(bday, Booking.is_flash)
        )
        for day, is_flash, cnt, gross, comm in qb.all():
            _add(day.isoformat(), "delivery" if is_flash else "rides", gross, comm, cnt)

        # Food orders (delivered)
        fday = cast(FoodOrder.created_at, Date)
        qf = await db.execute(
            select(fday, func.count(FoodOrder.id),
                   func.coalesce(func.sum(FoodOrder.final_amount), 0))
            .where(FoodOrder.created_at >= start_dt, FoodOrder.created_at < end_dt_exclusive,
                   FoodOrder.status == FoodOrderStatus.DELIVERED)
            .group_by(fday)
        )
        for day, cnt, gross in qf.all():
            _add(day.isoformat(), "food", gross, float(gross) * food_rate, cnt)

        # Market orders (delivered) — commission from each vendor's rate
        mday = cast(MarketOrder.created_at, Date)
        qm = await db.execute(
            select(mday, func.count(MarketOrder.id),
                   func.coalesce(func.sum(MarketOrder.final_amount), 0),
                   func.coalesce(func.sum(MarketOrder.total_amount * MarketVendor.commission_percentage / 100), 0))
            .join(MarketVendor, MarketVendor.id == MarketOrder.vendor_id)
            .where(MarketOrder.created_at >= start_dt, MarketOrder.created_at < end_dt_exclusive,
                   MarketOrder.status == MarketOrderStatus.DELIVERED)
            .group_by(mday)
        )
        for day, cnt, gross, comm in qm.all():
            _add(day.isoformat(), "market", gross, comm, cnt)

        # Gold subscriptions (wallet payments tagged GOLD) — 100% platform income
        gday = cast(WalletTransaction.created_at, Date)
        qg = await db.execute(
            select(gday, func.count(WalletTransaction.id),
                   func.coalesce(func.sum(WalletTransaction.amount), 0))
            .where(WalletTransaction.created_at >= start_dt, WalletTransaction.created_at < end_dt_exclusive,
                   WalletTransaction.reference_id == "GOLD")
            .group_by(gday)
        )
        for day, cnt, gross in qg.all():
            _add(day.isoformat(), "gold", gross, gross, cnt)

        trend = []
        for k in days_list:
            r = rows_by_day[k]
            total = r["rides"] + r["delivery"] + r["food"] + r["market"] + r["gold"]
            trend.append({
                "date": k, "rides": r["rides"], "delivery": r["delivery"],
                "food": r["food"], "market": r["market"], "total": total,
                "commission": r["commission"],
            })
        rows_sorted = list(reversed(trend))

        names = {"rides": "Rides", "delivery": "Flash Delivery", "food": "Food",
                 "market": "Marketplace", "gold": "Gold Subscriptions"}
        services = [
            {"key": s, "name": names[s], "gmv": svc[s]["gmv"],
             "orders": svc[s]["orders"], "commission": svc[s]["commission"]}
            for s in ("rides", "delivery", "food", "market", "gold")
        ]
        gross_total = sum(s["gmv"] for s in services)
        commission_total = sum(s["commission"] for s in services)

        return {
            "totals": {
                "gross_total": gross_total,
                "commission_total": commission_total,
                "food_revenue": svc["food"]["gmv"],
                "market_revenue": svc["market"]["gmv"],
            },
            "services": services,
            "trend": trend,
            "rows": rows_sorted,
        }

    elif type == "drivers":
        # Per-day driver performance rollup
        rows_by_day = {}
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            rows_by_day[cur.isoformat()] = {
                "date": cur.isoformat(),
                "active_drivers": set(),
                "rides": 0,
                "completed": 0,
                "cancelled": 0,
                "rating_sum": 0.0,
                "rating_count": 0,
            }
            cur = cur + timedelta(days=1)

        overall = {
            "rides": 0,
            "completed": 0,
            "cancelled": 0,
            "active_drivers": set(),
            "rating_sum": 0.0,
            "rating_count": 0,
        }

        qb = await db.execute(
            select(
                bucket,
                Booking.status,
                Booking.driver_id,
                Booking.driver_rating
            )
            .where(Booking.booked_at >= start_dt, Booking.booked_at < end_dt_exclusive)
        )
        for day, status, driver_id, driver_rating in qb.all():
            key = day.isoformat()
            if key not in rows_by_day:
                continue
            r = rows_by_day[key]
            r["rides"] += 1
            overall["rides"] += 1
            
            if status == BookingStatus.COMPLETED:
                r["completed"] += 1
                overall["completed"] += 1
                if driver_rating is not None:
                    r["rating_sum"] += float(driver_rating)
                    r["rating_count"] += 1
                    overall["rating_sum"] += float(driver_rating)
                    overall["rating_count"] += 1
            elif status == BookingStatus.CANCELLED:
                r["cancelled"] += 1
                overall["cancelled"] += 1
                
            if driver_id is not None:
                r["active_drivers"].add(driver_id)
                if status == BookingStatus.COMPLETED:
                    overall["active_drivers"].add(driver_id)

        serialized_rows = []
        for r in sorted(rows_by_day.values(), key=lambda x: x["date"], reverse=True):
            total_rides = r["rides"]
            comp_rate = (r["completed"] / total_rides * 100) if total_rides > 0 else 0.0
            avg_r = (r["rating_sum"] / r["rating_count"]) if r["rating_count"] > 0 else 0.0
            serialized_rows.append({
                "date": r["date"],
                "active_drivers": len(r["active_drivers"]),
                "rides": total_rides,
                "completed": r["completed"],
                "cancelled": r["cancelled"],
                "completion_rate": round(comp_rate, 1),
                "avg_rating": round(avg_r, 2),
            })

        trend = [
            {"date": r["date"], "active_drivers": r["active_drivers"], "completion_rate": r["completion_rate"]}
            for r in serialized_rows
        ]
        trend.reverse()

        overall_comp_rate = (overall["completed"] / overall["rides"] * 100) if overall["rides"] > 0 else 0.0
        overall_avg_rating = (overall["rating_sum"] / overall["rating_count"]) if overall["rating_count"] > 0 else 0.0

        return {
            "totals": {
                "active_drivers": len(overall["active_drivers"]),
                "total_rides": overall["rides"],
                "completed": overall["completed"],
                "cancelled": overall["cancelled"],
                "completion_rate": round(overall_comp_rate, 1),
                "avg_rating": round(overall_avg_rating, 2),
            },
            "trend": trend,
            "rows": serialized_rows,
        }

    elif type == "riders":
        # Per-day rider analytics rollup
        new_users_q = await db.execute(
            select(
                cast(User.created_at, Date).label("day"),
                func.count(User.id)
            )
            .where(
                User.role == UserRole.CUSTOMER,
                User.created_at >= start_dt,
                User.created_at < end_dt_exclusive
            )
            .group_by(cast(User.created_at, Date))
        )
        new_riders_by_day = {day.isoformat(): count for day, count in new_users_q.all()}

        rows_by_day = {}
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            day_str = cur.isoformat()
            rows_by_day[day_str] = {
                "date": day_str,
                "active_riders": set(),
                "rides": 0,
                "completed": 0,
                "fare_sum": 0.0,
                "new_riders": new_riders_by_day.get(day_str, 0),
            }
            cur = cur + timedelta(days=1)

        overall = {
            "active_riders": set(),
            "rides": 0,
            "completed": 0,
            "fare_sum": 0.0,
            "new_riders": sum(new_riders_by_day.values()),
        }

        qb = await db.execute(
            select(
                bucket,
                Booking.status,
                Booking.customer_id,
                Booking.final_amount
            )
            .where(Booking.booked_at >= start_dt, Booking.booked_at < end_dt_exclusive)
        )
        for day, status, customer_id, final_amount in qb.all():
            key = day.isoformat()
            if key not in rows_by_day:
                continue
            r = rows_by_day[key]
            r["rides"] += 1
            overall["rides"] += 1
            
            if customer_id is not None:
                r["active_riders"].add(customer_id)
                overall["active_riders"].add(customer_id)
                
            if status == BookingStatus.COMPLETED:
                r["completed"] += 1
                overall["completed"] += 1
                val = float(final_amount or 0.0)
                r["fare_sum"] += val
                overall["fare_sum"] += val

        serialized_rows = []
        for r in sorted(rows_by_day.values(), key=lambda x: x["date"], reverse=True):
            avg_f = (r["fare_sum"] / r["completed"]) if r["completed"] > 0 else 0.0
            serialized_rows.append({
                "date": r["date"],
                "active_riders": len(r["active_riders"]),
                "rides": r["rides"],
                "completed": r["completed"],
                "avg_fare": round(avg_f, 2),
                "new_riders": r["new_riders"],
            })

        trend = [
            {"date": r["date"], "active_riders": r["active_riders"], "new_riders": r["new_riders"]}
            for r in serialized_rows
        ]
        trend.reverse()

        overall_avg_fare = (overall["fare_sum"] / overall["completed"]) if overall["completed"] > 0 else 0.0

        return {
            "totals": {
                "active_riders": len(overall["active_riders"]),
                "total_rides": overall["rides"],
                "completed": overall["completed"],
                "avg_fare": round(overall_avg_fare, 2),
                "new_riders": overall["new_riders"],
            },
            "trend": trend,
            "rows": serialized_rows,
        }

    elif type == "revenue":
        # Per-day revenue broken down by every service line: rides, delivery
        # (flash parcels), food and marketplace. Mirrors the commission model in
        # services/finance_service.py — rides/flash use Booking.platform_fee,
        # food/market take 20% of delivery_fee as platform commission.
        from decimal import Decimal as D
        from app.models import (
            FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus,
        )
        PLATFORM_CUT = D("0.20")

        rows_by_day = {}
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            rows_by_day[cur.isoformat()] = {
                "date": cur.isoformat(),
                "rides": 0.0, "delivery": 0.0, "food": 0.0, "market": 0.0,
                "ride_commission": 0.0, "delivery_commission": 0.0,
                "food_commission": 0.0, "market_commission": 0.0,
            }
            cur = cur + timedelta(days=1)

        services = {
            "rides":    {"gmv": 0.0, "commission": 0.0, "orders": 0},
            "delivery": {"gmv": 0.0, "commission": 0.0, "orders": 0},
            "food":     {"gmv": 0.0, "commission": 0.0, "orders": 0},
            "market":   {"gmv": 0.0, "commission": 0.0, "orders": 0},
        }

        # Rides + flash parcels (split by is_flash), completed only.
        bq = await db.execute(
            select(
                bucket,
                Booking.is_flash,
                Booking.final_amount,
                Booking.fare_amount,
                Booking.platform_fee,
            )
            .where(
                Booking.booked_at >= start_dt,
                Booking.booked_at < end_dt_exclusive,
                Booking.status == BookingStatus.COMPLETED,
            )
        )
        for day, is_flash, final_amount, fare_amount, platform_fee in bq.all():
            r = rows_by_day.get(day.isoformat())
            if r is None:
                continue
            amt = float(final_amount if final_amount is not None else (fare_amount or 0))
            fee = float(platform_fee or 0)
            line = "delivery" if is_flash else "rides"
            comm_key = "delivery_commission" if is_flash else "ride_commission"
            r[line] += amt
            r[comm_key] += fee
            services[line]["gmv"] += amt
            services[line]["commission"] += fee
            services[line]["orders"] += 1

        # Food — delivered only, commission = 20% of delivery_fee.
        food_bucket = cast(FoodOrder.created_at, Date).label("day")
        fq = await db.execute(
            select(food_bucket, FoodOrder.final_amount, FoodOrder.delivery_fee)
            .where(
                FoodOrder.created_at >= start_dt,
                FoodOrder.created_at < end_dt_exclusive,
                FoodOrder.status == FoodOrderStatus.DELIVERED,
            )
        )
        for day, final_amount, delivery_fee in fq.all():
            r = rows_by_day.get(day.isoformat())
            if r is None:
                continue
            amt = float(final_amount or 0)
            comm = float((D(str(delivery_fee or 0)) * PLATFORM_CUT).quantize(D("0.01")))
            r["food"] += amt
            r["food_commission"] += comm
            services["food"]["gmv"] += amt
            services["food"]["commission"] += comm
            services["food"]["orders"] += 1

        # Marketplace — delivered only, same delivery-fee split as food.
        market_bucket = cast(MarketOrder.created_at, Date).label("day")
        mq = await db.execute(
            select(market_bucket, MarketOrder.final_amount, MarketOrder.delivery_fee)
            .where(
                MarketOrder.created_at >= start_dt,
                MarketOrder.created_at < end_dt_exclusive,
                MarketOrder.status == MarketOrderStatus.DELIVERED,
            )
        )
        for day, final_amount, delivery_fee in mq.all():
            r = rows_by_day.get(day.isoformat())
            if r is None:
                continue
            amt = float(final_amount or 0)
            comm = float((D(str(delivery_fee or 0)) * PLATFORM_CUT).quantize(D("0.01")))
            r["market"] += amt
            r["market_commission"] += comm
            services["market"]["gmv"] += amt
            services["market"]["commission"] += comm
            services["market"]["orders"] += 1

        serialized_rows = []
        for r in sorted(rows_by_day.values(), key=lambda x: x["date"], reverse=True):
            total = r["rides"] + r["delivery"] + r["food"] + r["market"]
            commission = (
                r["ride_commission"] + r["delivery_commission"]
                + r["food_commission"] + r["market_commission"]
            )
            serialized_rows.append({
                "date": r["date"],
                "rides": round(r["rides"], 2),
                "delivery": round(r["delivery"], 2),
                "food": round(r["food"], 2),
                "market": round(r["market"], 2),
                "total": round(total, 2),
                "commission": round(commission, 2),
            })

        trend = [
            {
                "date": r["date"], "rides": r["rides"], "delivery": r["delivery"],
                "food": r["food"], "market": r["market"], "total": r["total"],
            }
            for r in serialized_rows
        ]
        trend.reverse()

        total_gmv = sum(s["gmv"] for s in services.values())
        total_commission = sum(s["commission"] for s in services.values())
        total_orders = sum(s["orders"] for s in services.values())

        return {
            "totals": {
                "gross_total": round(total_gmv, 2),
                "commission_total": round(total_commission, 2),
                "ride_revenue": round(services["rides"]["gmv"], 2),
                "delivery_revenue": round(services["delivery"]["gmv"], 2),
                "food_revenue": round(services["food"]["gmv"], 2),
                "market_revenue": round(services["market"]["gmv"], 2),
                "total_orders": total_orders,
            },
            "services": [
                {"key": "rides", "name": "Rides",
                 "gmv": round(services["rides"]["gmv"], 2),
                 "commission": round(services["rides"]["commission"], 2),
                 "orders": services["rides"]["orders"]},
                {"key": "delivery", "name": "Delivery (Parcels)",
                 "gmv": round(services["delivery"]["gmv"], 2),
                 "commission": round(services["delivery"]["commission"], 2),
                 "orders": services["delivery"]["orders"]},
                {"key": "food", "name": "Food",
                 "gmv": round(services["food"]["gmv"], 2),
                 "commission": round(services["food"]["commission"], 2),
                 "orders": services["food"]["orders"]},
                {"key": "market", "name": "Marketplace",
                 "gmv": round(services["market"]["gmv"], 2),
                 "commission": round(services["market"]["commission"], 2),
                 "orders": services["market"]["orders"]},
            ],
            "trend": trend,
            "rows": serialized_rows,
        }

    elif type in ("revenue_rides", "revenue_delivery", "revenue_food", "revenue_market"):
        # ── Single-service revenue detail ──────────────────────────────────
        from decimal import Decimal as D
        from app.models import (
            FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus,
        )
        PLATFORM_CUT = D("0.20")

        rows_by_day = {}
        days_list = []
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            k = cur.isoformat()
            rows_by_day[k] = {"date": k, "gmv": 0.0, "commission": 0.0, "orders": 0}
            days_list.append(k)
            cur = cur + timedelta(days=1)

        if type == "revenue_rides":
            bday = cast(Booking.booked_at, Date)
            bq = await db.execute(
                select(bday, Booking.final_amount, Booking.fare_amount, Booking.platform_fee)
                .where(
                    Booking.booked_at >= start_dt,
                    Booking.booked_at < end_dt_exclusive,
                    Booking.status == BookingStatus.COMPLETED,
                    Booking.is_flash == False,  # noqa: E712
                )
            )
            for day, final_amount, fare_amount, platform_fee in bq.all():
                r = rows_by_day.get(day.isoformat())
                if r is None:
                    continue
                amt = float(final_amount if final_amount is not None else (fare_amount or 0))
                fee = float(platform_fee or 0)
                r["gmv"] += amt
                r["commission"] += fee
                r["orders"] += 1

        elif type == "revenue_delivery":
            bday = cast(Booking.booked_at, Date)
            bq = await db.execute(
                select(bday, Booking.final_amount, Booking.fare_amount, Booking.platform_fee)
                .where(
                    Booking.booked_at >= start_dt,
                    Booking.booked_at < end_dt_exclusive,
                    Booking.status == BookingStatus.COMPLETED,
                    Booking.is_flash == True,  # noqa: E712
                )
            )
            for day, final_amount, fare_amount, platform_fee in bq.all():
                r = rows_by_day.get(day.isoformat())
                if r is None:
                    continue
                amt = float(final_amount if final_amount is not None else (fare_amount or 0))
                fee = float(platform_fee or 0)
                r["gmv"] += amt
                r["commission"] += fee
                r["orders"] += 1

        elif type == "revenue_food":
            food_bucket = cast(FoodOrder.created_at, Date).label("day")
            fq = await db.execute(
                select(food_bucket, FoodOrder.final_amount, FoodOrder.delivery_fee)
                .where(
                    FoodOrder.created_at >= start_dt,
                    FoodOrder.created_at < end_dt_exclusive,
                    FoodOrder.status == FoodOrderStatus.DELIVERED,
                )
            )
            for day, final_amount, delivery_fee in fq.all():
                r = rows_by_day.get(day.isoformat())
                if r is None:
                    continue
                amt = float(final_amount or 0)
                comm = float((D(str(delivery_fee or 0)) * PLATFORM_CUT).quantize(D("0.01")))
                r["gmv"] += amt
                r["commission"] += comm
                r["orders"] += 1

        elif type == "revenue_market":
            market_bucket = cast(MarketOrder.created_at, Date).label("day")
            mq = await db.execute(
                select(market_bucket, MarketOrder.final_amount, MarketOrder.delivery_fee)
                .where(
                    MarketOrder.created_at >= start_dt,
                    MarketOrder.created_at < end_dt_exclusive,
                    MarketOrder.status == MarketOrderStatus.DELIVERED,
                )
            )
            for day, final_amount, delivery_fee in mq.all():
                r = rows_by_day.get(day.isoformat())
                if r is None:
                    continue
                amt = float(final_amount or 0)
                comm = float((D(str(delivery_fee or 0)) * PLATFORM_CUT).quantize(D("0.01")))
                r["gmv"] += amt
                r["commission"] += comm
                r["orders"] += 1

        # Build trend (chronological) and rows (newest-first)
        trend = []
        for k in days_list:
            r = rows_by_day[k]
            trend.append({"date": r["date"], "gmv": round(r["gmv"], 2), "commission": round(r["commission"], 2)})
        rows_sorted = list(reversed(trend))

        total_gmv = sum(r["gmv"] for r in trend)
        total_comm = sum(r["commission"] for r in trend)
        total_orders = sum(rows_by_day[k]["orders"] for k in days_list)

        return {
            "totals": {
                "gross_total": round(total_gmv, 2),
                "commission_total": round(total_comm, 2),
                "total_orders": total_orders,
            },
            "trend": trend,
            "rows": rows_sorted,
        }

    else:
        # Per-day per-status rollup
        q = await db.execute(
            select(
                bucket,
                Booking.status,
                func.count(Booking.id),
                func.coalesce(func.sum(Booking.final_amount), 0),
                func.coalesce(func.sum(Booking.platform_fee), 0),
                func.count(distinct(Booking.customer_id)),
                func.count(distinct(Booking.driver_id)),
            )
            .where(Booking.booked_at >= start_dt, Booking.booked_at < end_dt_exclusive)
            .group_by(bucket, Booking.status)
            .order_by(bucket)
        )
        rows_by_day: dict[str, dict] = {}
        overall = {"rides": 0, "completed": 0, "cancelled": 0, "revenue": D("0"), "platform": D("0")}
        drivers_set: set[int] = set()

        # Walk every day in range so the chart and table have zero-filled rows.
        cur = start_dt.date()
        end_d = (end_dt_exclusive - timedelta(seconds=1)).date()
        while cur <= end_d:
            rows_by_day[cur.isoformat()] = {
                "date": cur.isoformat(),
                "rides": 0,
                "completed": 0,
                "cancelled": 0,
                "revenue": D("0"),
                "drivers": set(),
                "riders": set(),
            }
            cur = cur + timedelta(days=1)

        for day, status, n, revenue, platform, customers, drivers in q.all():
            key = day.isoformat()
            r = rows_by_day.setdefault(key, {
                "date": key, "rides": 0, "completed": 0, "cancelled": 0,
                "revenue": D("0"), "drivers": set(), "riders": set(),
            })
            r["rides"] += n
            overall["rides"] += n
            if status == BookingStatus.COMPLETED:
                r["completed"] += n
                r["revenue"] += revenue
                overall["completed"] += n
                overall["revenue"] += revenue
                overall["platform"] += platform
            elif status == BookingStatus.CANCELLED:
                r["cancelled"] += n
                overall["cancelled"] += n

        # Distinct riders/drivers per day need a second pass (the group_by-status
        # query above can't aggregate distinct customer_id correctly because the
        # status dimension splits the same customer's bookings across rows).
        # The per-day "drivers" column counts everyone who took a trip that day
        # (any status). The top-level "Active drivers" KPI only counts drivers
        # who actually completed a ride — that's the meaningful business metric.
        qd = await db.execute(
            select(bucket, Booking.status, Booking.customer_id, Booking.driver_id)
            .where(Booking.booked_at >= start_dt, Booking.booked_at < end_dt_exclusive)
        )
        for day, status, cid, did in qd.all():
            key = day.isoformat()
            if key not in rows_by_day:
                continue
            if cid is not None:
                rows_by_day[key]["riders"].add(cid)
            if did is not None:
                rows_by_day[key]["drivers"].add(did)
                if status == BookingStatus.COMPLETED:
                    drivers_set.add(did)

        rows_sorted = sorted(rows_by_day.values(), key=lambda r: r["date"], reverse=True)
        serialized_rows = [
            {
                "date": r["date"],
                "rides": r["rides"],
                "completed": r["completed"],
                "cancelled": r["cancelled"],
                "revenue": float(r["revenue"]),
                "drivers": len(r["drivers"]),
                "riders": len(r["riders"]),
            }
            for r in rows_sorted
        ]
        trend = [
            {"date": r["date"], "rides": r["completed"], "revenue": r["revenue"]}
            for r in serialized_rows
        ]
        trend.reverse()  # chart wants oldest → newest

        return {
            "totals": {
                "admin_net": float(overall["platform"]),
                "total_rides": overall["rides"],
                "active_drivers": len(drivers_set),
                "gross_bookings": float(overall["revenue"]),
                "completed": overall["completed"],
                "cancelled": overall["cancelled"],
            },
            "trend": trend,
            "rows": serialized_rows,
        }


def _default_reports_range() -> tuple[datetime, datetime]:
    end_dt = datetime.now(timezone.utc).replace(hour=23, minute=59, second=59, microsecond=0)
    start_dt = (end_dt - timedelta(days=29)).replace(hour=0, minute=0, second=0, microsecond=0)
    return start_dt, end_dt


@router.get("/reports", response_class=HTMLResponse)
async def admin_reports(
    request: Request,
    start: str = "",
    end: str = "",
    type: str = "summary",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    default_start, default_end = _default_reports_range()
    start_dt = _parse_iso_date_or(default_start, start).replace(hour=0, minute=0, second=0, microsecond=0)
    end_dt = _parse_iso_date_or(default_end, end).replace(hour=23, minute=59, second=59, microsecond=0)
    if end_dt < start_dt:
        start_dt, end_dt = end_dt, start_dt
    data = await _reports_aggregate(db, start_dt, end_dt + timedelta(seconds=1), type)

    return templates.TemplateResponse(
        request,
        "reports.html",
        {
            "request": request,
            "active_page": "reports",
            "report_type": type,
            "start_date": start_dt.strftime("%Y-%m-%d"),
            "end_date": end_dt.strftime("%Y-%m-%d"),
            "data": data,
        },
    )


@router.get("/reports/data")
async def admin_reports_data(
    start: str = "",
    end: str = "",
    type: str = "summary",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    default_start, default_end = _default_reports_range()
    start_dt = _parse_iso_date_or(default_start, start).replace(hour=0, minute=0, second=0, microsecond=0)
    end_dt = _parse_iso_date_or(default_end, end).replace(hour=23, minute=59, second=59, microsecond=0)
    if end_dt < start_dt:
        start_dt, end_dt = end_dt, start_dt
    data = await _reports_aggregate(db, start_dt, end_dt + timedelta(seconds=1), type)
    return {
        **data,
        "start_date": start_dt.strftime("%Y-%m-%d"),
        "end_date": end_dt.strftime("%Y-%m-%d"),
    }


@router.get("/promotions", response_class=HTMLResponse)
async def admin_promotions(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import PromoCode

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(PromoCode.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(PromoCode)
        .order_by(PromoCode.id.desc())
        .offset(offset)
        .limit(limit)
    )
    promos = q.scalars().all()

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "promotions.html",
        {
            "request": request,
            "active_page": "promotions",
            "promos": promos,
            "page": page,
            "total_pages": total_pages,
            "total_promos": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



def _parse_admin_date(s: str):
    s = (s or "").strip()
    if not s:
        return None
    # Form input type="date" sends YYYY-MM-DD
    try:
        return datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid date '{s}', expected YYYY-MM-DD")


@router.post("/promotions/new")
async def admin_promotions_new(
    code: str = Form(...),
    description: str = Form(""),
    category: str = Form("all"),
    discount_type: str = Form("percentage"),
    discount_value: float = Form(...),
    min_order_amount: float = Form(0),
    max_discount: str = Form(""),
    usage_limit: str = Form(""),
    valid_from: str = Form(""),
    valid_to: str = Form(""),
    is_active: str = Form("on"),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import PromoCode
    from decimal import Decimal

    norm_code = code.strip().upper()
    if not norm_code:
        raise HTTPException(status_code=400, detail="Code is required")
    if discount_type not in ("percentage", "fixed"):
        raise HTTPException(status_code=400, detail="discount_type must be 'percentage' or 'fixed'")

    dup = await db.execute(select(PromoCode).where(PromoCode.code == norm_code))
    if dup.scalars().first():
        raise HTTPException(status_code=400, detail=f"Promo code '{norm_code}' already exists")

    norm_cat = (category or "all").strip().lower()
    if norm_cat not in ("all", "rides", "food", "market"):
        raise HTTPException(status_code=400, detail="category must be all/rides/food/market")

    db.add(PromoCode(
        code=norm_code,
        description=description.strip() or None,
        category=norm_cat,
        discount_type=discount_type,
        discount_value=Decimal(str(discount_value)),
        min_order_amount=Decimal(str(min_order_amount or 0)),
        max_discount=Decimal(str(max_discount)) if max_discount.strip() else None,
        usage_limit=int(usage_limit) if usage_limit.strip().isdigit() else None,
        used_count=0,
        valid_from=_parse_admin_date(valid_from),
        valid_to=_parse_admin_date(valid_to),
        is_active=(is_active == "on"),
    ))
    await db.commit()
    return RedirectResponse(url="/admin/promotions", status_code=303)


@router.post("/promotions/{promo_id}/edit")
async def admin_promotions_edit(
    promo_id: int,
    description: str = Form(""),
    category: str = Form("all"),
    discount_type: str = Form("percentage"),
    discount_value: float = Form(...),
    min_order_amount: float = Form(0),
    max_discount: str = Form(""),
    usage_limit: str = Form(""),
    valid_from: str = Form(""),
    valid_to: str = Form(""),
    is_active: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import PromoCode
    from decimal import Decimal

    if discount_type not in ("percentage", "fixed"):
        raise HTTPException(status_code=400, detail="discount_type must be 'percentage' or 'fixed'")
    norm_cat = (category or "all").strip().lower()
    if norm_cat not in ("all", "rides", "food", "market"):
        raise HTTPException(status_code=400, detail="category must be all/rides/food/market")

    q = await db.execute(select(PromoCode).where(PromoCode.id == promo_id))
    p = q.scalars().first()
    if not p:
        raise HTTPException(status_code=404, detail="Promo not found")

    p.description = description.strip() or None
    p.category = norm_cat
    p.discount_type = discount_type
    p.discount_value = Decimal(str(discount_value))
    p.min_order_amount = Decimal(str(min_order_amount or 0))
    p.max_discount = Decimal(str(max_discount)) if max_discount.strip() else None
    p.usage_limit = int(usage_limit) if usage_limit.strip().isdigit() else None
    p.valid_from = _parse_admin_date(valid_from)
    p.valid_to = _parse_admin_date(valid_to)
    p.is_active = (is_active == "on")
    await db.commit()
    return RedirectResponse(url="/admin/promotions", status_code=303)


@router.post("/promotions/{promo_id}/toggle")
async def admin_promotions_toggle(
    promo_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import PromoCode

    q = await db.execute(select(PromoCode).where(PromoCode.id == promo_id))
    p = q.scalars().first()
    if not p:
        raise HTTPException(status_code=404, detail="Promo not found")
    p.is_active = not bool(p.is_active)
    await db.commit()
    return RedirectResponse(url="/admin/promotions", status_code=303)


@router.post("/promotions/{promo_id}/delete")
async def admin_promotions_delete(
    promo_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import PromoCode

    q = await db.execute(select(PromoCode).where(PromoCode.id == promo_id))
    p = q.scalars().first()
    if not p:
        raise HTTPException(status_code=404, detail="Promo not found")
    # `used_count` may already be > 0; we still allow deletion because
    # bookings reference the code by string, not FK. The audit trail
    # lives on Booking.promo_code.
    await db.delete(p)
    await db.commit()
    return RedirectResponse(url="/admin/promotions", status_code=303)


@router.get("/complaints", response_class=HTMLResponse)
async def admin_complaints(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Complaint

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(Complaint.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Complaint)
        .order_by(Complaint.id.desc())
        .offset(offset)
        .limit(limit)
    )
    complaints = q.scalars().all()

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "complaints.html",
        {
            "request": request,
            "active_page": "complaints",
            "complaints": complaints,
            "page": page,
            "total_pages": total_pages,
            "total_complaints": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



# ---------- Live Tracking ----------
@router.get("/live-tracking", response_class=HTMLResponse)
async def admin_live_tracking(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    totals_q = await db.execute(
        select(
            func.count(Driver.id),
            func.count(Driver.id).filter(Driver.is_online == True),  # noqa: E712
        )
    )
    total, online = totals_q.one()
    return templates.TemplateResponse(
        request,
        "live_tracking.html",
        {
            "request": request,
            "active_page": "live-tracking",
            "total_drivers": total,
            "online_drivers": online,
            "offline_drivers": (total or 0) - (online or 0),
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY or "",
        },
    )


@router.get("/live-tracking/feed")
async def admin_live_tracking_feed(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """JSON feed for the live-tracking page.

    Returns ALL approved drivers (lat/lng may be null) so the page can render
    every driver in the under-map list, with their online/offline status.
    The map itself only plots drivers that have a known location.
    """

    q = await db.execute(
        select(Driver)
        .options(selectinload(Driver.user))
        .where(Driver.status == DriverStatus.APPROVED)
        .order_by(Driver.id)
    )
    drivers = q.scalars().all()

    totals_q = await db.execute(
        select(
            func.count(Driver.id),
            func.count(Driver.id).filter(Driver.is_online == True),  # noqa: E712
        )
    )
    total, online = totals_q.one()

    active_q = await db.execute(
        select(func.count(Booking.id)).where(
            Booking.status.in_([
                BookingStatus.ACCEPTED, BookingStatus.ARRIVED, BookingStatus.STARTED,
            ])
        )
    )
    active_bookings_count = active_q.scalar_one()

    return {
        "drivers": [
            {
                "id": d.id,
                "name": (d.user.full_name if d.user else "Driver") or "Driver",
                "phone": (d.user.phone_number if d.user else "") or "",
                "vehicle_type": d.vehicle_type or "car",
                "vehicle_number": d.vehicle_number or "",
                "lat": float(d.current_lat) if d.current_lat is not None else None,
                "lng": float(d.current_lng) if d.current_lng is not None else None,
                "is_online": bool(d.is_online),
                "last_seen": d.last_location_update.isoformat() if d.last_location_update else None,
            }
            for d in drivers
        ],
        "totals": {
            "online": online or 0,
            "offline": (total or 0) - (online or 0),
            "total": total or 0,
            "active_bookings": active_bookings_count or 0,
        },
        "server_time": datetime.now(timezone.utc).isoformat(),
    }


# ---------- Help & Support Center ----------
SUPPORT_STATUSES = ["open", "in_progress", "resolved", "closed"]


def _normalize_status(raw: str | None) -> str:
    """Treat legacy 'pending' rows as 'open' for display."""
    if not raw or raw == "pending":
        return "open"
    return raw


# ---------- BRD: Incident reports (driver-side) ----------
@router.get("/incidents", response_class=HTMLResponse)
async def admin_incidents(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Incident

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(Incident.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Incident)
        .options(selectinload(Incident.reporter))
        .order_by(Incident.id.desc())
        .offset(offset)
        .limit(limit)
    )
    incidents = q.scalars().all()

    counts_q = await db.execute(
        select(Incident.kind, func.count(Incident.id))
        .where(Incident.status == "active")
        .group_by(Incident.kind)
    )
    counts = {k: n for k, n in counts_q.all()}

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request,
        "incidents.html",
        {
            "request": request,
            "active_page": "incidents",
            "incidents": incidents,
            "counts": counts,
            "page": page,
            "total_pages": total_pages,
            "total_incidents": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



@router.post("/incidents/{incident_id}/dismiss")
async def admin_incidents_dismiss(
    incident_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Incident
    q = await db.execute(select(Incident).where(Incident.id == incident_id))
    inc = q.scalars().first()
    if not inc:
        raise HTTPException(status_code=404, detail="Incident not found")
    inc.status = "dismissed"
    await db.commit()
    return RedirectResponse(url="/admin/incidents", status_code=303)


# ---------- Website contact-form inbox ----------
@router.get("/inbox", response_class=HTMLResponse)
async def admin_inbox(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.api.v1.public import ContactMessage

    rows = (
        await db.execute(
            select(ContactMessage).order_by(ContactMessage.id.desc()).limit(500)
        )
    ).scalars().all()
    total = (await db.execute(select(func.count(ContactMessage.id)))).scalar() or 0
    unread = (
        await db.execute(
            select(func.count(ContactMessage.id)).where(
                ContactMessage.is_read == False  # noqa: E712
            )
        )
    ).scalar() or 0
    return templates.TemplateResponse(
        request,
        "inbox.html",
        {
            "request": request,
            "active_page": "inbox",
            "messages": rows,
            "total": total,
            "unread": unread,
            "read": total - unread,
        },
    )


@router.post("/inbox/{msg_id}/read")
async def admin_inbox_toggle_read(
    msg_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.api.v1.public import ContactMessage

    m = (
        await db.execute(select(ContactMessage).where(ContactMessage.id == msg_id))
    ).scalars().first()
    if not m:
        raise HTTPException(status_code=404, detail="Message not found")
    m.is_read = not bool(m.is_read)
    await db.commit()
    return RedirectResponse(url="/admin/inbox", status_code=303)


@router.post("/inbox/{msg_id}/delete")
async def admin_inbox_delete(
    msg_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.api.v1.public import ContactMessage

    m = (
        await db.execute(select(ContactMessage).where(ContactMessage.id == msg_id))
    ).scalars().first()
    if not m:
        raise HTTPException(status_code=404, detail="Message not found")
    await db.delete(m)
    await db.commit()
    return RedirectResponse(url="/admin/inbox", status_code=303)


# ---------- Corporate demo requests ----------
@router.get("/demo-requests", response_class=HTMLResponse)
async def admin_demo_requests(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.api.v1.public import DemoRequest

    rows = (
        await db.execute(
            select(DemoRequest).order_by(DemoRequest.id.desc()).limit(500)
        )
    ).scalars().all()
    total = (await db.execute(select(func.count(DemoRequest.id)))).scalar() or 0
    unread = (
        await db.execute(
            select(func.count(DemoRequest.id)).where(
                DemoRequest.is_read == False
            )
        )
    ).scalar() or 0
    return templates.TemplateResponse(
        request,
        "demo_requests.html",
        {
            "request": request,
            "active_page": "demo_requests",
            "requests": rows,
            "total": total,
            "unread": unread,
            "read": total - unread,
        },
    )


@router.post("/demo-requests/{req_id}/read")
async def admin_demo_request_toggle_read(
    req_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.api.v1.public import DemoRequest

    r = (
        await db.execute(select(DemoRequest).where(DemoRequest.id == req_id))
    ).scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Request not found")
    r.is_read = not bool(r.is_read)
    await db.commit()
    return RedirectResponse(url="/admin/demo-requests", status_code=303)


@router.post("/demo-requests/{req_id}/delete")
async def admin_demo_request_delete(
    req_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.api.v1.public import DemoRequest

    r = (
        await db.execute(select(DemoRequest).where(DemoRequest.id == req_id))
    ).scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Request not found")
    await db.delete(r)
    await db.commit()
    return RedirectResponse(url="/admin/demo-requests", status_code=303)





# ---------- Live notification feed for the top-bar bell ----------
@router.get("/notif-feed")
async def admin_notif_feed(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Real-time admin alerts for the bell popup. Read-only aggregate over
    existing tables — adds nothing to and changes nothing in the rest of the app."""
    from app.api.v1.public import ContactMessage, DemoRequest
    from app.models import Complaint

    def plural(n, word):
        return f"{n} {word}" + ("s" if n != 1 else "")

    items = []

    unread_msgs = (
        await db.execute(
            select(func.count(ContactMessage.id)).where(
                ContactMessage.is_read == False  # noqa: E712
            )
        )
    ).scalar() or 0
    if unread_msgs:
        items.append({
            "title": plural(unread_msgs, "new website message"),
            "subtitle": "From the contact form",
            "icon": "fa-inbox", "url": "/admin/inbox", "count": unread_msgs,
        })

    unread_demos = (
        await db.execute(
            select(func.count(DemoRequest.id)).where(
                DemoRequest.is_read == False
            )
        )
    ).scalar() or 0
    if unread_demos:
        items.append({
            "title": plural(unread_demos, "corporate demo request"),
            "subtitle": "From business page",
            "icon": "fa-laptop-code", "url": "/admin/demo-requests", "count": unread_demos,
        })


    pending_drivers = (
        await db.execute(
            select(func.count(Driver.id)).where(Driver.status == DriverStatus.PENDING)
        )
    ).scalar() or 0
    if pending_drivers:
        items.append({
            "title": plural(pending_drivers, "driver approval") + " pending",
            "subtitle": "Review & approve drivers",
            "icon": "fa-user-clock", "url": "/admin/drivers", "count": pending_drivers,
        })

    open_tickets = (
        await db.execute(
            select(func.count(Complaint.id)).where(Complaint.status == "open")
        )
    ).scalar() or 0
    if open_tickets:
        items.append({
            "title": plural(open_tickets, "open support ticket"),
            "subtitle": "Needs a response",
            "icon": "fa-life-ring", "url": "/admin/support", "count": open_tickets,
        })

    items.sort(key=lambda x: x["count"], reverse=True)
    return {"total": sum(i["count"] for i in items), "items": items}


# ---------- BRD: Driver document verification ----------
@router.post("/drivers/{driver_id}/documents/{doc_id}/verify")
async def admin_driver_doc_verify(
    driver_id: int,
    doc_id: int,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    from app.models import DriverDocument
    q = await db.execute(
        select(DriverDocument).where(
            DriverDocument.id == doc_id, DriverDocument.driver_id == driver_id
        )
    )
    doc = q.scalars().first()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    doc.is_verified = True
    doc.verified_by = admin.id
    doc.verified_at = datetime.now(timezone.utc)
    await db.commit()
    return RedirectResponse(url=f"/admin/drivers/{driver_id}/edit", status_code=303)


@router.post("/drivers/{driver_id}/documents/{doc_id}/reject")
async def admin_driver_doc_reject(
    driver_id: int,
    doc_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import DriverDocument
    q = await db.execute(
        select(DriverDocument).where(
            DriverDocument.id == doc_id, DriverDocument.driver_id == driver_id
        )
    )
    doc = q.scalars().first()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    doc.is_verified = False
    doc.verified_by = None
    doc.verified_at = None
    await db.commit()
    return RedirectResponse(url=f"/admin/drivers/{driver_id}/edit", status_code=303)


# ---------- BRD: CD-17 — Emergency alerts ----------
@router.get("/emergencies", response_class=HTMLResponse)
async def admin_emergencies(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import EmergencyAlert

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(EmergencyAlert.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(EmergencyAlert)
        .options(selectinload(EmergencyAlert.user))
        .order_by(EmergencyAlert.id.desc())
        .offset(offset)
        .limit(limit)
    )
    alerts = q.scalars().all()

    # Tallies for the header cards
    counts_q = await db.execute(
        select(EmergencyAlert.status, func.count(EmergencyAlert.id))
        .group_by(EmergencyAlert.status)
    )
    counts = {s: n for s, n in counts_q.all()}

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request,
        "emergencies.html",
        {
            "request": request,
            "active_page": "emergencies",
            "alerts": alerts,
            "counts": counts,
            "page": page,
            "total_pages": total_pages,
            "total_emergencies": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
            "open_count": counts.get("open", 0),
            "acknowledged_count": counts.get("acknowledged", 0),
            "resolved_count": counts.get("resolved", 0) + counts.get("dismissed", 0),
            "total_count": total,
        },
    )


@router.post("/emergencies/{alert_id}/{action}")
async def admin_emergencies_action(
    alert_id: int,
    action: str,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    from app.models import EmergencyAlert
    if action not in ("acknowledge", "resolve", "dismiss"):
        raise HTTPException(status_code=400, detail="Unknown action")
    q = await db.execute(select(EmergencyAlert).where(EmergencyAlert.id == alert_id))
    a = q.scalars().first()
    if not a:
        raise HTTPException(status_code=404, detail="Alert not found")
    now = datetime.now(timezone.utc)
    if action == "acknowledge":
        a.status = "acknowledged"
        a.acknowledged_by = admin.id
        a.acknowledged_at = now
    elif action == "resolve":
        a.status = "resolved"
        a.resolved_at = now
    else:
        a.status = "dismissed"
        a.resolved_at = now
    await db.commit()
    return RedirectResponse(url="/admin/emergencies", status_code=303)


@router.get("/support", response_class=HTMLResponse)
async def admin_support(
    request: Request,
    q: str = "",
    status: str = "",
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Complaint, ComplaintMessage

    base = (
        select(Complaint)
        .options(
            selectinload(Complaint.user),
            selectinload(Complaint.messages).selectinload(ComplaintMessage.sender),
        )
    )
    if status in SUPPORT_STATUSES:
        if status == "open":
            base = base.where(Complaint.status.in_(["open", "pending", None]))
        else:
            base = base.where(Complaint.status == status)
    if q:
        like = f"%{q}%"
        base = base.where(
            (Complaint.subject.ilike(like))
            | (User.full_name.ilike(like))
            | (User.phone_number.ilike(like))
        ).join(User, User.id == Complaint.user_id)

    base = base.order_by(Complaint.id.desc()).limit(200)
    result = await db.execute(base)
    tickets = result.scalars().all()

    # Pre-serialize for the template — Jinja can't do list comps inside dict literals.
    tickets_payload = []
    for t in tickets:
        tickets_payload.append({
            "id": t.id,
            "subject": t.subject or "",
            "category": t.category or "",
            "description": t.description or "",
            "status": _normalize_status(t.status),
            "user_name": (t.user.full_name if t.user else "") or "",
            "user_phone": (t.user.phone_number if t.user else "") or "",
            "created_at": t.created_at.strftime("%Y-%m-%d %H:%M") if t.created_at else "",
            "messages": [
                {
                    "id": m.id,
                    "sender_role": m.sender_role,
                    "sender_name": (m.sender.full_name if m.sender else "") or "",
                    "body": m.body,
                    "created_at": m.created_at.strftime("%Y-%m-%d %H:%M") if m.created_at else "",
                }
                for m in (t.messages or [])
            ],
        })

    # Unfiltered counts for the stat cards
    counts_q = await db.execute(
        select(Complaint.status, func.count(Complaint.id)).group_by(Complaint.status)
    )
    raw_counts: dict[str, int] = {}
    for raw, n in counts_q.all():
        raw_counts[_normalize_status(raw)] = raw_counts.get(_normalize_status(raw), 0) + n
    total = sum(raw_counts.values())

    return templates.TemplateResponse(
        request,
        "support.html",
        {
            "request": request,
            "active_page": "support",
            "tickets": tickets,
            "tickets_payload": tickets_payload,
            "normalize_status": _normalize_status,
            "total": total,
            "open_count": raw_counts.get("open", 0),
            "in_progress_count": raw_counts.get("in_progress", 0),
            "resolved_count": raw_counts.get("resolved", 0),
            "closed_count": raw_counts.get("closed", 0),
            "filter_q": q,
            "filter_status": status,
            "statuses": SUPPORT_STATUSES,
        },
    )


@router.get("/support/{ticket_id}/messages")
async def admin_support_messages(
    ticket_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Read-only JSON feed of a ticket's messages, for live polling in the UI."""
    from app.models import Complaint, ComplaintMessage

    res = await db.execute(
        select(Complaint)
        .options(selectinload(Complaint.messages).selectinload(ComplaintMessage.sender))
        .where(Complaint.id == ticket_id)
    )
    t = res.scalars().first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket not found")
    return {
        "status": _normalize_status(t.status),
        "messages": [
            {
                "id": m.id,
                "sender_role": m.sender_role,
                "sender_name": (m.sender.full_name if m.sender else "") or "",
                "body": m.body,
                "created_at": m.created_at.strftime("%Y-%m-%d %H:%M") if m.created_at else "",
            }
            for m in (t.messages or [])
        ],
    }


@router.post("/support/{ticket_id}/status")
async def admin_support_set_status(
    ticket_id: int,
    status: str = Form(...),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    from app.models import Complaint
    from app.services.ws_manager import manager

    if status not in SUPPORT_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid status")
    res = await db.execute(select(Complaint).where(Complaint.id == ticket_id))
    t = res.scalars().first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket not found")
    t.status = status
    if status == "resolved" and not t.resolved_at:
        t.resolved_at = datetime.now(timezone.utc)
    if status != "resolved":
        # Re-opening clears the resolved timestamp so the metric stays honest
        t.resolved_at = None
    await db.commit()
    # Push to the ticket owner so their app can refresh the badge
    if t.user_id:
        await manager.send(t.user_id, "support_ticket_update", {
            "ticket_id": t.id,
            "status": t.status,
        })
    return RedirectResponse(url="/admin/support", status_code=303)


@router.post("/support/{ticket_id}/reply")
async def admin_support_reply(
    ticket_id: int,
    request: Request,
    body: str = Form(...),
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    from app.models import Complaint, ComplaintMessage
    from app.services.ws_manager import manager

    text = body.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Reply body is required")
    res = await db.execute(select(Complaint).where(Complaint.id == ticket_id))
    t = res.scalars().first()
    if not t:
        raise HTTPException(status_code=404, detail="Ticket not found")

    msg = ComplaintMessage(
        complaint_id=t.id,
        sender_user_id=admin.id,
        sender_role="admin",
        body=text,
    )
    db.add(msg)
    # Admin replying nudges the ticket out of "open" if it was sitting idle
    if t.status in (None, "", "pending", "open"):
        t.status = "in_progress"
    await db.commit()
    await db.refresh(msg)

    payload = {
        "ticket_id": t.id,
        "message_id": msg.id,
        "sender_role": "admin",
        "body": msg.body,
        "created_at": msg.created_at.isoformat() if msg.created_at else None,
    }
    if t.user_id:
        await manager.send(t.user_id, "support_message", payload)
    # Broadcast to any admin viewing the support panel (instant multi-admin sync).
    try:
        await manager.publish("admin_live", "support_message", payload)
    except Exception:
        pass

    # Return JSON when the request came from the modal's fetch() so we avoid
    # an unnecessary redirect → full-page HTML roundtrip.
    accept = request.headers.get("accept", "")
    if "application/json" in accept:
        from fastapi.responses import JSONResponse
        return JSONResponse({"ok": True, "message_id": msg.id, "created_at": payload["created_at"]})
    return RedirectResponse(url="/admin/support", status_code=303)


# ---------------------------------------------------------------------------
# Finance pages — admin-only deep dive into platform revenue + entity payouts.
# Aggregation logic lives in services/finance_service.py; routes here are
# thin shims that fetch and template-render.
# ---------------------------------------------------------------------------

from app.services import finance_service as fin  # noqa: E402


@router.get("/finance", response_class=HTMLResponse)
async def admin_finance(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.overview(db)
    return templates.TemplateResponse(
        request, "finance.html",
        {"request": request, "active_page": "finance", "fin": data},
    )


@router.get("/withdrawals", response_class=HTMLResponse)
async def admin_withdrawals(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.get_withdrawals_data(db, page=page, page_size=20)
    return templates.TemplateResponse(
        request, "withdrawals.html",
        {
            "request": request,
            "active_page": "withdrawals",
            "total_pending": data["total_pending"],
            "rows": data["rows"],
            "history": data["history"],
            "total_pages": data["total_pages"],
            "start_idx": data["start_idx"],
            "end_idx": data["end_idx"],
            "total_drivers": data["total_drivers"],
            "page": data["page"],
            "page_range": data["page_range"],
        },
    )


@router.post("/withdrawals/{driver_id}/pay")
async def admin_withdrawals_pay(
    driver_id: int,
    amount: float = Form(...),
    note: str = Form("Manual payout"),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    await fin.execute_driver_payout(db, driver_id, Decimal(str(amount)), note)
    return RedirectResponse(url="/admin/withdrawals", status_code=303)


@router.get("/finance/drivers", response_class=HTMLResponse)
async def admin_finance_drivers(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.driver_finance_table(db)
    limit = 50
    offset = (page - 1) * limit
    total = len(rows)
    total_pages = (total + limit - 1) // limit
    paginated_rows = rows[offset:offset+limit]

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "finance_drivers.html",
        {
            "request": request,
            "active_page": "finance",
            "rows": paginated_rows,
            "page": page,
            "total_pages": total_pages,
            "total_drivers": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


@router.get("/finance/drivers/{driver_id}", response_class=HTMLResponse)
async def admin_finance_driver_detail(
    driver_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.driver_finance_detail(db, driver_id)
    if data is None:
        raise HTTPException(status_code=404, detail="Driver not found")
    return templates.TemplateResponse(
        request, "finance_driver_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


@router.post("/finance/drivers/{driver_id}/pay_incentive")
async def admin_finance_driver_pay_incentive(
    driver_id: int,
    amount: float = Form(...),
    note: str = Form("Incentive Payment"),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    await fin.execute_driver_payout(db, driver_id, Decimal(str(amount)), note)
    return RedirectResponse(url=f"/admin/finance/drivers/{driver_id}", status_code=303)



@router.get("/finance/customers", response_class=HTMLResponse)
async def admin_finance_customers(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.customer_finance_table(db)
    limit = 50
    offset = (page - 1) * limit
    total = len(rows)
    total_pages = (total + limit - 1) // limit
    paginated_rows = rows[offset:offset+limit]

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "finance_customers.html",
        {
            "request": request,
            "active_page": "finance",
            "rows": paginated_rows,
            "page": page,
            "total_pages": total_pages,
            "total_customers": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


@router.get("/finance/customers/{customer_id}", response_class=HTMLResponse)
async def admin_finance_customer_detail(
    customer_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.customer_finance_detail(db, customer_id)
    if data is None:
        raise HTTPException(status_code=404, detail="Customer not found")
    return templates.TemplateResponse(
        request, "finance_customer_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


@router.get("/finance/restaurants", response_class=HTMLResponse)
async def admin_finance_restaurants(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.restaurant_finance_table(db)
    limit = 50
    offset = (page - 1) * limit
    total = len(rows)
    total_pages = (total + limit - 1) // limit
    paginated_rows = rows[offset:offset+limit]

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "finance_restaurants.html",
        {
            "request": request,
            "active_page": "finance",
            "rows": paginated_rows,
            "page": page,
            "total_pages": total_pages,
            "total_restaurants": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


@router.get("/finance/restaurants/{restaurant_id}", response_class=HTMLResponse)
async def admin_finance_restaurant_detail(
    restaurant_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.restaurant_finance_detail(db, restaurant_id)
    if data is None:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    return templates.TemplateResponse(
        request, "finance_restaurant_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


@router.get("/finance/market", response_class=HTMLResponse)
async def admin_finance_market(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.vendor_finance_table(db)
    limit = 50
    offset = (page - 1) * limit
    total = len(rows)
    total_pages = (total + limit - 1) // limit
    paginated_rows = rows[offset:offset+limit]

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "finance_market.html",
        {
            "request": request,
            "active_page": "finance",
            "rows": paginated_rows,
            "page": page,
            "total_pages": total_pages,
            "total_vendors": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


@router.get("/finance/market/{vendor_id}", response_class=HTMLResponse)
async def admin_finance_vendor_detail(
    vendor_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.vendor_finance_detail(db, vendor_id)
    if data is None:
        raise HTTPException(status_code=404, detail="Vendor not found")
    return templates.TemplateResponse(
        request, "finance_vendor_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


# ---------------------------------------------------------------------------
# Events / ticketing admin
# ---------------------------------------------------------------------------

@router.get("/events", response_class=HTMLResponse)
async def admin_events(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Event
    from sqlalchemy.orm import selectinload as _sel

    limit = 50
    offset = (page - 1) * limit

    total = (await db.execute(select(func.count(Event.id)))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    q = await db.execute(
        select(Event)
        .options(_sel(Event.tiers))
        .order_by(desc(Event.starts_at))
        .offset(offset)
        .limit(limit)
    )
    events = q.scalars().all()

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "events.html",
        {
            "request": request,
            "active_page": "events",
            "events": events,
            "page": page,
            "total_pages": total_pages,
            "total_events": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )


EVENTS_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "events")
os.makedirs(EVENTS_UPLOAD_DIR, exist_ok=True)

async def _save_event_image(photo: UploadFile | None) -> str | None:
    if photo is None or not getattr(photo, "filename", None):
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        return None
    data = await photo.read()
    if len(data) == 0:
        return None
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(EVENTS_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/events/{fname}"


@router.get("/events/new", response_class=HTMLResponse)
async def admin_events_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    return templates.TemplateResponse(
        request, "event_new.html",
        {"request": request, "active_page": "events", "error": None, "form": {}},
    )


@router.post("/events/new")
async def admin_events_new_submit(
    request: Request,
    name: str = Form(...),
    venue: str = Form(""),
    city: str = Form(""),
    category: str = Form(""),
    description: str = Form(""),
    image: UploadFile | None = File(None),
    organizer_name: str = Form(""),
    organizer_phone: str = Form(""),
    starts_at: str = Form(...),
    ends_at: str = Form(""),
    tier_names: list[str] = Form(default=[]),
    tier_prices: list[str] = Form(default=[]),
    tier_capacities: list[str] = Form(default=[]),
    field_labels: list[str] = Form(default=[]),
    field_values: list[str] = Form(default=[]),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal as _D
    from app.models import Event as _E, EventTicketTier as _T

    def _parse_dt(s: str):
        # HTML datetime-local sends "2026-05-20T18:30" (no tz). Treat as UTC.
        if not s:
            return None
        try:
            dt = datetime.fromisoformat(s)
        except ValueError:
            return None
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)

    additional_fields = []
    for i in range(max(len(field_labels), len(field_values))):
        lbl = field_labels[i].strip() if i < len(field_labels) else ""
        val = field_values[i].strip() if i < len(field_values) else ""
        if lbl and val:
            additional_fields.append({"label": lbl, "value": val})

    form = {
        "name": name, "venue": venue, "city": city, "category": category, "description": description,
        "organizer_name": organizer_name,
        "organizer_phone": organizer_phone, "starts_at": starts_at, "ends_at": ends_at,
        "additional_fields": additional_fields,
    }
    sa = _parse_dt(starts_at)
    if sa is None:
        return templates.TemplateResponse(
            request, "event_new.html",
            {"request": request, "active_page": "events",
             "error": "Start date/time required", "form": form},
            status_code=400,
        )

    saved_image_url = await _save_event_image(image)

    ev = _E(
        name=name.strip(),
        description=description.strip() or None,
        venue=venue.strip() or None,
        city=city.strip() or None,
        category=category.strip() or None,
        image_url=saved_image_url,
        organizer_name=organizer_name.strip() or None,
        organizer_phone=organizer_phone.strip() or None,
        starts_at=sa,
        ends_at=_parse_dt(ends_at),
        is_published=True,
        additional_fields=additional_fields,
    )
    db.add(ev)
    await db.flush()

    # Pair up the parallel tier_* lists; ignore rows where name+price are blank.
    for i in range(max(len(tier_names), len(tier_prices), len(tier_capacities))):
        t_name = tier_names[i].strip() if i < len(tier_names) else ""
        t_price = tier_prices[i].strip() if i < len(tier_prices) else ""
        t_cap = tier_capacities[i].strip() if i < len(tier_capacities) else ""
        if not t_name and not t_price:
            continue
        try:
            price = _D(t_price or "0")
        except Exception:
            continue
        cap = int(t_cap) if t_cap.isdigit() else None
        db.add(_T(event_id=ev.id, name=t_name or "Regular", price=price, capacity=cap))

    await db.commit()
    return RedirectResponse(url="/admin/events", status_code=303)


@router.get("/events/{event_id}/edit", response_class=HTMLResponse)
async def admin_events_edit_form(
    event_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Event as _E
    from sqlalchemy.orm import selectinload as _sel

    q = await db.execute(select(_E).options(_sel(_E.tiers)).where(_E.id == event_id))
    ev = q.scalars().first()
    if not ev:
        raise HTTPException(status_code=404, detail="Event not found")

    form = {
        "id": ev.id,
        "name": ev.name,
        "description": ev.description,
        "venue": ev.venue,
        "city": ev.city,
        "category": ev.category,
        "starts_at": ev.starts_at.strftime("%Y-%m-%dT%H:%M") if ev.starts_at else "",
        "ends_at": ev.ends_at.strftime("%Y-%m-%dT%H:%M") if ev.ends_at else "",
        "organizer_name": ev.organizer_name,
        "organizer_phone": ev.organizer_phone,
        "tiers": ev.tiers,
        "additional_fields": ev.additional_fields or [],
    }

    return templates.TemplateResponse(
        request, "event_edit.html",
        {"request": request, "active_page": "events", "error": None, "form": form},
    )


@router.post("/events/{event_id}/edit")
async def admin_events_edit_submit(
    event_id: int,
    request: Request,
    name: str = Form(...),
    venue: str = Form(""),
    city: str = Form(""),
    category: str = Form(""),
    description: str = Form(""),
    image: UploadFile | None = File(None),
    organizer_name: str = Form(""),
    organizer_phone: str = Form(""),
    starts_at: str = Form(...),
    ends_at: str = Form(""),
    tier_ids: list[str] = Form(default=[]),
    tier_names: list[str] = Form(default=[]),
    tier_prices: list[str] = Form(default=[]),
    tier_capacities: list[str] = Form(default=[]),
    field_labels: list[str] = Form(default=[]),
    field_values: list[str] = Form(default=[]),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal as _D
    from app.models import Event as _E, EventTicketTier as _T

    def _parse_dt(s: str):
        if not s: return None
        try:
            dt = datetime.fromisoformat(s)
        except ValueError:
            return None
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)

    q = await db.execute(select(_E).where(_E.id == event_id))
    ev = q.scalars().first()
    if not ev:
        raise HTTPException(status_code=404, detail="Event not found")

    additional_fields = []
    for i in range(max(len(field_labels), len(field_values))):
        lbl = field_labels[i].strip() if i < len(field_labels) else ""
        val = field_values[i].strip() if i < len(field_values) else ""
        if lbl and val:
            additional_fields.append({"label": lbl, "value": val})

    sa = _parse_dt(starts_at)
    if sa is None:
        form = {
            "id": ev.id, "name": name, "venue": venue, "city": city, "category": category, "description": description,
            "organizer_name": organizer_name, "organizer_phone": organizer_phone, "starts_at": starts_at, "ends_at": ends_at,
            "tiers": [], "additional_fields": additional_fields
        }
        return templates.TemplateResponse(
            request, "event_edit.html",
            {"request": request, "active_page": "events",
             "error": "Start date/time required", "form": form},
            status_code=400,
        )

    ev.name = name.strip()
    ev.description = description.strip() or None
    ev.venue = venue.strip() or None
    ev.city = city.strip() or None
    ev.category = category.strip() or None
    ev.organizer_name = organizer_name.strip() or None
    ev.organizer_phone = organizer_phone.strip() or None
    ev.starts_at = sa
    ev.ends_at = _parse_dt(ends_at)
    ev.additional_fields = additional_fields

    saved_image_url = await _save_event_image(image)
    if saved_image_url:
        ev.image_url = saved_image_url

    t_q = await db.execute(select(_T).where(_T.event_id == event_id))
    existing_tiers = {str(t.id): t for t in t_q.scalars().all()}
    seen_tier_ids = set()

    for i in range(max(len(tier_names), len(tier_prices), len(tier_capacities))):
        t_id_str = tier_ids[i].strip() if i < len(tier_ids) else ""
        t_name = tier_names[i].strip() if i < len(tier_names) else ""
        t_price = tier_prices[i].strip() if i < len(tier_prices) else ""
        t_cap = tier_capacities[i].strip() if i < len(tier_capacities) else ""
        
        if not t_name and not t_price:
            continue
        try:
            price = _D(t_price or "0")
        except Exception:
            continue
        cap = int(t_cap) if t_cap.isdigit() else None

        if t_id_str and t_id_str in existing_tiers:
            t = existing_tiers[t_id_str]
            t.name = t_name or "Regular"
            t.price = price
            t.capacity = cap
            seen_tier_ids.add(t_id_str)
        else:
            db.add(_T(event_id=ev.id, name=t_name or "Regular", price=price, capacity=cap))

    for t_id_str, t in existing_tiers.items():
        if t_id_str not in seen_tier_ids:
            await db.delete(t)

    await db.commit()
    return RedirectResponse(url="/admin/events", status_code=303)


@router.post("/events/{event_id}/publish")
async def admin_events_toggle_publish(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Event as _E

    q = await db.execute(select(_E).where(_E.id == event_id))
    ev = q.scalars().first()
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    ev.is_published = not bool(ev.is_published)
    await db.commit()
    return RedirectResponse(url="/admin/events", status_code=303)


@router.post("/events/{event_id}/delete")
async def admin_events_delete(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Event as _E

    q = await db.execute(select(_E).where(_E.id == event_id))
    ev = q.scalars().first()
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    await db.delete(ev)
    await db.commit()
    return RedirectResponse(url="/admin/events", status_code=303)


@router.get("/messages", response_class=HTMLResponse)
async def admin_messages(
    request: Request,
    page: int = 1,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Notification
    import json

    limit = 50
    offset = (page - 1) * limit

    # Count the groups
    subq = (
        select(Notification.title)
        .where(Notification.type == "broadcast")
        .group_by(Notification.title, Notification.body, Notification.created_at, Notification.data)
        .subquery()
    )
    total = (await db.execute(select(func.count()).select_from(subq))).scalar() or 0
    total_pages = (total + limit - 1) // limit

    stmt = (
        select(
            Notification.title,
            Notification.body,
            Notification.created_at.label("sent_at"),
            Notification.data,
            func.count(Notification.id).label("count")
        )
        .where(Notification.type == "broadcast")
        .group_by(Notification.title, Notification.body, Notification.created_at, Notification.data)
        .order_by(desc(Notification.created_at))
        .offset(offset)
        .limit(limit)
    )
    res = await db.execute(stmt)
    batches = []
    for title, body, sent_at, data_str, count in res.all():
        audience = "all"
        if data_str:
            try:
                parsed = json.loads(data_str)
                audience = parsed.get("audience", "all")
            except Exception:
                pass
        batches.append({
            "title": title,
            "body": body,
            "sent_at": sent_at,
            "audience": audience,
            "count": count
        })

    start_idx = (page - 1) * limit + 1 if total > 0 else 0
    end_idx = min(page * limit, total)
    page_range = list(range(max(1, page - 3), min(total_pages, page + 3) + 1))

    return templates.TemplateResponse(
        request, "messages.html",
        {
            "request": request,
            "active_page": "messages",
            "batches": batches,
            "page": page,
            "total_pages": total_pages,
            "total_messages": total,
            "start_idx": start_idx,
            "end_idx": end_idx,
            "page_range": page_range,
        },
    )



@router.post("/messages/send")
async def admin_messages_send(
    request: Request,
    audience: str = Form(...),
    title: str = Form(...),
    body: str = Form(...),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import User, UserRole, Notification
    from app.services.ws_manager import manager
    from app.services import fcm_service

    if audience == "customer":
        q = await db.execute(select(User).where(User.role == UserRole.CUSTOMER, User.is_active == True))
    elif audience == "driver":
        q = await db.execute(select(User).where(User.role == UserRole.DRIVER, User.is_active == True))
    else:
        q = await db.execute(select(User).where(User.role.in_([UserRole.CUSTOMER, UserRole.DRIVER]), User.is_active == True))
    
    users = q.scalars().all()
    user_ids = [u.id for u in users]
    
    if user_ids:
        created_at_now = datetime.now(timezone.utc)
        import json
        data_str = json.dumps({"audience": audience})
        
        for uid in user_ids:
            db.add(
                Notification(
                    user_id=uid,
                    title=title,
                    body=body,
                    type="broadcast",
                    data=data_str,
                    created_at=created_at_now,
                )
            )
            try:
                await manager.send(uid, "broadcast_message", {"title": title, "body": body})
            except Exception:
                pass
        
        await db.commit()
        
        try:
            await fcm_service.send_to_users(db, user_ids, title, body, {"event": "broadcast_message"})
        except Exception as e:
            print(f"[broadcast] FCM send failed: {e}")

    return RedirectResponse(url="/admin/messages", status_code=303)


# ---------- Corporate Billing (BRD: PY-05 / AD-12) ----------

@router.get("/corporate", response_class=HTMLResponse)
async def admin_corporate(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateAccount, CorporateMember
    q = await db.execute(select(CorporateAccount).order_by(CorporateAccount.id.desc()))
    accounts = q.scalars().all()
    enriched = []
    for a in accounts:
        mq = await db.execute(
            select(func.count()).select_from(CorporateMember).where(CorporateMember.corporate_id == a.id)
        )
        count = mq.scalar() or 0
        enriched.append({"account": a, "member_count": count})
    return templates.TemplateResponse(
        request, "corporate.html",
        {"request": request, "active_page": "corporate", "accounts": enriched, "error": None, "success": None},
    )


@router.post("/corporate/create")
async def admin_corporate_create(
    request: Request,
    company_name: str = Form(...),
    billing_email: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateAccount
    from decimal import Decimal
    acct = CorporateAccount(
        company_name=company_name.strip(),
        billing_email=billing_email.strip() or None,
        balance=Decimal("0"),
    )
    db.add(acct)
    await db.commit()
    return RedirectResponse(url="/admin/corporate", status_code=303)


@router.post("/corporate/{account_id}/members/add")
async def admin_corporate_add_member(
    account_id: int,
    request: Request,
    phone_number: str = Form(...),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateAccount, CorporateMember
    aq = await db.execute(select(CorporateAccount).where(CorporateAccount.id == account_id))
    acct = aq.scalars().first()
    if not acct:
        raise HTTPException(status_code=404, detail="Corporate account not found")
    uq = await db.execute(select(User).where(User.phone_number == phone_number.strip()))
    target = uq.scalars().first()
    if not target:
        raise HTTPException(status_code=404, detail="No user found with this phone number")
    eq = await db.execute(select(CorporateMember).where(CorporateMember.user_id == target.id))
    if eq.scalars().first():
        raise HTTPException(status_code=409, detail="User already linked to a corporate account")
    member = CorporateMember(corporate_id=account_id, user_id=target.id, status="active")
    db.add(member)
    await db.commit()
    return RedirectResponse(url="/admin/corporate", status_code=303)


@router.post("/corporate/{account_id}/topup")
async def admin_corporate_topup(
    account_id: int,
    request: Request,
    amount: float = Form(...),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateAccount
    from decimal import Decimal
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")
    aq = await db.execute(select(CorporateAccount).where(CorporateAccount.id == account_id))
    acct = aq.scalars().first()
    if not acct:
        raise HTTPException(status_code=404, detail="Corporate account not found")
    acct.balance = Decimal(str(acct.balance or 0)) + Decimal(str(amount))
    await db.commit()
    return RedirectResponse(url="/admin/corporate", status_code=303)


@router.get("/corporate/{account_id}/members")
async def admin_corporate_members_json(
    account_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateMember
    q = await db.execute(
        select(CorporateMember)
        .options(selectinload(CorporateMember.user))
        .where(CorporateMember.corporate_id == account_id)
    )
    members = q.scalars().all()
    return [
        {
            "id": m.id,
            "phone_number": m.user.phone_number if m.user else "",
            "full_name": m.user.full_name if m.user else "",
            "status": m.status,
        }
        for m in members
    ]


@router.post("/corporate/{account_id}/edit")
async def admin_corporate_edit(
    account_id: int,
    request: Request,
    company_name: str = Form(...),
    billing_email: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateAccount
    company_name = company_name.strip()
    billing_email = billing_email.strip() or None
    if not company_name:
        raise HTTPException(status_code=400, detail="Company name cannot be empty")
    aq = await db.execute(select(CorporateAccount).where(CorporateAccount.id == account_id))
    acct = aq.scalars().first()
    if not acct:
        raise HTTPException(status_code=404, detail="Corporate account not found")
    acct.company_name = company_name
    acct.billing_email = billing_email
    await db.commit()
    return RedirectResponse(url="/admin/corporate", status_code=303)


@router.post("/corporate/{account_id}/delete")
async def admin_corporate_delete(
    account_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import CorporateAccount
    aq = await db.execute(select(CorporateAccount).where(CorporateAccount.id == account_id))
    acct = aq.scalars().first()
    if not acct:
        raise HTTPException(status_code=404, detail="Corporate account not found")
    await db.delete(acct)
    await db.commit()
    return RedirectResponse(url="/admin/corporate", status_code=303)


# ===========================================================================
# Food Home layout — banners / categories / collections / deals
# (drives the customer Food home screen via GET /api/v1/food/home)
# ===========================================================================
FOOD_HOME_UPLOAD_DIR = os.path.join(current_dir, "static", "uploads", "food_home")
os.makedirs(FOOD_HOME_UPLOAD_DIR, exist_ok=True)


async def _save_food_home_image(photo: UploadFile | None) -> str | None:
    if photo is None or not photo.filename:
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        raise HTTPException(status_code=400, detail="Image must be JPG, PNG, WEBP, or AVIF")
    data = await photo.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(FOOD_HOME_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/food_home/{fname}"


@router.get("/food-home", response_class=HTMLResponse)
async def admin_food_home(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import (
        FoodBanner,
        FoodCategory,
        FoodCollection,
        FoodDeal,
        Restaurant,
        PromoCode,
    )

    banners = (
        await db.execute(select(FoodBanner).order_by(FoodBanner.display_order, FoodBanner.id))
    ).scalars().all()
    categories = (
        await db.execute(select(FoodCategory).order_by(FoodCategory.display_order, FoodCategory.id))
    ).scalars().all()
    collections = (
        await db.execute(
            select(FoodCollection)
            .options(selectinload(FoodCollection.restaurants))
            .order_by(FoodCollection.display_order, FoodCollection.id)
        )
    ).scalars().all()
    deals = (
        await db.execute(
            select(FoodDeal)
            .options(selectinload(FoodDeal.promo_code))
            .order_by(FoodDeal.display_order, FoodDeal.id)
        )
    ).scalars().all()
    restaurants = (
        await db.execute(
            select(Restaurant).where(Restaurant.is_active == True).order_by(Restaurant.name)  # noqa: E712
        )
    ).scalars().all()
    promos = (
        await db.execute(
            select(PromoCode).where(PromoCode.is_active == True).order_by(PromoCode.code)  # noqa: E712
        )
    ).scalars().all()

    return templates.TemplateResponse(
        request,
        "food_home.html",
        {
            "request": request,
            "active_page": "food-home",
            "banners": banners,
            "categories": categories,
            "collections": collections,
            "deals": deals,
            "restaurants": restaurants,
            "promos": promos,
        },
    )


# ---------- Banners ----------
@router.post("/food-home/banners/new")
async def admin_food_banner_new(
    title: str = Form(""),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    image_url: str = Form(""),
    display_order: int = Form(0),
    is_active: str = Form("on"),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodBanner

    url = await _save_food_home_image(image) or (image_url.strip() or None)
    if not url:
        raise HTTPException(status_code=400, detail="A banner image (upload or URL) is required")
    db.add(
        FoodBanner(
            title=title.strip() or None,
            image_url=url,
            link_type=(link_type.strip() or "none"),
            link_value=link_value.strip() or None,
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/banners/{id}/edit")
async def admin_food_banner_edit(
    id: int,
    title: str = Form(""),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    image_url: str = Form(""),
    display_order: int = Form(0),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodBanner

    b = (await db.execute(select(FoodBanner).where(FoodBanner.id == id))).scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Banner not found")
    b.title = title.strip() or None
    b.link_type = link_type.strip() or "none"
    b.link_value = link_value.strip() or None
    b.display_order = int(display_order or 0)
    new_url = await _save_food_home_image(image)
    if new_url:
        b.image_url = new_url
    elif image_url.strip():
        b.image_url = image_url.strip()
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/banners/{id}/toggle")
async def admin_food_banner_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodBanner

    b = (await db.execute(select(FoodBanner).where(FoodBanner.id == id))).scalars().first()
    if b:
        b.is_active = not b.is_active
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/banners/{id}/delete")
async def admin_food_banner_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodBanner

    b = (await db.execute(select(FoodBanner).where(FoodBanner.id == id))).scalars().first()
    if b:
        await db.delete(b)
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


# ---------- Categories ----------
@router.post("/food-home/categories/new")
async def admin_food_category_new(
    name: str = Form(...),
    icon_url: str = Form(""),
    display_order: int = Form(0),
    is_active: str = Form("on"),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCategory

    if not name.strip():
        raise HTTPException(status_code=400, detail="Category name is required")
    url = await _save_food_home_image(image) or (icon_url.strip() or None)
    db.add(
        FoodCategory(
            name=name.strip(),
            icon_url=url,
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/categories/{id}/edit")
async def admin_food_category_edit(
    id: int,
    name: str = Form(...),
    icon_url: str = Form(""),
    display_order: int = Form(0),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCategory

    c = (await db.execute(select(FoodCategory).where(FoodCategory.id == id))).scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Category not found")
    c.name = name.strip() or c.name
    c.display_order = int(display_order or 0)
    new_url = await _save_food_home_image(image)
    if new_url:
        c.icon_url = new_url
    elif icon_url.strip():
        c.icon_url = icon_url.strip()
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/categories/{id}/toggle")
async def admin_food_category_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCategory

    c = (await db.execute(select(FoodCategory).where(FoodCategory.id == id))).scalars().first()
    if c:
        c.is_active = not c.is_active
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/categories/{id}/delete")
async def admin_food_category_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCategory

    c = (await db.execute(select(FoodCategory).where(FoodCategory.id == id))).scalars().first()
    if c:
        await db.delete(c)
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


# ---------- Collections ----------
@router.post("/food-home/collections/new")
async def admin_food_collection_new(
    name: str = Form(...),
    icon: str = Form("local_fire_department"),
    color: str = Form("blue"),
    display_order: int = Form(0),
    is_active: str = Form("on"),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCollection

    if not name.strip():
        raise HTTPException(status_code=400, detail="Collection name is required")
    db.add(
        FoodCollection(
            name=name.strip(),
            icon=icon.strip() or "local_fire_department",
            color=color.strip() or "blue",
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/collections/{id}/edit")
async def admin_food_collection_edit(
    id: int,
    name: str = Form(...),
    icon: str = Form("local_fire_department"),
    color: str = Form("blue"),
    display_order: int = Form(0),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCollection

    c = (await db.execute(select(FoodCollection).where(FoodCollection.id == id))).scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Collection not found")
    c.name = name.strip() or c.name
    c.icon = icon.strip() or "local_fire_department"
    c.color = color.strip() or "blue"
    c.display_order = int(display_order or 0)
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/collections/{id}/restaurants")
async def admin_food_collection_restaurants(
    id: int,
    restaurant_ids: list[int] = Form(default=[]),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCollection, Restaurant

    c = (
        await db.execute(
            select(FoodCollection)
            .options(selectinload(FoodCollection.restaurants))
            .where(FoodCollection.id == id)
        )
    ).scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Collection not found")
    chosen = []
    if restaurant_ids:
        chosen = (
            await db.execute(select(Restaurant).where(Restaurant.id.in_(restaurant_ids)))
        ).scalars().all()
    c.restaurants = list(chosen)
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/collections/{id}/toggle")
async def admin_food_collection_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCollection

    c = (await db.execute(select(FoodCollection).where(FoodCollection.id == id))).scalars().first()
    if c:
        c.is_active = not c.is_active
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/collections/{id}/delete")
async def admin_food_collection_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodCollection

    c = (await db.execute(select(FoodCollection).where(FoodCollection.id == id))).scalars().first()
    if c:
        await db.delete(c)
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


# ---------- Deals ----------
@router.post("/food-home/deals/new")
async def admin_food_deal_new(
    title: str = Form(...),
    subtitle: str = Form(""),
    color: str = Form("primary"),
    promo_code_id: str = Form(""),
    image_url: str = Form(""),
    display_order: int = Form(0),
    is_active: str = Form("on"),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodDeal

    if not title.strip():
        raise HTTPException(status_code=400, detail="Deal title is required")
    url = await _save_food_home_image(image) or (image_url.strip() or None)
    db.add(
        FoodDeal(
            title=title.strip(),
            subtitle=subtitle.strip() or None,
            color=color.strip() or "primary",
            promo_code_id=int(promo_code_id) if promo_code_id.strip() else None,
            image_url=url,
            display_order=int(display_order or 0),
            is_active=(is_active == "on"),
            link_type=link_type,
            link_value=link_value.strip() or None,
        )
    )
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/deals/{id}/edit")
async def admin_food_deal_edit(
    id: int,
    title: str = Form(...),
    subtitle: str = Form(""),
    color: str = Form("primary"),
    promo_code_id: str = Form(""),
    image_url: str = Form(""),
    display_order: int = Form(0),
    link_type: str = Form("none"),
    link_value: str = Form(""),
    image: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodDeal

    d = (await db.execute(select(FoodDeal).where(FoodDeal.id == id))).scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Deal not found")
    d.title = title.strip() or d.title
    d.subtitle = subtitle.strip() or None
    d.color = color.strip() or "primary"
    d.promo_code_id = int(promo_code_id) if promo_code_id.strip() else None
    d.display_order = int(display_order or 0)
    d.link_type = link_type
    d.link_value = link_value.strip() or None
    new_url = await _save_food_home_image(image)
    if new_url:
        d.image_url = new_url
    elif image_url.strip():
        d.image_url = image_url.strip()
    await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/deals/{id}/toggle")
async def admin_food_deal_toggle(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodDeal

    d = (await db.execute(select(FoodDeal).where(FoodDeal.id == id))).scalars().first()
    if d:
        d.is_active = not d.is_active
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


@router.post("/food-home/deals/{id}/delete")
async def admin_food_deal_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import FoodDeal

    d = (await db.execute(select(FoodDeal).where(FoodDeal.id == id))).scalars().first()
    if d:
        await db.delete(d)
        await db.commit()
    return RedirectResponse(url="/admin/food-home", status_code=303)


# ---------- Restaurant cuisine-category tagging (restaurant detail page) ----------
@router.post("/restaurants/{restaurant_id}/cuisine-categories")
async def admin_restaurant_set_cuisine_categories(
    restaurant_id: int,
    category_ids: list[int] = Form(default=[]),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import Restaurant, FoodCategory

    r = (
        await db.execute(
            select(Restaurant)
            .options(selectinload(Restaurant.food_categories))
            .where(Restaurant.id == restaurant_id)
        )
    ).scalars().first()
    if not r:
        raise HTTPException(status_code=404, detail="Restaurant not found")
    chosen = []
    if category_ids:
        chosen = (
            await db.execute(select(FoodCategory).where(FoodCategory.id.in_(category_ids)))
        ).scalars().all()
    r.food_categories = list(chosen)
    await db.commit()
    return RedirectResponse(url=f"/admin/restaurants/{restaurant_id}", status_code=303)


# ---------- Driver Incentives Management ----------
@router.get("/incentives")
async def admin_incentives(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    return RedirectResponse(url="/admin/settings?tab=incentives", status_code=307)


@router.post("/incentives/new")
async def admin_incentives_new(
    title: str = Form(...),
    limit_days: int = Form(...),
    trips_required: int = Form(...),
    reward_amount: float = Form(...),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import DriverIncentive
    from decimal import Decimal
    new_inc = DriverIncentive(
        title=title.strip(),
        limit_days=limit_days,
        trips_required=trips_required,
        reward_amount=Decimal(str(reward_amount)),
        is_active=True,
    )
    db.add(new_inc)
    await db.commit()
    return RedirectResponse(url="/admin/settings?tab=incentives", status_code=303)


@router.post("/incentives/{id}/edit")
async def admin_incentives_edit(
    id: int,
    title: str = Form(...),
    limit_days: int = Form(...),
    trips_required: int = Form(...),
    reward_amount: float = Form(...),
    is_active: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import DriverIncentive
    from decimal import Decimal
    q = await db.execute(select(DriverIncentive).where(DriverIncentive.id == id))
    inc = q.scalars().first()
    if not inc:
        raise HTTPException(status_code=404, detail="Incentive not found")
    inc.title = title.strip()
    inc.limit_days = limit_days
    inc.trips_required = trips_required
    inc.reward_amount = Decimal(str(reward_amount))
    inc.is_active = (is_active == "on")
    await db.commit()
    return RedirectResponse(url="/admin/settings?tab=incentives", status_code=303)


@router.post("/incentives/{id}/delete")
async def admin_incentives_delete(
    id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(require_superadmin_or_admin),
):
    from app.models import DriverIncentive
    q = await db.execute(select(DriverIncentive).where(DriverIncentive.id == id))
    inc = q.scalars().first()
    if inc:
        await db.delete(inc)
        await db.commit()
    return RedirectResponse(url="/admin/settings?tab=incentives", status_code=303)


@router.get("/forbidden", response_class=HTMLResponse)
async def admin_forbidden(request: Request):
    return templates.TemplateResponse(request, "forbidden.html", {"request": request})


@router.get("/admins", response_class=HTMLResponse)
async def admin_list_admins(
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_superadmin_or_admin),
):
    q = await db.execute(select(User).where(User.role == UserRole.ADMIN).order_by(User.id.desc()))
    admins = q.scalars().all()
    return templates.TemplateResponse(
        request, "admins.html",
        {"request": request, "active_page": "settings", "admins": admins}
    )


@router.post("/admins/new")
async def admin_create_admin(
    phone_number: str = Form(...),
    full_name: str = Form(...),
    email: str = Form(...),
    admin_role: str = Form(...),
    password: str = Form("admin123"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_superadmin_or_admin),
):
    # Non-superadmins cannot assign the superadmin role
    if (current_user.admin_role or "admin") != "superadmin":
        if admin_role == "superadmin":
            raise _AdminForbidden()

    # check if phone number exists
    existing = await db.execute(select(User).where(User.phone_number == phone_number))
    if existing.scalars().first():
        # Redirect back to admins page with error query parameter
        import urllib.parse
        return RedirectResponse(url=f"/admin/admins?error={urllib.parse.quote('Phone number already in use')}", status_code=303)

    new_admin = User(
        phone_number=phone_number,
        role=UserRole.ADMIN,
        admin_role=admin_role,
        full_name=full_name,
        email=email,
        password=password,
        is_active=True
    )
    db.add(new_admin)
    await db.commit()
    return RedirectResponse(url="/admin/admins", status_code=303)


@router.post("/admins/{admin_id}/edit")
async def admin_edit_admin(
    admin_id: int,
    full_name: str = Form(...),
    email: str = Form(...),
    admin_role: str = Form(...),
    password: str = Form(None),
    is_active: str = Form(""),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_superadmin_or_admin),
):
    q = await db.execute(select(User).where(User.id == admin_id, User.role == UserRole.ADMIN))
    admin = q.scalars().first()
    if not admin:
        raise HTTPException(status_code=404, detail="Admin user not found")

    # Non-superadmins cannot modify a superadmin or assign/change role to superadmin
    if (current_user.admin_role or "admin") != "superadmin":
        if (admin.admin_role or "admin") == "superadmin" or admin_role == "superadmin":
            raise _AdminForbidden()

    # A superadmin's role is permanent and cannot be changed to another role
    if (admin.admin_role or "admin") == "superadmin" and admin_role != "superadmin":
        import urllib.parse
        return RedirectResponse(
            url=f"/admin/admins?error={urllib.parse.quote('Superadmin role is permanent and cannot be changed')}",
            status_code=303
        )

    admin.full_name = full_name
    admin.email = email
    admin.admin_role = admin_role
    admin.is_active = (is_active == "on" or is_active == "1")
    if password and password.strip():
        admin.password = password.strip()

    await db.commit()
    return RedirectResponse(url="/admin/admins", status_code=303)


@router.post("/admins/{admin_id}/delete")
async def admin_delete_admin(
    admin_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_superadmin_or_admin),
):
    if admin_id == current_user.id:
        import urllib.parse
        return RedirectResponse(url=f"/admin/admins?error={urllib.parse.quote('You cannot delete yourself')}", status_code=303)

    q = await db.execute(select(User).where(User.id == admin_id, User.role == UserRole.ADMIN))
    admin = q.scalars().first()
    if admin:
        # Non-superadmins cannot delete a superadmin account
        if (current_user.admin_role or "admin") != "superadmin":
            if (admin.admin_role or "admin") == "superadmin":
                raise _AdminForbidden()
        await db.delete(admin)
        await db.commit()
    return RedirectResponse(url="/admin/admins", status_code=303)



# --- SURGE ZONES UI ---
from app.models import SurgeZone

@router.get("/surge-zones", response_class=HTMLResponse)
async def surge_zones_page(request: Request, db: AsyncSession = Depends(get_db), admin_user: User = Depends(current_admin)):
    q = await db.execute(select(SurgeZone).order_by(desc(SurgeZone.id)))
    zones_objs = q.scalars().all()
    
    zones = [
        {
            "id": z.id,
            "name": z.name,
            "flat_extra_charge": float(z.flat_extra_charge) if z.flat_extra_charge is not None else 0.0,
            "start_time": z.start_time,
            "end_time": z.end_time,
            "is_active": z.is_active,
            "coordinates": z.coordinates,
            "color": z.color,
        }
        for z in zones_objs
    ]

    # Need GOOGLE_MAPS_API_KEY
    gmap_key = settings.GOOGLE_MAPS_API_KEY or ""
    return templates.TemplateResponse("surge_zones.html", {
        "request": request,
        "admin": admin_user,
        "zones": zones,
        "gmap_key": gmap_key,
    })


@router.get("/referrals", response_class=HTMLResponse)
async def admin_referrals(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from app.models import ReferralBonus
    from sqlalchemy.orm import joinedload
    
    q = await db.execute(
        select(ReferralBonus)
        .options(joinedload(ReferralBonus.referrer), joinedload(ReferralBonus.referred))
        .order_by(ReferralBonus.created_at.desc())
        .limit(500)
    )
    bonuses = q.scalars().all()
    
    return templates.TemplateResponse(
        request, "referrals.html",
        {
            "request": request,
            "active_page": "referrals",
            "bonuses": bonuses,
        },
    )


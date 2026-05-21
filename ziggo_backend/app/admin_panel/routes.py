"""Server-rendered admin panel with real DB queries + simple session auth."""
from datetime import datetime, timezone
import os

from fastapi import APIRouter, Request, Form, Depends, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from itsdangerous import URLSafeSerializer, BadSignature
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc
from sqlalchemy.orm import selectinload

from ..config import settings
from ..database import get_db
from ..models import (
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
ALLOWED_PHOTO_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_PHOTO_BYTES = 5 * 1024 * 1024  # 5 MB


async def _save_uploaded_photo(photo: UploadFile | None) -> str | None:
    """Save an uploaded driver photo and return its public URL path.

    Returns None if no file was uploaded. Raises HTTPException for invalid type
    or oversize files so the admin sees a clear error.
    """
    if photo is None or not photo.filename:
        return None
    ext = os.path.splitext(photo.filename)[1].lower()
    if ext not in ALLOWED_PHOTO_EXTS:
        raise HTTPException(status_code=400, detail="Photo must be JPG, PNG, or WEBP")
    data = await photo.read()
    if len(data) == 0:
        return None
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Photo must be under 5 MB")
    import secrets
    fname = f"{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/drivers/{fname}"

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
    return admin


# ---------- Auth ----------
@router.get("/login", response_class=HTMLResponse)
async def admin_login_get(request: Request):
    return templates.TemplateResponse("login.html", {"request": request, "error": None})


@router.post("/login")
async def admin_login_post(
    request: Request,
    phone_number: str = Form(...),
    password: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    """Dev login: phone + 'admin123'. Seed script creates admin@0700000000 by default."""
    q = await db.execute(
        select(User).where(User.phone_number == phone_number, User.role == UserRole.ADMIN)
    )
    user = q.scalars().first()
    expected = "admin123"
    if not user or password != expected:
        return templates.TemplateResponse(
            "login.html",
            {"request": request, "error": "Invalid credentials"},
            status_code=401,
        )
    resp = RedirectResponse(url="/admin/dashboard", status_code=303)
    resp.set_cookie(SESSION_COOKIE, _make_session(user.id), httponly=True, max_age=60 * 60 * 8)
    return resp


@router.get("/logout")
async def admin_logout():
    resp = RedirectResponse(url="/admin/login", status_code=303)
    resp.delete_cookie(SESSION_COOKIE)
    return resp


# ---------- Pages ----------
@router.get("/dashboard", response_class=HTMLResponse)
async def admin_dashboard(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from datetime import timedelta
    from ..models import FareSetting

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
    revenue = (
        await db.execute(
            select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
                Booking.status == BookingStatus.COMPLETED
            )
        )
    ).scalar()
    avg_surge = (
        await db.execute(
            select(func.coalesce(func.avg(FareSetting.surge_multiplier), 1))
        )
    ).scalar()

    # Revenue for the last 7 days
    labels = []
    data = []
    for i in range(6, -1, -1):
        day_start = today_start - timedelta(days=i)
        day_end = day_start + timedelta(days=1)
        labels.append(day_start.strftime("%a"))
        day_rev = (
            await db.execute(
                select(func.coalesce(func.sum(Booking.final_amount), 0)).where(
                    Booking.status == BookingStatus.COMPLETED,
                    Booking.completed_at >= day_start,
                    Booking.completed_at < day_end,
                )
            )
        ).scalar()
        data.append(float(day_rev or 0))

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "active_page": "dashboard",
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
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Driver).options(selectinload(Driver.user)).order_by(Driver.id.desc())
    )
    drivers = q.scalars().all()

    total = (await db.execute(select(func.count(Driver.id)))).scalar() or 0
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
        "total": total,
        "online": online,
        "online_pct": int(round((online / total * 100) if total else 0)),
        "pending": pending,
        "avg_rating": avg_rating,
    }

    return templates.TemplateResponse(
        "drivers.html",
        {"request": request, "active_page": "drivers", "drivers": drivers, "stats": stats},
    )


@router.get("/drivers/new", response_class=HTMLResponse)
async def admin_drivers_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    return templates.TemplateResponse(
        "driver_new.html",
        {"request": request, "active_page": "drivers", "error": None, "form": {}},
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
    auto_approve: str = Form("on"),
    profile_photo: UploadFile | None = File(None),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import UserRole

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
        "auto_approve": auto_approve,
    }

    if vehicle_type not in {"bike", "tuk", "car", "van", "truck"}:
        return templates.TemplateResponse(
            "driver_new.html",
            {"request": request, "active_page": "drivers", "error": "Invalid vehicle type", "form": form},
            status_code=400,
        )

    existing = (
        await db.execute(select(User).where(User.phone_number == phone_number))
    ).scalars().first()
    if existing:
        return templates.TemplateResponse(
            "driver_new.html",
            {"request": request, "active_page": "drivers", "error": "Phone number already registered", "form": form},
            status_code=409,
        )

    for field, value, label in [
        (Driver.nic_number, nic_number, "NIC"),
        (Driver.license_number, license_number, "License"),
        (Driver.vehicle_number, vehicle_number, "Vehicle number"),
    ]:
        if (await db.execute(select(Driver).where(field == value))).scalars().first():
            return templates.TemplateResponse(
                "driver_new.html",
                {"request": request, "active_page": "drivers", "error": f"{label} already in use", "form": form},
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

    approved = bool(auto_approve)
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
    )
    db.add(driver)
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
    return templates.TemplateResponse(
        "driver_edit.html",
        {
            "request": request,
            "active_page": "drivers",
            "driver": d,
            "user": d.user,
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
            "driver_edit.html",
            {
                "request": request,
                "active_page": "drivers",
                "driver": d,
                "user": user,
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

    approved_now = bool(is_approved)
    if approved_now and not d.is_approved:
        d.is_approved = True
        d.status = DriverStatus.APPROVED
        d.approved_at = datetime.now(timezone.utc)
    elif not approved_now and d.is_approved:
        d.is_approved = False
        d.is_online = False
        d.status = DriverStatus.SUSPENDED

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


@router.get("/customers", response_class=HTMLResponse)
@router.get("/riders", response_class=HTMLResponse)
async def admin_customers(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Customer).options(selectinload(Customer.user)).order_by(Customer.id.desc())
    )
    customers = q.scalars().all()
    # active_page now reads "riders" to match the renamed sidebar entry; the
    # legacy /customers URL still works so existing bookmarks don't 404.
    return templates.TemplateResponse(
        "customers.html",
        {"request": request, "active_page": "riders", "customers": customers},
    )


@router.get("/bookings", response_class=HTMLResponse)
async def admin_bookings(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.driver).selectinload(Driver.user),
        )
        .where(Booking.is_flash == False)  # noqa: E712  -- rides only
        .order_by(desc(Booking.id))
        .limit(200)
    )
    bookings = q.scalars().all()
    return templates.TemplateResponse(
        "bookings.html",
        {"request": request, "active_page": "bookings", "bookings": bookings},
    )


@router.get("/flash", response_class=HTMLResponse)
async def admin_flash(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from datetime import timedelta  # noqa: F401 (kept for parity with dashboard)

    q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.driver).selectinload(Driver.user),
        )
        .where(Booking.is_flash == True)  # noqa: E712
        .order_by(desc(Booking.id))
        .limit(200)
    )
    orders = q.scalars().all()

    today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    total = (
        await db.execute(select(func.count(Booking.id)).where(Booking.is_flash == True))  # noqa: E712
    ).scalar() or 0
    active_count = sum(
        1 for o in orders
        if o.status in (
            BookingStatus.SEARCHING,
            BookingStatus.ACCEPTED,
            BookingStatus.ARRIVED,
            BookingStatus.STARTED,
        )
    )
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

    return templates.TemplateResponse(
        "flash.html",
        {
            "request": request,
            "active_page": "flash",
            "orders": orders,
            "stats": stats,
        },
    )


@router.get("/fare-settings", response_class=HTMLResponse)
async def admin_fare_settings(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import FareSetting

    q = await db.execute(select(FareSetting).order_by(FareSetting.id))
    return templates.TemplateResponse(
        "settings.html",
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
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import FareSetting
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
        await db.commit()
    return RedirectResponse(url="/admin/fare-settings", status_code=303)


# ---------- Flash pricing ----------
@router.get("/flash-pricing", response_class=HTMLResponse)
async def admin_flash_pricing(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import FlashWeightTier

    q = await db.execute(
        select(FlashWeightTier).order_by(FlashWeightTier.display_order, FlashWeightTier.id)
    )
    return templates.TemplateResponse(
        "flash_pricing.html",
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
    from ..models import FlashWeightTier

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
    from ..models import FlashWeightTier

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
    from ..models import FlashWeightTier

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
    from ..models import FlashWeightTier

    q = await db.execute(select(FlashWeightTier).where(FlashWeightTier.id == tier_id))
    t = q.scalars().first()
    if t:
        await db.delete(t)
        await db.commit()
    return RedirectResponse(url="/admin/flash-pricing", status_code=303)


@router.get("/restaurants", response_class=HTMLResponse)
async def admin_restaurants(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import Restaurant

    # Order pending (is_active=False) first so owner self-registrations rise
    # to the top of the admin's attention. Within each group, newest first.
    q = await db.execute(
        select(Restaurant).order_by(Restaurant.is_active.asc(), Restaurant.id.desc())
    )
    restaurants = q.scalars().all()

    # Join the owner's phone so the admin can identify who registered each one.
    owner_ids = [r.owner_id for r in restaurants if r.owner_id]
    owner_phone_by_id: dict[int, str] = {}
    if owner_ids:
        u_q = await db.execute(select(User).where(User.id.in_(owner_ids)))
        owner_phone_by_id = {u.id: u.phone_number for u in u_q.scalars().all()}

    rows = [
        {
            "id": r.id,
            "name": r.name,
            "description": r.description,
            "cuisine": r.cuisine,
            "address": r.address,
            "rating": r.rating,
            "delivery_fee": r.delivery_fee,
            "opening_time": r.opening_time,
            "closing_time": r.closing_time,
            "is_active": r.is_active,
            "owner_id": r.owner_id,
            "owner_phone": owner_phone_by_id.get(r.owner_id or 0),
        }
        for r in restaurants
    ]
    return templates.TemplateResponse(
        "restaurants.html",
        {"request": request, "active_page": "restaurants", "restaurants": rows},
    )


@router.post("/restaurants/{restaurant_id}/approve")
async def admin_restaurant_approve(
    restaurant_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import Notification, Restaurant
    from ..services.ws_manager import manager

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
    from ..models import Notification, Restaurant
    from ..services.ws_manager import manager

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
        "restaurant_new.html",
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
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Admin pre-creates a restaurant. If the phone already belongs to a
    user, we reuse them (and bump customers up to restaurant_owner).
    Otherwise we create a fresh user with role=restaurant_owner."""
    from decimal import Decimal
    from ..models import Restaurant, UserRole

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
    }

    phone = owner_phone.strip()
    if len(phone) != 10 or not phone.isdigit():
        return templates.TemplateResponse(
            "restaurant_new.html",
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
                "restaurant_new.html",
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
        from ..models import MarketVendor as _MV

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
        rating=Decimal("4.5"),
        is_active=True,  # admin pre-creates as already-approved
        is_open=True,
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    return RedirectResponse(url=f"/admin/restaurants/{r.id}", status_code=303)


@router.get("/restaurants/{restaurant_id}", response_class=HTMLResponse)
async def admin_restaurant_detail(
    restaurant_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import Restaurant, MenuCategory, MenuItem

    rq = await db.execute(
        select(Restaurant)
        .options(
            selectinload(Restaurant.categories),
            selectinload(Restaurant.items),
        )
        .where(Restaurant.id == restaurant_id)
    )
    restaurant = rq.scalars().first()
    if not restaurant:
        raise HTTPException(status_code=404, detail="Restaurant not found")

    return templates.TemplateResponse(
        "restaurant_detail.html",
        {
            "request": request,
            "active_page": "restaurants",
            "restaurant": restaurant,
            "categories": sorted(restaurant.categories, key=lambda c: c.display_order or 0),
            "items": restaurant.items,
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
    from ..models import MenuCategory

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
    from ..models import MenuItem

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


# ---------- Market vendors ----------
@router.get("/market", response_class=HTMLResponse)
async def admin_market(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import MarketVendor

    q = await db.execute(select(MarketVendor).order_by(MarketVendor.id.desc()))
    return templates.TemplateResponse(
        "market.html",
        {"request": request, "active_page": "market", "vendors": q.scalars().all()},
    )


@router.get("/market/new", response_class=HTMLResponse)
async def admin_market_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    return templates.TemplateResponse(
        "market_new.html",
        {"request": request, "active_page": "market", "error": None, "form": {}},
    )


@router.post("/market/new")
async def admin_market_new_submit(
    request: Request,
    owner_phone: str = Form(...),
    owner_full_name: str = Form(""),
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
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Admin pre-creates a market vendor. Finds or creates the owner user
    by phone, links them via owner_id, and promotes them to market_owner
    when safe (no conflicting restaurant tied to them)."""
    from decimal import Decimal
    from ..models import MarketVendor, Restaurant, UserRole

    form_echo = {
        "owner_phone": owner_phone,
        "owner_full_name": owner_full_name,
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
    }

    phone = owner_phone.strip()
    if len(phone) != 10 or not phone.isdigit():
        return templates.TemplateResponse(
            "market_new.html",
            {
                "request": request,
                "active_page": "market",
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
            role=UserRole.MARKET_OWNER,
            full_name=owner_full_name.strip() or None,
            is_active=True,
        )
        db.add(owner)
        await db.flush()
    else:
        existing = await db.execute(
            select(MarketVendor).where(MarketVendor.owner_id == owner.id)
        )
        if existing.scalars().first() is not None:
            return templates.TemplateResponse(
                "market_new.html",
                {
                    "request": request,
                    "active_page": "market",
                    "error": f"User {phone} already owns a market vendor.",
                    "form": form_echo,
                },
            )
        # Promote to market_owner whenever it's safe — i.e. they don't have
        # a Restaurant binding them to a different portal. Covers plain
        # customers AND restaurant_owners who never registered.
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

    v = MarketVendor(
        owner_id=owner.id,
        name=name.strip(),
        category=category.strip() or None,
        description=description.strip() or None,
        address=address.strip() or None,
        lat=Decimal(str(lat)),
        lng=Decimal(str(lng)),
        phone_number=phone_number.strip() or phone,
        image_url=image_url.strip() or None,
        opening_time=opening_time.strip() or None,
        closing_time=closing_time.strip() or None,
        delivery_fee=Decimal(str(delivery_fee)),
        eta_minutes=eta_minutes,
        rating=Decimal("4.3"),
        is_active=True,
        is_open=True,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    return RedirectResponse(url=f"/admin/market/{v.id}", status_code=303)


@router.get("/market/{vendor_id}", response_class=HTMLResponse)
async def admin_market_detail(
    vendor_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import MarketVendor, Product

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

    return templates.TemplateResponse(
        "market_detail.html",
        {
            "request": request,
            "active_page": "market",
            "vendor": vendor,
            "owner": owner,
            "products": vendor.products,
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
    image_url: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal
    from ..models import Product

    db.add(
        Product(
            vendor_id=vendor_id,
            name=name.strip(),
            description=description.strip() or None,
            price=Decimal(str(price)),
            unit=unit.strip() or None,
            stock_quantity=stock_quantity,
            image_url=image_url.strip() or None,
            is_available=True,
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/admin/market/{vendor_id}", status_code=303)


@router.post("/market/{vendor_id}/suspend")
async def admin_market_suspend(
    vendor_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Suspend a market vendor — sets is_active=False and forces is_open=False
    so customers stop seeing them immediately. Owner is notified by WS."""
    from ..models import MarketVendor, Notification
    from ..services.ws_manager import manager

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
    from ..models import MarketVendor, Notification
    from ..services.ws_manager import manager

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


@router.get("/promotions", response_class=HTMLResponse)
async def admin_promotions(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import PromoCode

    q = await db.execute(select(PromoCode).order_by(PromoCode.id.desc()))
    return templates.TemplateResponse(
        "promotions.html",
        {"request": request, "active_page": "promotions", "promos": q.scalars().all()},
    )


@router.get("/complaints", response_class=HTMLResponse)
@router.get("/support", response_class=HTMLResponse)
async def admin_complaints(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import Complaint

    q = await db.execute(
        select(Complaint).order_by(Complaint.id.desc()).limit(200)
    )
    return templates.TemplateResponse(
        "complaints.html",
        {"request": request, "active_page": "support", "complaints": q.scalars().all()},
    )


# ---------------------------------------------------------------------------
# Finance pages — admin-only deep dive into platform revenue + entity payouts.
# Aggregation logic lives in services/finance_service.py; routes here are
# thin shims that fetch and template-render.
# ---------------------------------------------------------------------------

from ..services import finance_service as fin  # noqa: E402


@router.get("/finance", response_class=HTMLResponse)
async def admin_finance(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    data = await fin.overview(db)
    return templates.TemplateResponse(
        "finance.html",
        {"request": request, "active_page": "finance", "fin": data},
    )


@router.get("/finance/drivers", response_class=HTMLResponse)
async def admin_finance_drivers(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.driver_finance_table(db)
    return templates.TemplateResponse(
        "finance_drivers.html",
        {"request": request, "active_page": "finance", "rows": rows},
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
        "finance_driver_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


@router.get("/finance/customers", response_class=HTMLResponse)
async def admin_finance_customers(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.customer_finance_table(db)
    return templates.TemplateResponse(
        "finance_customers.html",
        {"request": request, "active_page": "finance", "rows": rows},
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
        "finance_customer_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


@router.get("/finance/restaurants", response_class=HTMLResponse)
async def admin_finance_restaurants(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.restaurant_finance_table(db)
    return templates.TemplateResponse(
        "finance_restaurants.html",
        {"request": request, "active_page": "finance", "rows": rows},
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
        "finance_restaurant_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


@router.get("/finance/market", response_class=HTMLResponse)
async def admin_finance_market(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    rows = await fin.vendor_finance_table(db)
    return templates.TemplateResponse(
        "finance_market.html",
        {"request": request, "active_page": "finance", "rows": rows},
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
        "finance_vendor_detail.html",
        {"request": request, "active_page": "finance", "data": data},
    )


# ---------------------------------------------------------------------------
# Events / ticketing admin
# ---------------------------------------------------------------------------

@router.get("/events", response_class=HTMLResponse)
async def admin_events(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import Event
    from sqlalchemy.orm import selectinload as _sel

    q = await db.execute(
        select(Event)
        .options(_sel(Event.tiers))
        .order_by(desc(Event.starts_at))
    )
    events = q.scalars().all()
    return templates.TemplateResponse(
        "events.html",
        {"request": request, "active_page": "events", "events": events},
    )


@router.get("/events/new", response_class=HTMLResponse)
async def admin_events_new_form(
    request: Request,
    _: User = Depends(current_admin),
):
    return templates.TemplateResponse(
        "event_new.html",
        {"request": request, "active_page": "events", "error": None, "form": {}},
    )


@router.post("/events/new")
async def admin_events_new_submit(
    request: Request,
    name: str = Form(...),
    venue: str = Form(""),
    city: str = Form(""),
    description: str = Form(""),
    image_url: str = Form(""),
    organizer_name: str = Form(""),
    organizer_phone: str = Form(""),
    starts_at: str = Form(...),
    ends_at: str = Form(""),
    tier_names: list[str] = Form(default=[]),
    tier_prices: list[str] = Form(default=[]),
    tier_capacities: list[str] = Form(default=[]),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from decimal import Decimal as _D
    from ..models import Event as _E, EventTicketTier as _T

    def _parse_dt(s: str):
        # HTML datetime-local sends "2026-05-20T18:30" (no tz). Treat as UTC.
        if not s:
            return None
        try:
            dt = datetime.fromisoformat(s)
        except ValueError:
            return None
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)

    form = {
        "name": name, "venue": venue, "city": city, "description": description,
        "image_url": image_url, "organizer_name": organizer_name,
        "organizer_phone": organizer_phone, "starts_at": starts_at, "ends_at": ends_at,
    }
    sa = _parse_dt(starts_at)
    if sa is None:
        return templates.TemplateResponse(
            "event_new.html",
            {"request": request, "active_page": "events",
             "error": "Start date/time required", "form": form},
            status_code=400,
        )

    ev = _E(
        name=name.strip(),
        description=description.strip() or None,
        venue=venue.strip() or None,
        city=city.strip() or None,
        image_url=image_url.strip() or None,
        organizer_name=organizer_name.strip() or None,
        organizer_phone=organizer_phone.strip() or None,
        starts_at=sa,
        ends_at=_parse_dt(ends_at),
        is_published=True,
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


@router.post("/events/{event_id}/publish")
async def admin_events_toggle_publish(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    from ..models import Event as _E

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
    from ..models import Event as _E

    q = await db.execute(select(_E).where(_E.id == event_id))
    ev = q.scalars().first()
    if ev is None:
        raise HTTPException(status_code=404, detail="Event not found")
    await db.delete(ev)
    await db.commit()
    return RedirectResponse(url="/admin/events", status_code=303)


# ---------------------------------------------------------------------------
# Client-requested pages — added 2026-05-21 to match the 19-item sidebar
# the client supplied. Each is a read-only view backed by existing models
# (no new migrations). Mutating actions are kept minimal.
# ---------------------------------------------------------------------------

from decimal import Decimal  # noqa: E402
import json  # noqa: E402


@router.get("/heatmap", response_class=HTMLResponse)
async def admin_heatmap(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Pickup-location heat map for the last 500 bookings (rides + flash)."""
    q = await db.execute(
        select(Booking.pickup_lat, Booking.pickup_lng, Booking.service_type)
        .where(Booking.pickup_lat.isnot(None), Booking.pickup_lng.isnot(None))
        .order_by(desc(Booking.id))
        .limit(500)
    )
    points = [
        {"lat": float(r[0]), "lng": float(r[1]), "service": r[2] or ""}
        for r in q.all()
    ]
    return templates.TemplateResponse(
        "heatmap.html",
        {
            "request": request,
            "active_page": "heatmap",
            "points_json": json.dumps(points),
            "point_count": len(points),
        },
    )


@router.get("/vehicles", response_class=HTMLResponse)
async def admin_vehicles(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Every registered vehicle = every driver row (1 driver = 1 vehicle)."""
    q = await db.execute(
        select(Driver)
        .options(selectinload(Driver.user))
        .order_by(desc(Driver.id))
    )
    vehicles = q.scalars().all()
    # Per-type counts for the summary cards.
    by_type: dict[str, int] = {}
    online_count = 0
    for v in vehicles:
        if v.vehicle_type:
            by_type[v.vehicle_type] = by_type.get(v.vehicle_type, 0) + 1
        if v.is_online:
            online_count += 1
    return templates.TemplateResponse(
        "vehicles.html",
        {
            "request": request,
            "active_page": "vehicles",
            "vehicles": vehicles,
            "by_type": by_type,
            "online_count": online_count,
        },
    )


@router.get("/categories", response_class=HTMLResponse)
async def admin_categories(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Service categories = the 5 vehicle types + flash + food + market.

    Pulls FareSetting rows so the admin sees the per-category pricing alongside
    the live count of drivers/vendors in that category.
    """
    from ..models import FareSetting

    fare_q = await db.execute(select(FareSetting))
    fares = {f.service_type: f for f in fare_q.scalars().all()}

    drv_counts_q = await db.execute(
        select(Driver.vehicle_type, func.count(Driver.id)).group_by(Driver.vehicle_type)
    )
    drv_counts = {row[0]: int(row[1]) for row in drv_counts_q.all() if row[0]}

    booking_counts_q = await db.execute(
        select(Booking.service_type, func.count(Booking.id)).group_by(Booking.service_type)
    )
    booking_counts = {row[0]: int(row[1]) for row in booking_counts_q.all() if row[0]}

    categories = []
    catalog = [
        ("bike", "Bike", "fa-motorcycle", "from-rose-400 to-pink-500"),
        ("tuk", "Tuk-tuk", "fa-taxi", "from-amber-400 to-orange-500"),
        ("car", "Car", "fa-car", "from-sky-400 to-blue-500"),
        ("van", "Van", "fa-shuttle-van", "from-indigo-400 to-purple-500"),
        ("truck", "Truck", "fa-truck", "from-slate-500 to-zinc-700"),
    ]
    for key, label, icon, grad in catalog:
        f = fares.get(key)
        categories.append({
            "key": key,
            "label": label,
            "icon": icon,
            "grad": grad,
            "base_fare": float(f.base_fare) if f else None,
            "per_km": float(f.per_km_rate) if f else None,
            "per_min": float(f.per_minute_rate) if f else None,
            "min_fare": float(f.min_fare) if f else None,
            "drivers": drv_counts.get(key, 0),
            "bookings": booking_counts.get(key, 0),
        })
    return templates.TemplateResponse(
        "categories.html",
        {"request": request, "active_page": "categories", "categories": categories},
    )


@router.get("/live-tracking", response_class=HTMLResponse)
async def admin_live_tracking(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Real-time map of online + approved drivers. Page polls /live-tracking/feed."""
    return templates.TemplateResponse(
        "live_tracking.html",
        {"request": request, "active_page": "live-tracking"},
    )


@router.get("/live-tracking/feed")
async def admin_live_tracking_feed(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    q = await db.execute(
        select(Driver)
        .options(selectinload(Driver.user))
        .where(
            Driver.is_online == True,  # noqa: E712
            Driver.status == DriverStatus.APPROVED,
            Driver.current_lat.isnot(None),
            Driver.current_lng.isnot(None),
        )
    )
    drivers = []
    for d in q.scalars().all():
        drivers.append({
            "id": d.id,
            "name": d.user.full_name if d.user else f"Driver #{d.id}",
            "phone": d.user.phone_number if d.user else "",
            "vehicle_type": d.vehicle_type or "",
            "vehicle_number": d.vehicle_number or "",
            "lat": float(d.current_lat),
            "lng": float(d.current_lng),
            "last_update": d.last_location_update.isoformat() if d.last_location_update else None,
        })
    # Also surface in-progress bookings so the admin can see active trips.
    bq = await db.execute(
        select(Booking)
        .options(selectinload(Booking.customer).selectinload(Customer.user))
        .where(
            Booking.status.in_([
                BookingStatus.ACCEPTED,
                BookingStatus.ARRIVED,
                BookingStatus.STARTED,
            ])
        )
        .order_by(desc(Booking.id))
        .limit(50)
    )
    active = []
    for b in bq.scalars().all():
        active.append({
            "booking_ref": b.booking_ref,
            "status": b.status.value if b.status else "",
            "customer": (b.customer.user.full_name if b.customer and b.customer.user else ""),
            "pickup_lat": float(b.pickup_lat) if b.pickup_lat else None,
            "pickup_lng": float(b.pickup_lng) if b.pickup_lng else None,
            "drop_lat": float(b.drop_lat) if b.drop_lat else None,
            "drop_lng": float(b.drop_lng) if b.drop_lng else None,
        })
    return {"drivers": drivers, "active_bookings": active}


@router.get("/reports", response_class=HTMLResponse)
async def admin_reports(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """30-day revenue/ride summary + top drivers + top customers."""
    from datetime import timedelta
    from ..models import WalletTransaction

    now = datetime.now(timezone.utc)
    day0 = (now - timedelta(days=29)).replace(hour=0, minute=0, second=0, microsecond=0)

    daily_q = await db.execute(
        select(
            func.date(Booking.completed_at).label("day"),
            func.count(Booking.id).label("rides"),
            func.coalesce(func.sum(Booking.final_amount), 0).label("revenue"),
        )
        .where(
            Booking.status == BookingStatus.COMPLETED,
            Booking.completed_at >= day0,
        )
        .group_by(func.date(Booking.completed_at))
        .order_by(func.date(Booking.completed_at))
    )
    daily = [
        {
            "day": str(r[0]),
            "rides": int(r[1]),
            "revenue": float(r[2] or 0),
        }
        for r in daily_q.all()
    ]

    top_drivers_q = await db.execute(
        select(Driver, func.count(Booking.id).label("rides"),
               func.coalesce(func.sum(Booking.driver_earnings), 0).label("earnings"))
        .join(Booking, Booking.driver_id == Driver.id, isouter=True)
        .options(selectinload(Driver.user))
        .where(Booking.status == BookingStatus.COMPLETED)
        .group_by(Driver.id)
        .order_by(desc("earnings"))
        .limit(10)
    )
    top_drivers = [
        {
            "name": d.user.full_name if d.user else f"Driver #{d.id}",
            "phone": d.user.phone_number if d.user else "",
            "vehicle": d.vehicle_type or "",
            "rides": int(rides or 0),
            "earnings": float(earnings or 0),
        }
        for d, rides, earnings in top_drivers_q.all()
    ]

    top_customers_q = await db.execute(
        select(Customer, func.count(Booking.id).label("rides"),
               func.coalesce(func.sum(Booking.final_amount), 0).label("spend"))
        .join(Booking, Booking.customer_id == Customer.id, isouter=True)
        .options(selectinload(Customer.user))
        .where(Booking.status == BookingStatus.COMPLETED)
        .group_by(Customer.id)
        .order_by(desc("spend"))
        .limit(10)
    )
    top_customers = [
        {
            "name": c.user.full_name if c.user else f"Customer #{c.id}",
            "phone": c.user.phone_number if c.user else "",
            "rides": int(rides or 0),
            "spend": float(spend or 0),
        }
        for c, rides, spend in top_customers_q.all()
    ]

    totals = {
        "rides_30d": sum(d["rides"] for d in daily),
        "revenue_30d": sum(d["revenue"] for d in daily),
        "drivers": (await db.execute(select(func.count(Driver.id)))).scalar() or 0,
        "riders": (await db.execute(select(func.count(Customer.id)))).scalar() or 0,
        "topups_30d": float((await db.execute(
            select(func.coalesce(func.sum(WalletTransaction.amount), 0))
            .where(WalletTransaction.type == "credit", WalletTransaction.created_at >= day0)
        )).scalar() or 0),
    }

    return templates.TemplateResponse(
        "reports.html",
        {
            "request": request,
            "active_page": "reports",
            "daily_json": json.dumps(daily),
            "totals": totals,
            "top_drivers": top_drivers,
            "top_customers": top_customers,
        },
    )


@router.get("/withdrawals", response_class=HTMLResponse)
async def admin_withdrawals(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Driver payout overview.

    No dedicated withdrawal-request model exists yet, so this view derives the
    pending payout from `total_earnings` minus any `WalletTransaction` rows of
    type 'withdrawal'. Past payouts are listed in a second table.
    """
    from ..models import WalletTransaction

    d_q = await db.execute(
        select(Driver).options(selectinload(Driver.user)).order_by(desc(Driver.total_earnings))
    )
    drivers = d_q.scalars().all()

    paid_q = await db.execute(
        select(WalletTransaction.user_id, func.coalesce(func.sum(WalletTransaction.amount), 0))
        .where(WalletTransaction.type == "withdrawal")
        .group_by(WalletTransaction.user_id)
    )
    paid_by_user = {row[0]: float(row[1] or 0) for row in paid_q.all()}

    rows = []
    total_pending = Decimal("0")
    for d in drivers:
        earned = float(d.total_earnings or 0)
        paid = paid_by_user.get(d.user_id, 0.0)
        pending = max(earned - paid, 0.0)
        total_pending += Decimal(str(pending))
        rows.append({
            "driver_id": d.id,
            "user_id": d.user_id,
            "name": d.user.full_name if d.user else f"Driver #{d.id}",
            "phone": d.user.phone_number if d.user else "",
            "vehicle_type": d.vehicle_type or "",
            "earned": earned,
            "paid": paid,
            "pending": pending,
        })

    hist_q = await db.execute(
        select(WalletTransaction)
        .options(selectinload(WalletTransaction.user))
        .where(WalletTransaction.type == "withdrawal")
        .order_by(desc(WalletTransaction.id))
        .limit(100)
    )
    history = hist_q.scalars().all()

    return templates.TemplateResponse(
        "withdrawals.html",
        {
            "request": request,
            "active_page": "withdrawals",
            "rows": rows,
            "history": history,
            "total_pending": float(total_pending),
        },
    )


@router.post("/withdrawals/{driver_id}/pay")
async def admin_withdrawals_pay(
    driver_id: int,
    amount: str = Form(...),
    note: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Record a manual payout to a driver. Creates a WalletTransaction row of
    type='withdrawal' so the pending-payout calc in the table subtracts it.
    """
    q = await db.execute(select(Driver).where(Driver.id == driver_id))
    drv = q.scalars().first()
    if drv is None:
        raise HTTPException(status_code=404, detail="Driver not found")
    try:
        amt = Decimal(str(amount))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid amount")
    if amt <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")

    from ..models import WalletTransaction
    tx = WalletTransaction(
        user_id=drv.user_id,
        amount=amt,
        type="withdrawal",
        description=note or "Manual payout via admin panel",
        balance_after=Decimal("0"),
    )
    db.add(tx)
    await db.commit()
    return RedirectResponse(url="/admin/withdrawals", status_code=303)


@router.get("/payments", response_class=HTMLResponse)
async def admin_payments(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """All booking payments (cash/card/wallet) in reverse-chronological order."""
    from ..models import Payment

    q = await db.execute(
        select(Payment)
        .options(
            selectinload(Payment.booking).selectinload(Booking.customer).selectinload(Customer.user),
        )
        .order_by(desc(Payment.id))
        .limit(300)
    )
    payments = q.scalars().all()

    totals = {
        "total": float((await db.execute(
            select(func.coalesce(func.sum(Payment.amount), 0))
        )).scalar() or 0),
        "cash": float((await db.execute(
            select(func.coalesce(func.sum(Payment.amount), 0))
            .where(Payment.payment_method == "cash")
        )).scalar() or 0),
        "card": float((await db.execute(
            select(func.coalesce(func.sum(Payment.amount), 0))
            .where(Payment.payment_method == "card")
        )).scalar() or 0),
        "wallet": float((await db.execute(
            select(func.coalesce(func.sum(Payment.amount), 0))
            .where(Payment.payment_method == "wallet")
        )).scalar() or 0),
    }
    return templates.TemplateResponse(
        "payments.html",
        {
            "request": request,
            "active_page": "payments",
            "payments": payments,
            "totals": totals,
        },
    )


@router.get("/topups", response_class=HTMLResponse)
async def admin_topups(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Wallet credit history. Filter: WalletTransaction.type == 'credit'."""
    from ..models import WalletTransaction

    q = await db.execute(
        select(WalletTransaction)
        .options(selectinload(WalletTransaction.user))
        .where(WalletTransaction.type == "credit")
        .order_by(desc(WalletTransaction.id))
        .limit(300)
    )
    topups = q.scalars().all()
    total = float((await db.execute(
        select(func.coalesce(func.sum(WalletTransaction.amount), 0))
        .where(WalletTransaction.type == "credit")
    )).scalar() or 0)
    count = (await db.execute(
        select(func.count(WalletTransaction.id))
        .where(WalletTransaction.type == "credit")
    )).scalar() or 0
    return templates.TemplateResponse(
        "topups.html",
        {
            "request": request,
            "active_page": "topups",
            "topups": topups,
            "total": total,
            "count": int(count),
        },
    )


@router.post("/topups/manual")
async def admin_topups_manual(
    user_phone: str = Form(...),
    amount: str = Form(...),
    note: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Manually credit a customer's wallet. Used by support when a real top-up
    fails to post but the bank already cleared.
    """
    u_q = await db.execute(select(User).where(User.phone_number == user_phone.strip()))
    u = u_q.scalars().first()
    if u is None:
        raise HTTPException(status_code=404, detail="No user with that phone")
    c_q = await db.execute(select(Customer).where(Customer.user_id == u.id))
    c = c_q.scalars().first()
    if c is None:
        raise HTTPException(status_code=400, detail="User has no customer profile")
    try:
        amt = Decimal(str(amount))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid amount")
    if amt <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")

    c.wallet_balance = (c.wallet_balance or Decimal("0")) + amt
    from ..models import WalletTransaction
    tx = WalletTransaction(
        user_id=u.id,
        amount=amt,
        type="credit",
        description=note or "Manual top-up by admin",
        balance_after=c.wallet_balance,
    )
    db.add(tx)
    await db.commit()
    return RedirectResponse(url="/admin/topups", status_code=303)


@router.get("/services", response_class=HTMLResponse)
async def admin_services(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """The user-facing services exposed by Ziggo. Counts are derived from data."""
    from ..models import Restaurant, MarketVendor, Event

    rides_total = int((await db.execute(
        select(func.count(Booking.id)).where(Booking.is_flash == False)  # noqa: E712
    )).scalar() or 0)
    flash_total = int((await db.execute(
        select(func.count(Booking.id)).where(Booking.is_flash == True)  # noqa: E712
    )).scalar() or 0)
    rentals_total = int((await db.execute(
        select(func.count(Booking.id)).where(Booking.is_rental == True)  # noqa: E712
    )).scalar() or 0)
    restaurants_total = int((await db.execute(select(func.count(Restaurant.id)))).scalar() or 0)
    vendors_total = int((await db.execute(select(func.count(MarketVendor.id)))).scalar() or 0)
    events_total = int((await db.execute(select(func.count(Event.id)))).scalar() or 0)

    services = [
        {"key": "rides", "label": "Rides", "icon": "fa-car",
         "desc": "Bike, tuk, car, van and truck on-demand rides.",
         "count": rides_total, "count_label": "rides booked", "url": "/admin/bookings",
         "grad": "from-blue-500 to-indigo-600"},
        {"key": "flash", "label": "Flash Parcels", "icon": "fa-bolt",
         "desc": "Same-city parcel courier dispatched on demand.",
         "count": flash_total, "count_label": "parcels", "url": "/admin/flash",
         "grad": "from-amber-400 to-orange-500"},
        {"key": "rentals", "label": "Vehicle Rentals", "icon": "fa-key",
         "desc": "Hourly rental of bikes/tuks/vans to roam the city.",
         "count": rentals_total, "count_label": "rentals", "url": "/admin/bookings",
         "grad": "from-emerald-400 to-teal-500"},
        {"key": "food", "label": "Food Delivery", "icon": "fa-utensils",
         "desc": "Restaurant ordering with driver delivery.",
         "count": restaurants_total, "count_label": "restaurants", "url": "/admin/restaurants",
         "grad": "from-rose-400 to-red-500"},
        {"key": "market", "label": "Market", "icon": "fa-store",
         "desc": "Grocery & retail vendors shipping via Ziggo drivers.",
         "count": vendors_total, "count_label": "vendors", "url": "/admin/market",
         "grad": "from-purple-400 to-fuchsia-500"},
        {"key": "events", "label": "Events & Tickets", "icon": "fa-music",
         "desc": "Concert and event ticketing inside the app.",
         "count": events_total, "count_label": "events", "url": "/admin/events",
         "grad": "from-sky-400 to-cyan-500"},
    ]
    return templates.TemplateResponse(
        "services.html",
        {"request": request, "active_page": "services", "services": services},
    )


@router.get("/messages", response_class=HTMLResponse)
async def admin_messages(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Admin-broadcast messages. Stored as Notification rows of type='admin_message'."""
    from ..models import Notification

    q = await db.execute(
        select(Notification)
        .options(selectinload(Notification.user))
        .where(Notification.type == "admin_message")
        .order_by(desc(Notification.id))
        .limit(200)
    )
    messages = q.scalars().all()
    # Group by data field (JSON containing batch_id) so the inbox shows one row
    # per broadcast instead of one row per recipient.
    batches: dict[str, dict] = {}
    for m in messages:
        meta = {}
        if m.data:
            try:
                meta = json.loads(m.data)
            except Exception:
                meta = {}
        bid = meta.get("batch_id", f"single-{m.id}")
        if bid not in batches:
            batches[bid] = {
                "title": m.title,
                "body": m.body,
                "audience": meta.get("audience", "individual"),
                "sent_at": m.created_at,
                "count": 0,
                "first_id": m.id,
            }
        batches[bid]["count"] += 1
    grouped = sorted(batches.values(), key=lambda b: b["first_id"], reverse=True)
    return templates.TemplateResponse(
        "messages.html",
        {"request": request, "active_page": "messages", "batches": grouped},
    )


@router.post("/messages/send")
async def admin_messages_send(
    audience: str = Form(...),
    title: str = Form(...),
    body: str = Form(...),
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """Broadcast a message to all users of the chosen audience.

    audience ∈ {"all", "customer", "driver"}.
    """
    import secrets
    from ..models import Notification

    audience = audience.strip().lower()
    if audience not in ("all", "customer", "driver"):
        raise HTTPException(status_code=400, detail="Invalid audience")

    where = []
    if audience == "customer":
        where.append(User.role == UserRole.CUSTOMER)
    elif audience == "driver":
        where.append(User.role == UserRole.DRIVER)
    else:
        where.append(User.role.in_([UserRole.CUSTOMER, UserRole.DRIVER]))

    u_q = await db.execute(select(User.id).where(*where))
    user_ids = [row[0] for row in u_q.all()]

    batch_id = secrets.token_hex(8)
    meta = json.dumps({"batch_id": batch_id, "audience": audience})
    for uid in user_ids:
        db.add(Notification(
            user_id=uid,
            title=title.strip(),
            body=body.strip(),
            type="admin_message",
            data=meta,
            is_read=False,
        ))
    await db.commit()
    return RedirectResponse(url="/admin/messages", status_code=303)


@router.get("/notifications", response_class=HTMLResponse)
async def admin_notifications(
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(current_admin),
):
    """All notifications emitted by the system (latest first, limited 300)."""
    from ..models import Notification

    q = await db.execute(
        select(Notification)
        .options(selectinload(Notification.user))
        .order_by(desc(Notification.id))
        .limit(300)
    )
    notifications = q.scalars().all()

    by_type_q = await db.execute(
        select(Notification.type, func.count(Notification.id)).group_by(Notification.type)
    )
    by_type = {row[0] or "other": int(row[1]) for row in by_type_q.all()}
    unread_count = int((await db.execute(
        select(func.count(Notification.id)).where(Notification.is_read == False)  # noqa: E712
    )).scalar() or 0)
    return templates.TemplateResponse(
        "notifications.html",
        {
            "request": request,
            "active_page": "notifications",
            "notifications": notifications,
            "by_type": by_type,
            "unread_count": unread_count,
        },
    )


@router.get("/settings", response_class=HTMLResponse)
async def admin_settings(
    request: Request,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(current_admin),
):
    """General settings hub — surfaces system info + links to fare/flash configs."""
    from ..models import FareSetting, FlashWeightTier, PromoCode

    fare_count = int((await db.execute(select(func.count(FareSetting.id)))).scalar() or 0)
    flash_count = int((await db.execute(select(func.count(FlashWeightTier.id)))).scalar() or 0)
    promo_count = int((await db.execute(select(func.count(PromoCode.id)))).scalar() or 0)

    info = {
        "project_name": settings.PROJECT_NAME,
        "api_prefix": settings.API_V1_STR,
        "dev_mode": getattr(settings, "DEV_MODE", False),
        "fare_count": fare_count,
        "flash_count": flash_count,
        "promo_count": promo_count,
        "admin_name": admin.full_name or "Admin",
        "admin_phone": admin.phone_number,
        "admin_email": admin.email or "",
    }
    return templates.TemplateResponse(
        "admin_settings.html",
        {"request": request, "active_page": "settings", "info": info},
    )


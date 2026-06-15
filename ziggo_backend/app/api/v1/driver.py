import os
import secrets
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...database import get_db
from ...models import Driver, DriverDocument, DriverStatus, FareSetting, User
from ...schemas import (
    DriverLocationUpdate,
    DriverOnlineToggle,
    DriverProfileResponse,
    DriverRegisterRequest,
)
from ...services.auth_service import get_current_user, require_role
from ...services.fare_service import haversine_km
from ...services.ws_manager import manager

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
            d.relative_name,
            d.relative_contact,
            d.relative_relationship,
            d.billing_proof_url,
        ]
    )


def _to_response(user: User, d: Driver, paid_payouts: float = 0.0, pending_payout: float = 0.0, ss=None) -> DriverProfileResponse:
    peak_active = False
    is_curr_peak = False
    start_h = None
    end_h = None
    extra_amt = 0.0
    if ss:
        peak_active = bool(ss.peak_is_active)
        start_h = ss.peak_start_hour
        end_h = ss.peak_end_hour
        extra_amt = float(ss.peak_extra_amount or 0.0)
        if peak_active:
            from datetime import datetime, timezone, timedelta
            colombo_tz = timezone(timedelta(hours=5, minutes=30))
            current_hour = datetime.now(colombo_tz).hour
            if start_h is not None and end_h is not None:
                if start_h <= end_h:
                    is_curr_peak = start_h <= current_hour < end_h
                else:
                    is_curr_peak = current_hour >= start_h or current_hour < end_h

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
        relative_name=d.relative_name,
        relative_contact=d.relative_contact,
        relative_relationship=d.relative_relationship,
        billing_proof_url=d.billing_proof_url,
        paid_payouts=paid_payouts,
        pending_payout=pending_payout,
        peak_is_active=peak_active,
        peak_start_hour=start_h,
        peak_end_hour=end_h,
        peak_extra_amount=extra_amt,
        is_currently_peak=is_curr_peak,
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
            "heading": float(d.current_heading) if d.current_heading is not None else 0.0,
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
    from ...services.finance_service import get_driver_payout_stats
    stats = await get_driver_payout_stats(db, d.id)
    from ...models import SystemSettings
    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    return _to_response(user, d, paid_payouts=stats["paid"], pending_payout=stats["pending"], ss=ss)


# Fallback rate card when no FareSetting row exists for the driver's vehicle.
_FARE_DEFAULTS = {
    "bike":  {"base": 60,  "per_km": 35,  "per_min": 2, "min": 100},
    "tuk":   {"base": 80,  "per_km": 55,  "per_min": 3, "min": 150},
    "car":   {"base": 150, "per_km": 80,  "per_min": 4, "min": 250},
    "van":   {"base": 250, "per_km": 120, "per_min": 5, "min": 400},
    "truck": {"base": 500, "per_km": 200, "per_min": 6, "min": 750},
}


@router.get("/earnings-summary")
async def get_my_earnings_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Lifetime money split for the in-app Earnings page — total collected,
    admin commission, and the driver's net earnings (plus paid/pending)."""
    d = await _get_driver(db, user)
    from ...services.finance_service import get_driver_earnings_summary
    return await get_driver_earnings_summary(db, d.id)


@router.get("/fare-card")
async def get_my_fare_card(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """The live, admin-editable rate card for the driver's own vehicle type,
    plus a worked example so the driver sees exactly how a fare — and their
    share of it — is calculated. Read-only mirror of the booking fare engine."""
    d = await _get_driver(db, user)
    service_type = d.vehicle_type or "car"

    fs = (
        await db.execute(
            select(FareSetting).where(FareSetting.service_type == service_type)
        )
    ).scalars().first()

    if fs:
        base = float(fs.base_fare or 0)
        per_km = float(fs.per_km_rate or 0)
        per_min = float(fs.per_minute_rate or 0)
        min_fare = float(fs.min_fare or 0)
        platform_pct = float(fs.platform_fee_percent or 15)
        surge = float(fs.surge_multiplier or 1)
        pickup_fee = float(fs.pickup_fee or 0)
        boost = float(fs.boost or 0)
        passenger_deductible = float(fs.passenger_deductible or 0)
        display_name = fs.display_name or service_type
    else:
        dft = _FARE_DEFAULTS.get(service_type, _FARE_DEFAULTS["car"])
        base, per_km, per_min, min_fare = dft["base"], dft["per_km"], dft["per_min"], dft["min"]
        platform_pct, surge = 15.0, 1.0
        pickup_fee, boost, passenger_deductible = 0.0, 0.0, 0.0
        display_name = service_type

    # Worked example — a typical 5 km / 15 min trip.
    ex_km, ex_min = 5.0, 15.0
    raw = (base + pickup_fee + per_km * ex_km + per_min * ex_min) * surge
    fare = max(raw, min_fare) + boost
    gross = fare + passenger_deductible
    platform_fee = round(gross * (platform_pct / 100.0), 2)
    driver_earnings = round(gross - platform_fee, 2)

    return {
        "service_type": service_type,
        "display_name": display_name,
        "base_fare": round(base, 2),
        "per_km_rate": round(per_km, 2),
        "per_minute_rate": round(per_min, 2),
        "min_fare": round(min_fare, 2),
        "pickup_fee": round(pickup_fee, 2),
        "boost": round(boost, 2),
        "passenger_deductible": round(passenger_deductible, 2),
        "surge_multiplier": round(surge, 2),
        "platform_fee_percent": round(platform_pct, 2),
        "driver_share_percent": round(100 - platform_pct, 2),
        "example": {
            "distance_km": ex_km,
            "duration_min": ex_min,
            "gross_total": round(gross, 2),
            "platform_fee": platform_fee,
            "driver_earnings": driver_earnings,
        },
    }


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
    d.relative_name = body.relative_name
    d.relative_contact = body.relative_contact
    d.relative_relationship = body.relative_relationship
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
    if body.heading is not None:
        d.current_heading = Decimal(str(body.heading))
    d.last_location_update = datetime.now(timezone.utc)
    await db.commit()

    # Push to the admin live-tracking channel so the map can update without polling.
    await manager.publish("admin_live", "driver_location_update", {
        "id": d.id,
        "name": user.full_name or "Driver",
        "phone": user.phone_number or "",
        "vehicle_type": d.vehicle_type or "car",
        "vehicle_number": d.vehicle_number or "",
        "lat": float(d.current_lat),
        "lng": float(d.current_lng),
        "heading": float(d.current_heading) if d.current_heading is not None else 0.0,
        "is_online": bool(d.is_online),
        "last_seen": d.last_location_update.isoformat(),
    })

    # Find active booking and push update to customer
    from ...models import Booking, BookingStatus, Customer
    q_b = await db.execute(
        select(Booking)
        .where(
            Booking.driver_id == d.id,
            Booking.status.in_([BookingStatus.ACCEPTED, BookingStatus.ARRIVED, BookingStatus.STARTED])
        )
    )
    active_b = q_b.scalars().first()
    if active_b and active_b.customer_id:
        q_c = await db.execute(select(Customer).where(Customer.id == active_b.customer_id))
        cust = q_c.scalars().first()
        if cust:
            await manager.send(cust.user_id, "driver_location_update", {
                "booking_id": active_b.id,
                "lat": float(d.current_lat),
                "lng": float(d.current_lng),
                "heading": float(d.current_heading) if d.current_heading is not None else 0.0,
            })
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

    # Broadcast so the admin live map can swap the marker style instantly.
    await manager.publish("admin_live", "driver_status_update", {
        "id": d.id,
        "is_online": bool(d.is_online),
        "lat": float(d.current_lat) if d.current_lat is not None else None,
        "lng": float(d.current_lng) if d.current_lng is not None else None,
    })
    return {"is_online": d.is_online}


# ---------- BRD: Driver KYC document upload UI ----------
# Where uploads land. Lives under the admin-panel static volume so the
# admin can view the same files in the browser without extra plumbing. The
# admin_panel is now a top-level package alongside `app/`.
def _find_admin_panel_dir() -> str:
    curr = os.path.abspath(__file__)
    for _ in range(10):
        curr = os.path.dirname(curr)
        candidate = os.path.join(curr, "ziggo_admin_panel")
        if os.path.isdir(candidate):
            return candidate
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))),
        "ziggo_admin_panel"
    )

_ADMIN_PANEL_DIR = _find_admin_panel_dir()
_DOC_UPLOAD_DIR = os.path.join(_ADMIN_PANEL_DIR, "static", "uploads", "driver_docs")
os.makedirs(_DOC_UPLOAD_DIR, exist_ok=True)
_VALID_DOC_TYPES = {"nic_front", "nic_back", "license_front", "license_back", "vehicle_reg", "insurance", "year_license", "eco_test", "vehicle_front", "vehicle_back", "vehicle_side"}
_ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".pdf"}
_MAX_DOC_BYTES = 25 * 1024 * 1024  # 25 MB

async def _save_doc(file: UploadFile, doc_type: str) -> str:
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename")
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in _ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail="Must be JPG, PNG, WEBP, or PDF")
    data = await file.read()
    if len(data) == 0:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(data) > _MAX_DOC_BYTES:
        raise HTTPException(status_code=400, detail="File must be under 25 MB")
    fname = f"{doc_type}_{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(_DOC_UPLOAD_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/driver_docs/{fname}"


@router.post("/documents")
async def upload_driver_document(
    document_type: str = Form(...),
    document: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Driver uploads (or replaces) a KYC document.

    A doc that admin has already verified is locked — re-upload is rejected
    with 409. Replacing a still-pending doc wipes nothing extra (it's already
    unverified). The old file isn't deleted from disk (keeps an audit trail in
    case the driver disputes a rejection).
    """
    doc_type = document_type.strip().lower()
    if doc_type not in _VALID_DOC_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"document_type must be one of {sorted(_VALID_DOC_TYPES)}",
        )

    dq = await db.execute(select(Driver).where(Driver.user_id == user.id))
    d = dq.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver profile not found")

    # Upsert by (driver_id, document_type)
    exq = await db.execute(
        select(DriverDocument).where(
            DriverDocument.driver_id == d.id,
            DriverDocument.document_type == doc_type,
        )
    )
    existing = exq.scalars().first()
    if existing and existing.is_verified:
        raise HTTPException(
            status_code=409,
            detail="This document is already verified and can't be replaced. Contact support to change it.",
        )

    url = await _save_doc(document, doc_type)

    if existing:
        existing.document_url = url
        existing.is_verified = False
        existing.verified_by = None
        existing.verified_at = None
        existing.uploaded_at = datetime.now(timezone.utc)
        doc = existing
    else:
        doc = DriverDocument(
            driver_id=d.id,
            document_type=doc_type,
            document_url=url,
            is_verified=False,
        )
        db.add(doc)
    await db.commit()
    await db.refresh(doc)
    return {
        "id": doc.id,
        "document_type": doc.document_type,
        "document_url": doc.document_url,
        "is_verified": doc.is_verified,
        "uploaded_at": doc.uploaded_at.isoformat() if doc.uploaded_at else None,
    }


@router.get("/documents")
async def list_my_documents(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """List this driver's documents — each of the 4 expected types is
    returned, even if not yet uploaded, so the UI can render placeholders."""
    dq = await db.execute(select(Driver).where(Driver.user_id == user.id))
    d = dq.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver profile not found")

    q = await db.execute(
        select(DriverDocument).where(DriverDocument.driver_id == d.id)
    )
    by_type = {row.document_type: row for row in q.scalars().all()}
    out = []
    for kind in ("nic_front", "nic_back", "license_front", "license_back", "vehicle_reg", "insurance", "year_license", "eco_test", "vehicle_front", "vehicle_back", "vehicle_side"):
        row = by_type.get(kind)
        out.append({
            "document_type": kind,
            "id": row.id if row else None,
            "document_url": row.document_url if row else None,
            "is_verified": bool(row.is_verified) if row else False,
            "uploaded_at": row.uploaded_at.isoformat() if (row and row.uploaded_at) else None,
            "verified_at": row.verified_at.isoformat() if (row and row.verified_at) else None,
        })
    return out


_PROFILE_PHOTO_DIR = os.path.join(_ADMIN_PANEL_DIR, "static", "uploads", "drivers")
os.makedirs(_PROFILE_PHOTO_DIR, exist_ok=True)


async def _save_profile_photo(asset: UploadFile) -> str:
    ext = os.path.splitext(asset.filename or "")[1].lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
        raise HTTPException(status_code=400, detail="Photo must be JPG, PNG, or WEBP")
    data = await asset.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(data) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Photo must be under 5 MB")
    import secrets
    fname = f"profile_{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(_PROFILE_PHOTO_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/drivers/{fname}"


@router.post("/profile-photo")
async def upload_profile_photo(
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Driver uploads their profile photo."""
    url = await _save_profile_photo(photo)
    user.profile_photo = url
    await db.commit()
    await db.refresh(user)
    return {"ok": True, "profile_photo": url}


@router.post("/billing-proof")
async def upload_billing_proof(
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Driver uploads their billing proof."""
    d = await _get_driver(db, user)
    url = await _save_profile_photo(photo)
    d.billing_proof_url = url
    await db.commit()
    await db.refresh(d)
    return {"ok": True, "billing_proof_url": url}


@router.post("/settle-commission")
async def settle_commission(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Settle outstanding admin commission.
    This records a driver payout offset in the DB, matching the pending earnings balance."""
    d = await _get_driver(db, user)
    from ...services.finance_service import get_driver_earnings_summary
    summary = await get_driver_earnings_summary(db, d.id)
    
    commission = Decimal(str(summary["commission"]))
    pending = Decimal(str(summary["pending"]))
    
    if commission <= 0 or pending <= 0:
        raise HTTPException(status_code=400, detail="No commission or pending balance to settle")
        
    from ...models import DriverPayout
    payout = DriverPayout(
        driver_id=d.id,
        user_id=d.user_id,
        amount=pending,
        description="Commission settled (Cash balance offset)",
    )
    db.add(payout)
    await db.commit()
    
    return {"ok": True, "settled_amount": float(commission)}


@router.get("/incentives")
async def get_driver_incentives(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("driver")),
):
    """Get list of all active driver incentive tiers."""
    from ...models import DriverIncentive
    q = await db.execute(
        select(DriverIncentive)
        .where(DriverIncentive.is_active == True)
        .order_by(DriverIncentive.trips_required)
    )
    rows = q.scalars().all()
    return [
        {
            "id": r.id,
            "title": r.title,
            "limit_days": r.limit_days,
            "trips_required": r.trips_required,
            "reward_amount": float(r.reward_amount),
        }
        for r in rows
    ]


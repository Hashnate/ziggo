from datetime import datetime, timezone
from decimal import Decimal
from typing import List, Optional
import secrets

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from ...database import get_db
from ...models import (
    Booking,
    BookingStatus,
    Customer,
    Driver,
    User,
    UserRole,
    PromoCode,
    WalletTransaction,
    Notification,
)
from ...schemas import (
    FareEstimateRequest,
    FareEstimateResponse,
    BookingCreate,
    BookingResponse,
    BookingStatusUpdate,
    BookingRateRequest,
)
from ...services.auth_service import get_current_user
from ...services.fare_service import calculate_fare, to_decimal
from ...services.matching_service import find_all_nearby_drivers, find_nearest_driver
from ...services.ws_manager import manager

router = APIRouter()


def _gen_ref() -> str:
    return "ZG" + secrets.token_hex(4).upper()


async def _booking_to_response(db: AsyncSession, booking: Booking) -> BookingResponse:
    # Reload with driver+user joined so we can show driver details to the customer
    q = await db.execute(
        select(Booking)
        .options(selectinload(Booking.driver).selectinload(Driver.user))
        .where(Booking.id == booking.id)
    )
    b = q.scalars().first() or booking

    driver_obj = None
    if b.driver:
        driver_obj = {
            "id": b.driver.id,
            "full_name": b.driver.user.full_name if b.driver.user else None,
            "rating": float(b.driver.user.rating) if b.driver.user and b.driver.user.rating else None,
            "vehicle_type": b.driver.vehicle_type,
            "vehicle_number": b.driver.vehicle_number,
            "vehicle_model": b.driver.vehicle_model,
            "phone_number": b.driver.user.phone_number if b.driver.user else None,
            "current_lat": float(b.driver.current_lat) if b.driver.current_lat else None,
            "current_lng": float(b.driver.current_lng) if b.driver.current_lng else None,
        }

    return BookingResponse(
        id=b.id,
        booking_ref=b.booking_ref,
        status=b.status,
        service_type=b.service_type,
        trip_type=b.trip_type or "one_way",
        pickup_lat=float(b.pickup_lat),
        pickup_lng=float(b.pickup_lng),
        pickup_address=b.pickup_address,
        drop_lat=float(b.drop_lat),
        drop_lng=float(b.drop_lng),
        drop_address=b.drop_address,
        distance_km=float(b.distance_km) if b.distance_km else None,
        duration_min=b.duration_min,
        fare_amount=float(b.fare_amount) if b.fare_amount else None,
        discount_amount=float(b.discount_amount) if b.discount_amount else None,
        final_amount=float(b.final_amount) if b.final_amount else None,
        payment_method=b.payment_method,
        payment_status=b.payment_status,
        promo_code=b.promo_code,
        booked_at=b.booked_at,
        accepted_at=b.accepted_at,
        arrived_at=b.arrived_at,
        started_at=b.started_at,
        completed_at=b.completed_at,
        cancelled_at=b.cancelled_at,
        cancellation_reason=b.cancellation_reason,
        customer_rating=b.customer_rating,
        driver=driver_obj,
        is_flash=bool(b.is_flash),
        parcel_type=b.parcel_type,
        parcel_weight_kg=float(b.parcel_weight_kg) if b.parcel_weight_kg else None,
        receiver_name=b.receiver_name,
        receiver_phone=b.receiver_phone,
        parcel_instructions=b.parcel_instructions,
    )


async def _get_customer(db: AsyncSession, user: User) -> Customer:
    if user.role != UserRole.CUSTOMER:
        raise HTTPException(status_code=403, detail="Customer role required")
    q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = q.scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    return c


async def _get_driver(db: AsyncSession, user: User) -> Driver:
    if user.role != UserRole.DRIVER:
        raise HTTPException(status_code=403, detail="Driver role required")
    q = await db.execute(select(Driver).where(Driver.user_id == user.id))
    d = q.scalars().first()
    if not d:
        raise HTTPException(status_code=404, detail="Driver profile not found")
    return d


@router.post("/estimate", response_model=FareEstimateResponse)
async def estimate_fare(
    req: FareEstimateRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    fare = await calculate_fare(
        db,
        req.service_type,
        req.pickup_lat,
        req.pickup_lng,
        req.drop_lat,
        req.drop_lng,
        req.promo_code,
        trip_type=req.trip_type,
        is_flash=req.is_flash,
        parcel_weight_kg=req.parcel_weight_kg,
        is_rental=req.is_rental,
        rental_hours=req.rental_hours,
    )
    # FareEstimateResponse doesn't carry rental_hours/hourly_rate; strip them.
    fare.pop("hourly_rate", None)
    fare.pop("rental_hours", None)
    return FareEstimateResponse(service_type=req.service_type, **fare)


@router.post("", response_model=BookingResponse, status_code=201)
async def create_booking(
    req: BookingCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    customer = await _get_customer(db, user)

    fare = await calculate_fare(
        db,
        req.service_type,
        req.pickup_lat,
        req.pickup_lng,
        req.drop_lat,
        req.drop_lng,
        req.promo_code,
        trip_type=req.trip_type,
        is_flash=req.is_flash,
        parcel_weight_kg=req.parcel_weight_kg,
        is_rental=req.is_rental,
        rental_hours=req.rental_hours,
    )

    # If wallet payment, ensure balance
    if req.payment_method == "wallet" and float(customer.wallet_balance or 0) < fare["final_amount"]:
        raise HTTPException(status_code=400, detail="Insufficient wallet balance")

    # Flash deliveries must have a receiver phone — that's how the driver reaches them
    if req.is_flash and not (req.receiver_phone or "").strip():
        raise HTTPException(
            status_code=400,
            detail="Flash parcel requires receiver phone number",
        )
    # Rentals must specify a positive hour count
    if req.is_rental and not req.rental_hours:
        raise HTTPException(
            status_code=400,
            detail="Rental booking requires rental_hours",
        )
    if req.is_flash and req.is_rental:
        raise HTTPException(
            status_code=400,
            detail="A booking can't be both a flash parcel and a rental",
        )
    ref_prefix = "FL" if req.is_flash else ("RT" if req.is_rental else "ZG")
    booking = Booking(
        booking_ref=ref_prefix + secrets.token_hex(4).upper(),
        customer_id=customer.id,
        pickup_lat=Decimal(str(req.pickup_lat)),
        pickup_lng=Decimal(str(req.pickup_lng)),
        pickup_address=req.pickup_address,
        drop_lat=Decimal(str(req.drop_lat)),
        drop_lng=Decimal(str(req.drop_lng)),
        drop_address=req.drop_address,
        service_type=req.service_type,
        trip_type=req.trip_type,
        status=BookingStatus.SEARCHING,
        distance_km=to_decimal(fare["distance_km"]),
        duration_min=fare["duration_min"],
        fare_amount=to_decimal(fare["fare_amount"]),
        discount_amount=to_decimal(fare["discount_amount"]),
        final_amount=to_decimal(fare["final_amount"]),
        platform_fee=to_decimal(fare["platform_fee"]),
        driver_earnings=to_decimal(fare["driver_earnings"]),
        payment_method=req.payment_method,
        payment_status="pending",
        promo_code=fare["promo_code"],
        is_flash=req.is_flash,
        parcel_type=req.parcel_type,
        parcel_weight_kg=Decimal(str(req.parcel_weight_kg)) if req.parcel_weight_kg else None,
        receiver_name=req.receiver_name,
        receiver_phone=req.receiver_phone,
        parcel_instructions=req.parcel_instructions,
        is_rental=req.is_rental,
        rental_hours=req.rental_hours,
    )
    db.add(booking)
    await db.flush()

    # Broadcast to every nearby driver of the right vehicle type. The booking
    # stays SEARCHING until the first one taps "Accept" — at that point the
    # accept handler fires "ride_taken" to the rest so their request cards
    # dismiss. The race is resolved server-side by the status check in
    # accept_booking (later accepts get HTTP 409 "already taken").
    # Flash parcels broadcast to ANY nearby courier — vehicle type is just a
    # fare/surcharge hint, not a hard requirement (a tuk can carry a doc, a van
    # can carry a small parcel). Rides keep the strict vehicle-type filter.
    dispatch_vehicle = None if req.is_flash else req.service_type
    nearby = await find_all_nearby_drivers(
        db, req.pickup_lat, req.pickup_lng, dispatch_vehicle, max_distance_km=15
    )
    if booking.is_flash:
        n_title = "New parcel delivery"
        n_body = (
            f"{booking.parcel_type or 'Parcel'} • {booking.pickup_address} → "
            f"{booking.drop_address} • Rs.{int(booking.final_amount or 0)}"
        )
        n_type = "flash_request"
    elif booking.is_rental:
        n_title = "New rental booking"
        n_body = (
            f"{booking.rental_hours}h rental • {booking.pickup_address} • "
            f"Rs.{int(booking.final_amount or 0)}"
        )
        n_type = "rental_request"
    else:
        n_title = "New ride request"
        n_body = f"{booking.pickup_address} → {booking.drop_address} • Rs.{int(booking.final_amount or 0)}"
        n_type = "ride_request"

    ride_request_payload = {
        "booking_id": booking.id,
        "booking_ref": booking.booking_ref,
        "pickup_address": booking.pickup_address,
        "pickup_lat": float(booking.pickup_lat),
        "pickup_lng": float(booking.pickup_lng),
        "drop_address": booking.drop_address,
        "drop_lat": float(booking.drop_lat),
        "drop_lng": float(booking.drop_lng),
        "distance_km": float(booking.distance_km or 0),
        "duration_min": booking.duration_min,
        "service_type": booking.service_type,
        "trip_type": booking.trip_type or "one_way",
        "fare": float(booking.final_amount or 0),
        "driver_earnings": float(booking.driver_earnings or 0),
        "payment_method": booking.payment_method,
        "customer_name": user.full_name,
        "customer_phone": user.phone_number,
        "expires_in_seconds": 30,
        "is_flash": bool(booking.is_flash),
        "parcel_type": booking.parcel_type,
        "parcel_weight_kg": float(booking.parcel_weight_kg) if booking.parcel_weight_kg else None,
        "receiver_name": booking.receiver_name,
        "receiver_phone": booking.receiver_phone,
        "parcel_instructions": booking.parcel_instructions,
        "is_rental": bool(booking.is_rental),
        "rental_hours": booking.rental_hours,
    }

    for driver in nearby:
        await manager.send(driver.user_id, "new_ride_request", ride_request_payload)
        db.add(
            Notification(
                user_id=driver.user_id,
                title=n_title,
                body=n_body,
                type=n_type,
                data=f'{{"booking_id":{booking.id}}}',
            )
        )

    if not nearby:
        # No driver in range — tell the customer right away instead of leaving
        # them on a spinner that will never resolve.
        await manager.send(
            user.id,
            "no_drivers_available",
            {"booking_id": booking.id, "booking_ref": booking.booking_ref},
        )

    # Bump promo usage if applied
    if fare["promo_code"]:
        pq = await db.execute(select(PromoCode).where(PromoCode.code == fare["promo_code"]))
        p = pq.scalars().first()
        if p:
            p.used_count = (p.used_count or 0) + 1

    await db.commit()
    await db.refresh(booking)

    # Notify customer of status (so the WS-listening client gets the initial state)
    await manager.send(
        user.id,
        "booking_update",
        {"booking_id": booking.id, "status": booking.status.value},
    )

    return await _booking_to_response(db, booking)


@router.get("", response_model=List[BookingResponse])
async def list_my_bookings(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    limit: int = Query(50, le=200),
):
    if user.role == UserRole.CUSTOMER:
        customer = await _get_customer(db, user)
        q = await db.execute(
            select(Booking)
            .where(Booking.customer_id == customer.id)
            .order_by(Booking.booked_at.desc())
            .limit(limit)
        )
    elif user.role == UserRole.DRIVER:
        driver = await _get_driver(db, user)
        q = await db.execute(
            select(Booking)
            .where(Booking.driver_id == driver.id)
            .order_by(Booking.booked_at.desc())
            .limit(limit)
        )
    else:
        q = await db.execute(select(Booking).order_by(Booking.booked_at.desc()).limit(limit))

    bookings = q.scalars().all()
    return [await _booking_to_response(db, b) for b in bookings]


@router.get("/active", response_model=Optional[BookingResponse])
async def get_active_booking(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Return the customer's or driver's currently-in-progress booking, if any."""
    active = (
        BookingStatus.SEARCHING,
        BookingStatus.ACCEPTED,
        BookingStatus.ARRIVED,
        BookingStatus.STARTED,
        BookingStatus.PAYMENT_PENDING,
    )
    if user.role == UserRole.CUSTOMER:
        customer = await _get_customer(db, user)
        q = await db.execute(
            select(Booking)
            .where(Booking.customer_id == customer.id, Booking.status.in_(active))
            .order_by(Booking.id.desc())
        )
    elif user.role == UserRole.DRIVER:
        driver = await _get_driver(db, user)
        q = await db.execute(
            select(Booking)
            .where(Booking.driver_id == driver.id, Booking.status.in_(active))
            .order_by(Booking.id.desc())
        )
    else:
        return None

    b = q.scalars().first()
    return await _booking_to_response(db, b) if b else None


@router.get("/{booking_id}", response_model=BookingResponse)
async def get_booking(
    booking_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    # Auth: must be the customer, the assigned driver, or admin
    if user.role == UserRole.CUSTOMER:
        c = await _get_customer(db, user)
        if b.customer_id != c.id:
            raise HTTPException(status_code=403, detail="Not your booking")
    elif user.role == UserRole.DRIVER:
        d = await _get_driver(db, user)
        if b.driver_id != d.id:
            raise HTTPException(status_code=403, detail="Not your booking")
    return await _booking_to_response(db, b)


@router.post("/{booking_id}/accept", response_model=BookingResponse)
async def accept_booking(
    booking_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Driver accepts a ride request. Only works while booking is SEARCHING
    and no other driver has claimed it yet."""
    if user.role != UserRole.DRIVER:
        raise HTTPException(status_code=403, detail="Driver role required")
    driver = await _get_driver(db, user)
    if not driver.is_approved:
        raise HTTPException(status_code=403, detail="Account not approved")

    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")

    if b.status != BookingStatus.SEARCHING:
        raise HTTPException(
            status_code=409,
            detail="This ride has already been taken or cancelled",
        )

    # Claim the ride
    now = datetime.now(timezone.utc)
    b.driver_id = driver.id
    b.status = BookingStatus.ACCEPTED
    b.accepted_at = now
    await db.commit()
    await db.refresh(b)

    # Tell every OTHER nearby driver the ride is gone, so their pending request
    # card auto-dismisses (driver_provider listens for 'ride_taken'). We re-run
    # the same proximity query as create_booking to approximate "who was pinged".
    # Mirror create_booking: flash parcels were broadcast to ALL vehicle types,
    # so the dismissal needs to reach the same audience.
    other_drivers = await find_all_nearby_drivers(
        db,
        float(b.pickup_lat),
        float(b.pickup_lng),
        None if b.is_flash else b.service_type,
        max_distance_km=15,
        exclude_driver_id=driver.id,
    )
    for od in other_drivers:
        await manager.send(
            od.user_id,
            "ride_taken",
            {"booking_id": b.id, "booking_ref": b.booking_ref},
        )

    # Notify the customer that a driver accepted
    cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
    c = cq.scalars().first()
    if c:
        await manager.send(
            c.user_id,
            "booking_update",
            {"booking_id": b.id, "status": b.status.value},
        )
        db.add(
            Notification(
                user_id=c.user_id,
                title="Driver on the way",
                body=f"{user.full_name or 'Driver'} accepted your ride {b.booking_ref}",
                type="ride_update",
            )
        )
        await db.commit()

    return await _booking_to_response(db, b)


@router.post("/{booking_id}/decline")
async def decline_booking(
    booking_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Driver declines a ride request.

    Under broadcast dispatch, every nearby driver was pinged at create time, so
    decline is a per-driver dismissal — no forwarding. The booking stays in
    SEARCHING and any of the other pinged drivers can still accept.
    """
    if user.role != UserRole.DRIVER:
        raise HTTPException(status_code=403, detail="Driver role required")
    await _get_driver(db, user)

    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    return {"ok": True, "status": b.status.value}


VALID_TRANSITIONS = {
    BookingStatus.SEARCHING: {BookingStatus.ACCEPTED, BookingStatus.CANCELLED},
    BookingStatus.ACCEPTED: {BookingStatus.ARRIVED, BookingStatus.CANCELLED},
    BookingStatus.ARRIVED: {BookingStatus.STARTED, BookingStatus.CANCELLED},
    BookingStatus.STARTED: {BookingStatus.COMPLETED, BookingStatus.CANCELLED},
    BookingStatus.COMPLETED: set(),
    BookingStatus.CANCELLED: set(),
    BookingStatus.PAYMENT_PENDING: {BookingStatus.COMPLETED},
}


@router.patch("/{booking_id}/status", response_model=BookingResponse)
async def update_booking_status(
    booking_id: int,
    body: BookingStatusUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")

    new_status = body.status
    if new_status not in VALID_TRANSITIONS.get(b.status, set()):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot transition {b.status.value} -> {new_status.value}",
        )

    now = datetime.now(timezone.utc)
    b.status = new_status

    if new_status == BookingStatus.ARRIVED:
        b.arrived_at = now
    elif new_status == BookingStatus.STARTED:
        b.started_at = now
    elif new_status == BookingStatus.COMPLETED:
        b.completed_at = now
        b.payment_status = "paid"

        # Wallet debit if applicable
        if b.payment_method == "wallet":
            cust_q = await db.execute(select(Customer).where(Customer.id == b.customer_id))
            customer = cust_q.scalars().first()
            if customer:
                customer.wallet_balance = (customer.wallet_balance or Decimal(0)) - (b.final_amount or Decimal(0))
                db.add(
                    WalletTransaction(
                        user_id=customer.user_id,
                        amount=b.final_amount,
                        type="debit",
                        description=f"Ride {b.booking_ref}",
                        reference_id=b.booking_ref,
                        balance_after=customer.wallet_balance,
                    )
                )

        # Driver earnings
        if b.driver_id:
            dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
            drv = dq.scalars().first()
            if drv:
                drv.total_earnings = (drv.total_earnings or Decimal(0)) + (b.driver_earnings or Decimal(0))
                drv.today_earnings = (drv.today_earnings or Decimal(0)) + (b.driver_earnings or Decimal(0))
                drv.today_rides = (drv.today_rides or 0) + 1

    elif new_status == BookingStatus.CANCELLED:
        b.cancelled_at = now
        b.cancellation_reason = body.reason
        b.cancelled_by = user.role.value

    await db.commit()
    await db.refresh(b)

    # Push update to both parties
    if b.customer_id:
        cust_q = await db.execute(select(Customer).where(Customer.id == b.customer_id))
        c = cust_q.scalars().first()
        if c:
            await manager.send(
                c.user_id,
                "booking_update",
                {"booking_id": b.id, "status": b.status.value},
            )
            db.add(
                Notification(
                    user_id=c.user_id,
                    title=f"Ride {b.status.value.title()}",
                    body=f"Booking {b.booking_ref} is now {b.status.value}",
                    type="ride_update",
                )
            )
    if b.driver_id:
        dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
        drv = dq.scalars().first()
        if drv:
            await manager.send(
                drv.user_id,
                "booking_update",
                {"booking_id": b.id, "status": b.status.value},
            )
    await db.commit()

    return await _booking_to_response(db, b)


@router.post("/{booking_id}/rate", response_model=BookingResponse)
async def rate_booking(
    booking_id: int,
    body: BookingRateRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    if b.status != BookingStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Can only rate completed rides")

    if user.role == UserRole.CUSTOMER:
        c = await _get_customer(db, user)
        if b.customer_id != c.id:
            raise HTTPException(status_code=403, detail="Not your booking")
        b.customer_rating = body.rating
        b.customer_feedback = body.feedback
        # update driver aggregate rating
        if b.driver_id:
            dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
            drv = dq.scalars().first()
            if drv and drv.user_id:
                uq = await db.execute(select(User).where(User.id == drv.user_id))
                duser = uq.scalars().first()
                if duser:
                    prev = float(duser.rating or 0)
                    total = duser.total_rides or 0
                    new_total = total + 1
                    duser.rating = Decimal(str(round((prev * total + body.rating) / new_total, 2)))
                    duser.total_rides = new_total
    elif user.role == UserRole.DRIVER:
        d = await _get_driver(db, user)
        if b.driver_id != d.id:
            raise HTTPException(status_code=403, detail="Not your booking")
        b.driver_rating = body.rating
        b.driver_feedback = body.feedback

    await db.commit()
    await db.refresh(b)
    return await _booking_to_response(db, b)

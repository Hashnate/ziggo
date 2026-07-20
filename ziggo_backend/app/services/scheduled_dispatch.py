import asyncio
from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from ..database import AsyncSessionLocal
from ..models import Booking, BookingStatus, Notification, Customer, Driver, User
from .ws_manager import manager
from .matching_service import find_all_nearby_drivers
from ..api.v1.bookings import get_search_radius_for_service

TICK_SECONDS = 30
LEAD_TIME_MINUTES = 10

async def _dispatch_booking(db, booking: Booking) -> None:
    # Mark as sent immediately so we don't duplicate dispatch on network delay
    booking.scheduled_dispatch_sent = True
    await db.commit()
    await db.refresh(booking)

    print(f"[scheduled_dispatch] Dispatching booking {booking.booking_ref} scheduled at {booking.scheduled_at}")

    # Resolve customer user details
    customer_user = None
    if booking.customer and booking.customer.user:
        customer_user = booking.customer.user

    # Fetch customer name and phone
    customer_name = customer_user.full_name if customer_user else "Customer"
    customer_phone = customer_user.phone_number if customer_user else ""

    dispatch_vehicle = None if (booking.is_flash or booking.is_courier) else booking.service_type
    max_radius = await get_search_radius_for_service(db, dispatch_vehicle)

    nearby = await find_all_nearby_drivers(
        db, booking.pickup_lat, booking.pickup_lng, dispatch_vehicle, max_distance_km=max_radius
    )
    # Only ride-type drivers receive scheduled ride-hailing/parcel booking dispatches
    nearby = [d for d in nearby if getattr(d, 'driver_type', 'ride') == 'ride']
    if booking.is_flash or booking.is_courier:
        weight = float(booking.parcel_weight_kg or 0)
        filtered = []
        for d in nearby:
            vt = (d.vehicle_type or "").lower().strip()
            if vt == "car":
                continue
            if vt == "bike" and weight > 5.0:
                continue
            if vt == "tuk" and weight > 15.0:
                continue
            if vt == "van" and weight > 100.0:
                continue
            filtered.append(d)
        nearby = filtered

    if booking.is_courier:
        n_title = "New courier delivery"
        n_body = (
            f"{booking.parcel_type or 'Parcel'} • {booking.pickup_address} → "
            f"{booking.drop_address} • {booking.courier_eta_days or 2}-day • "
            f"Rs.{int(booking.final_amount or 0)}"
        )
        n_type = "courier_request"
    elif booking.is_flash:
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
        "customer_name": customer_name,
        "customer_phone": customer_phone,
        "expires_in_seconds": 30,
        "is_flash": bool(booking.is_flash),
        "parcel_type": booking.parcel_type,
        "parcel_weight_kg": float(booking.parcel_weight_kg) if booking.parcel_weight_kg else None,
        "receiver_name": booking.receiver_name,
        "receiver_phone": booking.receiver_phone,
        "parcel_instructions": booking.parcel_instructions,
        "is_rental": bool(booking.is_rental),
        "rental_hours": booking.rental_hours,
        "is_courier": bool(booking.is_courier),
        "courier_eta_days": booking.courier_eta_days,
        "stop_count": booking.stop_count or 0,
        "stops": [
            {
                "order_index": s.order_index,
                "lat": float(s.lat),
                "lng": float(s.lng),
                "address": s.address or "",
            }
            for s in (booking.stops or [])
        ],
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
        # If no driver in range, we notify the customer
        if customer_user:
            await manager.send(
                customer_user.id,
                "no_drivers_available",
                {"booking_id": booking.id, "booking_ref": booking.booking_ref},
            )

    # Commit the driver notifications
    await db.commit()

    # Notify customer of status change/search starting
    if customer_user:
        await manager.send(
            customer_user.id,
            "booking_update",
            {"booking_id": booking.id, "status": booking.status.value},
        )


async def _run_once() -> None:
    cutoff = datetime.now(timezone.utc) + timedelta(minutes=LEAD_TIME_MINUTES)
    async with AsyncSessionLocal() as db:
        q = await db.execute(
            select(Booking)
            .options(
                selectinload(Booking.stops),
                selectinload(Booking.customer).selectinload(Customer.user),
            )
            .where(
                Booking.status == BookingStatus.SEARCHING,
                Booking.scheduled_at != None,
                Booking.scheduled_dispatch_sent == False,
                Booking.scheduled_at <= cutoff,
            )
        )
        due_bookings = q.scalars().all()
        for b in due_bookings:
            try:
                await _dispatch_booking(db, b)
            except Exception as e:
                print(f"[scheduled_dispatch] Failed to dispatch {b.booking_ref}: {e!r}")


async def scheduled_dispatch_loop() -> None:
    """Long-running task to sweep and dispatch scheduled bookings."""
    print("[scheduled_dispatch] Starting scheduled dispatch background loop")
    while True:
        try:
            await _run_once()
        except Exception as e:
            print(f"[scheduled_dispatch] sweep error: {e!r}")
        await asyncio.sleep(TICK_SECONDS)

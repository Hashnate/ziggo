from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Dict, List, Optional
import secrets

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select
from sqlalchemy.orm import selectinload
from pydantic import BaseModel

from ...database import get_db
from ...models import (
    Booking,
    BookingStatus,
    BookingMessage,
    Customer,
    Driver,
    User,
    UserRole,
    PromoCode,
    WalletTransaction,
    Notification,
    CustomerCard,
    Payment,
    SystemSettings,
    FoodOrder,
    FoodOrderStatus,
    MarketOrder,
    MarketOrderStatus,
)
from ...schemas import (
    FareEstimateRequest,
    FareEstimateResponse,
    BulkFareEstimateRequest,
    BookingCreate,
    BookingResponse,
    BookingStatusUpdate,
    BookingRateRequest,
    BookingUpdateDestinationRequest,
)
from ...services.auth_service import get_current_user
from ...services.fare_service import calculate_fare, to_decimal
from ...services.matching_service import find_all_nearby_drivers, find_nearest_driver
from ...services.ws_manager import manager
from ...services import payhere_service

router = APIRouter()


def _gen_ref() -> str:
    return "ZG" + secrets.token_hex(4).upper()


async def get_search_radius_for_service(db: AsyncSession, service_type: Optional[str]) -> int:
    if service_type:
        from ...models import FareSetting
        q = await db.execute(select(FareSetting).where(FareSetting.service_type == service_type))
        fs = q.scalars().first()
        if fs and fs.search_radius_km is not None and fs.search_radius_km > 0:
            return fs.search_radius_km

    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    if ss and ss.driver_search_radius_km is not None:
        return ss.driver_search_radius_km

    return 15


async def _booking_to_response(db: AsyncSession, booking: Booking) -> BookingResponse:
    # Reload with driver+user joined so we can show driver details to the customer,
    # and customer+user joined so the driver can see customer contact details.
    q = await db.execute(
        select(Booking)
        .options(
            selectinload(Booking.driver).selectinload(Driver.user),
            selectinload(Booking.customer).selectinload(Customer.user),
            selectinload(Booking.stops),
        )
        .where(Booking.id == booking.id)
    )
    b = q.scalars().first() or booking

    driver_obj = None
    if b.driver:
        from sqlalchemy import func
        from ...models import DriverDocument
        
        trip_count_q = await db.execute(
            select(func.count(Booking.id)).where(
                Booking.driver_id == b.driver.id,
                Booking.status == "completed"
            )
        )
        actual_trips = trip_count_q.scalar() or 0

        # Get vehicle_front photo from driver documents
        doc_q = await db.execute(
            select(DriverDocument).where(
                DriverDocument.driver_id == b.driver.id,
                DriverDocument.document_type == 'vehicle_front'
            )
        )
        vehicle_doc = doc_q.scalars().first()
        actual_vehicle_photo = vehicle_doc.document_url if vehicle_doc else b.driver.vehicle_photo_url

        driver_obj = {
            "id": b.driver.id,
            "full_name": b.driver.user.full_name if b.driver.user else None,
            "rating": float(b.driver.user.rating) if b.driver.user and b.driver.user.rating else None,
            "vehicle_type": b.driver.vehicle_type,
            "vehicle_number": b.driver.vehicle_number,
            "vehicle_model": b.driver.vehicle_model,
            "vehicle_color": b.driver.vehicle_color,
            "phone_number": b.driver.user.phone_number if b.driver.user else None,
            "current_lat": float(b.driver.current_lat) if b.driver.current_lat else None,
            "current_lng": float(b.driver.current_lng) if b.driver.current_lng else None,
            "current_heading": float(b.driver.current_heading) if b.driver.current_heading is not None else 0.0,
            "profile_photo": b.driver.user.profile_photo if b.driver.user else None,
            "vehicle_photo_url": actual_vehicle_photo,
            "completed_trips": actual_trips,
        }

    customer_name = b.customer.user.full_name if b.customer and b.customer.user else None
    customer_phone = b.customer.user.phone_number if b.customer and b.customer.user else None

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
        customer_name=customer_name,
        customer_phone=customer_phone,
        otp=b.otp,
        is_flash=bool(b.is_flash),
        parcel_type=b.parcel_type,
        parcel_weight_kg=float(b.parcel_weight_kg) if b.parcel_weight_kg else None,
        receiver_name=b.receiver_name,
        receiver_phone=b.receiver_phone,
        parcel_instructions=b.parcel_instructions,
        is_courier=bool(b.is_courier),
        courier_eta_days=b.courier_eta_days,
        pickup_fee=float(b.pickup_fee) if b.pickup_fee is not None else 0.0,
        boost=float(b.boost) if b.boost is not None else 0.0,
        peak_surcharge=float(b.peak_surcharge) if b.peak_surcharge is not None else 0.0,
        passenger_deductible=float(b.passenger_deductible) if b.passenger_deductible is not None else 0.0,
        app_usage_charges=float(b.app_usage_charges) if b.app_usage_charges is not None else 0.0,
        deductions=float(b.deductions) if b.deductions is not None else 0.0,
        driver_earnings=float(b.driver_earnings) if b.driver_earnings is not None else 0.0,
        stops=[
            {
                "order_index": s.order_index,
                "lat": float(s.lat),
                "lng": float(s.lng),
                "address": s.address,
            }
            for s in (b.stops or [])
        ],
    )


async def _food_order_to_booking_response(db: AsyncSession, order: FoodOrder) -> BookingResponse:
    from sqlalchemy.orm import selectinload
    from ...services.finance_service import _food_split
    from ...services.fare_service import haversine_km

    status_map = {
        FoodOrderStatus.PENDING: BookingStatus.SEARCHING,
        FoodOrderStatus.CONFIRMED: BookingStatus.ACCEPTED,
        FoodOrderStatus.PREPARING: BookingStatus.STARTED,
        FoodOrderStatus.READY_FOR_PICKUP: BookingStatus.STARTED,
        FoodOrderStatus.OUT_FOR_DELIVERY: BookingStatus.STARTED,
        FoodOrderStatus.DELIVERED: BookingStatus.COMPLETED,
        FoodOrderStatus.CANCELLED: BookingStatus.CANCELLED,
    }
    booking_status = status_map.get(order.status, BookingStatus.SEARCHING)

    dist_km = 0.0
    if order.restaurant.lat is not None and order.restaurant.lng is not None and order.delivery_lat is not None and order.delivery_lng is not None:
        dist_km = haversine_km(float(order.restaurant.lat), float(order.restaurant.lng), float(order.delivery_lat), float(order.delivery_lng))

    duration_min = 0
    if order.delivered_at and order.picked_up_at:
        duration_min = int((order.delivered_at - order.picked_up_at).total_seconds() / 60)

    try:
        keep, cut = _food_split(order)
    except Exception:
        keep, cut = order.delivery_fee or 0, 0

    driver_obj = None
    if order.driver_id:
        drv_q = await db.execute(
            select(Driver).options(selectinload(Driver.user)).where(Driver.id == order.driver_id)
        )
        drv = drv_q.scalars().first()
        if drv:
            trip_count_q = await db.execute(
                select(func.count(Booking.id)).where(
                    Booking.driver_id == drv.id,
                    Booking.status == BookingStatus.COMPLETED
                )
            )
            actual_trips = trip_count_q.scalar() or 0
            driver_obj = {
                "id": drv.id,
                "full_name": drv.user.full_name if drv.user else None,
                "rating": float(drv.user.rating) if drv.user and drv.user.rating else None,
                "vehicle_type": drv.vehicle_type,
                "vehicle_number": drv.vehicle_number,
                "vehicle_model": drv.vehicle_model,
                "phone_number": drv.user.phone_number if drv.user else None,
                "current_lat": float(drv.current_lat) if drv.current_lat else None,
                "current_lng": float(drv.current_lng) if drv.current_lng else None,
                "current_heading": float(drv.current_heading) if drv.current_heading is not None else 0.0,
                "profile_photo": drv.user.profile_photo if drv.user else None,
                "completed_trips": actual_trips,
            }

    cust_name = None
    cust_phone = None
    if order.customer_id:
        cust_q = await db.execute(
            select(Customer).options(selectinload(Customer.user)).where(Customer.id == order.customer_id)
        )
        cust = cust_q.scalars().first()
        if cust and cust.user:
            cust_name = cust.user.full_name
            cust_phone = cust.user.phone_number

    pickup_fee = float(order.restaurant.pickup_fee) if order.restaurant.pickup_fee is not None else 70.0
    boost = float(order.restaurant.boost) if order.restaurant.boost is not None else 0.0

    return BookingResponse(
        id=order.id,
        booking_ref=order.order_ref,
        status=booking_status,
        service_type="food",
        trip_type="one_way",
        pickup_lat=float(order.restaurant.lat) if order.restaurant.lat is not None else 0.0,
        pickup_lng=float(order.restaurant.lng) if order.restaurant.lng is not None else 0.0,
        pickup_address=order.restaurant.address or order.restaurant.name,
        drop_lat=float(order.delivery_lat) if order.delivery_lat is not None else 0.0,
        drop_lng=float(order.delivery_lng) if order.delivery_lng is not None else 0.0,
        drop_address=order.delivery_address,
        distance_km=float(dist_km),
        duration_min=duration_min,
        fare_amount=float(order.delivery_fee or 0),
        discount_amount=float(order.discount_amount or 0),
        final_amount=float(order.final_amount or 0),
        payment_method=order.payment_method,
        payment_status=order.payment_status,
        booked_at=order.created_at,
        accepted_at=order.confirmed_at,
        started_at=order.picked_up_at,
        completed_at=order.delivered_at,
        cancelled_at=None,
        customer_name=cust_name,
        customer_phone=cust_phone,
        driver=driver_obj,
        pickup_fee=pickup_fee,
        boost=boost,
        passenger_deductible=0.0,
        app_usage_charges=float(order.delivery_fee or 0) - float(keep),
        deductions=float(order.delivery_fee or 0) - float(keep),
        driver_earnings=float(keep),
        is_food=True,
        is_market=False,
        items_price=float(order.total_amount or 0),
        restaurant_name=order.restaurant.name,
        stops=[]
    )


async def _market_order_to_booking_response(db: AsyncSession, order: MarketOrder) -> BookingResponse:
    from ...services.finance_service import _market_split

    status_map = {
        MarketOrderStatus.PENDING: BookingStatus.SEARCHING,
        MarketOrderStatus.CONFIRMED: BookingStatus.ACCEPTED,
        MarketOrderStatus.PREPARING: BookingStatus.STARTED,
        MarketOrderStatus.READY_FOR_PICKUP: BookingStatus.STARTED,
        MarketOrderStatus.OUT_FOR_DELIVERY: BookingStatus.STARTED,
        MarketOrderStatus.DELIVERED: BookingStatus.COMPLETED,
        MarketOrderStatus.CANCELLED: BookingStatus.CANCELLED,
    }
    booking_status = status_map.get(order.status, BookingStatus.SEARCHING)

    duration_min = 0
    if order.delivered_at and order.picked_up_at:
        duration_min = int((order.delivered_at - order.picked_up_at).total_seconds() / 60)

    try:
        keep, cut = _market_split(order)
    except Exception:
        keep, cut = order.delivery_fee or 0, 0

    driver_obj = None
    if order.driver_id:
        drv_q = await db.execute(
            select(Driver).options(selectinload(Driver.user)).where(Driver.id == order.driver_id)
        )
        drv = drv_q.scalars().first()
        if drv:
            trip_count_q = await db.execute(
                select(func.count(Booking.id)).where(
                    Booking.driver_id == drv.id,
                    Booking.status == BookingStatus.COMPLETED
                )
            )
            actual_trips = trip_count_q.scalar() or 0
            driver_obj = {
                "id": drv.id,
                "full_name": drv.user.full_name if drv.user else None,
                "rating": float(drv.user.rating) if drv.user and drv.user.rating else None,
                "vehicle_type": drv.vehicle_type,
                "vehicle_number": drv.vehicle_number,
                "vehicle_model": drv.vehicle_model,
                "phone_number": drv.user.phone_number if drv.user else None,
                "current_lat": float(drv.current_lat) if drv.current_lat else None,
                "current_lng": float(drv.current_lng) if drv.current_lng else None,
                "current_heading": float(drv.current_heading) if drv.current_heading is not None else 0.0,
                "profile_photo": drv.user.profile_photo if drv.user else None,
                "completed_trips": actual_trips,
            }

    cust_name = None
    cust_phone = None
    if order.customer_id:
        cust_q = await db.execute(
            select(Customer).options(selectinload(Customer.user)).where(Customer.id == order.customer_id)
        )
        cust = cust_q.scalars().first()
        if cust and cust.user:
            cust_name = cust.user.full_name
            cust_phone = cust.user.phone_number

    pickup_fee = float(order.vendor.pickup_fee) if order.vendor.pickup_fee is not None else 70.0
    boost = float(order.vendor.boost) if order.vendor.boost is not None else 0.0

    return BookingResponse(
        id=order.id,
        booking_ref=order.order_ref,
        status=booking_status,
        service_type="market",
        trip_type="one_way",
        pickup_lat=float(order.vendor.lat) if order.vendor.lat is not None else 0.0,
        pickup_lng=float(order.vendor.lng) if order.vendor.lng is not None else 0.0,
        pickup_address=order.vendor.address or order.vendor.name,
        drop_lat=float(order.delivery_lat) if order.delivery_lat is not None else 0.0,
        drop_lng=float(order.delivery_lng) if order.delivery_lng is not None else 0.0,
        drop_address=order.delivery_address,
        distance_km=float(order.delivery_distance_km) if order.delivery_distance_km else 0.0,
        duration_min=duration_min,
        fare_amount=float(order.delivery_fee or 0),
        discount_amount=float(order.discount_amount or order.redeem_discount or 0),
        final_amount=float(order.final_amount or 0),
        payment_method=order.payment_method,
        payment_status=order.payment_status,
        booked_at=order.created_at,
        accepted_at=order.confirmed_at,
        started_at=order.picked_up_at,
        completed_at=order.delivered_at,
        cancelled_at=None,
        customer_name=cust_name,
        customer_phone=cust_phone,
        driver=driver_obj,
        pickup_fee=pickup_fee,
        boost=boost,
        passenger_deductible=0.0,
        app_usage_charges=float(order.delivery_fee or 0) - float(keep),
        deductions=float(order.delivery_fee or 0) - float(keep),
        driver_earnings=float(keep),
        is_food=False,
        is_market=True,
        items_price=float(order.total_amount or 0),
        vendor_name=order.vendor.name,
        stops=[]
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
    # Customer is only needed when the estimate also previews a points
    # redemption. Avoid lazy-loading it through the User relationship —
    # async SQLAlchemy refuses that and we don't need it for plain estimates.
    customer = None
    if (req.redeem_points or 0) > 0:
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
        is_courier=req.is_courier,
        customer=customer,
        redeem_points=req.redeem_points or 0,
        stops=[s.model_dump() for s in (req.stops or [])],
    )
    # FareEstimateResponse doesn't carry rental_hours/hourly_rate; strip them.
    fare.pop("hourly_rate", None)
    fare.pop("rental_hours", None)
    return FareEstimateResponse(service_type=req.service_type, **fare)


@router.post("/estimate/bulk", response_model=Dict[str, FareEstimateResponse])
async def estimate_fare_bulk(
    req: BulkFareEstimateRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    customer = None
    if (req.redeem_points or 0) > 0:
        customer = await _get_customer(db, user)
        
    results = {}
    if "truck" not in req.service_types:
        req.service_types.append("truck")
        
    for st in req.service_types:
        try:
            fare = await calculate_fare(
                db,
                st,
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
                is_courier=req.is_courier,
                customer=customer,
                redeem_points=req.redeem_points or 0,
                stops=[s.model_dump() for s in (req.stops or [])],
            )
            fare.pop("hourly_rate", None)
            fare.pop("rental_hours", None)
            fare["service_type"] = st
            results[st] = fare
        except Exception as e:
            import logging
            logging.error(f"Error calculating fare for {st}: {e}", exc_info=True)
            # Skip or log error for this specific service type
            continue
            
    return results


@router.post("", response_model=BookingResponse, status_code=201)
async def create_booking(
    req: BookingCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    customer = await _get_customer(db, user)

    # BRD: CD-19 — clamp to admin-configured max stops before pricing.
    from ...models import SystemSettings
    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    max_stops = int(ss.multi_stop_max_count) if ss and ss.multi_stop_max_count is not None else 2
    incoming_stops = list(req.stops or [])
    if len(incoming_stops) > max_stops:
        raise HTTPException(
            status_code=400,
            detail=f"Up to {max_stops} intermediate stop(s) allowed; got {len(incoming_stops)}",
        )
    # Flash, courier and rental trips don't make sense with multi-stop. The
    # dispatcher doesn't know how to handle a parcel with intermediate
    # addresses, and a rental is by-the-hour so distance doesn't drive the fare.
    if incoming_stops and (req.is_flash or req.is_courier or req.is_rental):
        raise HTTPException(
            status_code=400,
            detail="Intermediate stops are not supported on flash, courier or rental bookings",
        )

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
        is_courier=req.is_courier,
        customer=customer,
        redeem_points=req.redeem_points or 0,
        stops=[s.model_dump() for s in incoming_stops],
    )

    # If wallet payment, ensure balance
    corporate_acct = None
    if req.payment_method == "wallet" and float(customer.wallet_balance or 0) < fare["final_amount"]:
        raise HTTPException(status_code=400, detail="Insufficient wallet balance")
    elif req.payment_method == "corporate":
        # BRD: PY-05 — corporate billing: verify membership and balance
        from ...models import CorporateMember, CorporateAccount
        mq = await db.execute(
            select(CorporateMember).where(
                CorporateMember.user_id == user.id,
                CorporateMember.status == "active",
            )
        )
        membership = mq.scalars().first()
        if not membership:
            raise HTTPException(status_code=403, detail="Not linked to an active corporate account")
        aq = await db.execute(
            select(CorporateAccount).where(CorporateAccount.id == membership.corporate_id)
        )
        corporate_acct = aq.scalars().first()
        if not corporate_acct or float(corporate_acct.balance or 0) < fare["final_amount"]:
            raise HTTPException(status_code=400, detail="Insufficient corporate balance")
    elif req.payment_method and req.payment_method.startswith("card_"):
        try:
            card_id = int(req.payment_method.split("_")[1])
        except (ValueError, IndexError):
            card_id = None
        if not card_id:
            raise HTTPException(status_code=400, detail="Invalid card selection")
        card_q = await db.execute(
            select(CustomerCard).where(CustomerCard.id == card_id, CustomerCard.customer_id == customer.id)
        )
        card = card_q.scalars().first()
        if not card:
            raise HTTPException(status_code=400, detail="Card not found")

    # Parcel deliveries (flash or courier) must have a receiver phone — that's
    # how the driver/courier reaches the recipient.
    if (req.is_flash or req.is_courier) and not (req.receiver_phone or "").strip():
        raise HTTPException(
            status_code=400,
            detail="Parcel delivery requires receiver phone number",
        )
    # Rentals must specify a positive hour count
    if req.is_rental and not req.rental_hours:
        raise HTTPException(
            status_code=400,
            detail="Rental booking requires rental_hours",
        )
    # A booking is exactly one service type — reject contradictory combinations.
    if sum([bool(req.is_flash), bool(req.is_courier), bool(req.is_rental)]) > 1:
        raise HTTPException(
            status_code=400,
            detail="A booking can only be one of flash, courier or rental",
        )
    ref_prefix = (
        "CR" if req.is_courier
        else "FL" if req.is_flash
        else "RT" if req.is_rental
        else "ZG"
    )
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
        redeem_points=int(fare.get("redeem_points_used", 0) or 0),
        redeem_discount=to_decimal(fare.get("redeem_discount", 0) or 0),
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
        is_courier=req.is_courier,
        courier_eta_days=fare.get("courier_eta_days") if req.is_courier else None,
        is_rental=req.is_rental,
        rental_hours=req.rental_hours,
        is_corporate=req.payment_method == "corporate",
        corporate_id=corporate_acct.id if corporate_acct else None,
        pickup_fee=to_decimal(fare.get("pickup_fee", 0)),
        boost=to_decimal(fare.get("boost", 0)),
        peak_surcharge=to_decimal(fare.get("peak_surcharge", 0)),
        passenger_deductible=to_decimal(fare.get("passenger_deductible", 0)),
        app_usage_charges=to_decimal(fare.get("app_usage_charges", 0)),
        deductions=to_decimal(fare.get("deductions", 0)),
    )
    db.add(booking)
    await db.flush()

    # BRD: CD-19 — snapshot intermediate stops + the waiting policy in effect
    # at booking time (so future admin tuning doesn't retroactively re-bill).
    if incoming_stops:
        from ...models import BookingStop
        free_secs = int((ss.multi_stop_free_minutes if ss else 3) or 3) * 60
        excess_rate = ss.multi_stop_excess_per_minute if (ss and ss.multi_stop_excess_per_minute is not None) else Decimal("5")
        for idx, stop in enumerate(incoming_stops, start=1):
            db.add(BookingStop(
                booking_id=booking.id,
                order_index=idx,
                lat=Decimal(str(stop.lat)),
                lng=Decimal(str(stop.lng)),
                address=stop.address,
                free_wait_seconds=free_secs,
                excess_rate_per_minute=Decimal(str(excess_rate)),
            ))
        booking.stop_count = len(incoming_stops)

    # BRD: RW-02 — deduct redeemed points now (at booking time) so they can't be
    # double-spent on another booking before this one completes. If the ride is
    # cancelled later we refund via update_booking_status.
    if booking.redeem_points and booking.redeem_points > 0:
        from ...services.loyalty_service import redeem_points as _redeem
        await _redeem(
            db, customer,
            points=int(booking.redeem_points),
            source_kind="booking",
            source_id=booking.id,
            description=f"Redeemed on {booking.booking_ref}",
        )

    # Broadcast to every nearby driver of the right vehicle type. The booking
    # stays SEARCHING until the first one taps "Accept" — at that point the
    # accept handler fires "ride_taken" to the rest so their request cards
    # dismiss. The race is resolved server-side by the status check in
    # accept_booking (later accepts get HTTP 409 "already taken").
    # Flash parcels broadcast to ANY nearby courier — vehicle type is just a
    # fare/surcharge hint, not a hard requirement (a tuk can carry a doc, a van
    # can carry a small parcel). Rides keep the strict vehicle-type filter.
    dispatch_vehicle = None if (req.is_flash or req.is_courier) else req.service_type

    max_radius = await get_search_radius_for_service(db, dispatch_vehicle)

    nearby = await find_all_nearby_drivers(
        db, req.pickup_lat, req.pickup_lng, dispatch_vehicle, max_distance_km=max_radius
    )
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
        "is_courier": bool(booking.is_courier),
        "courier_eta_days": booking.courier_eta_days,
        # BRD: CD-19 — intermediate stops so the driver popup can render them
        "stop_count": booking.stop_count or 0,
        "stops": [
            {
                "order_index": idx,
                "lat": float(s.lat),
                "lng": float(s.lng),
                "address": s.address or "",
            }
            for idx, s in enumerate(incoming_stops or [], start=1)
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


@router.post("/scan-and-go", response_model=BookingResponse, status_code=201)
async def scan_and_go_booking(
    req: BookingCreate,
    driver_id: int = Query(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    customer = await _get_customer(db, user)

    # Verify driver exists and is approved
    dq = await db.execute(
        select(Driver)
        .options(selectinload(Driver.user))
        .where(Driver.id == driver_id)
    )
    driver = dq.scalars().first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")
    if not driver.is_approved:
        raise HTTPException(status_code=400, detail="Driver is not approved")

    # Calculate fare
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
        is_courier=req.is_courier,
        customer=customer,
        redeem_points=req.redeem_points or 0,
        stops=[s.model_dump() for s in (req.stops or [])],
    )

    # Check wallet payment balance
    if req.payment_method == "wallet" and float(customer.wallet_balance or 0) < fare["final_amount"]:
        raise HTTPException(status_code=400, detail="Insufficient wallet balance")

    ref_prefix = (
        "CR" if req.is_courier
        else "FL" if req.is_flash
        else "RT" if req.is_rental
        else "ZG"
    )

    now = datetime.now(timezone.utc)
    booking = Booking(
        booking_ref=ref_prefix + secrets.token_hex(4).upper(),
        customer_id=customer.id,
        driver_id=driver.id,
        pickup_lat=Decimal(str(req.pickup_lat)),
        pickup_lng=Decimal(str(req.pickup_lng)),
        pickup_address=req.pickup_address,
        drop_lat=Decimal(str(req.drop_lat)),
        drop_lng=Decimal(str(req.drop_lng)),
        drop_address=req.drop_address,
        service_type=req.service_type,
        trip_type=req.trip_type,
        status=BookingStatus.ACCEPTED,  # Set directly to ACCEPTED
        accepted_at=now,
        distance_km=to_decimal(fare["distance_km"]),
        duration_min=fare["duration_min"],
        fare_amount=to_decimal(fare["fare_amount"]),
        discount_amount=to_decimal(fare["discount_amount"]),
        redeem_points=int(fare.get("redeem_points_used", 0) or 0),
        redeem_discount=to_decimal(fare.get("redeem_discount", 0) or 0),
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
        is_courier=req.is_courier,
        courier_eta_days=fare.get("courier_eta_days") if req.is_courier else None,
        is_rental=req.is_rental,
        rental_hours=req.rental_hours,
        pickup_fee=to_decimal(fare.get("pickup_fee", 0)),
        boost=to_decimal(fare.get("boost", 0)),
        peak_surcharge=to_decimal(fare.get("peak_surcharge", 0)),
        passenger_deductible=to_decimal(fare.get("passenger_deductible", 0)),
        app_usage_charges=to_decimal(fare.get("app_usage_charges", 0)),
        deductions=to_decimal(fare.get("deductions", 0)),
    )
    db.add(booking)
    await db.flush()

    if booking.redeem_points and booking.redeem_points > 0:
        from ...services.loyalty_service import redeem_points as _redeem
        await _redeem(
            db, customer,
            points=int(booking.redeem_points),
            source_kind="booking",
            source_id=booking.id,
            description=f"Redeemed on {booking.booking_ref}",
        )

    if fare["promo_code"]:
        pq = await db.execute(select(PromoCode).where(PromoCode.code == fare["promo_code"]))
        p = pq.scalars().first()
        if p:
            p.used_count = (p.used_count or 0) + 1

    await db.commit()
    await db.refresh(booking)

    # Notify driver (via ws manager) so their app transitions
    if driver.user_id:
        await manager.send(
            driver.user_id,
            "booking_update",
            {"booking_id": booking.id, "status": booking.status.value},
        )
        db.add(
            Notification(
                user_id=driver.user_id,
                title="Scan & Go Trip Started",
                body=f"A passenger scanned your QR code and started ride {booking.booking_ref}",
                type="ride_update",
            )
        )
        await db.commit()

    # Notify customer
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
        bookings = q.scalars().all()
        return [await _booking_to_response(db, b) for b in bookings]
    elif user.role == UserRole.DRIVER:
        driver = await _get_driver(db, user)
        q = await db.execute(
            select(Booking)
            .where(Booking.driver_id == driver.id)
            .order_by(Booking.booked_at.desc())
            .limit(limit)
        )
        bookings = q.scalars().all()

        fq = await db.execute(
            select(FoodOrder)
            .options(selectinload(FoodOrder.restaurant))
            .where(FoodOrder.driver_id == driver.id)
            .order_by(FoodOrder.created_at.desc())
            .limit(limit)
        )
        foods = fq.scalars().all()

        mq = await db.execute(
            select(MarketOrder)
            .options(selectinload(MarketOrder.vendor))
            .where(MarketOrder.driver_id == driver.id)
            .order_by(MarketOrder.created_at.desc())
            .limit(limit)
        )
        markets = mq.scalars().all()

        res = []
        for b in bookings:
            res.append((b.booked_at, await _booking_to_response(db, b)))
        for f in foods:
            res.append((f.created_at, await _food_order_to_booking_response(db, f)))
        for m in markets:
            res.append((m.created_at, await _market_order_to_booking_response(db, m)))

        res.sort(key=lambda x: x[0].astimezone(timezone.utc) if x[0] else datetime.min.replace(tzinfo=timezone.utc), reverse=True)
        final_res = [x[1] for x in res[:limit]]
        return final_res
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
    
    if driver.current_lat is not None and driver.current_lng is not None:
        b.driver_accepted_lat = Decimal(str(driver.current_lat))
        b.driver_accepted_lng = Decimal(str(driver.current_lng))

    from ...models import BookingStop
    sq = await db.execute(select(BookingStop).where(BookingStop.booking_id == b.id))
    booking_stops = sq.scalars().all()
    stops_list = []
    for s in booking_stops:
        stops_list.append({
            "lat": float(s.lat),
            "lng": float(s.lng),
            "address": s.address,
        })

    # Recalculate fare now that we have driver coordinates for pickup fee
    fare = await calculate_fare(
        db,
        b.service_type,
        float(b.pickup_lat),
        float(b.pickup_lng),
        float(b.drop_lat) if b.drop_lat else 0.0,
        float(b.drop_lng) if b.drop_lng else 0.0,
        b.promo_code,
        trip_type=b.trip_type or "one_way",
        is_flash=b.is_flash,
        parcel_weight_kg=float(b.parcel_weight_kg) if b.parcel_weight_kg else None,
        is_rental=b.is_rental,
        rental_hours=b.rental_hours,
        is_courier=b.is_courier,
        customer=None, # Not modifying loyalty here
        redeem_points=int(b.redeem_points) if b.redeem_points else 0,
        stops=stops_list,
        driver_accepted_lat=float(b.driver_accepted_lat) if b.driver_accepted_lat else None,
        driver_accepted_lng=float(b.driver_accepted_lng) if b.driver_accepted_lng else None,
    )
    
    b.distance_km = to_decimal(fare["distance_km"])
    b.duration_min = fare["duration_min"]
    b.fare_amount = to_decimal(fare["fare_amount"])
    b.discount_amount = to_decimal(fare["discount_amount"])
    b.final_amount = to_decimal(fare["final_amount"])
    b.platform_fee = to_decimal(fare["platform_fee"])
    b.driver_earnings = to_decimal(fare["driver_earnings"])
    b.pickup_distance_km = to_decimal(fare.get("pickup_distance_km", 0))
    b.pickup_fee = to_decimal(fare.get("pickup_fee", 0))
    b.boost = to_decimal(fare.get("boost", 0))
    b.passenger_deductible = to_decimal(fare.get("passenger_deductible", 0))
    b.app_usage_charges = to_decimal(fare.get("app_usage_charges", 0))
    b.deductions = to_decimal(fare.get("deductions", 0))

    await db.commit()
    await db.refresh(b)

    # Tell every OTHER nearby driver the ride is gone, so their pending request
    # card auto-dismisses (driver_provider listens for 'ride_taken'). We re-run
    # the same proximity query as create_booking to approximate "who was pinged".
    # Mirror create_booking: flash parcels were broadcast to ALL vehicle types,
    # so the dismissal needs to reach the same audience.
    dispatch_vehicle = None if (b.is_flash or b.is_courier) else b.service_type
    max_radius = await get_search_radius_for_service(db, dispatch_vehicle)
    other_drivers = await find_all_nearby_drivers(
        db,
        float(b.pickup_lat),
        float(b.pickup_lng),
        dispatch_vehicle,
        max_distance_km=max_radius,
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


# ---------- Intermediate-stop driver actions (BRD: CD-19 / BE-16 / BR-9) ----------
async def _load_booking_for_driver(db: AsyncSession, user: User, booking_id: int) -> Booking:
    """Look up a booking and verify the caller is its assigned driver."""
    d = await _get_driver(db, user)
    q = await db.execute(
        select(Booking)
        .options(selectinload(Booking.stops))
        .where(Booking.id == booking_id)
    )
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    if b.driver_id != d.id:
        raise HTTPException(status_code=403, detail="Not your booking")
    return b


@router.post("/{booking_id}/stops/{order_index}/arrive")
async def driver_arrived_at_stop(
    booking_id: int,
    order_index: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Driver taps "Arrived at stop". Starts the per-stop free-wait timer."""
    b = await _load_booking_for_driver(db, user, booking_id)
    if b.status != BookingStatus.STARTED:
        raise HTTPException(
            status_code=400,
            detail=f"Can only arrive at a stop after the trip starts (status={b.status.value})",
        )
    stop = next((s for s in (b.stops or []) if s.order_index == order_index), None)
    if not stop:
        raise HTTPException(status_code=404, detail=f"Stop {order_index} not found on this booking")
    if stop.arrived_at:
        # Idempotent: the driver might double-tap; just echo the existing timestamp.
        return {
            "ok": True, "already_arrived": True,
            "arrived_at": stop.arrived_at.isoformat(),
            "free_wait_seconds": stop.free_wait_seconds,
        }
    now = datetime.now(timezone.utc)
    stop.arrived_at = now
    await db.commit()
    # Notify the customer so their app can start the visible countdown
    if b.customer_id:
        cust_q = await db.execute(select(Customer).where(Customer.id == b.customer_id))
        c = cust_q.scalars().first()
        if c:
            await manager.send(c.user_id, "stop_arrived", {
                "booking_id": b.id,
                "order_index": order_index,
                "arrived_at": now.isoformat(),
                "free_wait_seconds": stop.free_wait_seconds,
            })
    return {
        "ok": True, "arrived_at": now.isoformat(),
        "free_wait_seconds": stop.free_wait_seconds,
    }


@router.post("/{booking_id}/stops/{order_index}/depart")
async def driver_departed_from_stop(
    booking_id: int,
    order_index: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Driver taps "Depart". Locks in this stop's excess wait charge."""
    b = await _load_booking_for_driver(db, user, booking_id)
    stop = next((s for s in (b.stops or []) if s.order_index == order_index), None)
    if not stop:
        raise HTTPException(status_code=404, detail=f"Stop {order_index} not found on this booking")
    if not stop.arrived_at:
        raise HTTPException(status_code=400, detail="Mark 'arrived' before 'depart'")
    if stop.departed_at:
        return {
            "ok": True, "already_departed": True,
            "departed_at": stop.departed_at.isoformat(),
            "excess_seconds": stop.excess_seconds,
            "wait_charge": float(stop.wait_charge or 0),
        }

    now = datetime.now(timezone.utc)
    waited_sec = max(0, int((now - stop.arrived_at).total_seconds()))
    free_sec = int(stop.free_wait_seconds or 0)
    excess_sec = max(0, waited_sec - free_sec)
    # Bill per started minute — same convention parking meters use.
    excess_minutes = (excess_sec + 59) // 60
    rate = Decimal(str(stop.excess_rate_per_minute or 0))
    charge = (Decimal(excess_minutes) * rate).quantize(Decimal("0.01"))

    stop.departed_at = now
    stop.excess_seconds = excess_sec
    stop.wait_charge = charge
    await db.commit()

    if b.customer_id:
        cust_q = await db.execute(select(Customer).where(Customer.id == b.customer_id))
        c = cust_q.scalars().first()
        if c:
            await manager.send(c.user_id, "stop_departed", {
                "booking_id": b.id,
                "order_index": order_index,
                "waited_seconds": waited_sec,
                "excess_seconds": excess_sec,
                "wait_charge": float(charge),
            })
    return {
        "ok": True,
        "departed_at": now.isoformat(),
        "waited_seconds": waited_sec,
        "excess_seconds": excess_sec,
        "wait_charge": float(charge),
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

    old_status = b.status
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
        import random
        b.otp = f"{random.randint(1000, 9999)}"
    elif new_status == BookingStatus.STARTED:
        if b.otp and body.otp != b.otp:
            raise HTTPException(status_code=400, detail="Invalid OTP code")
        b.started_at = now
    elif new_status == BookingStatus.COMPLETED:
        b.completed_at = now
        b.payment_status = "paid"

        # BRD: CD-19 / BR-9 — sum excess waiting charges across all stops and
        # add them to the customer's final bill. Done BEFORE the wallet debit
        # so the wallet path withdraws the full inclusive amount.
        from ...models import BookingStop
        sq = await db.execute(
            select(BookingStop).where(BookingStop.booking_id == b.id)
        )
        stops_now = sq.scalars().all()
        total_wait = Decimal("0")
        for s in stops_now:
            # If the driver never tapped 'depart' but tapped 'arrive', settle
            # the timer now so we don't lose the wait charge.
            if s.arrived_at and not s.departed_at:
                waited_sec = max(0, int((now - s.arrived_at).total_seconds()))
                free_sec = int(s.free_wait_seconds or 0)
                excess_sec = max(0, waited_sec - free_sec)
                excess_minutes = (excess_sec + 59) // 60
                rate = Decimal(str(s.excess_rate_per_minute or 0))
                s.departed_at = now
                s.excess_seconds = excess_sec
                s.wait_charge = (Decimal(excess_minutes) * rate).quantize(Decimal("0.01"))
            total_wait += Decimal(str(s.wait_charge or 0))
        if total_wait > 0:
            b.waiting_charge = total_wait.quantize(Decimal("0.01"))
            b.final_amount = (Decimal(str(b.final_amount or 0)) + b.waiting_charge).quantize(Decimal("0.01"))
            # Driver keeps the waiting charge (split-free) since it's
            # compensation for their time, not platform value.
            b.driver_earnings = (Decimal(str(b.driver_earnings or 0)) + b.waiting_charge).quantize(Decimal("0.01"))

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
        elif b.payment_method and b.payment_method.startswith("card_"):
            try:
                card_id = int(b.payment_method.split("_")[1])
            except (ValueError, IndexError):
                card_id = None

            if card_id:
                card_q = await db.execute(select(CustomerCard).where(CustomerCard.id == card_id))
                card = card_q.scalars().first()
                if card:
                    charge_res = await payhere_service.charge_tokenized_card(
                        customer_token=card.customer_token,
                        amount=b.final_amount,
                        order_id=b.booking_ref,
                        items=f"Ride payment {b.booking_ref}",
                    )
                    if not charge_res.get("success"):
                        b.status = BookingStatus.PAYMENT_PENDING
                        b.payment_status = "failed"
                        print(f"[payhere] automated charge failed for booking {b.booking_ref}: {charge_res.get('message')}")
                        from ...models import Payment
                        pay_rec = Payment(
                            booking_id=b.id,
                            customer_id=b.customer_id,
                            amount=b.final_amount,
                            payment_method=f"{card.card_type} ({card.card_no[-4:]})",
                            transaction_id=None,
                            payment_gateway_response=charge_res.get("message"),
                            status="failed",
                        )
                        db.add(pay_rec)
                    else:
                        b.payment_status = "paid"
                        from ...models import Payment
                        pay_rec = Payment(
                            booking_id=b.id,
                            customer_id=b.customer_id,
                            amount=b.final_amount,
                            payment_method=f"{card.card_type} ({card.card_no[-4:]})",
                            transaction_id=charge_res.get("transaction_id"),
                            payment_gateway_response=charge_res.get("message"),
                            status="paid",
                        )
                        db.add(pay_rec)

        # BRD: PY-05 — corporate billing debit
        elif b.payment_method == "corporate" and b.corporate_id:
            from ...models import CorporateAccount
            cq = await db.execute(
                select(CorporateAccount).where(CorporateAccount.id == b.corporate_id)
            )
            corp = cq.scalars().first()
            if corp:
                corp.balance = Decimal(str(corp.balance or 0)) - (b.final_amount or Decimal(0))
                b.payment_status = "paid"
                print(f"[corporate] debited Rs.{b.final_amount} from {corp.company_name} (balance: {corp.balance})")

        # Driver earnings
        if b.driver_id:
            dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
            drv = dq.scalars().first()
            if drv:
                drv.total_earnings = (drv.total_earnings or Decimal(0)) + (b.driver_earnings or Decimal(0))
                drv.today_earnings = (drv.today_earnings or Decimal(0)) + (b.driver_earnings or Decimal(0))
                drv.today_rides = (drv.today_rides or 0) + 1

                # Check driver incentives (daily bonus and cycle bonus) from SystemSettings
                from ...models import DriverPayout
                ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
                ss = ss_q.scalars().first()
                if ss:
                    min_daily = int(ss.min_rides_daily_bonus) if ss.min_rides_daily_bonus is not None else 0
                    daily_amt = Decimal(str(ss.daily_bonus_amount or 0))
                    if min_daily > 0 and daily_amt > 0:
                        if drv.today_rides == min_daily:
                            drv.today_earnings += daily_amt
                            drv.total_earnings += daily_amt
                            db.add(DriverPayout(
                                driver_id=drv.id,
                                user_id=drv.user_id,
                                amount=daily_amt,
                                description=f"Daily Ride Bonus ({min_daily} rides reached)",
                            ))
                            db.add(Notification(
                                user_id=drv.user_id,
                                title="Daily Bonus Unlocked!",
                                body=f"Congratulations! You completed {min_daily} rides today and earned a bonus of Rs.{daily_amt:,.2f}.",
                                type="payment",
                            ))

                    cycle_rides = int(ss.commission_cycle_rides) if ss.commission_cycle_rides is not None else 0
                    cycle_amt = Decimal(str(ss.commission_per_cycle or 0))
                    if cycle_rides > 0 and cycle_amt > 0:
                        # Count total completed bookings, food orders, and market orders for this driver
                        b_count_q = await db.execute(
                            select(func.count(Booking.id)).where(
                                Booking.driver_id == drv.id,
                                Booking.status == BookingStatus.COMPLETED
                            )
                        )
                        b_count = b_count_q.scalar() or 0

                        from ...models import FoodOrder, FoodOrderStatus, MarketOrder, MarketOrderStatus
                        f_count_q = await db.execute(
                            select(func.count(FoodOrder.id)).where(
                                FoodOrder.driver_id == drv.id,
                                FoodOrder.status == FoodOrderStatus.DELIVERED
                            )
                        )
                        f_count = f_count_q.scalar() or 0

                        m_count_q = await db.execute(
                            select(func.count(MarketOrder.id)).where(
                                MarketOrder.driver_id == drv.id,
                                MarketOrder.status == MarketOrderStatus.DELIVERED
                            )
                        )
                        m_count = m_count_q.scalar() or 0

                        completed_count = b_count + f_count + m_count
                        if completed_count > 0 and completed_count % cycle_rides == 0:
                            drv.total_earnings += cycle_amt
                            drv.today_earnings += cycle_amt
                            db.add(DriverPayout(
                                driver_id=drv.id,
                                user_id=drv.user_id,
                                amount=cycle_amt,
                                description=f"Commission Cycle Bonus ({completed_count} rides reached)",
                            ))
                            db.add(Notification(
                                user_id=drv.user_id,
                                title="Commission Cycle Bonus!",
                                body=f"Congratulations! You completed another cycle of {cycle_rides} rides and earned a bonus of Rs.{cycle_amt:,.2f}.",
                                type="payment",
                            ))

        # BRD: RW-01 — award loyalty points on completion (based on the cash
        # paid, i.e. final_amount AFTER any redemption discount).
        from ...services.loyalty_service import award_points as _award
        cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
        cust_for_points = cq.scalars().first()
        if cust_for_points and b.final_amount:
            await _award(
                db, cust_for_points,
                spend_amount=b.final_amount,
                source_kind="booking",
                source_id=b.id,
                description=f"Earned on {b.booking_ref}",
            )

        # CD-30 — process referral bonus on friend's first completed trip
        from ...services.referral_service import process_referral_on_first_trip
        await process_referral_on_first_trip(db, b)

        # Check and deactivate driver if outstanding commission exceeds limit
        if b.driver_id:
            from ...services.finance_service import check_and_deactivate_driver
            await check_and_deactivate_driver(db, b.driver_id)

    elif new_status == BookingStatus.CANCELLED:
        b.cancelled_at = now
        b.cancellation_reason = body.reason
        b.cancelled_by = user.role.value

        # Charge cancellation fee if cancelled by customer after grace period
        if b.cancelled_by == "customer":
            from ...models import WalletTransaction
            ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
            ss = ss_q.scalars().first()
            grace_period_mins = ss.cancellation_grace_period_minutes if (ss and ss.cancellation_grace_period_minutes is not None) else 3
            elapsed = now - b.booked_at
            if elapsed > timedelta(minutes=grace_period_mins):
                cancel_fee = ss.cancellation_fee if ss else Decimal(0)
                if cancel_fee > 0:
                    cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
                    customer = cq.scalars().first()
                    if customer:
                        customer.wallet_balance = (customer.wallet_balance or Decimal(0)) - cancel_fee
                        db.add(WalletTransaction(
                            user_id=customer.user_id,
                            amount=cancel_fee,
                            type="debit",
                            description=f"Cancellation fee for booking {b.booking_ref}",
                            reference_id=b.booking_ref,
                            balance_after=customer.wallet_balance,
                        ))
                        # Notify customer of cancellation fee
                        db.add(Notification(
                            user_id=customer.user_id,
                            title="Cancellation Fee Charged",
                            body=f"A cancellation fee of Rs.{cancel_fee:,.2f} was deducted from your wallet for cancelling booking {b.booking_ref}.",
                            type="payment",
                        ))

        # BRD: RW-02 — refund any redeemed points if the trip never happened.
        if b.redeem_points and b.redeem_points > 0:
            cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
            cust_refund = cq.scalars().first()
            if cust_refund:
                cust_refund.loyalty_points = int(cust_refund.loyalty_points or 0) + int(b.redeem_points)
                from ...models import LoyaltyTransaction
                db.add(LoyaltyTransaction(
                    customer_id=cust_refund.id,
                    points=int(b.redeem_points),
                    kind="adjust",
                    source_kind="booking",
                    source_id=b.id,
                    description=f"Refund — {b.booking_ref} cancelled",
                    balance_after=cust_refund.loyalty_points,
                ))
                # Zero out the snapshot so a re-cancellation doesn't double-refund.
                b.redeem_points = 0
                b.redeem_discount = Decimal("0.00")

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
                {"booking_id": b.id, "status": b.status.value, "otp": b.otp},
            )
            if not (b.status == BookingStatus.CANCELLED and b.cancelled_by == "customer"):
                db.add(
                    Notification(
                        user_id=c.user_id,
                        title=f"Ride {b.status.value.title()}",
                        body=f"Booking {b.booking_ref} is now {b.status.value}",
                        type="ride_update",
                    )
                )
    if b.status == BookingStatus.CANCELLED and b.driver_id is None:
        dispatch_vehicle = None if (b.is_flash or b.is_courier) else b.service_type
        max_radius = await get_search_radius_for_service(db, dispatch_vehicle)
        nearby = await find_all_nearby_drivers(
            db,
            float(b.pickup_lat),
            float(b.pickup_lng),
            dispatch_vehicle,
            max_distance_km=max_radius,
            exclude_driver_id=None,
        )
        for nd in nearby:
            await manager.send(
                nd.user_id,
                "booking_cancelled",
                {"booking_id": b.id, "booking_ref": b.booking_ref},
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
        dispatch_vehicle = None if (b.is_flash or b.is_courier) else b.service_type
        max_radius = await get_search_radius_for_service(db, dispatch_vehicle)

        other_drivers = await find_all_nearby_drivers(
            db,
            float(b.pickup_lat),
            float(b.pickup_lng),
            dispatch_vehicle,
            max_distance_km=max_radius,
            exclude_driver_id=None,
        )
        for od in other_drivers:
            await manager.send(
                od.user_id,
                "ride_taken",
                {"booking_id": b.id, "booking_ref": b.booking_ref},
            )
    await db.commit()

    return await _booking_to_response(db, b)


# ---------- BRD: CD-17 SOS alert ----------
@router.post("/{booking_id}/sos", status_code=201)
async def trigger_sos(
    booking_id: int,
    body: dict = Body(default={}),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Customer taps the panic button mid-ride.

    Stamps the alert with the booking's last-known driver location (if any)
    so admin sees where the rider was at the moment they pressed it. Also
    broadcasts to every connected admin socket so the alert pings the live
    admin dashboard immediately.
    """
    from ...models import EmergencyAlert
    from ...services.ws_manager import manager as _mgr

    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    # Anyone party to the booking can trigger — rider or driver.
    cust_q = await db.execute(select(Customer).where(Customer.id == b.customer_id))
    cust = cust_q.scalars().first()
    is_party = (cust and cust.user_id == user.id) or (
        b.driver_id and (await db.execute(
            select(Driver).where(Driver.id == b.driver_id)
        )).scalars().first().user_id == user.id
    )
    if not is_party:
        raise HTTPException(status_code=403, detail="Not your booking")

    # Take the most reliable lat/lng we have right now.
    lat = body.get("lat") or (float(b.pickup_lat) if b.pickup_lat is not None else None)
    lng = body.get("lng") or (float(b.pickup_lng) if b.pickup_lng is not None else None)

    alert = EmergencyAlert(
        user_id=user.id,
        booking_id=b.id,
        booking_ref=b.booking_ref,
        lat=Decimal(str(lat)) if lat is not None else None,
        lng=Decimal(str(lng)) if lng is not None else None,
        note=(body.get("note") or "")[:500] or None,
        status="open",
    )
    db.add(alert)
    await db.commit()
    await db.refresh(alert)

    payload = {
        "alert_id": alert.id,
        "booking_id": b.id,
        "booking_ref": b.booking_ref,
        "user_id": user.id,
        "user_name": user.full_name or "",
        "user_phone": user.phone_number or "",
        "lat": float(alert.lat) if alert.lat is not None else None,
        "lng": float(alert.lng) if alert.lng is not None else None,
        "note": alert.note or "",
        "created_at": alert.created_at.isoformat() if alert.created_at else None,
    }
    await _mgr.publish("admin_live", "sos_alert", payload)
    return {"ok": True, "alert_id": alert.id, "status": alert.status}


# ---------- BRD: CD-17 + CD-31 Trip sharing ----------
@router.post("/{booking_id}/share")
async def create_trip_share_link(
    booking_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Returns a signed share URL + a ready-to-send SMS/WhatsApp body.

    The URL hits the public `GET /api/v1/trip/share/{token}` viewer below — no
    auth — so the rider can deep-link family / friends without exposing the JWT.
    """
    import secrets as _secrets

    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    cust_q = await db.execute(select(Customer).where(Customer.id == b.customer_id))
    cust = cust_q.scalars().first()
    if not (cust and cust.user_id == user.id):
        raise HTTPException(status_code=403, detail="Only the rider can share a trip")

    if not b.share_token:
        b.share_token = _secrets.token_urlsafe(16)
        await db.commit()

    # Use the same host the request came in on; works for both nginx-front and
    # direct-port deployments.
    base = str(request.base_url).rstrip("/")
    share_url = f"{base}/api/v1/trip/share/{b.share_token}"
    eta_min = b.duration_min or 0
    sms_body = (
        f"I'm on a Ziggo ride. Track me live: {share_url}\n"
        f"Pickup: {b.pickup_address}\nDrop: {b.drop_address}\n"
        f"ETA: ~{eta_min} min."
    )
    return {
        "share_token": b.share_token,
        "share_url": share_url,
        "sms_body": sms_body,
        "wa_url": f"https://wa.me/?text={share_url}",
    }


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
        # update customer aggregate rating
        cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
        cust = cq.scalars().first()
        if cust and cust.user_id:
            uq = await db.execute(select(User).where(User.id == cust.user_id))
            cuser = uq.scalars().first()
            if cuser:
                prev = float(cuser.rating or 0)
                total = cuser.total_rides or 0
                new_total = total + 1
                cuser.rating = Decimal(str(round((prev * total + body.rating) / new_total, 2)))
                cuser.total_rides = new_total

    await db.commit()
    await db.refresh(b)
    return await _booking_to_response(db, b)


@router.patch("/{booking_id}/destination", response_model=BookingResponse)
async def update_booking_destination(
    booking_id: int,
    body: BookingUpdateDestinationRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")

    if user.role == UserRole.CUSTOMER:
        c = await _get_customer(db, user)
        if b.customer_id != c.id:
            raise HTTPException(status_code=403, detail="Not your booking")
    else:
        raise HTTPException(status_code=403, detail="Only customer can update destination")

    if b.status not in (BookingStatus.ACCEPTED, BookingStatus.ARRIVED, BookingStatus.STARTED):
        raise HTTPException(status_code=400, detail="Cannot update destination in current status")

    fare = await calculate_fare(
        db,
        b.service_type,
        float(b.pickup_lat),
        float(b.pickup_lng),
        body.drop_lat,
        body.drop_lng,
        b.promo_code,
        trip_type=b.trip_type or "one_way",
        is_flash=b.is_flash,
        parcel_weight_kg=float(b.parcel_weight_kg) if b.parcel_weight_kg else None,
        is_rental=b.is_rental,
        rental_hours=b.rental_hours,
        is_courier=b.is_courier,
        customer=c,
        redeem_points=int(b.redeem_points) if b.redeem_points else 0,
        stops=[s.model_dump() for s in (body.stops or [])],
        driver_accepted_lat=float(b.driver_accepted_lat) if b.driver_accepted_lat else None,
        driver_accepted_lng=float(b.driver_accepted_lng) if b.driver_accepted_lng else None,
    )

    b.drop_lat = Decimal(str(body.drop_lat))
    b.drop_lng = Decimal(str(body.drop_lng))
    b.drop_address = body.drop_address

    b.distance_km = to_decimal(fare["distance_km"])
    b.duration_min = fare["duration_min"]
    b.fare_amount = to_decimal(fare["fare_amount"])
    b.discount_amount = to_decimal(fare["discount_amount"])
    b.final_amount = to_decimal(fare["final_amount"])
    b.platform_fee = to_decimal(fare["platform_fee"])
    b.driver_earnings = to_decimal(fare["driver_earnings"])
    b.pickup_distance_km = to_decimal(fare.get("pickup_distance_km", 0))
    b.pickup_fee = to_decimal(fare.get("pickup_fee", 0))
    b.boost = to_decimal(fare.get("boost", 0))
    b.passenger_deductible = to_decimal(fare.get("passenger_deductible", 0))
    b.app_usage_charges = to_decimal(fare.get("app_usage_charges", 0))
    b.deductions = to_decimal(fare.get("deductions", 0))

    from ...models import BookingStop, SystemSettings
    if body.stops:
        await db.execute(BookingStop.__table__.delete().where(BookingStop.booking_id == b.id))
        ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
        ss = ss_q.scalars().first()
        free_secs = int((ss.multi_stop_free_minutes if ss else 3) or 3) * 60
        excess_rate = ss.multi_stop_excess_per_minute if (ss and ss.multi_stop_excess_per_minute is not None) else Decimal("5")
        for idx, stop in enumerate(body.stops, start=1):
            db.add(BookingStop(
                booking_id=b.id,
                order_index=idx,
                lat=Decimal(str(stop.lat)),
                lng=Decimal(str(stop.lng)),
                address=stop.address,
                free_wait_seconds=free_secs,
                excess_rate_per_minute=Decimal(str(excess_rate)),
            ))
        b.stop_count = len(body.stops)
    else:
        await db.execute(BookingStop.__table__.delete().where(BookingStop.booking_id == b.id))
        b.stop_count = 0

    await db.commit()
    await db.refresh(b)

    if b.driver_id:
        dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
        drv = dq.scalars().first()
        if drv and drv.user_id:
            await manager.send(
                drv.user_id,
                "destination_updated",
                {
                    "booking_id": b.id,
                    "drop_lat": float(b.drop_lat),
                    "drop_lng": float(b.drop_lng),
                    "drop_address": b.drop_address,
                    "final_amount": float(b.final_amount),
                }
            )
            db.add(
                Notification(
                    user_id=drv.user_id,
                    title="Destination Updated",
                    body=f"Destination changed to {b.drop_address}. Fare updated.",
                    type="ride_update",
                )
            )
            await db.commit()

    return await _booking_to_response(db, b)

class MessageRequest(BaseModel):
    message: str

@router.post("/{booking_id}/message")
async def send_booking_message(
    booking_id: int, 
    body: MessageRequest, 
    db: AsyncSession = Depends(get_db), 
    current_user: User = Depends(get_current_user)
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
    
    target_user_id = None
    sender_type = None

    if b.customer_id:
        cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
        cust = cq.scalars().first()
        if cust and cust.user_id == current_user.id:
            sender_type = 'customer'
            if b.driver_id:
                dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
                drv = dq.scalars().first()
                if drv:
                    target_user_id = drv.user_id

    if b.driver_id and not sender_type:
        dq = await db.execute(select(Driver).where(Driver.id == b.driver_id))
        drv = dq.scalars().first()
        if drv and drv.user_id == current_user.id:
            sender_type = 'driver'
            if b.customer_id:
                cq = await db.execute(select(Customer).where(Customer.id == b.customer_id))
                cust = cq.scalars().first()
                if cust:
                    target_user_id = cust.user_id

    if not sender_type:
        raise HTTPException(status_code=403, detail="Not part of this booking")

    # Save message to DB
    new_msg = BookingMessage(
        booking_id=b.id,
        sender_type=sender_type,
        message=body.message,
    )
    db.add(new_msg)
    await db.commit()
    await db.refresh(new_msg)

    if target_user_id:
        payload = {
            "booking_id": b.id,
            "sender_type": sender_type,
            "message": body.message,
        }
        await manager.send(target_user_id, "chat_message", payload)

    return {"status": "success", "message_id": new_msg.id}

@router.get("/{booking_id}/messages")
async def get_booking_messages(
    booking_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    q = await db.execute(select(Booking).where(Booking.id == booking_id))
    b = q.scalars().first()
    if not b:
        raise HTTPException(status_code=404, detail="Booking not found")
        
    mq = await db.execute(
        select(BookingMessage)
        .where(BookingMessage.booking_id == booking_id)
        .order_by(BookingMessage.created_at.asc())
    )
    messages = mq.scalars().all()
    
    return [
        {
            "id": m.id,
            "booking_id": m.booking_id,
            "sender_type": m.sender_type,
            "message": m.message,
            "created_at": m.created_at.isoformat() if m.created_at else None
        }
        for m in messages
    ]

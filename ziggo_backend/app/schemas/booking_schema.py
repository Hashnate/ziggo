from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime

from ..models.booking import BookingStatus


class StopRequest(BaseModel):
    """An intermediate waypoint (BRD: CD-19)."""
    lat: float
    lng: float
    address: Optional[str] = None


class FareEstimateRequest(BaseModel):
    service_type: str
    pickup_lat: float
    pickup_lng: float
    drop_lat: float
    drop_lng: float
    promo_code: Optional[str] = None
    trip_type: str = "one_way"  # one_way | return
    is_flash: bool = False
    parcel_weight_kg: Optional[float] = None
    # Courier (island-wide, weight-priced) parcel delivery.
    is_courier: bool = False
    # Rental fields — when is_rental=True we ignore drop_* and price by
    # hourly_rate * rental_hours.
    is_rental: bool = False
    rental_hours: Optional[int] = Field(default=None, ge=1, le=24)
    # BRD: RW-02 — optional preview of points redemption on the estimate
    redeem_points: int = 0
    # BRD: CD-19 — up to N intermediate stops (server clamps to admin limit)
    stops: List[StopRequest] = Field(default_factory=list)


class FareEstimateResponse(BaseModel):
    service_type: str
    distance_km: float
    duration_min: int
    fare_amount: float
    discount_amount: float
    final_amount: float
    platform_fee: float
    driver_earnings: float
    promo_code: Optional[str] = None
    surge_multiplier: float
    flash_surcharge: float = 0
    # Courier SLA (days) — only populated on courier estimates.
    courier_eta_days: Optional[int] = None
    # BRD: RS-07 — show this on the vehicle selection card
    points_earnable: int = 0
    # BRD: RW-02 — populated when the customer pre-applies points on estimate
    redeem_points_used: int = 0
    redeem_discount: float = 0
    redeem_reason: Optional[str] = None
    # BRD: CD-19 — multi-stop snapshot
    stop_count: int = 0
    stops_fee: float = 0
    # Custom Calculations / Deductions
    pickup_fee: float = 0
    boost: float = 0
    passenger_deductible: float = 0
    app_usage_charges: float = 0
    deductions: float = 0


class BookingCreate(BaseModel):
    service_type: str
    pickup_lat: float
    pickup_lng: float
    pickup_address: str
    drop_lat: float
    drop_lng: float
    drop_address: str
    payment_method: str = "cash"
    promo_code: Optional[str] = None
    trip_type: str = "one_way"  # one_way | return
    # Flash parcel fields (only set when this is a parcel delivery, not a ride)
    is_flash: bool = False
    parcel_type: Optional[str] = None
    parcel_weight_kg: Optional[float] = None
    receiver_name: Optional[str] = None
    receiver_phone: Optional[str] = None
    parcel_instructions: Optional[str] = None
    # Courier (island-wide, weight-priced) parcel delivery.
    is_courier: bool = False
    # Rental fields — when is_rental=True the customer is hiring the vehicle
    # for rental_hours. drop_* can be the same as pickup_* (no fixed dropoff).
    is_rental: bool = False
    rental_hours: Optional[int] = Field(default=None, ge=1, le=24)
    # BRD: RW-02 — points the customer wants to redeem at checkout
    redeem_points: int = 0
    # BRD: CD-19 — up to N intermediate stops (server clamps to admin limit)
    stops: List[StopRequest] = Field(default_factory=list)


class DriverMini(BaseModel):
    id: int
    full_name: Optional[str] = None
    rating: Optional[float] = None
    vehicle_type: Optional[str] = None
    vehicle_number: Optional[str] = None
    vehicle_model: Optional[str] = None
    phone_number: Optional[str] = None
    current_lat: Optional[float] = None
    current_lng: Optional[float] = None
    profile_photo: Optional[str] = None

    class Config:
        from_attributes = True


class BookingResponse(BaseModel):
    id: int
    booking_ref: str
    status: BookingStatus
    service_type: str
    trip_type: str = "one_way"

    pickup_lat: float
    pickup_lng: float
    pickup_address: str
    drop_lat: float
    drop_lng: float
    drop_address: str

    distance_km: Optional[float] = None
    duration_min: Optional[int] = None
    fare_amount: Optional[float] = None
    discount_amount: Optional[float] = None
    final_amount: Optional[float] = None

    payment_method: Optional[str] = None
    payment_status: Optional[str] = None
    promo_code: Optional[str] = None

    booked_at: Optional[datetime] = None
    accepted_at: Optional[datetime] = None
    arrived_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None
    cancellation_reason: Optional[str] = None

    customer_rating: Optional[int] = None
    customer_feedback: Optional[str] = None
    driver: Optional[DriverMini] = None
    customer_name: Optional[str] = None
    customer_phone: Optional[str] = None

    # Flash parcel fields (only present when is_flash=True)
    is_flash: bool = False
    parcel_type: Optional[str] = None
    parcel_weight_kg: Optional[float] = None
    receiver_name: Optional[str] = None
    receiver_phone: Optional[str] = None
    parcel_instructions: Optional[str] = None

    # Courier fields (only present when is_courier=True)
    is_courier: bool = False
    courier_eta_days: Optional[int] = None

    # Rental fields (only present when is_rental=True)
    is_rental: bool = False
    rental_hours: Optional[int] = None

    # Custom Calculations / Deductions
    pickup_fee: Optional[float] = 0
    boost: Optional[float] = 0
    passenger_deductible: Optional[float] = 0
    app_usage_charges: Optional[float] = 0
    deductions: Optional[float] = 0
    driver_earnings: Optional[float] = 0

    class Config:
        from_attributes = True



class BookingStatusUpdate(BaseModel):
    status: BookingStatus
    reason: Optional[str] = None


class BookingRateRequest(BaseModel):
    rating: int = Field(ge=1, le=5)
    feedback: Optional[str] = None

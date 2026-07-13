from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    DECIMAL,
    ForeignKey,
    Text,
    Enum as SQLEnum,
)
# Boolean already imported above

from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum

from ..database import Base


class BookingStatus(str, enum.Enum):
    SEARCHING = "searching"
    ACCEPTED = "accepted"
    ARRIVED = "arrived"
    STARTED = "started"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    PAYMENT_PENDING = "payment_pending"


class Booking(Base):
    __tablename__ = "bookings"

    id = Column(Integer, primary_key=True, index=True)
    booking_ref = Column(String(20), unique=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="SET NULL"), nullable=True)
    driver_id = Column(Integer, ForeignKey("drivers.id", ondelete="SET NULL"), nullable=True)

    pickup_lat = Column(DECIMAL(10, 7))
    pickup_lng = Column(DECIMAL(10, 7))
    pickup_address = Column(Text)
    drop_lat = Column(DECIMAL(10, 7))
    drop_lng = Column(DECIMAL(10, 7))
    drop_address = Column(Text)
    
    requested_drop_lat = Column(DECIMAL(10, 7), nullable=True)
    requested_drop_lng = Column(DECIMAL(10, 7), nullable=True)
    requested_drop_address = Column(Text, nullable=True)
    
    driver_accepted_lat = Column(DECIMAL(10, 7))
    driver_accepted_lng = Column(DECIMAL(10, 7))

    service_type = Column(String(20))  # bike, tuk, car, van, truck, delivery
    trip_type = Column(String(20), default="one_way", nullable=False)  # one_way | return
    status = Column(
        SQLEnum(BookingStatus, name="booking_status"),
        default=BookingStatus.SEARCHING,
        index=True,
    )
    fare_amount = Column(DECIMAL(10, 2))
    distance_km = Column(DECIMAL(8, 2))
    duration_min = Column(Integer)

    payment_method = Column(String(20))  # cash, card, wallet
    payment_status = Column(String(20), default="pending")
    promo_code = Column(String(50))
    discount_amount = Column(DECIMAL(10, 2), default=0)
    # BRD: RW-02 — loyalty redemption snapshot per booking, separate from
    # `discount_amount` so admin can split promo vs points in finance reports.
    redeem_points = Column(Integer, nullable=False, default=0)
    redeem_discount = Column(DECIMAL(10, 2), nullable=False, default=0)
    final_amount = Column(DECIMAL(10, 2))
    platform_fee = Column(DECIMAL(10, 2))
    driver_earnings = Column(DECIMAL(10, 2))
    pickup_distance_km = Column(DECIMAL(8, 2), default=0.00)
    pickup_fee = Column(DECIMAL(10, 2), default=0.00)
    boost = Column(DECIMAL(10, 2), default=0.00)
    peak_surcharge = Column(DECIMAL(10, 2), default=0.00)
    passenger_deductible = Column(DECIMAL(10, 2), default=0.00)
    app_usage_charges = Column(DECIMAL(10, 2), default=0.00)
    deductions = Column(DECIMAL(10, 2), default=0.00)

    booked_at = Column(DateTime(timezone=True), server_default=func.now())
    accepted_at = Column(DateTime(timezone=True))
    arrived_at = Column(DateTime(timezone=True))
    started_at = Column(DateTime(timezone=True))
    completed_at = Column(DateTime(timezone=True))
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(String(20))
    cancellation_reason = Column(Text)

    customer_rating = Column(Integer)
    driver_rating = Column(Integer)
    customer_feedback = Column(Text)
    driver_feedback = Column(Text)

    # Flash / parcel-delivery fields. is_flash=True means the trip is a parcel
    # courier job (not a passenger ride). The other fields capture parcel
    # metadata so the driver knows what to pick up and where to deliver it.
    is_flash = Column(Boolean, default=False, index=True)
    parcel_type = Column(String(50))           # document | food | clothes | electronics | other
    parcel_weight_kg = Column(DECIMAL(6, 2))   # estimated weight
    receiver_name = Column(String(100))
    receiver_phone = Column(String(20))
    parcel_instructions = Column(Text)

    # Courier (island-wide, 2-3 day, CityPak-style) parcel deliveries. Shares
    # all the parcel_* / receiver_* metadata above with flash, but is_courier
    # marks the slower weight-priced service. booking_ref is prefixed `CR`.
    # courier_eta_days is the promised SLA snapshot (2 or 3) shown to the user.
    is_courier = Column(Boolean, default=False, index=True)
    courier_eta_days = Column(Integer, nullable=True)

    # Rental / vehicle-hire fields. is_rental=True means the customer hires a
    # vehicle for `rental_hours` and the fare is hourly_rate * hours (no drop
    # address required at booking time — the customer can roam).
    is_rental = Column(Boolean, default=False, index=True)
    rental_hours = Column(Integer)

    # BRD: CD-19 / BE-16 / BR-9 — total waiting surcharge across all stops
    # (computed when COMPLETED transition fires). Stored on the booking itself
    # so reporting can split it from base fare + promo + redemption.
    waiting_charge = Column(DECIMAL(10, 2), nullable=False, default=0)
    stop_count = Column(Integer, nullable=False, default=0)
    # BRD: CD-17 / CD-31 — opaque token that lets emergency contacts view the
    # trip in real time via a public, no-auth URL. Generated on demand.
    share_token = Column(String(40), unique=True, index=True)
    otp = Column(String(4), nullable=True)

    # BRD: PY-05 — corporate billing. When True the fare is debited from the
    # linked CorporateAccount.balance instead of the customer's personal wallet.
    is_corporate = Column(Boolean, default=False, index=True)
    corporate_id = Column(Integer, ForeignKey("corporate_accounts.id"), nullable=True)

    customer = relationship("Customer", back_populates="bookings")
    driver = relationship("Driver", back_populates="bookings")
    payments = relationship("Payment", back_populates="booking", cascade="all, delete-orphan")
    stops = relationship(
        "BookingStop",
        back_populates="booking",
        cascade="all, delete-orphan",
        order_by="BookingStop.order_index",
    )


class BookingStop(Base):
    """An intermediate waypoint on a multi-stop booking (BRD: CD-19 / BE-16 / BR-9).

    Each stop is appended in order between pickup and drop. `arrived_at` is
    set when the driver taps "Arrived at stop"; `departed_at` is set when
    they tap "Depart". `free_wait_seconds` snapshots the policy in effect at
    booking time so changes to admin settings don't retroactively re-bill an
    in-flight trip.
    """
    __tablename__ = "booking_stops"

    id = Column(Integer, primary_key=True, index=True)
    booking_id = Column(Integer, ForeignKey("bookings.id", ondelete="CASCADE"), index=True)
    order_index = Column(Integer, nullable=False)        # 1-based
    lat = Column(DECIMAL(10, 7))
    lng = Column(DECIMAL(10, 7))
    address = Column(Text)

    arrived_at = Column(DateTime(timezone=True))
    departed_at = Column(DateTime(timezone=True))
    # Policy snapshot at booking time
    free_wait_seconds = Column(Integer, nullable=False, default=180)
    excess_rate_per_minute = Column(DECIMAL(10, 2), nullable=False, default=5)
    # Computed surcharge for this stop (set at the depart-from-stop moment)
    excess_seconds = Column(Integer, nullable=False, default=0)
    wait_charge = Column(DECIMAL(10, 2), nullable=False, default=0)

    booking = relationship("Booking", back_populates="stops")


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    booking_id = Column(Integer, ForeignKey("bookings.id", ondelete="SET NULL"), nullable=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="SET NULL"), nullable=True)
    amount = Column(DECIMAL(10, 2))
    payment_method = Column(String(20))
    transaction_id = Column(String(100))
    payment_gateway_response = Column(Text)
    status = Column(String(20), default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    booking = relationship("Booking", back_populates="payments")


class PromoCode(Base):
    __tablename__ = "promo_codes"

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(50), unique=True, index=True)
    description = Column(Text)
    # Surface where the promo applies. "all" = any checkout.
    category = Column(String(20), nullable=False, default="all")  # all | rides | food | market
    discount_type = Column(String(20))  # percentage, fixed
    discount_value = Column(DECIMAL(10, 2))
    min_order_amount = Column(DECIMAL(10, 2), default=0)
    max_discount = Column(DECIMAL(10, 2))
    usage_limit = Column(Integer)
    used_count = Column(Integer, default=0)
    valid_from = Column(DateTime(timezone=True))
    valid_to = Column(DateTime(timezone=True))
    is_active = Column(Boolean, default=True)

class BookingMessage(Base):
    __tablename__ = "booking_messages"

    id = Column(Integer, primary_key=True, index=True)
    booking_id = Column(Integer, ForeignKey("bookings.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_type = Column(String(20), nullable=False)  # 'customer' | 'driver'
    message = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    booking = relationship("Booking")

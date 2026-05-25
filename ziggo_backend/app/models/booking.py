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
    customer_id = Column(Integer, ForeignKey("customers.id"))
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)

    pickup_lat = Column(DECIMAL(10, 7))
    pickup_lng = Column(DECIMAL(10, 7))
    pickup_address = Column(Text)
    drop_lat = Column(DECIMAL(10, 7))
    drop_lng = Column(DECIMAL(10, 7))
    drop_address = Column(Text)

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

    # Rental / vehicle-hire fields. is_rental=True means the customer hires a
    # vehicle for `rental_hours` and the fare is hourly_rate * hours (no drop
    # address required at booking time — the customer can roam).
    is_rental = Column(Boolean, default=False, index=True)
    rental_hours = Column(Integer)

    customer = relationship("Customer", back_populates="bookings")
    driver = relationship("Driver", back_populates="bookings")
    payments = relationship("Payment", back_populates="booking", cascade="all, delete-orphan")


class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    booking_id = Column(Integer, ForeignKey("bookings.id"))
    customer_id = Column(Integer, ForeignKey("customers.id"))
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

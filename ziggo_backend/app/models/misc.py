from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    DECIMAL,
    ForeignKey,
    Text,
    JSON,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from decimal import Decimal

from ..database import Base


class WalletTransaction(Base):
    __tablename__ = "wallet_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    amount = Column(DECIMAL(10, 2))
    type = Column(String(20))  # credit, debit
    description = Column(Text)
    reference_id = Column(String(100))
    balance_after = Column(DECIMAL(10, 2))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="wallet_transactions")


class WalletTopupRequest(Base):
    __tablename__ = "wallet_topup_requests"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    amount = Column(DECIMAL(10, 2))
    status = Column(String(20), default="pending")  # pending, approved, rejected
    note = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    approved_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    user = relationship("User", foreign_keys=[user_id])
    approved_by = relationship("User", foreign_keys=[approved_by_id])


class Complaint(Base):
    __tablename__ = "complaints"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    booking_id = Column(Integer, ForeignKey("bookings.id"), nullable=True)
    category = Column(String(50))
    subject = Column(String(200))
    description = Column(Text)
    attachment_url = Column(String(255))
    status = Column(String(20), default="open")
    assigned_to = Column(Integer, ForeignKey("users.id"))
    resolved_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", foreign_keys=[user_id])
    messages = relationship(
        "ComplaintMessage",
        back_populates="complaint",
        cascade="all, delete-orphan",
        order_by="ComplaintMessage.id",
    )


class ComplaintMessage(Base):
    __tablename__ = "complaint_messages"

    id = Column(Integer, primary_key=True, index=True)
    complaint_id = Column(Integer, ForeignKey("complaints.id", ondelete="CASCADE"), index=True)
    sender_user_id = Column(Integer, ForeignKey("users.id"))
    # "customer" / "driver" / "admin" — keeps role on the message even if the
    # user's profile role later changes (rare, but cheap to denormalize).
    sender_role = Column(String(20), nullable=False)
    body = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    complaint = relationship("Complaint", back_populates="messages")
    sender = relationship("User", foreign_keys=[sender_user_id])


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    title = Column(String(200))
    body = Column(Text)
    type = Column(String(50))  # ride_update, promo, system, payment
    data = Column(Text)  # JSON string
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="notifications")


class FareSetting(Base):
    __tablename__ = "fare_settings"

    id = Column(Integer, primary_key=True, index=True)
    service_type = Column(String(20), unique=True, index=True)
    display_name = Column(String(60))
    image_url = Column(String(255))
    capacity = Column(Integer, default=0)
    description = Column(String(255))
    is_active = Column(Boolean, nullable=False, default=True)
    base_fare = Column(DECIMAL(10, 2))
    per_km_rate = Column(DECIMAL(10, 2))
    per_minute_rate = Column(DECIMAL(10, 2))
    min_fare = Column(DECIMAL(10, 2), default=0)
    platform_fee_percent = Column(DECIMAL(5, 2), default=15)
    surge_multiplier = Column(DECIMAL(3, 2), default=1.00)
    pickup_fee = Column(DECIMAL(10, 2), default=0.00)
    boost = Column(DECIMAL(10, 2), default=0.00)
    passenger_deductible = Column(DECIMAL(10, 2), default=0.00)
    promo_message = Column(String(255), nullable=True)
    discount_percentage = Column(DECIMAL(5, 2), default=0.00)
    display_order = Column(Integer, nullable=False, default=0)
    search_radius_km = Column(Integer, nullable=True)
    is_truck = Column(Boolean, nullable=False, default=False)
    is_delivery = Column(Boolean, nullable=False, default=False)
    rental_hourly_rate = Column(DECIMAL(10, 2), nullable=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SystemSettings(Base):
    __tablename__ = "system_settings"

    id = Column(Integer, primary_key=True, default=1)
    # General
    site_name = Column(String(100), default="Ziggo")
    admin_email = Column(String(120), default="")
    contact_phone = Column(String(20), default="")
    contact_email = Column(String(120), default="")
    address = Column(Text, default="")
    # Pricing
    commission_rate = Column(DECIMAL(5, 2), default=15)
    surge_start_hour = Column(Integer, default=17)
    surge_end_hour = Column(Integer, default=20)
    surge_multiplier = Column(DECIMAL(3, 2), default=1.5)
    cancellation_fee = Column(DECIMAL(10, 2), default=0)
    cancellation_grace_period_minutes = Column(Integer, default=3)
    rider_penalty = Column(DECIMAL(10, 2), default=0)
    # Search Radius
    driver_search_radius_km = Column(Integer, default=15)
    # Security
    min_password_length = Column(Integer, default=6)
    session_timeout_minutes = Column(Integer, default=30)
    max_login_attempts = Column(Integer, default=5)
    password_reset_option = Column(String(20), default="email")
    # Notifications
    email_notifications_enabled = Column(Boolean, nullable=False, default=True)
    sms_notifications_enabled = Column(Boolean, nullable=False, default=True)
    push_notifications_enabled = Column(Boolean, nullable=False, default=True)
    # Driver incentives
    min_rides_daily_bonus = Column(Integer, default=15)
    daily_bonus_amount = Column(DECIMAL(10, 2), default=1000)
    commission_cycle_rides = Column(Integer, default=5)
    commission_per_cycle = Column(DECIMAL(10, 2), default=500)
    # Loyalty (BRD: RW-01, RW-02, AD-13)
    # Default: 1 point per Rs.10 spent (rate=10), each point worth Rs.0.50 (value=0.50)
    loyalty_earn_rupees_per_point = Column(DECIMAL(10, 2), nullable=False, default=10)
    loyalty_value_per_point = Column(DECIMAL(10, 4), nullable=False, default=Decimal("0.50"))
    loyalty_min_redeem_points = Column(Integer, nullable=False, default=100)
    loyalty_max_redeem_order_pct = Column(DECIMAL(5, 2), nullable=False, default=20)
    loyalty_is_active = Column(Boolean, nullable=False, default=True)
    # Gold membership (BRD: RW-03)
    gold_delivery_discount_pct = Column(DECIMAL(5, 2), nullable=False, default=50)
    # Self-pickup app usage charge
    self_pickup_app_usage_charge = Column(DECIMAL(10, 2), nullable=False, default=5.00)
    # Multi-stop trips (BRD: CD-19 / BE-16 / BR-9)
    multi_stop_max_count = Column(Integer, nullable=False, default=2)
    multi_stop_free_minutes = Column(Integer, nullable=False, default=3)
    multi_stop_excess_per_minute = Column(DECIMAL(10, 2), nullable=False, default=5)
    multi_stop_fee_per_stop = Column(DECIMAL(10, 2), nullable=False, default=50)
    max_settle_amount = Column(DECIMAL(10, 2), default=1000.00)
    # Peak Hours
    peak_start_hour = Column(Integer, default=17)
    peak_end_hour = Column(Integer, default=20)
    peak_extra_amount = Column(DECIMAL(10, 2), default=0.00)
    peak_is_active = Column(Boolean, nullable=False, default=False)
    # Referral
    referral_referrer_amount = Column(DECIMAL(10, 2), nullable=False, default=Decimal("300.00"))
    referral_referred_amount = Column(DECIMAL(10, 2), nullable=False, default=Decimal("300.00"))
    # Branding
    logo_url = Column(String(255))
    favicon_url = Column(String(255))
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Incident(Base):
    """Driver-reported road event (accident, traffic, closure, checkpoint).

    Used by:
    - other drivers nearby — to render warning pins on their map (BRD)
    - admin — to see hotspots in real time

    `kind` whitelist is enforced in the API, not at DB level, so admin can
    add new types later without a migration.
    """
    __tablename__ = "incidents"

    id = Column(Integer, primary_key=True, index=True)
    reported_by_user_id = Column(Integer, ForeignKey("users.id"))
    kind = Column(String(30), nullable=False)  # accident | traffic | closure | police | hazard | other
    lat = Column(DECIMAL(10, 7), nullable=False)
    lng = Column(DECIMAL(10, 7), nullable=False)
    note = Column(Text)
    status = Column(String(20), nullable=False, default="active")  # active | expired | dismissed
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    reporter = relationship("User", foreign_keys=[reported_by_user_id])


class EmergencyAlert(Base):
    """A panic-button alert raised by a customer mid-ride (BRD: CD-17).

    `status` lifecycle: open → acknowledged → resolved | dismissed.
    Snapshot the rider's location + booking ref so admin sees what mattered
    even if the rider's phone later goes silent.
    """
    __tablename__ = "emergency_alerts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    booking_id = Column(Integer, ForeignKey("bookings.id"), nullable=True, index=True)
    booking_ref = Column(String(20))
    lat = Column(DECIMAL(10, 7))
    lng = Column(DECIMAL(10, 7))
    note = Column(Text)
    status = Column(String(20), nullable=False, default="open", index=True)
    acknowledged_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    acknowledged_at = Column(DateTime(timezone=True))
    resolved_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", foreign_keys=[user_id])


class LoyaltyTransaction(Base):
    """Audit ledger for loyalty points (BRD: RW-01).

    `points` is signed: positive on earn, negative on redeem. The matching
    `customer.loyalty_points` balance is kept hot for fast reads.
    `source_kind` + `source_id` link back to the booking/order that caused
    the entry so the admin can trace any anomaly.
    """
    __tablename__ = "loyalty_transactions"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    points = Column(Integer, nullable=False)
    kind = Column(String(20), nullable=False)  # earn | redeem | adjust
    source_kind = Column(String(20))           # booking | food_order | market_order | manual
    source_id = Column(Integer)
    description = Column(Text)
    balance_after = Column(Integer, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class CustomerPromoClaim(Base):
    """Tracks which promos a customer has 'saved' to their inbox (BRD: RW-04).

    Claiming is purely a UX affordance — the promo can still be applied at
    checkout without claiming. Claimed promos float to the top of the inbox
    and get a 'Saved' badge.
    """
    __tablename__ = "customer_promo_claims"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    promo_code_id = Column(Integer, ForeignKey("promo_codes.id", ondelete="CASCADE"), index=True)
    claimed_at = Column(DateTime(timezone=True), server_default=func.now())


class FlashWeightTier(Base):
    """Admin-configurable weight tier for Flash parcel deliveries.

    Each tier maps a weight band (min_kg .. max_kg) to a flat surcharge added
    on top of the base distance fare. `max_kg = None` represents the open-ended
    top tier ("> X kg"). Customers pick a tier on the parcel screen; the fare
    service looks up the row by weight and adds `surcharge` to the final fare.
    """
    __tablename__ = "flash_weight_tiers"

    id = Column(Integer, primary_key=True, index=True)
    label = Column(String(40), nullable=False)
    min_weight_kg = Column(DECIMAL(6, 2), nullable=False, default=0)
    max_weight_kg = Column(DECIMAL(6, 2), nullable=True)
    representative_weight_kg = Column(DECIMAL(6, 2), nullable=False, default=0)
    surcharge = Column(DECIMAL(10, 2), nullable=False, default=0)
    icon = Column(String(40), nullable=False, default="inventory_2")
    display_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class DriverPayout(Base):
    __tablename__ = "driver_payouts"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount = Column(DECIMAL(10, 2), nullable=False)
    description = Column(String(255))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    driver = relationship("Driver", foreign_keys=[driver_id])
    user = relationship("User", foreign_keys=[user_id])


class DriverIncentive(Base):
    __tablename__ = "driver_incentives"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(100), nullable=False)  # e.g., "One Day Incentives", "Weekday Incentives"
    limit_days = Column(Integer, default=1)  # e.g., 1 day, 6 days
    trips_required = Column(Integer, nullable=False)  # e.g., 3, 100, 120, 225
    reward_amount = Column(DECIMAL(10, 2), nullable=False)  # e.g., 350, 3500, 6000, 20000
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class PeakHourSetting(Base):
    __tablename__ = "peak_hour_settings"

    id = Column(Integer, primary_key=True, index=True)
    start_hour = Column(Integer, nullable=True, default=9)
    end_hour = Column(Integer, nullable=True, default=11)
    start_time = Column(String(5), nullable=True, default="09:00")
    end_time = Column(String(5), nullable=True, default="11:00")
    extra_amount = Column(DECIMAL(10, 2), nullable=False, default=50.00)
    is_active = Column(Boolean, nullable=False, default=True)
    vehicle_category = Column(String(50), nullable=True)


class SurgeZone(Base):
    """Geographic area (polygon) where peak hour/surge pricing applies."""
    __tablename__ = "surge_zones"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    # Stored as a list of dicts: [{"lat": 6.9, "lng": 79.8}, ...]
    coordinates = Column(JSON, nullable=False)
    flat_extra_charge = Column(DECIMAL(10, 2), nullable=False, default=0.00)
    start_time = Column(String(5), nullable=True)  # e.g., "17:00"
    end_time = Column(String(5), nullable=True)    # e.g., "19:00"
    is_active = Column(Boolean, nullable=False, default=True)
    color = Column(String(7), nullable=False, server_default="#dc3545")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

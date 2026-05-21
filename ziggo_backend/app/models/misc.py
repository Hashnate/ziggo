from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    DECIMAL,
    ForeignKey,
    Text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

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
    rider_penalty = Column(DECIMAL(10, 2), default=0)
    # Security
    min_password_length = Column(Integer, default=6)
    session_timeout_minutes = Column(Integer, default=30)
    max_login_attempts = Column(Integer, default=5)
    # Notifications
    email_notifications_enabled = Column(Boolean, nullable=False, default=True)
    sms_notifications_enabled = Column(Boolean, nullable=False, default=True)
    push_notifications_enabled = Column(Boolean, nullable=False, default=True)
    # Driver incentives
    min_rides_daily_bonus = Column(Integer, default=15)
    daily_bonus_amount = Column(DECIMAL(10, 2), default=1000)
    commission_cycle_rides = Column(Integer, default=5)
    commission_per_cycle = Column(DECIMAL(10, 2), default=500)
    # Branding
    logo_url = Column(String(255))
    favicon_url = Column(String(255))
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


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

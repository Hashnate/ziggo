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
    status = Column(String(20), default="pending")
    assigned_to = Column(Integer, ForeignKey("users.id"))
    resolved_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())


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
    base_fare = Column(DECIMAL(10, 2))
    per_km_rate = Column(DECIMAL(10, 2))
    per_minute_rate = Column(DECIMAL(10, 2))
    min_fare = Column(DECIMAL(10, 2), default=0)
    platform_fee_percent = Column(DECIMAL(5, 2), default=15)
    surge_multiplier = Column(DECIMAL(3, 2), default=1.00)
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

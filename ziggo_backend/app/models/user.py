from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    DECIMAL,
    ForeignKey,
    Enum as SQLEnum,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum
import secrets
import string

from ..database import Base


class UserRole(str, enum.Enum):
    CUSTOMER = "customer"
    DRIVER = "driver"
    ADMIN = "admin"
    RESTAURANT_OWNER = "restaurant_owner"
    MARKET_OWNER = "market_owner"


class AdminRole(str, enum.Enum):
    SUPERADMIN = "superadmin"
    ADMIN = "admin"
    DATA_ENTRY = "data_entry"


class ReferralKind(str, enum.Enum):
    credit = "credit"
    points = "points"


class ReferralStatus(str, enum.Enum):
    pending = "pending"
    completed = "completed"
    failed = "failed"


def generate_referral_code() -> str:
    chars = string.ascii_uppercase + string.digits
    return "ZG" + "".join(secrets.choice(chars) for _ in range(6))


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), unique=True, nullable=False, index=True)
    role = Column(SQLEnum(UserRole, name="user_role"), nullable=False)
    admin_role = Column(String(30), nullable=True)
    full_name = Column(String(100))
    email = Column(String(120))
    profile_photo = Column(String(255))
    rating = Column(DECIMAL(3, 2), default=0)
    total_rides = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)
    # FCM device token. User-level (not customer/driver) so the same person
    # gets pushes across roles + devices. ensure_schema auto-adds this column
    # on startup if it doesn't exist — no manual migration needed.
    notification_token = Column(String(255))
    password = Column(String(100), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    referral_code = Column(String(16), unique=True, nullable=True, default=generate_referral_code)
    referred_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    customer_profile = relationship("Customer", back_populates="user", uselist=False, cascade="all, delete-orphan")
    driver_profile = relationship("Driver", back_populates="user", uselist=False, cascade="all, delete-orphan")
    saved_addresses = relationship("SavedAddress", back_populates="user", cascade="all, delete-orphan")
    wallet_transactions = relationship("WalletTransaction", back_populates="user", cascade="all, delete-orphan")
    notifications = relationship("Notification", back_populates="user", cascade="all, delete-orphan")
    referred_by = relationship("User", remote_side=[id], foreign_keys=[referred_by_user_id])


class Customer(Base):
    __tablename__ = "customers"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    default_payment_method = Column(String(20), default="cash")
    wallet_balance = Column(DECIMAL(10, 2), default=0)
    notification_token = Column(String(255))
    gold_member = Column(Boolean, default=False)
    gold_expires_at = Column(DateTime(timezone=True))
    loyalty_points = Column(Integer, nullable=False, default=0)

    user = relationship("User", back_populates="customer_profile")
    bookings = relationship("Booking", back_populates="customer")
    cards = relationship("CustomerCard", back_populates="customer", cascade="all, delete-orphan")


class CustomerCard(Base):
    __tablename__ = "customer_cards"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="CASCADE"), index=True)
    card_no = Column(String(30), nullable=False)  # masked card number
    card_expiry = Column(String(10), nullable=False)  # MMYY
    card_holder_name = Column(String(100), nullable=True)
    card_type = Column(String(20), nullable=False)  # VISA, MASTER, etc.
    customer_token = Column(String(255), nullable=False)
    is_default = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    customer = relationship("Customer", back_populates="cards")


class DriverStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    SUSPENDED = "suspended"


class Driver(Base):
    __tablename__ = "drivers"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    nic_number = Column(String(20), unique=True)
    license_number = Column(String(50), unique=True)
    vehicle_type = Column(String(20))  # bike, tuk, car, van, truck
    vehicle_number = Column(String(20), unique=True)
    vehicle_model = Column(String(100))
    vehicle_color = Column(String(50))
    vehicle_year = Column(Integer)
    vehicle_photo_url = Column(String(255))
    is_approved = Column(Boolean, default=False)
    is_online = Column(Boolean, default=False)
    current_lat = Column(DECIMAL(10, 7))
    current_lng = Column(DECIMAL(10, 7))
    current_heading = Column(DECIMAL(5, 2))
    last_location_update = Column(DateTime(timezone=True))
    total_earnings = Column(DECIMAL(12, 2), default=0)
    today_earnings = Column(DECIMAL(10, 2), default=0)
    today_rides = Column(Integer, default=0)
    acceptance_rate = Column(DECIMAL(5, 2), default=100)
    status = Column(SQLEnum(DriverStatus, name="driver_status"), default=DriverStatus.PENDING)
    approved_at = Column(DateTime(timezone=True))
    relative_name = Column(String(100))
    relative_contact = Column(String(20))
    relative_relationship = Column(String(50))
    billing_proof_url = Column(String(255))
    bank_name = Column(String(100), nullable=True)
    account_holder_name = Column(String(100), nullable=True)
    account_number = Column(String(50), nullable=True)
    branch_name = Column(String(100), nullable=True)


    user = relationship("User", back_populates="driver_profile")
    documents = relationship("DriverDocument", back_populates="driver", cascade="all, delete-orphan")
    bookings = relationship("Booking", back_populates="driver")


class DriverDocument(Base):
    __tablename__ = "driver_documents"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id", ondelete="CASCADE"))
    document_type = Column(String(50))  # nic, license, vehicle_reg, insurance
    document_url = Column(String(255))
    is_verified = Column(Boolean, default=False)
    verified_by = Column(Integer, ForeignKey("users.id"))
    verified_at = Column(DateTime(timezone=True))
    uploaded_at = Column(DateTime(timezone=True), server_default=func.now())

    driver = relationship("Driver", back_populates="documents")


class SavedAddress(Base):
    __tablename__ = "saved_addresses"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    label = Column(String(50))  # Home, Work, Gym, etc.
    address = Column(String(255))
    lat = Column(DECIMAL(10, 7))
    lng = Column(DECIMAL(10, 7))
    is_default = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="saved_addresses")


class OTPCode(Base):
    __tablename__ = "otp_codes"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), index=True, nullable=False)
    code = Column(String(10), nullable=False)
    is_used = Column(Boolean, default=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class ReferralBonus(Base):
    __tablename__ = "referral_bonuses"

    id = Column(Integer, primary_key=True, index=True)
    referrer_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    referred_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    kind = Column(SQLEnum(ReferralKind, name="referral_kind"), nullable=False, default=ReferralKind.credit)
    referrer_amount = Column(DECIMAL(10, 2), nullable=False)
    referred_amount = Column(DECIMAL(10, 2), nullable=False)
    status = Column(SQLEnum(ReferralStatus, name="referral_status"), nullable=False, default=ReferralStatus.pending)
    trigger_description = Column(String(255))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    paid_at = Column(DateTime(timezone=True), nullable=True)

    referrer = relationship("User", foreign_keys=[referrer_user_id], backref="referrals_sent")
    referred = relationship("User", foreign_keys=[referred_user_id], backref="referrals_received")

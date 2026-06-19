"""Event ticketing — concerts, shows, festivals.

Admin creates events with one or more ticket tiers. Customers browse the
listing + detail, select tickets (cart), and purchase (summary → wallet/cash).
A purchase writes an EventOrder + EventOrderItem rows; wallet payments debit
Customer.wallet_balance and write a WalletTransaction, mirroring rides.
"""
import enum

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
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from ..database import Base


class EventOrderStatus(str, enum.Enum):
    PENDING = "pending"        # placed, awaiting payment (cash) or just created
    CONFIRMED = "confirmed"    # paid (wallet) / confirmed
    CANCELLED = "cancelled"


class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text)
    venue = Column(String(200))
    city = Column(String(80))
    image_url = Column(String(500))
    organizer_name = Column(String(100))
    organizer_phone = Column(String(20))
    category = Column(String(50))  # e.g. "Sports", "Bank Offers", "Experience", "Charity"
    starts_at = Column(DateTime(timezone=True), nullable=False, index=True)
    ends_at = Column(DateTime(timezone=True))
    is_published = Column(Boolean, default=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    tiers = relationship(
        "EventTicketTier",
        back_populates="event",
        cascade="all, delete-orphan",
        order_by="EventTicketTier.price",
    )
    orders = relationship("EventOrder", back_populates="event")


class EventTicketTier(Base):
    __tablename__ = "event_ticket_tiers"

    id = Column(Integer, primary_key=True, index=True)
    event_id = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"))
    name = Column(String(50), nullable=False)         # VIP, Premium, Regular
    price = Column(DECIMAL(10, 2), nullable=False)
    capacity = Column(Integer)                         # max seats / null = unlimited
    description = Column(Text)
    # Optional sale window. Drives the "Only available till …" / "Starting …"
    # subtitles and the Not-Available badge in the customer cart.
    sale_starts_at = Column(DateTime(timezone=True))
    sale_ends_at = Column(DateTime(timezone=True))

    event = relationship("Event", back_populates="tiers")


class EventOrder(Base):
    __tablename__ = "event_orders"

    id = Column(Integer, primary_key=True, index=True)
    order_ref = Column(String(20), unique=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"))
    event_id = Column(Integer, ForeignKey("events.id"))

    status = Column(
        SQLEnum(EventOrderStatus, name="event_order_status"),
        default=EventOrderStatus.PENDING,
        index=True,
    )
    subtotal = Column(DECIMAL(10, 2), nullable=False, default=0)
    convenience_fee = Column(DECIMAL(10, 2), nullable=False, default=0)
    discount_amount = Column(DECIMAL(10, 2), nullable=False, default=0)
    total_amount = Column(DECIMAL(10, 2), nullable=False, default=0)

    payment_method = Column(String(20))               # wallet | cash
    payment_status = Column(String(20), default="pending")

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    items = relationship(
        "EventOrderItem", back_populates="order", cascade="all, delete-orphan"
    )
    event = relationship("Event", back_populates="orders")


class EventOrderItem(Base):
    __tablename__ = "event_order_items"

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("event_orders.id", ondelete="CASCADE"))
    tier_id = Column(Integer, ForeignKey("event_ticket_tiers.id"))
    tier_name = Column(String(50))                     # snapshot at purchase
    quantity = Column(Integer, nullable=False)
    price_at_order = Column(DECIMAL(10, 2), nullable=False)

    order = relationship("EventOrder", back_populates="items")

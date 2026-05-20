"""Event ticketing — concerts, shows, festivals.

Browse-only for now: admin creates events with one or more ticket tiers, and
customers see the listing + detail. No purchase pipeline yet — tapping Buy
in the customer app surfaces a "contact organizer" CTA.
"""
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


class EventTicketTier(Base):
    __tablename__ = "event_ticket_tiers"

    id = Column(Integer, primary_key=True, index=True)
    event_id = Column(Integer, ForeignKey("events.id", ondelete="CASCADE"))
    name = Column(String(50), nullable=False)         # VIP, Premium, Regular
    price = Column(DECIMAL(10, 2), nullable=False)
    capacity = Column(Integer)                         # max seats / null = unlimited
    description = Column(Text)

    event = relationship("Event", back_populates="tiers")

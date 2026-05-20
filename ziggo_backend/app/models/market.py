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
import enum

from ..database import Base


class MarketOrderStatus(str, enum.Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    PROCESSING = "processing"
    READY_FOR_PICKUP = "ready_for_pickup"
    OUT_FOR_DELIVERY = "out_for_delivery"
    SHIPPED = "shipped"  # legacy, kept for backward compat with old rows
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


class MarketVendor(Base):
    __tablename__ = "market_vendors"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text)
    category = Column(String(100))  # Grocery, Pharmacy, Electronics, etc.
    address = Column(String(500))
    lat = Column(DECIMAL(10, 7))
    lng = Column(DECIMAL(10, 7))
    phone_number = Column(String(20))
    image_url = Column(String(255))
    rating = Column(DECIMAL(3, 2), default=0)
    is_active = Column(Boolean, default=False)
    is_open = Column(Boolean, default=True)
    opening_time = Column(String(10))
    closing_time = Column(String(10))
    delivery_fee = Column(DECIMAL(10, 2), default=0)
    eta_minutes = Column(Integer, default=40)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    products = relationship("Product", back_populates="vendor", cascade="all, delete-orphan")
    orders = relationship("MarketOrder", back_populates="vendor")


class Product(Base):
    __tablename__ = "products"

    id = Column(Integer, primary_key=True, index=True)
    vendor_id = Column(Integer, ForeignKey("market_vendors.id", ondelete="CASCADE"))
    name = Column(String(200), nullable=False)
    description = Column(Text)
    price = Column(DECIMAL(10, 2), nullable=False)
    stock_quantity = Column(Integer, default=0)
    image_url = Column(String(255))
    unit = Column(String(20))
    is_available = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    vendor = relationship("MarketVendor", back_populates="products")


class MarketOrder(Base):
    __tablename__ = "market_orders"

    id = Column(Integer, primary_key=True, index=True)
    order_ref = Column(String(20), unique=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"))
    vendor_id = Column(Integer, ForeignKey("market_vendors.id"))
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)

    status = Column(
        SQLEnum(MarketOrderStatus, name="market_order_status"),
        default=MarketOrderStatus.PENDING,
        index=True,
    )
    total_amount = Column(DECIMAL(10, 2))
    delivery_fee = Column(DECIMAL(10, 2))
    final_amount = Column(DECIMAL(10, 2))

    delivery_address = Column(Text)
    delivery_lat = Column(DECIMAL(10, 7))
    delivery_lng = Column(DECIMAL(10, 7))
    payment_method = Column(String(20))
    payment_status = Column(String(20), default="pending")

    instructions = Column(Text)
    cancellation_reason = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    confirmed_at = Column(DateTime(timezone=True))
    ready_at = Column(DateTime(timezone=True))
    picked_up_at = Column(DateTime(timezone=True))
    delivered_at = Column(DateTime(timezone=True))

    vendor = relationship("MarketVendor", back_populates="orders")
    items = relationship("MarketOrderItem", back_populates="order", cascade="all, delete-orphan")


class MarketOrderItem(Base):
    __tablename__ = "market_order_items"

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("market_orders.id", ondelete="CASCADE"))
    product_id = Column(Integer, ForeignKey("products.id"))
    quantity = Column(Integer, nullable=False)
    price_at_order = Column(DECIMAL(10, 2), nullable=False)

    order = relationship("MarketOrder", back_populates="items")

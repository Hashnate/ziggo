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
    logo_url = Column(String(255))
    
    # New fields requested by user
    business_registration_number = Column(String(100), nullable=True)
    tax_vat_number = Column(String(100), nullable=True)
    self_delivery = Column(Boolean, default=False, nullable=False)
    marketplace_delivery = Column(Boolean, default=True, nullable=False)
    delivery_radius_km = Column(DECIMAL(10, 2), nullable=True)
    average_prep_time_minutes = Column(Integer, default=30)
    bank_name = Column(String(100), nullable=True)
    account_holder_name = Column(String(100), nullable=True)
    account_number = Column(String(100), nullable=True)
    branch_name = Column(String(100), nullable=True)
    nic_passport_copy_url = Column(String(255), nullable=True)
    business_reg_cert_url = Column(String(255), nullable=True)
    tax_cert_url = Column(String(255), nullable=True)
    food_license_url = Column(String(255), nullable=True)
    additional_docs_url = Column(String(255), nullable=True)
    commission_percentage = Column(DECIMAL(5, 2), default=10.00, nullable=False)
    priority_level = Column(String(50), default="standard", nullable=False)
    is_featured = Column(Boolean, default=False, nullable=False)
    pickup_fee = Column(DECIMAL(10, 2), default=70.00, nullable=False)
    per_km_rate = Column(DECIMAL(10, 2), default=40.00, nullable=False)
    boost = Column(DECIMAL(10, 2), default=0.00, nullable=False)
    max_settle_amount = Column(DECIMAL(10, 2), default=1000.00)

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
    # When set and greater than `price`, the product is an offer: the UI shows
    # the strikethrough was-price and computes the % OFF badge.
    original_price = Column(DECIMAL(10, 2))
    stock_quantity = Column(Integer, default=0)
    image_url = Column(String(255))
    unit = Column(String(20))
    # Per-unit weight in kilograms, used by the distance+weight delivery-fee
    # engine. Null is treated as the DEFAULT_ITEM_WEIGHT_KG fallback.
    weight_kg = Column(DECIMAL(10, 3), nullable=True)
    # Free-form product category (e.g. "Fresh Produce", "Skin Care") that the
    # customer vendor page groups products into as tabs.
    category = Column(String(100))
    # Vendor-flagged "Popular Picks" surface on the vendor page.
    is_popular = Column(Boolean, default=False)
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
    is_self_pickup = Column(Boolean, default=False, nullable=False)

    status = Column(
        SQLEnum(MarketOrderStatus, name="market_order_status"),
        default=MarketOrderStatus.PENDING,
        index=True,
    )
    total_amount = Column(DECIMAL(10, 2))
    delivery_fee = Column(DECIMAL(10, 2))
    # BRD: RW-02 — loyalty redemption snapshot
    redeem_points = Column(Integer, nullable=False, default=0)
    redeem_discount = Column(DECIMAL(10, 2), nullable=False, default=0)
    # BRD: RW-03 — gold delivery discount applied
    gold_discount = Column(DECIMAL(10, 2), nullable=False, default=0)
    final_amount = Column(DECIMAL(10, 2))

    delivery_address = Column(Text)
    delivery_lat = Column(DECIMAL(10, 7))
    delivery_lng = Column(DECIMAL(10, 7))
    # How this order gets to the customer: "marketplace" (broadcast to riders)
    # or "self" (the vendor delivers it). Null until the vendor marks ready.
    delivery_mode = Column(String(20), nullable=True)
    # Snapshot of what drove the delivery fee, for vendor/customer transparency.
    delivery_distance_km = Column(DECIMAL(10, 2), nullable=True)
    total_weight_kg = Column(DECIMAL(10, 3), nullable=True)
    payment_method = Column(String(20))
    payment_status = Column(String(20), default="pending")

    instructions = Column(Text)
    cancellation_reason = Column(Text)
    # Customer delivery rating (1-5) and optional text feedback left after delivery.
    customer_rating = Column(Integer, nullable=True)
    customer_feedback = Column(Text, nullable=True)
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


class MarketAd(Base):
    __tablename__ = "market_ads"

    id = Column(Integer, primary_key=True, index=True)
    vendor_id = Column(Integer, ForeignKey("market_vendors.id", ondelete="CASCADE"), nullable=True)
    restaurant_id = Column(Integer, ForeignKey("restaurants.id", ondelete="CASCADE"), nullable=True)
    image_url = Column(String(255), nullable=False)
    radius_km = Column(DECIMAL(10, 2), default=5.00, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    link_type = Column(String(20), nullable=False, default="none")
    link_value = Column(String(255))
    display_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    vendor = relationship("MarketVendor")
    restaurant = relationship("Restaurant")


class MarketDeal(Base):
    __tablename__ = "market_deals"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(120), nullable=False)
    subtitle = Column(String(200))
    image_url = Column(String(255))
    color = Column(String(20), nullable=False, default="primary")
    promo_code_id = Column(
        Integer, ForeignKey("promo_codes.id", ondelete="SET NULL"), nullable=True
    )
    display_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    link_type = Column(String(20), nullable=False, default="none")
    link_value = Column(String(255))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    promo_code = relationship("PromoCode")


class MarketCategory(Base):
    __tablename__ = "market_categories"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(120), nullable=False)
    color = Column(String(20), nullable=False, default="primary")
    image_url = Column(String(255))
    display_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


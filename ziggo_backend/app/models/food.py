from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    DECIMAL,
    ForeignKey,
    Text,
    Table,
    UniqueConstraint,
    Enum as SQLEnum,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import enum

from ..database import Base


class FoodOrderStatus(str, enum.Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    PREPARING = "preparing"
    READY_FOR_PICKUP = "ready_for_pickup"
    OUT_FOR_DELIVERY = "out_for_delivery"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


class Restaurant(Base):
    __tablename__ = "restaurants"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    description = Column(Text)
    address = Column(String(500))
    lat = Column(DECIMAL(10, 7))
    lng = Column(DECIMAL(10, 7))
    phone_number = Column(String(20))
    email = Column(String(120))
    image_url = Column(String(255))
    rating = Column(DECIMAL(3, 2), default=0)
    is_active = Column(Boolean, default=True)
    is_open = Column(Boolean, default=True)
    opening_time = Column(String(10))
    closing_time = Column(String(10))
    delivery_fee = Column(DECIMAL(10, 2), default=0)
    cuisine = Column(String(100))
    eta_minutes = Column(Integer, default=30)
    pickup_fee = Column(DECIMAL(10, 2), default=70.00, nullable=False)
    per_km_rate = Column(DECIMAL(10, 2), default=40.00, nullable=False)
    boost = Column(DECIMAL(10, 2), default=0.00, nullable=False)
    commission_percentage = Column(DECIMAL(5, 2), default=20.00, nullable=False)

    owner_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    categories = relationship("MenuCategory", back_populates="restaurant", cascade="all, delete-orphan")
    items = relationship("MenuItem", back_populates="restaurant", cascade="all, delete-orphan")
    orders = relationship("FoodOrder", back_populates="restaurant")
    food_categories = relationship(
        "FoodCategory",
        secondary="restaurant_food_categories",
        back_populates="restaurants",
    )
    collections = relationship(
        "FoodCollection",
        secondary="food_collection_restaurants",
        back_populates="restaurants",
    )


class MenuCategory(Base):
    __tablename__ = "menu_categories"

    id = Column(Integer, primary_key=True, index=True)
    restaurant_id = Column(Integer, ForeignKey("restaurants.id", ondelete="CASCADE"))
    name = Column(String(100), nullable=False)
    description = Column(String(500))
    display_order = Column(Integer, default=0)
    is_active = Column(Boolean, default=True)

    restaurant = relationship("Restaurant", back_populates="categories")
    items = relationship("MenuItem", back_populates="category")


class MenuItem(Base):
    __tablename__ = "menu_items"

    id = Column(Integer, primary_key=True, index=True)
    restaurant_id = Column(Integer, ForeignKey("restaurants.id", ondelete="CASCADE"))
    category_id = Column(Integer, ForeignKey("menu_categories.id"))
    name = Column(String(200), nullable=False)
    description = Column(Text)
    price = Column(DECIMAL(10, 2), nullable=False)
    image_url = Column(String(255))
    is_available = Column(Boolean, default=True)
    is_veg = Column(Boolean, default=False)
    calories = Column(Integer)
    prep_time_min = Column(Integer)

    restaurant = relationship("Restaurant", back_populates="items")
    category = relationship("MenuCategory", back_populates="items")


class FoodOrder(Base):
    __tablename__ = "food_orders"

    id = Column(Integer, primary_key=True, index=True)
    order_ref = Column(String(20), unique=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id", ondelete="SET NULL"), nullable=True)
    restaurant_id = Column(Integer, ForeignKey("restaurants.id", ondelete="SET NULL"), nullable=True)
    driver_id = Column(Integer, ForeignKey("drivers.id", ondelete="SET NULL"), nullable=True)

    status = Column(
        SQLEnum(FoodOrderStatus, name="food_order_status"),
        default=FoodOrderStatus.PENDING,
        index=True,
    )
    total_amount = Column(DECIMAL(10, 2))
    delivery_fee = Column(DECIMAL(10, 2))
    tax_amount = Column(DECIMAL(10, 2), default=0)
    discount_amount = Column(DECIMAL(10, 2), default=0)
    # BRD: RW-02 — loyalty redemption snapshot
    redeem_points = Column(Integer, nullable=False, default=0)
    redeem_discount = Column(DECIMAL(10, 2), nullable=False, default=0)
    # BRD: RW-03 — gold delivery discount applied (so admin reporting can see it)
    gold_discount = Column(DECIMAL(10, 2), nullable=False, default=0)
    final_amount = Column(DECIMAL(10, 2))

    delivery_address = Column(Text)
    delivery_lat = Column(DECIMAL(10, 7))
    delivery_lng = Column(DECIMAL(10, 7))

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

    items = relationship("FoodOrderItem", back_populates="order", cascade="all, delete-orphan")
    restaurant = relationship("Restaurant", back_populates="orders")


class FoodOrderItem(Base):
    __tablename__ = "food_order_items"

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("food_orders.id", ondelete="CASCADE"))
    menu_item_id = Column(Integer, ForeignKey("menu_items.id"))
    quantity = Column(Integer, nullable=False)
    price_at_order = Column(DECIMAL(10, 2), nullable=False)
    notes = Column(String(255))

    order = relationship("FoodOrder", back_populates="items")


# ---------------------------------------------------------------------------
# Food home-page layout (admin-managed). Drives the customer Food home screen:
# carousel banners, cuisine category chips, curated "Picked for you"
# collections, and promo-linked deal cards. All four are created on first boot
# by schema_sync._seed_food_home and editable at /admin/food-home.
# ---------------------------------------------------------------------------

# Restaurant <-> cuisine category (many-to-many). Tapping a category on the
# home screen filters the restaurant list to its tagged restaurants.
restaurant_food_categories = Table(
    "restaurant_food_categories",
    Base.metadata,
    Column(
        "restaurant_id",
        Integer,
        ForeignKey("restaurants.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "food_category_id",
        Integer,
        ForeignKey("food_categories.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)

# Collection <-> restaurant (many-to-many). A collection is an admin-curated
# group ("Popular", "Newly Joined", ...). Tapping one filters to its members.
food_collection_restaurants = Table(
    "food_collection_restaurants",
    Base.metadata,
    Column(
        "collection_id",
        Integer,
        ForeignKey("food_collections.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "restaurant_id",
        Integer,
        ForeignKey("restaurants.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)


class FoodBanner(Base):
    __tablename__ = "food_banners"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(120))
    image_url = Column(String(255), nullable=False)
    # none | restaurant | category | collection | promo | url
    link_type = Column(String(20), nullable=False, default="none")
    link_value = Column(String(255))
    display_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class FoodCategory(Base):
    __tablename__ = "food_categories"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(80), nullable=False)
    icon_url = Column(String(255))
    display_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    restaurants = relationship(
        "Restaurant",
        secondary="restaurant_food_categories",
        back_populates="food_categories",
    )


class FoodCollection(Base):
    __tablename__ = "food_collections"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(80), nullable=False)
    icon = Column(String(40), nullable=False, default="local_fire_department")
    color = Column(String(20), nullable=False, default="blue")
    display_order = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    restaurants = relationship(
        "Restaurant",
        secondary="food_collection_restaurants",
        back_populates="collections",
    )


class FoodDeal(Base):
    __tablename__ = "food_deals"

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
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    promo_code = relationship("PromoCode")


class FavoriteRestaurant(Base):
    __tablename__ = "favorite_restaurants"
    __table_args__ = (
        UniqueConstraint(
            "customer_id", "restaurant_id", name="uq_favorite_customer_restaurant"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(
        Integer, ForeignKey("customers.id", ondelete="CASCADE"), index=True
    )
    restaurant_id = Column(
        Integer, ForeignKey("restaurants.id", ondelete="CASCADE"), index=True
    )
    created_at = Column(DateTime(timezone=True), server_default=func.now())

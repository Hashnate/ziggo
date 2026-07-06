from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime


class ProductResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    price: float
    original_price: Optional[float] = None
    stock_quantity: int
    image_url: Optional[str] = None
    unit: Optional[str] = None
    category: Optional[str] = None
    is_popular: bool = False
    is_available: bool
    weight_kg: Optional[float] = None

    class Config:
        from_attributes = True


class MarketVendorResponse(BaseModel):
    id: int
    name: str
    category: Optional[str] = None
    description: Optional[str] = None
    address: Optional[str] = None
    image_url: Optional[str] = None
    rating: float
    is_active: bool

    class Config:
        from_attributes = True


class MarketOrderItemRequest(BaseModel):
    product_id: int
    quantity: int


class MarketOrderCreate(BaseModel):
    vendor_id: int
    items: List[MarketOrderItemRequest]
    delivery_address: Optional[str] = None
    delivery_lat: Optional[float] = None
    delivery_lng: Optional[float] = None
    payment_method: str = "cash"
    instructions: Optional[str] = None
    # BRD: RW-02 — loyalty points the customer wants to redeem at checkout
    redeem_points: int = 0
    # BRD: optional promo code applied at checkout
    promo_code: Optional[str] = None
    is_self_pickup: bool = False


class MarketOrderResponse(BaseModel):
    id: int
    order_ref: str
    status: str
    total_amount: float
    delivery_fee: float
    final_amount: float
    delivery_address: Optional[str] = None
    payment_method: str
    payment_status: str
    delivery_distance_km: Optional[float] = None
    total_weight_kg: Optional[float] = None
    delivery_mode: Optional[str] = None
    created_at: datetime
    cancellation_reason: Optional[str] = None
    is_self_pickup: bool = False

    class Config:
        from_attributes = True


# ---------- Vendor portal schemas ----------


class MarketVendorProfileResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    phone_number: Optional[str] = None
    image_url: Optional[str] = None
    logo_url: Optional[str] = None
    opening_time: Optional[str] = None
    closing_time: Optional[str] = None
    delivery_fee: float = 0.0
    eta_minutes: Optional[int] = None
    rating: float = 0.0
    is_active: bool = False
    is_open: bool = True
    is_approved: bool = False
    delivery_radius_km: Optional[float] = None
    self_delivery: bool = False
    marketplace_delivery: bool = True
    created_at: Optional[datetime] = None


class MarketVendorProfileUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    address: Optional[str] = Field(None, min_length=2, max_length=500)
    lat: Optional[float] = None
    lng: Optional[float] = None
    phone_number: Optional[str] = Field(None, max_length=20)
    opening_time: Optional[str] = Field(None, max_length=10)
    closing_time: Optional[str] = Field(None, max_length=10)
    delivery_fee: Optional[float] = Field(None, ge=0)
    eta_minutes: Optional[int] = Field(None, ge=5)
    delivery_radius_km: Optional[float] = Field(None, ge=0)
    self_delivery: Optional[bool] = None
    marketplace_delivery: Optional[bool] = None


class ProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    price: float = Field(..., ge=0)
    original_price: Optional[float] = Field(None, ge=0)
    stock_quantity: int = Field(0, ge=0)
    unit: Optional[str] = Field(None, max_length=20)
    category: Optional[str] = Field(None, max_length=100)
    is_popular: bool = False
    image_url: Optional[str] = Field(None, max_length=255)
    is_available: bool = True
    weight_kg: Optional[float] = Field(None, ge=0)


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    price: Optional[float] = Field(None, ge=0)
    original_price: Optional[float] = Field(None, ge=0)
    stock_quantity: Optional[int] = Field(None, ge=0)
    unit: Optional[str] = Field(None, max_length=20)
    category: Optional[str] = Field(None, max_length=100)
    is_popular: Optional[bool] = None
    image_url: Optional[str] = Field(None, max_length=255)
    is_available: Optional[bool] = None
    weight_kg: Optional[float] = Field(None, ge=0)


class MarketVendorRegisterRequest(BaseModel):
    """Owner self-registers their market stall. Same shape as
    RestaurantRegisterRequest — created with `is_active=False` pending admin
    approval, owner_id pointing to the current logged-in user."""

    name: str = Field(..., min_length=2, max_length=200)
    category: Optional[str] = Field(None, max_length=100)
    description: Optional[str] = None
    address: str = Field(..., min_length=2, max_length=500)
    lat: float
    lng: float
    phone_number: Optional[str] = Field(None, max_length=20)
    opening_time: Optional[str] = Field(None, max_length=10)
    closing_time: Optional[str] = Field(None, max_length=10)
    delivery_fee: Optional[float] = None
    eta_minutes: Optional[int] = None
    image_url: Optional[str] = None


class AdminMarketVendorCreate(BaseModel):
    """Admin-creates-vendor flow. Owner phone is required so we can either
    attach to an existing user or create one and bind role=market_owner."""

    name: str = Field(..., min_length=2, max_length=200)
    owner_phone: str = Field(..., pattern=r"^\d{10}$")
    owner_full_name: Optional[str] = None
    category: Optional[str] = None
    description: Optional[str] = None
    address: str = Field(..., min_length=2, max_length=500)
    lat: float
    lng: float
    phone_number: Optional[str] = None
    opening_time: Optional[str] = None
    closing_time: Optional[str] = None
    delivery_fee: Optional[float] = None
    eta_minutes: Optional[int] = None
    image_url: Optional[str] = None

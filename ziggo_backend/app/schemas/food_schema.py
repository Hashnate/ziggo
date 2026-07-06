from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime


class MenuItemResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    price: float
    image_url: Optional[str] = None
    is_available: bool
    is_veg: bool
    prep_time_min: Optional[int] = None
    category_id: Optional[int] = None

    class Config:
        from_attributes = True


class MenuCategoryResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None

    class Config:
        from_attributes = True


class RestaurantResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    cuisine: Optional[str] = None
    image_url: Optional[str] = None
    rating: float
    delivery_fee: float
    opening_time: Optional[str] = None
    closing_time: Optional[str] = None
    eta_minutes: Optional[int] = None
    is_active: bool

    class Config:
        from_attributes = True


class FoodOrderItemRequest(BaseModel):
    menu_item_id: int
    quantity: int
    notes: Optional[str] = None


class FoodOrderCreate(BaseModel):
    restaurant_id: int
    items: List[FoodOrderItemRequest]
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


class FoodOrderItemResponse(BaseModel):
    menu_item_id: int
    quantity: int
    price_at_order: float

    class Config:
        from_attributes = True


class FoodOrderResponse(BaseModel):
    id: int
    order_ref: str
    status: str
    total_amount: float
    delivery_fee: float
    final_amount: float
    delivery_address: Optional[str] = None
    payment_method: str
    payment_status: str
    created_at: datetime
    is_self_pickup: bool = False
    restaurant_name: Optional[str] = None
    restaurant_address: Optional[str] = None
    items: List[FoodOrderItemResponse] = []

    class Config:
        from_attributes = True

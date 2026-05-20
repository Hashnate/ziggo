"""Pydantic schemas for the restaurant-owner portal."""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class RestaurantRegisterRequest(BaseModel):
    """Submitted by a logged-in user with role=restaurant_owner the first time
    they register their restaurant. Creates a Restaurant row with
    `is_active=False` and `owner_id` set — admin must approve before customers
    see it in the listing.
    """

    name: str = Field(..., min_length=2, max_length=200)
    description: Optional[str] = None
    address: str = Field(..., min_length=2, max_length=500)
    lat: float
    lng: float
    phone_number: Optional[str] = Field(None, max_length=20)
    cuisine: Optional[str] = Field(None, max_length=100)
    opening_time: Optional[str] = Field(None, max_length=10)
    closing_time: Optional[str] = Field(None, max_length=10)
    delivery_fee: Optional[float] = None
    eta_minutes: Optional[int] = None
    image_url: Optional[str] = None


class RestaurantProfileResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    phone_number: Optional[str] = None
    image_url: Optional[str] = None
    cuisine: Optional[str] = None
    opening_time: Optional[str] = None
    closing_time: Optional[str] = None
    delivery_fee: float = 0.0
    eta_minutes: Optional[int] = None
    rating: float = 0.0
    is_active: bool = False
    is_open: bool = True
    is_approved: bool = False
    created_at: Optional[datetime] = None


class MenuCategoryCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    display_order: Optional[int] = 0


class MenuCategoryUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    description: Optional[str] = Field(None, max_length=500)
    display_order: Optional[int] = None
    is_active: Optional[bool] = None


class MenuItemCreate(BaseModel):
    category_id: Optional[int] = None
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    price: float = Field(..., ge=0)
    image_url: Optional[str] = Field(None, max_length=255)
    is_available: bool = True
    is_veg: bool = False
    prep_time_min: Optional[int] = Field(None, ge=0)


class MenuItemUpdate(BaseModel):
    category_id: Optional[int] = None
    name: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    price: Optional[float] = Field(None, ge=0)
    image_url: Optional[str] = Field(None, max_length=255)
    is_available: Optional[bool] = None
    is_veg: Optional[bool] = None
    prep_time_min: Optional[int] = Field(None, ge=0)


class RestaurantProfileUpdate(BaseModel):
    """Owner-side profile edits. Every field is optional so the form can
    submit only what changed."""

    name: Optional[str] = Field(None, min_length=2, max_length=200)
    description: Optional[str] = None
    address: Optional[str] = Field(None, min_length=2, max_length=500)
    lat: Optional[float] = None
    lng: Optional[float] = None
    phone_number: Optional[str] = Field(None, max_length=20)
    cuisine: Optional[str] = Field(None, max_length=100)
    opening_time: Optional[str] = Field(None, max_length=10)
    closing_time: Optional[str] = Field(None, max_length=10)
    delivery_fee: Optional[float] = Field(None, ge=0)
    eta_minutes: Optional[int] = Field(None, ge=5)

from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class PromoCodeResponse(BaseModel):
    id: int
    code: str
    description: Optional[str] = None
    discount_type: str
    discount_value: float
    min_order_amount: Optional[float] = None
    max_discount: Optional[float] = None
    valid_to: Optional[datetime] = None

    class Config:
        from_attributes = True


class ComplaintCreate(BaseModel):
    category: str  # driver_behavior, fare_issue, safety, technical, other
    subject: str
    description: str
    booking_id: Optional[int] = None


class ComplaintResponse(BaseModel):
    id: int
    category: str
    subject: str
    description: str
    status: str
    created_at: datetime
    resolved_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class ComplaintMessageCreate(BaseModel):
    body: str


class ComplaintMessageResponse(BaseModel):
    id: int
    complaint_id: int
    sender_role: str  # "customer" / "driver" / "admin"
    body: str
    created_at: datetime

    class Config:
        from_attributes = True


class GoldSubscribeRequest(BaseModel):
    months: int = 1  # 1, 3, 6, 12

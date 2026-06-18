from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class PromoCodeResponse(BaseModel):
    id: int
    code: str
    description: Optional[str] = None
    # BRD: RW-04 — category-tagged so the customer inbox can filter
    category: str = "all"  # all | rides | food | market
    discount_type: str
    discount_value: float
    min_order_amount: Optional[float] = None
    max_discount: Optional[float] = None
    valid_to: Optional[datetime] = None
    # BRD: RW-04 — populated when the customer has claimed this promo
    claimed_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class LoyaltyBalanceResponse(BaseModel):
    points: int
    value: float                # current rupee value of the balance
    earn_rupees_per_point: float
    value_per_point: float
    min_redeem_points: int
    max_redeem_order_pct: float


class LoyaltyTransactionResponse(BaseModel):
    id: int
    points: int                 # signed: + earn, − redeem, ± adjust
    kind: str                   # earn | redeem | adjust
    source_kind: Optional[str] = None
    source_id: Optional[int] = None
    description: Optional[str] = None
    balance_after: int
    created_at: datetime

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


class SurgeZoneBase(BaseModel):
    name: str
    coordinates: List[Dict[str, float]] # e.g. [{"lat": 6.9, "lng": 79.8}]
    flat_extra_charge: float
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    is_active: bool = True

class SurgeZoneCreate(SurgeZoneBase):
    pass

class SurgeZoneUpdate(BaseModel):
    name: Optional[str] = None
    coordinates: Optional[List[Dict[str, float]]] = None
    flat_extra_charge: Optional[float] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    is_active: Optional[bool] = None

class SurgeZoneResponse(SurgeZoneBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True

from typing import List, Optional

from pydantic import BaseModel, Field


class EventBookItem(BaseModel):
    tier_id: int
    quantity: int = Field(..., ge=1, le=20)


class EventBookRequest(BaseModel):
    items: List[EventBookItem] = Field(..., min_length=1)
    payment_method: str = Field("cash", pattern=r"^(wallet|cash)$")
    promo_code: Optional[str] = None

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class SavedAddressCreate(BaseModel):
    label: str
    address: str
    lat: float
    lng: float
    is_default: bool = False


class SavedAddressResponse(SavedAddressCreate):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class WalletTopUp(BaseModel):
    amount: float = Field(gt=0)
    description: Optional[str] = None


class WalletTransactionResponse(BaseModel):
    id: int
    amount: float
    type: str
    description: Optional[str] = None
    reference_id: Optional[str] = None
    balance_after: Optional[float] = None
    created_at: datetime

    class Config:
        from_attributes = True

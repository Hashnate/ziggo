from pydantic import BaseModel, Field
from typing import Optional
from decimal import Decimal

class QRResolveRequest(BaseModel):
    payload: str

class QRResolveResponse(BaseModel):
    merchant_type: str  # restaurant | market_vendor
    merchant_id: int
    name: str
    address: Optional[str] = None
    image_url: Optional[str] = None

class MerchantPayRequest(BaseModel):
    merchant_type: str  # restaurant | market_vendor
    merchant_id: int
    amount: Decimal = Field(gt=0)

class MerchantPayResponse(BaseModel):
    success: bool
    reference_id: str
    amount: Decimal
    remaining_balance: Decimal
    merchant_name: str

from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class CorporateAccountCreate(BaseModel):
    company_name: str
    billing_email: Optional[str] = None


class CorporateAccountResponse(BaseModel):
    id: int
    company_name: str
    billing_email: Optional[str] = None
    balance: float
    member_count: int = 0
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class CorporateMemberResponse(BaseModel):
    id: int
    user_id: int
    phone_number: str
    full_name: Optional[str] = None
    status: str
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class CorporateAddMember(BaseModel):
    phone_number: str


class CorporateTopup(BaseModel):
    amount: float


class CorporateProfileResponse(BaseModel):
    """Returned to the mobile app so the customer knows they can book as corporate."""
    company_name: str
    status: str  # active | suspended

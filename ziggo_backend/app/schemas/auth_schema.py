from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from ..models.user import UserRole


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    role: UserRole


class TokenData(BaseModel):
    phone_number: Optional[str] = None
    role: Optional[str] = None


class UserBase(BaseModel):
    phone_number: str
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None


class UserCreate(UserBase):
    role: UserRole


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    profile_photo: Optional[str] = None


class UserResponse(UserBase):
    id: int
    role: UserRole
    is_active: bool
    profile_photo: Optional[str] = None
    rating: Optional[float] = None
    total_rides: Optional[int] = None

    class Config:
        from_attributes = True


class OTPRequest(BaseModel):
    phone_number: str = Field(..., pattern=r"^\d{10}$", description="10-digit phone number")


class OTPVerify(BaseModel):
    phone_number: str = Field(..., pattern=r"^\d{10}$")
    otp: str
    role: UserRole
    # full_name is set only on signup (first-ever OTP for this phone) from
    # the Registration screen. Ignored for returning users.
    full_name: Optional[str] = Field(None, min_length=2, max_length=100)


class OTPResponse(BaseModel):
    message: str
    dev_otp: Optional[str] = None

from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from ..models.user import UserRole


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    role: UserRole
    # True only on first-ever OTP verification for this phone (signup). The app
    # uses it to route new users through the "Your details" profile-completion
    # screen before landing on home.
    is_new: bool = False


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
    phone_number: Optional[str] = None
    referred_by_code: Optional[str] = None


class ProfileCompleteness(BaseModel):
    """BRD: CD-34 — fed to the mobile completeness ring widget."""
    percent: int                  # 0..100
    completed: List[str]          # field keys the user has filled
    missing: List[str]            # field keys still needed


class UserResponse(UserBase):
    id: int
    role: UserRole
    is_active: bool
    profile_photo: Optional[str] = None
    rating: Optional[float] = None
    total_rides: Optional[int] = None
    referral_code: Optional[str] = None
    referred_by_user_id: Optional[int] = None
    # BRD: CD-34 — populated server-side from the user record
    profile_completeness: Optional[ProfileCompleteness] = None

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

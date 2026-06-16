from pydantic import BaseModel, EmailStr, Field
from typing import Optional


class DriverLocationUpdate(BaseModel):
    lat: float
    lng: float
    heading: Optional[float] = None


class DriverOnlineToggle(BaseModel):
    is_online: bool


class DriverRegisterRequest(BaseModel):
    """Submitted from the mobile app right after the driver's first OTP login."""
    full_name: str
    email: Optional[EmailStr] = None
    nic_number: str
    license_number: str
    vehicle_type: str  # bike | tuk | car | van | truck
    vehicle_number: str
    vehicle_model: str
    vehicle_color: str
    relative_name: Optional[str] = None
    relative_contact: Optional[str] = None
    relative_relationship: Optional[str] = None


class AdminDriverCreateRequest(BaseModel):
    """Admin creates a driver in one shot (creates User + Driver)."""
    phone_number: str = Field(..., pattern=r"^\d{10}$")
    full_name: str
    email: Optional[EmailStr] = None
    nic_number: str
    license_number: str
    vehicle_type: str
    vehicle_number: str
    vehicle_model: str
    vehicle_color: str
    auto_approve: bool = True


class DriverProfileResponse(BaseModel):
    id: int
    full_name: Optional[str] = None
    phone_number: Optional[str] = None
    profile_photo: Optional[str] = None
    vehicle_type: Optional[str] = None
    vehicle_number: Optional[str] = None
    vehicle_model: Optional[str] = None
    vehicle_color: Optional[str] = None
    nic_number: Optional[str] = None
    license_number: Optional[str] = None
    is_online: bool
    is_approved: bool
    profile_complete: bool
    status: Optional[str] = None
    rating: Optional[float] = None
    today_earnings: Optional[float] = None
    today_rides: Optional[int] = None
    total_earnings: Optional[float] = None
    acceptance_rate: Optional[float] = None
    relative_name: Optional[str] = None
    relative_contact: Optional[str] = None
    relative_relationship: Optional[str] = None
    billing_proof_url: Optional[str] = None
    paid_payouts: Optional[float] = 0.0
    pending_payout: Optional[float] = 0.0
    peak_is_active: Optional[bool] = False
    peak_start_hour: Optional[int] = None
    peak_end_hour: Optional[int] = None
    peak_extra_amount: Optional[float] = 0.0
    is_currently_peak: Optional[bool] = False

    bank_name: Optional[str] = None
    account_holder_name: Optional[str] = None
    account_number: Optional[str] = None
    branch_name: Optional[str] = None

    class Config:
        from_attributes = True

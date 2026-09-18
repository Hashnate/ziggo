from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional


class Settings(BaseSettings):
    PROJECT_NAME: str = "Ziggo"
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = "change-me"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 365 * 10  # 10 years

    DATABASE_URL: str
    SYNC_DATABASE_URL: str

    DEV_MODE: bool = True

    # Stubbed third-party (filled in later)
    FIREBASE_CREDENTIALS_PATH: Optional[str] = None
    TWILIO_ACCOUNT_SID: Optional[str] = None
    TWILIO_AUTH_TOKEN: Optional[str] = None
    TWILIO_PHONE_NUMBER: Optional[str] = None
    STRIPE_API_KEY: Optional[str] = None
    STRIPE_WEBHOOK_SECRET: Optional[str] = None
    GOOGLE_MAPS_API_KEY: Optional[str] = None

    # Notify.lk — Sri Lankan SMS gateway. When any of these are empty the
    # service no-ops and OTP just lands in the uvicorn console (DEV_MODE flow).
    NOTIFY_LK_USER_ID: Optional[str] = None
    NOTIFY_LK_API_KEY: Optional[str] = None
    NOTIFY_LK_SENDER_ID: Optional[str] = None

    # PayHere — Sri Lankan payment gateway. When MERCHANT_ID is empty the
    # /payments/payhere/* endpoints return 503 and wallet top-ups fall back
    # to the existing mock direct-credit flow.
    PAYHERE_MERCHANT_ID: Optional[str] = None
    PAYHERE_MERCHANT_SECRET: Optional[str] = None
    PAYHERE_APP_ID: Optional[str] = None
    PAYHERE_APP_SECRET: Optional[str] = None
    PAYHERE_MODE: Optional[str] = "sandbox"  # "sandbox" or "live"
    PAYHERE_NOTIFY_URL: Optional[str] = None

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True, extra="ignore")


settings = Settings()

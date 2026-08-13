from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException, File, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from ...database import get_db
from ...models import Customer, User, UserRole, SavedAddress, WalletTransaction, Notification, WalletTopupRequest
from ...schemas import (
    SavedAddressCreate,
    SavedAddressResponse,
    WalletTopUp,
    WalletTransactionResponse,
    WalletTopupRequestCreate,
    WalletTopupRequestResponse,
    UserUpdate,
    UserResponse,
)
from ...services.auth_service import require_role

router = APIRouter()


async def _get_customer(db: AsyncSession, user: User) -> Customer:
    q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = q.scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    return c


@router.patch("/profile", response_model=UserResponse)
async def update_profile(
    body: UserUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    updates = body.model_dump(exclude_unset=True)
    if "phone_number" in updates and updates["phone_number"]:
        new_phone = updates["phone_number"].strip()
        if new_phone != user.phone_number:
            clash = (await db.execute(select(User).where(User.phone_number == new_phone))).scalars().first()
            if clash:
                raise HTTPException(status_code=409, detail="Phone number already in use by another account")
            user.phone_number = new_phone

    if "referred_by_code" in updates and updates["referred_by_code"]:
        code = updates["referred_by_code"].strip().upper()
        if user.referred_by_user_id is not None:
            raise HTTPException(status_code=400, detail="Referral code already applied")

        referrer_q = await db.execute(select(User).where(User.referral_code == code))
        referrer = referrer_q.scalars().first()
        if not referrer:
            raise HTTPException(status_code=400, detail="Invalid referral code")

        if referrer.id == user.id:
            raise HTTPException(status_code=400, detail="You cannot refer yourself")

        user.referred_by_user_id = referrer.id

        from ...models import ReferralBonus, ReferralKind, ReferralStatus, SystemSettings
        ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
        ss = ss_q.scalars().first()
        ref_amt = ss.referral_referrer_amount if (ss and ss.referral_referrer_amount is not None) else Decimal("300.00")
        refd_amt = ss.referral_referred_amount if (ss and ss.referral_referred_amount is not None) else Decimal("300.00")

        bonus = ReferralBonus(
            referrer_user_id=referrer.id,
            referred_user_id=user.id,
            kind=ReferralKind.credit,
            referrer_amount=ref_amt,
            referred_amount=refd_amt,
            status=ReferralStatus.pending,
            trigger_description="Referral bonus — friend completed first order"
        )
        db.add(bonus)

    for field, val in updates.items():
        if field not in ("phone_number", "referred_by_code"):
            setattr(user, field, val)

    await db.commit()
    await db.refresh(user)
    return user


import os
import secrets

def _find_admin_panel_dir() -> str:
    curr = os.path.abspath(__file__)
    for _ in range(10):
        curr = os.path.dirname(curr)
        candidate = os.path.join(curr, "ziggo_admin_panel")
        if os.path.isdir(candidate):
            return candidate
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))),
        "ziggo_admin_panel"
    )

_ADMIN_PANEL_DIR = _find_admin_panel_dir()
_PROFILE_PHOTO_DIR = os.path.join(_ADMIN_PANEL_DIR, "static", "uploads", "customers")
os.makedirs(_PROFILE_PHOTO_DIR, exist_ok=True)


async def _save_profile_photo(asset: UploadFile) -> str:
    ext = os.path.splitext(asset.filename or "")[1].lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp", ".avif"}:
        raise HTTPException(status_code=400, detail="Photo must be JPG, PNG, WEBP, or AVIF")
    data = await asset.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(data) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Photo must be under 5 MB")
    from ...utils.image import process_image_upload
    data = process_image_upload(data, is_profile=True)
    fname = f"profile_{secrets.token_hex(8)}{ext}"
    fpath = os.path.join(_PROFILE_PHOTO_DIR, fname)
    with open(fpath, "wb") as f:
        f.write(data)
    return f"/static/uploads/customers/{fname}"



@router.post("/profile-photo")
async def upload_profile_photo(
    photo: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Customer uploads their profile photo."""
    url = await _save_profile_photo(photo)
    user.profile_photo = url
    await db.commit()
    await db.refresh(user)
    return {"ok": True, "profile_photo": url}


# BRD: CD-32 — Account deletion. We soft-delete: PII is scrubbed but the user
# row stays so historical bookings/payments still have a foreign key target.
# Phone number is randomized to free it up for future re-registration.
@router.delete("/me", status_code=200)
async def delete_my_account(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    import secrets as _secrets

    # Tombstone the phone number so the row is unique-safe even after the user
    # signs back up with their real number on a new account. Stays under the
    # phone_number column's 20-char limit.
    user.phone_number = f"del-{_secrets.token_hex(6)}"  # 4 + 12 = 16 chars
    user.full_name = None
    user.email = None
    user.profile_photo = None
    user.is_active = False

    # Clear the customer profile's wallet + invalidate notification tokens.
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cq.scalars().first()
    if customer:
        customer.notification_token = None
        # Wallet balance + loyalty points stay on the row for auditing but are
        # detached from any usable identity above.

    await db.commit()
    return {
        "ok": True,
        "message": (
            "Your Ziggo account has been deleted. "
            "Personal data (name, email, photo, phone, push tokens) has been "
            "erased. Historical trip + payment records are retained for legal "
            "and accounting compliance (Sri Lanka Inland Revenue requires 6 "
            "years of transaction history). Wallet balance, if any, was "
            "forfeit per the Terms of Service."
        ),
    }


@router.get("/addresses", response_model=List[SavedAddressResponse])
async def list_addresses(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    q = await db.execute(
        select(SavedAddress).where(SavedAddress.user_id == user.id).order_by(SavedAddress.is_default.desc(), SavedAddress.id.desc())
    )
    return q.scalars().all()


@router.post("/addresses", response_model=SavedAddressResponse, status_code=201)
async def add_address(
    body: SavedAddressCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    if body.is_default:
        await db.execute(
            update(SavedAddress).where(SavedAddress.user_id == user.id).values(is_default=False)
        )
    addr = SavedAddress(user_id=user.id, **body.model_dump())
    db.add(addr)
    await db.commit()
    await db.refresh(addr)
    return addr


@router.delete("/addresses/{address_id}", status_code=204)
async def delete_address(
    address_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    q = await db.execute(
        select(SavedAddress).where(SavedAddress.id == address_id, SavedAddress.user_id == user.id)
    )
    addr = q.scalars().first()
    if not addr:
        raise HTTPException(status_code=404, detail="Address not found")
    await db.delete(addr)
    await db.commit()


@router.get("/wallet")
async def wallet_balance(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    c = await _get_customer(db, user)
    return {"balance": float(c.wallet_balance or 0), "currency": "LKR"}


@router.post("/wallet/topup", response_model=WalletTransactionResponse)
async def wallet_topup(
    body: WalletTopUp,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Mock top-up (no real payment gateway). Adds amount to wallet immediately."""
    c = await _get_customer(db, user)
    c.wallet_balance = (c.wallet_balance or Decimal(0)) + Decimal(str(body.amount))
    txn = WalletTransaction(
        user_id=user.id,
        amount=Decimal(str(body.amount)),
        type="credit",
        description=body.description or "Wallet top-up",
        reference_id="TOPUP",
        balance_after=c.wallet_balance,
    )
    db.add(txn)
    await db.commit()
    await db.refresh(txn)
    return txn


@router.post("/wallet/topup-request", response_model=WalletTopupRequestResponse)
async def create_wallet_topup_request(
    body: WalletTopupRequestCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    req = WalletTopupRequest(
        user_id=user.id,
        amount=Decimal(str(body.amount)),
        note=body.note,
        status="pending"
    )
    db.add(req)
    await db.commit()
    await db.refresh(req)
    return req


@router.get("/wallet/topup-requests", response_model=List[WalletTopupRequestResponse])
async def list_wallet_topup_requests(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    q = await db.execute(
        select(WalletTopupRequest)
        .where(WalletTopupRequest.user_id == user.id)
        .order_by(WalletTopupRequest.id.desc())
        .limit(100)
    )
    return q.scalars().all()


@router.get("/wallet/transactions", response_model=List[WalletTransactionResponse])
async def wallet_transactions(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    q = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.user_id == user.id)
        .order_by(WalletTransaction.id.desc())
        .limit(100)
    )
    return q.scalars().all()


@router.get("/notifications")
async def list_notifications(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    q = await db.execute(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.id.desc())
        .limit(50)
    )
    rows = q.scalars().all()
    return [
        {
            "id": n.id,
            "title": n.title,
            "body": n.body,
            "type": n.type,
            "is_read": n.is_read,
            "created_at": n.created_at,
        }
        for n in rows
    ]


@router.post("/notifications/{nid}/read")
async def mark_notification_read(
    nid: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    q = await db.execute(
        select(Notification).where(Notification.id == nid, Notification.user_id == user.id)
    )
    n = q.scalars().first()
    if not n:
        raise HTTPException(status_code=404, detail="Not found")
    n.is_read = True
    await db.commit()
    return {"ok": True}


@router.get("/referrals")
async def get_referral_summary(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    from ...models import ReferralBonus, ReferralStatus
    from sqlalchemy import select

    if not user.referral_code:
        from ...models.user import generate_referral_code
        user.referral_code = generate_referral_code()
        db.add(user)
        await db.commit()
        await db.refresh(user)

    q = await db.execute(
        select(ReferralBonus)
        .where(ReferralBonus.referrer_user_id == user.id)
        .order_by(ReferralBonus.created_at.desc())
    )
    bonuses = q.scalars().all()

    total_referred = len(bonuses)
    earned_amount = sum((b.referrer_amount for b in bonuses if b.status == ReferralStatus.completed), Decimal("0.00"))
    pending_amount = sum((b.referrer_amount for b in bonuses if b.status == ReferralStatus.pending), Decimal("0.00"))

    friends = []
    for b in bonuses:
        referred_user = await db.get(User, b.referred_user_id)
        name = referred_user.full_name or "New User"
        phone = referred_user.phone_number
        if phone and len(phone) >= 7:
            phone_masked = phone[:3] + "****" + phone[-3:]
        else:
            phone_masked = phone or ""

        friends.append({
            "id": b.id,
            "name": name,
            "phone": phone_masked,
            "status": b.status.value,
            "amount": float(b.referrer_amount),
            "created_at": b.created_at,
            "paid_at": b.paid_at,
        })

    from ...models import SystemSettings
    ss_q = await db.execute(select(SystemSettings).where(SystemSettings.id == 1))
    ss = ss_q.scalars().first()
    ref_amt_config = float(ss.referral_referred_amount) if (ss and ss.referral_referred_amount is not None) else 300.0

    return {
        "referral_code": user.referral_code,
        "total_referred": total_referred,
        "earned_amount": float(earned_amount),
        "pending_amount": float(pending_amount),
        "referral_amount": ref_amt_config,
        "friends": friends
    }

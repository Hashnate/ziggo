from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from ...database import get_db
from ...models import Customer, User, UserRole, SavedAddress, WalletTransaction, Notification
from ...schemas import (
    SavedAddressCreate,
    SavedAddressResponse,
    WalletTopUp,
    WalletTransactionResponse,
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
    for field, val in body.model_dump(exclude_unset=True).items():
        setattr(user, field, val)
    await db.commit()
    await db.refresh(user)
    return user


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

"""Public-ish endpoints: promos, complaints, Gold subscription."""
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ...database import get_db
from ...models import (
    PromoCode,
    Complaint,
    Customer,
    FlashWeightTier,
    User,
    WalletTransaction,
)
from ...schemas import (
    PromoCodeResponse,
    ComplaintCreate,
    ComplaintResponse,
    GoldSubscribeRequest,
)
from ...services.auth_service import get_current_user, require_role

router = APIRouter()


# ---------- Flash pricing tiers (public — used by the customer flash screen) ----------
@router.get("/flash/pricing")
async def list_flash_tiers(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    q = await db.execute(
        select(FlashWeightTier)
        .where(FlashWeightTier.is_active == True)  # noqa: E712
        .order_by(FlashWeightTier.display_order, FlashWeightTier.id)
    )
    return [
        {
            "id": t.id,
            "label": t.label,
            "min_weight_kg": float(t.min_weight_kg or 0),
            "max_weight_kg": float(t.max_weight_kg) if t.max_weight_kg is not None else None,
            "representative_weight_kg": float(t.representative_weight_kg or 0),
            "surcharge": float(t.surcharge or 0),
            "icon": t.icon or "inventory_2",
            "display_order": t.display_order,
        }
        for t in q.scalars().all()
    ]


# ---------- Promos ----------
@router.get("/promos", response_model=List[PromoCodeResponse])
async def list_active_promos(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)
    q = await db.execute(
        select(PromoCode).where(
            PromoCode.is_active == True,  # noqa: E712
            (PromoCode.valid_to == None) | (PromoCode.valid_to >= now),  # noqa: E711
        )
        .order_by(PromoCode.id.desc())
    )
    return q.scalars().all()


# ---------- Complaints ----------
@router.post("/complaints", response_model=ComplaintResponse, status_code=201)
async def create_complaint(
    body: ComplaintCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    c = Complaint(
        user_id=user.id,
        booking_id=body.booking_id,
        category=body.category,
        subject=body.subject,
        description=body.description,
        status="pending",
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return c


@router.get("/complaints", response_model=List[ComplaintResponse])
async def list_my_complaints(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = await db.execute(
        select(Complaint)
        .where(Complaint.user_id == user.id)
        .order_by(Complaint.id.desc())
    )
    return q.scalars().all()


# ---------- Gold subscription ----------
GOLD_PRICE_PER_MONTH = 500  # LKR


@router.post("/gold/subscribe")
async def subscribe_gold(
    body: GoldSubscribeRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    if body.months not in {1, 3, 6, 12}:
        raise HTTPException(status_code=400, detail="months must be 1, 3, 6, or 12")

    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cust_q.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    cost = GOLD_PRICE_PER_MONTH * body.months
    if (customer.wallet_balance or Decimal(0)) < Decimal(str(cost)):
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient wallet balance. Need Rs.{cost}, have Rs.{customer.wallet_balance or 0}",
        )

    # Debit wallet
    customer.wallet_balance = (customer.wallet_balance or Decimal(0)) - Decimal(str(cost))
    db.add(
        WalletTransaction(
            user_id=user.id,
            amount=Decimal(str(cost)),
            type="debit",
            description=f"Ziggo Gold - {body.months} month(s)",
            reference_id="GOLD",
            balance_after=customer.wallet_balance,
        )
    )

    # Extend Gold membership
    now = datetime.now(timezone.utc)
    base = customer.gold_expires_at if (customer.gold_expires_at and customer.gold_expires_at > now) else now
    customer.gold_expires_at = base + timedelta(days=30 * body.months)
    customer.gold_member = True

    await db.commit()
    return {
        "ok": True,
        "gold_member": True,
        "expires_at": customer.gold_expires_at.isoformat(),
        "wallet_balance": float(customer.wallet_balance),
        "months": body.months,
        "cost": cost,
    }


@router.get("/gold/status")
async def gold_status(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    cust_q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = cust_q.scalars().first()
    if not c:
        raise HTTPException(status_code=404, detail="Customer profile not found")
    now = datetime.now(timezone.utc)
    active = bool(c.gold_member and c.gold_expires_at and c.gold_expires_at > now)
    return {
        "gold_member": active,
        "expires_at": c.gold_expires_at.isoformat() if c.gold_expires_at else None,
        "price_per_month": GOLD_PRICE_PER_MONTH,
    }

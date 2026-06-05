"""BRD: PY-05 / AD-12 / BE-19 — Corporate billing profile APIs.

Customer-facing:
  GET  /corporate/profile   — returns the caller's corporate affiliation (if any)

Admin-facing:
  POST /admin/corporate             — create a new corporate account
  GET  /admin/corporate             — list all corporate accounts
  GET  /admin/corporate/{id}        — detail view with members
  POST /admin/corporate/{id}/members — add a user by phone number
  POST /admin/corporate/{id}/topup   — add prepaid credit
"""
from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ...database import get_db
from ...models import CorporateAccount, CorporateMember, User, UserRole
from ...schemas import (
    CorporateAccountCreate,
    CorporateAccountResponse,
    CorporateAddMember,
    CorporateMemberResponse,
    CorporateProfileResponse,
    CorporateTopup,
)
from ...services.auth_service import get_current_user

router = APIRouter()


# ────────────────── Customer endpoint ──────────────────


@router.get("/corporate/profile", response_model=CorporateProfileResponse)
async def my_corporate_profile(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Return the caller's corporate affiliation, or 404 if not linked."""
    q = await db.execute(
        select(CorporateMember)
        .options(selectinload(CorporateMember.corporate))
        .where(CorporateMember.user_id == user.id)
    )
    member = q.scalars().first()
    if not member:
        raise HTTPException(status_code=404, detail="Not linked to a corporate account")
    return CorporateProfileResponse(
        company_name=member.corporate.company_name,
        status=member.status,
    )


# ────────────────── Admin endpoints ──────────────────


def _require_admin(user: User) -> None:
    if user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin role required")


@router.post("/admin/corporate", response_model=CorporateAccountResponse, status_code=201)
async def create_corporate_account(
    body: CorporateAccountCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _require_admin(user)
    acct = CorporateAccount(
        company_name=body.company_name,
        billing_email=body.billing_email,
        balance=Decimal("0"),
    )
    db.add(acct)
    await db.commit()
    await db.refresh(acct)
    return CorporateAccountResponse(
        id=acct.id,
        company_name=acct.company_name,
        billing_email=acct.billing_email,
        balance=float(acct.balance or 0),
        member_count=0,
        created_at=acct.created_at,
    )


@router.get("/admin/corporate", response_model=List[CorporateAccountResponse])
async def list_corporate_accounts(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _require_admin(user)
    q = await db.execute(
        select(CorporateAccount).order_by(CorporateAccount.id.desc())
    )
    accounts = q.scalars().all()
    results = []
    for a in accounts:
        mq = await db.execute(
            select(func.count()).select_from(CorporateMember).where(CorporateMember.corporate_id == a.id)
        )
        count = mq.scalar() or 0
        results.append(CorporateAccountResponse(
            id=a.id,
            company_name=a.company_name,
            billing_email=a.billing_email,
            balance=float(a.balance or 0),
            member_count=count,
            created_at=a.created_at,
        ))
    return results


@router.get("/admin/corporate/{account_id}", response_model=CorporateAccountResponse)
async def get_corporate_detail(
    account_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _require_admin(user)
    q = await db.execute(
        select(CorporateAccount).where(CorporateAccount.id == account_id)
    )
    acct = q.scalars().first()
    if not acct:
        raise HTTPException(status_code=404, detail="Corporate account not found")
    mq = await db.execute(
        select(func.count()).select_from(CorporateMember).where(CorporateMember.corporate_id == acct.id)
    )
    count = mq.scalar() or 0
    return CorporateAccountResponse(
        id=acct.id,
        company_name=acct.company_name,
        billing_email=acct.billing_email,
        balance=float(acct.balance or 0),
        member_count=count,
        created_at=acct.created_at,
    )


@router.get("/admin/corporate/{account_id}/members", response_model=List[CorporateMemberResponse])
async def list_corporate_members(
    account_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _require_admin(user)
    q = await db.execute(
        select(CorporateMember)
        .options(selectinload(CorporateMember.user))
        .where(CorporateMember.corporate_id == account_id)
    )
    members = q.scalars().all()
    return [
        CorporateMemberResponse(
            id=m.id,
            user_id=m.user_id,
            phone_number=m.user.phone_number if m.user else "",
            full_name=m.user.full_name if m.user else None,
            status=m.status,
            created_at=m.created_at,
        )
        for m in members
    ]


@router.post("/admin/corporate/{account_id}/members", response_model=CorporateMemberResponse, status_code=201)
async def add_corporate_member(
    account_id: int,
    body: CorporateAddMember,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _require_admin(user)
    # Verify corporate account exists
    aq = await db.execute(select(CorporateAccount).where(CorporateAccount.id == account_id))
    if not aq.scalars().first():
        raise HTTPException(status_code=404, detail="Corporate account not found")

    # Look up the user by phone number
    uq = await db.execute(select(User).where(User.phone_number == body.phone_number))
    target = uq.scalars().first()
    if not target:
        raise HTTPException(status_code=404, detail="No user found with this phone number")

    # Check if already a member of any corporate account
    eq = await db.execute(select(CorporateMember).where(CorporateMember.user_id == target.id))
    if eq.scalars().first():
        raise HTTPException(status_code=409, detail="User is already linked to a corporate account")

    member = CorporateMember(
        corporate_id=account_id,
        user_id=target.id,
        status="active",
    )
    db.add(member)
    await db.commit()
    await db.refresh(member)
    return CorporateMemberResponse(
        id=member.id,
        user_id=target.id,
        phone_number=target.phone_number,
        full_name=target.full_name,
        status=member.status,
        created_at=member.created_at,
    )


@router.post("/admin/corporate/{account_id}/topup", response_model=CorporateAccountResponse)
async def topup_corporate(
    account_id: int,
    body: CorporateTopup,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    _require_admin(user)
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="Amount must be positive")
    q = await db.execute(select(CorporateAccount).where(CorporateAccount.id == account_id))
    acct = q.scalars().first()
    if not acct:
        raise HTTPException(status_code=404, detail="Corporate account not found")
    acct.balance = Decimal(str(acct.balance or 0)) + Decimal(str(body.amount))
    await db.commit()
    await db.refresh(acct)
    mq = await db.execute(
        select(func.count()).select_from(CorporateMember).where(CorporateMember.corporate_id == acct.id)
    )
    count = mq.scalar() or 0
    return CorporateAccountResponse(
        id=acct.id,
        company_name=acct.company_name,
        billing_email=acct.billing_email,
        balance=float(acct.balance or 0),
        member_count=count,
        created_at=acct.created_at,
    )

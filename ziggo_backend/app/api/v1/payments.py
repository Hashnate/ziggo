"""Payment endpoints — PayHere (Sri Lanka card + wallet gateway).

Endpoints:
  POST /payments/payhere/checkout    — start a wallet top-up; returns hosted
                                       checkout URL + signed form fields
  POST /payments/payhere/notify      — server-to-server webhook from PayHere
                                       on payment completion
  GET  /payments/payhere/status/{id} — client polls this to detect success
                                       (the WS push is the primary channel,
                                       this is the fallback)

All endpoints 503 when PayHere isn't configured so the mobile app can
gracefully fall back to the existing mock /customer/wallet/topup path.
"""
from decimal import Decimal
import secrets

from fastapi import APIRouter, Depends, Form, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...database import get_db
from ...models import Customer, User, WalletTransaction
from ...schemas import WalletTransactionResponse
from ...services import payhere_service
from ...services.auth_service import require_role
from ...services.ws_manager import manager

router = APIRouter()


def _ensure_enabled():
    if not payhere_service.is_enabled():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PayHere is not configured on this server",
        )


@router.post("/payhere/checkout")
async def payhere_checkout(
    body: dict,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Start a wallet top-up. Body: {amount: number, return_url?, cancel_url?}.

    Returns:
      { order_id, url, fields }  ← post `fields` to `url` from a WebView.
    """
    _ensure_enabled()
    try:
        amount = Decimal(str(body.get("amount", 0)))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid amount")
    if amount < Decimal("100"):
        raise HTTPException(status_code=400, detail="Minimum top-up is LKR 100")

    order_id = "WT" + secrets.token_hex(6).upper()  # WT = wallet top-up

    full_name = (user.full_name or "Customer").strip()
    first, _, last = full_name.partition(" ")
    payload = payhere_service.build_checkout_payload(
        order_id=order_id,
        amount=amount,
        items="Ziggo wallet top-up",
        first_name=first or "Customer",
        last_name=last or "-",
        email=user.email or f"{user.phone_number}@ziggo.local",
        phone=user.phone_number,
        return_url=body.get("return_url") or "",
        cancel_url=body.get("cancel_url") or "",
    )
    return {"order_id": order_id, **payload}


@router.post("/payhere/notify")
async def payhere_notify(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Server-to-server webhook from PayHere. Public (no auth).

    PayHere POSTs application/x-www-form-urlencoded. We verify the md5
    signature, then on a success status credit the wallet + push WS.
    """
    if not payhere_service.is_enabled():
        # Don't leak that PayHere isn't configured — just say OK so PayHere
        # doesn't retry forever if someone misroutes a webhook.
        return {"ok": True, "note": "ignored"}

    form = await request.form()
    merchant_id = str(form.get("merchant_id", ""))
    order_id = str(form.get("order_id", ""))
    payhere_amount = str(form.get("payhere_amount", ""))
    payhere_currency = str(form.get("payhere_currency", "LKR"))
    status_code = str(form.get("status_code", ""))
    md5sig = str(form.get("md5sig", ""))
    custom1 = str(form.get("custom_1", ""))  # we stash user_id here in future

    ok = payhere_service.verify_notification(
        merchant_id=merchant_id,
        order_id=order_id,
        payhere_amount=payhere_amount,
        payhere_currency=payhere_currency,
        status_code=status_code,
        md5sig=md5sig,
    )
    if not ok:
        print(f"[payhere] notify rejected — bad signature for order {order_id}")
        raise HTTPException(status_code=400, detail="Invalid signature")

    label = payhere_service.status_label(status_code)
    print(f"[payhere] notify order={order_id} status={label} amount={payhere_amount}")

    if status_code != payhere_service.STATUS_SUCCESS:
        return {"ok": True, "status": label}

    # Idempotency — if we already credited this order, skip.
    existing = await db.execute(
        select(WalletTransaction).where(WalletTransaction.reference_id == order_id)
    )
    if existing.scalars().first() is not None:
        print(f"[payhere] order {order_id} already credited, skipping")
        return {"ok": True, "status": "already_credited"}

    # Look up the customer this top-up belongs to. The order_id convention
    # 'WT<hex>' doesn't embed user_id; we derive it from `custom_1` if set,
    # otherwise fall back to email lookup. The mobile app populates custom_1
    # with user.id when starting checkout.
    cust_user_id = None
    try:
        cust_user_id = int(custom1) if custom1 else None
    except ValueError:
        cust_user_id = None
    if not cust_user_id:
        email = str(form.get("email", ""))
        if email:
            uq = await db.execute(select(User).where(User.email == email))
            u = uq.scalars().first()
            if u:
                cust_user_id = u.id
    if not cust_user_id:
        print(f"[payhere] couldn't resolve user for order {order_id}")
        return {"ok": True, "status": "unmatched"}

    cq = await db.execute(select(Customer).where(Customer.user_id == cust_user_id))
    cust = cq.scalars().first()
    if cust is None:
        print(f"[payhere] no customer profile for user {cust_user_id}")
        return {"ok": True, "status": "no_customer"}

    amount = Decimal(payhere_amount)
    cust.wallet_balance = (cust.wallet_balance or Decimal(0)) + amount
    txn = WalletTransaction(
        user_id=cust_user_id,
        amount=amount,
        type="credit",
        description=f"PayHere top-up ({order_id})",
        reference_id=order_id,
        balance_after=cust.wallet_balance,
    )
    db.add(txn)
    await db.commit()

    # Notify the app via WS (which also piggybacks an FCM if configured)
    await manager.send(
        cust_user_id,
        "wallet_credited",
        {"order_id": order_id, "amount": float(amount), "balance": float(cust.wallet_balance)},
    )

    return {"ok": True, "status": "credited"}


@router.get("/payhere/status/{order_id}", response_model=WalletTransactionResponse)
async def payhere_status(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Client polls this after the WebView closes. If the credit landed,
    returns the wallet transaction; otherwise 404 (still pending or failed)."""
    _ensure_enabled()
    q = await db.execute(
        select(WalletTransaction)
        .where(WalletTransaction.reference_id == order_id)
        .where(WalletTransaction.user_id == user.id)
    )
    txn = q.scalars().first()
    if not txn:
        raise HTTPException(status_code=404, detail="Top-up not yet completed")
    return txn


@router.get("/payhere/config")
async def payhere_config():
    """Lightweight probe so the Flutter app can decide which top-up flow to
    show (real gateway vs mock). No auth required — returns no secrets."""
    return {
        "enabled": payhere_service.is_enabled(),
        "mode": settings_mode(),
    }


def settings_mode() -> str:
    from ...config import settings
    return (settings.PAYHERE_MODE or "sandbox").lower()

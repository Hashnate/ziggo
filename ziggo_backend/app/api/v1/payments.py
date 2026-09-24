"""Payment endpoints — iPay (Sri Lanka card + wallet gateway).

Endpoints:
  POST /payments/ipay/checkout    — start a wallet top-up; returns hosted
                                    checkout URL + signed form fields
  POST /payments/ipay/notify      — server-to-server webhook from iPay
                                    on payment completion
  GET  /payments/ipay/status/{id} — client polls this to detect success
  GET  /payments/ipay/config      — probe gateway status & mode
  POST /payments/ipay/preapprove  — start card registration/tokenization session

Aliases are maintained under /payments/payhere/* for transitional compatibility.
"""
from decimal import Decimal
import json
import secrets

from fastapi import APIRouter, Depends, Form, HTTPException, Request, status
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ...database import get_db
from ...models import Customer, User, WalletTransaction, CustomerCard, Restaurant, MarketVendor
from ...schemas import (
    WalletTransactionResponse,
    QRResolveRequest,
    QRResolveResponse,
    MerchantPayRequest,
    MerchantPayResponse,
)
from ...services import ipay_service, payhere_service
from ...services.auth_service import require_role
from ...services.ws_manager import manager

from urllib.parse import urlparse, parse_qs

router = APIRouter()


def _ensure_enabled():
    if not ipay_service.is_enabled():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="iPay payment gateway is not configured on this server",
        )


@router.post("/ipay/checkout")
@router.post("/payhere/checkout")
async def ipay_checkout(
    body: dict,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "restaurant_owner", "market_owner")),
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
    payload = ipay_service.build_checkout_payload(
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


@router.post("/ipay/notify")
@router.post("/payhere/notify")
async def ipay_notify(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """Server-to-server webhook from iPay. Public (no auth).

    Accepts application/x-www-form-urlencoded or application/json.
    Verifies cryptographic signature, credits wallet / registers card, and notifies client via WS.
    """
    if not ipay_service.is_enabled():
        return {"ok": True, "note": "ignored"}

    data: dict = {}
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            data = await request.json()
        except Exception:
            data = {}
    else:
        form = await request.form()
        data = dict(form)

    merchant_id = str(data.get("merchant_id", ""))
    order_id = str(data.get("order_id", ""))
    amount_str = str(data.get("ipay_amount") or data.get("payhere_amount") or data.get("amount", ""))
    currency = str(data.get("ipay_currency") or data.get("payhere_currency") or data.get("currency", "LKR"))
    status_code = str(data.get("status_code") or data.get("status", ""))
    signature = str(data.get("signature") or data.get("md5sig") or data.get("hash", ""))
    custom1 = str(data.get("custom_1") or data.get("user_id", ""))

    ok = ipay_service.verify_notification(
        merchant_id_val=merchant_id,
        order_id=order_id,
        ipay_amount=amount_str,
        ipay_currency=currency,
        status_code=status_code,
        signature=signature,
    )
    if not ok:
        print(f"[ipay] notify rejected — bad signature for order {order_id}")
        raise HTTPException(status_code=400, detail="Invalid signature")

    label = ipay_service.status_label(status_code)
    print(f"[ipay] notify order={order_id} status={label} amount={amount_str}")

    if label != "success":
        return {"ok": True, "status": label}

    if order_id.startswith("PA"):
        cust_user_id = None
        try:
            cust_user_id = int(custom1) if custom1 else None
        except ValueError:
            cust_user_id = None
        if not cust_user_id:
            email = str(data.get("email", ""))
            if email:
                uq = await db.execute(select(User).where(User.email == email))
                u = uq.scalars().first()
                if u:
                    cust_user_id = u.id
        if not cust_user_id:
            print(f"[ipay] preapprove couldn't resolve user for order {order_id}")
            return {"ok": True, "status": "unmatched"}

        cq = await db.execute(select(Customer).where(Customer.user_id == cust_user_id))
        cust = cq.scalars().first()
        if cust is None:
            print(f"[ipay] preapprove no customer profile for user {cust_user_id}")
            return {"ok": True, "status": "no_customer"}

        customer_token = str(data.get("customer_token") or data.get("token", ""))
        card_no = str(data.get("card_no") or data.get("masked_card_no", ""))
        card_expiry = str(data.get("card_expiry", ""))
        card_type = str(data.get("method") or data.get("card_type", "CARD"))
        card_holder_name = str(data.get("card_holder_name", ""))

        if not customer_token:
            print(f"[ipay] preapprove missing customer_token for order {order_id}")
            return {"ok": True, "status": "missing_token"}

        existing_card = await db.execute(
            select(CustomerCard).where(CustomerCard.customer_token == customer_token)
        )
        if existing_card.scalars().first() is not None:
            return {"ok": True, "status": "already_added"}

        has_cards = await db.execute(
            select(CustomerCard).where(CustomerCard.customer_id == cust.id)
        )
        is_first = has_cards.scalars().first() is None

        card = CustomerCard(
            customer_id=cust.id,
            card_no=card_no,
            card_expiry=card_expiry,
            card_holder_name=card_holder_name or None,
            card_type=card_type,
            customer_token=customer_token,
            is_default=is_first,
        )
        db.add(card)
        await db.commit()

        await manager.send(
            cust_user_id,
            "card_added",
            {
                "id": card.id,
                "card_no": card_no,
                "card_type": card_type,
                "is_default": card.is_default,
            },
        )
        return {"ok": True, "status": "card_added"}

    # Idempotency — if we already credited this order, skip.
    existing = await db.execute(
        select(WalletTransaction).where(WalletTransaction.reference_id == order_id)
    )
    if existing.scalars().first() is not None:
        print(f"[ipay] order {order_id} already credited, skipping")
        return {"ok": True, "status": "already_credited"}

    # Look up the customer this top-up belongs to.
    cust_user_id = None
    try:
        cust_user_id = int(custom1) if custom1 else None
    except ValueError:
        cust_user_id = None
    if not cust_user_id:
        email = str(data.get("email", ""))
        if email:
            uq = await db.execute(select(User).where(User.email == email))
            u = uq.scalars().first()
            if u:
                cust_user_id = u.id
    if not cust_user_id:
        print(f"[ipay] couldn't resolve user for order {order_id}")
        return {"ok": True, "status": "unmatched"}

    cq = await db.execute(select(Customer).where(Customer.user_id == cust_user_id))
    cust = cq.scalars().first()
    if cust is None:
        print(f"[ipay] no customer profile for user {cust_user_id}")
        return {"ok": True, "status": "no_customer"}

    amount = Decimal(amount_str)
    cust.wallet_balance = (cust.wallet_balance or Decimal(0)) + amount
    txn = WalletTransaction(
        user_id=cust_user_id,
        amount=amount,
        type="credit",
        description=f"iPay top-up ({order_id})",
        reference_id=order_id,
        balance_after=cust.wallet_balance,
    )
    db.add(txn)
    await db.commit()

    # Notify the app via WS
    await manager.send(
        cust_user_id,
        "wallet_credited",
        {"order_id": order_id, "amount": float(amount), "balance": float(cust.wallet_balance)},
    )

    return {"ok": True, "status": "credited"}


@router.get("/ipay/status/{order_id}", response_model=WalletTransactionResponse)
@router.get("/payhere/status/{order_id}", response_model=WalletTransactionResponse)
async def ipay_status(
    order_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "restaurant_owner", "market_owner")),
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


@router.get("/ipay/config")
@router.get("/payhere/config")
async def ipay_config():
    """Lightweight probe so the Flutter app can decide which top-up flow to
    show (real gateway vs mock). No auth required — returns no secrets."""
    return {
        "enabled": ipay_service.is_enabled(),
        "mode": ipay_service.mode(),
        "gateway": "ipay",
    }


@router.post("/ipay/preapprove")
@router.post("/payhere/preapprove")
async def ipay_preapprove(
    body: dict,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    """Start a card pre-approval/tokenization session. Body: {return_url?, cancel_url?}.
    Returns fields to be posted to iPay pre-approve URL.
    """
    _ensure_enabled()
    order_id = "PA" + secrets.token_hex(6).upper()  # PA = pre-approval
    full_name = (user.full_name or "Customer").strip()
    first, _, last = full_name.partition(" ")
    payload = ipay_service.build_preapprove_payload(
        order_id=order_id,
        first_name=first or "Customer",
        last_name=last or "-",
        email=user.email or f"{user.phone_number}@ziggo.local",
        phone=user.phone_number,
        return_url=body.get("return_url") or "",
        cancel_url=body.get("cancel_url") or "",
    )
    return {"order_id": order_id, **payload}


@router.get("/methods")
async def list_payment_methods(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    """List all saved cards for the customer."""
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cq.scalars().first()
    if not customer:
        customer = Customer(user_id=user.id)
        db.add(customer)
        await db.commit()
        await db.refresh(customer)

    q = await db.execute(
        select(CustomerCard)
        .where(CustomerCard.customer_id == customer.id)
        .order_by(CustomerCard.is_default.desc(), CustomerCard.id.desc())
    )
    cards = q.scalars().all()
    return [
        {
            "id": c.id,
            "card_no": c.card_no,
            "card_expiry": c.card_expiry,
            "card_holder_name": c.card_holder_name,
            "card_type": c.card_type,
            "is_default": c.is_default,
            "created_at": c.created_at,
        }
        for c in cards
    ]


@router.delete("/methods/{card_id}", status_code=204)
async def delete_payment_method(
    card_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    """Delete a saved card."""
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cq.scalars().first()
    if not customer:
        customer = Customer(user_id=user.id)
        db.add(customer)
        await db.commit()
        await db.refresh(customer)

    q = await db.execute(
        select(CustomerCard).where(CustomerCard.id == card_id, CustomerCard.customer_id == customer.id)
    )
    card = q.scalars().first()
    if not card:
        raise HTTPException(status_code=404, detail="Card not found")

    await db.delete(card)
    await db.commit()
    return None


@router.post("/methods/{card_id}/default")
async def set_default_payment_method(
    card_id: int,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    """Set a card as default."""
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cq.scalars().first()
    if not customer:
        customer = Customer(user_id=user.id)
        db.add(customer)
        await db.commit()
        await db.refresh(customer)

    # Verify card exists and belongs to customer
    q = await db.execute(
        select(CustomerCard).where(CustomerCard.id == card_id, CustomerCard.customer_id == customer.id)
    )
    card = q.scalars().first()
    if not card:
        raise HTTPException(status_code=404, detail="Card not found")

    # Set all other cards for this customer to is_default = False
    await db.execute(
        update(CustomerCard)
        .where(CustomerCard.customer_id == customer.id)
        .values(is_default=False)
    )
    card.is_default = True
    await db.commit()
    return {"ok": True}


@router.post("/methods/mock")
async def add_mock_card(
    body: dict = {},
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer", "driver")),
):
    """Add a mock card for testing when PayHere is not configured."""
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cq.scalars().first()
    if not customer:
        customer = Customer(user_id=user.id)
        db.add(customer)
        await db.commit()
        await db.refresh(customer)

    import secrets
    
    input_card_no = body.get("card_no") if body else None
    input_card_expiry = body.get("card_expiry") if body else None
    input_card_holder = body.get("card_holder_name") if body else None
    input_card_type = body.get("card_type") if body else None

    if input_card_no:
        cleaned_no = "".join(filter(str.isdigit, input_card_no))
        if len(cleaned_no) >= 12:
            card_no = cleaned_no[:6] + "X" * (len(cleaned_no) - 10) + cleaned_no[-4:]
        else:
            card_no = cleaned_no
    else:
        card_no = f"411111XXXXXX{secrets.token_hex(2).upper()}"

    if input_card_expiry:
        card_expiry = "".join(filter(str.isdigit, input_card_expiry))
    else:
        card_expiry = "1228"

    card_holder_name = input_card_holder or user.full_name or "Valued Customer"
    card_type = (input_card_type or "VISA").upper()

    card = CustomerCard(
        customer_id=customer.id,
        card_no=card_no,
        card_expiry=card_expiry,
        card_holder_name=card_holder_name,
        card_type=card_type,
        customer_token=f"mock_token_{secrets.token_hex(8)}",
        is_default=True,
    )
    # Set all other cards to is_default = False
    await db.execute(
        update(CustomerCard)
        .where(CustomerCard.customer_id == customer.id)
        .values(is_default=False)
    )
    db.add(card)
    await db.commit()
    return {"ok": True, "card_id": card.id}


@router.post("/qr/resolve", response_model=QRResolveResponse)
async def qr_resolve(
    body: QRResolveRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Resolve a QR code payload (e.g. ziggopay://pay?type=restaurant&id=1)
    and return the merchant details.
    """
    payload = body.payload.strip()
    try:
        parsed = urlparse(payload)
        query = parse_qs(parsed.query)
        merchant_type = query.get("type", [None])[0]
        merchant_id_str = query.get("id", [None])[0]
    except Exception:
        merchant_type = None
        merchant_id_str = None

    if not merchant_type or not merchant_id_str:
        raise HTTPException(
            status_code=400,
            detail="Invalid QR code payload format. Expected ziggopay://pay?type=...&id=..."
        )

    try:
        m_id = int(merchant_id_str)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid merchant ID")

    if merchant_type == "restaurant":
        q = await db.execute(select(Restaurant).where(Restaurant.id == m_id))
        restaurant = q.scalars().first()
        if not restaurant:
            raise HTTPException(status_code=404, detail="Restaurant merchant not found")
        return QRResolveResponse(
            merchant_type="restaurant",
            merchant_id=restaurant.id,
            name=restaurant.name,
            address=restaurant.address,
            image_url=restaurant.image_url,
        )
    elif merchant_type == "market_vendor":
        q = await db.execute(select(MarketVendor).where(MarketVendor.id == m_id))
        vendor = q.scalars().first()
        if not vendor:
            raise HTTPException(status_code=404, detail="Market merchant not found")
        return QRResolveResponse(
            merchant_type="market_vendor",
            merchant_id=vendor.id,
            name=vendor.name,
            address=vendor.address,
            image_url=vendor.image_url,
        )
    else:
        raise HTTPException(status_code=400, detail="Unsupported merchant type")


@router.post("/qr/pay", response_model=MerchantPayResponse)
async def qr_pay(
    body: MerchantPayRequest,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(require_role("customer")),
):
    """Execute a QR payment from customer wallet to merchant."""
    cq = await db.execute(select(Customer).where(Customer.user_id == user.id))
    customer = cq.scalars().first()
    if not customer:
        raise HTTPException(status_code=404, detail="Customer profile not found")

    amount = Decimal(str(body.amount))
    if customer.wallet_balance < amount:
        raise HTTPException(status_code=400, detail="Insufficient wallet balance")

    merchant_name = ""
    owner_id = None
    if body.merchant_type == "restaurant":
        q = await db.execute(select(Restaurant).where(Restaurant.id == body.merchant_id))
        restaurant = q.scalars().first()
        if not restaurant:
            raise HTTPException(status_code=404, detail="Restaurant merchant not found")
        merchant_name = restaurant.name
        owner_id = restaurant.owner_id
    elif body.merchant_type == "market_vendor":
        q = await db.execute(select(MarketVendor).where(MarketVendor.id == body.merchant_id))
        vendor = q.scalars().first()
        if not vendor:
            raise HTTPException(status_code=404, detail="Market merchant not found")
        merchant_name = vendor.name
        owner_id = vendor.owner_id
    else:
        raise HTTPException(status_code=400, detail="Unsupported merchant type")

    customer.wallet_balance -= amount
    ref_id = "QR" + secrets.token_hex(6).upper()

    customer_txn = WalletTransaction(
        user_id=user.id,
        amount=amount,
        type="debit",
        description=f"QR payment to {merchant_name}",
        reference_id=ref_id,
        balance_after=customer.wallet_balance,
    )
    db.add(customer_txn)

    if owner_id:
        oq = await db.execute(select(Customer).where(Customer.user_id == owner_id))
        owner_cust = oq.scalars().first()
        if owner_cust:
            owner_cust.wallet_balance = (owner_cust.wallet_balance or Decimal(0)) + amount
            owner_txn = WalletTransaction(
                user_id=owner_id,
                amount=amount,
                type="credit",
                description=f"QR payment received from customer {user.full_name or user.phone_number} at {merchant_name}",
                reference_id=ref_id,
                balance_after=owner_cust.wallet_balance,
            )
            db.add(owner_txn)

            await manager.send(
                owner_id,
                "payment_received",
                {"reference_id": ref_id, "amount": float(amount), "balance": float(owner_cust.wallet_balance)},
            )

    await db.commit()

    await manager.send(
        user.id,
        "wallet_debited",
        {"reference_id": ref_id, "amount": float(amount), "balance": float(customer.wallet_balance)},
    )

    return MerchantPayResponse(
        success=True,
        reference_id=ref_id,
        amount=amount,
        remaining_balance=customer.wallet_balance,
        merchant_name=merchant_name
    )


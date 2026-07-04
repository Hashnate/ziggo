import re

with open('ziggo_backend/app/api/v1/market_vendor.py', 'r') as f:
    content = f.read()

# Replace get_commission logic
old_logic = '''    # 1. Total sales (Delivered orders)
    q = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == vendor.id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = q.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    total_sales = cod_sales + online_sales

    # 2. Commission rate & total owed
    comm_pct = Decimal(str(vendor.commission_percentage)) if vendor.commission_percentage is not None else Decimal("10.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")

    # 3. Total paid
    from ...models import WalletTransaction
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == user.id,
            WalletTransaction.type == "commission_payment"
        ).order_by(WalletTransaction.created_at.desc())
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == user.id,
            WalletTransaction.type == "settlement_payment"
        ).order_by(WalletTransaction.created_at.desc())
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    # 4. Outstanding
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    admin_owes_vendor = Decimal("0")
    vendor_owes_admin = Decimal("0")
    if net_owed_to_admin > 0:
        vendor_owes_admin = net_owed_to_admin
    else:
        admin_owes_vendor = -net_owed_to_admin'''

new_logic = '''    from ...services.finance_service import get_market_outstanding_commission
    vendor_owes_admin = await get_market_outstanding_commission(db, vendor.id)
    admin_owes_vendor = Decimal("0")
    
    # Get payments for history
    from ...models import WalletTransaction, MarketOrder, MarketOrderStatus
    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == user.id,
            WalletTransaction.type == "commission_payment"
        ).order_by(WalletTransaction.created_at.desc())
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == user.id,
            WalletTransaction.type == "settlement_payment"
        ).order_by(WalletTransaction.created_at.desc())
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    q = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == vendor.id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = q.scalars().all()
    total_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in orders)
    
    comm_pct = Decimal(str(vendor.commission_percentage)) if vendor.commission_percentage is not None else Decimal("10.0")
    commission_owed_to_admin = total_sales * comm_pct / Decimal("100.0")'''

if old_logic in content:
    content = content.replace(old_logic, new_logic)

# Insert check_and_deactivate_market_vendor after pay_commission
payment_logic = '''    return {"ok": True, "paid_amount": float(outstanding)}'''
new_payment_logic = '''    from ...services.finance_service import check_and_deactivate_market_vendor
    await check_and_deactivate_market_vendor(db, vendor.id)
    return {"ok": True, "paid_amount": float(outstanding)}'''

if payment_logic in content:
    content = content.replace(payment_logic, new_payment_logic)

with open('ziggo_backend/app/api/v1/market_vendor.py', 'w') as f:
    f.write(content)


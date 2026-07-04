import os

with open('ziggo_backend/app/services/finance_service.py', 'a') as f:
    f.write('''

async def get_market_outstanding_commission(db, vendor_id: int):
    from sqlalchemy import select
    from decimal import Decimal
    from app.models import MarketOrder, MarketOrderStatus, WalletTransaction, MarketVendor
    
    vq = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = vq.scalars().first()
    if not v or not v.owner_id:
        return Decimal("0")

    q = await db.execute(
        select(MarketOrder).where(
            MarketOrder.vendor_id == vendor_id,
            MarketOrder.status == MarketOrderStatus.DELIVERED
        )
    )
    orders = q.scalars().all()
    
    cod_orders = [o for o in orders if o.payment_method == "cash"]
    online_orders = [o for o in orders if o.payment_method != "cash"]
    
    cod_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in cod_orders)
    online_sales = sum((o.final_amount or Decimal(0)) - (o.delivery_fee or Decimal(0)) for o in online_orders)
    
    comm_pct = Decimal(str(v.commission_percentage)) if v.commission_percentage is not None else Decimal("10.0")
    commission_owed_to_admin = (cod_sales * comm_pct) / Decimal("100.0")
    settlement_owed_to_vendor = online_sales * (Decimal("100.0") - comm_pct) / Decimal("100.0")

    tq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == v.owner_id,
            WalletTransaction.type == "commission_payment"
        )
    )
    txs = tq.scalars().all()
    total_paid_to_admin = sum(tx.amount for tx in txs if tx.amount)
    
    stq = await db.execute(
        select(WalletTransaction).where(
            WalletTransaction.user_id == v.owner_id,
            WalletTransaction.type == "settlement_payment"
        )
    )
    settlement_txs = stq.scalars().all()
    total_paid_to_vendor = sum(tx.amount for tx in settlement_txs if tx.amount)
    
    net_owed_to_admin = (commission_owed_to_admin - total_paid_to_admin) - (settlement_owed_to_vendor - total_paid_to_vendor)
    
    return max(Decimal("0"), net_owed_to_admin)


async def check_and_deactivate_market_vendor(db, vendor_id: int) -> bool:
    from sqlalchemy import select
    from decimal import Decimal
    from app.models import MarketVendor
    
    vq = await db.execute(select(MarketVendor).where(MarketVendor.id == vendor_id))
    v = vq.scalars().first()
    if not v:
        return False
        
    outstanding = await get_market_outstanding_commission(db, vendor_id)
    max_limit = v.max_settle_amount if v.max_settle_amount is not None else Decimal("1000.00")
        
    if outstanding > max_limit:
        if v.is_active:
            v.is_active = False
            await db.commit()
            print(f"[deactivation] MarketVendor {vendor_id} deactivated. Outstanding: {outstanding}, Limit: {max_limit}")
        return True
    else:
        if not v.is_active:
            v.is_active = True
            await db.commit()
            print(f"[reactivation] MarketVendor {vendor_id} reactivated. Outstanding: {outstanding}")
        return False
''')

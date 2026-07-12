import asyncio
import sys
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select
from decimal import Decimal

sys.path.insert(0, '/var/www/ziggo/ziggo_backend')
from app.config import settings
from app.models import Restaurant, MarketVendor
from app.services.finance_service import (
    get_restaurant_outstanding_commission,
    get_market_outstanding_commission
)

async def main():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with async_session() as db:
        print("=== RESTAURANTS ===")
        rq = await db.execute(select(Restaurant))
        for r in rq.scalars().all():
            out = await get_restaurant_outstanding_commission(db, r.id)
            print(f"ID: {r.id}, Name: {r.name}, Active: {r.is_active}, Outstanding: {out}, Limit: {r.max_settle_amount}")
            
        print("\n=== MARKET VENDORS ===")
        vq = await db.execute(select(MarketVendor))
        for v in vq.scalars().all():
            out = await get_market_outstanding_commission(db, v.id)
            print(f"ID: {v.id}, Name: {v.name}, Active: {v.is_active}, Outstanding: {out}, Limit: {v.max_settle_amount}")

if __name__ == "__main__":
    asyncio.run(main())

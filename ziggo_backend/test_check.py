import asyncio
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import Driver
from app.services.finance_service import get_driver_outstanding_commission

async def check():
    async with AsyncSessionLocal() as db:
        drv_q = await db.execute(select(Driver).where(Driver.id == 13))
        d = drv_q.scalar()
        if d:
            out = await get_driver_outstanding_commission(db, d.id)
            print(f"Driver ID: {d.id}, Outstanding Commission: Rs.{out}")

if __name__ == "__main__":
    asyncio.run(check())

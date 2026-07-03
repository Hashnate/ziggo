import asyncio
import sys
sys.path.insert(0, '/var/www/ziggo/ziggo_backend')
from app.database import SessionLocal
from app.models import FoodOrder, Customer, Driver, Restaurant
from sqlalchemy import select

async def main():
    async with SessionLocal() as db:
        # Get the first PENDING food order or create one
        q = await db.execute(select(FoodOrder).limit(1))
        order = q.scalars().first()
        print(order.id, order.status.value)

if __name__ == "__main__":
    asyncio.run(main())

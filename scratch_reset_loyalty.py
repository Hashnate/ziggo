import asyncio
import sys
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import update

sys.path.insert(0, '/var/www/ziggo/ziggo_backend')
from app.config import settings
from app.models import Customer

async def main():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with async_session() as db:
        print("Resetting all customer loyalty points to 0...")
        stmt = update(Customer).values(loyalty_points=0)
        result = await db.execute(stmt)
        await db.commit()
        print(f"Successfully reset loyalty points. Rows affected: {result.rowcount}")

if __name__ == "__main__":
    asyncio.run(main())

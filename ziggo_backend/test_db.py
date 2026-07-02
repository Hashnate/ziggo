import asyncio
import os
import sys

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import AsyncSessionLocal
from app.services.fare_service import calculate_fare

async def main():
    async with AsyncSessionLocal() as db:
        try:
            fare = await calculate_fare(
                db=db,
                service_type='truck',
                pickup_lat=6.9,
                pickup_lng=79.8,
                drop_lat=6.91,
                drop_lng=79.81
            )
            print("Fare calculated:", fare)
        except Exception as e:
            import traceback
            traceback.print_exc()

if __name__ == '__main__':
    asyncio.run(main())

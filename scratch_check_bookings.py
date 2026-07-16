import asyncio
import sys
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select

sys.path.insert(0, '/var/www/ziggo/ziggo_backend')
from app.config import settings
from app.models import Booking, Driver

async def main():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with async_session() as db:
        print("=== BOOKINGS ===")
        bq = await db.execute(select(Booking))
        bookings = bq.scalars().all()
        print(f"Total bookings: {len(bookings)}")
        for b in bookings[:20]:
            print(f"ID: {b.id}, Ref: {b.booking_ref}, DriverID: {b.driver_id}, Status: {b.status}, PaymentMethod: {b.payment_method}, FinalAmt: {b.final_amount}, PlatformFee: {b.platform_fee}, DriverEarn: {b.driver_earnings}")

if __name__ == "__main__":
    asyncio.run(main())

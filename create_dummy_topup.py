import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select
import sys
import os

# add app to path
sys.path.insert(0, '/var/www/ziggo/ziggo_backend')
from app.models import User, WalletTopupRequest
from app.config import settings

async def main():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with async_session() as db:
        user = (await db.execute(select(User).limit(1))).scalars().first()
        if not user:
            print("No user found")
            return
            
        req = WalletTopupRequest(
            user_id=user.id,
            amount=5000,
            note="Test topup request",
            status="pending"
        )
        db.add(req)
        await db.commit()
        print("Created dummy request!")

if __name__ == "__main__":
    asyncio.run(main())

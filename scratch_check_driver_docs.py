import asyncio
import sys
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select

sys.path.insert(0, '/var/www/ziggo/ziggo_backend')
from app.config import settings
from app.models import DriverDocument, Driver, User

async def main():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    
    async with async_session() as db:
        print("=== DRIVER DOCUMENTS ===")
        dq = await db.execute(select(DriverDocument).options())
        docs = dq.scalars().all()
        print(f"Total documents: {len(docs)}")
        for d in docs:
            print(f"ID: {d.id}, DriverID: {d.driver_id}, Type: {d.document_type}, URL: {d.document_url}, Verified: {d.is_verified}")

if __name__ == "__main__":
    asyncio.run(main())

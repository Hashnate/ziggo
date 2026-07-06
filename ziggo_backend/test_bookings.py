import asyncio
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models import User, UserRole
from app.api.v1.bookings import list_my_bookings

async def main():
    async with AsyncSessionLocal() as db:
        q = await db.execute(select(User).where(User.role == UserRole.DRIVER))
        user = q.scalars().first()
        if not user:
            print("No driver user found")
            return
        
        print(f"Testing list_my_bookings for driver user {user.phone_number}")
        try:
            res = await list_my_bookings(db=db, user=user)
            print("Success! Number of records returned:", len(res))
            for item in res[:5]:
                print(f"Ref: {item.booking_ref}, Service: {item.service_type}, Status: {item.status}")
        except Exception as e:
            print("Error occurred:")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(main())

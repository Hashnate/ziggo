import asyncio
from app.database import AsyncSessionLocal, engine
from app.models import User
from sqlalchemy import select
from app.services import fcm_service

async def test_push():
    fcm_service.init()
    if not fcm_service.is_enabled():
        print("FCM is not enabled! Make sure FIREBASE_CREDENTIALS_PATH is set.")
        await engine.dispose()
        return

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.notification_token != None))
        users = result.scalars().all()
        
        if not users:
            print("No users found with a notification token in the database. Please open the app on your phone and log in to register your device token!")
            await engine.dispose()
            return
            
        print(f"Found {len(users)} users with tokens. Sending test notifications...")
        for user in users:
            success = await fcm_service.send_to_user(
                db, 
                user.id, 
                "Ziggo Test Notification 🚀", 
                "This is a test push notification sent from the backend!", 
                {"event": "test"}
            )
            print(f"Sent to user {user.id} ({user.phone_number}): {'Success' if success else 'Failed'}")
    
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(test_push())

import asyncio
from sqlalchemy import text
from app.database import engine

async def migrate():
    print("Starting chat messages migration...")
    async with engine.begin() as conn:
        # Check if table exists
        result = await conn.execute(text(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='booking_messages';"
        ))
        if result.scalar():
            print("Table booking_messages already exists.")
            return

        print("Creating booking_messages table...")
        await conn.execute(text("""
            CREATE TABLE booking_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                booking_id INTEGER NOT NULL,
                sender_type VARCHAR(20) NOT NULL,
                message TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(booking_id) REFERENCES bookings(id) ON DELETE CASCADE
            )
        """))
        
        print("Creating index on booking_id...")
        await conn.execute(text(
            "CREATE INDEX ix_booking_messages_booking_id ON booking_messages(booking_id)"
        ))
        print("Migration complete!")

if __name__ == "__main__":
    asyncio.run(migrate())

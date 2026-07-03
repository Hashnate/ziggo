import asyncio
from sqlalchemy import text
from app.database import engine

async def migrate():
    print("Starting chat messages migration...")
    async with engine.begin() as conn:
        print("Creating booking_messages table...")
        await conn.execute(text("""
            CREATE TABLE IF NOT EXISTS booking_messages (
                id SERIAL PRIMARY KEY,
                booking_id INTEGER NOT NULL,
                sender_type VARCHAR(20) NOT NULL,
                message TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(booking_id) REFERENCES bookings(id) ON DELETE CASCADE
            )
        """))
        
        print("Creating index on booking_id...")
        await conn.execute(text(
            "CREATE INDEX IF NOT EXISTS ix_booking_messages_booking_id ON booking_messages(booking_id)"
        ))
        print("Migration complete!")

if __name__ == "__main__":
    asyncio.run(migrate())

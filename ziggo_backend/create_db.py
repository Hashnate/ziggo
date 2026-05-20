"""One-shot DB creation. Creates all tables from the SQLAlchemy models.

Use this for fresh local SQLite databases. For production PostgreSQL, prefer
Alembic migrations (`alembic upgrade head`).
"""
import asyncio

from app.database import engine, Base
from app import models  # noqa: F401 -- registers all models


async def main():
    print("[create_db] Creating tables...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    print("[create_db] Done. Tables:")
    for t in Base.metadata.sorted_tables:
        print(f"  - {t.name}")


if __name__ == "__main__":
    asyncio.run(main())

"""Lightweight self-healing schema sync that runs on FastAPI startup.

Two responsibilities, in order:

1. **Create missing tables** — runs ``Base.metadata.create_all`` so any newly
   added model class appears in the DB on next boot.

2. **Add missing columns** — for each entry in ``PENDING_COLUMNS``, inspect the
   table and ``ALTER TABLE`` the column in if it's not there. Idempotent.

3. **Seed defaults** — populate small lookup tables (e.g. FlashWeightTier) on
   first creation. Safe to re-run — only inserts when the table is empty.

To add a new column migration, append to ``PENDING_COLUMNS``. To add a new
table, just declare the model class anywhere under ``app/models`` and import
it via ``app/models/__init__.py`` — ``create_all`` picks it up automatically.
"""
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from typing import Iterable

from sqlalchemy import inspect, select, text
from sqlalchemy.ext.asyncio import AsyncEngine

from ..database import Base
from ..models import Event, EventTicketTier, FlashWeightTier, CorporateAccount, CorporateMember, DriverPayout  # noqa: F401 — ensures import for create_all

# (table_name, column_name, column_ddl)
PENDING_COLUMNS: Iterable[tuple[str, str, str]] = (
    ("bookings", "trip_type", "VARCHAR(20) NOT NULL DEFAULT 'one_way'"),
    ("restaurants", "is_open", "BOOLEAN NOT NULL DEFAULT 1"),
    ("food_orders", "confirmed_at", "DATETIME"),
    ("food_orders", "ready_at", "DATETIME"),
    ("food_orders", "picked_up_at", "DATETIME"),
    ("food_orders", "cancellation_reason", "TEXT"),
    ("market_vendors", "is_open", "BOOLEAN NOT NULL DEFAULT 1"),
    ("market_vendors", "opening_time", "VARCHAR(10)"),
    ("market_vendors", "closing_time", "VARCHAR(10)"),
    ("market_vendors", "delivery_fee", "NUMERIC(10, 2) NOT NULL DEFAULT 0"),
    ("market_vendors", "eta_minutes", "INTEGER NOT NULL DEFAULT 40"),
    ("market_vendors", "owner_id", "INTEGER"),
    ("market_orders", "instructions", "TEXT"),
    ("market_orders", "cancellation_reason", "TEXT"),
    ("market_orders", "confirmed_at", "DATETIME"),
    ("market_orders", "ready_at", "DATETIME"),
    ("market_orders", "picked_up_at", "DATETIME"),
    ("bookings", "is_rental", "BOOLEAN NOT NULL DEFAULT FALSE"),
    ("bookings", "rental_hours", "INTEGER"),
    ("users", "notification_token", "VARCHAR(255)"),
    ("drivers", "relative_name", "VARCHAR(100)"),
    ("drivers", "relative_contact", "VARCHAR(20)"),
    ("drivers", "relative_relationship", "VARCHAR(50)"),
    ("drivers", "billing_proof_url", "VARCHAR(255)"),
    ("bookings", "is_corporate", "BOOLEAN NOT NULL DEFAULT FALSE"),
    ("bookings", "corporate_id", "INTEGER"),
    ("market_vendors", "logo_url", "VARCHAR(255)"),
)



DEFAULT_FLASH_TIERS = [
    {
        "label": "Light",
        "min_weight_kg": Decimal("0"),
        "max_weight_kg": Decimal("1"),
        "representative_weight_kg": Decimal("0.5"),
        "surcharge": Decimal("0"),
        "icon": "feed",
        "display_order": 1,
    },
    {
        "label": "Medium",
        "min_weight_kg": Decimal("1"),
        "max_weight_kg": Decimal("5"),
        "representative_weight_kg": Decimal("3"),
        "surcharge": Decimal("80"),
        "icon": "shopping_bag",
        "display_order": 2,
    },
    {
        "label": "Heavy",
        "min_weight_kg": Decimal("5"),
        "max_weight_kg": Decimal("15"),
        "representative_weight_kg": Decimal("10"),
        "surcharge": Decimal("250"),
        "icon": "inventory_2",
        "display_order": 3,
    },
    {
        "label": "X-Large",
        "min_weight_kg": Decimal("15"),
        "max_weight_kg": None,
        "representative_weight_kg": Decimal("20"),
        "surcharge": Decimal("600"),
        "icon": "local_shipping",
        "display_order": 4,
    },
]


async def ensure_schema(engine: AsyncEngine) -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

        def _alter(sync_conn) -> list[str]:
            insp = inspect(sync_conn)
            tables = set(insp.get_table_names())
            added: list[str] = []
            for table, column, ddl in PENDING_COLUMNS:
                if table not in tables:
                    continue
                existing = {c["name"] for c in insp.get_columns(table)}
                if column in existing:
                    continue
                sync_conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}"))
                added.append(f"{table}.{column}")
            return added

        added = await conn.run_sync(_alter)
        if added:
            print(f"[schema_sync] Added columns: {', '.join(added)}")

        await _seed_flash_tiers(conn)
        await _seed_sample_events(conn)


async def _seed_flash_tiers(conn) -> None:
    existing = await conn.execute(select(FlashWeightTier))
    if existing.scalars().first() is not None:
        return
    for row in DEFAULT_FLASH_TIERS:
        await conn.execute(
            FlashWeightTier.__table__.insert().values(**row, is_active=True)
        )
    print(f"[schema_sync] Seeded {len(DEFAULT_FLASH_TIERS)} default flash weight tiers")


async def _seed_sample_events(conn) -> None:
    """Drop in two demo events on first boot so the customer Events screen has
    something to show. Skipped if any rows already exist."""
    existing = await conn.execute(select(Event))
    if existing.scalars().first() is not None:
        return

    now = datetime.now(timezone.utc)
    samples = [
        {
            "event": {
                "name": "Colombo Music Night 2026",
                "description": (
                    "An open-air evening of local indie + reggae acts at the "
                    "Galle Face Green. Food trucks, late-night DJ set."
                ),
                "venue": "Galle Face Green",
                "city": "Colombo",
                "image_url": "https://images.unsplash.com/photo-1470229722913-7c0e2dbbafd3?w=1200&q=80",
                "organizer_name": "Ziggo Live",
                "organizer_phone": "0771234567",
                "starts_at": now + timedelta(days=14),
                "ends_at": now + timedelta(days=14, hours=5),
                "is_published": True,
            },
            "tiers": [
                {"name": "Regular", "price": Decimal("1500"), "capacity": 300},
                {"name": "Premium", "price": Decimal("3500"), "capacity": 100},
                {"name": "VIP", "price": Decimal("7500"), "capacity": 40},
            ],
        },
        {
            "event": {
                "name": "Kandy Cultural Festival",
                "description": (
                    "A weekend of traditional dance, drumming and craft stalls "
                    "in the heart of the hill country. Family-friendly."
                ),
                "venue": "Bogambara Stadium",
                "city": "Kandy",
                "image_url": "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=1200&q=80",
                "organizer_name": "Hill Country Arts Council",
                "organizer_phone": "0812223344",
                "starts_at": now + timedelta(days=30),
                "ends_at": now + timedelta(days=32),
                "is_published": True,
            },
            "tiers": [
                {"name": "Day Pass", "price": Decimal("800"), "capacity": 500},
                {"name": "Weekend Pass", "price": Decimal("1800"), "capacity": 250},
            ],
        },
    ]

    for s in samples:
        result = await conn.execute(
            Event.__table__.insert().values(**s["event"])
        )
        event_id = result.inserted_primary_key[0]
        for t in s["tiers"]:
            await conn.execute(
                EventTicketTier.__table__.insert().values(event_id=event_id, **t)
            )
    print(f"[schema_sync] Seeded {len(samples)} sample events")

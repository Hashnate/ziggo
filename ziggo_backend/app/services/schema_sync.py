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
from ..models import Event, EventTicketTier, EventOrder, EventOrderItem, FlashWeightTier, CorporateAccount, CorporateMember, DriverPayout, MarketAd, DriverIncentive  # noqa: F401 — ensures import for create_all

# (table_name, column_name, column_ddl)
PENDING_COLUMNS: Iterable[tuple[str, str, str]] = (
    ("bookings", "trip_type", "VARCHAR(20) NOT NULL DEFAULT 'one_way'"),
    ("restaurants", "is_open", "BOOLEAN NOT NULL DEFAULT TRUE"),
    ("food_orders", "confirmed_at", "TIMESTAMP"),
    ("food_orders", "ready_at", "TIMESTAMP"),
    ("food_orders", "picked_up_at", "TIMESTAMP"),
    ("food_orders", "cancellation_reason", "TEXT"),
    ("market_vendors", "is_open", "BOOLEAN NOT NULL DEFAULT TRUE"),
    ("market_vendors", "opening_time", "VARCHAR(10)"),
    ("market_vendors", "closing_time", "VARCHAR(10)"),
    ("market_vendors", "delivery_fee", "NUMERIC(10, 2) NOT NULL DEFAULT 0"),
    ("market_vendors", "eta_minutes", "INTEGER NOT NULL DEFAULT 40"),
    ("market_vendors", "owner_id", "INTEGER"),
    ("market_orders", "instructions", "TEXT"),
    ("market_orders", "cancellation_reason", "TEXT"),
    ("market_orders", "confirmed_at", "TIMESTAMP"),
    ("market_orders", "ready_at", "TIMESTAMP"),
    ("market_orders", "picked_up_at", "TIMESTAMP"),
    ("market_orders", "delivery_mode", "VARCHAR(20)"),
    ("market_orders", "delivery_distance_km", "NUMERIC(10, 2)"),
    ("market_orders", "total_weight_kg", "NUMERIC(10, 3)"),
    ("products", "weight_kg", "NUMERIC(10, 3)"),
    ("market_vendors", "self_delivery", "BOOLEAN NOT NULL DEFAULT FALSE"),
    ("market_vendors", "marketplace_delivery", "BOOLEAN NOT NULL DEFAULT TRUE"),
    ("market_vendors", "delivery_radius_km", "NUMERIC(10, 2)"),
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
    ("event_ticket_tiers", "sale_starts_at", "TIMESTAMP"),
    ("event_ticket_tiers", "sale_ends_at", "TIMESTAMP"),
    ("drivers", "current_heading", "NUMERIC(5, 2)"),
    ("users", "password", "VARCHAR(100)"),
    ("bookings", "otp", "VARCHAR(4)"),
    ("users", "admin_role", "VARCHAR(30)"),
    ("drivers", "bank_name", "VARCHAR(100)"),
    ("drivers", "account_holder_name", "VARCHAR(100)"),
    ("drivers", "account_number", "VARCHAR(50)"),
    ("drivers", "branch_name", "VARCHAR(100)"),
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


# Default Food home-screen layout, seeded on first boot so the customer Food
# screen renders content out of the box. Admin-editable at /admin/food-home.
# Category/collection names are shared with seed.py (get-or-create by name) so
# the demo restaurants can be tagged without duplicating the lists.
DEFAULT_FOOD_BANNERS = [
    {"title": "Pizza Festival", "image_url": "https://images.unsplash.com/photo-1513104890138-7c749659a591?q=80&w=800&auto=format&fit=crop", "link_type": "none", "link_value": None, "display_order": 1},
    {"title": "Combo Deals", "image_url": "https://images.unsplash.com/photo-1504674900247-0877df9cc836?q=80&w=800&auto=format&fit=crop", "link_type": "none", "link_value": None, "display_order": 2},
]

DEFAULT_FOOD_CATEGORIES = [
    {"name": "Rice & Curry", "icon_url": "https://images.unsplash.com/photo-1546833999-b9f581a1996d?q=80&w=200&auto=format&fit=crop", "display_order": 1},
    {"name": "Burgers", "icon_url": "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?q=80&w=200&auto=format&fit=crop", "display_order": 2},
    {"name": "Shawarma", "icon_url": "https://images.unsplash.com/photo-1628840042765-356cda07504e?q=80&w=200&auto=format&fit=crop", "display_order": 3},
    {"name": "Desserts", "icon_url": "https://images.unsplash.com/photo-1551024506-0bccd828d307?q=80&w=200&auto=format&fit=crop", "display_order": 4},
    {"name": "Beverages", "icon_url": "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?q=80&w=200&auto=format&fit=crop", "display_order": 5},
    {"name": "Chinese", "icon_url": "https://images.unsplash.com/photo-1585032226651-759b368d7246?q=80&w=200&auto=format&fit=crop", "display_order": 6},
    {"name": "Indian", "icon_url": "https://images.unsplash.com/photo-1585937421612-70a008356fbe?q=80&w=200&auto=format&fit=crop", "display_order": 7},
    {"name": "Pizza", "icon_url": "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?q=80&w=200&auto=format&fit=crop", "display_order": 8},
]

DEFAULT_FOOD_COLLECTIONS = [
    {"name": "Popular", "icon": "local_fire_department", "color": "blue", "display_order": 1},
    {"name": "Newly Joined", "icon": "fiber_new", "color": "cyan", "display_order": 2},
    {"name": "Featured Outlets", "icon": "verified", "color": "red", "display_order": 3},
    {"name": "Family Friendly", "icon": "family_restroom", "color": "indigo", "display_order": 4},
]

DEFAULT_FOOD_DEALS = [
    {"title": "30% OFF", "subtitle": "Save up to Rs.360", "image_url": "https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?q=80&w=400&auto=format&fit=crop", "color": "orange", "promo_code": "ZIGGO50", "display_order": 1},
    {"title": "Rs.100 OFF", "subtitle": "Flat Rs.100 off your order", "image_url": "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?q=80&w=400&auto=format&fit=crop", "color": "purple", "promo_code": "FLAT100", "display_order": 2},
    {"title": "Spend more, Save more", "subtitle": "Deals from your favourite outlets!", "image_url": "https://images.unsplash.com/photo-1576867757603-05b134ebc379?q=80&w=400&auto=format&fit=crop", "color": "green", "promo_code": None, "display_order": 3},
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
        await _seed_food_home(conn)
        await _seed_incentives(conn)


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


async def _seed_food_home(conn) -> None:
    """Seed the four food home-layout tables on first boot. Each is guarded
    independently, so a table added later still gets its defaults. Deals link
    to seeded promo codes by code when one exists. Restaurant tagging
    (category/collection membership) happens in seed.py, which owns the demo
    restaurants."""
    from ..models import FoodBanner, FoodCategory, FoodCollection, FoodDeal, PromoCode

    seeded: list[str] = []

    if (await conn.execute(select(FoodBanner))).scalars().first() is None:
        for row in DEFAULT_FOOD_BANNERS:
            await conn.execute(FoodBanner.__table__.insert().values(is_active=True, **row))
        seeded.append(f"{len(DEFAULT_FOOD_BANNERS)} banners")

    if (await conn.execute(select(FoodCategory))).scalars().first() is None:
        for row in DEFAULT_FOOD_CATEGORIES:
            await conn.execute(FoodCategory.__table__.insert().values(is_active=True, **row))
        seeded.append(f"{len(DEFAULT_FOOD_CATEGORIES)} categories")

    if (await conn.execute(select(FoodCollection))).scalars().first() is None:
        for row in DEFAULT_FOOD_COLLECTIONS:
            await conn.execute(FoodCollection.__table__.insert().values(is_active=True, **row))
        seeded.append(f"{len(DEFAULT_FOOD_COLLECTIONS)} collections")

    if (await conn.execute(select(FoodDeal))).scalars().first() is None:
        for row in DEFAULT_FOOD_DEALS:
            values = {k: v for k, v in row.items() if k != "promo_code"}
            code = row.get("promo_code")
            promo_id = None
            if code:
                pq = await conn.execute(select(PromoCode.id).where(PromoCode.code == code))
                promo_id = pq.scalar_one_or_none()
            await conn.execute(
                FoodDeal.__table__.insert().values(is_active=True, promo_code_id=promo_id, **values)
            )
        seeded.append(f"{len(DEFAULT_FOOD_DEALS)} deals")

    if seeded:
        print(f"[schema_sync] Seeded food home: {', '.join(seeded)}")


async def _seed_incentives(conn) -> None:
    from ..models import DriverIncentive
    existing = await conn.execute(select(DriverIncentive))
    if existing.scalars().first() is not None:
        return
    
    defaults = [
        {"title": "One Day Incentives", "limit_days": 1, "trips_required": 3, "reward_amount": Decimal("350.00")},
        {"title": "Weekday Incentives", "limit_days": 6, "trips_required": 100, "reward_amount": Decimal("3500.00")},
        {"title": "Weekday Incentives", "limit_days": 6, "trips_required": 120, "reward_amount": Decimal("6000.00")},
        {"title": "Weekday Incentives", "limit_days": 6, "trips_required": 225, "reward_amount": Decimal("20000.00")},
    ]
    for row in defaults:
        await conn.execute(DriverIncentive.__table__.insert().values(**row, is_active=True))
    print(f"[schema_sync] Seeded {len(defaults)} default driver incentive tiers")

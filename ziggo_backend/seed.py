"""Seed the database with demo data so the app behaves like a real PickMe-ish system.

Run after migrations:
    python seed.py
"""
import asyncio
from decimal import Decimal
from datetime import datetime, timezone, timedelta

from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models import (
    User,
    UserRole,
    Customer,
    Driver,
    DriverStatus,
    FareSetting,
    PromoCode,
    Restaurant,
    MenuCategory,
    MenuItem,
    MarketVendor,
    Product,
)

# Colombo center
CMB_LAT, CMB_LNG = 6.9271, 79.8612


async def upsert_user(db, phone, role, full_name=None, email=None):
    q = await db.execute(select(User).where(User.phone_number == phone))
    u = q.scalars().first()
    if u:
        return u
    u = User(phone_number=phone, role=role, full_name=full_name, email=email, is_active=True)
    db.add(u)
    await db.flush()
    return u


async def seed_admin(db):
    admin = await upsert_user(db, "0700000000", UserRole.ADMIN, full_name="Ziggo Admin", email="admin@ziggo.com")
    return admin


async def seed_fare_settings(db):
    rates = [
        ("bike",  60,  35,  2, 100, 15, 1.0),
        ("tuk",   80,  55,  3, 150, 15, 1.0),
        ("car",   150, 80,  4, 250, 15, 1.0),
        ("van",   250, 120, 5, 400, 15, 1.0),
        ("truck", 500, 200, 6, 750, 15, 1.0),
    ]
    for st, base, perkm, permin, minf, pct, surge in rates:
        q = await db.execute(select(FareSetting).where(FareSetting.service_type == st))
        if q.scalars().first():
            continue
        db.add(
            FareSetting(
                service_type=st,
                base_fare=Decimal(str(base)),
                per_km_rate=Decimal(str(perkm)),
                per_minute_rate=Decimal(str(permin)),
                min_fare=Decimal(str(minf)),
                platform_fee_percent=Decimal(str(pct)),
                surge_multiplier=Decimal(str(surge)),
            )
        )


async def seed_promos(db):
    promos = [
        ("ZIGGO50",  "50% off your next ride (max Rs.500)", "percentage", 50, 0,   500, 1000),
        ("FLAT100",  "Flat Rs.100 off",                       "fixed",      100, 200, 100, 5000),
        ("WELCOME",  "Welcome bonus - 30% off",               "percentage", 30,  0,   300, 10000),
    ]
    for code, desc, dtype, dval, minamt, maxd, lim in promos:
        q = await db.execute(select(PromoCode).where(PromoCode.code == code))
        if q.scalars().first():
            continue
        db.add(
            PromoCode(
                code=code,
                description=desc,
                discount_type=dtype,
                discount_value=Decimal(str(dval)),
                min_order_amount=Decimal(str(minamt)),
                max_discount=Decimal(str(maxd)),
                usage_limit=lim,
                used_count=0,
                valid_from=datetime.now(timezone.utc),
                valid_to=datetime.now(timezone.utc) + timedelta(days=365),
                is_active=True,
            )
        )


async def seed_drivers(db):
    """Seed 6 demo drivers scattered around Colombo with various vehicle types."""
    drivers = [
        ("0771000001", "Kumara Silva",  "car",   "WP-1234", "Toyota Aqua",       "White",  6.9300, 79.8500),
        ("0771000002", "Nimal Perera",  "car",   "WP-5678", "Suzuki WagonR",     "Silver", 6.9210, 79.8650),
        ("0771000003", "Saman Fernando","tuk",   "TUK-9012","Bajaj Three-wheeler","Black", 6.9275, 79.8615),
        ("0771000004", "Ruwan Jayaweera","tuk",  "TUK-3456","Bajaj Three-wheeler","Yellow",6.9180, 79.8580),
        ("0771000005", "Tharindu Bandara","bike","WP-BIK-1","Honda CB125",       "Red",    6.9320, 79.8700),
        ("0771000006", "Asanka Wijesinghe","van","WP-VAN-1","Toyota HiAce",      "White",  6.9400, 79.8550),
    ]
    for phone, name, vtype, vnum, vmodel, vcolor, lat, lng in drivers:
        q = await db.execute(select(User).where(User.phone_number == phone))
        user = q.scalars().first()
        if not user:
            user = User(phone_number=phone, role=UserRole.DRIVER, full_name=name, is_active=True, rating=Decimal("4.8"), total_rides=120)
            db.add(user)
            await db.flush()
        dq = await db.execute(select(Driver).where(Driver.user_id == user.id))
        d = dq.scalars().first()
        if d:
            continue
        db.add(
            Driver(
                user_id=user.id,
                nic_number=f"NIC{user.id:07d}V",
                license_number=f"L-{user.id:06d}",
                vehicle_type=vtype,
                vehicle_number=vnum,
                vehicle_model=vmodel,
                vehicle_color=vcolor,
                is_approved=True,
                is_online=True,
                status=DriverStatus.APPROVED,
                current_lat=Decimal(str(lat)),
                current_lng=Decimal(str(lng)),
                last_location_update=datetime.now(timezone.utc),
                approved_at=datetime.now(timezone.utc),
                acceptance_rate=Decimal("95"),
                total_earnings=Decimal("125000"),
                today_earnings=Decimal("1250"),
                today_rides=12,
            )
        )


async def seed_demo_customer(db):
    user = await upsert_user(db, "0771234567", UserRole.CUSTOMER, full_name="John Doe", email="john@example.com")
    q = await db.execute(select(Customer).where(Customer.user_id == user.id))
    c = q.scalars().first()
    if not c:
        db.add(Customer(user_id=user.id, wallet_balance=Decimal("2450")))


async def seed_restaurants(db):
    data = [
        ("Spice Garden",   "Authentic Sri Lankan curry", "123 Galle Rd, Colombo", "Sri Lankan", 6.9255, 79.8620),
        ("Pizza Palace",   "Wood-fired pizzas",          "55 Marine Dr, Colombo", "Italian",    6.9282, 79.8480),
        ("Burger Hub",     "Smash burgers and fries",    "88 Park Ave, Dehiwala", "American",   6.8500, 79.8650),
        ("Bistro Café",    "Brunch and coffee",          "12 Independence Sq",    "Café",       6.9050, 79.8700),
    ]
    for name, desc, addr, cuisine, lat, lng in data:
        q = await db.execute(select(Restaurant).where(Restaurant.name == name))
        if q.scalars().first():
            continue
        r = Restaurant(
            name=name,
            description=desc,
            address=addr,
            cuisine=cuisine,
            lat=Decimal(str(lat)),
            lng=Decimal(str(lng)),
            phone_number="+94112000000",
            rating=Decimal("4.5"),
            is_active=True,
            opening_time="09:00",
            closing_time="22:00",
            delivery_fee=Decimal("150"),
            eta_minutes=30,
        )
        db.add(r)
        await db.flush()

        cat_main = MenuCategory(restaurant_id=r.id, name="Mains", display_order=1)
        cat_drinks = MenuCategory(restaurant_id=r.id, name="Drinks", display_order=2)
        db.add_all([cat_main, cat_drinks])
        await db.flush()

        items = [
            (cat_main.id,  "Chicken Kottu",   "House special", 950,  False),
            (cat_main.id,  "Vegetable Rice",  "Mixed veggies", 700,  True),
            (cat_main.id,  "Cheese Pizza",    "12-inch",       1450, True),
            (cat_drinks.id,"Iced Coffee",     "Cold brew",     400,  True),
            (cat_drinks.id,"Fresh Lime Soda", "Refreshing",    300,  True),
        ]
        for cid, n, d, price, veg in items:
            db.add(
                MenuItem(
                    restaurant_id=r.id,
                    category_id=cid,
                    name=n,
                    description=d,
                    price=Decimal(str(price)),
                    is_available=True,
                    is_veg=veg,
                    prep_time_min=15,
                )
            )


async def seed_market(db):
    # (vendor name, category, description, lat, lng, owner phone, owner name)
    data = [
        ("Fresh Mart",     "Grocery",   "Daily essentials", 6.9270, 79.8600, "0772000001", "Fresh Mart Owner"),
        ("PharmaPlus",     "Pharmacy",  "24/7 pharmacy",    6.9250, 79.8580, "0772000002", "PharmaPlus Owner"),
    ]
    for name, cat, desc, lat, lng, owner_phone, owner_name in data:
        # Ensure the owner user exists and is a market_owner so they can log in.
        owner = await upsert_user(
            db, owner_phone, UserRole.MARKET_OWNER, full_name=owner_name
        )
        # Idempotent backfill: if this vendor already exists from an older seed
        # run without an owner, attach the owner now instead of skipping.
        q = await db.execute(select(MarketVendor).where(MarketVendor.name == name))
        existing = q.scalars().first()
        if existing:
            if existing.owner_id is None:
                existing.owner_id = owner.id
            continue
        v = MarketVendor(
            owner_id=owner.id,
            name=name,
            category=cat,
            description=desc,
            address="Colombo",
            lat=Decimal(str(lat)),
            lng=Decimal(str(lng)),
            phone_number=owner_phone,
            rating=Decimal("4.3"),
            is_active=True,
            is_open=True,
            opening_time="08:00",
            closing_time="22:00",
            delivery_fee=Decimal("250"),
            eta_minutes=40,
        )
        db.add(v)
        await db.flush()
        for pn, price, unit in [
            ("Rice 5kg", 1200, "pack"),
            ("Sugar 1kg", 280, "kg"),
            ("Milk 1L", 320, "pc"),
            ("Eggs (10pc)", 450, "pack"),
        ]:
            db.add(
                Product(
                    vendor_id=v.id,
                    name=pn,
                    price=Decimal(str(price)),
                    unit=unit,
                    stock_quantity=100,
                    is_available=True,
                )
            )


async def main():
    async with AsyncSessionLocal() as db:
        await seed_admin(db)
        await seed_fare_settings(db)
        await seed_promos(db)
        await seed_drivers(db)
        await seed_demo_customer(db)
        await seed_restaurants(db)
        await seed_market(db)
        await db.commit()
        print("[seed] Done.")
        print("  Admin login   : phone 0700000000  password admin123  -> /admin/login")
        print("  Demo customer : 0771234567 (OTP 123456 in DEV_MODE)")
        print("  Demo drivers  : 077100000{1..6}")
        print("  Promo codes   : ZIGGO50, FLAT100, WELCOME")


if __name__ == "__main__":
    asyncio.run(main())

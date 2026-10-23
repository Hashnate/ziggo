"""Fill the STAGING database with generated customers, drivers and trips.

refresh-data.sh runs this inside the staging backend container, after
production's business setup (fare rates, zones, settings, catalog) has been
loaded into an empty schema:

    docker exec -i -e ADMIN_PASSWORDS=a,b,c ziggo_backend_staging python - < deploy/staging/generate_data.py

Everything here is made up: names like "Customer 12", phone numbers starting
with 000, and trips over all 25 districts plus border, coastal and
cross-district cases, so pricing, district and report work has data
everywhere. Fares come from the app's own fare engine and the loaded rates.
A fixed seed makes reruns produce the same people and trips.
"""
import asyncio
import math
import os
import random
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy import func, select, text

from app.config import settings
from app.database import AsyncSessionLocal
from app.models import (
    Booking, BookingStatus, BookingStop, Customer, Driver, DriverStatus, DriverVehicle,
    FareSetting, MarketVendor, PromoCode, Restaurant, User, UserRole, WalletTransaction,
)
from app.services.fare_service import calculate_fare, to_decimal

SEED = 20261022
N_CUSTOMERS = 400
N_TRIPS = 2500
DAYS = 90

rng = random.Random(SEED)
NOW = datetime.now(timezone.utc).replace(microsecond=0)
LOCAL = timezone(timedelta(hours=5, minutes=30))

# Rough share of trips per district, and approximate town centres in each.
DISTRICTS = {
    "Colombo": (30, [("Fort", 6.9344, 79.8500), ("Bambalapitiya", 6.8942, 79.8580), ("Borella", 6.9147, 79.8778),
                     ("Nugegoda", 6.8649, 79.8997), ("Maharagama", 6.8480, 79.9265), ("Rajagiriya", 6.9094, 79.8939),
                     ("Dehiwala", 6.8511, 79.8700), ("Moratuwa", 6.7730, 79.8822), ("Kottawa", 6.8412, 79.9654),
                     ("Homagama", 6.8441, 80.0024), ("Kaduwela", 6.9330, 79.9850), ("Wellawatte", 6.8746, 79.8640)]),
    "Gampaha": (15, [("Gampaha", 7.0917, 79.9997), ("Negombo", 7.2008, 79.8737), ("Kadawatha", 7.0010, 79.9530),
                     ("Ja-Ela", 7.0744, 79.8919), ("Wattala", 6.9897, 79.8925), ("Kiribathgoda", 6.9800, 79.9290),
                     ("Minuwangoda", 7.1660, 79.9530)]),
    "Kalutara": (6, [("Kalutara", 6.5854, 79.9650), ("Panadura", 6.7132, 79.9070), ("Horana", 6.7159, 80.0626),
                     ("Beruwala", 6.4788, 79.9900), ("Matugama", 6.5215, 80.1137)]),
    "Kandy": (8, [("Kandy", 7.2906, 80.6337), ("Peradeniya", 7.2690, 80.5970), ("Katugastota", 7.3370, 80.6250),
                  ("Gampola", 7.1643, 80.5696), ("Kundasale", 7.2810, 80.6900)]),
    "Matale": (1.5, [("Matale", 7.4675, 80.6234), ("Dambulla", 7.8742, 80.6511)]),
    "Nuwara Eliya": (1.5, [("Nuwara Eliya", 6.9497, 80.7891), ("Hatton", 6.8916, 80.5955)]),
    "Galle": (5, [("Galle", 6.0535, 80.2210), ("Hikkaduwa", 6.1395, 80.1100), ("Ambalangoda", 6.2355, 80.0580),
                  ("Karapitiya", 6.0640, 80.2290)]),
    "Matara": (3, [("Matara", 5.9549, 80.5500), ("Weligama", 5.9746, 80.4330), ("Akuressa", 6.0950, 80.4760)]),
    "Hambantota": (1.5, [("Hambantota", 6.1241, 81.1100), ("Tangalle", 6.0240, 80.7940),
                         ("Tissamaharama", 6.2786, 81.2876)]),
    "Jaffna": (2, [("Jaffna", 9.6615, 80.0255), ("Chavakachcheri", 9.6580, 80.1630), ("Point Pedro", 9.8100, 80.2333)]),
    "Kilinochchi": (0.5, [("Kilinochchi", 9.3803, 80.3770)]),
    "Mannar": (0.5, [("Mannar", 8.9770, 79.9100), ("Murunkan", 8.8360, 80.0560)]),
    "Vavuniya": (1, [("Vavuniya", 8.7514, 80.4971)]),
    "Mullaitivu": (0.5, [("Puthukkudiyiruppu", 9.3170, 80.7130), ("Mullaitivu", 9.2671, 80.8000)]),
    "Batticaloa": (1.5, [("Batticaloa", 7.7310, 81.6747), ("Eravur", 7.7730, 81.6040), ("Kattankudy", 7.6750, 81.7290)]),
    "Ampara": (1.5, [("Ampara", 7.2975, 81.6820), ("Kalmunai", 7.4167, 81.8100), ("Akkaraipattu", 7.2167, 81.8450)]),
    "Trincomalee": (1.5, [("Trincomalee", 8.5874, 81.2152), ("Kinniya", 8.4970, 81.1800), ("Kantale", 8.3700, 80.9700)]),
    "Kurunegala": (4, [("Kurunegala", 7.4863, 80.3647), ("Kuliyapitiya", 7.4688, 80.0401), ("Narammala", 7.4320, 80.2150)]),
    "Puttalam": (2, [("Puttalam", 8.0362, 79.8400), ("Chilaw", 7.5758, 79.8050), ("Wennappuwa", 7.3500, 79.8500)]),
    "Anuradhapura": (2, [("Anuradhapura", 8.3114, 80.4037), ("Kekirawa", 8.0380, 80.5980)]),
    "Polonnaruwa": (1, [("Polonnaruwa", 7.9403, 81.0188), ("Hingurakgoda", 8.0400, 80.9500)]),
    "Badulla": (2, [("Badulla", 6.9934, 81.0550), ("Bandarawela", 6.8259, 80.9982), ("Mahiyanganaya", 7.3270, 81.0010)]),
    "Monaragala": (1, [("Monaragala", 6.8728, 81.3507), ("Wellawaya", 6.7370, 81.1020), ("Bibile", 7.1600, 81.2200)]),
    "Ratnapura": (2, [("Ratnapura", 6.6828, 80.3992), ("Embilipitiya", 6.3430, 80.8490), ("Balangoda", 6.6480, 80.6970)]),
    "Kegalle": (2, [("Kegalle", 7.2513, 80.3464), ("Mawanella", 7.2520, 80.4460), ("Warakapola", 7.2270, 80.1970)]),
}
DISTRICT_WEIGHTS = {name: weight for name, (weight, _) in DISTRICTS.items()}

# Pickups right next to a district boundary, for district-pricing edge cases.
BORDER_POINTS = [
    ("Kelaniya", "Gampaha", 6.9553, 79.9220), ("Peliyagoda", "Gampaha", 6.9650, 79.8850),
    ("Kaduwela", "Colombo", 6.9330, 79.9850), ("Lunawa", "Colombo", 6.7880, 79.8800),
    ("Panadura north", "Kalutara", 6.7400, 79.9050), ("Kadugannawa", "Kandy", 7.2550, 80.5230),
    ("Avissawella", "Colombo", 6.9533, 80.2100), ("Ruwanwella", "Kegalle", 7.0430, 80.2560),
]
# Pickups on the shoreline, where simplified district outlines may not reach.
COASTAL_POINTS = [
    ("Galle Face Green", "Colombo", 6.9235, 79.8456), ("Mount Lavinia beach", "Colombo", 6.8390, 79.8630),
    ("Negombo beach", "Gampaha", 7.2150, 79.8350), ("Unawatuna beach", "Galle", 6.0098, 80.2491),
    ("Nilaveli beach", "Trincomalee", 8.6970, 81.1880), ("Arugam Bay", "Ampara", 6.8400, 81.8360),
]
# Longer trips that start in one district and end in another.
CROSS_DISTRICT = [
    ("Colombo", "Kandy"), ("Colombo", "Galle"), ("Colombo", "Gampaha"), ("Gampaha", "Colombo"),
    ("Kalutara", "Colombo"), ("Kandy", "Matale"), ("Kandy", "Nuwara Eliya"), ("Kurunegala", "Puttalam"),
    ("Anuradhapura", "Polonnaruwa"), ("Galle", "Matara"), ("Matara", "Hambantota"),
    ("Batticaloa", "Ampara"), ("Jaffna", "Kilinochchi"), ("Kegalle", "Colombo"),
]

RIDE_MIX = {"tuk": 32, "bike": 24, "mini": 9, "car": 9, "moto scooter": 7, "wagon r": 5, "van": 7, "mover": 2, "truck": 2}
FLASH_MIX = {"bike": 6, "tuk": 3, "van": 1}
RENTAL_MIX = {"car": 2, "van": 1, "tuk": 1}
FLEET = {"tuk": 40, "bike": 30, "car": 14, "moto scooter": 8, "wagon r": 6, "mini": 6, "van": 6, "mover": 3, "truck": 3}
TEST_DRIVER_TYPES = ["tuk", "bike", "car", "mini", "van", "moto scooter"]
MODELS = {
    "tuk": ["Bajaj RE", "Bajaj RE Compact", "TVS King"],
    "bike": ["Honda Dio", "Bajaj Pulsar 150", "TVS Apache 160", "Yamaha FZ", "Hero Splendor"],
    "moto scooter": ["Honda Dio", "TVS Ntorq", "Yamaha Ray ZR"],
    "car": ["Toyota Axio", "Toyota Prius", "Honda Fit", "Toyota Aqua"],
    "mini": ["Suzuki Alto", "Perodua Viva", "Suzuki Celerio"],
    "wagon r": ["Suzuki Wagon R"],
    "van": ["Toyota HiAce", "Nissan Caravan", "Suzuki Every"],
    "mover": ["Tata Ace", "DFSK Mini Truck"],
    "truck": ["Isuzu Elf", "Mitsubishi Canter"],
}
COLOURS = ["White", "Black", "Silver", "Red", "Blue", "Green", "Grey", "Yellow"]
CANCEL_REASONS = {
    "customer": ["Changed my mind", "Driver is taking too long", "Booked by mistake", "Wrong pickup location"],
    "driver": ["Customer not at pickup", "Vehicle problem", "Too far away"],
    "system": ["No drivers available"],
}
PARCEL_TYPES = ["document", "food", "clothes", "electronics", "other"]
PARCEL_MAX_KG = {"bike": 5, "tuk": 15, "van": 60}
# Trips per local hour of day, with morning and evening peaks.
HOUR_WEIGHTS = [1, 1, 1, 1, 1, 2, 3, 6, 8, 7, 5, 5, 6, 5, 5, 5, 6, 8, 9, 8, 6, 4, 3, 2]


def weighted(choices: dict):
    keys = list(choices)
    return rng.choices(keys, weights=[choices[k] for k in keys])[0]


def move(lat: float, lng: float, km: float, bearing: float) -> tuple[float, float]:
    b = math.radians(bearing)
    return (lat + km / 111.32 * math.cos(b),
            lng + km / (111.32 * math.cos(math.radians(lat))) * math.sin(b))


def near(lat: float, lng: float, max_km: float) -> tuple[float, float]:
    return move(lat, lng, max_km * math.sqrt(rng.random()), rng.uniform(0, 360))


def coord(x: float) -> Decimal:
    return Decimal(str(round(x, 7)))


def town(district: str) -> tuple[str, float, float]:
    name, lat, lng = rng.choice(DISTRICTS[district][1])
    lat, lng = near(lat, lng, 0.8)
    return name, lat, lng


def joined_at() -> datetime:
    return NOW - timedelta(days=rng.randint(DAYS + 1, DAYS + 180), minutes=rng.randrange(1440))


def trip_time() -> datetime:
    day = (NOW.astimezone(LOCAL) - timedelta(days=rng.randint(1, DAYS))).date()
    hour = rng.choices(range(24), weights=HOUR_WEIGHTS)[0]
    local = datetime(day.year, day.month, day.day, hour, rng.randrange(60), rng.randrange(60), tzinfo=LOCAL)
    return local.astimezone(timezone.utc)


def trip_places():
    """Return (pickup, drop, pickup district, case) with places as (address, lat, lng)."""
    roll = rng.random()
    if roll < 0.08:
        start, end = rng.choice(CROSS_DISTRICT)
        pname, plat, plng = town(start)
        dname, dlat, dlng = town(end)
        return (f"{pname}, {start}", plat, plng), (f"{dname}, {end}", dlat, dlng), start, "cross-district"
    if roll < 0.15:
        name, district, lat, lng = rng.choice(BORDER_POINTS)
        plat, plng = near(lat, lng, 0.3)
        case = "border"
    elif roll < 0.20:
        name, district, plat, plng = rng.choice(COASTAL_POINTS)
        case = "coastal"
    else:
        district = weighted(DISTRICT_WEIGHTS)
        name, plat, plng = town(district)
        case = "in-district"
    km = min(25.0, max(0.8, rng.lognormvariate(1.3, 0.6)))
    dlat, dlng = move(plat, plng, km, rng.uniform(0, 360))
    return (f"{name}, {district}", plat, plng), (f"Near {name}, {district}", dlat, dlng), district, case


async def add_user(db, phone, role, name, joined, admin_role=None, password=None) -> User:
    user = User(phone_number=phone, role=role, full_name=name, admin_role=admin_role,
                password=password, is_active=True, created_at=joined)
    db.add(user)
    await db.flush()
    return user


async def add_driver(db, n: int, phone: str, name: str, vtype, status, driver_type="ride", home=None):
    joined = joined_at()
    user = await add_user(db, phone, UserRole.DRIVER, name, joined)
    home = home or weighted(DISTRICT_WEIGHTS)
    driver = Driver(user_id=user.id, driver_type=driver_type, status=status, is_online=False,
                    is_approved=status == DriverStatus.APPROVED, acceptance_rate=Decimal(rng.randint(70, 100)))
    if vtype:
        _, lat, lng = town(home)
        driver.vehicle_type = vtype
        driver.vehicle_number = f"STG-{n:04d}"
        driver.nic_number = f"STGNIC{n:05d}"
        driver.license_number = f"STGLIC{n:05d}"
        driver.vehicle_model = rng.choice(MODELS.get(vtype, ["Generic"]))
        driver.vehicle_color = rng.choice(COLOURS)
        driver.vehicle_year = rng.randint(2012, 2024)
        driver.current_lat, driver.current_lng = coord(lat), coord(lng)
        driver.last_location_update = NOW - timedelta(hours=rng.randint(1, 72))
        if status in (DriverStatus.APPROVED, DriverStatus.SUSPENDED):
            driver.approved_at = joined + timedelta(days=rng.randint(1, 5))
    db.add(driver)
    await db.flush()
    if vtype:
        db.add(DriverVehicle(
            driver_id=driver.id, vehicle_type=vtype, vehicle_number=driver.vehicle_number,
            vehicle_model=driver.vehicle_model, vehicle_color=driver.vehicle_color,
            vehicle_year=driver.vehicle_year, is_approved=driver.is_approved, is_active=True,
            approved_at=driver.approved_at,
        ))
    return driver, home


async def main() -> None:
    if "ziggo_postgres_staging" not in settings.DATABASE_URL:
        raise SystemExit("Refusing to run: this is not the staging database.")
    passwords = [p for p in (os.environ.get("ADMIN_PASSWORDS") or "").split(",") if p]
    if len(passwords) != 3:
        raise SystemExit("ADMIN_PASSWORDS must hold three comma-separated passwords.")

    async with AsyncSessionLocal() as db:
        if await db.scalar(select(func.count()).select_from(User)):
            raise SystemExit("Refusing to run: the database already has users. Use refresh-data.sh.")

        active = set((await db.execute(
            select(FareSetting.service_type).where(FareSetting.is_active == True)  # noqa: E712
        )).scalars())
        ride_mix = {t: w for t, w in RIDE_MIX.items() if t in active}
        flash_mix = {t: w for t, w in FLASH_MIX.items() if t in active}
        rental_mix = {t: w for t, w in RENTAL_MIX.items() if t in active}
        promos = [p.code for p in (await db.execute(
            select(PromoCode).where(PromoCode.is_active == True)  # noqa: E712
        )).scalars() if (p.category or "all") in ("all", "rides")]

        for phone, role, name, password in zip(
            ("0700000000", "0700000001", "0700000002"), ("superadmin", "admin", "data_entry"),
            ("Staging Superadmin", "Staging Admin", "Staging Data Entry"), passwords,
        ):
            await add_user(db, phone, UserRole.ADMIN, name, joined_at(), admin_role=role, password=password)

        # Customers: a few heavy riders, most occasional, plus the known test customer.
        customers, activity = [], []
        test_customer = None
        for i in range(N_CUSTOMERS + 1):
            is_test = i == 0
            phone, name = ("0771234567", "Test Customer") if is_test else (f"0000{i:06d}", f"Customer {i}")
            user = await add_user(db, phone, UserRole.CUSTOMER, name, joined_at())
            cust = Customer(user_id=user.id, wallet_balance=Decimal("0"),
                            default_payment_method=rng.choice(["cash", "cash", "cash", "wallet"]))
            db.add(cust)
            await db.flush()
            cust.joined = user.created_at
            customers.append(cust)
            activity.append(12 if is_test else rng.choice([1] * 60 + [3] * 30 + [8] * 10))
            if is_test:
                test_customer = cust

        # Drivers: approved fleet by vehicle mix, delivery riders, pending and suspended
        # registrations, and six known test drivers.
        ride_drivers, home_of, test_drivers = defaultdict(list), {}, {}
        n = 0
        for vtype, count in FLEET.items():
            if vtype not in active:
                continue
            for _ in range(count):
                n += 1
                driver, home = await add_driver(db, n, f"0001{n:06d}", f"Driver {n}", vtype, DriverStatus.APPROVED)
                ride_drivers[vtype].append(driver)
                home_of[driver.id] = home
        for vtype in ["bike"] * 8 + ["tuk"] * 3:
            n += 1
            await add_driver(db, n, f"0001{n:06d}", f"Delivery Rider {n}", vtype, DriverStatus.APPROVED,
                             driver_type="delivery")
        for vtype in ["tuk", "bike", "car", "van", "bike", "tuk"] + [None] * 12:
            n += 1
            await add_driver(db, n, f"0001{n:06d}", f"Applicant {n}", vtype, DriverStatus.PENDING)
        for vtype in ["bike", "tuk", "tuk", "car", "bike", "van", "mini", "bike"]:
            n += 1
            await add_driver(db, n, f"0001{n:06d}", f"Driver {n}", vtype, DriverStatus.SUSPENDED)
        for k, vtype in enumerate([t for t in TEST_DRIVER_TYPES if t in active][:6], start=1):
            n += 1
            driver, home = await add_driver(db, n, f"077100000{k}", f"Test Driver {k} ({vtype})", vtype,
                                            DriverStatus.APPROVED, home="Colombo")
            ride_drivers[vtype].append(driver)
            home_of[driver.id] = home
            test_drivers[vtype] = driver

        # Owner logins for the restaurant and vendor portals.
        restaurant = (await db.execute(select(Restaurant).order_by(Restaurant.is_active.desc(), Restaurant.id).limit(1))).scalars().first()
        if restaurant:
            owner = await add_user(db, "0771100001", UserRole.RESTAURANT_OWNER, "Test Restaurant Owner", joined_at())
            restaurant.owner_id = owner.id
        vendor = (await db.execute(select(MarketVendor).order_by(MarketVendor.is_active.desc(), MarketVendor.id).limit(1))).scalars().first()
        if vendor:
            owner = await add_user(db, "0771200001", UserRole.MARKET_OWNER, "Test Vendor Owner", joined_at())
            vendor.owner_id = owner.id

        # Plan every trip first, then price and store them in time order so wallet
        # balances run forward correctly.
        plans = []
        for _ in range(N_TRIPS):
            kind = weighted({"ride": 88, "flash": 9, "rental": 3})
            mix = {"ride": ride_mix, "flash": flash_mix, "rental": rental_mix}[kind] or ride_mix
            plans.append({"kind": kind, "service": weighted(mix), "at": trip_time()})
        plans.sort(key=lambda p: p["at"])

        balance = defaultdict(Decimal)
        refs, stats = set(), Counter()
        by_district, by_case = Counter(), Counter()
        topups = 0

        async def topup(cust, amount: Decimal, at: datetime):
            nonlocal topups
            topups += 1
            balance[cust.id] += amount
            db.add(WalletTransaction(user_id=cust.user_id, amount=amount, type="credit",
                                     description="Wallet top-up", reference_id=f"STG-TOPUP-{topups}",
                                     balance_after=balance[cust.id], created_at=at))

        await topup(test_customer, Decimal("5000.00"), test_customer.joined)
        for cust in customers[1:]:
            if rng.random() < 0.35:
                await topup(cust, Decimal(rng.randrange(1000, 10001, 500)), cust.joined)

        for i, plan in enumerate(plans, start=1):
            kind, service, booked_at = plan["kind"], plan["service"], plan["at"]
            (paddr, plat, plng), (daddr, dlat, dlng), district, case = trip_places()
            if kind == "rental":
                daddr, dlat, dlng = paddr, plat, plng
            cust = rng.choices(customers, weights=activity)[0]

            stops = []
            trip_type = "one_way"
            if kind == "ride":
                trip_type = "return" if rng.random() < 0.04 else "one_way"
                for k in range(weighted({0: 91, 1: 7, 2: 2})):
                    f = (k + 1) / 3
                    slat, slng = near(plat + (dlat - plat) * f, plng + (dlng - plng) * f, 0.5)
                    stops.append({"lat": slat, "lng": slng, "address": f"Stop {k + 1} near {paddr}"})

            status = BookingStatus.COMPLETED if rng.random() < 0.70 else BookingStatus.CANCELLED
            cancelled_by = None if status == BookingStatus.COMPLETED else weighted({"system": 40, "customer": 45, "driver": 15})
            pool = ride_drivers.get(service, [])
            needs_driver = status == BookingStatus.COMPLETED or cancelled_by == "driver" or (
                cancelled_by == "customer" and rng.random() < 0.5)
            driver = None
            if needs_driver and pool:
                local = [d for d in pool if home_of[d.id] == district]
                if service in test_drivers and rng.random() < 0.05:
                    driver = test_drivers[service]
                else:
                    driver = rng.choice(local if local and rng.random() < 0.7 else pool)
            elif needs_driver:
                status, cancelled_by = BookingStatus.CANCELLED, "system"

            alat, alng = (move(plat, plng, rng.uniform(0.3, 4.0), rng.uniform(0, 360)) if driver else (plat, plng))
            weight = round(rng.uniform(0.3, PARCEL_MAX_KG.get(service, 10)), 1) if kind == "flash" else None
            hours = rng.randint(2, 10) if kind == "rental" else None
            promo = rng.choice(promos) if promos and kind == "ride" and rng.random() < 0.08 else None
            fare = await calculate_fare(
                db, service, plat, plng, dlat, dlng, promo,
                trip_type=trip_type, is_flash=kind == "flash", parcel_weight_kg=weight,
                is_rental=kind == "rental", rental_hours=hours, stops=stops or None,
                driver_accepted_lat=alat, driver_accepted_lng=alng,
            )

            prefix = "FL" if kind == "flash" else "ZG"
            ref = f"{prefix}{rng.getrandbits(32):08X}"
            while ref in refs:
                ref = f"{prefix}{rng.getrandbits(32):08X}"
            refs.add(ref)

            payment = weighted({"cash": 70, "wallet": 25, "card": 5})
            booking = Booking(
                booking_ref=ref, customer_id=cust.id, driver_id=driver.id if driver else None,
                pickup_lat=coord(plat), pickup_lng=coord(plng), pickup_address=paddr,
                drop_lat=coord(dlat), drop_lng=coord(dlng), drop_address=daddr,
                service_type=service, trip_type=trip_type, status=status,
                distance_km=to_decimal(fare["distance_km"]), duration_min=fare["duration_min"],
                fare_amount=to_decimal(fare["fare_amount"]), discount_amount=to_decimal(fare["discount_amount"]),
                final_amount=to_decimal(fare["final_amount"]), platform_fee=to_decimal(fare["platform_fee"]),
                driver_earnings=to_decimal(fare["driver_earnings"]),
                pickup_distance_km=to_decimal(fare.get("pickup_distance_km", 0)),
                pickup_fee=to_decimal(fare.get("pickup_fee", 0)), boost=to_decimal(fare.get("boost", 0)),
                peak_surcharge=to_decimal(fare.get("peak_surcharge", 0)),
                passenger_deductible=to_decimal(fare.get("passenger_deductible", 0)),
                app_usage_charges=to_decimal(fare.get("app_usage_charges", 0)),
                deductions=to_decimal(fare.get("deductions", 0)),
                promo_code=fare.get("promo_code"), payment_method=payment,
                payment_status="paid" if status == BookingStatus.COMPLETED else "pending",
                is_flash=kind == "flash", is_rental=kind == "rental", rental_hours=hours,
                stop_count=len(stops), booked_at=booked_at, dispatch_started_at=booked_at,
            )
            if kind == "flash":
                booking.parcel_type = rng.choice(PARCEL_TYPES)
                booking.parcel_weight_kg = Decimal(str(weight))
                booking.receiver_name = f"Receiver {i}"
                booking.receiver_phone = f"0002{i:06d}"
            if driver:
                booking.driver_accepted_lat, booking.driver_accepted_lng = coord(alat), coord(alng)
                booking.accepted_at = booked_at + timedelta(minutes=rng.uniform(0.5, 4))

            if status == BookingStatus.COMPLETED:
                pickup_minutes = float(fare.get("pickup_distance_km", 0)) / 20 * 60 + rng.uniform(1, 3)
                booking.arrived_at = booking.accepted_at + timedelta(minutes=pickup_minutes)
                booking.started_at = booking.arrived_at + timedelta(minutes=rng.uniform(1, 5))
                ride_minutes = hours * 60 + rng.uniform(-10, 10) if hours else fare["duration_min"] * rng.uniform(0.85, 1.3)
                booking.completed_at = booking.started_at + timedelta(minutes=ride_minutes)
                if rng.random() < 0.85:
                    booking.customer_rating = weighted({5: 62, 4: 28, 3: 7, 2: 2, 1: 1})
                if rng.random() < 0.70:
                    booking.driver_rating = weighted({5: 70, 4: 25, 3: 5})
                if payment == "wallet":
                    due = booking.final_amount or Decimal("0")
                    if balance[cust.id] < due:
                        await topup(cust, max(Decimal("2000"), Decimal(math.ceil((due - balance[cust.id]) / 1000) * 1000)),
                                    booked_at - timedelta(minutes=5))
                    balance[cust.id] -= due
                    db.add(WalletTransaction(user_id=cust.user_id, amount=due, type="debit",
                                             description=f"Payment for ride {ref}", reference_id=ref,
                                             balance_after=balance[cust.id], created_at=booking.completed_at))
            else:
                start = booking.accepted_at or booked_at
                booking.cancelled_at = start + timedelta(minutes=rng.uniform(1, 8))
                booking.cancelled_by = cancelled_by
                booking.cancellation_reason = rng.choice(CANCEL_REASONS[cancelled_by])

            db.add(booking)
            if stops:
                await db.flush()
                for k, stop in enumerate(stops, start=1):
                    db.add(BookingStop(booking_id=booking.id, order_index=k, lat=coord(stop["lat"]),
                                       lng=coord(stop["lng"]), address=stop["address"]))
            if i % 250 == 0:
                await db.flush()
            stats[status.value] += 1
            by_district[district] += 1
            by_case[case] += 1

        for cust in customers:
            cust.wallet_balance = balance[cust.id].quantize(Decimal("0.01"))
        await db.flush()

        # Driver and customer totals that the app normally keeps up to date itself.
        await db.execute(text("""
            UPDATE drivers d SET total_earnings = s.earned
            FROM (SELECT driver_id, sum(driver_earnings) AS earned FROM bookings
                  WHERE status = 'COMPLETED' GROUP BY driver_id) s
            WHERE d.id = s.driver_id"""))
        await db.execute(text("""
            UPDATE users u SET total_rides = s.trips, rating = coalesce(s.stars, 0)
            FROM (SELECT d.user_id, count(*) AS trips, round(avg(b.customer_rating)::numeric, 2) AS stars
                  FROM bookings b JOIN drivers d ON d.id = b.driver_id
                  WHERE b.status = 'COMPLETED' GROUP BY d.user_id) s
            WHERE u.id = s.user_id"""))
        await db.execute(text("""
            UPDATE users u SET total_rides = s.trips, rating = coalesce(s.stars, 0)
            FROM (SELECT c.user_id, count(*) AS trips, round(avg(b.driver_rating)::numeric, 2) AS stars
                  FROM bookings b JOIN customers c ON c.id = b.customer_id
                  WHERE b.status = 'COMPLETED' GROUP BY c.user_id) s
            WHERE u.id = s.user_id"""))
        await db.commit()

    print(f"   customers: {len(customers)} | drivers: {n} | trips: {len(plans)} | wallet top-ups: {topups}")
    print(f"   statuses: {dict(stats)}")
    print(f"   cases: {dict(by_case)}")
    print("   trips by pickup district: " + ", ".join(f"{d} {c}" for d, c in by_district.most_common()))


asyncio.run(main())

"""No lady driver: a Scooter ride switched to any driver also goes to Bike drivers
(Phase 2, feature 03). Other rides keep their own vehicle type; parcels go to any."""
from types import SimpleNamespace

from sqlalchemy import delete, select

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from app.models import Driver, DriverStatus, User, UserRole
from app.services.matching_service import dispatch_vehicles, find_all_nearby_drivers

PHONES = [f"07799903{i:02d}" for i in range(1, 5)]
PICKUP = (8.5024, 81.1812)


def _booking(service_type="moto scooter", include_bikes=False, is_flash=False, is_courier=False):
    return SimpleNamespace(service_type=service_type, include_bikes=include_bikes, is_flash=is_flash,
                           is_courier=is_courier)


def test_dispatch_vehicles():
    assert dispatch_vehicles(_booking()) == ["moto scooter"]
    assert dispatch_vehicles(_booking(include_bikes=True)) == ["moto scooter", "bike"]
    assert dispatch_vehicles(_booking("tuk")) == ["tuk"]
    assert dispatch_vehicles(_booking(is_flash=True, include_bikes=True)) is None, "parcels go to any vehicle"


async def _clean(db):
    users = select(User.id).where(User.phone_number.in_(PHONES))
    await db.execute(delete(Driver).where(Driver.user_id.in_(users)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


async def test_fallback_reaches_bike_drivers():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                ids = {}
                for phone, vehicle in zip(PHONES, ("moto scooter", "bike", "tuk", "car")):
                    u = User(phone_number=phone, role=UserRole.DRIVER, full_name=vehicle)
                    db.add(u)
                    await db.flush()
                    d = Driver(user_id=u.id, vehicle_type=vehicle, status=DriverStatus.APPROVED, is_approved=True,
                               is_online=True, current_lat=PICKUP[0] + 0.001, current_lng=PICKUP[1])
                    db.add(d)
                    await db.flush()
                    ids[vehicle] = d.id
                await db.commit()

                async def offered(booking):
                    found = await find_all_nearby_drivers(db, *PICKUP, dispatch_vehicles(booking), max_distance_km=2)
                    return {d.vehicle_type for d in found if d.id in ids.values()}

                assert await offered(_booking()) == {"moto scooter"}
                assert await offered(_booking(include_bikes=True)) == {"moto scooter", "bike"}
                assert await offered(_booking("tuk")) == {"tuk"}
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()

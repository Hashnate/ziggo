"""Genders for the lady-driver option (Phase 2, feature 03, stage A).

Drivers get theirs from the NIC, customers choose once in the app, and an admin
can correct either. A driver can ask for female passengers only if she is female
and rides a Scooter, the only vehicle lady drivers use.
"""
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlalchemy import delete, select

import app.models  # noqa: F401  (registers every table for create_all)
from app.api.v1.customer import update_profile
from app.api.v1.driver import FemalePassengersOnlyRequest, set_female_passengers_only
from app.database import AsyncSessionLocal, Base, engine
from app.models import Customer, Driver, DriverStatus, User, UserRole
from app.schemas import UserUpdate
from app.services.gender_service import (
    FEMALE_PASSENGERS_ONLY,
    LADY_DRIVER_REQUESTED,
    apply_driver_gender,
    apply_nic_gender,
    gender_from_nic,
    is_lady_driver_service,
    refusal_for_driver,
    set_admin_gender,
)
from app.services.matching_service import drivers_for_customer
from app.services.schema_sync import _backfill_driver_genders

PHONES = [f"07799900{i:02d}" for i in range(1, 7)]


@pytest.mark.parametrize("nic, expected", [
    ("853202937V", "male"),        # old format, day 320
    ("858202937V", "female"),      # old format, day 820 = 320 + 500
    ("858202937x", "female"),
    ("850012937V", "male"),        # day 1
    ("853662937V", "male"),        # day 366
    ("855012937V", "female"),      # day 501
    ("858662937V", "female"),      # day 866
    ("853672937V", None),          # 367..500 is not a day
    ("855002937V", None),
    ("850002937V", None),
    ("858672937V", None),
    ("199032002937", "male"),      # new format, day 320
    ("199082002937", "female"),
    ("1990 820 02937", "female"),
    ("1990-820-02937", "female"),
    ("85820293V", None),           # too short
    ("8582029371V", None),
    ("ABC", None),
    ("", None),
    (None, None),
])
def test_gender_from_nic(nic, expected):
    assert gender_from_nic(nic) == expected


@pytest.mark.parametrize("driver, fpo, customer, lady, expected", [
    ("female", False, "female", True, None),
    ("male", False, "female", True, LADY_DRIVER_REQUESTED),
    (None, False, "female", True, LADY_DRIVER_REQUESTED),       # unknown gender is not a lady driver
    ("male", False, "male", False, None),
    ("female", True, "female", False, None),
    ("female", True, "female", True, None),
    ("female", True, "male", False, FEMALE_PASSENGERS_ONLY),
    ("female", True, None, False, FEMALE_PASSENGERS_ONLY),       # customer who hasn't said is not female
    ("male", True, "male", False, None),                        # the switch means nothing for a man
    ("female", False, "male", False, None),
])
def test_who_may_take_a_ride(driver, fpo, customer, lady, expected):
    assert refusal_for_driver(driver, fpo, customer, lady) == expected


@pytest.mark.parametrize("service, expected", [
    ("moto scooter", True), (" Moto Scooter ", True), ("tuk", False), ("bike", False), ("car", False), (None, False),
])
def test_lady_drivers_ride_scooters(service, expected):
    assert is_lady_driver_service(service) is expected


def _person(gender=None, source=None):
    return SimpleNamespace(gender=gender, gender_source=source)


@pytest.mark.parametrize("nic, chosen, before, expected, refused", [
    ("858202937V", "female", (None, None), ("female", "nic"), False),       # NIC agrees
    ("858202937V", None, (None, None), ("female", "nic"), False),           # older app: NIC alone, as before
    ("858202937V", "male", (None, None), (None, None), True),               # NIC says female
    ("199032002937", "female", (None, None), (None, None), True),           # NIC says male
    ("2000245065403", "female", (None, None), ("female", "self"), False),   # 13 digits: NIC unreadable, choice kept
    ("garbage", "Male", ("female", "self"), ("male", "self"), False),       # re-submitted with another choice
    ("garbage", None, ("female", "self"), ("female", "self"), False),       # nothing to go on: unchanged
    ("garbage", "other", (None, None), (None, None), False),                # only female/male count
    ("858202937V", "male", ("male", "admin"), ("male", "admin"), False),    # the admin's say stands
])
def test_driver_signup_gender(nic, chosen, before, expected, refused):
    user = SimpleNamespace(gender=before[0], gender_source=before[1])
    refusal = apply_driver_gender(user, nic, chosen)
    assert (refusal is not None) == refused
    if refused:
        assert "NIC" in refusal and (user.gender, user.gender_source) == before
    assert (user.gender, user.gender_source) == expected


def test_nic_follows_unless_admin_set_it():
    p = _person()
    apply_nic_gender(p, "858202937V")
    assert (p.gender, p.gender_source) == ("female", "nic")
    apply_nic_gender(p, "853202937V")
    assert (p.gender, p.gender_source) == ("male", "nic"), "a corrected NIC changes the gender"
    apply_nic_gender(p, "not a nic")
    assert (p.gender, p.gender_source) == ("male", "nic"), "an unreadable NIC changes nothing"

    p = _person("male", "self")
    apply_nic_gender(p, "858202937V")
    assert (p.gender, p.gender_source) == ("female", "nic"), "the NIC beats the customer's own choice"

    p = _person("female", "admin")
    apply_nic_gender(p, "853202937V")
    assert (p.gender, p.gender_source) == ("female", "admin"), "an admin's choice is never overridden"


def test_admin_corrections():
    p = _person("male", "nic")
    set_admin_gender(p, "female", "853202937V")
    assert (p.gender, p.gender_source) == ("female", "admin")
    set_admin_gender(p, "auto", "853202937V")
    assert (p.gender, p.gender_source) == ("male", "nic"), "auto goes back to the NIC"

    p = _person("female", "admin")
    set_admin_gender(p, "auto", "bad nic")
    assert (p.gender, p.gender_source) == (None, None), "auto with an unreadable NIC leaves it empty"

    p = _person("female", "self")
    set_admin_gender(p, "none")
    assert (p.gender, p.gender_source) == (None, None), "none lets the customer choose again"

    p = _person("female", "self")
    set_admin_gender(p, "auto", None)
    assert (p.gender, p.gender_source) == ("female", "self"), "auto keeps a customer's choice when there is no NIC"


async def _clean(db):
    ids = select(User.id).where(User.phone_number.in_(PHONES))
    await db.execute(delete(Driver).where(Driver.user_id.in_(ids)))
    await db.execute(delete(Customer).where(Customer.user_id.in_(ids)))
    await db.execute(delete(User).where(User.phone_number.in_(PHONES)))
    await db.commit()


async def test_profiles_backfill_and_switch():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        async with AsyncSessionLocal() as db:
            await _clean(db)
            try:
                people = {}
                for phone, role, nic, gender, source, vehicle in [
                    (PHONES[0], UserRole.DRIVER, "858202937V", None, None, "moto scooter"),
                    (PHONES[1], UserRole.DRIVER, "199032002937", None, None, "moto scooter"),
                    (PHONES[2], UserRole.DRIVER, "858202938V", "male", "admin", "moto scooter"),
                    (PHONES[3], UserRole.DRIVER, "garbage", None, None, "tuk"),
                    (PHONES[4], UserRole.CUSTOMER, None, None, None, None),
                    (PHONES[5], UserRole.DRIVER, "858202939V", None, None, "tuk"),
                ]:
                    u = User(phone_number=phone, role=role, full_name=phone, gender=gender, gender_source=source)
                    db.add(u)
                    await db.flush()
                    if role == UserRole.DRIVER:
                        db.add(Driver(user_id=u.id, nic_number=nic, status=DriverStatus.APPROVED, is_approved=True,
                                      vehicle_type=vehicle))
                    else:
                        db.add(Customer(user_id=u.id))
                    people[phone] = u.id
                await db.commit()

                async with engine.begin() as conn:
                    await _backfill_driver_genders(conn)
                got = {p: tuple(r) for p, *r in (await db.execute(
                    select(User.phone_number, User.gender, User.gender_source).where(User.phone_number.in_(PHONES))
                )).all()}
                assert got[PHONES[0]] == ("female", "nic")
                assert got[PHONES[1]] == ("male", "nic")
                assert got[PHONES[2]] == ("male", "admin"), "backfill leaves an admin's choice alone"
                assert got[PHONES[3]] == (None, None)
                assert got[PHONES[4]] == (None, None), "customers are never guessed"
                assert got[PHONES[5]] == ("female", "nic")

                customer = await db.get(User, people[PHONES[4]])
                await update_profile(UserUpdate(full_name="Amali"), db, customer)
                assert customer.gender is None, "saving other fields doesn't set a gender"
                for older_app_value in ("Female", "Male", "Prefer not to say"):
                    await update_profile(UserUpdate(gender=older_app_value), db, customer)
                    assert customer.gender is None, \
                        f"older apps' '{older_app_value}' is ignored: they don't warn that it locks"
                await update_profile(UserUpdate(gender="female"), db, customer)
                assert (customer.gender, customer.gender_source) == ("female", "self")
                await update_profile(UserUpdate(gender="female", full_name="Amali P"), db, customer)
                assert customer.gender == "female", "sending the same gender again is fine"
                for older_app_value in ("Male", "Female", "Other"):
                    await update_profile(UserUpdate(gender=older_app_value), db, customer)
                assert (customer.gender, customer.gender_source) == ("female", "self"), \
                    "older apps can't change it either, and get no error they can't show"
                with pytest.raises(HTTPException) as e:
                    await update_profile(UserUpdate(gender="male"), db, customer)
                assert e.value.status_code == 400 and "support" in e.value.detail
                await db.rollback()
                customer = await db.get(User, people[PHONES[4]])
                assert customer.gender == "female", "a refused change leaves the gender as it was"

                lady = await db.get(User, people[PHONES[0]])
                res = await set_female_passengers_only(FemalePassengersOnlyRequest(enabled=True), db, lady)
                assert res.female_passengers_only is True and res.gender == "female"
                res = await set_female_passengers_only(FemalePassengersOnlyRequest(enabled=False), db, lady)
                assert res.female_passengers_only is False

                man = await db.get(User, people[PHONES[1]])
                with pytest.raises(HTTPException) as e:
                    await set_female_passengers_only(FemalePassengersOnlyRequest(enabled=True), db, man)
                assert e.value.status_code == 400
                await db.rollback()
                man = await db.get(User, people[PHONES[1]])
                res = await set_female_passengers_only(FemalePassengersOnlyRequest(enabled=False), db, man)
                assert res.female_passengers_only is False, "anyone can switch it off"

                tuk_lady = await db.get(User, people[PHONES[5]])
                with pytest.raises(HTTPException) as e:
                    await set_female_passengers_only(FemalePassengersOnlyRequest(enabled=True), db, tuk_lady)
                assert e.value.status_code == 400 and "Scooter" in e.value.detail, "a lady on a tuk can't"
                await db.rollback()

                lady_d, man_d, ladmin_d, tuk_lady_d = [
                    (await db.execute(select(Driver).where(Driver.user_id == people[p]))).scalars().one()
                    for p in (PHONES[0], PHONES[1], PHONES[2], PHONES[5])
                ]
                lady_d.female_passengers_only = True
                tuk_lady_d.female_passengers_only = True  # chosen on a scooter, then moved to a tuk
                await db.commit()
                pool = [lady_d, man_d, ladmin_d]  # ladmin: female NIC, but an admin made him male

                async def offered(customer_gender, lady, passenger=True):
                    return [d.id for d in await drivers_for_customer(db, pool, customer_gender, lady, passenger)]

                assert await offered("female", True) == [lady_d.id], "lady driver ride: only the woman"
                assert await offered("female", False) == [d.id for d in pool]
                assert await offered("male", False) == [man_d.id, ladmin_d.id], "female-only lady skips a man"
                assert await offered(None, False) == [man_d.id, ladmin_d.id], "and a customer with no gender"
                assert await offered("male", False, passenger=False) == [d.id for d in pool], "parcels unchanged"
                assert await drivers_for_customer(db, [], "female", True, True) == []
                tuk_pool = await drivers_for_customer(db, [tuk_lady_d], "male", False, True)
                assert tuk_pool == [tuk_lady_d], "female passengers only counts on a Scooter only"

                tuk_lady = await db.get(User, people[PHONES[5]])
                res = await set_female_passengers_only(FemalePassengersOnlyRequest(enabled=False), db, tuk_lady)
                assert res.female_passengers_only is False
            finally:
                await db.rollback()
                await _clean(db)
    finally:
        await engine.dispose()

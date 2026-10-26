"""Gender on a user's profile, for the lady-driver option (Phase 2, feature 03).

``users.gender`` is "female", "male" or empty. ``users.gender_source`` says who set it:
- "nic": read from a driver's NIC; follows the NIC whenever it changes.
- "self": chosen once by the customer in the app; after that only an admin can change it.
- "admin": set by an admin; nothing else overrides it.
"""
import re

FEMALE = "female"
MALE = "male"
GENDERS = (FEMALE, MALE)

SOURCE_NIC = "nic"
SOURCE_SELF = "self"
SOURCE_ADMIN = "admin"

GENDER_LOCKED_MESSAGE = "Your gender is already set. Please contact Ziggo support to change it."


def gender_from_nic(nic: str | None) -> str | None:
    """Sri Lankan NICs carry the day of birth in the year, plus 500 for women.
    Old format: YY DDD NNNN V/X (DDD at 2..5). New format: YYYY DDD NNNNN (DDD at 4..7)."""
    s = re.sub(r"[\s-]", "", nic or "").upper()
    if re.fullmatch(r"\d{9}[VX]", s):
        days = int(s[2:5])
    elif re.fullmatch(r"\d{12}", s):
        days = int(s[4:7])
    else:
        return None
    if 1 <= days <= 366:
        return MALE
    if 501 <= days <= 866:
        return FEMALE
    return None


def apply_nic_gender(user, nic: str | None) -> None:
    """Set a driver's gender from their NIC unless an admin has set it by hand.
    An NIC that can't be read leaves the gender as it was."""
    if user is None or user.gender_source == SOURCE_ADMIN:
        return
    g = gender_from_nic(nic)
    if g:
        user.gender = g
        user.gender_source = SOURCE_NIC


def set_admin_gender(user, choice: str, nic: str | None = None) -> None:
    """Admin correction. ``choice`` is "female"/"male" (fixed by the admin), "auto"
    (drivers: follow the NIC again) or "none" (customers: empty, so they can choose again)."""
    choice = (choice or "").strip().lower()
    if choice in GENDERS:
        user.gender = choice
        user.gender_source = SOURCE_ADMIN
        return
    if choice == "auto" and user.gender_source != SOURCE_ADMIN:
        apply_nic_gender(user, nic)
        return
    user.gender = None
    user.gender_source = None
    if choice == "auto":
        apply_nic_gender(user, nic)


def gender_label(user) -> str:
    g = (user.gender or "").capitalize() if user is not None else ""
    return g or "Not set"


# ── Who may be offered a trip (stage B) ──────────────────────────────────────
# Both rules apply to Scooter rides only (incl. rentals and return trips): lady
# drivers ride scooters. Other vehicles, parcels and couriers are dispatched as before.

LADY_DRIVER_SERVICE = "moto scooter"
# When no lady driver takes a Scooter ride and the customer chooses any driver,
# Bike drivers are offered it too (Booking.include_bikes).
FALLBACK_BIKE = "bike"

LADY_DRIVER_RIDES_ONLY = "A lady driver can only be requested for rides."
LADY_DRIVER_SCOOTER_ONLY = "A lady driver can only be requested for Scooter rides."
FEMALE_PASSENGERS_SCOOTER_ONLY = "Only lady Scooter drivers can choose female passengers only."
LADY_DRIVER_FEMALE_ONLY = "Only customers whose profile says female can ask for a lady driver."
NO_LADY_DRIVER_MESSAGE = ("No lady driver is available nearby right now. "
                          "You can book with any Scooter or Bike driver instead.")
LADY_DRIVER_REQUESTED = "This customer asked for a lady driver."
FEMALE_PASSENGERS_ONLY = "You chose female passengers only."


def is_passenger_trip(is_flash, is_courier) -> bool:
    return not (is_flash or is_courier)


def is_lady_driver_service(service_type) -> bool:
    return (service_type or "").strip().lower() == LADY_DRIVER_SERVICE


def female_passengers_only(driver) -> bool:
    """The driver's "female passengers only" choice, which counts only while she rides a
    Scooter; a driver moved to another vehicle keeps the stored choice for if she comes back."""
    return bool(driver.female_passengers_only) and is_lady_driver_service(driver.vehicle_type)


def refusal_for_driver(driver_gender, female_passengers_only, customer_gender, lady_driver_requested) -> str | None:
    """Why this driver may not take this ride, or None if she or he may."""
    if lady_driver_requested and driver_gender != FEMALE:
        return LADY_DRIVER_REQUESTED
    if female_passengers_only and driver_gender == FEMALE and customer_gender != FEMALE:
        return FEMALE_PASSENGERS_ONLY
    return None


def no_driver_payload(booking) -> dict:
    """The `no_drivers_available` event; a lady-driver ride says why and that any driver is an option."""
    payload = {"booking_id": booking.id, "booking_ref": booking.booking_ref}
    if booking.lady_driver_requested:
        payload.update(lady_driver=True, message=NO_LADY_DRIVER_MESSAGE)
    return payload


def search_timeout_reason(booking) -> str:
    if booking.lady_driver_requested:
        return "No lady driver available within search window"
    return "No driver available within search window"

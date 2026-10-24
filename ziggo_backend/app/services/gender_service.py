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

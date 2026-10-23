"""Launch locations (Phase 2, feature 02): which jobs fall in an active one."""
from datetime import date
from types import SimpleNamespace

from app.services.launch_service import match, status_of

KINNIYA = (8.4970, 81.1800)       # Trincomalee district
TRINCO_TOWN = (8.5874, 81.2152)   # Trincomalee district, ~10 km away
BATTICALOA = (7.7310, 81.6747)
# A drawn box around Kinniya only.
KINNIYA_BOX = [{"lat": 8.45, "lng": 81.14}, {"lat": 8.45, "lng": 81.22},
               {"lat": 8.54, "lng": 81.22}, {"lat": 8.54, "lng": 81.14}]
START, END = date(2026, 11, 1), date(2026, 11, 30)


def loc(**kw):
    base = dict(id=1, kind="district", district="Trincomalee", coordinates=None, start_date=START, end_date=END,
                services=["rides", "parcels"], is_active=True)
    return SimpleNamespace(**{**base, **kw})


def test_whole_district():
    l = loc()
    assert match([l], *KINNIYA, "rides", date(2026, 11, 10)) is l
    assert match([l], *TRINCO_TOWN, "rides", date(2026, 11, 10)) is l
    assert match([l], *BATTICALOA, "rides", date(2026, 11, 10)) is None


def test_drawn_area():
    l = loc(kind="area", district=None, coordinates=KINNIYA_BOX)
    assert match([l], *KINNIYA, "rides", date(2026, 11, 10)) is l
    assert match([l], *TRINCO_TOWN, "rides", date(2026, 11, 10)) is None


def test_dates_are_inclusive():
    l = loc()
    for day, inside in ((date(2026, 10, 31), False), (START, True), (date(2026, 11, 15), True),
                        (END, True), (date(2026, 12, 1), False)):
        assert (match([l], *KINNIYA, "rides", day) is l) == inside, day


def test_only_ticked_services():
    l = loc(services=["rides"])
    assert match([l], *KINNIYA, "rides", date(2026, 11, 10)) is l
    assert match([l], *KINNIYA, "parcels", date(2026, 11, 10)) is None
    assert match([l], *KINNIYA, "food", date(2026, 11, 10)) is None


def test_switched_off():
    l = loc(is_active=False)
    assert match([l], *KINNIYA, "rides", date(2026, 11, 10)) is None
    assert status_of(l, date(2026, 11, 10)) == "off"


def test_status():
    l = loc()
    assert status_of(l, date(2026, 10, 1)) == "upcoming"
    assert status_of(l, START) == "active"
    assert status_of(l, END) == "active"
    assert status_of(l, date(2026, 12, 1)) == "ended"


def test_first_matching_location_wins_and_missing_points():
    a = loc(id=1, kind="area", district=None, coordinates=KINNIYA_BOX)
    b = loc(id=2)
    assert match([a, b], *KINNIYA, "rides", date(2026, 11, 10)) is a
    assert match([a, b], *TRINCO_TOWN, "rides", date(2026, 11, 10)) is b
    assert match([a, b], None, None, "rides", date(2026, 11, 10)) is None
    assert match([loc(kind="area", district=None, coordinates=KINNIYA_BOX[:2])], *KINNIYA, "rides",
                 date(2026, 11, 10)) is None

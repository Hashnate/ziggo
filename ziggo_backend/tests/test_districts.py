"""District lookup: every district's towns, border and shoreline points, and the sea."""
import pytest

from app.services.district_service import DISTRICTS, _outlines, district_for

TOWNS = {
    "Colombo": [(6.9344, 79.8500), (6.8942, 79.8580), (6.9147, 79.8778), (6.8649, 79.8997), (6.8480, 79.9265),
                (6.9094, 79.8939), (6.8511, 79.8700), (6.7730, 79.8822), (6.8412, 79.9654), (6.8441, 80.0024),
                (6.9330, 79.9850), (6.8746, 79.8640)],
    "Gampaha": [(7.0917, 79.9997), (7.2008, 79.8737), (7.0010, 79.9530), (7.0744, 79.8919), (6.9897, 79.8925),
                (6.9800, 79.9290), (7.1660, 79.9530)],
    "Kalutara": [(6.5854, 79.9650), (6.7132, 79.9070), (6.7159, 80.0626), (6.4788, 79.9900), (6.5215, 80.1137)],
    "Kandy": [(7.2906, 80.6337), (7.2690, 80.5970), (7.3370, 80.6250), (7.1643, 80.5696), (7.2810, 80.6900)],
    "Matale": [(7.4675, 80.6234), (7.8742, 80.6511)],
    "Nuwara Eliya": [(6.9497, 80.7891), (6.8916, 80.5955)],
    "Galle": [(6.0535, 80.2210), (6.1395, 80.1100), (6.2355, 80.0580), (6.0640, 80.2290)],
    "Matara": [(5.9549, 80.5500), (5.9746, 80.4330), (6.0950, 80.4760)],
    "Hambantota": [(6.1241, 81.1100), (6.0240, 80.7940), (6.2786, 81.2876)],
    "Jaffna": [(9.6615, 80.0255), (9.6580, 80.1630), (9.8100, 80.2333)],
    "Kilinochchi": [(9.3803, 80.3770)],
    "Mannar": [(8.9770, 79.9100), (8.8360, 80.0560)],
    "Vavuniya": [(8.7514, 80.4971)],
    "Mullaitivu": [(9.3170, 80.7130), (9.2671, 80.8000)],
    "Batticaloa": [(7.7310, 81.6747), (7.7730, 81.6040), (7.6750, 81.7290)],
    "Ampara": [(7.2975, 81.6820), (7.4167, 81.8100), (7.2167, 81.8450)],
    "Trincomalee": [(8.5874, 81.2152), (8.4970, 81.1800), (8.3700, 80.9700)],
    "Kurunegala": [(7.4863, 80.3647), (7.4688, 80.0401), (7.4320, 80.2150)],
    "Puttalam": [(8.0362, 79.8400), (7.5758, 79.8050), (7.3500, 79.8500)],
    "Anuradhapura": [(8.3114, 80.4037), (8.0380, 80.5980)],
    "Polonnaruwa": [(7.9403, 81.0188), (8.0400, 80.9500)],
    "Badulla": [(6.9934, 81.0550), (6.8259, 80.9982), (7.3270, 81.0010)],
    "Monaragala": [(6.8728, 81.3507), (6.7370, 81.1020), (7.1600, 81.2200)],
    "Ratnapura": [(6.6828, 80.3992), (6.3430, 80.8490), (6.6480, 80.6970)],
    "Kegalle": [(7.2513, 80.3464), (7.2520, 80.4460), (7.2270, 80.1970)],
}
# Right next to a district boundary.
BORDER = [("Gampaha", 6.9553, 79.9220), ("Gampaha", 6.9650, 79.8850), ("Colombo", 6.9330, 79.9850),
          ("Colombo", 6.7880, 79.8800), ("Kalutara", 6.7400, 79.9050), ("Kandy", 7.2550, 80.5230),
          ("Colombo", 6.9533, 80.2100), ("Kegalle", 7.0430, 80.2560),
          # Across Bolgoda Lake from Moratuwa town: Kalutara district, not Colombo.
          ("Kalutara", 6.7730, 79.8900)]
# On the shoreline, where the simplified outlines can stop a few metres short.
COAST = [("Colombo", 6.9235, 79.8456), ("Colombo", 6.8390, 79.8630), ("Gampaha", 7.2150, 79.8350),
         ("Galle", 6.0098, 80.2491), ("Trincomalee", 8.6970, 81.1880), ("Ampara", 6.8400, 81.8360)]


def test_file_has_exactly_the_25_districts():
    assert sorted(name for name, _, _ in _outlines()) == sorted(DISTRICTS)


@pytest.mark.parametrize("want,lat,lng", [(d, la, ln) for d, pts in TOWNS.items() for la, ln in pts] + BORDER + COAST)
def test_point_is_in_its_district(want, lat, lng):
    assert district_for(lat, lng) == want


def test_every_district_is_covered_by_a_town():
    assert set(TOWNS) == set(DISTRICTS)


@pytest.mark.parametrize("lat,lng", [
    (6.90, 79.60),    # 25 km off Colombo
    (13.0827, 80.2707),  # Chennai, India
    (0.0, 0.0),
])
def test_no_district_outside_sri_lanka(lat, lng):
    assert district_for(lat, lng) is None


def test_missing_coordinates():
    assert district_for(None, 79.85) is None
    assert district_for(6.9, None) is None

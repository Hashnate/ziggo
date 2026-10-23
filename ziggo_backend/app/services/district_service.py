"""Which of Sri Lanka's 25 districts a point is in.

Outlines: app/data/lk_districts.geojson (© OpenStreetMap contributors, ODbL —
see app/data/LK_DISTRICTS_LICENSE.txt). The outlines are simplified, so a point
on the beach or a jetty can fall just outside every district; those go to the
nearest district if it's within COASTAL_SNAP_KM. Points further out (sea, India)
have no district.
"""
import json
from functools import lru_cache
from pathlib import Path
from typing import Optional

from shapely.geometry import Point, shape
from shapely.prepared import prep

DISTRICTS = (
    "Ampara", "Anuradhapura", "Badulla", "Batticaloa", "Colombo", "Galle", "Gampaha",
    "Hambantota", "Jaffna", "Kalutara", "Kandy", "Kegalle", "Kilinochchi", "Kurunegala",
    "Mannar", "Matale", "Matara", "Monaragala", "Mullaitivu", "Nuwara Eliya",
    "Polonnaruwa", "Puttalam", "Ratnapura", "Trincomalee", "Vavuniya",
)
COASTAL_SNAP_KM = 3.0
_KM_PER_DEGREE = 111.0
_DATA = Path(__file__).resolve().parent.parent / "data" / "lk_districts.geojson"


@lru_cache(maxsize=1)
def _outlines():
    features = json.loads(_DATA.read_text())["features"]
    out = []
    for f in features:
        geom = shape(f["geometry"])
        out.append((f["properties"]["district"], geom, prep(geom)))
    return tuple(out)


def district_for(lat: Optional[float], lng: Optional[float]) -> Optional[str]:
    """The district containing (lat, lng), or None if it's not in Sri Lanka."""
    if lat is None or lng is None:
        return None
    p = Point(float(lng), float(lat))
    outlines = _outlines()
    for name, _, prepared in outlines:
        if prepared.contains(p):
            return name
    name, geom, _ = min(outlines, key=lambda o: o[1].distance(p))
    return name if geom.distance(p) * _KM_PER_DEGREE <= COASTAL_SNAP_KM else None

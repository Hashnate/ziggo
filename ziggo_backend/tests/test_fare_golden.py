"""Fare engine tests.

test_fares_match_recorded_results: every scenario must return exactly the
recorded result. A failure means a price changed; if that was intended,
re-record the golden file (see record_fare_golden.py) and review its diff.

test_vehicle_cards_match_booking: in every scenario, each vehicle card
(calculate_fares_bulk) must show the same values as booking that vehicle
(calculate_fare).
"""
import json
from pathlib import Path

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from fare_cases import build_cases, install, run_case

GOLDEN = Path(__file__).parent / "golden" / "fare_results.jsonl"
_results: dict = {}


async def _run_all() -> dict:
    """Run every scenario once per test session and keep the JSON-safe results."""
    if not _results:
        results = {}
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        try:
            async with AsyncSessionLocal() as db:
                variant = None
                for case in build_cases():
                    if case["variant"] != variant:
                        variant = case["variant"]
                        await install(db, variant)
                    results[case["id"]] = json.loads(json.dumps(await run_case(db, case)))
        finally:
            await engine.dispose()
        _results.update(results)
    return _results


def _describe(case_id: str, expected, actual) -> str:
    if not (isinstance(expected, dict) and isinstance(actual, dict)):
        return f"{case_id}: expected {expected!r}, got {actual!r}"
    keys = sorted(set(expected) | set(actual), key=str)
    diffs = [f"{k}: {expected.get(k, '<missing>')!r} -> {actual.get(k, '<missing>')!r}"
             for k in keys if expected.get(k, "<missing>") != actual.get(k, "<missing>")]
    return f"{case_id}: " + "; ".join(diffs[:6])


async def test_fares_match_recorded_results():
    expected = {}
    for line in GOLDEN.read_text().splitlines():
        row = json.loads(line)
        expected[row["id"]] = row["result"]
    actual = await _run_all()
    assert list(actual) == list(expected), "scenario list differs from the recording"
    changed = [_describe(i, expected[i], actual[i]) for i in expected if actual[i] != expected[i]]
    assert not changed, f"{len(changed)} of {len(actual)} scenarios changed:\n" + "\n".join(changed[:10])


async def test_vehicle_cards_match_booking():
    results = await _run_all()
    mismatches, checked = [], 0
    for case_id, cards in results.items():
        parts = case_id.split("|")
        if parts[1] != "bulk":
            continue
        variant, _, at, name = parts
        for service_type, card in cards.items():
            booking = results[f"{variant}|single|{at}|{service_type}|{name}"]
            shared = sorted((set(card) & set(booking)) - {"service_type"})
            checked += 1
            diffs = {k: (card[k], booking[k]) for k in shared if card[k] != booking[k]}
            if diffs:
                mismatches.append(f"{case_id} [{service_type}] card vs booking: {diffs}")
    assert checked > 0
    assert not mismatches, f"{len(mismatches)} of {checked} cards differ from booking:\n" + "\n".join(mismatches[:10])

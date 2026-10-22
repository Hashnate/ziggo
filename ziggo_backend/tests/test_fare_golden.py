"""The fare engine must return exactly the recorded result for every scenario.

A failure means a price changed. If that was intended, re-record the golden
file (see record_fare_golden.py) and review its diff.
"""
import json
from pathlib import Path

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from fare_cases import build_cases, install, run_case

GOLDEN = Path(__file__).parent / "golden" / "fare_results.jsonl"


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
    cases = build_cases()
    assert [c["id"] for c in cases] == list(expected), "scenario list differs from the recording"

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    changed = []
    try:
        async with AsyncSessionLocal() as db:
            variant = None
            for case in cases:
                if case["variant"] != variant:
                    variant = case["variant"]
                    await install(db, variant)
                actual = json.loads(json.dumps(await run_case(db, case)))
                if actual != expected[case["id"]]:
                    changed.append(_describe(case["id"], expected[case["id"]], actual))
    finally:
        await engine.dispose()
    assert not changed, f"{len(changed)} of {len(cases)} scenarios changed:\n" + "\n".join(changed[:10])

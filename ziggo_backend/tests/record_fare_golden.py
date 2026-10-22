"""Record what the current fare engine returns for every scenario in fare_cases.

The golden test then holds the engine to these exact results. Re-record only
when prices are meant to change, and review the diff of the golden file:

    deploy/staging/run-backend-tests.sh record-fare-golden
"""
import asyncio
import json
from pathlib import Path

import app.models  # noqa: F401  (registers every table for create_all)
from app.database import AsyncSessionLocal, Base, engine
from fare_cases import build_cases, install, run_case

GOLDEN = Path(__file__).parent / "golden" / "fare_results.jsonl"


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    lines = []
    try:
        async with AsyncSessionLocal() as db:
            variant = None
            for case in build_cases():
                if case["variant"] != variant:
                    variant = case["variant"]
                    await install(db, variant)
                result = await run_case(db, case)
                lines.append(json.dumps({"id": case["id"], "result": result}, sort_keys=True))
    finally:
        await engine.dispose()
    GOLDEN.parent.mkdir(exist_ok=True)
    GOLDEN.write_text("\n".join(lines) + "\n")
    print(f"Recorded {len(lines)} scenarios to {GOLDEN.relative_to(Path.cwd())}")


asyncio.run(main())

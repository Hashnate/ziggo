"""One-shot migration: copy every row from ziggo.db (SQLite) into the
PostgreSQL database currently configured in .env.

(ASCII-only output so it runs cleanly under the Windows cp1252 console.)

How it works:
  1. Verifies the Postgres URL is actually Postgres (not SQLite).
  2. Calls ensure_schema() on the Postgres connection so all tables + the
     flash-weight-tier seeds exist (idempotent).
  3. TRUNCATEs every table on Postgres with RESTART IDENTITY CASCADE so we
     start from a clean slate (necessary because schema_sync seeds a few
     rows on first boot — without truncating we'd get duplicates).
  4. Copies rows table-by-table in FK-safe order using
     Base.metadata.sorted_tables.
  5. Bumps Postgres sequences to MAX(id)+1 so the next INSERT from the
     running app doesn't collide with the IDs we just copied.

Safety:
  - Reads from ziggo.db only — never modifies SQLite.
  - Asks for confirmation before truncating Postgres.
  - If anything fails partway, just re-run; truncate makes it idempotent.

Usage:
  cd ziggo_backend
  python sqlite_to_postgres.py
"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from sqlalchemy import create_engine, select, text
from sqlalchemy.exc import OperationalError, ProgrammingError

# Make sure models are imported so Base.metadata is populated.
from app import models  # noqa: F401 — needed for side-effect import of all models
from app.config import settings
from app.database import Base, engine as async_pg_engine
from app.services.schema_sync import ensure_schema


SQLITE_PATH = Path(__file__).parent / "ziggo.db"
SQLITE_URL = f"sqlite:///{SQLITE_PATH}"


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def banner(msg: str, char: str = "=") -> None:
    print()
    print(char * 72)
    print(f" {msg}")
    print(char * 72)


def confirm(prompt: str) -> bool:
    """Yes/no prompt; defaults to no on Enter."""
    ans = input(f"{prompt} [y/N]: ").strip().lower()
    return ans in ("y", "yes")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> int:
    banner("Ziggo SQLite -> Postgres migration")

    # ---- Sanity check: must be configured for Postgres ----
    pg_url = settings.SYNC_DATABASE_URL
    if not pg_url.startswith("postgresql"):
        print(
            "ERROR: SYNC_DATABASE_URL in .env is not Postgres.\n"
            f"       Currently: {pg_url}\n"
            "       Switch the .env to Postgres URLs first, then re-run."
        )
        return 1

    if not SQLITE_PATH.exists():
        print(f"ERROR: SQLite file not found at {SQLITE_PATH}")
        return 1

    print(f"Source : {SQLITE_URL}")
    print(f"Target : {pg_url.split('@')[-1]}  (Postgres)")
    print()

    # ---- 1. Ensure schema on Postgres (creates tables + ENUM types + seeds) ----
    print("-> Creating schema on Postgres (idempotent)...")
    try:
        await ensure_schema(async_pg_engine)
    except Exception as e:
        print(f"ERROR while creating Postgres schema: {e}")
        return 1
    print("  OK")

    # ---- 2. Confirm before destructive truncate ----
    print()
    print("This will TRUNCATE every table in the Postgres `ziggo` database")
    print("and replace its contents with the data from ziggo.db.")
    if not confirm("Proceed?"):
        print("Aborted.")
        return 1

    # ---- 3. Open both connections (sync — easier for bulk copy) ----
    src_engine = create_engine(SQLITE_URL, future=True)
    dst_engine = create_engine(pg_url, future=True)

    tables_in_dep_order = list(Base.metadata.sorted_tables)
    # FlashWeightTier is seeded by ensure_schema; if SQLite has rows for it
    # we still want to overwrite with SQLite's data, so include it. The
    # TRUNCATE in step 4 will clear the seeded rows first.

    # ---- 4. Truncate target ----
    banner("Truncating Postgres tables", "-")
    with dst_engine.begin() as conn:
        # Need to disable triggers/FKs or use CASCADE.
        # Build one single TRUNCATE statement listing all tables, with CASCADE.
        names = ", ".join(f'"{t.name}"' for t in tables_in_dep_order)
        try:
            conn.execute(text(f"TRUNCATE TABLE {names} RESTART IDENTITY CASCADE"))
            print(f"  Truncated {len(tables_in_dep_order)} tables.")
        except (OperationalError, ProgrammingError) as e:
            print(f"ERROR truncating: {e}")
            return 1

    # ---- 5. Copy table-by-table in dependency order ----
    banner("Copying rows", "-")
    src_meta_tables = {}  # cache of (table_name → set of column names that exist in SQLite)

    with src_engine.connect() as src_conn:
        # Find which tables actually exist in the SQLite DB and what
        # columns they have. Older SQLite databases may not have every
        # column that Base.metadata has (schema_sync adds them on boot to
        # whichever DB the app actually connects to).
        existing = src_conn.execute(
            text("SELECT name FROM sqlite_master WHERE type='table'")
        ).scalars().all()
        for tname in existing:
            cols = src_conn.execute(text(f"PRAGMA table_info({tname})")).all()
            src_meta_tables[tname] = {row[1] for row in cols}

    total_rows = 0
    with src_engine.connect() as src_conn, dst_engine.begin() as dst_conn:
        for table in tables_in_dep_order:
            tname = table.name
            if tname not in src_meta_tables:
                print(f"  [skip]  {tname}  (not in SQLite)")
                continue

            src_cols = src_meta_tables[tname]
            # Intersect with model columns so we only SELECT what exists in both.
            shared_cols = [c.name for c in table.columns if c.name in src_cols]
            if not shared_cols:
                print(f"  [skip]  {tname}  (no shared columns)")
                continue

            col_list = ", ".join(f'"{c}"' for c in shared_cols)
            try:
                result = src_conn.execute(text(f"SELECT {col_list} FROM {tname}"))
                rows = result.mappings().all()
            except Exception as e:
                print(f"  [error] {tname}: {e}")
                continue

            if not rows:
                print(f"  [empty] {tname}")
                continue

            # Bulk insert into Postgres using SQLAlchemy core.
            # rows is a list of RowMapping objects; convert to plain dicts.
            payload = [dict(r) for r in rows]
            try:
                dst_conn.execute(table.insert(), payload)
                print(f"  [ok]    {tname:<32} {len(payload):>5} rows")
                total_rows += len(payload)
            except Exception as e:
                print(f"  [error] {tname}: {e}")
                # Continue to next table — partial migration is recoverable
                # with re-run; full abort would be more painful.

    # ---- 6. Bump sequences so next INSERT doesn't collide ----
    banner("Bumping Postgres sequences", "-")
    with dst_engine.begin() as dst_conn:
        # Per-table lookup avoids the IN-clause parameter-binding quirk that
        # bit us earlier. pg_get_serial_sequence resolves the auto-created
        # sequence name for any SERIAL/IDENTITY column.
        for table in tables_in_dep_order:
            pks = [c for c in table.primary_key.columns]
            if len(pks) != 1:
                continue
            pk = pks[0]
            try:
                seq = dst_conn.execute(text(
                    f"SELECT pg_get_serial_sequence('{table.name}', '{pk.name}')"
                )).scalar()
            except Exception as e:
                print(f"  [warn]  {table.name}: {e}")
                continue
            if not seq:
                continue
            try:
                dst_conn.execute(text(
                    f"SELECT setval('{seq}', "
                    f"COALESCE((SELECT MAX(\"{pk.name}\") FROM \"{table.name}\"), 1), "
                    f"(SELECT EXISTS (SELECT 1 FROM \"{table.name}\")))"
                ))
                print(f"  [ok]    {seq}")
            except Exception as e:
                print(f"  [warn]  {seq}: {e}")

    # ---- 7. Summary ----
    banner("Done")
    print(f"Total rows copied: {total_rows}")
    print()
    print("Next steps:")
    print("  1. uvicorn app.main:app --reload  -> confirms the app boots on Postgres")
    print("  2. Open /admin/finance and check the numbers match what you had before")
    print("  3. If anything looks off, re-run this script (it's idempotent)")
    print()
    return 0


if __name__ == "__main__":
    code = asyncio.run(main())
    sys.exit(code)

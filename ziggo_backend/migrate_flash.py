"""Idempotent migration: add parcel/Flash fields to the bookings table.

Run once:
    python migrate_flash.py

Re-running is safe — it only adds columns that don't already exist.
"""
import sqlite3

DB = "ziggo.db"

NEW_COLUMNS = {
    "is_flash": "INTEGER DEFAULT 0",
    "parcel_type": "VARCHAR(50)",
    "parcel_weight_kg": "DECIMAL(6,2)",
    "receiver_name": "VARCHAR(100)",
    "receiver_phone": "VARCHAR(20)",
    "parcel_instructions": "TEXT",
}


def main():
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(bookings)")
    existing = {row[1] for row in cur.fetchall()}

    added = []
    for col, ddl in NEW_COLUMNS.items():
        if col in existing:
            continue
        cur.execute(f"ALTER TABLE bookings ADD COLUMN {col} {ddl}")
        added.append(col)

    cur.execute("CREATE INDEX IF NOT EXISTS ix_bookings_is_flash ON bookings(is_flash)")
    conn.commit()
    conn.close()

    if added:
        print(f"[migrate_flash] Added columns: {', '.join(added)}")
    else:
        print("[migrate_flash] Nothing to do — all flash columns already exist.")


if __name__ == "__main__":
    main()

"""Idempotent migration: add Courier parcel fields to the bookings table.

Run once:
    python migrate_courier.py

Re-running is safe — it only adds columns that don't already exist. Mirrors
migrate_flash.py; courier deliveries reuse the existing parcel_* / receiver_*
columns and only need these two extra markers.
"""
import sqlite3

DB = "ziggo.db"

NEW_COLUMNS = {
    "is_courier": "INTEGER DEFAULT 0",
    "courier_eta_days": "INTEGER",
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

    cur.execute("CREATE INDEX IF NOT EXISTS ix_bookings_is_courier ON bookings(is_courier)")
    conn.commit()
    conn.close()

    if added:
        print(f"[migrate_courier] Added columns: {', '.join(added)}")
    else:
        print("[migrate_courier] Nothing to do — all courier columns already exist.")


if __name__ == "__main__":
    main()

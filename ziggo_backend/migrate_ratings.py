"""migrate_ratings.py — Adds customer_rating and customer_feedback columns to
food_orders and market_orders tables (delivery feedback feature).

Run once against the production/development ziggo.db:
    python migrate_ratings.py
"""
import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "ziggo.db")

MIGRATIONS = [
    "ALTER TABLE food_orders ADD COLUMN customer_rating INTEGER;",
    "ALTER TABLE food_orders ADD COLUMN customer_feedback TEXT;",
    "ALTER TABLE market_orders ADD COLUMN customer_rating INTEGER;",
    "ALTER TABLE market_orders ADD COLUMN customer_feedback TEXT;",
]


def run():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    for sql in MIGRATIONS:
        try:
            cur.execute(sql)
            print(f"OK: {sql}")
        except sqlite3.OperationalError as exc:
            # Column already exists — safe to skip.
            print(f"SKIP ({exc}): {sql}")
    conn.commit()
    conn.close()
    print("Migration complete.")


if __name__ == "__main__":
    run()

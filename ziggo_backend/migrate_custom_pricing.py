import sys
import sqlite3
from sqlalchemy import create_engine, text
from app.config import settings

def migrate_sqlite():
    print("Migrating SQLite...")
    try:
        conn = sqlite3.connect("test.db")
        cur = conn.cursor()
        
        # Migrate restaurants
        cur.execute("PRAGMA table_info(restaurants)")
        cols = {row[1] for row in cur.fetchall()}
        
        r_cols = {
            "pickup_fee": "DECIMAL(10, 2) DEFAULT 70.00",
            "per_km_rate": "DECIMAL(10, 2) DEFAULT 40.00",
            "boost": "DECIMAL(10, 2) DEFAULT 0.00",
            "commission_percentage": "DECIMAL(5, 2) DEFAULT 20.00"
        }
        for col, ddl in r_cols.items():
            if col not in cols:
                cur.execute(f"ALTER TABLE restaurants ADD COLUMN {col} {ddl}")
                print(f"SQLite: Added {col} to restaurants")
                
        # Migrate market_vendors
        cur.execute("PRAGMA table_info(market_vendors)")
        cols = {row[1] for row in cur.fetchall()}
        
        m_cols = {
            "pickup_fee": "DECIMAL(10, 2) DEFAULT 70.00",
            "per_km_rate": "DECIMAL(10, 2) DEFAULT 40.00",
            "boost": "DECIMAL(10, 2) DEFAULT 0.00"
        }
        for col, ddl in m_cols.items():
            if col not in cols:
                cur.execute(f"ALTER TABLE market_vendors ADD COLUMN {col} {ddl}")
                print(f"SQLite: Added {col} to market_vendors")
                
        conn.commit()
        conn.close()
        print("SQLite migration finished.")
    except Exception as e:
        print(f"SQLite migration failed/skipped: {e}")

def migrate_postgres():
    print("Migrating Postgres...")
    db_url = settings.SYNC_DATABASE_URL
    print(f"Connecting to: {db_url}")
    try:
        engine = create_engine(db_url)
        with engine.connect() as conn:
            # Check restaurants columns
            res = conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='restaurants'"))
            cols = {row[0] for row in res.fetchall()}
            
            r_cols = {
                "pickup_fee": "DECIMAL(10, 2) DEFAULT 70.00 NOT NULL",
                "per_km_rate": "DECIMAL(10, 2) DEFAULT 40.00 NOT NULL",
                "boost": "DECIMAL(10, 2) DEFAULT 0.00 NOT NULL",
                "commission_percentage": "DECIMAL(5, 2) DEFAULT 20.00 NOT NULL"
            }
            for col, ddl in r_cols.items():
                if col not in cols:
                    conn.execute(text(f"ALTER TABLE restaurants ADD COLUMN {col} {ddl}"))
                    print(f"Postgres: Added {col} to restaurants")
            
            # Check market_vendors columns
            res = conn.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='market_vendors'"))
            cols = {row[0] for row in res.fetchall()}
            
            m_cols = {
                "pickup_fee": "DECIMAL(10, 2) DEFAULT 70.00 NOT NULL",
                "per_km_rate": "DECIMAL(10, 2) DEFAULT 40.00 NOT NULL",
                "boost": "DECIMAL(10, 2) DEFAULT 0.00 NOT NULL"
            }
            for col, ddl in m_cols.items():
                if col not in cols:
                    conn.execute(text(f"ALTER TABLE market_vendors ADD COLUMN {col} {ddl}"))
                    print(f"Postgres: Added {col} to market_vendors")
                    
            conn.commit()
        print("Postgres migration finished.")
    except Exception as e:
        print(f"Postgres migration failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    migrate_sqlite()
    migrate_postgres()

import sqlite3
db = sqlite3.connect('ziggo.db')
print(db.execute("SELECT base_fare, per_km_rate, per_minute_rate, min_fare FROM fare_settings WHERE service_type='truck'").fetchone())

import sqlite3
db = sqlite3.connect('ziggo.db')
db.execute("UPDATE fare_settings SET is_truck=1 WHERE service_type='truck'")
db.commit()
print("Updated successfully!")

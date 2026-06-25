import sqlite3
conn = sqlite3.connect('ziggo.db')
c = conn.cursor()
c.execute('SELECT name FROM sqlite_master WHERE type="table"')
print(c.fetchall())
c.execute('SELECT id, name FROM restaurants')
print("Restaurants:", c.fetchall())
c.execute('SELECT id, phone_number FROM users')
print("Users:", c.fetchall())


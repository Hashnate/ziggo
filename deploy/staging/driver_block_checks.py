"""Bug 4 checks: drivers blocked for unpaid commission can't take jobs.

Runs a throwaway backend on a throwaway copy of the staging database (both
removed afterwards), so neither the live site nor the staging site is touched.

    python3 deploy/staging/driver_block_checks.py <backend image>
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

IMAGE = sys.argv[1]
NAME, COPY_DB, NET = "ziggo_bug4_test", "ziggo_bug4", "ziggo_staging_ziggo_staging_net"
BASE = "http://127.0.0.1:8033/api/v1"
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
COORDS = {"pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1]}
DRIVER_MSG = "Your account is deactivated due to outstanding commission. Please settle it."
CUSTOMER_MSG = "This driver can't take bookings right now. Please choose another ride."
env = dict(l.strip().split("=", 1) for l in open("/var/www/ziggo-staging/.env") if "=" in l and not l.startswith("#"))
DB_USER, DB_PASS = env.get("POSTGRES_USER", "ziggo_staging"), env["POSTGRES_PASSWORD"]
BIKE = "(select d.id from drivers d join users u on u.id = d.user_id where u.phone_number = '0771000002')"
results = []


def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()


def sql(query):
    return run("docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", DB_USER, "-d", COPY_DB,
               "-At", "-v", "ON_ERROR_STOP=1", "-c", query)


def call(method, path, token=None, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw and raw[:1] in b"[{" else raw
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw and raw[:1] in b"[{" else raw


def login(phone, role):
    _, sent = call("POST", "/auth/send-otp", body={"phone_number": phone})
    _, tok = call("POST", "/auth/verify-otp", body={"phone_number": phone, "otp": sent["dev_otp"], "role": role})
    return tok["access_token"]


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))


def detail(body):
    return body.get("detail") if isinstance(body, dict) else body


def new_bike_booking():
    s, b = call("POST", "/bookings", customer, {"service_type": "bike", **COORDS, "pickup_address": "x",
                                                 "drop_address": "y", "payment_method": "cash"})
    assert s == 201, f"booking not created: HTTP {s} {b}"
    return b["id"]


def ready_order(table):
    """Re-use an existing order in the throwaway copy as a fresh ready-for-pickup delivery."""
    oid = sql(f"select id from {table} order by id desc limit 1")
    sql(f"update {table} set status = 'READY_FOR_PICKUP', driver_id = null where id = {oid}")
    return oid


def accepts(label, path, want_ok, want_msg=DRIVER_MSG):
    s, r = call("POST", path, bike)
    if want_ok:
        check(label, s == 200, f"HTTP {s}" + ("" if s == 200 else f": {detail(r)}"))
        # Release the job so the driver is free (not busy) for the next check.
        kind, oid = path.split("/")[1], path.split("/")[-2]
        table = {"bookings": "bookings", "food": "food_orders", "market": "market_orders"}[kind]
        sql(f"update {table} set status = 'CANCELLED' where id = {oid}")
    else:
        check(label, s == 403 and detail(r) == want_msg, f"HTTP {s}: {detail(r)}")


try:
    run("docker", "exec", "ziggo_postgres_staging", "sh", "-c",
        f"dropdb -U {DB_USER} --if-exists {COPY_DB} && createdb -U {DB_USER} {COPY_DB} && "
        f"pg_dump -U {DB_USER} ziggo_staging | psql -q -U {DB_USER} -d {COPY_DB} >/dev/null")
    # Start every test driver debt-free in the copy.
    sql("insert into driver_payouts (driver_id, user_id, amount, description, created_at) "
        "select d.id, d.user_id, x.o, 'Commission settled (staging test setup)', now() from drivers d "
        "join users u on u.id = d.user_id cross join lateral (select "
        "(select coalesce(sum(coalesce(b.final_amount, b.fare_amount) - b.driver_earnings), 0) from bookings b "
        " where b.driver_id = d.id and b.status = 'COMPLETED' and b.payment_method = 'cash') - "
        "(select coalesce(sum(amount), 0) from driver_payouts p where p.driver_id = d.id and "
        " (lower(p.description) like '%commission settled%' or lower(p.description) like '%commission settlement%')) as o) x "
        "where u.phone_number like '077100000_' and x.o > 0")
    sql(f"update drivers set status = 'APPROVED' where id = {BIKE}")
    run("docker", "run", "-d", "--name", NAME, "--network", NET, "-p", "127.0.0.1:8033:8000",
        "-e", f"DATABASE_URL=postgresql+asyncpg://{DB_USER}:{DB_PASS}@ziggo_postgres_staging:5432/{COPY_DB}",
        "-e", f"SYNC_DATABASE_URL=postgresql+psycopg://{DB_USER}:{DB_PASS}@ziggo_postgres_staging:5432/{COPY_DB}",
        "-e", "TZ=Asia/Colombo", "-e", "SECRET_KEY=bug4-test-only", "-e", "DEV_MODE=true", IMAGE)
    for _ in range(60):
        try:
            urllib.request.urlopen("http://127.0.0.1:8033/health", timeout=2)
            break
        except Exception:
            time.sleep(1)
    customer, bike = login("0771234567", "customer"), login("0771000002", "driver")
    bike_id = call("GET", "/driver/me", bike)[1]["id"]
    limit = sql("select coalesce(max_settle_amount, 1000) from system_settings where id = 1")

    def balance():
        s = call("GET", "/driver/earnings-summary", bike)[1]
        return round(s["pending"] - s["outstanding_commission"], 2)
    print(f"commission limit on this copy: Rs.{limit}")

    print("\nA. Driver with no unpaid commission (control)")
    accepts("accepts a ride", f"/bookings/{new_bike_booking()}/accept", True)
    accepts("accepts a food delivery", f"/food/orders/{ready_order('food_orders')}/accept", True)
    accepts("accepts a market delivery", f"/market/orders/{ready_order('market_orders')}/accept", True)

    for case, setup, undo in (
        ("B. Driver suspended for unpaid commission (still 'approved')",
         f"update drivers set status = 'SUSPENDED' where id = {BIKE}",
         f"update drivers set status = 'APPROVED' where id = {BIKE}"),
        ("C. Debt already over the limit, status not yet updated",
         # Debt measured from the driver's real balance (card earnings offset commission).
         lambda: "insert into driver_payouts (driver_id, user_id, amount, description, created_at) "
         f"select id, user_id, -({balance()} + {limit} + 500), 'Commission settled (bug4 test debt)', now() from drivers where id = {BIKE}",
         f"delete from driver_payouts where driver_id = {BIKE} and description = 'Commission settled (bug4 test debt)'"),
    ):
        print(f"\n{case}")
        sql(setup() if callable(setup) else setup)
        bid = new_bike_booking()
        accepts("ride accept refused", f"/bookings/{bid}/accept", False)
        check("ride stays open for other drivers", sql(f"select status from bookings where id = {bid}") == "SEARCHING")
        before = sql("select count(*) from bookings")
        s, r = call("POST", f"/bookings/scan-and-go?driver_id={bike_id}", customer, {
            "service_type": "bike", **COORDS, "pickup_address": "x", "drop_address": "y", "payment_method": "cash"})
        check("scan-and-go to this driver refused", s == 400 and detail(r) == CUSTOMER_MSG, f"HTTP {s}: {detail(r)}")
        check("no scan-and-go booking created", sql("select count(*) from bookings") == before)
        accepts("food delivery accept refused", f"/food/orders/{ready_order('food_orders')}/accept", False)
        accepts("market delivery accept refused", f"/market/orders/{ready_order('market_orders')}/accept", False)
        sql(undo)
        accepts("after settling, accepts a ride again", f"/bookings/{new_bike_booking()}/accept", True)
finally:
    subprocess.run(["docker", "rm", "-f", NAME], capture_output=True)
    subprocess.run(["docker", "exec", "ziggo_postgres_staging", "dropdb", "-U", DB_USER, "--if-exists", "--force", COPY_DB],
                   capture_output=True)
    print("\nRemoved the throwaway backend and database copy.")

fails = [r for r in results if not r[1]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for label, _, d in fails:
    print(f"  FAILED: {label} ({d})")
sys.exit(1 if fails else 0)

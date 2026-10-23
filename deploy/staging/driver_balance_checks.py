"""Checks for the one-balance-per-driver change (option A).

Throwaway backend on a throwaway copy of the staging database (both removed
afterwards). Uses the test car driver, who has cash trips and wallet trips.

    python3 deploy/staging/driver_balance_checks.py <backend image>
"""
import http.cookiejar
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

IMAGE = sys.argv[1]
NAME, COPY_DB, NET, PORT = "ziggo_balance_test", "ziggo_balance", "ziggo_staging_ziggo_staging_net", 8034
ROOT = f"http://127.0.0.1:{PORT}"
BASE = ROOT + "/api/v1"
OFFICE = "Please settle your commission with the Ziggo office."
env = dict(l.strip().split("=", 1) for l in open("/var/www/ziggo-staging/.env") if "=" in l and not l.startswith("#"))
DB_USER, DB_PASS = env.get("POSTGRES_USER", "ziggo_staging"), env["POSTGRES_PASSWORD"]
ADMIN_PW = next(l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700000000"))
CAR = "(select d.id from drivers d join users u on u.id = d.user_id where u.phone_number = '0771000003')"
results = []


def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()


def sql(q):
    return run("docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", DB_USER, "-d", COPY_DB,
               "-At", "-v", "ON_ERROR_STOP=1", "-c", q)


def start():
    subprocess.run(["docker", "rm", "-f", NAME], capture_output=True)
    url = f"{DB_USER}:{DB_PASS}@ziggo_postgres_staging:5432/{COPY_DB}"
    run("docker", "run", "-d", "--name", NAME, "--network", NET, "-p", f"127.0.0.1:{PORT}:8000",
        "-e", f"DATABASE_URL=postgresql+asyncpg://{url}", "-e", f"SYNC_DATABASE_URL=postgresql+psycopg://{url}",
        "-e", "TZ=Asia/Colombo", "-e", "SECRET_KEY=balance-test-only", "-e", "DEV_MODE=true", IMAGE)
    for _ in range(60):
        try:
            urllib.request.urlopen(ROOT + "/health", timeout=2)
            return
        except Exception:
            time.sleep(1)
    raise SystemExit("backend did not start")


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


admin = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def admin_post(path, fields):
    data = urllib.parse.urlencode(fields).encode()
    try:
        with admin.open(ROOT + path, data=data, timeout=30) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def admin_get(path):
    try:
        with admin.open(ROOT + path, timeout=30) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, ""


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))


def summary():
    return call("GET", "/driver/earnings-summary", car)[1]


def balance():
    s = summary()
    return round(s["pending"] - s["outstanding_commission"], 2), s


def near(a, b):
    return abs(a - b) < 0.01


try:
    run("docker", "exec", "ziggo_postgres_staging", "sh", "-c",
        f"dropdb -U {DB_USER} --if-exists {COPY_DB} && createdb -U {DB_USER} {COPY_DB} && "
        f"pg_dump -U {DB_USER} ziggo_staging | psql -q -U {DB_USER} -d {COPY_DB} >/dev/null")
    sql(f"delete from driver_payouts where driver_id = {CAR}")      # start from a clean money ledger
    sql(f"update drivers set status = 'APPROVED' where id = {CAR}")
    start()
    car, customer = login("0771000003", "driver"), login("0771234567", "customer")
    car_id = int(sql(f"select {CAR}"))
    admin_post("/admin/login", {"phone_number": "0700000000", "password": ADMIN_PW})
    limit = float(sql("select coalesce(max_settle_amount, 1000) from system_settings where id = 1"))
    cash_comm = float(sql(f"select coalesce(sum(coalesce(final_amount, fare_amount) - driver_earnings), 0) from bookings "
                          f"where driver_id = {CAR} and status = 'COMPLETED' and payment_method = 'cash'"))
    noncash = float(sql(f"select coalesce(sum(driver_earnings), 0) from bookings where driver_id = {CAR} "
                        f"and status = 'COMPLETED' and payment_method <> 'cash'"))
    print(f"car driver: cash commission Rs.{cash_comm:.2f}, card/wallet earnings Rs.{noncash:.2f}, limit Rs.{limit:.0f}")

    print("\n1. Automatic offset")
    b0, s = balance()
    check("card/wallet earnings are netted against cash commission", near(b0, noncash - cash_comm),
          f"balance Rs.{b0} = Rs.{noncash:.2f} - Rs.{cash_comm:.2f}; old system would show Rs.{cash_comm:.2f} owed")
    check("app shows only one side (owed or pending)", s["pending"] == 0 or s["outstanding_commission"] == 0,
          f"pending Rs.{s['pending']}, owed Rs.{s['outstanding_commission']}")

    print("\n2. Ledger entries")
    sql(f"insert into driver_payouts (driver_id, user_id, amount, description, created_at) select id, user_id, 250, "
        f"'One Day Incentives Bonus (6 trips completed)', now() from drivers where id = {CAR}")
    b1, _ = balance()
    check("an earned bonus (older row, no type) is owed to the driver", near(b1, b0 + 250), f"Rs.{b0} -> Rs.{b1}")
    paid0 = summary()["paid"]
    s_, _ = admin_post(f"/admin/finance/drivers/{car_id}/pay_incentive", {"amount": 500, "note": "Festival bonus"})
    b2, s = balance()
    check("admin 'Pay incentive' doesn't put the driver in debt", near(b2, b1) and near(s["paid"], paid0 + 500),
          f"HTTP {s_}, balance Rs.{b1} -> Rs.{b2}, paid Rs.{paid0} -> Rs.{s['paid']}")
    s_, _ = admin_post(f"/admin/withdrawals/{car_id}/pay", {"amount": 100, "payment_method": "Direct Bank Transfer"})
    b3, s = balance()
    check("a payout lowers what Ziggo owes", near(b3, b2 - 100) and near(s["paid"], paid0 + 600), f"HTTP {s_}, Rs.{b2} -> Rs.{b3}")
    sql(f"insert into driver_payouts (driver_id, user_id, amount, description, created_at) select id, user_id, 300, "
        f"'Commission settled (Cash balance offset)', now() from drivers where id = {CAR}")
    b4, _ = balance()
    check("an old 'Cash balance offset' row has no effect", near(b4, b3), f"Rs.{b3} -> Rs.{b4}")

    print("\n3. Block, office payment, unblock")
    push = round(b4 + limit + 200, 2)       # an over-payment that leaves the driver owing limit + 200
    admin_post(f"/admin/withdrawals/{car_id}/pay", {"amount": push, "payment_method": "Direct Bank Transfer"})
    b5, s = balance()
    check("driver now owes more than the limit", near(s["outstanding_commission"], limit + 200), f"owes Rs.{s['outstanding_commission']}")
    st, r = call("POST", "/driver/online", car, {"is_online": True})
    check("blocked from going online", st == 403, f"HTTP {st}")
    _, bk = call("POST", "/bookings", customer, {"service_type": "car", "pickup_lat": 6.9147, "pickup_lng": 79.8778,
                 "drop_lat": 6.8649, "drop_lng": 79.8997, "pickup_address": "x", "drop_address": "y", "payment_method": "cash"})
    st, r = call("POST", f"/bookings/{bk['id']}/accept", car)
    check("blocked from accepting a trip", st == 403, f"HTTP {st}")
    st, r = call("POST", "/driver/settle-commission", car, {})
    check("app 'settle' without a card points to the office", st == 400 and isinstance(r, dict) and r.get("detail") == OFFICE,
          f"HTTP {st}: {r.get('detail') if isinstance(r, dict) else r}")
    st, page = admin_get(f"/admin/finance/drivers/{car_id}")
    check("admin driver page shows 'Record Commission Payment'", st == 200 and "Record Commission Payment" in page, f"HTTP {st}")
    owed = s["outstanding_commission"]
    st, _ = admin_post(f"/admin/finance/drivers/{car_id}/commission_payment",
                       {"amount": owed, "payment_method": "Cash at office", "reference_id": "R-1001"})
    _, s = balance()
    check("office payment clears the debt", st == 200 and s["outstanding_commission"] == 0, f"HTTP {st}, owes Rs.{s['outstanding_commission']}")
    check("driver unblocked straight away", sql(f"select status from drivers where id = {CAR}") == "APPROVED")
    st, _ = call("POST", "/driver/online", car, {"is_online": True})
    check("can go online again", st == 200, f"HTTP {st}")
    call("POST", "/driver/online", car, {"is_online": False})
    note = sql(f"select title || ': ' || body from notifications where user_id = (select user_id from drivers where id = {CAR}) "
               "and title = 'Commission payment received' order by id desc limit 1")
    check("driver gets a 'payment received' message", "Commission payment received" in note, note[:90])
    kinds = sql(f"select string_agg(coalesce(kind, 'null'), ',' order by id) from driver_payouts where driver_id = {CAR}")
    check("new records carry their type", kinds.endswith("incentive_paid,payout,null,payout,commission_payment"), kinds)

    print("\n4. Card settlement (test site only, gateway simulated)")
    admin_post(f"/admin/withdrawals/{car_id}/pay", {"amount": 400, "payment_method": "Direct Bank Transfer"})
    owed = summary()["outstanding_commission"]
    _, cd = call("POST", "/payments/methods/mock", car, {})
    st, r = call("POST", "/driver/settle-commission", car, {"card_id": cd.get("card_id")})
    check("driver settles by card", st == 200 and isinstance(r, dict) and near(r.get("settled_amount", 0), owed),
          f"HTTP {st}, settled Rs.{r.get('settled_amount') if isinstance(r, dict) else r} of Rs.{owed}")
    check("debt cleared", summary()["outstanding_commission"] == 0)

    print("\n5. Restart keeps every record")
    before = sql(f"select count(*) from driver_payouts where driver_id = {CAR}")
    start()
    after = sql(f"select count(*) from driver_payouts where driver_id = {CAR}")
    offset_left = sql(f"select count(*) from driver_payouts where driver_id = {CAR} and description ilike '%Cash balance offset%'")
    check("nothing deleted at restart (old offset row still there)", before == after and offset_left == "1",
          f"{before} -> {after} records, offset rows {offset_left}")

    print("\n6. Admin pages")
    admin_post("/admin/login", {"phone_number": "0700000000", "password": ADMIN_PW})
    for p in ("/admin/finance/drivers", f"/admin/finance/drivers/{car_id}", "/admin/withdrawals", "/admin/finance"):
        st, _ = admin_get(p)
        check(f"{p} loads", st == 200, f"HTTP {st}")
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

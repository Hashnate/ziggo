"""Checks for the driver bonus wallet.

Throwaway backend on a throwaway copy of the staging database (both removed
afterwards). Uses the test car driver (0771000003) and the test customer.

    python3 deploy/staging/driver_wallet_checks.py <backend image>
"""
import http.cookiejar
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

IMAGE = sys.argv[1]
NAME, COPY_DB, NET, PORT = "ziggo_wallet_test", "ziggo_wallet", "ziggo_staging_ziggo_staging_net", 8035
ROOT = f"http://127.0.0.1:{PORT}"
BASE = ROOT + "/api/v1"
env = dict(l.strip().split("=", 1) for l in open("/var/www/ziggo-staging/.env") if "=" in l and not l.startswith("#"))
DB_USER, DB_PASS = env.get("POSTGRES_USER", "ziggo_staging"), env["POSTGRES_PASSWORD"]
PASSWORDS = {l.split()[0]: l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700")}
CAR = "(select d.id from drivers d join users u on u.id = d.user_id where u.phone_number = '0771000003')"
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
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
        "-e", "TZ=Asia/Colombo", "-e", "SECRET_KEY=wallet-test-only", "-e", "DEV_MODE=true", IMAGE)
    for _ in range(90):
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
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw and raw[:1] in b"[{" else raw
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw and raw[:1] in b"[{" else raw


def login(phone, role):
    _, sent = call("POST", "/auth/send-otp", body={"phone_number": phone})
    _, tok = call("POST", "/auth/verify-otp", body={"phone_number": phone, "otp": sent["dev_otp"], "role": role})
    return tok["access_token"]


class Admin:
    def __init__(self, phone):
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.post("/admin/login", {"phone_number": phone, "password": PASSWORDS[phone]})

    def post(self, path, fields):
        try:
            with self.opener.open(ROOT + path, data=urllib.parse.urlencode(fields).encode(), timeout=120) as r:
                return r.status, r.read().decode(errors="replace")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")

    def get(self, path):
        try:
            with self.opener.open(ROOT + path, timeout=60) as r:
                return r.status, r.read().decode(errors="replace")
        except urllib.error.HTTPError as e:
            return e.code, ""


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))
    return ok


def near(a, b):
    return abs(a - b) < 0.01


def wallet():
    return call("GET", "/driver/wallet", car)[1]


def summary():
    return call("GET", "/driver/earnings-summary", car)[1]


def balance():
    s = summary()
    return round(s["pending"] - s["outstanding_commission"], 2)


def set_balance(target):
    """Add a ledger row so the car driver's balance is exactly target (below zero = owes)."""
    diff = round(balance() - target, 2)
    if diff:
        kind = "payout" if diff > 0 else "commission_payment"
        sql(f"insert into driver_payouts (driver_id, user_id, amount, kind, description, created_at) "
            f"select id, user_id, {abs(diff)}, '{kind}', 'wallet check setup', now() from drivers where id = {CAR}")


def driver_status():
    return sql(f"select status from drivers where id = {CAR}")


def grant_id(note):
    return int(sql(f"select max(id) from driver_wallet_grants where note = '{note}'"))


def credit(note):
    used, amount, expires = sql(
        f"select c.used_amount, c.amount, c.expires_on from driver_wallet_credits c join driver_wallet_grants g "
        f"on g.id = c.grant_id where g.note = '{note}' and c.driver_id = {CAR}").split("|")
    return float(used), float(amount), expires


def cash_ride():
    """A real cash car ride, Borella -> Nugegoda, through the API."""
    call("POST", "/driver/online", car, {"is_online": True})
    call("POST", "/driver/location", car, {"lat": BORELLA[0] + 0.002, "lng": BORELLA[1]})
    body = {"service_type": "car", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
            "drop_lng": NUGEGODA[1], "pickup_address": "Wallet check pickup", "drop_address": "Wallet check drop",
            "payment_method": "cash"}
    s, b = call("POST", "/bookings", customer, body)
    if not check("cash ride booked", s == 201, f"HTTP {s}" + ("" if s == 201 else f": {str(b)[:120]}")):
        return None
    bid = b["id"]
    s, _ = call("POST", f"/bookings/{bid}/accept", car)
    check("driver accepts", s == 200, f"HTTP {s}")
    call("PATCH", f"/bookings/{bid}/status", car, {"status": "arrived"})
    _, cb = call("GET", f"/bookings/{bid}", customer)
    call("PATCH", f"/bookings/{bid}/status", car, {"status": "started", "otp": cb.get("otp")})
    s, done = call("PATCH", f"/bookings/{bid}/status", car,
                   {"status": "completed", "lat": NUGEGODA[0], "lng": NUGEGODA[1]})
    call("POST", "/driver/online", car, {"is_online": False})
    if not check("ride completed", s == 200 and isinstance(done, dict) and done.get("status") == "completed", f"HTTP {s}"):
        return None
    paid, earned = map(float, sql(f"select coalesce(final_amount, fare_amount), driver_earnings from bookings "
                                  f"where id = {bid}").split("|"))
    return round(paid - earned, 2)


try:
    run("docker", "exec", "ziggo_postgres_staging", "sh", "-c",
        f"dropdb -U {DB_USER} --if-exists {COPY_DB} && createdb -U {DB_USER} {COPY_DB} && "
        f"pg_dump -U {DB_USER} ziggo_staging | psql -q -U {DB_USER} -d {COPY_DB} >/dev/null")
    sql(f"delete from driver_payouts where driver_id = {CAR}")      # start from a clean money ledger
    sql(f"update drivers set status = 'APPROVED', is_approved = true where id = {CAR}")
    start()
    car, customer = login("0771000003", "driver"), login("0771234567", "customer")
    car_id = int(sql(f"select {CAR}"))
    superadmin, admin, data_entry = Admin("0700000000"), Admin("0700000001"), Admin("0700000002")
    limit = float(sql("select coalesce(max_settle_amount, 1000) from system_settings where id = 1"))
    approved = int(sql("select count(*) from drivers where is_approved"))
    approved_cars = int(sql("select count(*) from drivers where is_approved and vehicle_type = 'car'"))
    today = datetime.now(timezone(timedelta(hours=5, minutes=30))).date()   # Sri Lanka day
    print(f"{approved} approved drivers, {approved_cars} of them car; commission limit Rs.{limit:.0f}")

    print("\n1. Admin page")
    check("wallet tables created at startup", sql("select count(*) from driver_wallet_grants") == "0")
    st, page = superadmin.get("/admin/driver-wallet")
    check("superadmin opens Driver Bonus Wallet", st == 200 and "Give a bonus" in page, f"HTTP {st}")
    check("form counts the approved drivers", f"All approved drivers <span class=\"text-gray-400\">({approved})" in page)
    check("sidebar has the link", 'href="/admin/driver-wallet"' in page)
    st, page = admin.get("/admin/driver-wallet")
    check("admin role opens it too", st == 200 and "Give a bonus" in page, f"HTTP {st}")
    st, page = data_entry.get("/admin/driver-wallet")
    check("data entry can't open it", "Give a bonus" not in page, f"HTTP {st}")
    data_entry.post("/admin/driver-wallet/give", {"amount": 500, "expires_on": (today + timedelta(days=7)).isoformat(),
                                                   "note": "Data entry try", "audience": "all"})
    check("data entry can't give a bonus", sql("select count(*) from driver_wallet_grants") == "0")

    print("\n2. Wrong input is refused")
    _, page = superadmin.post("/admin/driver-wallet/give", {"amount": 0, "expires_on": today.isoformat(), "note": "x"})
    check("amount 0 refused", "between Rs.0.01" in page)
    _, page = superadmin.post("/admin/driver-wallet/give", {"amount": 100, "note": "x",
                                                            "expires_on": (today - timedelta(days=1)).isoformat()})
    check("an expiry date in the past refused", "from today onwards" in page)
    check("nothing was given", sql("select count(*) from driver_wallet_grants") == "0")

    print("\n3. Bonus to all car drivers pays what is owed at once")
    set_balance(-300)
    check("car driver owes Rs.300", near(summary()["outstanding_commission"], 300))
    note1 = "Wallet check bonus"
    _, page = admin.post("/admin/driver-wallet/give", {
        "amount": 500, "expires_on": (today + timedelta(days=7)).isoformat(), "note": note1,
        "audience": "vehicle", "vehicle_type": "car"})
    check("admin sees the result", f"bonus given to {approved_cars} drivers" in page, f"{approved_cars} car drivers")
    check("one credit per approved car driver",
          sql(f"select count(*) from driver_wallet_credits where grant_id = {grant_id(note1)}") == str(approved_cars))
    check("other vehicle types got nothing", sql(
        f"select count(*) from driver_wallet_credits c join drivers d on d.id = c.driver_id "
        f"where c.grant_id = {grant_id(note1)} and d.vehicle_type <> 'car'") == "0")
    w, s = wallet(), summary()
    check("Rs.300 commission paid from the wallet, Rs.200 left",
          near(w["available"], 200) and near(s["outstanding_commission"], 0) and w["commission_due"] == 0,
          f"left Rs.{w['available']}, owed Rs.{s['outstanding_commission']}")
    check("wallet money is never a pending payout", s["pending"] == 0 and near(s["wallet_available"], 200),
          f"pending Rs.{s['pending']}, earnings page wallet Rs.{s['wallet_available']}")
    check("the app can't withdraw it", w["withdrawable"] is False)
    note = sql(f"select title || ': ' || body from notifications where user_id = (select user_id from drivers "
               f"where id = {CAR}) and type = 'wallet' order by id desc limit 1")
    check("driver is told", note.startswith("Bonus added to your wallet: Rs.500.00 (Wallet check bonus)"), note[:90])

    print("\n4. Bonus for one driver from their page; soonest-ending money used first")
    st, page = superadmin.get(f"/admin/finance/drivers/{car_id}")
    check("driver page shows the wallet and 'Give Bonus'",
          st == 200 and "Bonus wallet" in page and "Give Bonus" in page and note1 in page, f"HTTP {st}")
    note2 = "Today only"
    _, page = superadmin.post("/admin/driver-wallet/give", {
        "amount": 100, "expires_on": today.isoformat(), "note": note2, "audience": "driver",
        "driver_id": car_id, "back": f"/admin/finance/drivers/{car_id}"})
    check("returns to the driver page with the result", "bonus given to 1 driver" in page and "Bonus wallet" in page)
    w = wallet()
    check("Rs.300 in the wallet; Rs.100 ends today",
          near(w["available"], 300) and w["next_expiry"] == {"date": today.isoformat(), "days_left": 0, "amount": 100.0},
          str(w["next_expiry"]))
    commission = cash_ride()
    if commission is not None:
        w, s = wallet(), summary()
        today_used = credit(note2)[0]
        check(f"the ride's Rs.{commission:.2f} commission is paid from the wallet",
              near(w["available"], 300 - commission) and s["outstanding_commission"] == 0,
              f"left Rs.{w['available']}, owed Rs.{s['outstanding_commission']}")
        check("the bonus ending today is used first", near(today_used, min(100, commission)), f"used Rs.{today_used}")
        check("the payment is listed in the app", near(w["payments"][0]["amount"], commission))

    print("\n5. Blocked driver: wallet pays first, a new bonus unblocks")
    left = wallet()["available"]
    set_balance(-(limit + left + 200))
    st, _ = call("POST", "/driver/online", car, {"is_online": True})
    s = summary()
    check("going online spends the wallet but the driver is still over the limit",
          st == 403 and wallet()["available"] == 0 and near(s["outstanding_commission"], limit + 200),
          f"HTTP {st}, owes Rs.{s['outstanding_commission']}")
    check("driver is blocked", driver_status() == "SUSPENDED")
    _, page = superadmin.post("/admin/driver-wallet/give", {
        "amount": 300, "expires_on": (today + timedelta(days=1)).isoformat(), "note": "Unblock", "audience": "driver",
        "driver_id": car_id, "back": f"/admin/finance/drivers/{car_id}"})
    s = summary()
    check("the bonus pays Rs.300, bringing the debt under the limit",
          near(s["outstanding_commission"], limit - 100), f"owes Rs.{s['outstanding_commission']}")
    check("driver unblocked straight away", driver_status() == "APPROVED")
    st, _ = call("POST", "/driver/online", car, {"is_online": True})
    check("can go online again", st == 200, f"HTTP {st}")
    call("POST", "/driver/online", car, {"is_online": False})

    print("\n6. Expiry dates and removing a bonus")
    set_balance(0)
    note3 = "Expiry check"
    superadmin.post("/admin/driver-wallet/give", {
        "amount": 200, "expires_on": (today + timedelta(days=3)).isoformat(), "note": note3, "audience": "driver",
        "driver_id": car_id, "back": f"/admin/finance/drivers/{car_id}"})
    check("Rs.200 bonus in the wallet", near(wallet()["available"], 200))
    g3 = grant_id(note3)
    _, page = superadmin.post(f"/admin/driver-wallet/grants/{g3}/expiry",
                              {"expires_on": (today - timedelta(days=1)).isoformat()})
    w = wallet()
    check("moving the end date to yesterday expires it", w["available"] == 0 and w["credits"][0]["status"] == "expired",
          f"left Rs.{w['available']}, {w['credits'][0]['status']}")
    set_balance(-50)
    call("POST", "/driver/online", car, {"is_online": True})
    call("POST", "/driver/online", car, {"is_online": False})
    check("expired money doesn't pay commission", near(summary()["outstanding_commission"], 50))
    superadmin.post(f"/admin/driver-wallet/grants/{g3}/expiry", {"expires_on": (today + timedelta(days=3)).isoformat()})
    w = wallet()
    check("bringing the date back pays the Rs.50 at once", near(w["available"], 150) and w["commission_due"] == 0,
          f"left Rs.{w['available']}, owed Rs.{w['commission_due']}")
    cid = int(sql(f"select id from driver_wallet_credits where grant_id = {g3}"))
    superadmin.post(f"/admin/driver-wallet/credits/{cid}/expiry", {"expires_on": (today + timedelta(days=10)).isoformat()})
    check("one driver's own date can be changed", credit(note3)[2] == (today + timedelta(days=10)).isoformat())
    _, page = superadmin.post(f"/admin/driver-wallet/grants/{g3}/cancel", {})
    w = wallet()
    check("'Remove rest' takes away the Rs.150 left", "Removed Rs.150.00" in page and w["available"] == 0
          and w["credits"][0]["status"] == "cancelled", f"left Rs.{w['available']}")
    check("commission already paid stays paid", w["commission_due"] == 0)

    print("\n7. Other pages")
    st, page = superadmin.get("/admin/driver-wallet")
    check("bonus list shows all four bonuses", all(n in page for n in (note1, note2, "Unblock", note3)), f"HTTP {st}")
    st, page = superadmin.get("/admin/withdrawals")
    check("wallet payments are not listed as payouts", st == 200 and "Commission paid from bonus wallet" not in page,
          f"HTTP {st}")

    print("\n8. Restart keeps every record")
    before = sql("select count(*), sum(used_amount) from driver_wallet_credits")
    start()
    check("nothing lost at restart", sql("select count(*), sum(used_amount) from driver_wallet_credits") == before, before)
finally:
    subprocess.run(["docker", "rm", "-f", NAME], capture_output=True)
    subprocess.run(["docker", "exec", "ziggo_postgres_staging", "dropdb", "-U", DB_USER, "--if-exists", COPY_DB],
                   capture_output=True)

failed = [r for r in results if not r[1]]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)

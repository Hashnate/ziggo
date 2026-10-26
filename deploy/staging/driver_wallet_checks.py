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


ALL_JOBS = [("job_types", t) for t in ("rides", "parcels", "food", "market")]
LK_DAY = "(x at time zone 'Asia/Colombo')::date"


def found(page):
    """The '2. N drivers found' count on the admin page, or None."""
    import re
    m = re.search(r"2\. (\d+) drivers? found", page)
    return int(m.group(1)) if m else None


def jobs_sql(kinds, start=None, end=None):
    """SQL for each approved driver's completed jobs of these kinds (Sri Lanka days)."""
    def window(col):
        w = ""
        if start:
            w += f" and {LK_DAY.replace('x', col)} >= '{start}'"
        if end:
            w += f" and {LK_DAY.replace('x', col)} <= '{end}'"
        return w
    parts = []
    parcel = "(coalesce(b.is_flash, false) or coalesce(b.is_courier, false))"
    if "rides" in kinds or "parcels" in kinds:
        which = "" if {"rides", "parcels"} <= set(kinds) else (f" and not {parcel}" if "rides" in kinds else f" and {parcel}")
        parts.append(f"(select count(*) from bookings b where b.driver_id = d.id and b.status = 'COMPLETED'{which}"
                     f"{window('b.completed_at')})")
    if "food" in kinds:
        parts.append(f"(select count(*) from food_orders o where o.driver_id = d.id and o.status = 'DELIVERED'"
                     f"{window('o.delivered_at')})")
    if "market" in kinds:
        parts.append(f"(select count(*) from market_orders o where o.driver_id = d.id and o.status = 'DELIVERED'"
                     f"{window('o.delivered_at')})")
    return " + ".join(parts) or "0"


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
    check("superadmin opens Driver Bonus Wallet", st == 200 and "Give a bonus to these" in page, f"HTTP {st}")
    check("with no filter, every approved driver is listed", found(page) == approved, f"{found(page)} / {approved}")
    check("sidebar has the link", 'href="/admin/driver-wallet"' in page)
    st, page = admin.get("/admin/driver-wallet")
    check("admin role opens it too", st == 200 and "Give a bonus" in page, f"HTTP {st}")
    st, page = data_entry.get("/admin/driver-wallet")
    check("data entry can't open it", "Give a bonus" not in page, f"HTTP {st}")
    data_entry.post("/admin/driver-wallet/give", {"amount": 500, "expires_on": (today + timedelta(days=7)).isoformat(),
                                                   "note": "Data entry try", "expected_count": approved})
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
    give_cars = [("f", "1"), ("vehicle_type", "car"), *ALL_JOBS, ("amount", 500), ("note", note1),
                 ("expires_on", (today + timedelta(days=7)).isoformat())]
    _, page = admin.post("/admin/driver-wallet/give", give_cars + [("expected_count", approved_cars + 1)])
    check("refused if the list changed since the admin looked", "changed" in page
          and sql("select count(*) from driver_wallet_grants") == "0", f"{approved_cars} now")
    _, page = admin.post("/admin/driver-wallet/give", give_cars + [("expected_count", approved_cars)])
    check("admin sees the result", f"bonus given to {approved_cars} drivers" in page, f"{approved_cars} car drivers")
    check("the page keeps the car filter", found(page) == approved_cars)
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

    print("\n7. Filters match the database")
    kinds_all = ("rides", "parcels", "food", "market")
    # Staging has no driver-delivered food or Mart orders; hand a few to the car driver in this copy.
    sql(f"update food_orders set status = 'DELIVERED', driver_id = {CAR}, delivered_at = now() "
        "where id in (select id from food_orders order by id limit 2)")
    sql(f"update market_orders set status = 'DELIVERED', driver_id = {CAR}, delivered_at = now() "
        "where id in (select id from market_orders order by id limit 1)")
    cases = [
        ("drivers with 1+ completed rides (not parcels)", [("min_jobs", 1), ("job_types", "rides")],
         f"({jobs_sql(['rides'])}) >= 1"),
        ("drivers with no completed job yet", [("max_jobs", 0), *ALL_JOBS], f"({jobs_sql(kinds_all)}) = 0"),
        ("drivers with 1 to 5 food or Mart deliveries", [("min_jobs", 1), ("max_jobs", 5), ("job_types", "food"),
                                                          ("job_types", "market")],
         f"({jobs_sql(['food', 'market'])}) between 1 and 5"),
        ("drivers with 3+ jobs in the last 30 days",
         [("min_jobs", 3), *ALL_JOBS, ("jobs_from", (today - timedelta(days=29)).isoformat()), ("jobs_to", today.isoformat())],
         f"({jobs_sql(kinds_all, today - timedelta(days=29), today)}) >= 3"),
        ("tuk drivers who signed up in the last 150 days", [("vehicle_type", "tuk"), ("new_days", 150), ("new_by", "joined"), *ALL_JOBS],
         "d.vehicle_type = 'tuk' and u.created_at >= now() - interval '150 days'"),
        ("drivers approved in the last 150 days with 2+ parcels",
         [("new_days", 150), ("new_by", "approved"), ("min_jobs", 2), ("job_types", "parcels")],
         f"d.approved_at >= now() - interval '150 days' and ({jobs_sql(['parcels'])}) >= 2"),
    ]
    for label, params, where in cases:
        _, page = superadmin.get("/admin/driver-wallet?" + urllib.parse.urlencode([("f", "1"), *params]))
        want = int(sql(f"select count(*) from drivers d join users u on u.id = d.user_id where d.is_approved and {where}"))
        check(f"{label}: {want}", found(page) == want and want > 0, f"page shows {found(page)}")
    _, page = superadmin.get("/admin/driver-wallet?f=1&min_jobs=5&max_jobs=2&job_types=rides")
    check("'at least' above 'at most' is explained, nothing listed", "be more than" in page and found(page) is None)
    _, page = superadmin.get("/admin/driver-wallet?f=1&min_jobs=1")
    check("counting jobs with no kind ticked is explained", "Tick at least one kind of job" in page)
    fewest = int(sql(f"select min({jobs_sql(kinds_all)}) from drivers d where d.is_approved and d.vehicle_type = 'car'"))
    newbies = [("f", "1"), ("vehicle_type", "car"), ("max_jobs", fewest), *ALL_JOBS]
    _, page = superadmin.get("/admin/driver-wallet?" + urllib.parse.urlencode(newbies))
    n = found(page)
    _, page = superadmin.post("/admin/driver-wallet/give", newbies + [
        ("amount", 75), ("note", "First trips bonus"), ("expires_on", today.isoformat()), ("expected_count", n)])
    check(f"bonus to the {n} car drivers with at most {fewest} jobs", n and f"bonus given to {n} driver" in page, f"{n} drivers")
    _, page = superadmin.get("/admin/driver-wallet")
    check("the bonus list says who it was for", f"Car drivers · at most {fewest} completed jobs" in page)
    check("the filter is stored with the bonus", sql("select filters->>'max_jobs' from driver_wallet_grants "
                                                     "where note = 'First trips bonus'") == str(fewest))

    print("\n8. Other pages")
    st, page = superadmin.get("/admin/driver-wallet")
    check("bonus list shows all the bonuses", all(x in page for x in (note1, note2, "Unblock", note3)), f"HTTP {st}")
    st, page = superadmin.get("/admin/withdrawals")
    check("wallet payments are not listed as payouts", st == 200 and "Commission paid from bonus wallet" not in page,
          f"HTTP {st}")

    print("\n9. Restart keeps every record")
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

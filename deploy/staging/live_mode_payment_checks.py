"""Live-mode payment checks: card payments, test cards and free top-ups refused on live.

Runs a throwaway backend exactly like the live server (DEV_MODE off, no gateway
keys) on a throwaway copy of the staging database. Neither the live site nor
the staging site is touched, and both throwaways are removed at the end.

Phase 1 (DEV_MODE on): log in, create pretend cards, and start a card-paid trip.
Phase 2 (DEV_MODE off, same secret so the logins stay valid): every check.

    python3 deploy/staging/live_mode_payment_checks.py <backend image> [--sandbox-keys]
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

IMAGE = sys.argv[1]
# --sandbox-keys: phase 2 also gets iPay sandbox keys, like the live server has.
SANDBOX = "--sandbox-keys" in sys.argv[2:]
SANDBOX_ENV = ["-e", "IPAY_MERCHANT_ID=TESTMERCHANT", "-e", "IPAY_SECRET_KEY=testsecret", "-e", "IPAY_APP_ID=TESTAPP",
               "-e", "IPAY_APP_SECRET=testappsecret", "-e", "IPAY_MODE=sandbox"]
NAME = "ziggo_livemode_test"
COPY_DB = "ziggo_livemode"
NET = "ziggo_staging_ziggo_staging_net"
BASE = "http://127.0.0.1:8032/api/v1"
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
COORDS = {"pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1]}
COMING_SOON = "Card payments are coming soon. Please pay with cash or wallet."
OFFICE = "Please settle your commission with the Ziggo office."
env = dict(l.strip().split("=", 1) for l in open("/var/www/ziggo-staging/.env") if "=" in l and not l.startswith("#"))
DB_USER = env.get("POSTGRES_USER", "ziggo_staging")
DB_PASS = env["POSTGRES_PASSWORD"]
results = []


def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()


def sql(query):
    return run("docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", DB_USER, "-d", COPY_DB,
               "-At", "-v", "ON_ERROR_STOP=1", "-c", query)


def start(dev_mode, extra_env=()):
    subprocess.run(["docker", "rm", "-f", NAME], capture_output=True)
    url = f"{DB_USER}:{DB_PASS}@ziggo_postgres_staging:5432/{COPY_DB}"
    run("docker", "run", "-d", "--name", NAME, "--network", NET, "-p", "127.0.0.1:8032:8000",
        "-e", f"DATABASE_URL=postgresql+asyncpg://{url}", "-e", f"SYNC_DATABASE_URL=postgresql+psycopg://{url}",
        "-e", "TZ=Asia/Colombo", "-e", "SECRET_KEY=livemode-test-only", "-e", f"DEV_MODE={'true' if dev_mode else 'false'}",
        *extra_env, IMAGE)
    for _ in range(60):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8032/health", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception:
            time.sleep(1)
    raise SystemExit("throwaway backend did not start:\n" + subprocess.run(
        ["docker", "logs", "--tail", "30", NAME], capture_output=True, text=True).stdout)


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


def refused(label, resp, status, message):
    s, body = resp
    got = body.get("detail") if isinstance(body, dict) else body
    check(label, s == status and got == message, f"HTTP {s}: {got}")


def count(query):
    return int(sql(query))


CUST = "(select c.id from customers c join users u on u.id = c.user_id where u.phone_number = '0771234567')"
BIKE_DRIVER = "(select d.id from drivers d join users u on u.id = d.user_id where u.phone_number = '0771000002')"

try:
    print("Copying the staging database to a throwaway database ...")
    run("docker", "exec", "ziggo_postgres_staging", "sh", "-c",
        f"dropdb -U {DB_USER} --if-exists {COPY_DB} && createdb -U {DB_USER} {COPY_DB} && "
        f"pg_dump -U {DB_USER} ziggo_staging | psql -q -U {DB_USER} -d {COPY_DB} >/dev/null")

    print("\nPhase 1: throwaway backend in TEST mode (setup)")
    start(dev_mode=True)
    customer = login("0771234567", "customer")
    tuk = login("0771000001", "driver")
    bike = login("0771000002", "driver")
    tuk_id = call("GET", "/driver/me", tuk)[1]["id"]
    s, r = call("POST", "/payments/methods/mock", customer, {})
    card = r.get("card_id") if isinstance(r, dict) else None
    check("setup: customer adds a pretend card (allowed in test mode)", s == 200 and card, f"HTTP {s}, card {card}")
    s, r = call("POST", "/payments/methods/mock", bike, {})
    driver_card = r.get("card_id") if isinstance(r, dict) else None
    check("setup: driver adds a pretend card (allowed in test mode)", s == 200 and driver_card, f"HTTP {s}, card {driver_card}")
    # Give the bike driver Rs.500 of real debt, measured from their balance (card earnings offset commission).
    bs = call("GET", "/driver/earnings-summary", bike)[1]
    sql("insert into driver_payouts (driver_id, user_id, amount, description, created_at) select id, user_id, "
        f"-({bs['pending'] - bs['outstanding_commission']} + 500), 'Commission settled (livemode test debt)', now() "
        f"from drivers where id = {BIKE_DRIVER}")
    inflight = None
    if not SANDBOX:
      call("POST", "/driver/online", tuk, {"is_online": True})
      call("POST", "/driver/location", tuk, {"lat": BORELLA[0] + 0.0027, "lng": BORELLA[1]})
      s, b = call("POST", "/bookings", customer, {"service_type": "tuk", **COORDS, "pickup_address": "Test pickup",
                                                 "drop_address": "Test drop", "payment_method": f"card_{card}"})
      check("setup: card-paid tuk booking created (test mode)", s == 201, f"HTTP {s}")
      inflight = b["id"]
      s1, _ = call("POST", f"/bookings/{inflight}/accept", tuk)
      s2, _ = call("PATCH", f"/bookings/{inflight}/status", tuk, {"status": "arrived"})
      otp = call("GET", f"/bookings/{inflight}", customer)[1].get("otp")
      s3, _ = call("PATCH", f"/bookings/{inflight}/status", tuk, {"status": "started", "otp": otp})
      check("setup: driver accepts, arrives and starts the card trip", (s1, s2, s3) == (200, 200, 200), f"HTTP {s1}/{s2}/{s3}")

    print("\nPhase 2: the same backend in LIVE mode (DEV_MODE off, " + ("iPay SANDBOX keys" if SANDBOX else "no gateway keys") + ")")
    start(dev_mode=False, extra_env=SANDBOX_ENV if SANDBOX else ())
    s, cfg = call("GET", "/payments/ipay/config")
    check("gateway reported as not connected", s == 200 and cfg.get("enabled") is False, f"HTTP {s}: {cfg}")

    gateway_off = "iPay payment gateway is not configured on this server"
    refused("gateway wallet top-up refused", call("POST", "/payments/ipay/checkout", customer, {"amount": 1000}), 503, gateway_off)
    refused("gateway card registration refused", call("POST", "/payments/ipay/preapprove", customer, {}), 503, gateway_off)
    s, r = call("POST", "/payments/ipay/notify", None, {"order_id": "WTTEST", "status_code": "2", "merchant_id": "TESTMERCHANT"})
    check("gateway callback ignored (cannot credit wallets)", s == 200 and isinstance(r, dict) and r.get("note") == "ignored",
          f"HTTP {s}: {r}")
    if inflight:
      s, done = call("PATCH", f"/bookings/{inflight}/status", tuk, {"status": "completed", "lat": NUGEGODA[0], "lng": NUGEGODA[1]})
      ok = s == 200 and isinstance(done, dict)
      check("card trip already under way finishes normally",
            ok and done.get("status") == "completed" and done.get("payment_status") == "paid",
            f"HTTP {s}, {done.get('status') if ok else done} / {done.get('payment_status') if ok else ''}")

    wallet_before = sql(f"select wallet_balance from customers where id = {CUST}")
    refused("free wallet top-up is closed", call("POST", "/customer/wallet/topup", customer, {"amount": 5000}),
            403, "Please request a wallet top-up from the app.")
    wallet_after = sql(f"select wallet_balance from customers where id = {CUST}")
    check("wallet balance unchanged", wallet_before == wallet_after, f"Rs.{wallet_before} -> Rs.{wallet_after}")
    s, _ = call("POST", "/customer/wallet/topup-request", customer, {"amount": 1000, "note": "live-mode test"})
    check("top-up REQUEST (the app's way, approved by admin) still works", s in (200, 201), f"HTTP {s}")

    cards_before = count(f"select count(*) from customer_cards where customer_id = {CUST}")
    refused("customer cannot add a pretend card", call("POST", "/payments/methods/mock", customer, {"card_no": "4111111111111111"}),
            400, COMING_SOON)
    check("no card was saved", count(f"select count(*) from customer_cards where customer_id = {CUST}") == cards_before)
    refused("driver cannot add a pretend card", call("POST", "/payments/methods/mock", bike, {}), 400, OFFICE)

    bookings_before = count(f"select count(*) from bookings where customer_id = {CUST}")
    refused("new ride booking by card refused", call("POST", "/bookings", customer, {
        "service_type": "tuk", **COORDS, "pickup_address": "x", "drop_address": "y", "payment_method": f"card_{card}"}),
        400, COMING_SOON)
    refused("scan-and-go by card refused", call("POST", f"/bookings/scan-and-go?driver_id={tuk_id}", customer, {
        "service_type": "tuk", **COORDS, "pickup_address": "x", "drop_address": "y", "payment_method": f"card_{card}"}),
        400, COMING_SOON)
    check("no booking was created", count(f"select count(*) from bookings where customer_id = {CUST}") == bookings_before)
    refused("food order by card refused", call("POST", "/food/orders", customer, {
        "restaurant_id": 8, "items": [{"menu_item_id": 28, "quantity": 1}], "payment_method": f"card_{card}",
        "is_self_pickup": True}), 400, COMING_SOON)
    refused("market order by card refused", call("POST", "/market/orders", customer, {
        "vendor_id": 9, "items": [{"product_id": 22, "quantity": 1}], "payment_method": f"card_{card}",
        "is_self_pickup": True}), 400, COMING_SOON)

    payouts_before = count(f"select count(*) from driver_payouts where driver_id = {BIKE_DRIVER}")
    refused("driver cannot settle commission by card", call("POST", "/driver/settle-commission", bike, {"card_id": driver_card}),
            400, OFFICE)
    check("no settlement was recorded", count(f"select count(*) from driver_payouts where driver_id = {BIKE_DRIVER}") == payouts_before)

    s, cash = call("POST", "/bookings", customer, {"service_type": "tuk", **COORDS, "pickup_address": "x",
                                                    "drop_address": "y", "payment_method": "cash"})
    check("cash ride booking still works", s == 201, f"HTTP {s}")
    s, food = call("POST", "/food/orders", customer, {"restaurant_id": 8, "items": [{"menu_item_id": 28, "quantity": 1}],
                                                      "payment_method": "cash", "is_self_pickup": True})
    check("cash food order still works", s == 201, f"HTTP {s}")
finally:
    subprocess.run(["docker", "rm", "-f", NAME], capture_output=True)
    subprocess.run(["docker", "exec", "ziggo_postgres_staging", "dropdb", "-U", DB_USER, "--if-exists", "--force", COPY_DB],
                   capture_output=True)
    print("\nRemoved the throwaway backend and database copy.")

fails = [r for r in results if not r[1]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for label, _, detail in fails:
    print(f"  FAILED: {label} ({detail})")
sys.exit(1 if fails else 0)

"""Admin Customer Map (Phase 2, feature 01, stage D) on the STAGING site only.

    python3 deploy/staging/customer_map_checks.py

Checks who can open the page, its feed against the database, an active trip whose
customer shares her or his location, and the phone-reveal log. The test customer
(0771234567) books a tuk ride that Test Driver 1 (0771000001) accepts; the ride is
cancelled, the driver put offline and the reveals this script made are deleted after.
"""
import http.cookiejar
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

ROOT = "https://test.ziggo.lk"
BASE = ROOT + "/api/v1"
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging", "-d", "ziggo_staging",
      "-At", "-v", "ON_ERROR_STOP=1", "-c"]
ADMIN_PW = {l.split()[0]: l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("070")}
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
results = []


def sql(q):
    return subprocess.run(DB + [q], capture_output=True, text=True, check=True).stdout.strip()


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


def admin_cookie(phone):
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    data = urllib.parse.urlencode({"phone_number": phone, "password": ADMIN_PW[phone]}).encode()
    opener.open(ROOT + "/admin/login", data=data, timeout=30).read()
    return next(c.value for c in jar if c.name == "ziggo_admin")


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))
    return ok


def ride(token, **extra):
    body = {"service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
            "drop_lng": NUGEGODA[1], "pickup_address": "Staging map test pickup",
            "drop_address": "Staging map test drop", "payment_method": "cash", **extra}
    s, b = call("POST", "/bookings", token, body)
    return b.get("id") if s == 201 else None


def share(token, bid, lat, lng):
    return call("POST", f"/bookings/{bid}/passenger-location", token, {"lat": lat, "lng": lng})


def online(token, on, km):
    call("POST", "/driver/online", token, {"is_online": on})
    if on:
        call("POST", "/driver/location", token, {"lat": BORELLA[0] + km / 111.32, "lng": BORELLA[1]})

CUSTOMER, DRIVER = "0771234567", "0771000001"
ADMINS = (("superadmin", "0700000000"), ("admin", "0700000001"), ("data_entry", "0700000002"))
LK = timezone(timedelta(hours=5, minutes=30))


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def admin_req(method, path, cookie=None, json_reply=False):
    """(status, location, body) without following redirects."""
    req = urllib.request.Request(ROOT + path, method=method, data=b"" if method == "POST" else None)
    if cookie:
        req.add_header("Cookie", f"ziggo_admin={cookie}")
    if json_reply:
        req.add_header("Accept", "application/json")
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(req, timeout=60) as r:
            return r.status, "", r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Location", ""), e.read().decode()


def keys(obj):
    if isinstance(obj, dict):
        return set(obj) | {k for v in obj.values() for k in keys(v)}
    if isinstance(obj, list):
        return {k for v in obj for k in keys(v)}
    return set()


def score(done):
    if not done:
        return 0
    days = (datetime.now(LK).date() - date.fromisoformat(done)).days
    return max(0, min(100, round(100 * (1 - days / 60))))


customer, driver = login(CUSTOMER, "customer"), login(DRIVER, "driver")
for phone in [f"077100000{k}" for k in range(2, 7)]:
    call("POST", "/driver/online", login(phone, "driver"), {"is_online": False})
cookies = {role: admin_cookie(phone) for role, phone in ADMINS}
first_reveal = int(sql("select coalesce(max(id), 0) from admin_phone_reveals"))
customer_id = int(sql(f"select c.id from customers c join users u on u.id = c.user_id where u.phone_number = '{CUSTOMER}'"))
created = []

try:
    print("Who can open it")
    for role, _ in ADMINS:
        s, loc, html = admin_req("GET", "/admin/customer-map", cookies[role])
        if role == "data_entry":
            check("data entry is sent to the forbidden page", s == 303 and loc.endswith("/admin/forbidden"), f"{s} {loc}")
        else:
            check(f"{role} opens the Customer Map", s == 200 and "customerMap" in html, s)
            check(f"{role}: reveal log shown only to super admins",
                  ("Phone reveal log" in html) == (role == "superadmin"))
            check(f"{role}: the page loads the map grouping script", "@googlemaps/markerclusterer@2.5.3" in html)
        s, _, dash = admin_req("GET", "/admin/dashboard", cookies[role])
        check(f"{role}: sidebar link {'hidden' if role == 'data_entry' else 'shown'}",
              s == 200 and ('href="/admin/customer-map"' in dash) == (role != "data_entry"))
    s, _, _ = admin_req("GET", "/admin/customer-map/feed", cookies["data_entry"], json_reply=True)
    check("data entry can't read the feed", s == 403, s)
    s, _, _ = admin_req("POST", f"/admin/customer-map/customers/{customer_id}/phone", cookies["data_entry"], json_reply=True)
    check("data entry can't reveal a phone", s == 403, s)
    s, loc, _ = admin_req("GET", "/admin/customer-map/feed")
    check("signed out goes to the login page", s in (302, 303, 307) and "/admin/login" in loc, f"{s} {loc}")

    print("Feed")
    t0 = time.time()
    s, _, raw = admin_req("GET", "/admin/customer-map/feed", cookies["admin"], json_reply=True)
    took = time.time() - t0
    feed = json.loads(raw)
    check("admin reads the feed", s == 200, f"{len(raw) // 1024} KB in {took:.1f} s, {len(feed['customers'])} customers")
    check("no phone numbers in the feed", not any("phone" in k for k in keys(feed)) and CUSTOMER not in raw)
    booked = int(sql("select count(distinct customer_id) from bookings where customer_id is not null"))
    total = int(sql("select count(*) from customers"))
    check("totals match the database", (feed["totals"]["customers"], feed["totals"]["booked"],
                                         feed["totals"]["never_booked"]) == (total, booked, total - booked),
          feed["totals"])
    bands = feed["totals"]
    check("every customer on the map is in one score band",
          bands["recent"] + bands["lapsing"] + bands["inactive"] == len(feed["customers"]))
    dot = next((c for c in feed["customers"] if c["id"] == customer_id), None)
    ref, lat = sql(f"select booking_ref || '|' || pickup_lat from bookings where customer_id = {customer_id} "
                   "order by id desc limit 1").split("|")
    done = sql(f"select (max(coalesce(completed_at, booked_at)) at time zone 'Asia/Colombo')::date from bookings "
               f"where customer_id = {customer_id} and status = 'COMPLETED' and is_flash is not true "
               "and is_courier is not true")
    check("the test customer is drawn at the pickup of the latest booking",
          dot and dot["booking_ref"] == ref and abs(dot["lat"] - float(lat)) < 1e-6, dot and dot["booking_ref"])
    check("and scored on the last completed ride", dot and dot["score"] == score(done), f"{dot and dot['score']} / {done}")

    print("An active trip")
    online(driver, True, 0.3)
    bid = ride(customer)
    created.append(bid)
    s, _ = call("POST", f"/bookings/{bid}/accept", driver)
    check("Test Driver 1 accepts", s == 200, s)
    s, _, raw = admin_req("GET", "/admin/customer-map/feed?part=active", cookies["admin"], json_reply=True)
    part = json.loads(raw)
    trip = next((t for t in part["active"] if t["booking_id"] == bid), None)
    check("part=active returns only the trips", "customers" not in part and trip is not None)
    check("waiting customer drawn at the pickup", trip and trip["source"] == "pickup"
          and abs(trip["lat"] - BORELLA[0]) < 1e-6, trip and trip["source"])
    s, _ = share(customer, bid, 6.9150, 79.8780)
    s, _, raw = admin_req("GET", "/admin/customer-map/feed?part=active", cookies["superadmin"], json_reply=True)
    trip = next((t for t in json.loads(raw)["active"] if t["booking_id"] == bid), None)
    check("sharing customer drawn at the live point", trip and trip["source"] == "live" and trip["lat"] == 6.915,
          trip and trip["source"])

    print("Phone reveals")
    s, _, raw = admin_req("POST", f"/admin/customer-map/customers/{customer_id}/phone?booking_id={bid}",
                          cookies["admin"], json_reply=True)
    check("admin reveals the phone", s == 200 and json.loads(raw)["phone"] == CUSTOMER, s)
    row = sql("select r.admin_user_id = u.id, r.customer_id, r.booking_id, r.customer_name is not null "
              "from admin_phone_reveals r join users u on u.phone_number = '0700000001' "
              f"where r.id > {first_reveal} order by r.id desc limit 1")
    check("the reveal is logged: who, which customer, which booking", row == f"t|{customer_id}|{bid}|t", row)
    s, _, _ = admin_req("POST", "/admin/customer-map/customers/999999999/phone", cookies["superadmin"], json_reply=True)
    check("an unknown customer is a 404", s == 404, s)
    s, _, html = admin_req("GET", "/admin/customer-map", cookies["superadmin"])
    name = sql(f"select coalesce(full_name, '') from users where phone_number = '{CUSTOMER}'")
    check("super admin sees it in the log", name in html.split("Phone reveal log", 1)[-1], name)

    print("Ending the trip")
    call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "staging map check"})
    created.remove(bid)
    s, _, raw = admin_req("GET", "/admin/customer-map/feed?part=active", cookies["admin"], json_reply=True)
    check("a cancelled trip leaves the active list", all(t["booking_id"] != bid for t in json.loads(raw)["active"]))
finally:
    for b in created:
        call("PATCH", f"/bookings/{b}/status", customer, {"status": "cancelled", "reason": "staging map check"})
    online(driver, False, 0)
    sql(f"delete from admin_phone_reveals where id > {first_reveal}")

passed = sum(ok for _, ok, _ in results)
print(f"\n{passed}/{len(results)} checks passed")
sys.exit(0 if passed == len(results) else 1)

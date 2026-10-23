"""Commission-free trips in a launch location, end to end on the STAGING site only.

    python3 deploy/staging/launch_trip_checks.py

Creates a Colombo launch location through the admin page, books cash tuk trips
through the app's API, ends the period while a trip is under way, and checks the
customer price, Ziggo's commission and the driver's balance. Everything it
creates is removed afterwards.
"""
import http.cookiejar
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

ROOT = "https://test.ziggo.lk"
BASE = ROOT + "/api/v1"
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging", "-d", "ziggo_staging",
      "-At", "-v", "ON_ERROR_STOP=1", "-c"]
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)   # Colombo district
ADMIN_PW = next(l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700000000"))
TODAY = datetime.now(timezone(timedelta(hours=5, minutes=30))).date()
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


admin = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def admin_post(path, fields):
    data = urllib.parse.urlencode(fields, doseq=True).encode()
    with admin.open(ROOT + path, data=data, timeout=30) as r:
        return r.status


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))


def balance():
    s = call("GET", "/driver/earnings-summary", tuk)[1]
    return round(s["pending"] - s["outstanding_commission"], 2)


COORDS = {"pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1]}


def estimate():
    return call("POST", "/bookings/estimate", customer, {"service_type": "tuk", **COORDS})[1]


def book_and_start():
    s, b = call("POST", "/bookings", customer, {"service_type": "tuk", **COORDS, "pickup_address": "x",
                                                 "drop_address": "y", "payment_method": "cash"})
    assert s == 201, (s, b)
    call("POST", f"/bookings/{b['id']}/accept", tuk)
    call("PATCH", f"/bookings/{b['id']}/status", tuk, {"status": "arrived"})
    otp = call("GET", f"/bookings/{b['id']}", customer)[1].get("otp")
    call("PATCH", f"/bookings/{b['id']}/status", tuk, {"status": "started", "otp": otp})
    return b


def complete(b):
    return call("PATCH", f"/bookings/{b['id']}/status", tuk, {"status": "completed", "lat": NUGEGODA[0], "lng": NUGEGODA[1]})[1]


customer, tuk = login("0771234567", "customer"), login("0771000001", "driver")
admin.open(ROOT + "/admin/login", data=urllib.parse.urlencode({"phone_number": "0700000000", "password": ADMIN_PW}).encode())
before_ids = sql("select coalesce(string_agg(id::text, ','), '') from launch_locations")
name = "Staging check: Colombo launch"
loc_fields = {"name": name, "kind": "district", "district": "Colombo", "start_date": (TODAY - timedelta(days=1)).isoformat(),
              "end_date": (TODAY + timedelta(days=5)).isoformat(), "services": ["rides"], "waive_delivery_cut": "on",
              "is_active": "on"}
try:
    call("POST", "/driver/online", tuk, {"is_online": True})
    call("POST", "/driver/location", tuk, {"lat": BORELLA[0] + 0.0027, "lng": BORELLA[1]})
    normal = estimate()
    check("before: normal commission", normal["platform_fee"] > 0 and not normal.get("commission_free"),
          f"Ziggo Rs.{normal['platform_fee']} of Rs.{normal['final_amount']}")

    print("\n1. Launch location created in the admin")
    admin_post("/admin/launch-locations/save", loc_fields)
    loc_id = sql(f"select id from launch_locations where name = '{name}'")
    check("saved", loc_id != "", f"id {loc_id}")
    free = estimate()
    check("customer price unchanged", free["final_amount"] == normal["final_amount"], f"Rs.{free['final_amount']}")
    check("Ziggo commission is 0, driver gets it", free["platform_fee"] == 0
          and abs(free["driver_earnings"] - normal["driver_earnings"] - normal["platform_fee"]) <= 0.02,
          f"driver Rs.{normal['driver_earnings']} -> Rs.{free['driver_earnings']}")
    check("estimate names the launch location", free.get("commission_free") == name
          and abs((free.get("commission_waived") or 0) - normal["platform_fee"]) < 0.01,
          f"{free.get('commission_free')}, waived Rs.{free.get('commission_waived')}")

    print("\n2. Booked during the period; the period ends before the trip finishes")
    bal0 = balance()
    b = book_and_start()
    admin_post("/admin/launch-locations/save", {**loc_fields, "id": loc_id,
                                                "start_date": (TODAY - timedelta(days=3)).isoformat(),
                                                "end_date": (TODAY - timedelta(days=1)).isoformat()})
    done = complete(b)
    row = sql(f"select platform_fee || '|' || coalesce(launch_location_id::text, '') from bookings where id = {b['id']}")
    check("completed at the normal customer price", isinstance(done, dict) and done.get("final_amount") == free["final_amount"],
          f"Rs.{done.get('final_amount') if isinstance(done, dict) else done}")
    check("still commission-free after the period ended", row == f"0.00|{loc_id}", row)
    bal1 = balance()
    # The passenger service fee is part of the customer's (unchanged) price and stays Ziggo's;
    # the driver collected it in cash, so only that is owed - no commission.
    fee = free.get("passenger_deductible") or 0
    check("cash trip: driver owes no commission (only the passenger fee they collected)",
          abs((bal0 - bal1) - fee) <= 0.02, f"balance Rs.{bal0} -> Rs.{bal1}, passenger fee Rs.{fee}")

    print("\n3. Booked after the period ended")
    after = estimate()
    check("commission is back for new trips", after["platform_fee"] == normal["platform_fee"]
          and not after.get("commission_free"), f"Ziggo Rs.{after['platform_fee']}")
    b2 = book_and_start()
    complete(b2)
    fee2 = float(sql(f"select platform_fee from bookings where id = {b2['id']}"))
    check("trip booked after the period pays commission", abs(fee2 - normal["platform_fee"]) < 0.01, f"Rs.{fee2}")
finally:
    call("POST", "/driver/online", tuk, {"is_online": False})
    keep = before_ids or "0"
    sql(f"delete from launch_locations where id not in ({keep})")
    print("\nRemoved the test launch location.")

fails = [r for r in results if not r[1]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for label, _, d in fails:
    print(f"  FAILED: {label} ({d})")
sys.exit(1 if fails else 0)

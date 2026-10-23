"""District base fares end to end on the STAGING site (test.ziggo.lk) only.

    python3 deploy/staging/district_fare_checks.py

Uses the admin page to set a Colombo tuk base fare and the switch, then prices
and books trips through the app's API. The switch and the district fares are put
back exactly as they were afterwards, even if a check fails.
"""
import http.cookiejar
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = "https://test.ziggo.lk"
BASE = ROOT + "/api/v1"
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging", "-d", "ziggo_staging",
      "-At", "-v", "ON_ERROR_STOP=1", "-c"]
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)       # Colombo district
NEGOMBO, NEGOMBO_BEACH = (7.2008, 79.8737), (7.2150, 79.8350)  # Gampaha district
EXTRA = 50.0
ADMIN_PW = next(l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700000000"))
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


def admin_req(path, fields=None):
    data = None if fields is None else urllib.parse.urlencode(fields).encode()
    try:
        with admin.open(ROOT + path, data=data, timeout=30) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))


def quote(pickup, drop):
    body = {"pickup_lat": pickup[0], "pickup_lng": pickup[1], "drop_lat": drop[0], "drop_lng": drop[1]}
    _, est = call("POST", "/bookings/estimate", customer, {"service_type": "tuk", **body})
    _, cards = call("POST", "/bookings/estimate/bulk", customer, {"service_types": ["tuk"], **body})
    return est, cards.get("tuk") if isinstance(cards, dict) else None


customer, tuk = login("0771234567", "customer"), login("0771000001", "driver")
was_on = sql("select district_fares_enabled from system_settings where id = 1") == "t"
saved_rows = sql("select coalesce(json_agg(row_to_json(d)), '[]') from (select district, service_type, base_fare "
                 "from district_fares) d")
national = float(sql("select base_fare from fare_settings where service_type = 'tuk'"))
try:
    admin_req("/admin/login", {"phone_number": "0700000000", "password": ADMIN_PW})
    print("\n1. Admin page")
    st, page = admin_req("/admin/fare-settings/districts?service=tuk")
    check("District base fares page loads with all 25 districts", st == 200 and page.count('name="base_') == 25, f"HTTP {st}")
    admin_req("/admin/fare-settings/districts/switch", {"enabled": "off", "service": "tuk"})
    st, _ = admin_req("/admin/fare-settings/districts/save", {"service_type": "tuk", "base_Colombo": f"{national + EXTRA:.2f}"})
    stored = sql("select base_fare from district_fares where district = 'Colombo' and service_type = 'tuk'")
    check("saving a Colombo tuk base fare stores it", st == 200 and stored and float(stored) == national + EXTRA,
          f"national Rs.{national:.2f}, Colombo Rs.{stored}")

    print("\n2. Switch OFF: nothing changes")
    sql("delete from district_fares where not (district = 'Colombo' and service_type = 'tuk')")
    off_col, off_col_card = quote(BORELLA, NUGEGODA)
    off_gam, _ = quote(NEGOMBO, NEGOMBO_BEACH)
    check("Colombo trip uses the national fare while the switch is off", "district" not in off_col_card)

    print("\n3. Switch ON")
    st, page = admin_req("/admin/fare-settings/districts/switch", {"enabled": "on", "service": "tuk"})
    check("switch turned on from the admin page", st == 200 and "district_fares_enabled" not in page
          and sql("select district_fares_enabled from system_settings where id = 1") == "t")
    on_col, on_col_card = quote(BORELLA, NUGEGODA)
    on_gam, _ = quote(NEGOMBO, NEGOMBO_BEACH)
    surge = float(on_col.get("surge_multiplier") or 1)
    diff = round(on_col["fare_amount"] - off_col["fare_amount"], 2)
    # The estimate reply has a fixed list of fields; the vehicle card carries the district label.
    check("Colombo trip uses Colombo's base fare", on_col_card.get("district") == "Colombo"
          and abs(diff - EXTRA * surge) < 0.02, f"+Rs.{diff} (expected +{EXTRA * surge:.2f})")
    check("vehicle card shows the same price", on_col_card and on_col_card["final_amount"] == on_col["final_amount"],
          f"card Rs.{on_col_card and on_col_card['final_amount']} / estimate Rs.{on_col['final_amount']}")
    check("Gampaha trip (no district fare) is unchanged", on_gam["final_amount"] == off_gam["final_amount"]
          and "district" not in on_gam, f"Rs.{off_gam['final_amount']} -> Rs.{on_gam['final_amount']}")

    print("\n4. A booked trip keeps the district price to the end")
    call("POST", "/driver/online", tuk, {"is_online": True})
    call("POST", "/driver/location", tuk, {"lat": BORELLA[0] + 0.0027, "lng": BORELLA[1]})
    priced, _ = quote(BORELLA, NUGEGODA)   # with the driver online, as the app would see it
    s, b = call("POST", "/bookings", customer, {"service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1],
                "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1], "pickup_address": "x", "drop_address": "y",
                "payment_method": "cash"})
    check("booking created at the district price", s == 201 and b["final_amount"] == priced["final_amount"],
          f"HTTP {s}, Rs.{b.get('final_amount') if isinstance(b, dict) else b}")
    bid = b["id"]
    call("POST", f"/bookings/{bid}/accept", tuk)
    call("PATCH", f"/bookings/{bid}/status", tuk, {"status": "arrived"})
    otp = call("GET", f"/bookings/{bid}", customer)[1].get("otp")
    call("PATCH", f"/bookings/{bid}/status", tuk, {"status": "started", "otp": otp})
    s, done = call("PATCH", f"/bookings/{bid}/status", tuk, {"status": "completed", "lat": NUGEGODA[0], "lng": NUGEGODA[1]})
    check("trip completed at the district price", s == 200 and done["final_amount"] == priced["final_amount"],
          f"HTTP {s}, Rs.{done.get('final_amount') if isinstance(done, dict) else done}")
    row = sql(f"select district || '|' || (fare_breakdown->>'district_base_fare') from bookings where id = {bid}")
    check("trip record shows Colombo and the district base fare", row == f"Colombo|{national + EXTRA:.1f}"
          or row == f"Colombo|{national + EXTRA}", row)
    call("POST", "/driver/online", tuk, {"is_online": False})

    print("\n5. Clearing a box goes back to the national fare")
    admin_req("/admin/fare-settings/districts/save", {"service_type": "tuk", "base_Colombo": ""})
    cleared, _ = quote(BORELLA, NUGEGODA)
    cleared_card = quote(BORELLA, NUGEGODA)[1]
    check("emptying the Colombo box removes the district fare", "district" not in cleared_card
          and cleared["fare_amount"] == off_col["fare_amount"], f"Rs.{cleared['fare_amount']} vs Rs.{off_col['fare_amount']}")
finally:
    sql(f"update system_settings set district_fares_enabled = {'true' if was_on else 'false'} where id = 1")
    sql("delete from district_fares")
    for r in json.loads(saved_rows):
        sql(f"insert into district_fares (district, service_type, base_fare) values "
            f"('{r['district']}', '{r['service_type']}', {r['base_fare']})")
    print(f"\nRestored: switch {'on' if was_on else 'off'}, {len(json.loads(saved_rows))} district fare(s).")

fails = [r for r in results if not r[1]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for label, _, d in fails:
    print(f"  FAILED: {label} ({d})")
sys.exit(1 if fails else 0)

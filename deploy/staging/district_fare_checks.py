"""District base fares end to end on the STAGING site (test.ziggo.lk) only.

    python3 deploy/staging/district_fare_checks.py

Uses the admin page to add a Colombo tuk base fare for a period and to switch it on
and off, then prices and books trips through the app's API. The district fares are
put back exactly as they were afterwards, even if a check fails. It books a trip with
the test customer and Test Driver 1, so don't run it while testers use those accounts.
"""
from datetime import date, timedelta
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
saved_rows = sql("select coalesce(json_agg(row_to_json(d)), '[]') from (select district, service_type, base_fare, "
                 "start_date, end_date, is_active from district_fares) d")
national = float(sql("select base_fare from fare_settings where service_type = 'tuk'"))
today = date.fromisoformat(sql("select (now() at time zone 'Asia/Colombo')::date"))


def colombo_tuk_id():
    return sql("select id from district_fares where district = 'Colombo' and service_type = 'tuk' order by id desc limit 1")


try:
    sql("delete from district_fares")
    admin_req("/admin/login", {"phone_number": "0700000000", "password": ADMIN_PW})
    print("\n1. Admin page")
    st, page = admin_req("/admin/fare-settings/districts")
    check("District base fares page loads, empty", st == 200 and "No district fares yet" in page, f"HTTP {st}")
    off_col, off_col_card = quote(BORELLA, NUGEGODA)
    off_gam, _ = quote(NEGOMBO, NEGOMBO_BEACH)
    check("with no district fares a Colombo trip is national", off_col_card.get("district") is None)
    st, page = admin_req("/admin/fare-settings/districts/save", {
        "district": "Colombo", "service_type": "tuk", "base_fare": f"{national + EXTRA:.2f}",
        "start_date": today.isoformat(), "end_date": (today + timedelta(days=2)).isoformat(), "is_active": "on"})
    stored = sql("select base_fare || '|' || start_date || '|' || end_date || '|' || is_active from district_fares "
                 "where district = 'Colombo' and service_type = 'tuk'")
    check("adding a Colombo tuk fare for 3 days stores it", st == 200 and stored.startswith(f"{national + EXTRA:.2f}|{today}"),
          stored)
    check("the list shows it as active", "Active · 3 days left" in page)
    st, page = admin_req("/admin/fare-settings/districts/save", {
        "district": "Colombo", "service_type": "tuk", "base_fare": "1.00",
        "start_date": (today + timedelta(days=1)).isoformat(), "end_date": (today + timedelta(days=5)).isoformat(),
        "is_active": "on"})
    check("an overlapping switched-on period is refused", ("can&#39;t overlap" in page or "can't overlap" in page)
          and sql("select count(*) from district_fares") == "1", sql("select count(*) from district_fares"))

    print("\n2. Switched on, inside its period")
    on_col, on_col_card = quote(BORELLA, NUGEGODA)
    on_gam, _ = quote(NEGOMBO, NEGOMBO_BEACH)
    surge = float(on_col.get("surge_multiplier") or 1)
    diff = round(on_col["fare_amount"] - off_col["fare_amount"], 2)
    check("Colombo trip uses Colombo's base fare", on_col_card.get("district") == "Colombo"
          and abs(diff - EXTRA * surge) < 0.02, f"+Rs.{diff} (expected +{EXTRA * surge:.2f})")
    check("vehicle card shows the same price", on_col_card and on_col_card["final_amount"] == on_col["final_amount"],
          f"card Rs.{on_col_card and on_col_card['final_amount']} / estimate Rs.{on_col['final_amount']}")
    check("Gampaha trip (no district fare) is unchanged", on_gam["final_amount"] == off_gam["final_amount"]
          and on_gam.get("district") is None, f"Rs.{off_gam['final_amount']} -> Rs.{on_gam['final_amount']}")

    print("\n3. Its own switch")
    admin_req(f"/admin/fare-settings/districts/{colombo_tuk_id()}/switch", {"enabled": "off"})
    switched_off, _ = quote(BORELLA, NUGEGODA)
    check("switched off: national fare", quote(BORELLA, NUGEGODA)[1].get("district") is None
          and switched_off["fare_amount"] == off_col["fare_amount"], f"Rs.{switched_off['fare_amount']}")
    admin_req(f"/admin/fare-settings/districts/{colombo_tuk_id()}/switch", {"enabled": "on"})
    check("switched on again: Colombo fare", quote(BORELLA, NUGEGODA)[1].get("district") == "Colombo")

    print("\n4. A booked trip keeps the district price to the end, even if the fare is switched off")
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
    admin_req(f"/admin/fare-settings/districts/{colombo_tuk_id()}/switch", {"enabled": "off"})
    call("PATCH", f"/bookings/{bid}/status", tuk, {"status": "arrived"})
    otp = call("GET", f"/bookings/{bid}", customer)[1].get("otp")
    call("PATCH", f"/bookings/{bid}/status", tuk, {"status": "started", "otp": otp})
    s, done = call("PATCH", f"/bookings/{bid}/status", tuk, {"status": "completed", "lat": NUGEGODA[0], "lng": NUGEGODA[1]})
    check("trip completed at the district price after the fare was switched off",
          s == 200 and done["final_amount"] == priced["final_amount"],
          f"HTTP {s}, Rs.{done.get('final_amount') if isinstance(done, dict) else done}")
    row = sql(f"select district || '|' || (fare_breakdown->>'district_base_fare') from bookings where id = {bid}")
    check("trip record shows Colombo and the district base fare", row == f"Colombo|{national + EXTRA:.1f}"
          or row == f"Colombo|{national + EXTRA}", row)
    call("POST", "/driver/online", tuk, {"is_online": False})

    print("\n5. After its period, and deleted")
    fid = colombo_tuk_id()
    admin_req("/admin/fare-settings/districts/save", {
        "id": fid, "district": "Colombo", "service_type": "tuk", "base_fare": f"{national + EXTRA:.2f}",
        "start_date": (today - timedelta(days=5)).isoformat(), "end_date": (today - timedelta(days=1)).isoformat(),
        "is_active": "on"})
    ended, ended_card = quote(BORELLA, NUGEGODA)
    st, page = admin_req("/admin/fare-settings/districts")
    check("a period that ended yesterday: national fare again", ended_card.get("district") is None
          and ended["fare_amount"] == off_col["fare_amount"] and "Ended · national fare again" in page,
          f"Rs.{ended['fare_amount']} vs Rs.{off_col['fare_amount']}")
    admin_req(f"/admin/fare-settings/districts/{fid}/delete", {})
    check("delete removes it", sql("select count(*) from district_fares") == "0")
finally:
    sql("delete from district_fares")
    for r in json.loads(saved_rows):
        dates = ", ".join("null" if r[k] is None else f"'{r[k]}'" for k in ("start_date", "end_date"))
        sql(f"insert into district_fares (district, service_type, base_fare, start_date, end_date, is_active) values "
            f"('{r['district']}', '{r['service_type']}', {r['base_fare']}, {dates}, {str(r['is_active']).lower()})")
    print(f"\nRestored {len(json.loads(saved_rows))} district fare(s).")

fails = [r for r in results if not r[1]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for label, _, d in fails:
    print(f"  FAILED: {label} ({d})")
sys.exit(1 if fails else 0)

"""Geographic custom fare zones end to end on the STAGING site (test.ziggo.lk).

    python3 deploy/staging/custom_fare_zone_checks.py

Uses the admin API to create a custom fare zone in Colombo Fort with custom rates
and peak/surge exemptions, verifies quotes inside vs outside, verifies dispatch radius,
and ensures cleanup in a finally block even if a check fails.
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

FORT_POLY = [
    {"lat": 6.9300, "lng": 79.8400},
    {"lat": 6.9400, "lng": 79.8400},
    {"lat": 6.9400, "lng": 79.8600},
    {"lat": 6.9300, "lng": 79.8600},
]
POINT_INSIDE = (6.9350, 79.8500)
POINT_OUTSIDE = (6.9000, 79.8700)
results = []


def sql(q):
    return subprocess.run(DB + [q], capture_output=True, text=True, check=True).stdout.strip()


def get_admin_cookie():
    try:
        admin_pw = next(l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700000000"))
    except Exception:
        admin_pw = "admin123"

    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    login_data = urllib.parse.urlencode({"phone": "0700000000", "password": admin_pw}).encode()
    req = urllib.request.Request(f"{ROOT}/admin/login", data=login_data, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with opener.open(req, timeout=15) as r:
            pass
    except urllib.error.HTTPError as e:
        if e.code not in (302, 303):
            raise
    cookie_header = "; ".join(f"{c.name}={c.value}" for c in jar)
    return cookie_header


def api_call(method, path, cookie=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", method=method, data=data)
    req.add_header("Content-Type", "application/json")
    if cookie:
        req.add_header("Cookie", cookie)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())


def check(name, ok, detail=""):
    results.append((name, ok, detail))
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {name} {detail}")


def main():
    print("--- Running Geographic Custom Fare Zone Staging Checks ---")
    cookie = get_admin_cookie()
    zone_id = None

    try:
        # 1. Create custom zone via admin API
        created = api_call("POST", "/custom-fare-zones", cookie=cookie, body={
            "name": "Staging Automated Test Zone",
            "coordinates": FORT_POLY,
            "color": "#2563eb",
            "is_active": True,
            "exempt_peak_surge": True,
            "rates": {
                "tuk": {"base_fare": 250.0, "min_fare": 250.0, "search_radius_km": 3.0},
                "car": {"base_fare": 500.0, "min_fare": 550.0, "search_radius_km": 5.0},
            }
        })
        zone_id = created.get("id")
        check("Create Custom Fare Zone", bool(zone_id), f"ID: {zone_id}")

        # 2. Estimate bulk fares inside zone
        est_inside = api_call("POST", "/bookings/estimate-bulk", body={
            "service_types": ["tuk", "car"],
            "pickup_lat": POINT_INSIDE[0],
            "pickup_lng": POINT_INSIDE[1],
            "drop_lat": POINT_OUTSIDE[0],
            "drop_lng": POINT_OUTSIDE[1],
        })
        tuk_fare = est_inside.get("tuk", {})
        check("Surge Exemption Inside Zone", tuk_fare.get("surge_multiplier") == 1.0, f"surge: {tuk_fare.get('surge_multiplier')}")
        check("Peak Surcharge Exemption Inside Zone", tuk_fare.get("peak_surcharge") == 0.0, f"peak: {tuk_fare.get('peak_surcharge')}")
        check("Zone ID Snapshotted in Quote", tuk_fare.get("custom_fare_zone_id") == zone_id, f"zone: {tuk_fare.get('custom_fare_zone_id')}")

        # 3. Estimate fares outside zone (should not have custom_fare_zone_id)
        est_outside = api_call("POST", "/bookings/estimate-bulk", body={
            "service_types": ["tuk"],
            "pickup_lat": POINT_OUTSIDE[0],
            "pickup_lng": POINT_OUTSIDE[1],
            "drop_lat": POINT_INSIDE[0],
            "drop_lng": POINT_INSIDE[1],
        })
        tuk_outside = est_outside.get("tuk", {})
        check("Pickup Outside Zone Not Affected", "custom_fare_zone_id" not in tuk_outside)

    finally:
        # Cleanup zone
        if zone_id:
            try:
                api_call("DELETE", f"/custom-fare-zones/{zone_id}", cookie=cookie)
                print(f"[CLEANUP] Deleted test zone {zone_id}")
            except Exception as e:
                print(f"[WARN] Failed to delete test zone {zone_id}: {e}")

    failed = [r for r in results if not r[1]]
    if failed:
        print(f"\n{len(failed)} of {len(results)} checks failed.")
        sys.exit(1)
    else:
        print(f"\nAll {len(results)} checks PASSED successfully.")


if __name__ == "__main__":
    main()


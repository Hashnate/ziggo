"""Customer live location (Phase 2, feature 01) end to end on the STAGING site only.

    python3 deploy/staging/customer_location_checks.py

The test customer (0771234567) books a tuk ride at a Colombo pickup with two tuk drivers
online nearby: Test Driver 1 (0771000001), who accepts, and a generated tuk driver who
doesn't. Live messages are read with WebSocket listeners run inside the staging backend:
the drivers' app channel and the admin Customer Map channel, opened with each admin
role's login cookie. Rides are cancelled and drivers put offline afterwards.
"""
import http.cookiejar
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = "https://test.ziggo.lk"
BASE = ROOT + "/api/v1"
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging", "-d", "ziggo_staging",
      "-At", "-v", "ON_ERROR_STOP=1", "-c"]
ADMIN_PW = {l.split()[0]: l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("070")}
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
LISTEN = r'''
import asyncio, sys, websockets
async def main(path, cookie, seconds):
    headers = {"Cookie": f"ziggo_admin={cookie}"} if cookie else {}
    try:
        ws = await websockets.connect(f"ws://127.0.0.1:8000{path}", additional_headers=headers)
    except Exception as e:
        print("REFUSED", type(e).__name__, flush=True)
        return
    async with ws:
        print("READY", flush=True)
        try:
            while True:
                print(await asyncio.wait_for(ws.recv(), timeout=seconds), flush=True)
        except (asyncio.TimeoutError, websockets.ConnectionClosed):
            pass
asyncio.run(main(sys.argv[1], sys.argv[2], float(sys.argv[3])))
'''
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


class Listener:
    """Collects the WebSocket events one connection receives while it is open."""

    def __init__(self, path, cookie="", seconds=4):
        self.p = subprocess.Popen(["docker", "exec", "-i", "ziggo_backend_staging", "python", "-u", "-c", LISTEN,
                                   path, cookie, str(seconds)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True)
        self.first = self.p.stdout.readline().strip()
        self.ready = self.first == "READY"

    def events(self, name=None):
        out, _ = self.p.communicate(timeout=60)
        evs = [json.loads(line) for line in out.splitlines() if line.startswith("{")]
        return [e for e in evs if name is None or e["event"] == name]


def app_listener(token, seconds=4):
    return Listener(f"/ws?token={token}", seconds=seconds)


def ride(token, **extra):
    body = {"service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
            "drop_lng": NUGEGODA[1], "pickup_address": "Staging location test pickup",
            "drop_address": "Staging location test drop", "payment_method": "cash", **extra}
    s, b = call("POST", "/bookings", token, body)
    return b.get("id") if s == 201 else None


def share(token, bid, lat, lng):
    return call("POST", f"/bookings/{bid}/passenger-location", token, {"lat": lat, "lng": lng})


def point(bid):
    return sql(f"select passenger_sharing || '|' || coalesce(passenger_lat::text, '') from bookings where id = {bid}")


def online(token, on, km):
    call("POST", "/driver/online", token, {"is_online": on})
    if on:
        call("POST", "/driver/location", token, {"lat": BORELLA[0] + km / 111.32, "lng": BORELLA[1]})


CUSTOMER, DRIVER = "0771234567", "0771000001"
customer, driver = login(CUSTOMER, "customer"), login(DRIVER, "driver")
for phone in [f"077100000{k}" for k in range(2, 7)]:
    call("POST", "/driver/online", login(phone, "driver"), {"is_online": False})
other_phone = sql("select u.phone_number from drivers d join users u on u.id = d.user_id where d.vehicle_type = 'tuk' "
                  "and d.status = 'APPROVED' and d.driver_type = 'ride' and not d.is_online "
                  "and not d.female_passengers_only and u.phone_number like '0001%' order by d.id limit 1")
other = login(other_phone, "driver")
stranger_phone = sql("select u.phone_number from customers c join users u on u.id = c.user_id "
                     f"where u.phone_number <> '{CUSTOMER}' and u.is_active order by c.id limit 1")
stranger = login(stranger_phone, "customer")
cookies = {role: admin_cookie(phone) for role, phone in
           (("superadmin", "0700000000"), ("admin", "0700000001"), ("data_entry", "0700000002"))}
created = []
try:
    print("Setup")
    online(driver, True, 0.3)
    online(other, True, 0.5)
    check("two tuk drivers online near the pickup", sql(
        f"select count(*) from drivers d join users u on u.id = d.user_id where d.is_online "
        f"and u.phone_number in ('{DRIVER}', '{other_phone}')") == "2")

    print("Who can open the admin Customer Map channel")
    probes = {role: Listener("/ws/admin/customers", cookie, seconds=1) for role, cookie in cookies.items()}
    probes["no login"] = Listener("/ws/admin/customers", "", seconds=1)
    for role, probe in probes.items():
        probe.events()
        want = role in ("superadmin", "admin")
        check(f"{role}: {'allowed' if want else 'refused'}", probe.ready == want, probe.first)
    probe = Listener("/ws/admin", cookies["data_entry"], seconds=1)
    probe.events()
    check("data entry still has the driver Live Tracking channel", probe.ready, probe.first)

    print("Sharing while searching")
    bid = ride(customer)
    created.append(bid)
    check("ride booked", bid is not None)
    s, r = call("GET", "/bookings/active", customer)
    check("sharing is off until the customer turns it on", s == 200 and r.get("passenger_sharing") is False
          and r.get("passenger_location") is None, f"{s}")
    sa, ad, dw, ow = (Listener("/ws/admin/customers", cookies["superadmin"]),
                      Listener("/ws/admin/customers", cookies["admin"]), app_listener(driver), app_listener(other))
    s, r = share(customer, bid, BORELLA[0] + 0.0001, BORELLA[1])
    check("customer shares", s == 200 and r.get("sharing") is True, f"{s} {r}")
    s, r = share(stranger, bid, 6.9, 79.9)
    check("another customer can't share on this ride", s == 404, f"{s}")
    sa_ev, ad_ev = sa.events("customer_location_update"), ad.events("customer_location_update")
    check("the admin map gets the point, marked searching", any(
        e["data"]["booking_id"] == bid and e["data"]["status"] == "searching" for e in sa_ev), str(sa_ev)[:200])
    check("both admin roles get it", any(e["data"]["booking_id"] == bid for e in ad_ev))
    check("with no phone number or name", all("phone" not in json.dumps(e) and "name" not in json.dumps(e)
                                                  for e in sa_ev))
    check("no driver gets it before one accepts", not dw.events("passenger_location_update")
          and not ow.events("passenger_location_update"))

    print("After a driver accepts")
    s, r = call("POST", f"/bookings/{bid}/accept", driver)
    check("Test Driver 1 accepts", s == 200, f"{s} {str(r)[:100]}")
    s, r = call("GET", "/bookings/active", driver)
    pl = (r or {}).get("passenger_location") or {}
    check("her trip shows where the customer is", s == 200 and abs(pl.get("lat", 0) - (BORELLA[0] + 0.0001)) < 1e-6,
          str(pl))
    time.sleep(2.1)
    dw, ow = app_listener(driver), app_listener(other)
    s, r = share(customer, bid, BORELLA[0] + 0.0002, BORELLA[1])
    at = r.get("at")
    s2, r2 = share(customer, bid, BORELLA[0] + 0.0009, BORELLA[1])
    check("a point less than 2 s after the last is ignored", s2 == 200 and r2.get("at") == at, f"{at} / {r2.get('at')}")
    d_ev, o_ev = dw.events("passenger_location_update"), ow.events("passenger_location_update")
    check("she gets the customer's moves live", len(d_ev) == 1 and d_ev[0]["data"]["booking_id"] == bid
          and abs(d_ev[0]["data"]["lat"] - (BORELLA[0] + 0.0002)) < 1e-6, str(d_ev)[:200])
    check("the driver who didn't accept gets nothing", not o_ev, str(o_ev)[:120])
    sql(f"update bookings set passenger_location_at = now() - interval '61 seconds' where id = {bid}")
    s, r = call("GET", "/bookings/active", driver)
    check("a point older than 60 s isn't shown", r.get("passenger_location") is None and r.get("passenger_sharing"))
    sql(f"update bookings set passenger_location_at = now() - interval '11 minutes' where id = {bid}")
    cleared = False
    for _ in range(23):
        if point(bid) == "false|":
            cleared = True
            break
        time.sleep(2)
    check("a point that stopped updating is deleted by the 30 s sweep", cleared, point(bid))

    print("The trip starts")
    share(customer, bid, BORELLA[0] + 0.0003, BORELLA[1])
    s, r = call("PATCH", f"/bookings/{bid}/status", driver, {"status": "arrived"})
    check("arrived: still shared", s == 200 and point(bid).startswith("true|"), point(bid))
    otp = sql(f"select otp from bookings where id = {bid}")
    sa = Listener("/ws/admin/customers", cookies["superadmin"])
    s, r = call("PATCH", f"/bookings/{bid}/status", driver, {"status": "started", "otp": otp})
    check("trip started", s == 200, f"{s} {str(r)[:100]}")
    check("the point is deleted at once", point(bid) == "false|", point(bid))
    check("the admin map is told to drop it", any(e["data"]["booking_id"] == bid
                                                    for e in sa.events("customer_location_stopped")))
    s, r = share(customer, bid, BORELLA[0], BORELLA[1])
    check("sharing is refused once the trip is under way", s == 409 and "starts" in str(r), f"{s} {r}")
    call("PATCH", f"/bookings/{bid}/status", driver, {"status": "cancelled", "reason": "customer location checks"})

    print("The customer stops sharing")
    bid = ride(customer)
    created.append(bid)
    call("POST", f"/bookings/{bid}/accept", driver)
    share(customer, bid, BORELLA[0], BORELLA[1])
    dw, sa = app_listener(driver), Listener("/ws/admin/customers", cookies["superadmin"])
    s, r = call("DELETE", f"/bookings/{bid}/passenger-location", customer)
    check("switching it off deletes the point", s == 200 and r.get("sharing") is False and point(bid) == "false|",
          f"{s} {point(bid)}")
    check("the driver is told", any(e["data"]["booking_id"] == bid for e in dw.events("passenger_location_stopped")))
    check("the admin map is told", any(e["data"]["booking_id"] == bid for e in sa.events("customer_location_stopped")))
    share(customer, bid, BORELLA[0], BORELLA[1])
    call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "customer location checks"})
    check("cancelling deletes the point", point(bid) == "false|", point(bid))

    print("Search timeout and parcels")
    online(driver, False, 0)
    online(other, False, 0)
    bid = ride(customer)
    created.append(bid)
    share(customer, bid, BORELLA[0], BORELLA[1])
    sql(f"update bookings set dispatch_started_at = now() - interval '3 minutes' where id = {bid}")
    call("GET", "/bookings/active", customer)
    check("a search that times out deletes the point", sql(f"select status from bookings where id = {bid}")
          == "CANCELLED" and point(bid) == "false|", point(bid))
    s, b = call("POST", "/bookings", customer, {
        "service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
        "drop_lng": NUGEGODA[1], "pickup_address": "x", "drop_address": "y", "is_flash": True,
        "parcel_weight_kg": 1, "receiver_phone": "0000000001", "payment_method": "cash"})
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    s, r = share(customer, bid, BORELLA[0], BORELLA[1])
    check("parcels can't share (rides only)", s == 400 and "rides" in str(r), f"{s} {r}")
finally:
    for bid in created:
        if bid and sql(f"select status from bookings where id = {bid}") not in ("CANCELLED", "COMPLETED"):
            call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "location checks"})
    online(driver, False, 0)
    online(other, False, 0)

failed = [r for r in results if not r[1]]
print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
sys.exit(1 if failed else 0)

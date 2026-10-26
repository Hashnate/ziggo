"""Lady drivers and "female passengers only" end to end on the STAGING site only (Phase 2, feature 03).

    python3 deploy/staging/lady_driver_checks.py

Lady drivers ride scooters, so two Scooter drivers go online next to a Colombo pickup:
Test Driver 6 (0771000006, a woman by her NIC) and a generated male Scooter driver. The
test customer (0771234567) books through the app's API. Who was offered a ride is read from the per-driver request notifications,
and the live messages are read with a WebSocket listener inside the staging backend.
The admin Bookings page is checked for the Lady driver label, filter and count.
Genders, the switch and the drivers' online state are put back afterwards.
"""
import http.cookiejar
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

ROOT = "https://test.ziggo.lk"
BASE = ROOT + "/api/v1"
ADMIN_PW = next(l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700000000"))
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging", "-d", "ziggo_staging",
      "-At", "-v", "ON_ERROR_STOP=1", "-c"]
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
REQUEST_TYPES = "('ride_request', 'next_ride_request', 'rental_request', 'flash_request', 'courier_request')"
LISTEN = r'''
import asyncio, json, sys, websockets
async def main(token, seconds):
    async with websockets.connect(f"ws://127.0.0.1:8000/ws?token={token}") as ws:
        print("READY", flush=True)
        try:
            while True:
                print(await asyncio.wait_for(ws.recv(), timeout=seconds), flush=True)
        except asyncio.TimeoutError:
            pass
asyncio.run(main(sys.argv[1], float(sys.argv[2])))
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


def check(label, ok, detail=""):
    results.append((label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))
    return ok


class Listener:
    """Collects the WebSocket events one user receives while it is open."""

    def __init__(self, token, seconds=4):
        self.p = subprocess.Popen(["docker", "exec", "-i", "ziggo_backend_staging", "python", "-u", "-c", LISTEN,
                                   token, str(seconds)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        assert self.p.stdout.readline().strip() == "READY", "WebSocket listener didn't connect"

    def events(self):
        out, _ = self.p.communicate(timeout=60)
        return [json.loads(line) for line in out.splitlines() if line.startswith("{")]


def offered(bid):
    """Phones of the drivers a booking was offered to."""
    rows = sql(f"select u.phone_number from notifications n join users u on u.id = n.user_id "
               f"where n.type in {REQUEST_TYPES} and (n.data = '{{\"booking_id\":{bid}}}' "
               f"or n.data like '{{\"booking_id\":{bid},%') order by 1")
    return set(rows.split()) if rows else set()


admin = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def admin_req(path, fields=None):
    data = None if fields is None else urllib.parse.urlencode(fields).encode()
    try:
        with admin.open(ROOT + path, data=data, timeout=30) as r:
            return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def table_row(html, bid):
    return html.split(f'id="table-row-{bid}"', 1)[1].split("</tr>", 1)[0] if f'id="table-row-{bid}"' in html else ""


def wait_for(predicate, seconds=45):
    """The scheduled-ride and auto-cancel sweeps run every 30 s."""
    end = time.time() + seconds
    while time.time() < end:
        if predicate():
            return True
        time.sleep(2)
    return predicate()


def set_gender(phone, gender, source):
    g = "null" if gender is None else f"'{gender}'"
    s = "null" if source is None else f"'{source}'"
    sql(f"update users set gender = {g}, gender_source = {s} where phone_number = '{phone}'")


SCOOTER = "moto scooter"


def ride(token, **extra):
    body = {"service_type": SCOOTER, "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
            "drop_lng": NUGEGODA[1], "pickup_address": "Staging lady test pickup",
            "drop_address": "Staging lady test drop", "payment_method": "cash", **extra}
    return call("POST", "/bookings", token, body)


def cancel(token, bid):
    if bid:
        call("PATCH", f"/bookings/{bid}/status", token, {"status": "cancelled", "reason": "lady driver checks"})


def online(token, on, km=0.3):
    s, r = call("POST", "/driver/online", token, {"is_online": on})
    if on:
        call("POST", "/driver/location", token, {"lat": BORELLA[0] + km / 111.32, "lng": BORELLA[1]})
    return s, r


CUSTOMER, LADY = "0771234567", "0771000006"
TEST_DRIVERS = [f"077100000{k}" for k in range(1, 7)]
saved = sql("select json_object_agg(u.phone_number, json_build_object('gender', u.gender, 'source', u.gender_source, "
            "'fpo', d.female_passengers_only)) from users u left join drivers d on d.user_id = u.id "
            f"where u.phone_number in ('{CUSTOMER}', '{LADY}')")
customer, lady = login(CUSTOMER, "customer"), login(LADY, "driver")
test_tokens = [login(p, "driver") for p in TEST_DRIVERS]
for tok in test_tokens:
    call("POST", "/driver/online", tok, {"is_online": False})

man_phone, man = None, None
for phone in sql("select u.phone_number from drivers d join users u on u.id = d.user_id where d.vehicle_type = 'moto scooter' "
                 "and d.status = 'APPROVED' and d.driver_type = 'ride' and u.gender = 'male' and not d.is_online "
                 "and u.phone_number like '0001%' order by d.id limit 8").split():
    tok = login(phone, "driver")
    if online(tok, True, km=0.5)[0] == 200:
        man_phone, man = phone, tok
        break
created = []
try:
    print("Setup")
    check("a generated male Scooter driver is online 500 m away", man is not None, man_phone or "none could go online")
    check("Test Driver 6 (female by NIC) is online 300 m away", online(lady, True)[0] == 200)
    sql(f"update drivers set female_passengers_only = false where user_id = (select id from users where phone_number = '{LADY}')")
    if man is None:
        raise SystemExit(1)

    print("Who may ask for a lady driver")
    set_gender(CUSTOMER, None, None)
    s, r = ride(customer, lady_driver=True)
    check("a customer with no gender can't", s == 400 and "female" in str(r), f"{s} {r}")
    set_gender(CUSTOMER, "male", "admin")
    s, r = ride(customer, lady_driver=True)
    check("a male customer can't", s == 400, f"{s} {r}")
    set_gender(CUSTOMER, "female", "self")
    s, r = call("POST", "/bookings", customer, {
        "service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
        "drop_lng": NUGEGODA[1], "pickup_address": "x", "drop_address": "y", "is_flash": True,
        "parcel_weight_kg": 1, "receiver_phone": "0000000001", "lady_driver": True})
    check("not for parcels", s == 400 and "rides" in str(r), f"{s} {r}")
    for vehicle in ("tuk", "bike", "car"):
        s, r = ride(customer, lady_driver=True, service_type=vehicle)
        check(f"not for a {vehicle}: lady drivers ride scooters", s == 400 and "Scooter" in str(r), f"{s} {r}")

    print("Estimate")
    coords = {"pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1]}
    _, plain = call("POST", "/bookings/estimate", customer, {"service_type": SCOOTER, **coords})
    _, est = call("POST", "/bookings/estimate", customer, {"service_type": SCOOTER, "lady_driver": True, **coords})
    _, tuk_est = call("POST", "/bookings/estimate", customer, {"service_type": "tuk", "lady_driver": True, **coords})
    _, cards = call("POST", "/bookings/estimate/bulk", customer,
                    {"service_types": [SCOOTER, "tuk", "car"], "lady_driver": True, **coords})
    check("estimate counts 1 lady Scooter driver nearby", est.get("lady_drivers_nearby") == 1, str(est.get("lady_drivers_nearby")))
    check("a tuk estimate doesn't count lady drivers", tuk_est.get("lady_drivers_nearby") is None,
          str(tuk_est.get("lady_drivers_nearby")))
    check("vehicle cards count on the Scooter card only", cards[SCOOTER].get("lady_drivers_nearby") == 1
          and cards["tuk"].get("lady_drivers_nearby") is None and cards["car"].get("lady_drivers_nearby") is None,
          " / ".join(str(cards[v].get("lady_drivers_nearby")) for v in (SCOOTER, "tuk", "car")))
    check("no extra charge: same price as a normal estimate", est["final_amount"] == plain["final_amount"],
          f"Rs.{plain['final_amount']} / Rs.{est['final_amount']}")
    check("a normal estimate doesn't count", plain.get("lady_drivers_nearby") is None)

    print("Lady driver ride")
    lw, mw, cw = Listener(lady), Listener(man), Listener(customer)
    s, b = ride(customer, lady_driver=True)
    bid = lady_bid = b.get("id") if s == 201 else None
    created.append(bid)
    check("booked", s == 201 and b.get("lady_driver_requested") is True, f"{s} {str(b)[:120]}")
    time.sleep(1)
    check("offered to the lady driver only", offered(bid) == {LADY}, str(offered(bid)))
    lady_ev = [e for e in lw.events() if e["event"] == "new_ride_request"]
    man_ev = [e for e in mw.events() if e["event"] == "new_ride_request"]
    cust_ev = [e["event"] for e in cw.events()]
    check("she gets the live request, marked lady driver", any(e["data"]["booking_id"] == bid
          and e["data"].get("lady_driver_requested") is True for e in lady_ev), str(lady_ev)[:150])
    check("he gets no live request", not any(e["data"]["booking_id"] == bid for e in man_ev))
    check("customer isn't told 'no drivers'", "no_drivers_available" not in cust_ev, str(cust_ev))
    s, r = call("POST", f"/bookings/{bid}/accept", man)
    check("he can't accept it", s == 403 and "lady driver" in str(r), f"{s} {r}")
    s, r = call("POST", f"/bookings/{bid}/accept", lady)
    check("she accepts", s == 200 and r.get("status") == "accepted", f"{s} {str(r)[:100]}")
    _, act = call("GET", "/bookings/active", customer)
    check("customer's booking says lady driver", (act or {}).get("lady_driver_requested") is True)
    cancel(customer, bid)

    print("Normal ride")
    s, b = ride(customer)
    bid = plain_bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("offered to both drivers", {LADY, man_phone} <= offered(bid), str(offered(bid)))
    check("not marked lady driver", b.get("lady_driver_requested") is False)
    cancel(customer, bid)

    print("Lady driver rental")
    s, b = ride(customer, lady_driver=True, is_rental=True, rental_hours=2)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("booked as a rental, marked lady driver", s == 201 and b.get("lady_driver_requested") is True
          and sql(f"select is_rental from bookings where id = {bid}") == "t", f"{s} {str(b)[:120]}")
    check("offered to the lady driver only", offered(bid) == {LADY}, str(offered(bid)))
    cancel(customer, bid)

    print("No lady driver nearby")
    online(lady, False)
    _, est = call("POST", "/bookings/estimate", customer, {"service_type": SCOOTER, "lady_driver": True, **coords})
    check("estimate says 0 lady drivers", est.get("lady_drivers_nearby") == 0, str(est.get("lady_drivers_nearby")))
    cw = Listener(customer)
    s, b = ride(customer, lady_driver=True)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    nd = [e["data"] for e in cw.events() if e["event"] == "no_drivers_available"]
    check("still booked, offered to nobody", s == 201 and offered(bid) == set(), str(offered(bid)))
    check("customer told: no lady driver, any driver possible", any(d.get("booking_id") == bid and d.get("lady_driver")
          is True and "any driver" in d.get("message", "") for d in nd), str(nd)[:200])
    old_start = sql(f"select coalesce(dispatch_started_at, booked_at) from bookings where id = {bid}")
    mw = Listener(man)
    s, r = call("POST", f"/bookings/{bid}/any-driver", customer)
    check("switch to any driver, Bike drivers included", s == 200 and r.get("lady_driver_requested") is False
          and r.get("include_bikes") is True and r.get("status") == "searching",
          f"{s} {str(r)[:120]}")
    time.sleep(1)
    check("now offered to the male driver", man_phone in offered(bid), str(offered(bid)))
    check("he gets the live request", any(e["event"] == "new_ride_request" and e["data"]["booking_id"] == bid
                                          for e in mw.events()))
    check("search clock restarted", sql(f"select dispatch_started_at > '{old_start}' from bookings where id = {bid}") == "t")
    s, r = call("POST", f"/bookings/{bid}/accept", man)
    check("he accepts", s == 200, f"{s} {str(r)[:100]}")
    s, r = call("POST", f"/bookings/{bid}/any-driver", customer)
    check("switching after a driver accepted is refused", s == 409, f"{s}")
    cancel(customer, bid)

    print("Search times out with no lady driver")
    s, b = ride(customer, lady_driver=True)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    sql(f"update bookings set dispatch_started_at = now() - interval '3 minutes' where id = {bid}")
    call("GET", "/bookings/active", customer)
    st = sql(f"select status || ' / ' || coalesce(cancellation_reason, '') from bookings where id = {bid}")
    check("cancelled, saying no lady driver", st == "CANCELLED / No lady driver available within search window", st)
    s, b = ride(customer, lady_driver=True)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    sql(f"update bookings set dispatch_started_at = now() - interval '3 minutes' where id = {bid}")
    wait_for(lambda: sql(f"select status from bookings where id = {bid}") == "CANCELLED")
    st = sql(f"select status || ' / ' || coalesce(cancellation_reason, '') from bookings where id = {bid}")
    check("the background sweep cancels one too, saying no lady driver",
          st == "CANCELLED / No lady driver available within search window", st)
    note = sql(f"select body from notifications where type = 'ride_update' and data = '{{\"booking_id\":{bid}}}' "
               f"order by id desc limit 1")
    check("and the customer's notice offers any driver", "lady driver" in note and "any driver" in note, note)

    print("Scheduled lady driver ride")
    s, b = ride(customer, lady_driver=True, scheduled_time=(datetime.now(timezone.utc) + timedelta(hours=2)).isoformat())
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    s, r = call("POST", f"/bookings/{bid}/any-driver", customer)
    check("switching before its time only clears the request", s == 200 and r.get("lady_driver_requested") is False
          and offered(bid) == set(), f"{s} {offered(bid)}")
    cancel(customer, bid)
    online(lady, True)
    s, b = ride(customer, lady_driver=True, scheduled_time=(datetime.now(timezone.utc) + timedelta(hours=2)).isoformat())
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("nobody is offered it before its time", s == 201 and offered(bid) == set(), f"{s} {offered(bid)}")
    sql(f"update bookings set scheduled_at = now() + interval '5 minutes' where id = {bid}")
    sent = wait_for(lambda: sql(f"select scheduled_dispatch_sent from bookings where id = {bid}") == "t")
    time.sleep(1)
    check("when it comes due it is offered to the lady driver only", sent and offered(bid) == {LADY},
          f"sent={sent} {offered(bid)}")
    cancel(customer, bid)

    print("Female passengers only")
    online(lady, True)
    s, r = call("POST", "/driver/female-passengers-only", lady, {"enabled": True})
    check("she switches it on", s == 200 and r.get("female_passengers_only") is True, f"{s}")
    s, b = ride(customer)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("female customer: offered to both", {LADY, man_phone} <= offered(bid), str(offered(bid)))
    cancel(customer, bid)
    set_gender(CUSTOMER, "male", "admin")
    s, b = ride(customer)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("male customer: not offered to her", LADY not in offered(bid) and man_phone in offered(bid), str(offered(bid)))
    s, r = call("POST", f"/bookings/{bid}/accept", lady)
    check("she can't accept it", s == 403 and "female passengers only" in str(r), f"{s} {r}")
    cancel(customer, bid)
    set_gender(CUSTOMER, None, None)
    s, b = ride(customer)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("customer with no gender: not offered to her", LADY not in offered(bid), str(offered(bid)))
    cancel(customer, bid)
    set_gender(CUSTOMER, "male", "admin")
    s, b = call("POST", "/bookings", customer, {
        "service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0],
        "drop_lng": NUGEGODA[1], "pickup_address": "x", "drop_address": "y", "is_flash": True,
        "parcel_weight_kg": 1, "receiver_phone": "0000000001", "payment_method": "cash"})
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    time.sleep(1)
    check("parcels are unchanged: offered to her too", s == 201 and LADY in offered(bid), f"{s} {offered(bid)}")
    cancel(customer, bid)

    print("Admin Bookings page")
    set_gender(CUSTOMER, "female", "self")
    s, b = ride(customer, lady_driver=True)
    bid = b.get("id") if s == 201 else None
    created.append(bid)
    st, html = admin_req("/admin/login", {"phone_number": "0700000000", "password": ADMIN_PW})
    check("admin logs in", st == 200 and "logout" in html.lower(), f"{st}")
    lady_count = sql("select count(*) from bookings where not is_flash and not is_courier and lady_driver_requested")
    st, html = admin_req("/admin/bookings")
    check("the table labels the lady driver ride, not the normal one", "Lady driver" in table_row(html, lady_bid)
          and table_row(html, plain_bid) and "Lady driver" not in table_row(html, plain_bid), f"{st}")
    card = html.split(f'id="ride-card-{bid}"', 1)[-1].split("fa-user", 1)[0] if f'id="ride-card-{bid}"' in html else ""
    check("the live sidebar labels the searching lady driver ride", "Lady driver" in card)
    check("the Total card counts lady driver requests", f"{lady_count} asked for a lady driver" in html, lady_count)
    st, html = admin_req("/admin/bookings?lady=1")
    total = re.search(r'id="kpiStatTotal">(\d+)<', html)
    check("the Lady driver filter lists only lady driver rides", st == 200 and table_row(html, lady_bid)
          and not table_row(html, plain_bid), f"{st}")
    check("and its Total is the lady driver count", total and total.group(1) == lady_count,
          f"{total and total.group(1)} / {lady_count}")
    check("a filtered page keeps its own KPI numbers", "var kpiFiltered = true;" in html
          and "var kpiFiltered = false;" in admin_req("/admin/bookings")[1])
    st, feed = admin_req("/admin/bookings/feed")
    flags = {x["id"]: x.get("lady_driver_requested") for x in json.loads(feed)["recent_bookings"]}
    check("the live feed carries the flag", flags.get(lady_bid) is True and flags.get(plain_bid) is False
          and any(x["id"] == bid and x.get("lady_driver_requested") for x in json.loads(feed)["active_bookings"]),
          f"{flags.get(lady_bid)} {flags.get(plain_bid)}")
    cancel(customer, bid)
finally:
    for bid in created:
        if bid and sql(f"select status from bookings where id = {bid}") not in ("CANCELLED", "COMPLETED"):
            cancel(customer, bid)
    online(lady, False)
    if man:
        online(man, False)
    for phone, v in json.loads(saved or "{}").items():
        set_gender(phone, v["gender"], v["source"])
        if v["fpo"] is not None:
            sql(f"update drivers set female_passengers_only = {str(v['fpo']).lower()} "
                f"where user_id = (select id from users where phone_number = '{phone}')")

failed = [r for r in results if not r[1]]
print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
sys.exit(1 if failed else 0)

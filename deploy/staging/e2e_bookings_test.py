"""Complete end-to-end booking test on the STAGING site (test.ziggo.lk) only.

    python3 deploy/staging/e2e_bookings_test.py      (on the staging server, as root)

Every booking type goes through the same API the app uses: single estimate,
vehicle card, booking, driver accept, arrive, start with the customer's code,
stops, destination change, completion and payment. Prices are compared at
every step. Staging-only database tweaks are used to simulate waiting time at
a stop and to add a temporary expired promo code (removed afterwards).
"""
import json
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = "https://test.ziggo.lk/api/v1"
STAGING_DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging",
              "-d", "ziggo_staging", "-At", "-v", "ON_ERROR_STOP=1", "-c"]
ESTIMATE_FIELDS = {"promo_code", "trip_type", "is_flash", "parcel_weight_kg", "is_courier",
                   "is_rental", "rental_hours", "redeem_points", "packages", "stops"}
# Booking replies don't include platform_fee (always shown as 0), so commission is
# checked against the stored booking instead.
MONEY = ("fare_amount", "discount_amount", "final_amount", "driver_earnings")

BORELLA, NUGEGODA, DEHIWALA = (6.9147, 79.8778), (6.8649, 79.8997), (6.8511, 79.8700)
STOP = {"lat": 6.8900, "lng": 79.8850, "address": "Kirulapone (stop)"}
RECEIVER = {"receiver_name": "Staging Receiver", "receiver_phone": "0000000001"}
results = []


def sql(query):
    return subprocess.run(STAGING_DB + [query], capture_output=True, text=True, check=True).stdout.strip()


def call(method, path, token=None, body=None, base=BASE):
    req = urllib.request.Request(base + path, method=method,
                                 data=None if body is None else json.dumps(body).encode())
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


def check(trip, label, ok, detail=""):
    results.append((trip, label, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}" + (f"  ({detail})" if detail else ""))
    return bool(ok)


def money(d):
    # Booking replies show a zero discount as null; compare the amounts themselves.
    return {k: round(float(d.get(k) or 0), 2) for k in MONEY} if isinstance(d, dict) else d


def differences(a, b):
    ma, mb = money(a), money(b)
    return ", ".join(f"{k} {ma[k]} vs {mb[k]}" for k in MONEY if ma[k] != mb[k]) or "all equal"


def near(point, km=0.3):
    return (point[0] + km / 111.32, point[1])


customer = login("0771234567", "customer")
drivers = {vt: login(f"077100000{n}", "driver")
           for n, vt in enumerate(["tuk", "bike", "car", "mini", "van", "moto scooter"], start=1)}
driver_ids = {vt: call("GET", "/driver/me", tok)[1]["id"] for vt, tok in drivers.items()}
for tok in drivers.values():
    call("POST", "/driver/online", tok, {"is_online": False})


def wallet():
    return float(sql("select wallet_balance from customers c join users u on u.id = c.user_id "
                     "where u.phone_number = '0771234567'"))


def trip(name, vt, pickup, drop, extra=None, payment="cash", stops=None, scan=False,
         wait_minutes=None, new_drop=None, cancel_after_accept=False, ref_prefix="ZG", schedule=False):
    print(f"\n{name}")
    extra = dict(extra or {})
    s1, r1 = call("POST", "/driver/online", drivers[vt], {"is_online": True})
    s2, _ = call("POST", "/driver/location", drivers[vt], {"lat": near(pickup)[0], "lng": near(pickup)[1]})
    check(name, f"{vt} driver goes online 300 m from the pickup", s1 == 200 and s2 == 200,
          f"online HTTP {s1}, location HTTP {s2}" + ("" if s1 == 200 else f": {str(r1)[:100]}"))
    coords = {"pickup_lat": pickup[0], "pickup_lng": pickup[1], "drop_lat": drop[0], "drop_lng": drop[1]}
    if stops:
        extra["stops"] = stops
    est_fields = {**coords, **{k: v for k, v in extra.items() if k in ESTIMATE_FIELDS}}
    s, est = call("POST", "/bookings/estimate", customer, {"service_type": vt, **est_fields})
    s2, cards = call("POST", "/bookings/estimate/bulk", customer, {"service_types": [vt], **est_fields})
    card = cards.get(vt) if isinstance(cards, dict) else None
    check(name, "estimate and vehicle card load", s == 200 and s2 == 200 and card is not None, f"HTTP {s} / {s2}")
    if s != 200 or card is None:
        call("POST", "/driver/online", drivers[vt], {"is_online": False})
        return None, None
    check(name, "vehicle card shows the same price as the estimate", money(card) == money(est),
          f"card Rs.{card['final_amount']} / estimate Rs.{est['final_amount']}")
    body = {"service_type": vt, **coords, "pickup_address": "Staging test pickup",
            "drop_address": "Staging test drop", "payment_method": payment, **extra}
    if schedule:
        body["scheduled_time"] = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
    path = f"/bookings/scan-and-go?driver_id={driver_ids[vt]}" if scan else "/bookings"
    s, b = call("POST", path, customer, body)
    if not check(name, "booking created", s == 201, f"HTTP {s}" + ("" if s == 201 else f": {str(b)[:150]}")):
        call("POST", "/driver/online", drivers[vt], {"is_online": False})
        return None, est
    bid = b["id"]
    check(name, f"booking reference starts with {ref_prefix}", b["booking_ref"].startswith(ref_prefix), b["booking_ref"])
    check(name, "booking price = estimate (fare, discount, total, driver pay)", money(b) == money(est),
          f"booking Rs.{b['final_amount']} / estimate Rs.{est['final_amount']}; {differences(b, est)}")
    stored_fee = float(sql(f"select platform_fee from bookings where id = {bid}"))
    check(name, "stored commission = estimate's commission", abs(stored_fee - est["platform_fee"]) < 0.01,
          f"Rs.{stored_fee} / Rs.{est['platform_fee']}")
    if schedule:
        s, c = call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "complete test"})
        check(name, "scheduled booking can be cancelled", s == 200 and c.get("status") == "cancelled", f"HTTP {s}")
        call("POST", "/driver/online", drivers[vt], {"is_online": False})
        return b, est
    if not scan:
        s, b = call("POST", f"/bookings/{bid}/accept", drivers[vt])
        check(name, "driver accepts", s == 200, f"HTTP {s}" + ("" if s == 200 else f": {str(b)[:150]}"))
        if s != 200:
            call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "complete test cleanup"})
            call("POST", "/driver/online", drivers[vt], {"is_online": False})
            return None, est
        check(name, "price unchanged when the estimated driver accepts", b["final_amount"] == est["final_amount"],
              f"Rs.{est['final_amount']} -> Rs.{b['final_amount']}")
    if cancel_after_accept:
        s, c = call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "complete test"})
        check(name, "customer cancels after the driver accepted", s == 200 and c.get("status") == "cancelled", f"HTTP {s}")
        call("POST", "/driver/online", drivers[vt], {"is_online": False})
        return c, est
    agreed = b["final_amount"]
    s, _ = call("PATCH", f"/bookings/{bid}/status", drivers[vt], {"status": "arrived"})
    check(name, "driver arrives", s == 200, f"HTTP {s}")
    _, cb = call("GET", f"/bookings/{bid}", customer)
    s, _ = call("PATCH", f"/bookings/{bid}/status", drivers[vt], {"status": "started", "otp": "0000"})
    check(name, "a wrong start code is refused", s == 400, f"HTTP {s}")
    s, _ = call("PATCH", f"/bookings/{bid}/status", drivers[vt], {"status": "started", "otp": cb.get("otp")})
    check(name, "trip starts with the customer's code", s == 200, f"HTTP {s}")
    wait_charge = 0.0
    if stops:
        s, _ = call("POST", f"/bookings/{bid}/stops/1/arrive", drivers[vt])
        check(name, "driver arrives at the stop", s == 200, f"HTTP {s}")
        if wait_minutes:
            sql(f"update booking_stops set arrived_at = arrived_at - interval '{wait_minutes} minutes' "
                f"where booking_id = {bid} and order_index = 1")
        s, _ = call("POST", f"/bookings/{bid}/stops/1/depart", drivers[vt])
        check(name, "driver leaves the stop", s == 200, f"HTTP {s}")
        free_min, per_min = map(float, sql("select free_wait_seconds / 60.0, excess_rate_per_minute from booking_stops "
                                           f"where booking_id = {bid} and order_index = 1").split("|"))
        wait_charge = float(sql(f"select wait_charge from booking_stops where booking_id = {bid} and order_index = 1"))
        expected = max(0.0, (wait_minutes or 0) - free_min) * per_min
        check(name, f"waiting charge for {wait_minutes} min ({free_min:g} free, Rs.{per_min:g}/min after)",
              abs(wait_charge - expected) < 0.01, f"Rs.{wait_charge} (expected Rs.{expected:g})")
    end = drop
    if new_drop:
        s, b = call("PATCH", f"/bookings/{bid}/destination", customer,
                    {"drop_lat": new_drop[0], "drop_lng": new_drop[1], "drop_address": "Staging new drop"})
        check(name, "customer changes destination; price recalculated", s == 200,
              f"Rs.{agreed} -> Rs.{b.get('final_amount') if isinstance(b, dict) else '?'}")
        agreed, end = b["final_amount"], new_drop
    s, done = call("PATCH", f"/bookings/{bid}/status", drivers[vt], {"status": "completed", "lat": end[0], "lng": end[1]})
    completed = s == 200 and isinstance(done, dict) and done.get("status") == "completed"
    check(name, "trip completed", completed,
          f"HTTP {s}, status {done.get('status') if isinstance(done, dict) else 'server error'}")
    if completed:
        check(name, "final price = agreed price + waiting charges", abs(done["final_amount"] - (agreed + wait_charge)) < 0.01,
              f"Rs.{agreed} + Rs.{wait_charge} = Rs.{done['final_amount']}")
    else:
        # Don't leave a half-finished trip behind to skew the next ones.
        call("PATCH", f"/bookings/{bid}/status", customer, {"status": "cancelled", "reason": "complete test cleanup"})
        done = None
    call("POST", "/driver/online", drivers[vt], {"is_online": False})
    return done, est


# 1. Tuk ride, cash, with a destination change
done, est = trip("1. Tuk ride, cash, destination changed on the way", "tuk", BORELLA, NUGEGODA, new_drop=DEHIWALA)
if done:
    check("1. Tuk ride, cash, destination changed on the way", "cash payment marked paid", done.get("payment_status") == "paid",
          done.get("payment_status"))

# 2. Car ride paid from the wallet
before = wallet()
done, est = trip("2. Car ride paid from the wallet", "car", BORELLA, NUGEGODA, payment="wallet")
if done:
    after = wallet()
    check("2. Car ride paid from the wallet", "wallet debited by exactly the final price",
          abs((before - after) - done["final_amount"]) < 0.01, f"Rs.{before:.2f} -> Rs.{after:.2f} (fare Rs.{done['final_amount']})")
    tx = sql(f"select amount from wallet_transactions where reference_id = '{done['booking_ref']}' and type = 'debit'")
    check("2. Car ride paid from the wallet", "wallet transaction recorded", tx and abs(float(tx) - done["final_amount"]) < 0.01, f"Rs.{tx}")

# 3. Bike ride paid by card (staging has no gateway keys, so charges are simulated)
s, card = call("POST", "/payments/methods/mock", customer, {})
card_id = card.get("card_id") if isinstance(card, dict) else None
done, est = trip("3. Bike ride paid by saved card", "bike", BORELLA, NUGEGODA, payment=f"card_{card_id}")
if done:
    check("3. Bike ride paid by saved card", "card charged and marked paid",
          done.get("status") == "completed" and done.get("payment_status") == "paid", f"{done.get('status')} / {done.get('payment_status')}")

# 4. Return trip
oneway = call("POST", "/bookings/estimate", customer, {"service_type": "mini", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1],
                                                       "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1]})[1]
done, est = trip("4. Mini return trip", "mini", BORELLA, NUGEGODA, extra={"trip_type": "return"})
if est:
    check("4. Mini return trip", "return fare = 2.1 x one-way fare (current rule)",
          abs(est["fare_amount"] - 2.1 * oneway["fare_amount"]) < 0.02, f"Rs.{oneway['fare_amount']} x 2.1 vs Rs.{est['fare_amount']}")

# 5. One stop with 6 minutes of waiting, and two stops (over the limit)
done, est = trip("5. Van ride with a stop and 6 min waiting", "van", BORELLA, NUGEGODA, stops=[STOP], wait_minutes=6)
if est:
    check("5. Van ride with a stop and 6 min waiting", "stop fee in the price", est.get("stops_fee", 0) > 0, f"Rs.{est.get('stops_fee')}")
s, r = call("POST", "/bookings", customer, {"service_type": "van", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1],
                                            "pickup_address": "x", "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1],
                                            "drop_address": "y", "stops": [STOP, STOP]})
print("\n5b. Two stops")
check("5b. Two stops", "more stops than allowed is refused", s == 400, f"HTTP {s}: {str(r)[:90]}")

# 6. Promo code
used_before = int(sql("select used_count from promo_codes where code = 'FLAT50'"))
done, est = trip("6. Tuk ride with promo FLAT50", "tuk", BORELLA, NUGEGODA, extra={"promo_code": "FLAT50"})
if est:
    check("6. Tuk ride with promo FLAT50", "discount = 50% of the fare (cap Rs.3000)",
          abs(est["discount_amount"] - min(0.5 * est["fare_amount"], 3000)) < 0.02, f"Rs.{est['discount_amount']} off Rs.{est['fare_amount']}")
    check("6. Tuk ride with promo FLAT50", "promo use counted once",
          int(sql("select used_count from promo_codes where code = 'FLAT50'")) == used_before + 1, f"{used_before} -> {used_before + 1}")

# 7. Flash parcel
trip("7. Flash parcel, 3 kg, bike", "bike", BORELLA, NUGEGODA, ref_prefix="FL",
     extra={"is_flash": True, "parcel_type": "document", "parcel_weight_kg": 3.0, **RECEIVER})

# 8. Courier parcel
trip("8. Courier, two packages", "bike", BORELLA, NUGEGODA, ref_prefix="CR",
     extra={"is_courier": True, "parcel_type": "other", "packages": [{"weight_kg": 1.0}, {"weight_kg": 4.0}], **RECEIVER})

# 9. Rental
done, est = trip("9. Car rental, 3 hours", "car", BORELLA, BORELLA, ref_prefix="RT",
                 extra={"is_rental": True, "rental_hours": 3})
if est:
    hourly = float(sql("select coalesce(rental_hourly_rate, 1200) from fare_settings where service_type = 'car'"))
    check("9. Car rental, 3 hours", "rental fare = hourly rate x 3", abs(est["fare_amount"] - hourly * 3) < 0.01,
          f"Rs.{hourly:g} x 3 = Rs.{est['fare_amount']}")

# 10. Scan-and-go
trip("10. Scan-and-go (customer scans the tuk driver's code)", "tuk", BORELLA, NUGEGODA, scan=True)

# 11. Scheduled ride
trip("11. Scheduled ride, 2 hours ahead", "tuk", BORELLA, NUGEGODA, schedule=True)

# 12. Cancel after accept
trip("12. Customer cancels after the driver accepted", "tuk", BORELLA, NUGEGODA, cancel_after_accept=True)

# 13. Known issue check: expired promo codes
print("\n13. Expired promo code (known issue check)")
sql("insert into promo_codes (code, description, category, discount_type, discount_value, min_order_amount, used_count, "
    "is_active, valid_to) values ('STGEXPIRED', 'staging test', 'rides', 'fixed', 100, 0, 0, true, now() - interval '1 day')")
try:
    _, e = call("POST", "/bookings/estimate", customer, {"service_type": "tuk", "pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1],
                                                         "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1], "promo_code": "STGEXPIRED"})
    check("13. Expired promo code", "an expired promo code gives no discount", e.get("discount_amount") == 0,
          f"discount Rs.{e.get('discount_amount')} from a code that expired yesterday")
finally:
    sql("delete from promo_codes where code = 'STGEXPIRED'")

# 14. Admin pages for these bookings
print("\n14. Admin panel")
password = next(l.split()[-1] for l in open("/root/ziggo-staging-admin-logins.txt") if l.startswith("0700000000"))
jar = tempfile.mkstemp(suffix=".cookies")[1]
subprocess.run(["curl", "-s", "-c", jar, "-o", "/dev/null", "-X", "POST", "--data-urlencode", "phone_number=0700000000",
                "--data-urlencode", f"password={password}", "https://test.ziggo.lk/admin/login"], check=True)
for page in ("bookings", "flash", "courier", "finance", "finance/drivers", "reports", "dashboard"):
    code = subprocess.run(["curl", "-s", "-b", jar, "-o", "/dev/null", "-w", "%{http_code}", f"https://test.ziggo.lk/admin/{page}"],
                          capture_output=True, text=True).stdout
    check("14. Admin panel", f"/admin/{page} loads", code == "200", f"HTTP {code}")
subprocess.run(["rm", "-f", jar])

print("\n=========== SUMMARY ===========")
by_trip = {}
for t, label, ok, detail in results:
    by_trip.setdefault(t, []).append(ok)
for t, oks in by_trip.items():
    print(f"  {'OK  ' if all(oks) else 'FAIL'}  {t}: {sum(oks)}/{len(oks)} checks passed")
fails = [(t, l, d) for t, l, ok, d in results if not ok]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for t, l, d in fails:
    print(f"  FAILED: {t} -> {l} ({d})")
sys.exit(1 if fails else 0)

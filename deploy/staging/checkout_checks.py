"""Checkout checks on the STAGING site (test.ziggo.lk) only.

    python3 deploy/staging/checkout_checks.py

Covers what the full booking test doesn't: the promo date window in every
checkout (ride estimate, vehicle card, food, market, events) and the customer
cancellation fee path. Every temporary row (promos, event, orders, fee setting)
is removed or restored afterwards, even if a check fails.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "https://test.ziggo.lk/api/v1"
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging",
      "-d", "ziggo_staging", "-At", "-v", "ON_ERROR_STOP=1", "-c"]
BORELLA, NUGEGODA = (6.9147, 79.8778), (6.8649, 79.8997)
COORDS = {"pickup_lat": BORELLA[0], "pickup_lng": BORELLA[1], "drop_lat": NUGEGODA[0], "drop_lng": NUGEGODA[1]}
# code: (valid_from, valid_to, should the Rs.100 discount apply?)
PROMOS = {
    "STGVALID": ("now() - interval '1 day'", "now() + interval '1 day'", True),
    "STGNODATES": ("null", "null", True),
    "STGEXPIRED": ("now() - interval '2 days'", "now() - interval '1 day'", False),
    "STGNOTYET": ("now() + interval '1 day'", "now() + interval '2 days'", False),
}
FOOD = {"restaurant_id": 8, "items": [{"menu_item_id": 28, "quantity": 1}]}
MARKET = {"vendor_id": 9, "items": [{"product_id": 22, "quantity": 1}]}
results = []


def sql(query):
    return subprocess.run(DB + [query], capture_output=True, text=True, check=True).stdout.strip()


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


def wallet():
    return float(sql("select wallet_balance from customers c join users u on u.id = c.user_id "
                     "where u.phone_number = '0771234567'"))


customer = login("0771234567", "customer")
tuk = login("0771000001", "driver")
old_fee = sql("select cancellation_fee from system_settings where id = 1")
created = {"food": [], "market": []}
event_id = None
try:
    for code, (vf, vt, _) in PROMOS.items():
        sql("insert into promo_codes (code, description, category, discount_type, discount_value, min_order_amount, "
            f"used_count, is_active, valid_from, valid_to) values ('{code}', 'staging hotfix test', 'all', 'fixed', 100, "
            f"0, 0, true, {vf}, {vt})")
    event_id = sql("insert into events (name, venue, city, starts_at, is_published) values "
                   "('Staging promo test event', 'Test venue', 'Colombo', now() + interval '1 day', true) returning id").splitlines()[0]
    tier_id = int(sql(f"insert into event_ticket_tiers (event_id, name, price, capacity) values "
                      f"({event_id}, 'General', 1000, 100) returning id").splitlines()[0])

    print("\nRide estimate and vehicle card")
    for code, (_, _, applies) in PROMOS.items():
        want = 100.0 if applies else 0.0
        _, est = call("POST", "/bookings/estimate", customer, {"service_type": "tuk", **COORDS, "promo_code": code})
        _, cards = call("POST", "/bookings/estimate/bulk", customer, {"service_types": ["tuk"], **COORDS, "promo_code": code})
        card = cards.get("tuk") if isinstance(cards, dict) else {}
        check(f"ride estimate with {code}: discount Rs.{want:g}", float(est.get("discount_amount") or 0) == want,
              f"got Rs.{est.get('discount_amount')}")
        check(f"vehicle card with {code}: discount Rs.{want:g}", float(card.get("discount_amount") or 0) == want,
              f"got Rs.{card.get('discount_amount')}")

    def order(kind, code=None):
        body = {**(FOOD if kind == "food" else MARKET), "payment_method": "cash", "is_self_pickup": True}
        if code:
            body["promo_code"] = code
        s, o = call("POST", f"/{kind}/orders", customer, body)
        if s == 201:
            created[kind].append(o["id"])
        return s, o

    def event(code=None):
        body = {"items": [{"tier_id": tier_id, "quantity": 1}], "payment_method": "cash"}
        if code:
            body["promo_code"] = code
        return call("POST", f"/events/{event_id}/book", customer, body)

    # Where each checkout records the promo: food stores discount_amount, market only
    # lowers final_amount, events return discount_amount (the 1% fee is charged after it).
    def food_discount(o):
        return float(sql(f"select discount_amount from food_orders where id = {o['id']}"))

    def market_final(o):
        return float(sql(f"select final_amount from market_orders where id = {o['id']}"))

    def event_discount(o):
        return float(o["discount_amount"])

    for kind, place, measure, saved in (
        ("food", lambda c=None: order("food", c), food_discount, "discount"),
        ("market", lambda c=None: order("market", c), market_final, "final total"),
        ("event tickets", event, event_discount, "discount"),
    ):
        print(f"\n{kind.capitalize()} checkout")
        s, plain = place()
        ok = s == 201 and isinstance(plain, dict)
        check(f"{kind}: order without a promo is placed", ok, f"HTTP {s}" + ("" if ok else f": {str(plain)[:150]}"))
        if not ok:
            continue
        if kind == "food":
            alerts = sql("select count(*) from notifications n join restaurants r on r.owner_id = n.user_id "
                         f"where r.id = {FOOD['restaurant_id']} and n.type = 'new_food_order' "
                         f"and n.data = '{{\"food_order_id\":{plain['id']}}}'")
            check("food: restaurant owner gets the 'new food order' alert", alerts == "1", f"{alerts} alert(s)")
        base = measure(plain)
        for code, (_, _, applies) in PROMOS.items():
            s, o = place(code)
            got = measure(o) if s == 201 and isinstance(o, dict) else None
            if saved == "discount":
                want = 100.0 if applies else 0.0
            else:
                want = base - 100 if applies else base
            check(f"{kind} with {code}: {saved} Rs.{want:g}", got is not None and abs(got - want) < 0.01,
                  f"HTTP {s}, {saved} Rs.{got}")

    print("\nCustomer cancels 10 minutes after booking (cancellation fee Rs.50, temporarily set)")
    sql("update system_settings set cancellation_fee = 50 where id = 1")
    call("POST", "/driver/online", tuk, {"is_online": True})
    call("POST", "/driver/location", tuk, {"lat": BORELLA[0] + 0.0027, "lng": BORELLA[1]})
    s, b = call("POST", "/bookings", customer, {"service_type": "tuk", **COORDS, "pickup_address": "Staging test pickup",
                                                 "drop_address": "Staging test drop", "payment_method": "cash"})
    if s != 201:
        check("booking created", False, f"HTTP {s}: {str(b)[:150]}")
    else:
        s, _ = call("POST", f"/bookings/{b['id']}/accept", tuk)
        check("driver accepts", s == 200, f"HTTP {s}")
        sql(f"update bookings set booked_at = booked_at - interval '10 minutes' where id = {b['id']}")
        before = wallet()
        s, c = call("PATCH", f"/bookings/{b['id']}/status", customer, {"status": "cancelled", "reason": "hotfix test"})
        check("cancellation accepted", s == 200 and isinstance(c, dict) and c.get("status") == "cancelled",
              f"HTTP {s}" + ("" if s == 200 else f": {str(c)[:150]}"))
        after = wallet()
        check("Rs.50 fee debited from the wallet", abs((before - after) - 50) < 0.01, f"Rs.{before:.2f} -> Rs.{after:.2f}")
        tx = sql(f"select amount from wallet_transactions where reference_id = '{b['booking_ref']}' "
                 "and description like 'Cancellation fee%'")
        check("fee transaction recorded", tx != "" and abs(float(tx) - 50) < 0.01, f"Rs.{tx or 'none'}")
finally:
    sql(f"update system_settings set cancellation_fee = {old_fee} where id = 1")
    call("POST", "/driver/online", tuk, {"is_online": False})
    # Orders saved before a server error never reach `created`, so also sweep the
    # test customer's recent pending orders.
    cust_id = sql("select c.id from customers c join users u on u.id = c.user_id where u.phone_number = '0771234567'")
    for kind, table in (("food", "food_orders"), ("market", "market_orders")):
        stray = sql(f"select id from {table} where customer_id = {cust_id} and status::text = 'PENDING' "
                    "and created_at > now() - interval '15 minutes'").split()
        created[kind] = sorted(set(created[kind]) | {int(i) for i in stray})
        for oid in created[kind]:
            s, _ = call("POST", f"/{kind}/orders/{oid}/cancel", customer, {"reason": "staging hotfix test"})
            if s != 200:
                print(f"  note: could not cancel {kind} order {oid} (HTTP {s})")
    if event_id:
        sql(f"delete from event_order_items where order_id in (select id from event_orders where event_id = {event_id}); "
            f"delete from event_orders where event_id = {event_id}; delete from event_ticket_tiers where event_id = {event_id}; "
            f"delete from events where id = {event_id}")
    sql("delete from promo_codes where description = 'staging hotfix test'")
    print(f"\nCleaned up: {len(created['food'])} food + {len(created['market'])} market test orders cancelled, "
          f"test event and promos removed, cancellation fee back to Rs.{old_fee}")

fails = [r for r in results if not r[1]]
print(f"\n{len(results) - len(fails)}/{len(results)} checks passed")
for label, _, detail in fails:
    print(f"  FAILED: {label} ({detail})")
sys.exit(1 if fails else 0)

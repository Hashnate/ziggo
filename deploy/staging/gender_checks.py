"""Genders for the lady-driver option (Phase 2, feature 03) on the STAGING site only.

    python3 deploy/staging/gender_checks.py

The test customer (0771234567) chooses a gender once, admins correct customers on
the Riders page and drivers on the driver edit form, and only a lady driver can
ask for female passengers only. The Drivers page filters, counts and exports lady
drivers. Test Driver 1 (0771000001, tuk) is a woman by her
generated NIC; Test Driver 2 (0771000002, bike) is a man. Everything touched is
put back afterwards, even if a check fails.
"""
import csv
import http.cookiejar
import io
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = "https://test.ziggo.lk"
BASE = ROOT + "/api/v1"
DB = ["docker", "exec", "-i", "ziggo_postgres_staging", "psql", "-U", "ziggo_staging", "-d", "ziggo_staging",
      "-At", "-v", "ON_ERROR_STOP=1", "-c"]
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


def gender_of(phone):
    return sql(f"select coalesce(gender, '') || '/' || coalesce(gender_source, '') from users where phone_number = '{phone}'")


def listed(html, phone):
    return f'truncate">{phone}</p>' in html


def driver_form(driver_id, gender):
    row = sql(f"select json_build_object('phone_number', u.phone_number, 'full_name', u.full_name, 'email', "
              f"coalesce(u.email, ''), 'nic_number', d.nic_number, 'license_number', d.license_number, "
              f"'vehicle_type', d.vehicle_type, 'vehicle_number', d.vehicle_number, 'vehicle_model', "
              f"coalesce(d.vehicle_model, ''), 'vehicle_color', coalesce(d.vehicle_color, ''), "
              f"'relative_name', coalesce(d.relative_name, ''), 'relative_contact', coalesce(d.relative_contact, ''), "
              f"'relative_relationship', coalesce(d.relative_relationship, ''), 'driver_type', d.driver_type) "
              f"from drivers d join users u on u.id = d.user_id where d.id = {driver_id}")
    return {**json.loads(row), "is_approved": "1", "gender": gender}


CUSTOMER, LADY, MAN = "0771234567", "0771000001", "0771000002"
saved = sql(f"select json_object_agg(u.phone_number, json_build_object('gender', u.gender, 'source', u.gender_source, "
            f"'fpo', d.female_passengers_only)) from users u left join drivers d on d.user_id = u.id "
            f"where u.phone_number in ('{CUSTOMER}', '{LADY}', '{MAN}')")
customer_id = sql(f"select c.id from customers c join users u on u.id = c.user_id where u.phone_number = '{CUSTOMER}'")
lady_id = sql(f"select d.id from drivers d join users u on u.id = d.user_id where u.phone_number = '{LADY}'")
try:
    sql(f"update users set gender = null, gender_source = null where phone_number = '{CUSTOMER}'")
    customer, lady, man = login(CUSTOMER, "customer"), login(LADY, "driver"), login(MAN, "driver")

    print("Customer chooses once")
    _, me = call("GET", "/auth/me", customer)
    check("no gender yet", me.get("gender") is None, str(me.get("gender")))
    st, res = call("PATCH", "/customer/profile", customer, {"full_name": me.get("full_name")})
    check("saving the name doesn't set a gender", st == 200 and res.get("gender") is None, f"{st} {res}")
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "Prefer not to say"})
    check("the current app's 'Prefer not to say' leaves it empty", st == 200 and gender_of(CUSTOMER) == "/",
          f"{st} {gender_of(CUSTOMER)}")
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "female"})
    check("chooses female", st == 200 and res.get("gender") == "female", f"{st} {res}")
    check("stored as her own choice", gender_of(CUSTOMER) == "female/self", gender_of(CUSTOMER))
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "male"})
    check("can't change it herself", st == 400 and "support" in str(res), f"{st} {res}")
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "female"})
    check("sending the same answer again is fine", st == 200, f"{st} {res}")
    for older_app_value in ("Female", "Other", "Prefer not to say"):
        st, res = call("PATCH", "/customer/profile", customer, {"gender": older_app_value})
        check(f"the current app's '{older_app_value}' is accepted without changing it", st == 200
              and gender_of(CUSTOMER) == "female/self", f"{st} {gender_of(CUSTOMER)}")
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "Male"})
    check("the current app's 'Male' is refused like 'male'", st == 400, f"{st}")
    _, me = call("GET", "/auth/me", customer)
    check("/auth/me shows it", me.get("gender") == "female", str(me.get("gender")))

    print("Admin corrects a customer on the Riders page")
    st, html = admin_req("/admin/login", {"phone_number": "0700000000", "password": ADMIN_PW})
    check("admin logs in", st == 200 and "logout" in html.lower(), f"{st}")
    st, html = admin_req(f"/admin/riders?search={CUSTOMER}")
    check("Riders page shows the gender and who set it", st == 200 and "Gender</th>" in html
          and f'action="/admin/riders/{customer_id}/gender"' in html and "by rider" in html, f"{st}")
    st, _ = admin_req(f"/admin/riders/{customer_id}/gender", {"gender": "male", "back": f"/admin/riders?search={CUSTOMER}"})
    check("admin sets male", st == 200 and gender_of(CUSTOMER) == "male/admin", f"{st} {gender_of(CUSTOMER)}")
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "female"})
    check("customer can't undo the admin", st == 400, f"{st}")
    st, _ = admin_req(f"/admin/riders/{customer_id}/gender", {"gender": "none", "back": "https://example.com/"})
    check("admin clears it (and an outside 'back' link is ignored)", st == 200 and gender_of(CUSTOMER) == "/",
          f"{st} {gender_of(CUSTOMER)}")
    st, res = call("PATCH", "/customer/profile", customer, {"gender": "female"})
    check("customer can choose again after the admin clears it", st == 200 and gender_of(CUSTOMER) == "female/self",
          f"{st} {gender_of(CUSTOMER)}")

    print("Drivers")
    _, prof = call("GET", "/driver/me", lady)
    check("Test Driver 1 is female by her NIC", prof.get("gender") == "female" and gender_of(LADY) == "female/nic",
          f"{prof.get('gender')} {gender_of(LADY)}")
    check("female passengers only is off to start", prof.get("female_passengers_only") is False)
    st, res = call("POST", "/driver/female-passengers-only", lady, {"enabled": True})
    check("she switches on female passengers only", st == 200 and res.get("female_passengers_only") is True, f"{st} {res}")
    st, res = call("POST", "/driver/female-passengers-only", lady, {"enabled": False})
    check("and off again", st == 200 and res.get("female_passengers_only") is False, f"{st}")
    st, res = call("POST", "/driver/female-passengers-only", man, {"enabled": True})
    check("a male driver can't switch it on", st == 400, f"{st} {res}")

    print("Admin corrects a driver on the edit form")
    st, html = admin_req(f"/admin/drivers/{lady_id}/edit")
    check("edit form offers the gender, reading 'From NIC (Female)'", st == 200 and 'name="gender"' in html
          and "From NIC (Female)" in html, f"{st}")
    st, html = admin_req(f"/admin/drivers/{lady_id}/edit", driver_form(lady_id, "male"))
    check("admin sets male by hand", st == 200 and gender_of(LADY) == "male/admin", f"{st} {gender_of(LADY)}")
    st, html = admin_req(f"/admin/drivers/{lady_id}/edit")
    check("form now shows 'Male (set by admin)' selected", 'value="male" selected' in html)
    st, res = call("POST", "/driver/female-passengers-only", lady, {"enabled": True})
    check("as a man by the admin's say, she can't switch it on", st == 400, f"{st}")
    st, html = admin_req(f"/admin/drivers/{lady_id}/edit", driver_form(lady_id, "auto"))
    check("back to 'From NIC' makes her female again", st == 200 and gender_of(LADY) == "female/nic",
          f"{st} {gender_of(LADY)}")
    check("saving the form left her approved", sql(f"select status from drivers where id = {lady_id}") == "APPROVED",
          sql(f"select status from drivers where id = {lady_id}"))

    print("Admin driver list")
    submitted_ladies = ("from drivers d join users u on u.id = d.user_id "
                        "where coalesce(d.vehicle_number, '') <> '' and u.gender = 'female'")
    call("POST", "/driver/online", lady, {"is_online": True})
    st, html = admin_req("/admin/drivers")
    card = re.search(r'(\d+) online</span>\s*</div>\s*<p[^>]*>Lady Drivers</p>\s*<p[^>]*>(\d+)</p>', html)
    want = (sql(f"select count(*) filter (where d.is_online and d.is_approved) {submitted_ladies}"),
            sql(f"select count(*) {submitted_ladies}"))
    check("Lady Drivers card counts them and how many are online", card and card.groups() == want,
          f"{card and card.groups()} / {want}")
    call("POST", "/driver/online", lady, {"is_online": False})
    st, html = admin_req(f"/admin/drivers?gender=female&search={LADY}")
    check("lady filter lists Test Driver 1 with a Lady badge", st == 200 and listed(html, LADY) and ">Lady</span>" in html
          and ">Female passengers only</span>" not in html and "Clear Filter" in html, f"{st}")
    for gender, phone in (("male", LADY), ("female", MAN), ("unknown", LADY)):
        st, html = admin_req(f"/admin/drivers?gender={gender}&search={phone}")
        check(f"'{gender}' filter leaves out {phone}", st == 200 and not listed(html, phone), f"{st}")
    st, html = admin_req(f"/admin/drivers?gender=male&search={MAN}")
    check("'male' filter lists Test Driver 2, no Lady badge", listed(html, MAN) and ">Lady</span>" not in html)
    sql(f"update users set gender = null, gender_source = null where phone_number = '{MAN}'")
    st, html = admin_req(f"/admin/drivers?gender=unknown&search={MAN}")
    check("'not known' filter finds a driver with no gender", st == 200 and listed(html, MAN), f"{st}")
    st, html = admin_req(f"/admin/drivers?gender=nonsense&search={LADY}")
    check("an unknown filter value is ignored", st == 200 and listed(html, LADY), f"{st}")
    call("POST", "/driver/female-passengers-only", lady, {"enabled": True})
    st, html = admin_req(f"/admin/drivers?gender=female&search={LADY}")
    check("her row says Female passengers only", ">Female passengers only</span>" in html)
    st, csv_text = admin_req(f"/admin/drivers/export?gender=female&search={LADY}")
    rows = list(csv.reader(io.StringIO(csv_text)))
    check("export has Gender columns and her row", st == 200 and rows[0][-2:] == ["Gender", "Female Passengers Only"]
          and len(rows) == 2 and rows[1][2] == LADY and rows[1][-2:] == ["Female", "Yes"], f"{st} {rows[:1]} {rows[1:2]}")
    st, csv_text = admin_req(f"/admin/drivers/export?gender=male&search={LADY}")
    check("export honours the gender filter", st == 200 and len(list(csv.reader(io.StringIO(csv_text)))) == 1, f"{st}")
    call("POST", "/driver/female-passengers-only", lady, {"enabled": False})
finally:
    for phone, v in json.loads(saved or "{}").items():
        g = "null" if v["gender"] is None else f"'{v['gender']}'"
        s = "null" if v["source"] is None else f"'{v['source']}'"
        sql(f"update users set gender = {g}, gender_source = {s} where phone_number = '{phone}'")
        if v["fpo"] is not None:
            sql(f"update drivers set female_passengers_only = {str(v['fpo']).lower()} "
                f"where user_id = (select id from users where phone_number = '{phone}')")

failed = [r for r in results if not r[1]]
print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
sys.exit(1 if failed else 0)

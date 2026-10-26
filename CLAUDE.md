# CLAUDE.md — Ziggo Super App

Read this file first whenever you receive a task in this repo. It is the single source of truth for layout, conventions, and where things live so you can skip discovery and jump straight to the right file.

---

## 0. Live site, staging and branches (read first)

Ziggo is **live in production**. Two checkouts sit on the same server:

| | Live (ziggo.lk) | Staging (test.ziggo.lk) |
| --- | --- | --- |
| Folder | `/var/www/ziggo` | `/var/www/ziggo-staging` |
| Branch | `main` only | `dev` |
| Backend | `ziggo_backend` on `:8030`, Postgres `ziggo_postgres` | `ziggo_backend_staging` on `127.0.0.1:8031`, Postgres `ziggo_postgres_staging` |

- **Only `main` is ever deployed to the live site.** New work goes feature branch → `dev` (runs on staging) → `main` only at a release the owner approves.
- **Never edit files or switch branches in `/var/www/ziggo`.** A git hook puts that folder back on `main` after any checkout, and its branch list only knows `main`.
- **The live backend runs a sealed image.** `docker-compose.override.yml` in the live folder removes the code bind mounts, so code reaches customers only through a deliberate deploy: `git pull --ff-only`, then `docker build --network=host -f ziggo_backend/Dockerfile -t ziggo-ziggo_backend:latest .`, then `docker compose up -d`.
- **Staging** has its own `.env`: `DEV_MODE=true` (the API returns the OTP), no SMS or push credentials, payments in sandbox mode. `deploy/staging/refresh-data.sh` rebuilds its data from production's business setup plus generated customers, drivers and trips (no personal data). `deploy/staging/run-backend-tests.sh` runs the backend tests. Pushing a `staging-app-*` tag builds a test APK that talks only to test.ziggo.lk.
- Docker builds on this server need `--network=host`; on the default bridge network, package downloads crawl.

---

## 1. What this project is

Ziggo is a PickMe-style **ride + food + market + flash-parcel** super app for Sri Lanka.

Three deliverables live in this repo:

1. **`ziggo_app/`** — single Flutter binary that contains both the **customer** and **driver** UIs (chosen at the role-selection screen after login).
2. **`ziggo_backend/`** — FastAPI + SQLAlchemy (async) backend. It also serves the server-rendered **admin web panel** at `/admin/*`, whose code lives in the top-level `ziggo_admin_panel/`.
3. **`README.md`** — onboarding doc for a fresh dev (setup steps, demo credentials, end-to-end test flow).

Production uses Postgres 16, Notify.lk (OTP SMS), Firebase Cloud Messaging, Google Maps and Places, and the iPay / PayHere gateways. An integration whose credentials are empty falls back to a stub, which is how staging runs: the OTP is printed and returned by the API when `DEV_MODE=true`, and push notifications are skipped.

---

## 2. Repo layout

```
ziggo/
├── README.md                  Setup + demo credentials + end-to-end test
├── CLAUDE.md                  ← this file
├── ziggo_app/                 Flutter app (customer + driver)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart                          Root: providers + auth-aware routing
│   │   ├── app/
│   │   │   ├── app_theme.dart                 Material 3 light theme (Outfit font)
│   │   │   ├── app_colors.dart
│   │   │   └── app_styles.dart
│   │   ├── config/                            (currently empty)
│   │   ├── core/
│   │   │   ├── network/
│   │   │   │   ├── api_client.dart            Dio + token interceptor, baseHost picker
│   │   │   │   └── ws_client.dart             WebSocket reconnect-safe wrapper
│   │   │   ├── storage/token_storage.dart     flutter_secure_storage wrapper
│   │   │   ├── map/
│   │   │   │   ├── ziggo_map.dart             Reusable OSM map widget
│   │   │   │   └── places.dart                Hard-coded Sri Lanka POIs
│   │   │   └── widgets/                       ambient_orbs, glass_card, skeleton, etc.
│   │   └── modules/
│   │       ├── auth/
│   │       │   ├── auth_provider.dart         Status + OTP send/verify + profile
│   │       │   └── screens/                   role_selection, phone_login, otp_verification
│   │       ├── common/screens/splash_screen.dart
│   │       ├── customer/
│   │       │   ├── booking_provider.dart      Ride lifecycle + WS subscription
│   │       │   ├── wallet_provider.dart
│   │       │   ├── addresses_provider.dart
│   │       │   ├── food_provider.dart
│   │       │   ├── market_provider.dart
│   │       │   ├── promos_provider.dart
│   │       │   ├── notifications_provider.dart
│   │       │   └── screens/                   home, fare_estimate, ride_tracking, rating,
│   │       │                                  ride_history, wallet, profile, flash_*,
│   │       │                                  food_*, market_*, restaurant_detail, support_*, …
│   │       └── driver/
│   │           ├── driver_provider.dart       Online toggle, location timer, accept/decline
│   │           └── screens/                   driver_home, driver_history, driver_registration
│   ├── assets/{images,icons}/
│   ├── android/ ios/ web/ windows/ macos/ linux/
│   └── test/
└── ziggo_backend/
    ├── requirements.txt
    ├── alembic.ini  alembic/                  Migrations (env reads SYNC_DATABASE_URL)
    ├── .env                                   Loaded by app/config.py via pydantic-settings
    ├── ziggo.db                               Default SQLite file (see §5)
    ├── seed.py                                Idempotent demo-data seeder
    ├── create_db.py  reset_db.py  migrate_flash.py    One-off DB scripts
    └── app/
        ├── main.py                            FastAPI app, mounts routers + /admin
        ├── config.py                          Pydantic Settings (.env loader)
        ├── database.py                        Async engine + get_db + Base
        ├── models/                            SQLAlchemy: user, booking, food, market, misc
        ├── schemas/                           Pydantic request/response models
        ├── services/
        │   ├── auth_service.py                OTP + JWT + get_current_user + require_role
        │   ├── fare_service.py                Haversine + fare engine + promo
        │   ├── matching_service.py            Nearest online+approved driver
        │   └── ws_manager.py                  In-memory pub/sub keyed by user_id
        └── api/v1/                            JSON routers: auth, customer, driver,
                                               bookings, food, market, admin, misc, ws, …

ziggo_admin_panel/                             Jinja2 admin served at /admin/* (cookie session),
├── routes.py                                  a top-level sibling of ziggo_backend/
├── templates/                                 login, dashboard, drivers, bookings, flash, …
└── static/
```

---

## 3. Backend — quick reference

### Run

```powershell
cd ziggo_backend
pip install -r requirements.txt
alembic upgrade head      # or: alembic revision --autogenerate -m "..." && alembic upgrade head
python seed.py            # idempotent
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- API docs:    `http://localhost:8000/docs`
- Admin panel: `http://localhost:8000/admin/login`  (root `/` redirects here)
- Health:      `http://localhost:8000/health`

### Routers and prefixes (see [app/main.py](ziggo_backend/app/main.py))

| Prefix                  | File                                          | Purpose                                            |
| ----------------------- | --------------------------------------------- | -------------------------------------------------- |
| `/api/v1/auth`          | [app/api/v1/auth.py](ziggo_backend/app/api/v1/auth.py)         | `send-otp`, `verify-otp`, `me`                     |
| `/api/v1/customer`      | [app/api/v1/customer.py](ziggo_backend/app/api/v1/customer.py) | profile, addresses, wallet, notifications          |
| `/api/v1/driver`        | [app/api/v1/driver.py](ziggo_backend/app/api/v1/driver.py)     | register, location, online toggle, `me`            |
| `/api/v1/bookings`      | [app/api/v1/bookings.py](ziggo_backend/app/api/v1/bookings.py) | estimate, create, list, active, accept, decline, status, rate |
| `/api/v1/food`          | [app/api/v1/food.py](ziggo_backend/app/api/v1/food.py)         | restaurants list/detail/menu, orders               |
| `/api/v1/market`        | [app/api/v1/market.py](ziggo_backend/app/api/v1/market.py)     | vendors list, products, orders                     |
| `/api/v1/admin`         | [app/api/v1/admin.py](ziggo_backend/app/api/v1/admin.py)       | stats, create/approve/suspend drivers (JSON)       |
| `/api/v1` (misc)        | [app/api/v1/misc.py](ziggo_backend/app/api/v1/misc.py)         | promos, complaints, gold subscription              |
| `/ws`                   | [app/api/v1/ws.py](ziggo_backend/app/api/v1/ws.py)             | JWT-authed WebSocket (`?token=<jwt>`); admin cookie channels `/ws/admin` (Live Tracking) and `/ws/admin/customers` (Customer Map, superadmin/admin only) |
| `/admin/*`              | [ziggo_admin_panel/routes.py](ziggo_admin_panel/routes.py) | Jinja2 admin UI (cookie session via itsdangerous)  |

### Auth model

- Phone-OTP only (no passwords for customers/drivers). Admin panel login is phone + the admin user's stored password; an admin with no password set falls back to `admin123` (`ziggo_admin_panel/routes.py::admin_login_post`).
- `services/auth_service.py::get_current_user` is the OAuth2 bearer dependency. Use `require_role("customer"|"driver"|"admin")` to gate routes.
- Admin panel uses a separate signed cookie (`ziggo_admin`) via `itsdangerous.URLSafeSerializer`, NOT the JWT — see `ziggo_admin_panel/routes.py::current_admin`.
- WebSocket auth: token passed as `?token=` query param, decoded inline in `ws.py`.

### Booking state machine (see [app/api/v1/bookings.py](ziggo_backend/app/api/v1/bookings.py))

```
SEARCHING → ACCEPTED → ARRIVED → STARTED → COMPLETED
     │           │           │           │
     └───────────┴───────────┴───────────┴── CANCELLED   (any state above COMPLETED)
```

`VALID_TRANSITIONS` is enforced in `update_booking_status`. On `COMPLETED`:
- wallet payments → debit `Customer.wallet_balance` + write `WalletTransaction`
- driver totals → bump `Driver.total_earnings`, `today_earnings`, `today_rides`

On rate: customer rating updates the driver's aggregate `User.rating` and `User.total_rides`.

### Driver matching (see [app/services/matching_service.py](ziggo_backend/app/services/matching_service.py))

`find_nearest_driver(db, lat, lng, vehicle_type, max_distance_km, exclude_driver_id?)`
- Filters: `is_online=True`, `status=APPROVED`, `vehicle_type=<match>`, has current location.
- Pure Python loop using `haversine_km` — fine for demo, not for production scale.

### Fare engine (see [app/services/fare_service.py](ziggo_backend/app/services/fare_service.py))

`calculate_fare` (one vehicle type: estimates, booking create / accept / completion / destination change, public pages) and `calculate_fares_bulk` (the vehicle cards) share one set of pricing rules: (base + per-km + per-minute) × surge, minimum fare, category discount, boost, pickup fee, peak-hour and surge-zone surcharges, stop fees, flash weight tiers, return trips, promo codes, passenger deductible and commission. Rentals and courier have their own simpler rules.

Prices must not change by accident: `ziggo_backend/tests/test_fare_golden.py` holds both functions to 2,535 recorded results and checks that every vehicle card shows the same price, pickup fee and loyalty points as booking that vehicle. If a change is intended, re-record with `deploy/staging/run-backend-tests.sh record-fare-golden` and review the diff.

Rates come from `FareSetting` rows (admin-editable at `/admin/fare-settings`); falls back to `DEFAULTS` constant if a row is missing.

**Trip distance** is a straight line (`haversine_km`) unless `SystemSettings.road_distance_enabled` is on (switch on `/admin/fare-settings`, off by default). Then rides and flash parcels use Google's driving route via [road_distance_service.py](ziggo_backend/app/services/road_distance_service.py) (Directions API, backend `GOOGLE_MAPS_API_KEY`; that key needs the Directions API enabled). Stops are passed through in order; the result is never shorter than the straight line; the 25 km/h time estimate follows it; answers are cached 30 min per route (points rounded to ~11 m). Google failing falls back to the straight line, and quotes then say `distance_source: "straight"` (`"road"` otherwise; no key while the switch is off). At COMPLETE TRIP the route is measured to where the driver tapped it. The pickup fee (driver → pickup), courier, rental and food/Mart delivery fees still use straight lines.

### Flash (parcel) deliveries

A `Booking` row with `is_flash=True`. Same state machine, but requires `receiver_phone`, and `booking_ref` is prefixed `FL` instead of `ZG`. The admin panel splits them: `/admin/bookings` shows rides (where `is_flash=False`) and `/admin/flash` shows parcels.

### WebSocket events the backend emits

| Event                  | To       | Payload key fields                                            |
| ---------------------- | -------- | ------------------------------------------------------------- |
| `new_ride_request`     | driver   | full booking summary + customer name/phone + 30s expiry + `lady_driver_requested` |
| `booking_update`       | both     | `booking_id`, `status` (string)                               |
| `no_drivers_available` | customer | `booking_id`, `booking_ref` (+ `lady_driver`, `message` when no lady driver was found) |
| `passenger_location_update` | driver | `booking_id`, `lat`, `lng`, `at` — the customer's shared point while the driver is on the way |
| `passenger_location_stopped` | driver | `booking_id` — the customer switched sharing off |
| `customer_location_update` | admins on `/ws/admin/customers` | `booking_id`, `lat`, `lng`, `at`, `customer_id`, `status` (no name or phone) |
| `customer_location_stopped` | admins on `/ws/admin/customers` | `booking_id` |

Customer dispatch: when a booking is created, **every** available online, approved driver within the search radius gets `new_ride_request` at once (`find_all_nearby_drivers`). Rides go only to the booked vehicle type, flash and courier parcels to any type, and a driver about to finish a nearby trip can get a ride as a back-to-back request. The first to accept (`POST /bookings/{id}/accept`) wins, and the others get `ride_taken`.

### Lady drivers and "female passengers only" (see [app/services/gender_service.py](ziggo_backend/app/services/gender_service.py))

- `users.gender` is `female`, `male` or empty; `users.gender_source` says who set it. Drivers: read from the NIC (Sri Lankan NIC day-of-year + 500 = female) by `apply_nic_gender` wherever a NIC is saved. Customers: chosen once in the app (`PATCH /customer/profile` with exactly `female`/`male`; older apps' `Female`/`Male`/`Other` are ignored because they don't warn that it locks). An admin's choice (driver edit form, Riders page) is never overridden.
- **Lady drivers ride scooters**: both options exist only for `moto scooter` (`gender_service.LADY_DRIVER_SERVICE`). A female customer can book a Scooter ride with `lady_driver: true` (`bookings.lady_driver_requested`; any other vehicle is a 400, and estimates count `lady_drivers_nearby` for Scooter only). A woman on a Scooter can switch on `drivers.female_passengers_only`; read it through `gender_service.female_passengers_only(driver)`, which ignores the stored flag while she is on another vehicle. Both apply to rides only (rentals and return trips included, not flash/courier parcels) and never change the price. Women on other vehicles drive as normal and get every ride.
- **Every place that offers or hands a ride to a driver must apply the rule**: `matching_service.drivers_for_customer` / `gender_service.refusal_for_driver`. Today that is `create_booking`, `scheduled_dispatch.dispatch_booking`, the cancelled-ride notice to nearby drivers and accept (403). Scan-and-go is deliberately not filtered (the driver picks the passenger in person). A new dispatch path needs it too.
- No lady driver: the customer gets `no_drivers_available` with `lady_driver` + `message`, and `POST /bookings/{id}/any-driver` re-dispatches to everyone and restarts the search clock.
- Staging checks: `deploy/staging/gender_checks.py`, `deploy/staging/lady_driver_checks.py`.

### Customer live location and the Customer Map (see [app/services/passenger_location_service.py](ziggo_backend/app/services/passenger_location_service.py))

- On a ride (not a parcel) waiting for pickup, the customer can switch on "Share my live location with driver". It is per booking and off by default. The app sends points only while it is in the foreground (`BookingProvider` sharing section: every 5 s when moved 10 m, a 20 s heartbeat) to `POST /bookings/{id}/passenger-location`; `DELETE` stops it. 400 for parcels, 409 once the trip has started.
- Only the latest point is kept, on the booking (`bookings.passenger_sharing`, `passenger_lat`/`_lng`, `passenger_location_at`); there is no trail. It goes to the accepting driver (`passenger_location_update`) and to the admin Customer Map channel. `BookingResponse.passenger_location` carries it only while fresh (`LIVE_SECONDS` = 60).
- **The point is wiped** when the trip starts or ends (`update_booking_status`), on a search timeout (poll and `auto_cancel`), on `DELETE`, and by the `auto_cancel` sweep (`forget_stale`, every 30 s) for anything no longer waiting or not updated for 10 minutes. A new path that ends a booking should call `passenger_location_service.clear` too; the sweep only catches it later.
- The driver app shows it as a green "Customer | updated N s ago" marker beside the pickup (`DriverProvider.passengerLocation`), hidden after 60 s.
- **Admin Customer Map** (`/admin/customer-map`, [customer_map_service.py](ziggo_backend/app/services/customer_map_service.py)), superadmin and admin only (data entry is refused, and so is its WebSocket). Active trips are drawn at the fresh shared point, else the pickup, or the driver once under way. Every other customer who has booked sits at the pickup of the latest booking, coloured by a 0-100 score of how recently the last ride (not parcel) was completed: 100 today, 0 at `SCORE_DAYS` (60) days or never. The feed has no phones; `POST /admin/customer-map/customers/{id}/phone` returns one and writes `admin_phone_reveals` (who, which customer, booking, when), which super admins see on the page.
- Staging checks: `deploy/staging/customer_location_checks.py`, `deploy/staging/customer_map_checks.py`.

### Database

- Production and staging run **Postgres 16** in Docker; the containers get `DATABASE_URL` from docker-compose. SQLite (`sqlite+aiosqlite:///./ziggo.db`) is only the bare local-dev fallback.
- Schema changes are applied when the backend starts, by `app/services/schema_sync.py` (`create_all` for new tables, `PENDING_COLUMNS` for new columns), not by Alembic. It cannot add values to Postgres enum types (`user_role`, `booking_status`, …), so avoid new enum values.
- `DATABASE_URL` is the async URL (used by the app). `SYNC_DATABASE_URL` is what alembic uses.
- Models live in [app/models/](ziggo_backend/app/models/) — split per domain (`user.py`, `booking.py`, `food.py`, `market.py`, `misc.py`) and re-exported from `__init__.py`.
- All `created_at`/`updated_at` use `server_default=func.now()`.

### Seed data ([seed.py](ziggo_backend/seed.py))

Idempotent — safe to re-run. Creates:
- 3 admins (`0700000000`–`0700000002`); seed.py resets their passwords to `admin123` on every run, so never run it against production
- 1 demo customer (`0771234567`, wallet Rs. 2450)
- 6 demo drivers across Colombo, all APPROVED + online, mixed `vehicle_type`
- 5 fare-setting rows (bike/tuk/car/van/truck)
- 3 promo codes: `ZIGGO50`, `FLAT100`, `WELCOME`
- 4 restaurants (with menu categories + items)
- 2 market vendors (with products)

In `DEV_MODE` you can use any 6-digit OTP returned by `/auth/send-otp` (the response includes `dev_otp`). The README mentions `123456` as the demo OTP — that only works if you actually requested it (it's just whatever the last OTP was).

---

## 4. Flutter app — quick reference

### Run

```powershell
cd ziggo_app
flutter pub get
flutter run
```

### Host detection ([lib/core/network/host_resolver.dart](ziggo_app/lib/core/network/host_resolver.dart))

- Release builds use `https://ziggo.lk`.
- A build made with `--dart-define=API_HOST=...` uses only that host, never falling back to production, and shows a STAGING (test.ziggo.lk) or DEV banner.
- Debug builds without `API_HOST` also probe `http://localhost:8030` and `http://10.0.2.2:8030`.

### State management

Plain `provider` (no riverpod/bloc). All providers are registered in [lib/main.dart](ziggo_app/lib/main.dart) `MultiProvider`:

`AuthProvider`, `BookingProvider`, `WalletProvider`, `FoodProvider`, `MarketProvider`, `NotificationsProvider`, `PromosProvider`, `AddressesProvider`, `DriverProvider`.

Pattern: each provider holds a `Map<String, dynamic>?` of the current entity (e.g. `activeBooking`), exposes async methods that hit `ApiClient.instance.dio`, sets `_lastError` on `DioException`, and calls `notifyListeners()`.

### Realtime

- `core/network/ws_client.dart` opens one connection per provider that needs it. Token is supplied at `connectRealtime(token)`. `BookingProvider` and `DriverProvider` both have their own `WsClient` instance.
- Events are dispatched by string matching `event` against `'new_ride_request'`, `'booking_update'`, `'ride_taken'`, etc.

### Map

- Maps use Google Maps (`google_maps_flutter`), wrapped by [`ZiggoMap`](ziggo_app/lib/core/map/ziggo_map.dart). The key comes from the build: `MAPS_API_KEY` in CI, `GOOGLE_MAPS_API_KEY` in the app's `.env`.
- Place search uses Google Places via [maps_service.dart](ziggo_app/lib/core/map/maps_service.dart); [places.dart](ziggo_app/lib/core/map/places.dart) still holds Sri Lanka POIs used by some screens.
- Live location uses the OS GPS via `geolocator`.

### Theming — "soft-shadow" design language

Material 3, royal-blue brand seed in [app_colors.dart](ziggo_app/lib/app/app_colors.dart), Outfit font via `google_fonts`. The look is **minimal, rounded-everywhere, soft diffuse shadows** (Foodix-style):
- Radius/spacing/shadow tokens live in [app_styles.dart](ziggo_app/lib/app/app_styles.dart) `AppStyles` — `radiusXs..Xl` (12→36), `shadowSm/Md/Lg` are low-opacity large-blur. Use these tokens, don't hardcode.
- `AppStyles.card()` is **borderless + soft-shadowed by default**. `SoftCard` (in app_styles.dart) is the standard white rounded card widget — prefer it for new surfaces.
- `PrimaryButton`, `GradientServiceTile`, `GlassPill` (app_styles.dart) and `GlassCard` (core/widgets) are the shared building blocks.
- Theme defaults (radii, soft shadows, transparent appbar) are in [app_theme.dart](ziggo_app/lib/app/app_theme.dart) — themed `ElevatedButton`/`Card`/inputs inherit the look automatically. Match this in any new screen.

### Customer navigation shell

[customer_shell.dart](ziggo_app/lib/modules/customer/screens/customer_shell.dart) is a 5-tab `IndexedStack` with the floating [CurvedNavbar](ziggo_app/lib/core/widgets/curved_navbar.dart): `0 Mart · 1 Rides · 2 Home (raised center, default) · 3 Alerts · 4 Profile`. Tabs map to `MarketHomeScreen / FareEstimateScreen / HomeScreen / NotificationsScreen / ProfileScreen`. The shell uses `extendBody: true`, so screens need ~104px bottom padding to clear the navbar.

### Auth-aware routing

[lib/main.dart](ziggo_app/lib/main.dart) `_Root` is the gatekeeper:
1. Show `SplashScreen` for 3 s.
2. If `AuthProvider.status != authenticated` → `RoleSelectionScreen`.
3. Else, lazily connect booking WS + `loadActive()`, then route to `DriverHomeScreen` if `role == 'driver'` else `CustomerShell`.

---

## 5. Conventions to follow

- **Money** is always `DECIMAL(10,2)` on the backend, `Decimal` in Python, `double`/`float` in JSON. Always `Decimal(str(value))` when converting from float.
- **Coordinates** are `DECIMAL(10,7)` on the backend.
- **Datetimes** are timezone-aware UTC: `datetime.now(timezone.utc)`.
- **Booking refs** are `ZG` + 8-hex for rides, `FL` + 8-hex for flash deliveries (`secrets.token_hex(4).upper()`).
- **Currency** is LKR everywhere; UI shows `Rs.<int>`.
- **Phone numbers** are stored as the user typed them (`+94...` or `0...`). Seed data uses the `0...` form; the README documents both depending on context.
- **noqa: E712 / E711** is intentional throughout queries — `is_online == True` and `valid_to == None` are SQLAlchemy filter expressions, not Pythonic comparisons. Don't "fix" them to `is True` / `is None`.
- **Enums** are Python `str, enum.Enum` and stored via `SQLEnum(Cls, name="…")`. When comparing to a value from JSON, compare `enum.value` not the enum directly.
- **Errors from FastAPI** come back as `{"detail": "..."}`. Flutter consistently reads `e.response?.data?['detail']?.toString()`.
- **No comments** in code unless the *why* is non-obvious. The existing codebase has some explanatory comments — match that style for tricky bits, skip for trivial code.
- **No new top-level files / docs** unless the user asks for them.

---

## 6. Common task → starting points

| If the user asks…                                       | Start here                                                                 |
| ------------------------------------------------------- | -------------------------------------------------------------------------- |
| Add a backend endpoint                                  | New handler in the matching `app/api/v1/<domain>.py`; if it needs auth use `Depends(get_current_user)` or `require_role(...)`. Add a schema to `app/schemas/<domain>_schema.py`. |
| Add a new SQLAlchemy column / table                     | Edit the model under `app/models/`. New tables are created at startup; a new column on an existing table also needs an entry in `PENDING_COLUMNS` in `app/services/schema_sync.py` (nullable or with a default). |
| Wire a Flutter screen to a new endpoint                 | Pick (or create) a provider under `lib/modules/<area>/`. Use `ApiClient.instance.dio`. Match the error-handling pattern of existing providers. |
| Tweak fare math                                         | [services/fare_service.py](ziggo_backend/app/services/fare_service.py). Admin can also live-edit at `/admin/fare-settings`. Keep `tests/test_fare_golden.py` passing. |
| Change driver matching                                  | [services/matching_service.py](ziggo_backend/app/services/matching_service.py) — the in-memory scan is the only place. |
| Push a new realtime event                               | Add `await manager.send(user_id, "<event>", {...})` in the backend; handle in `BookingProvider` or `DriverProvider` `_onWsEvent`. |
| Modify the admin panel                                  | Add route in [ziggo_admin_panel/routes.py](ziggo_admin_panel/routes.py); template under `ziggo_admin_panel/templates/`. Pages all extend `base.html` and pass `active_page` for nav highlighting. |
| Real Twilio / Stripe                                    | The README lists the 5 files to touch. Don't refactor anything else when wiring real keys — the rest of the app is intentionally stub-friendly. |
| Driver document upload UI                               | `DriverDocument` model + endpoint exist; the Flutter screen is the missing piece (`modules/driver/screens/driver_registration_screen.dart` is the natural place). |

---

## 7. Things to watch out for

- **Forgetting `await db.commit()`**: every mutation handler ends with `await db.commit()` then often `await db.refresh(...)`. Skipping commit silently rolls back on session close.
- **WebSocket manager is in-process only**: a second uvicorn worker breaks broadcasts. The fix is documented in the README — swap `ws_manager.py` for Redis pub/sub. Don't add `--workers 2` to the dev command.
- **Decline forwarding hits the DB twice with nested executes** — see `decline_booking`'s `(await db.execute(select(Customer.user_id)...))` inside a `select(User)`. Works, but ugly. If you touch it, use two clean queries.
- **`Booking.is_flash` index split**: `/admin/bookings` filters `is_flash == False`, `/admin/flash` filters `is_flash == True`. Anything booking-listing-related on the admin side has to honor this split.
- **Schemas mismatch with model fields**: some response models (e.g. `FoodOrderResponse`) don't include `items` even though the model has them. Re-check the schema before assuming a field is round-tripped.
- **Places**: the backend stores lat/lng plus free-form address strings everywhere; the app's place search uses Google Places (`core/map/maps_service.dart`) plus the static POIs in `core/map/places.dart`.
- **Tests**: the backend tests in `ziggo_backend/tests/` (fare golden, districts, launch locations, genders, customer location, Customer Map) run with `deploy/staging/run-backend-tests.sh`; `deploy/staging/*_checks.py` exercise staging end to end. `ziggo_app/test/` is still the default Flutter scaffold, so app changes are only compiled by the staging APK build; try them on a phone.

---

## 8. Test logins (staging only)

| Who | Login |
| --- | --- |
| Admin (web, test.ziggo.lk/admin) | `0700000000` (superadmin), `0700000001`, `0700000002`; passwords are in `/root/ziggo-staging-admin-logins.txt` on the server |
| Test customer | `0771234567`; the staging API returns the OTP and the app fills it in |
| Test drivers | `0771000001` … `0771000006` (tuk, bike, car, mini, van, moto scooter) |
| Restaurant / vendor owner | `0771100001` / `0771200001` |

These exist only on staging. Never use test logins or default passwords on the live site.

# CLAUDE.md — Ziggo Super App

Read this file first whenever you receive a task in this repo. It is the single source of truth for layout, conventions, and where things live so you can skip discovery and jump straight to the right file.

---

## 1. What this project is

Ziggo is a PickMe-style **ride + food + market + flash-parcel** super app for Sri Lanka. It runs entirely locally — no paid third-party APIs are required.

Three deliverables live in this repo:

1. **`ziggo_app/`** — single Flutter binary that contains both the **customer** and **driver** UIs (chosen at the role-selection screen after login).
2. **`ziggo_backend/`** — FastAPI + SQLAlchemy (async) backend that also serves a server-rendered **admin web panel** at `/admin/*`.
3. **`README.md`** — onboarding doc for a fresh dev (setup steps, demo credentials, end-to-end test flow).

Real services are stubbed with local replacements:

| Real service       | Local replacement                                            |
| ------------------ | ------------------------------------------------------------ |
| Twilio SMS         | OTP printed to console + returned in API when `DEV_MODE=true` |
| Google Maps SDK    | `flutter_map` + OpenStreetMap tiles (no API key)             |
| Google Places      | Hard-coded SL POI list in [ziggo_app/lib/core/map/places.dart](ziggo_app/lib/core/map/places.dart) |
| Stripe / PayHere   | Wallet top-up is a direct DB credit                          |
| Firebase FCM       | WebSocket events from FastAPI (`ws_manager.py`)              |
| Cloud Storage      | Local file paths (driver document upload UI not yet built)   |

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
        ├── api/v1/                            JSON routers: auth, customer, driver,
        │                                      bookings, food, market, admin, misc, ws
        └── admin_panel/                       Jinja2 server-rendered admin (cookie session)
            ├── routes.py
            ├── templates/                     login, dashboard, drivers, customers,
            │                                  bookings, flash, restaurants, market,
            │                                  promotions, complaints, settings, …
            └── static/{css,js}/
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
| `/ws`                   | [app/api/v1/ws.py](ziggo_backend/app/api/v1/ws.py)             | JWT-authed WebSocket (`?token=<jwt>`)              |
| `/admin/*`              | [app/admin_panel/routes.py](ziggo_backend/app/admin_panel/routes.py) | Jinja2 admin UI (cookie session via itsdangerous)  |

### Auth model

- Phone-OTP only (no passwords for customers/drivers). Admin login uses `phone + 'admin123'` against the seeded admin user.
- `services/auth_service.py::get_current_user` is the OAuth2 bearer dependency. Use `require_role("customer"|"driver"|"admin")` to gate routes.
- Admin panel uses a separate signed cookie (`ziggo_admin`) via `itsdangerous.URLSafeSerializer`, NOT the JWT — see `admin_panel/routes.py::current_admin`.
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

`final = max(base + per_km*distance + per_min*duration, min_fare) * surge - promo_discount`
Then `platform_fee = final * pct`, `driver_earnings = final - platform_fee`.

Rates come from `FareSetting` rows (admin-editable at `/admin/fare-settings`); falls back to `DEFAULTS` constant if a row is missing.

### Flash (parcel) deliveries

A `Booking` row with `is_flash=True`. Same state machine, but requires `receiver_phone`, and `booking_ref` is prefixed `FL` instead of `ZG`. The admin panel splits them: `/admin/bookings` shows rides (where `is_flash=False`) and `/admin/flash` shows parcels.

### WebSocket events the backend emits

| Event                  | To       | Payload key fields                                            |
| ---------------------- | -------- | ------------------------------------------------------------- |
| `new_ride_request`     | driver   | full booking summary + customer name/phone + 30s expiry       |
| `booking_update`       | both     | `booking_id`, `status` (string)                               |
| `no_drivers_available` | customer | `booking_id`, `booking_ref`                                   |

Customer dispatch: when a booking is created, the **nearest driver only** is pinged via `new_ride_request` — they tap Accept (`POST /bookings/{id}/accept`) or Decline (`POST /bookings/{id}/decline`). On decline the backend forwards to the next nearest driver, excluding the one who just declined.

### Database

- Config is in `.env`. The default is **SQLite** (`sqlite+aiosqlite:///./ziggo.db`), not PostgreSQL — the README's PostgreSQL section is the optional production path. Don't assume Postgres is running.
- `DATABASE_URL` is the async URL (used by the app). `SYNC_DATABASE_URL` is what alembic uses.
- Models live in [app/models/](ziggo_backend/app/models/) — split per domain (`user.py`, `booking.py`, `food.py`, `market.py`, `misc.py`) and re-exported from `__init__.py`.
- All `created_at`/`updated_at` use `server_default=func.now()`.

### Seed data ([seed.py](ziggo_backend/seed.py))

Idempotent — safe to re-run. Creates:
- 1 admin (`0700000000` / password `admin123`)
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

### Host detection ([lib/core/network/api_client.dart](ziggo_app/lib/core/network/api_client.dart))

- Web → `http://localhost:8000`
- Android/iOS (emulator or device) → hard-coded `_lanIp = 'http://192.168.1.114:8000'`
- Desktop → `http://localhost:8000`

If the dev's LAN IP changes, edit `_lanIp` in `api_client.dart`. (The README mentions `10.0.2.2` for Android emulator but the current code uses the LAN IP for all mobile platforms.)

### State management

Plain `provider` (no riverpod/bloc). All providers are registered in [lib/main.dart](ziggo_app/lib/main.dart) `MultiProvider`:

`AuthProvider`, `BookingProvider`, `WalletProvider`, `FoodProvider`, `MarketProvider`, `NotificationsProvider`, `PromosProvider`, `AddressesProvider`, `DriverProvider`.

Pattern: each provider holds a `Map<String, dynamic>?` of the current entity (e.g. `activeBooking`), exposes async methods that hit `ApiClient.instance.dio`, sets `_lastError` on `DioException`, and calls `notifyListeners()`.

### Realtime

- `core/network/ws_client.dart` opens one connection per provider that needs it. Token is supplied at `connectRealtime(token)`. `BookingProvider` and `DriverProvider` both have their own `WsClient` instance.
- Events are dispatched by string matching `event` against `'new_ride_request'`, `'booking_update'`, `'ride_taken'`, etc.

### Map

- All maps use [`ZiggoMap`](ziggo_app/lib/core/map/ziggo_map.dart) backed by OSM tiles. No Google Maps key needed.
- "Place autocomplete" is actually a static list ([places.dart](ziggo_app/lib/core/map/places.dart)).
- Live location uses the OS GPS via `geolocator` (no Google Places).

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
| Add a new SQLAlchemy column / table                     | Edit the model under `app/models/`, then `alembic revision --autogenerate -m "..." && alembic upgrade head`. |
| Wire a Flutter screen to a new endpoint                 | Pick (or create) a provider under `lib/modules/<area>/`. Use `ApiClient.instance.dio`. Match the error-handling pattern of existing providers. |
| Tweak fare math                                         | [services/fare_service.py](ziggo_backend/app/services/fare_service.py). Admin can also live-edit at `/admin/fare-settings`. |
| Change driver matching                                  | [services/matching_service.py](ziggo_backend/app/services/matching_service.py) — the in-memory scan is the only place. |
| Push a new realtime event                               | Add `await manager.send(user_id, "<event>", {...})` in the backend; handle in `BookingProvider` or `DriverProvider` `_onWsEvent`. |
| Modify the admin panel                                  | Add route in [admin_panel/routes.py](ziggo_backend/app/admin_panel/routes.py); template under `admin_panel/templates/`. Pages all extend `base.html` and pass `active_page` for nav highlighting. |
| Real Twilio / Stripe                                    | The README lists the 5 files to touch. Don't refactor anything else when wiring real keys — the rest of the app is intentionally stub-friendly. |
| Driver document upload UI                               | `DriverDocument` model + endpoint exist; the Flutter screen is the missing piece (`modules/driver/screens/driver_registration_screen.dart` is the natural place). |

---

## 7. Things to watch out for

- **Forgetting `await db.commit()`**: every mutation handler ends with `await db.commit()` then often `await db.refresh(...)`. Skipping commit silently rolls back on session close.
- **WebSocket manager is in-process only**: a second uvicorn worker breaks broadcasts. The fix is documented in the README — swap `ws_manager.py` for Redis pub/sub. Don't add `--workers 2` to the dev command.
- **Decline forwarding hits the DB twice with nested executes** — see `decline_booking`'s `(await db.execute(select(Customer.user_id)...))` inside a `select(User)`. Works, but ugly. If you touch it, use two clean queries.
- **`Booking.is_flash` index split**: `/admin/bookings` filters `is_flash == False`, `/admin/flash` filters `is_flash == True`. Anything booking-listing-related on the admin side has to honor this split.
- **Schemas mismatch with model fields**: some response models (e.g. `FoodOrderResponse`) don't include `items` even though the model has them. Re-check the schema before assuming a field is round-tripped.
- **Two different "places" sources**: backend uses lat/lng + free-form address strings everywhere; the Flutter UI picks from the hard-coded list in `core/map/places.dart`. There is no Google Places call. If you add a destination picker, use that list (or build a real one) — don't introduce a Google Places dependency.
- **No tests**: the `ziggo_app/test/` dir is the default Flutter scaffold; the backend has no test suite at all. Don't claim you've "verified" anything by running tests — there aren't any. Verify by running the server / app and exercising the endpoint.

---

## 8. Demo credentials (after `seed.py`)

| Who              | Login                       | Password / OTP                                   |
| ---------------- | --------------------------- | ------------------------------------------------ |
| Admin (web)      | `0700000000` (or `+94700000000`) | `admin123`                                  |
| Demo customer    | `0771234567`                | any OTP the API returns (`dev_otp` in response)  |
| Demo drivers     | `0771000001` … `0771000006` | any OTP the API returns                          |
| Promo codes      | `ZIGGO50`, `FLAT100`, `WELCOME` | —                                            |

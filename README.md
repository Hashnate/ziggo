# Ziggo — PickMe-style Super App

Full-stack ride/food/delivery platform: Flutter mobile app + FastAPI backend + admin web panel.
**No third-party APIs required** — runs entirely on your machine.

```
ziggo/
├── ziggo_app/         Flutter app (customer + driver in one binary)
├── ziggo_backend/     FastAPI + PostgreSQL + admin panel
└── README.md          (this file)
```

---

## One-time setup

### 1. PostgreSQL

Install PostgreSQL 16 or 17 from https://www.postgresql.org/download/windows/.
Set the superuser password to **`postgres`** during install. Default port `5432`.

Create the database (PowerShell, after install):
```powershell
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -c "CREATE DATABASE ziggo;"
```

If the version path differs, just open pgAdmin and create a database named `ziggo`.

### 2. Backend (Python)

```powershell
cd ziggo_backend
pip install -r requirements.txt

# Create all tables
alembic revision --autogenerate -m "init"
alembic upgrade head

# Seed demo data (admin, drivers, fare settings, promo codes, restaurants)
python seed.py

# Run the server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Backend will be on http://localhost:8000.

Useful URLs:
- Admin panel: http://localhost:8000/admin/login
- API docs:    http://localhost:8000/docs

### 3. Flutter app

```powershell
cd ziggo_app
flutter pub get
flutter run
```

The app auto-detects the backend host:
- Android emulator → `10.0.2.2:8000`
- iOS sim / desktop / web → `localhost:8000`

If running on a **physical device**, edit [`ziggo_app/lib/core/network/api_client.dart`](ziggo_app/lib/core/network/api_client.dart) to point `baseHost` at your machine's LAN IP (e.g. `http://192.168.1.5:8000`).

---

## Demo credentials (after `seed.py`)

| Who | Login | Password |
|---|---|---|
| **Admin** (web) | `+94700000000` | `admin123` |
| **Customer** | `+94771234567` | OTP shown in backend console (or `123456` in DEV_MODE) |
| **Drivers** | `+94771000001` … `+94771000006` | OTP `123456` |
| **Promo codes** | `ZIGGO50` / `FLAT100` / `WELCOME` | — |

`DEV_MODE=true` in `.env` makes the OTP endpoint return the code in the response, so the mobile app auto-fills it on the OTP screen — you never need to read the console.

---

## Architecture

### Backend ([`ziggo_backend/app/`](ziggo_backend/app/))

| Path | Purpose |
|---|---|
| `config.py` | Pydantic settings (loads `.env`) |
| `database.py` | Async SQLAlchemy engine + `get_db` dependency |
| `models/` | SQLAlchemy models (User, Driver, Customer, Booking, Restaurant, MarketVendor, …) |
| `schemas/` | Pydantic request/response schemas |
| `services/auth_service.py` | OTP generation/verification, JWT, `get_current_user` |
| `services/fare_service.py` | Haversine distance + fare engine (base + per-km + per-min + surge + promo) |
| `services/matching_service.py` | Nearest-online-driver algorithm |
| `services/ws_manager.py` | In-memory WebSocket pub/sub keyed by user ID |
| `api/v1/auth.py` | Send/verify OTP + `/me` |
| `api/v1/bookings.py` | Full ride state machine: estimate → create → status updates → rate |
| `api/v1/customer.py` | Profile, addresses, wallet, top-ups, transactions |
| `api/v1/driver.py` | Location updates, online toggle, profile |
| `api/v1/food.py`, `market.py` | Restaurant/vendor catalogs and orders |
| `api/v1/admin.py` | Admin stats + driver approve/suspend (JSON) |
| `api/v1/ws.py` | WebSocket endpoint for live ride updates |
| `admin_panel/` | Jinja2-rendered admin web pages (real DB queries) |

### Booking state machine

```
SEARCHING → ACCEPTED → ARRIVED → STARTED → COMPLETED
     │           │           │           │
     └───────────┴───────────┴───────────┴── CANCELLED (any time before COMPLETED)
```

Each transition pushes a WebSocket event to the customer and driver, debits/credits the wallet on completion, and updates driver earnings.

### Flutter app ([`ziggo_app/lib/`](ziggo_app/lib/))

| Path | Purpose |
|---|---|
| `main.dart` | Root: providers + auth-aware routing |
| `core/network/api_client.dart` | Dio + token-injecting interceptor |
| `core/network/ws_client.dart` | WebSocket reconnect-safe client |
| `core/storage/token_storage.dart` | `flutter_secure_storage` wrapper |
| `core/map/ziggo_map.dart` | Reusable map widget (OpenStreetMap tiles, **no API key**) |
| `core/map/places.dart` | Hard-coded Sri Lanka POIs for the autocomplete picker |
| `modules/auth/` | `AuthProvider` + phone/OTP screens |
| `modules/customer/booking_provider.dart` | Booking lifecycle + WS subscription |
| `modules/customer/wallet_provider.dart` | Wallet balance + transactions |
| `modules/customer/screens/` | Home, fare estimate, tracking, rating, history, wallet, profile, … |
| `modules/driver/driver_provider.dart` | Online toggle, location stream, ride accept/decline |
| `modules/driver/screens/driver_home_screen.dart` | Driver UI |

### Maps

The app uses **OpenStreetMap** tiles via `flutter_map` — free, no API key, looks like Google Maps. The admin live-ride map uses Leaflet on the same tiles.

### Without third-party APIs (current state)

| Real service | Local replacement |
|---|---|
| Twilio SMS | OTP printed to backend console + returned in API in DEV_MODE |
| Google Maps SDK | flutter_map + OpenStreetMap |
| Google Places | Hard-coded Sri Lanka POI list (`places.dart`) |
| Stripe / PayHere | Wallet top-up is a direct DB credit |
| Firebase Cloud Messaging | WebSocket events from FastAPI |
| Google Cloud Storage | Local file paths (not yet wired) |

When you buy real API keys later, replace each in the corresponding service file — the rest of the app is unchanged.

---

## Testing the end-to-end ride flow

1. Start backend: `uvicorn app.main:app --reload`
2. Start Flutter app (emulator)
3. **Pick "RIDE & ORDER"** on the role screen
4. Phone: `+94771234567` → tap **SEND OTP**
5. OTP field autofills with `123456` → **VERIFY**
6. Home screen shows a live OpenStreetMap centered on Colombo
7. Tap **BOOK A RIDE** → pick pickup + destination from the place list
8. Fare cards populate with real estimates (bike / tuk / car / van / truck)
9. Optionally enter promo `ZIGGO50`, choose payment method
10. Tap **BOOK** → backend assigns the nearest seeded driver, status flips to `ACCEPTED`
11. Ride tracking screen shows driver + pickup + drop on the map
12. To advance the ride, hit `PATCH /api/v1/bookings/{id}/status` from `/docs` as the driver:
    - `accepted` → `arrived` → `started` → `completed`
    - Or log in to the app as a driver (`+94771000003`) and use the driver UI
13. Customer sees status updates via WebSocket and is auto-routed to the rating screen on `completed`
14. Admin panel at `/admin/dashboard` shows live counts, the booking in the live map, and driver list

---

## Known limitations (intentional, not bugs)

- **No automatic location detection in the customer app** — pickup defaults to a curated POI. Add `geolocator` permission flow on the home screen when you want it.
- **No SMS provider** — OTP is logged to the console / returned in dev. Wire Twilio in `services/auth_service.py::create_and_send_otp` when ready.
- **No card payments** — wallet top-up is a direct credit. Add Stripe/PayHere in `api/v1/customer.py::wallet_topup` when ready.
- **In-process WebSocket manager** — fine for one Uvicorn worker. For horizontal scale, swap `services/ws_manager.py` for Redis pub/sub.
- **No driver document upload UI** — backend model exists (`DriverDocument`), but the upload screen is not built.
- **Food/Market verticals** — backend routers exist and the schema is complete; the Flutter food/market screens still use the older UI and need to be rewired to the providers.

---

## Tearing it down / starting over

```powershell
# Wipe and recreate the database
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -c "DROP DATABASE ziggo;"
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres -c "CREATE DATABASE ziggo;"
cd ziggo_backend
alembic upgrade head
python seed.py
```

---

## What gets harder when you add real APIs

When you eventually purchase keys, the only files that change:

1. **`.env`** — fill in the empty `TWILIO_*`, `GOOGLE_MAPS_API_KEY`, `STRIPE_*` values.
2. **`app/services/auth_service.py`** — `create_and_send_otp` calls Twilio.
3. **`app/api/v1/customer.py`** — `wallet_topup` creates a real Stripe/PayHere charge.
4. **`ziggo_app/lib/core/map/ziggo_map.dart`** — swap the `urlTemplate` for Google Maps if you prefer (or keep OSM; PickMe-grade UX is achievable on OSM).
5. **`ziggo_app/lib/core/map/places.dart`** — replace with Google Places Autocomplete.

Everything else (booking flow, driver matching, fare engine, wallet ledger, admin panel) stays as-is.
#   z i g g o  
 #   z i g g o  
 
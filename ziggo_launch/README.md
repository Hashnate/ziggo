# Ziggo GRAND LAUNCH — VIP Celebrity Event Page 🚀

An **award-tier, VIP red-carpet, cinematic grand-reveal single-page microsite** built for the nationwide Ziggo launch ceremony.

**Celebrity Event Highlights:**
- 🎬 **Cinematic Preloader**: Real 0→100% loading progress counter + smooth 1.2s curtain/mask reveal.
- 📜 **Lenis Inertia Smooth Scroll**: Buttery-smooth physics tuned at `lerp: 0.08` for an ultra-luxe browsing feel.
- 🎞️ **35mm Film Grain Overlay**: Procedural non-blocking canvas noise for authentic cinema texture.
- 🎯 **Custom Magnetic Cursor**: Fluid trailing ring with interactive contextual labels (`RSVP`, `IGNITE`, `VIP`).
- ✨ **SplitType Kinetic Headline**: Character/word staggered mask reveals powered by GSAP.
- ⏱️ **Titanium Stage Chronometer**: High-contrast flip-style countdown cards with Sri Lanka Standard Time (GMT+5:30).
- 🌟 **VIP Celebrity Lineup**: GSAP ScrollTrigger glass cards teasing film, music, sports, and tech icons.
- 📱 **3D Colorful Super App Showcase**: High-impact 3D visual ecosystem featuring Ziggo Rides, Food, Mart, Trucks, Rental & Events.
- 🔔 **Luxe RSVP Glass Form**: Full Name, Email, Sri Lanka +94 Phone validation + Web Push subscription saving to `launch_subscribers`.
- 🚀 **Grand Reveal Stadium Moment**: Custom canvas fireworks + multi-wave gold confetti + celebration fanfare audio.
- 🔒 **Protected Launch Control**: Secret `/launch-control` route with idempotent Web Push & FCM fan-out.


---

## Quick Start

```bash
cd /var/www/ziggo/ziggo_launch
cp .env.local.example .env.local
# Fill in DATABASE_URL, LAUNCH_ADMIN_TOKEN, VAPID keys (see below)
npm install
npm run dev         # → http://localhost:3000
```

---

## Environment Variables

Copy `.env.local.example` → `.env.local` and fill in:

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | ✅ | Postgres connection string |
| `LAUNCH_ADMIN_TOKEN` | ✅ | Secret token for `/launch-control` and admin APIs |
| `NEXT_PUBLIC_VAPID_PUBLIC_KEY` | ✅ | VAPID public key (browser push) |
| `VAPID_PRIVATE_KEY` | ✅ | VAPID private key (server side only) |
| `VAPID_SUBJECT` | ✅ | `mailto:admin@ziggo.app` |
| `NEXT_PUBLIC_LAUNCH_DATETIME` | ✅ | Fallback launch datetime (ISO 8601, e.g. `2026-09-06T16:30:00+05:30`) |
| `NEXT_PUBLIC_APP_LINK` | ✅ | Ziggo app/store URL for push notification click action |
| `FCM_SERVER_KEY` | ❌ | Firebase Cloud Messaging server key (optional) |

> **Note:** `DATABASE_URL` is optional for Phase 1 (countdown falls back to env var). Required for subscriber registration and launch fan-out.

---

## Generate VAPID Keys

```bash
npx web-push generate-vapid-keys
```

Copy the output into `.env.local`:
```env
NEXT_PUBLIC_VAPID_PUBLIC_KEY=BExamplePublicKeyHere...
VAPID_PRIVATE_KEY=ExamplePrivateKeyHere...
VAPID_SUBJECT=mailto:admin@ziggo.app
```

> ⚠️ The public key must be in `.env.local` as `NEXT_PUBLIC_VAPID_PUBLIC_KEY` (with the `NEXT_PUBLIC_` prefix) so it's available in the browser.

---

## Database Setup

The app auto-creates tables on first API call. To run migrations manually:

```sql
-- app_config table (launch datetime storage)
CREATE TABLE IF NOT EXISTS app_config (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO app_config (key, value)
VALUES ('launch_datetime', '2026-09-06T16:30:00+05:30')
ON CONFLICT (key) DO NOTHING;

-- Subscriber waitlist
CREATE TABLE IF NOT EXISTS launch_subscribers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name         TEXT NOT NULL,
  email             TEXT UNIQUE NOT NULL,
  phone             TEXT NOT NULL,
  push_subscription JSONB,
  push_enabled      BOOLEAN NOT NULL DEFAULT false,
  notified          BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## API Routes

| Route | Auth | Method | Description |
|---|---|---|---|
| `/api/launch-time` | Public | GET | Returns `{ launchAt: "ISO string" }` from DB |
| `/api/subscribe` | Public | POST | Saves subscriber + push subscription |
| `/api/admin/set-launch-time` | Admin token | POST | Updates launch datetime in DB |
| `/api/admin/subscribers` | Admin token | GET | Returns total subscriber count |
| `/api/launch` | Admin token | POST | Fan-out push notifications to all subscribers |

### Update launch time (curl example):
```bash
curl -X POST http://localhost:3000/api/admin/set-launch-time \
  -H "Content-Type: application/json" \
  -d '{"adminToken": "YOUR_TOKEN", "launchAt": "2026-09-06T16:30:00+05:30"}'
```

---

## Launch Day Guide

### 1. Pre-launch checklist
- [ ] `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` set in production env
- [ ] `DATABASE_URL` points to production Postgres
- [ ] `LAUNCH_ADMIN_TOKEN` is a strong random secret (`openssl rand -hex 32`)
- [ ] `NEXT_PUBLIC_APP_LINK` set to real Play Store / App Store URL
- [ ] Page is deployed and accessible

### 2. On launch day
1. Open `https://your-domain.com/launch-control`
2. Enter your admin token
3. Verify subscriber count and countdown date
4. Optionally adjust launch datetime if needed (Update Launch Time)
5. When ready: click **🚀 FIRE THE LAUNCH**
6. Confirm the dialog ("Yes, fire it!")
7. Watch the confetti 🎉 and check the summary (sent / failed / skipped)

### 3. Idempotency
The `/api/launch` endpoint is safe to call multiple times:
- Subscribers with `notified = true` are counted as `skipped` and NOT re-notified
- Expired/invalid push subscriptions (410/404) are automatically cleaned up

---

## Deploy

```bash
npm run build   # Verify zero errors
npm run start   # Production server

# Or with PM2:
pm2 start npm --name ziggo-launch -- run start
```

For Docker, add a stage to the existing `docker-compose.yml`:
```yaml
  ziggo_launch:
    build: ./ziggo_launch
    ports: ["3000:3000"]
    env_file: ./ziggo_launch/.env.local
    restart: unless-stopped
```

---

## Project Structure

```
ziggo_launch/
├── app/
│   ├── layout.tsx                    Root layout (fonts, SEO, Open Graph)
│   ├── page.tsx                      Landing page
│   ├── globals.css                   Tailwind v4 + custom animations
│   ├── launch-control/               Admin panel
│   │   ├── layout.tsx
│   │   └── page.tsx
│   └── api/
│       ├── launch-time/route.ts      GET — public countdown time
│       ├── subscribe/route.ts        POST — register subscriber
│       ├── launch/route.ts           POST — fire push notifications
│       └── admin/
│           ├── set-launch-time/      POST — update datetime
│           └── subscribers/          GET — subscriber count
├── components/
│   ├── Hero.tsx                      Hero section
│   ├── Countdown.tsx                 Live flip-card countdown
│   ├── RegistrationForm.tsx          Waitlist form + push permission
│   ├── FeatureTeaser.tsx             6 service cards
│   ├── Footer.tsx                    Footer
│   └── LaunchReveal.tsx              Confetti + celebration overlay
├── lib/
│   └── db.ts                         Shared Postgres pool + migrations
├── public/
│   ├── service-worker.js             Web Push handler
│   ├── logo-light.png
│   └── logo-dark.png
└── .env.local.example
```

---

## Tech Stack

- **Framework:** Next.js 16 (App Router) + React 19
- **Styling:** Tailwind CSS v4
- **Database:** PostgreSQL via `pg` (Node.js)
- **Push notifications:** `web-push` (VAPID) + Service Worker API
- **Confetti:** `canvas-confetti`
- **Fonts:** Outfit (headings) + DM Sans (body) via Google Fonts

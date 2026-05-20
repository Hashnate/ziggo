# Deploying Ziggo on a shared host

Target: a Linux server that already runs other apps behind a host **nginx** (with TLS via certbot), plus an existing MariaDB on 3306, Redis on 6379, gunicorn on 8000. We bring Ziggo up as two new docker containers without touching any of that.

---

## 1. What you get

| Container       | Image              | Reachable on                | Notes                              |
| --------------- | ------------------ | --------------------------- | ---------------------------------- |
| `ziggo_postgres`| `postgres:16-alpine` | internal docker network only | data persists in volume `ziggo_pgdata` |
| `ziggo_backend` | built from `./ziggo_backend/Dockerfile` | `127.0.0.1:8030` (host loopback) | uploads persist in volume `ziggo_uploads` |

Host nginx will reverse-proxy `ziggo.your-domain.com` → `127.0.0.1:8030`.

### Port choice

A `ss -tulnp` on the target server shows these ports already in use: **22, 80, 443, 3000, 3306, 6379, 8000, 8001, 8010, 8020, 9000, 9090**. `ZIGGO_PORT` defaults to **8030** which is clear. If anything ever conflicts, change it in `.env`.

---

## 2. One-time install (per server)

Install Docker if it isn't there yet:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER         # so you don't need sudo for docker
newgrp docker                          # apply group without logging out
```

---

## 3. Bring Ziggo up

```bash
cd /var/www/ziggo

# Pull the latest code
git pull

# Create the prod env file (only the first time)
cp ziggo_backend/.env.production.example .env
nano .env
#   POSTGRES_PASSWORD=<openssl rand -base64 24>
#   SECRET_KEY=<openssl rand -hex 48>
#   ZIGGO_PORT=8030    (change if 8030 is taken)
#   DEV_MODE=false     (critical!)

# Build images and start containers in the background
docker compose up -d --build

# Watch the logs until you see "Application startup complete"
docker compose logs -f ziggo_backend
```

On first boot the backend's `schema_sync` creates all tables and seeds the demo flash weight tiers + sample events. No alembic command needed.

**Smoke test:**

```bash
curl http://127.0.0.1:8030/health
# {"status":"ok"}
```

---

## 4. (Optional) Seed demo data

`seed.py` adds the demo admin, demo customer, 6 demo drivers, fare settings, promo codes, restaurants and market vendors. Re-runnable safely.

```bash
docker compose exec ziggo_backend python seed.py
```

Admin login afterwards: phone `0700000000`, password `admin123` at `/admin/login`. **Change the admin password** before the site goes public.

---

## 5. Wire host nginx

```bash
sudo cp deploy/nginx-ziggo.conf.example /etc/nginx/sites-available/ziggo
sudo nano /etc/nginx/sites-available/ziggo
#   server_name ziggo.your-domain.com;
sudo ln -s /etc/nginx/sites-available/ziggo /etc/nginx/sites-enabled/ziggo
sudo nginx -t && sudo systemctl reload nginx
```

DNS-wise, point `ziggo.your-domain.com` at the server's public IP. Then add HTTPS with certbot:

```bash
sudo certbot --nginx -d ziggo.your-domain.com
```

certbot edits the same nginx file to add the TLS server block and auto-renews via systemd timer.

---

## 6. Point the Flutter app at the new server

In [`ziggo_app/lib/core/network/api_client.dart`](ziggo_app/lib/core/network/api_client.dart), replace the dev LAN IP with the production base URL. Look for `_lanIp`:

```dart
// before
static const String _lanIp = 'http://192.168.1.114:8000';
// after
static const String _lanIp = 'https://ziggo.your-domain.com';
```

Same for WebSocket if it's a separate constant. Rebuild the APK / iOS app from the same machine and distribute.

---

## 7. Day-to-day operations

```bash
# Logs (follow)
docker compose logs -f ziggo_backend
docker compose logs -f ziggo_postgres

# Shell into the backend container
docker compose exec ziggo_backend bash

# psql into the DB
docker compose exec ziggo_postgres psql -U ziggo -d ziggo

# Restart after pulling new code
git pull
docker compose up -d --build

# Stop everything (data persists)
docker compose down

# Stop AND nuke volumes (loses all DB data + uploads — DESTRUCTIVE)
docker compose down -v
```

---

## 8. Backups

Two things to back up:

1. **Postgres data** — dump weekly via cron:
   ```bash
   docker compose exec -T ziggo_postgres pg_dump -U ziggo ziggo \
     | gzip > /var/backups/ziggo-$(date +%F).sql.gz
   ```
2. **Uploads volume** — periodically tar it:
   ```bash
   docker run --rm -v ziggo_uploads:/data -v /var/backups:/backup alpine \
     tar czf /backup/ziggo-uploads-$(date +%F).tar.gz -C /data .
   ```

Restore Postgres from a dump:

```bash
gunzip -c /var/backups/ziggo-2026-05-20.sql.gz | \
  docker compose exec -T ziggo_postgres psql -U ziggo -d ziggo
```

---

## 9. Troubleshooting

**`ziggo_backend` container restarts in a loop**
- `docker compose logs ziggo_backend` — almost always `DATABASE_URL` typo or `POSTGRES_PASSWORD` mismatch between the two service environments. They're built from the same `.env` so just re-check that file.

**Backend boots but `/api/v1/auth/send-otp` returns 500**
- DB schema didn't sync. Wipe the volume and bring it up clean (only safe if you have no real data yet): `docker compose down -v && docker compose up -d --build`

**WebSocket connects then disconnects after ~60s**
- nginx default `proxy_read_timeout` is short. The supplied config sets it to 3600s for the `/ws` location — make sure you used that.

**Driver app shows "No drivers available" but a driver IS online**
- The driver's location update hits the backend, but on a fresh server the GPS might be denied. Tap the location toggle in the driver app to re-trigger the permission prompt.

**`docker compose` says "the input device is not a TTY"**
- You're running it through ssh without `-t`. Add `-T` flag to exec calls that don't need a TTY: `docker compose exec -T ziggo_backend python seed.py`

---

## 10. Files this deploy uses

| File                                                | Purpose                                            |
| --------------------------------------------------- | -------------------------------------------------- |
| `docker-compose.yml`                                | Defines both containers, network, volumes          |
| `ziggo_backend/Dockerfile`                          | Builds the FastAPI image                           |
| `ziggo_backend/.dockerignore`                       | Keeps `.git`, venv, sqlite db out of the image     |
| `ziggo_backend/.env.production.example`             | Template for the runtime `.env` (copy + edit)      |
| `deploy/nginx-ziggo.conf.example`                   | Host nginx server block (copy to sites-available)  |
| `.env`                                              | (you create this — not in git)                     |

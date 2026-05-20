# Ziggo backend — FastAPI + uvicorn
# Runs alongside other apps on a shared host; the container exposes 8000 and
# docker-compose maps it to a free host port (8030 by default).

FROM python:3.11-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# OS deps:
#   - libpq5  : runtime for psycopg2/psycopg
#   - build-essential + libpq-dev : compile asyncpg / psycopg if wheel unavailable
#   - curl    : healthcheck
# Build deps are dropped after pip install to keep the final image small.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential libpq-dev libpq5 curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt \
 && apt-get purge -y build-essential libpq-dev \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

COPY . .

# Ensure upload dir exists (mounted as a volume in compose so it survives rebuilds)
RUN mkdir -p /app/app/admin_panel/static/uploads/drivers

EXPOSE 8000

# Healthcheck hits /health which the app exposes; compose uses this to gate
# the host nginx reverse-proxy from sending traffic too early.
HEALTHCHECK --interval=20s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/health || exit 1

# --proxy-headers so X-Forwarded-* from nginx is honoured.
# --forwarded-allow-ips="*" trusts the docker bridge net.
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--proxy-headers", \
     "--forwarded-allow-ips=*"]

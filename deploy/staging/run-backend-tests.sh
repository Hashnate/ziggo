#!/usr/bin/env bash
# Run the backend tests in a throwaway container from the staging image, against
# a temporary database on the staging Postgres. Production and the staging app's
# own database are never touched, and the temporary database is dropped after.
#
#   deploy/staging/run-backend-tests.sh                      # all tests
#   deploy/staging/run-backend-tests.sh -k fare -q           # extra pytest args
#   deploy/staging/run-backend-tests.sh record-fare-golden   # re-record expected fares
set -euo pipefail

STAGING_DIR=/var/www/ziggo-staging
DB=ziggo_postgres_staging
IMAGE=ziggo-staging-backend

cd "$STAGING_DIR"
DB_USER=$(sed -n 's/^POSTGRES_USER=//p' .env)
DB_PASS=$(sed -n 's/^POSTGRES_PASSWORD=//p' .env)
TEST_DB="ziggo_test_$(date +%s)"

sql() { docker exec -i "$DB" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
cleanup() { sql -c "DROP DATABASE IF EXISTS $TEST_DB WITH (FORCE)" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sql -c "CREATE DATABASE $TEST_DB"

if [ "${1:-}" = "record-fare-golden" ]; then
  mount=rw
  cmd="python tests/record_fare_golden.py"
else
  mount=ro
  cmd="python -m pytest -p no:cacheprovider $*"
fi

docker run --rm --network host \
  -e TZ=Asia/Colombo -e PYTHONDONTWRITEBYTECODE=1 -e PYTHONPATH=/work \
  -e DATABASE_URL="postgresql+asyncpg://$DB_USER:$DB_PASS@127.0.0.1:5434/$TEST_DB" \
  -e SYNC_DATABASE_URL="postgresql+psycopg://$DB_USER:$DB_PASS@127.0.0.1:5434/$TEST_DB" \
  -e SECRET_KEY=test-only -e DEV_MODE=true \
  -v "$STAGING_DIR/ziggo_backend:/work:$mount" -v ziggo_test_pip_cache:/root/.cache/pip \
  -w /work "$IMAGE" \
  sh -c "pip install -q --disable-pip-version-check --root-user-action=ignore -r requirements-dev.txt && $cmd"

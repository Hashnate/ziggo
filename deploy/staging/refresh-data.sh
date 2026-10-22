#!/usr/bin/env bash
# Rebuild the STAGING database: production's business setup plus generated data.
#
#   cd /var/www/ziggo-staging && deploy/staging/refresh-data.sh
#
# Only business tables are read from production (fare rates, settings, zones,
# promo codes, restaurant and vendor catalogs, events), through SELECTs that
# blank owner links, phone numbers, emails and bank details on the production
# side, so no personal data leaves it. Business images are copied; personal
# upload folders (driver documents and photos, customer photos, vehicle photos,
# vendor KYC) are not. generate_data.py then creates customers, drivers and
# trips. Logins go to /root/ziggo-staging-admin-logins.txt, keeping existing
# admin passwords. If anything fails, the previous staging database is kept.
set -euo pipefail

STAGING_DIR=/var/www/ziggo-staging
PROD_DB=ziggo_postgres
PROD_APP=ziggo_backend
DB=ziggo_postgres_staging
APP=ziggo_backend_staging
DB_USER=ziggo_staging
DB_NAME=ziggo_staging
BUILD=ziggo_build
LOGINS=/root/ziggo-staging-admin-logins.txt
UPLOADS=/app/ziggo_admin_panel/static/uploads

# Loaded in this order so foreign keys resolve.
TABLES=(
  system_settings fare_settings peak_hour_settings surge_zones flash_weight_tiers
  driver_incentives promo_codes
  restaurants menu_categories menu_items food_categories restaurant_food_categories
  food_collections food_collection_restaurants food_banners food_deals
  market_categories market_vendors products market_deals market_ads
  events event_ticket_tiers
)
# Columns replaced on the production side, as "column=SQL expression;...".
declare -A BLANKED=(
  [restaurants]="owner_id=NULL;phone_number='0003' || lpad(id::text, 6, '0');email=NULL"
  [market_vendors]="owner_id=NULL;phone_number='0004' || lpad(id::text, 6, '0');bank_name=NULL;account_holder_name=NULL;account_number=NULL;branch_name=NULL;nic_passport_copy_url=NULL;business_reg_cert_url=NULL;tax_cert_url=NULL;food_license_url=NULL;additional_docs_url=NULL"
  [events]="organizer_name='Organizer ' || id;organizer_phone=NULL"
)
# Business images only.
IMAGE_DIRS=(branding categories events food_home market_ads market_home market_vendors menu_items products restaurants vendors jobs)

cd "$STAGING_DIR"
compose() { docker compose -f docker-compose.staging.yml -p ziggo_staging "$@"; }
sql() { docker exec -i "$DB" psql -U "$DB_USER" -v ON_ERROR_STOP=1 -q "$@"; }

app_stopped=0
swapped=0
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$swapped" = 1 ]; then
    compose stop "$APP" >/dev/null 2>&1 || true
    sql -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE)" \
      -c "ALTER DATABASE ${DB_NAME}_prev RENAME TO $DB_NAME" || true
    app_stopped=1
  fi
  sql -d postgres -c "DROP DATABASE IF EXISTS $BUILD WITH (FORCE)" >/dev/null 2>&1 || true
  if [ "$app_stopped" = 1 ]; then
    compose up -d --no-build --wait >/dev/null 2>&1 || true
  fi
  if [ "$status" -ne 0 ]; then
    echo "FAILED (exit $status). The previous staging database was kept." >&2
  fi
}
trap cleanup EXIT

select_for() {
  # "SELECT <every staging column> FROM <table>", with blanked columns replaced.
  local missing
  missing=$(sql -d "$BUILD" -At -v t="$1" -v blanked="${BLANKED[$1]:-}" <<'SQL'
SELECT string_agg(col, ', ') FROM (
  SELECT split_part(pair, '=', 1) AS col FROM unnest(string_to_array(:'blanked', ';')) AS pair WHERE pair <> ''
) b
WHERE col NOT IN (SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = :'t');
SQL
)
  if [ -n "$missing" ]; then
    echo "Column(s) to blank not found in $1: $missing" >&2
    return 1
  fi
  sql -d "$BUILD" -At -v t="$1" -v blanked="${BLANKED[$1]:-}" <<'SQL'
WITH b AS (
  SELECT split_part(pair, '=', 1) AS col, substr(pair, strpos(pair, '=') + 1) AS expr
  FROM unnest(string_to_array(:'blanked', ';')) AS pair WHERE pair <> ''
)
SELECT 'SELECT ' || string_agg(coalesce(b.expr || ' AS ' || quote_ident(c.column_name), quote_ident(c.column_name)),
                               ', ' ORDER BY c.ordinal_position) || ' FROM ' || quote_ident(:'t')
FROM information_schema.columns c LEFT JOIN b ON b.col = c.column_name
WHERE c.table_schema = 'public' AND c.table_name = :'t';
SQL
}

copy_from_prod() {
  local t=$1 query cols
  query=$(select_for "$t")
  cols=$(sql -d "$BUILD" -At -c "SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = '$t'")
  docker exec "$PROD_DB" psql -U ziggo -d ziggo -v ON_ERROR_STOP=1 -c "\\copy ($query) TO STDOUT" \
    | sql -d "$BUILD" -c "\\copy $t ($cols) FROM STDIN"
  if sql -d "$BUILD" -At -c "SELECT pg_get_serial_sequence('$t', 'id')" 2>/dev/null | grep -q .; then
    sql -d "$BUILD" -At -c "SELECT setval(pg_get_serial_sequence('$t', 'id'), coalesce(max(id), 1), max(id) IS NOT NULL) FROM $t" >/dev/null
  fi
  printf '   %-28s %s rows\n' "$t" "$(sql -d "$BUILD" -At -c "SELECT count(*) FROM $t")"
}

admin_password() {
  # Keep the staging admin password already handed out, or make a new one.
  local pw
  pw=$(awk -v p="$1" '$1 == p && $2 == "admin" {print $NF}' "$LOGINS" 2>/dev/null | head -1)
  [ -n "$pw" ] || pw=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)
  echo "$pw"
}

echo "1/7 Creating an empty copy of the staging schema"
sql -d postgres -c "DROP DATABASE IF EXISTS $BUILD WITH (FORCE)" -c "CREATE DATABASE $BUILD"
docker exec "$DB" pg_dump -U "$DB_USER" -d "$DB_NAME" --schema-only --no-owner --no-privileges | sql -d "$BUILD" >/dev/null

echo "2/7 Copying business setup from production (personal columns blanked at the source)"
for t in "${TABLES[@]}"; do copy_from_prod "$t"; done

echo "3/7 Swapping it in as $DB_NAME"
compose stop "$APP" >/dev/null
app_stopped=1
sql -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME}_prev WITH (FORCE)" \
  -c "ALTER DATABASE $DB_NAME RENAME TO ${DB_NAME}_prev" -c "ALTER DATABASE $BUILD RENAME TO $DB_NAME" >/dev/null
swapped=1

echo "4/7 Starting staging"
compose up -d --no-build --wait >/dev/null
app_stopped=0

echo "5/7 Generating customers, drivers and trips"
P0=$(admin_password 0700000000); P1=$(admin_password 0700000001); P2=$(admin_password 0700000002)
docker exec -i -e ADMIN_PASSWORDS="$P0,$P1,$P2" "$APP" python - < deploy/staging/generate_data.py

echo "6/7 Copying business images"
dirs=$(docker exec "$PROD_APP" sh -c "cd $UPLOADS && ls -d ${IMAGE_DIRS[*]} 2>/dev/null" | tr '\n' ' ')
docker exec "$PROD_APP" tar -C "$UPLOADS" -cf - $dirs | docker exec -i "$APP" tar -C "$UPLOADS" -xf -
echo "   copied: $dirs"

echo "7/7 Writing logins"
umask 077
{
  echo "# Ziggo STAGING logins (https://test.ziggo.lk), refreshed $(date '+%F %H:%M %Z'). Generated data only."
  echo "# Admin panel: https://test.ziggo.lk/admin/login with phone + password."
  echo "# App: test phones log in with the code the API returns (DEV_MODE, no SMS is sent)."
  echo "0700000000  admin (superadmin)  $P0"
  echo "0700000001  admin (admin)       $P1"
  echo "0700000002  admin (data_entry)  $P2"
} > "$LOGINS"
sql -d "$DB_NAME" -At -F '  ' -c "SELECT phone_number, full_name FROM users WHERE phone_number LIKE '077%' ORDER BY phone_number" \
  | sed 's/^/app: /' >> "$LOGINS"

sql -d postgres -c "DROP DATABASE ${DB_NAME}_prev WITH (FORCE)"
swapped=0
curl -fsS http://127.0.0.1:8031/health
echo
echo "Done. Logins are in $LOGINS"

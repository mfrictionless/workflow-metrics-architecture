#!/bin/sh
# M2.4 regression check: warehouse-postgres is a second, genuinely separate
# Postgres instance from ods-postgres -- distinct container, distinct
# volume, own port, and no visibility into ODS tables. This is the concrete
# form of FR-2 (CDC adds no load to the write primary): the write primary
# and the warehouse physically cannot share load. See design/Milestones.md
# M2.4.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${ODS_POSTGRES_USER:=postgres}"
: "${WAREHOUSE_POSTGRES_USER:=postgres}"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

./scripts/compose_up.sh >/dev/null

wait_ready_or_die() {
  service=$1
  user=$2
  ready=0
  i=0
  while [ "$i" -lt 30 ]; do
    if docker compose exec -T "$service" pg_isready -U "$user" >/dev/null 2>&1; then
      ready=1
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    printf 'FAIL: %s did not become ready within 30s\n' "$service" >&2
    exit 1
  fi
}

wait_ready_or_die ods-postgres "$ODS_POSTGRES_USER"
wait_ready_or_die warehouse-postgres "$WAREHOUSE_POSTGRES_USER"

# 1. Two distinct containers, two distinct volumes.
ods_cid=$(docker compose ps -q ods-postgres)
wh_cid=$(docker compose ps -q warehouse-postgres)
[ -n "$ods_cid" ] && [ -n "$wh_cid" ] || err "expected both containers to be running"
[ "$ods_cid" != "$wh_cid" ] || err "expected ods-postgres and warehouse-postgres to be different containers"

ods_vol=$(docker inspect "$ods_cid" --format '{{range .Mounts}}{{.Name}}{{end}}' 2>/dev/null)
wh_vol=$(docker inspect "$wh_cid" --format '{{range .Mounts}}{{.Name}}{{end}}' 2>/dev/null)
[ -n "$ods_vol" ] && [ -n "$wh_vol" ] || err "expected both containers to have a named volume mounted"
[ "$ods_vol" != "$wh_vol" ] || err "expected ods-postgres and warehouse-postgres to use different volumes"

# 2. A row written to the ODS is not visible in the warehouse -- there's no
# 'files' table there at all, not just an empty one.
docker compose exec -T ods-postgres psql -U "$ODS_POSTGRES_USER" -d "${ODS_POSTGRES_DB:-ods}" -v ON_ERROR_STOP=1 \
  -c "INSERT INTO files (file_number, status, opened_at, product_type) VALUES ('WH-ISOLATION-TEST', 'WIP', now(), 'REFINANCE');" >/dev/null

has_table=$(docker compose exec -T warehouse-postgres psql -U "$WAREHOUSE_POSTGRES_USER" -d "${WAREHOUSE_POSTGRES_DB:-warehouse}" -tAc \
  "SELECT 1 FROM information_schema.tables WHERE table_name='files';" 2>/dev/null | tr -d '[:space:]')
[ "$has_table" != "1" ] || err "expected the warehouse instance to have no 'files' table, but it does"

if [ "$fail" -ne 0 ]; then
  printf '\nwarehouse postgres check FAILED\n' >&2
  exit 1
fi
printf 'warehouse postgres check passed\n'

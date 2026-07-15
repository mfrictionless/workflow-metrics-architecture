#!/bin/sh
# M3.1 regression check: the dbt project connects to warehouse-postgres and
# its `raw` source declarations resolve to the real Raw tables (M2.5/M2.6),
# not just a config that parses. See design/Milestones.md M3.1.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${CONNECT_REST_PORT:=8083}"
BASE_URL="http://localhost:${CONNECT_REST_PORT}"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

./scripts/compose_up.sh >/dev/null

# 1. dbt debug passes -- profiles/project found, connection OK.
debug_output=$(docker compose run --rm dbt --no-use-colors debug 2>&1) || true
if ! printf '%s' "$debug_output" | grep -q "All checks passed!"; then
  err "dbt debug did not report all checks passed"
  printf '%s\n' "$debug_output" >&2
fi

# 2. dbt run completes cleanly, not an error. Originally asserted "Nothing
# to do" when the project had 0 models (M3.1); staging models exist as of
# M3.2, so this now checks for a clean "Completed successfully" instead --
# still proving the run doesn't error, without pinning to a model count that
# is expected to keep growing (M3.3+).
run_output=$(docker compose run --rm dbt --no-use-colors run 2>&1) || true
if ! printf '%s' "$run_output" | grep -q "Completed successfully"; then
  err "dbt run did not complete successfully"
  printf '%s\n' "$run_output" >&2
fi

# 3. The 'raw' source resolves to live data, not just a config that parses.
i=0
while [ "$i" -lt 60 ]; do
  curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/connectors" 2>/dev/null | grep -q '^200$' && break
  i=$((i + 1))
  sleep 1
done

./scripts/register_connector.sh >/dev/null
./scripts/seed.sh >/dev/null

landed=0
i=0
while [ "$i" -lt 30 ]; do
  count=$(docker compose exec -T warehouse-postgres psql -U postgres -d warehouse -tAc "SELECT count(*) FROM raw_files;" 2>/dev/null | tr -d '[:space:]')
  [ "$count" = "1" ] && { landed=1; break; }
  i=$((i + 1))
  sleep 1
done
[ "$landed" -eq 1 ] || err "expected 1 row in raw_files within 30s of seeding"

show_output=$(docker compose run --rm dbt --no-use-colors show --inline "select count(*) as n from {{ source('raw','files') }}" 2>&1) || true
n=$(printf '%s' "$show_output" | grep -oE '\| [0-9]+ \|$' | tail -1 | grep -oE '[0-9]+' || true)
[ "$n" = "1" ] || {
  err "expected the 'raw.files' source to resolve to 1 row, got '${n:-<none>}'"
  printf '%s\n' "$show_output" >&2
}

if [ "$fail" -ne 0 ]; then
  printf '\ndbt scaffold check FAILED\n' >&2
  exit 1
fi
printf 'dbt scaffold check passed\n'

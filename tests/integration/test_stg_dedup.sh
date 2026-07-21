#!/bin/sh
# M3.2 regression check: the staging models (stg_files, stg_file_actions,
# stg_parties) collapse Raw's append-only landing to exactly one current row
# per business key. Proven against two sources of duplication: (1) real
# multi-version data from the M2.8 lifecycle simulator (a WIP insert then a
# CLOSED update land as two raw_files/raw_file_actions rows per key) and (2)
# a synthetic byte-for-byte duplicate raw_files row, covering at-least-once
# Kafka redelivery, which the pipeline doesn't reproduce deterministically.
# See design/Milestones.md M3.2 and design/Decisions.md D017.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${CONNECT_REST_PORT:=8083}"
: "${WAREHOUSE_POSTGRES_USER:=postgres}"
: "${WAREHOUSE_POSTGRES_DB:=warehouse}"
BASE_URL="http://localhost:${CONNECT_REST_PORT}"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

psql_wh() {
  docker compose exec -T warehouse-postgres psql -U "$WAREHOUSE_POSTGRES_USER" -d "$WAREHOUSE_POSTGRES_DB" -tAc "$1" 2>/dev/null | tr -d '[:space:]'
}

./scripts/compose_up.sh >/dev/null

ready=0
i=0
while [ "$i" -lt 60 ]; do
  if curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/connectors" 2>/dev/null | grep -q '^200$'; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
[ "$ready" -eq 1 ] || { printf 'FAIL: Kafka Connect REST API did not become ready within 60s\n' >&2; exit 1; }

./scripts/register_connector.sh >/dev/null

running=0
i=0
while [ "$i" -lt 30 ]; do
  status_json=$(curl -s "${BASE_URL}/connectors/warehouse-raw-sink/status" 2>/dev/null || true)
  state=$(printf '%s' "$status_json" | jq -r '.connector.state' 2>/dev/null || true)
  task_state=$(printf '%s' "$status_json" | jq -r '.tasks[0].state' 2>/dev/null || true)
  [ "$state" = "RUNNING" ] && [ "$task_state" = "RUNNING" ] && { running=1; break; }
  i=$((i + 1))
  sleep 1
done
[ "$running" -eq 1 ] || err "sink connector/task did not both reach RUNNING within 30s"

# M2.8 lifecycle: 2 raw_files rows (c/WIP + u/CLOSED), 8 raw_file_actions
# (4 c + 4 u), 6 raw_parties (c only) for the one simulated file.
COUNT=1 ./scripts/simulate.sh >/dev/null

wait_count() {
  table=$1
  expected=$2
  i=0
  while [ "$i" -lt 30 ]; do
    count=$(psql_wh "SELECT count(*) FROM ${table};")
    [ "$count" = "$expected" ] && return 0
    i=$((i + 1))
    sleep 1
  done
  return 1
}
wait_count raw_files 2 || err "expected 2 raw_files rows (c+u) within 30s of simulate"
wait_count raw_file_actions 8 || err "expected 8 raw_file_actions rows (4 c + 4 u) within 30s of simulate"
wait_count raw_parties 6 || err "expected 6 raw_parties rows within 30s of simulate"

# Synthetic redelivery case: a reserved file_id the simulator never
# generates, inserted twice with identical values/_cdc_ts.
psql_wh "INSERT INTO raw_files (file_id, file_number, status, opened_at, closed_at, county_fips, product_type, _cdc_op, _cdc_ts, _sink_ts, _cdc_txn_id, _cdc_source_txn_id) VALUES (999999, 'SIM-TEST-DEDUP', 'CLOSED', now(), now(), '06037', 'REFINANCE', 'c', 1700000000000, now(), 'test:1', 999001);" >/dev/null
psql_wh "INSERT INTO raw_files (file_id, file_number, status, opened_at, closed_at, county_fips, product_type, _cdc_op, _cdc_ts, _sink_ts, _cdc_txn_id, _cdc_source_txn_id) VALUES (999999, 'SIM-TEST-DEDUP', 'CLOSED', now(), now(), '06037', 'REFINANCE', 'c', 1700000000000, now(), 'test:1', 999001);" >/dev/null

docker compose run --rm dbt --no-use-colors run >/dev/null

# 1. Multi-version collapse (real): the simulated file's stg_files/stg_file_actions
# rows are exactly 1 per key, reflecting the latest (CLOSED/received) version.
real_file_id=$(psql_wh "SELECT file_id FROM raw_files WHERE file_id <> 999999 LIMIT 1;")
[ -n "$real_file_id" ] || err "expected a real simulated file_id in raw_files"

stg_files_count=$(psql_wh "SELECT count(*) FROM stg_files WHERE file_id = ${real_file_id:-0};")
[ "$stg_files_count" = "1" ] || err "expected exactly 1 stg_files row for file_id=$real_file_id, got $stg_files_count"

stg_files_status=$(psql_wh "SELECT status FROM stg_files WHERE file_id = ${real_file_id:-0};")
[ "$stg_files_status" = "CLOSED" ] || err "expected stg_files.status='CLOSED' for file_id=$real_file_id, got '$stg_files_status'"

stg_actions_null_received=$(psql_wh "SELECT count(*) FROM stg_file_actions WHERE file_id = ${real_file_id:-0} AND received_at IS NULL;")
[ "$stg_actions_null_received" = "0" ] || err "expected every stg_file_actions row for file_id=$real_file_id to have received_at set, found $stg_actions_null_received null"

stg_actions_count=$(psql_wh "SELECT count(*) FROM stg_file_actions WHERE file_id = ${real_file_id:-0};")
[ "$stg_actions_count" = "4" ] || err "expected exactly 4 stg_file_actions rows for file_id=$real_file_id, got $stg_actions_count"

# 2. Redelivery collapse (synthetic): the duplicate reserved file_id still
# collapses to exactly 1 stg_files row.
reserved_count=$(psql_wh "SELECT count(*) FROM stg_files WHERE file_id = 999999;")
[ "$reserved_count" = "1" ] || err "expected exactly 1 stg_files row for the reserved duplicate file_id=999999, got $reserved_count"

# 3. No entity lost or duplicated, across all raw_files/raw_file_actions/raw_parties.
distinct_files=$(psql_wh "SELECT count(DISTINCT file_id) FROM raw_files;")
stg_files_total=$(psql_wh "SELECT count(*) FROM stg_files;")
[ "$distinct_files" = "$stg_files_total" ] || err "expected count(distinct file_id) in raw_files ($distinct_files) to equal count(*) in stg_files ($stg_files_total)"

distinct_actions=$(psql_wh "SELECT count(DISTINCT file_action_id) FROM raw_file_actions;")
stg_actions_total=$(psql_wh "SELECT count(*) FROM stg_file_actions;")
[ "$distinct_actions" = "$stg_actions_total" ] || err "expected count(distinct file_action_id) in raw_file_actions ($distinct_actions) to equal count(*) in stg_file_actions ($stg_actions_total)"

distinct_parties=$(psql_wh "SELECT count(DISTINCT party_id) FROM raw_parties;")
stg_parties_total=$(psql_wh "SELECT count(*) FROM stg_parties;")
[ "$distinct_parties" = "$stg_parties_total" ] || err "expected count(distinct party_id) in raw_parties ($distinct_parties) to equal count(*) in stg_parties ($stg_parties_total)"

# 4. dbt test passes (unique/not_null on each staging key).
if ! docker compose run --rm dbt --no-use-colors test >/tmp/dbt_test_output_$$ 2>&1; then
  err "dbt test failed"
  cat /tmp/dbt_test_output_$$ >&2
fi
rm -f /tmp/dbt_test_output_$$

if [ "$fail" -ne 0 ]; then
  printf '\nstaging dedup check FAILED\n' >&2
  exit 1
fi
printf 'staging dedup check passed\n'

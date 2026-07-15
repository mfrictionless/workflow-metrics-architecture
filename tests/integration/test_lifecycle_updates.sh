#!/bin/sh
# M2.8 regression check: the simulator writes each file through a two-phase
# lifecycle (INSERT the WIP file/actions, then UPDATE to CLOSED/received), so
# the CDC pipeline finally exercises UPDATE events. ODS UPDATEs modify rows
# in place -- the extra versions appear only in the append-only Raw landing
# (raw_files/raw_file_actions get a `c` then a `u` row per key), while the
# ODS final state per file is unchanged. See design/Milestones.md M2.8 and
# design/Decisions.md D016.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${CONNECT_REST_PORT:=8083}"
: "${WAREHOUSE_POSTGRES_USER:=postgres}"
: "${WAREHOUSE_POSTGRES_DB:=warehouse}"
: "${ODS_POSTGRES_USER:=postgres}"
: "${ODS_POSTGRES_DB:=ods}"
BASE_URL="http://localhost:${CONNECT_REST_PORT}"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

psql_wh() {
  docker compose exec -T warehouse-postgres psql -U "$WAREHOUSE_POSTGRES_USER" -d "$WAREHOUSE_POSTGRES_DB" -tAc "$1" 2>/dev/null | tr -d '[:space:]'
}
psql_ods() {
  docker compose exec -T ods-postgres psql -U "$ODS_POSTGRES_USER" -d "$ODS_POSTGRES_DB" -tAc "$1" 2>/dev/null | tr -d '[:space:]'
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

COUNT=1 ./scripts/simulate.sh >/dev/null

# The lifecycle lands 2 raw_files rows (c + u), 8 raw_file_actions (4 c + 4 u),
# and 6 raw_parties (c only) per simulated file.
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
wait_count raw_files 2 || err "expected 2 raw_files rows (c + u) within 30s"
wait_count raw_file_actions 8 || err "expected 8 raw_file_actions rows (4 c + 4 u) within 30s"
wait_count raw_parties 6 || err "expected 6 raw_parties rows (c only) within 30s"

# 1. ODS final state is the in-place-updated closed file -- unchanged from the
# old insert-only simulator: 1 CLOSED file, 4 received actions, 6 parties.
[ "$(psql_ods "SELECT count(*) FROM files;")" = "1" ] || err "expected 1 file in the ODS"
[ "$(psql_ods "SELECT count(*) FROM files WHERE status='CLOSED' AND closed_at IS NOT NULL;")" = "1" ] || err "expected the ODS file to be CLOSED with a closed_at"
[ "$(psql_ods "SELECT count(*) FROM file_actions;")" = "4" ] || err "expected 4 file_actions in the ODS"
[ "$(psql_ods "SELECT count(*) FROM file_actions WHERE received_at IS NULL;")" = "0" ] || err "expected every ODS file_action to have received_at set after close"
[ "$(psql_ods "SELECT count(*) FROM parties;")" = "6" ] || err "expected 6 parties in the ODS"

# 2. raw_files carries the create-then-update version pair.
[ "$(psql_wh "SELECT count(*) FROM raw_files WHERE _cdc_op='c' AND status='WIP';")" = "1" ] || err "expected 1 raw_files row op=c/status=WIP"
[ "$(psql_wh "SELECT count(*) FROM raw_files WHERE _cdc_op='u' AND status='CLOSED';")" = "1" ] || err "expected 1 raw_files row op=u/status=CLOSED"
# The update's event timestamp must be >= the create's (create lands first).
c_ts=$(psql_wh "SELECT _cdc_ts FROM raw_files WHERE _cdc_op='c';")
u_ts=$(psql_wh "SELECT _cdc_ts FROM raw_files WHERE _cdc_op='u';")
[ -n "$c_ts" ] && [ -n "$u_ts" ] && [ "$u_ts" -ge "$c_ts" ] || err "expected the update _cdc_ts ($u_ts) to be >= the create _cdc_ts ($c_ts)"

# 3. raw_file_actions: 4 create rows (received_at null) + 4 update rows (set).
[ "$(psql_wh "SELECT count(*) FROM raw_file_actions WHERE _cdc_op='c' AND received_at IS NULL;")" = "4" ] || err "expected 4 raw_file_actions op=c with received_at NULL"
[ "$(psql_wh "SELECT count(*) FROM raw_file_actions WHERE _cdc_op='u' AND received_at IS NOT NULL;")" = "4" ] || err "expected 4 raw_file_actions op=u with received_at set"

# 4. raw_parties are insert-only.
[ "$(psql_wh "SELECT count(*) FROM raw_parties WHERE _cdc_op<>'c';")" = "0" ] || err "expected all raw_parties rows to be op=c (insert-only)"

# 5. Two transactions: all create rows share one source txId; all update rows
# share a second, different one (M2.6 correlation still holds per phase).
c_txn=$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_files WHERE _cdc_op='c';")
u_txn=$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_files WHERE _cdc_op='u';")
[ -n "$c_txn" ] && [ -n "$u_txn" ] || err "expected non-null source txn ids on both create and update raw_files rows"
[ "$c_txn" != "$u_txn" ] || err "expected the update txn ($u_txn) to differ from the create txn ($c_txn)"
# Create rows across all three tables share the create txn.
[ "$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_parties;")" = "$c_txn" ] || err "expected raw_parties to share the create txn $c_txn"
[ "$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_file_actions WHERE _cdc_op='c';")" = "$c_txn" ] || err "expected raw_file_actions create rows to share the create txn $c_txn"
# Update rows (files + file_actions) share the update txn.
[ "$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_file_actions WHERE _cdc_op='u';")" = "$u_txn" ] || err "expected raw_file_actions update rows to share the update txn $u_txn"

if [ "$fail" -ne 0 ]; then
  printf '\nlifecycle updates check FAILED\n' >&2
  exit 1
fi
printf 'lifecycle updates check passed\n'

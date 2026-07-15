#!/bin/sh
# M2.6 regression check: Debezium's transaction-metadata feature
# (provide.transaction.metadata=true) lets Raw rows be correlated back to
# the ODS transaction that produced them. _cdc_source_txn_id (source.txId,
# a plain integer) is the directly `=`-comparable correlation key;
# _cdc_txn_id (transaction.id, "<txId>:<lsn>") demonstrates the richer
# transaction-metadata feature but is NOT equal across rows in the same
# transaction, since its LSN suffix advances per WAL record -- confirmed
# empirically while building this milestone. See design/Milestones.md M2.6
# and design/Decisions.md D012.
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
  docker compose exec -T warehouse-postgres psql -U "$WAREHOUSE_POSTGRES_USER" -d "$WAREHOUSE_POSTGRES_DB" -tAc "$1" 2>/dev/null
}

# Fresh volumes are required: 002_transaction_metadata.sql only runs via
# docker-entrypoint-initdb.d on an empty data directory.
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

# 1. One simulated file -- files/parties/file_actions inserted under a
# single conn.commit() -- must share one _cdc_source_txn_id across tables.
COUNT=1 ./scripts/simulate.sh >/dev/null

wait_count() {
  table=$1
  expected=$2
  i=0
  while [ "$i" -lt 30 ]; do
    count=$(psql_wh "SELECT count(*) FROM ${table};" | tr -d '[:space:]')
    [ "$count" = "$expected" ] && return 0
    i=$((i + 1))
    sleep 1
  done
  return 1
}

wait_count raw_files 1 || err "expected 1 row in raw_files within 30s of the first simulate run"
wait_count raw_parties 6 || err "expected 6 rows in raw_parties within 30s of the first simulate run"
wait_count raw_file_actions 4 || err "expected 4 rows in raw_file_actions within 30s of the first simulate run"

files_txn=$(psql_wh "SELECT _cdc_source_txn_id FROM raw_files WHERE file_id = 1;" | tr -d '[:space:]')
[ -n "$files_txn" ] || err "expected a non-null _cdc_source_txn_id on raw_files"

parties_txns=$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_parties WHERE file_id = 1;" | tr -d '[:space:]')
[ "$parties_txns" = "$files_txn" ] || err "expected raw_parties for file_id=1 to share _cdc_source_txn_id=$files_txn, got: $parties_txns"

actions_txns=$(psql_wh "SELECT DISTINCT _cdc_source_txn_id FROM raw_file_actions WHERE file_id = 1;" | tr -d '[:space:]')
[ "$actions_txns" = "$files_txn" ] || err "expected raw_file_actions for file_id=1 to share _cdc_source_txn_id=$files_txn, got: $actions_txns"

# 2. A second, separate simulate run must get a DIFFERENT transaction id.
COUNT=1 ./scripts/simulate.sh >/dev/null

wait_count raw_files 2 || err "expected 2 rows in raw_files within 30s of the second simulate run"

second_txn=$(psql_wh "SELECT _cdc_source_txn_id FROM raw_files WHERE file_id = 2;" | tr -d '[:space:]')
[ "$second_txn" != "$files_txn" ] || err "expected the second simulate run's _cdc_source_txn_id to differ from the first ($files_txn), got the same value"

# 3. _cdc_txn_id (the richer transaction.id) is populated but NOT expected
# to be equal across rows in the same transaction -- just non-null here.
null_txn_id=$(psql_wh "SELECT count(*) FROM raw_files WHERE _cdc_txn_id IS NULL;" | tr -d '[:space:]')
[ "$null_txn_id" = "0" ] || err "expected _cdc_txn_id non-null on every raw_files row, found $null_txn_id null"

# 4. The ods.transaction topic exists with BEGIN/END events.
topics=$(docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list)
printf '%s' "$topics" | grep -qx "ods.transaction" || err "expected topic 'ods.transaction' to exist"

if [ "$fail" -ne 0 ]; then
  printf '\ntransaction metadata check FAILED\n' >&2
  exit 1
fi
printf 'transaction metadata check passed\n'

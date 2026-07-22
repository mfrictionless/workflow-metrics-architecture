#!/bin/sh
# Regression check: the Debezium JDBC sink connector lands ods.public.*
# topic messages into pre-defined Raw tables (warehouse/ddl/001_raw_schema.sql)
# in the warehouse, with _cdc_op/_cdc_ts/_cdc_source_lsn/_cdc_topic_offset
# (stamped by an SMT chain) and _sink_ts (a Postgres-side DEFAULT) populated 
# on every row.
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
if [ "$ready" -ne 1 ]; then
  printf 'FAIL: Kafka Connect REST API did not become ready within 60s\n' >&2
  exit 1
fi

./scripts/register_connector.sh >/dev/null

running=0
i=0
while [ "$i" -lt 30 ]; do
  status_json=$(curl -s "${BASE_URL}/connectors/warehouse-raw-sink/status" 2>/dev/null || true)
  state=$(printf '%s' "$status_json" | jq -r '.connector.state' 2>/dev/null || true)
  task_state=$(printf '%s' "$status_json" | jq -r '.tasks[0].state' 2>/dev/null || true)
  if [ "$state" = "RUNNING" ] && [ "$task_state" = "RUNNING" ]; then
    running=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$running" -ne 1 ]; then
  err "sink connector/task did not both reach RUNNING within 30s (connector: ${state:-unknown}, task: ${task_state:-unknown})"
fi

./scripts/seed.sh >/dev/null

psql_wh() {
  docker compose exec -T warehouse-postgres psql -U "$WAREHOUSE_POSTGRES_USER" -d "$WAREHOUSE_POSTGRES_DB" -tAc "$1" 2>/dev/null
}
psql_ods() {
  docker compose exec -T ods-postgres psql -U "${ODS_POSTGRES_USER:-postgres}" -d "${ODS_POSTGRES_DB:-ods}" -tAc "$1" 2>/dev/null
}

  # Wait for the seeded row to land (async pipeline).
  landed=0
  i=0
  while [ "$i" -lt 30 ]; do
    count=$(psql_wh "SELECT count(*) FROM raw_files;" | tr -d '[:space:]')
    [ "$count" = "1" ] && { landed=1; break; }
    i=$((i + 1))
    sleep 1
  done
  if [ "$landed" -ne 1 ]; then
    err "expected 1 row in raw_files within 30s of seeding, found '${count:-0}'"
  fi

# Row counts match ODS for all 6 seeded tables.
for pair in "files:raw_files" "file_actions:raw_file_actions" "users:raw_users" "persons:raw_persons" "parties:raw_parties" "audit_events:raw_audit_events"; do
  ods_table=${pair%%:*}
  raw_table=${pair##*:}
  ods_count=$(psql_ods "SELECT count(*) FROM ${ods_table};" | tr -d '[:space:]')
  raw_count=$(psql_wh "SELECT count(*) FROM ${raw_table};" | tr -d '[:space:]')
  [ "$ods_count" = "$raw_count" ] || err "row count mismatch: ${ods_table}=${ods_count} vs ${raw_table}=${raw_count}"
done

# Change Data Capture metadata columns populated on every row, on every raw
# table. _cdc_op/_cdc_ts/_cdc_source_lsn/_cdc_topic_offset are
# populated by the Debezium/JDBC-sink SMT chain; _sink_ts is a Warehouse
# Postgres-side DEFAULT.
for raw_table in raw_files raw_file_actions raw_users raw_persons raw_parties raw_audit_events; do
  for col in _cdc_op _cdc_ts _cdc_source_lsn _cdc_topic_offset _sink_ts; do
    null_count=$(psql_wh "SELECT count(*) FROM ${raw_table} WHERE ${col} IS NULL;" | tr -d '[:space:]')
    [ "$null_count" = "0" ] || err "expected ${col} non-null on every ${raw_table} row, found '${null_count}' null"
  done
done

# This could fail if we use an update for our seeded row, but we don't. The seed.sh script uses an insert-only source table.
op_value=$(psql_wh "SELECT DISTINCT _cdc_op FROM raw_files;" | tr -d '[:space:]')
[ "$op_value" = "c" ] || err "expected _cdc_op='c' (create) for an insert-only source, got '$op_value'"

if [ "$fail" -ne 0 ]; then
  printf '\njdbc sink check FAILED\n' >&2
  exit 1
fi
printf 'jdbc sink check passed\n'

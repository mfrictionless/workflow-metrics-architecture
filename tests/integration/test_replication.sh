#!/bin/sh
# M2.1 regression check: the ODS is configured for logical replication --
# wal_level=logical, a publication covering all 4 source tables, and a
# pgoutput logical replication slot (dbz_slot) for Debezium (M2.3) to
# consume later. "Decodable WAL change" is verified via a separate,
# temporary test_decoding-plugin slot created and dropped within this test,
# so the real pgoutput slot is left untouched for M2.3.
# See design/Milestones.md M2.1.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${ODS_POSTGRES_USER:=postgres}"
: "${ODS_POSTGRES_DB:=ods}"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

psql_c() {
  docker compose exec -T ods-postgres psql -U "$ODS_POSTGRES_USER" -d "$ODS_POSTGRES_DB" -tAc "$1" 2>/dev/null
}

./scripts/compose_up.sh

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if docker compose exec -T ods-postgres pg_isready -U "$ODS_POSTGRES_USER" >/dev/null 2>&1; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  printf 'FAIL: ODS Postgres did not become ready within 30s\n' >&2
  exit 1
fi

# 1. wal_level is logical.
wal_level=$(psql_c "SHOW wal_level;" | tr -d '[:space:]')
[ "$wal_level" = "logical" ] || err "expected wal_level='logical', got '$wal_level'"

# 2. Publication covers all 4 source tables.
for t in files file_actions parties audit_events; do
  count=$(psql_c "SELECT count(*) FROM pg_publication_tables WHERE pubname='dbz_publication' AND tablename='$t';" | tr -d '[:space:]')
  [ "$count" = "1" ] || err "table '$t' is not in publication 'dbz_publication'"
done

# 3. The pgoutput slot for Debezium exists.
plugin=$(psql_c "SELECT plugin FROM pg_replication_slots WHERE slot_name='dbz_slot';" | tr -d '[:space:]')
[ "$plugin" = "pgoutput" ] || err "expected dbz_slot with plugin='pgoutput', got plugin='$plugin'"

slot_type=$(psql_c "SELECT slot_type FROM pg_replication_slots WHERE slot_name='dbz_slot';" | tr -d '[:space:]')
[ "$slot_type" = "logical" ] || err "expected dbz_slot slot_type='logical', got '$slot_type'"

# 4. A manual INSERT produces a decodable WAL change -- verified via a
# separate, temporary test_decoding slot so dbz_slot stays untouched.
psql_c "SELECT pg_create_logical_replication_slot('test_decode_slot', 'test_decoding');" >/dev/null

psql_c "INSERT INTO files (file_number, status, opened_at, product_type) VALUES ('REPL-TEST', 'WIP', now(), 'REFINANCE');" >/dev/null

changes=$(psql_c "SELECT data FROM pg_logical_slot_get_changes('test_decode_slot', NULL, NULL);")

psql_c "SELECT pg_drop_replication_slot('test_decode_slot');" >/dev/null

if ! printf '%s' "$changes" | grep -q "INSERT"; then
  err "expected decoded WAL output to contain 'INSERT', got: $changes"
fi
if ! printf '%s' "$changes" | grep -qi "files"; then
  err "expected decoded WAL output to reference the 'files' table, got: $changes"
fi

if [ "$fail" -ne 0 ]; then
  printf '\nreplication check FAILED\n' >&2
  exit 1
fi
printf 'replication check passed\n'

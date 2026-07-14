#!/bin/sh
# M1.3 regression check: `make simulate COUNT=n` inserts n new, independent,
# fully-closed files via the simulator container -- no orphaned rows, no
# cross-file mixups, correct roles per step, additive (existing data
# untouched). See design/Milestones.md M1.3.
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

# 0 files before the simulator runs.
count=$(psql_c "SELECT count(*) FROM files;" | tr -d '[:space:]')
[ "$count" = "0" ] || err "expected 0 files before simulating, got $count"

# Run the simulator for 3 files.
COUNT=3 ./scripts/simulate.sh

count=$(psql_c "SELECT count(*) FROM files;" | tr -d '[:space:]')
[ "$count" = "3" ] || err "expected 3 files after COUNT=3, got $count"

closed_count=$(psql_c "SELECT count(*) FROM files WHERE status='CLOSED';" | tr -d '[:space:]')
[ "$closed_count" = "3" ] || err "expected all 3 files to be CLOSED, got $closed_count"

# Every file has exactly 4 file_actions and 6 parties -- no orphans, no
# cross-file mixups.
bad_actions=$(psql_c "
  SELECT count(*) FROM (
    SELECT file_id, count(*) AS n FROM file_actions GROUP BY file_id
  ) t WHERE t.n <> 4;
" | tr -d '[:space:]')
[ "$bad_actions" = "0" ] || err "$bad_actions file(s) do not have exactly 4 file_actions"

bad_parties=$(psql_c "
  SELECT count(*) FROM (
    SELECT file_id, count(*) AS n FROM parties GROUP BY file_id
  ) t WHERE t.n <> 6;
" | tr -d '[:space:]')
[ "$bad_parties" = "0" ] || err "$bad_parties file(s) do not have exactly 6 parties"

# No orphaned file_actions/parties (every file_id resolves to a real file).
orphan_actions=$(psql_c "SELECT count(*) FROM file_actions fa LEFT JOIN files f ON f.file_id = fa.file_id WHERE f.file_id IS NULL;" | tr -d '[:space:]')
[ "$orphan_actions" = "0" ] || err "$orphan_actions orphaned file_actions row(s)"

orphan_parties=$(psql_c "SELECT count(*) FROM parties p LEFT JOIN files f ON f.file_id = p.file_id WHERE f.file_id IS NULL;" | tr -d '[:space:]')
[ "$orphan_parties" = "0" ] || err "$orphan_parties orphaned parties row(s)"

# Sender/receiver roles correct per step, joined within the correct file
# (proves no cross-file mixups -- a wrong join would show a wrong role).
check_sender() {
  action_code="$1"; expected="$2"
  bad=$(psql_c "
    SELECT count(*) FROM file_actions fa
    JOIN parties p ON p.user_id = fa.sent_user_id AND p.file_id = fa.file_id
    WHERE fa.action_code = '$action_code' AND p.role <> '$expected';
  " | tr -d '[:space:]')
  [ "$bad" = "0" ] || err "$bad '$action_code' row(s) have a sender role other than '$expected'"
}

check_receiver() {
  action_code="$1"; expected="$2"
  bad=$(psql_c "
    SELECT count(*) FROM file_actions fa
    JOIN parties p ON p.user_id = fa.received_user_id AND p.file_id = fa.file_id
    WHERE fa.action_code = '$action_code' AND p.role <> '$expected';
  " | tr -d '[:space:]')
  [ "$bad" = "0" ] || err "$bad '$action_code' row(s) have a receiver role other than '$expected'"
}

check_sender "APPLICATION_SUBMIT" "BORROWER"
check_receiver "APPLICATION_SUBMIT" "LOAN_OFFICER"
check_sender "LOAN_PROCESS" "BORROWER"
check_receiver "LOAN_PROCESS" "LOAN_PROCESSOR"
check_sender "SIGNING" "BORROWER"
check_receiver "SIGNING" "TITLE_AGENT"
check_sender "RECORDING" "TITLE_AGENT"

null_recv=$(psql_c "SELECT count(*) FROM file_actions WHERE action_code='RECORDING' AND received_user_id IS NOT NULL;" | tr -d '[:space:]')
[ "$null_recv" = "0" ] || err "$null_recv RECORDING row(s) have a non-NULL received_user_id"

# Additive: running again adds more files rather than touching existing ones.
COUNT=1 ./scripts/simulate.sh
count=$(psql_c "SELECT count(*) FROM files;" | tr -d '[:space:]')
[ "$count" = "4" ] || err "expected 4 files after a second run with COUNT=1, got $count"

if [ "$fail" -ne 0 ]; then
  printf '\nsimulator check FAILED\n' >&2
  exit 1
fi
printf 'simulator check passed\n'

#!/bin/sh
# M1.2 regression check: `make up` alone must bring up an empty ODS, and
# `make seed` must insert exactly the truncated 4-step workflow described in
# design/Milestones.md M1.2 -- one closed file, correct timestamps,
# RACI-correct sender/receiver roles, and files.closed_at matching the
# terminal step's received_at.
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

# 1. `make up` alone must not seed anything.
count=$(psql_c "SELECT count(*) FROM files;" | tr -d '[:space:]')
[ "$count" = "0" ] || err "expected 0 files after 'make up' alone, got $count -- seed data must not auto-load"

# 2. Apply the seed.
./scripts/seed.sh

# 3. Exactly one closed file.
count=$(psql_c "SELECT count(*) FROM files;" | tr -d '[:space:]')
[ "$count" = "1" ] || err "expected exactly 1 file after 'make seed', got $count"

status=$(psql_c "SELECT status FROM files LIMIT 1;" | tr -d '[:space:]')
[ "$status" = "CLOSED" ] || err "expected seeded file status='CLOSED', got '$status'"

# 4. Exactly 4 file_actions, in the expected order.
actions=$(psql_c "SELECT string_agg(action_code, ',' ORDER BY sent_at) FROM file_actions;" | tr -d '[:space:]')
expected="APPLICATION_SUBMIT,LOAN_PROCESS,SIGNING,RECORDING"
[ "$actions" = "$expected" ] || err "expected action sequence '$expected', got '$actions'"

# 5. Every row has sent_at < received_at.
bad=$(psql_c "SELECT count(*) FROM file_actions WHERE NOT (sent_at < received_at);" | tr -d '[:space:]')
[ "$bad" = "0" ] || err "$bad file_actions row(s) do not have sent_at < received_at"

# 6. Sender/receiver roles match Home-Refinance-Workflow.md for each step.
check_sender() {
  action_code="$1"; expected="$2"
  actual=$(psql_c "
    SELECT par.role
    FROM file_actions fa INNER JOIN users su ON su.user_id = fa.sent_user_id INNER JOIN parties par ON par.person_id = su.person_id AND par.file_id = fa.file_id
    WHERE fa.action_code = '$action_code';" | tr -d '[:space:]')
  [ "$actual" = "$expected" ] || err "$action_code sender expected '$expected', got '$actual'"
}

check_receiver() {
  action_code="$1"; expected="$2"
  actual=$(psql_c "
    SELECT par.role
    FROM file_actions fa INNER JOIN parties par ON par.file_id = fa.file_id INNER JOIN users ru ON ru.person_id = par.person_id AND ru.user_id = fa.received_user_id
    WHERE fa.action_code = '$action_code';" | tr -d '[:space:]')
  [ "$actual" = "$expected" ] || err "$action_code receiver expected '$expected', got '$actual'"
}

check_sender "APPLICATION_SUBMIT" "BORROWER"
check_receiver "APPLICATION_SUBMIT" "LOAN_OFFICER"
check_sender "LOAN_PROCESS" "BORROWER"
check_receiver "LOAN_PROCESS" "LOAN_PROCESSOR"
check_sender "SIGNING" "BORROWER"
check_receiver "SIGNING" "TITLE_AGENT"
check_sender "RECORDING" "TITLE_AGENT"

# 7. RECORDING's person is the Autoclose System user.
recv=$(psql_c "
  SELECT p.display_name
  FROM file_actions fa
  INNER JOIN users u ON (
    u.user_id = fa.received_user_id)
  INNER JOIN persons p ON (
    p.person_id = u.person_id)
  WHERE
    action_code='RECORDING';")
[ "$recv" = "Autoclose System" ] || err "RECORDING.person_display_name expected 'Autoclose System', got '$recv'"

# 8. files.closed_at equals the RECORDING row's received_at.
closed_at=$(psql_c "SELECT closed_at FROM files LIMIT 1;")
recording_received_at=$(psql_c "SELECT received_at FROM file_actions WHERE action_code='RECORDING';")
[ "$closed_at" = "$recording_received_at" ] || err "files.closed_at ('$closed_at') does not match RECORDING.received_at ('$recording_received_at')"

if [ "$fail" -ne 0 ]; then
  printf '\nseed data check FAILED\n' >&2
  exit 1
fi
printf 'seed data check passed\n'
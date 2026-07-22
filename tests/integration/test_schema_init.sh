#!/bin/sh
# M1.1.1 (amended M1.1) regression check: the ODS schema mounts into Postgres's auto-init
# mechanism via docker-compose.yml and actually executes on `make up` --
# tables, foreign keys, ALL CAPS enum CHECK constraints, and per-column
# comments all present, with no manual `psql -f` step.
# See design/Milestones.md M1.1.
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

# 1. The mount is wired: 001_schema.sql is present where Postgres's auto-init
# mechanism looks for it. Numbered so a second init file (002_replication.sql,
# M2.1) is guaranteed to run after it -- alphabetical order, not directory
# listing order, controls execution sequence.
docker compose exec -T ods-postgres test -f /docker-entrypoint-initdb.d/001_schema.sql \
  || err "/docker-entrypoint-initdb.d/001_schema.sql not found in the container -- mount not wired"

# 2. All 6 tables exist.
for t in files file_actions parties audit_events users persons; do
  count=$(psql_c "SELECT count(*) FROM information_schema.tables WHERE table_name='$t';" | tr -d '[:space:]')
  [ "$count" = "1" ] || err "table '$t' does not exist"
done

# 3. Foreign keys from file_actions/parties/audit_events to files are present.
for t in file_actions parties audit_events; do
  count=$(psql_c "SELECT count(*) FROM information_schema.table_constraints WHERE table_name='$t' AND constraint_type='FOREIGN KEY';" | tr -d '[:space:]')
  [ "$count" -ge "1" ] 2>/dev/null || err "table '$t' has no foreign key constraint"
done

# 4. Foreign keys from file_actions are present.
for t in file_actions; do
  count=$(psql_c "SELECT count(*) FROM information_schema.table_constraints WHERE table_name='$t' AND constraint_type='FOREIGN KEY';" | tr -d '[:space:]')
  [ "$count" -ge "3" ] 2>/dev/null || err "table '$t' has no foreign key constraint"
done

# 5. Foreign keys from parties are present.
for t in parties; do
  count=$(psql_c "SELECT count(*) FROM information_schema.table_constraints WHERE table_name='$t' AND constraint_type='FOREIGN KEY';" | tr -d '[:space:]')
  [ "$count" -ge "1" ] 2>/dev/null || err "table '$t' has no foreign key constraint"
done

# 5. Foreign keys from users are present.
for t in users; do
  count=$(psql_c "SELECT count(*) FROM information_schema.table_constraints WHERE table_name='$t' AND constraint_type='FOREIGN KEY';" | tr -d '[:space:]')
  [ "$count" -ge "1" ] 2>/dev/null || err "table '$t' has no foreign key constraint"
done


# 4. Enum CHECK constraints only accept ALL CAPS values -- a lowercase insert
# on each enumerated column must be rejected *specifically by that column's
# CHECK constraint*, not by some other, unrelated failure (e.g. a bad
# file_id) that would incorrectly count as "rejected".
rejected_by_constraint() {
  sql="$1"
  constraint="$2"
  out=$(docker compose exec -T ods-postgres psql -U "$ODS_POSTGRES_USER" -d "$ODS_POSTGRES_DB" -c "$sql" 2>&1) && return 1
  printf '%s' "$out" | grep -q "$constraint"
}

# Wrapped in WITH...SELECT so psql's -t (tuples-only) suppresses the "INSERT
# 0 1" completion tag -- for a bare INSERT...RETURNING, -t does not suppress
# it, which silently corrupted file_id in an earlier version of this test.
file_id=$(psql_c "WITH ins AS (INSERT INTO files (file_number, status, opened_at, product_type) VALUES ('T-1', 'WIP', now(), 'REFINANCE') RETURNING file_id) SELECT file_id FROM ins;" | tr -d '[:space:]')
[ -n "$file_id" ] || err "setup insert for enum tests failed -- cannot test enum rejection without a valid file_id"

if [ -n "$file_id" ]; then
  rejected_by_constraint "INSERT INTO files (file_number, status, opened_at, product_type) VALUES ('T-bad', 'wip', now(), 'REFINANCE');" "files_status_check" \
    || err "files.status did not reject a lowercase value ('wip') via its CHECK constraint"

  rejected_by_constraint "INSERT INTO file_actions (file_id, action_code, action_type) VALUES ($file_id, 'signing', 'COMPLETE');" "file_actions_action_code_check" \
    || err "file_actions.action_code did not reject a lowercase value ('signing') via its CHECK constraint"

  rejected_by_constraint "INSERT INTO file_actions (file_id, action_code, action_type) VALUES ($file_id, 'SIGNING', 'complete');" "file_actions_action_type_check" \
    || err "file_actions.action_type did not reject a lowercase value ('complete') via its CHECK constraint"

  rejected_by_constraint "INSERT INTO parties (file_id, role) VALUES ($file_id, 'borrower');" "parties_role_check" \
    || err "parties.role did not reject a lowercase value ('borrower') via its CHECK constraint"
fi

# 5. Every column of every table has a non-empty comment.
for t in files file_actions parties audit_events users persons; do
  total=$(psql_c "SELECT count(*) FROM information_schema.columns WHERE table_name='$t';" | tr -d '[:space:]')
  commented=$(psql_c "
    SELECT count(*) FROM information_schema.columns c
    WHERE c.table_name='$t'
      AND col_description((quote_ident(c.table_name))::regclass::oid, c.ordinal_position) IS NOT NULL;
  " | tr -d '[:space:]')
  [ "$total" = "$commented" ] || err "table '$t' has $((total - commented)) column(s) missing a COMMENT ($commented/$total commented)"
done

if [ "$fail" -ne 0 ]; then
  printf '\nschema init check FAILED\n' >&2
  exit 1
fi
printf 'schema init check passed\n'

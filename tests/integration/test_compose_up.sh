#!/bin/sh
# M0.2 docker-compose bring-up smoke check.
# Asserts docker-compose.yml + .env at the repo root bring up the ODS Postgres
# service with no manual steps, and that .env values are actually wired in
# (not vestigial). Bring-up goes through scripts/compose_up.sh -- the same
# script `make up` uses -- so this test and the documented entrypoint share
# one source of truth for the retry/diagnostic behavior.
# See design/Milestones.md M0.2.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${ODS_POSTGRES_USER:=postgres}"

wait_ready_or_die() {
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
}

# 1. Bring up with default .env settings.
./scripts/compose_up.sh
wait_ready_or_die

# 2. Prove .env is wired in, not vestigial: override a value and confirm it takes effect.
./scripts/compose_down.sh >/dev/null 2>&1 || true
ODS_POSTGRES_DB=override_test_db ./scripts/compose_up.sh
wait_ready_or_die

found=$(docker compose exec -T ods-postgres psql -U "$ODS_POSTGRES_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='override_test_db';" 2>/dev/null | tr -d '[:space:]')
if [ "$found" != "1" ]; then
  printf "FAIL: expected database 'override_test_db' to exist from the .env override, but it does not\n" >&2
  exit 1
fi

printf 'docker compose bring-up check passed\n'

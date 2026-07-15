#!/bin/sh
# Bring the compose stack up with a friendly, actionable message on a port
# conflict -- Docker's own error ("port is already allocated") doesn't say
# where the port came from or how to change it. Shared by `make up` and
# tests/integration/test_compose_up.sh so both give the same diagnosis.
#
# `docker compose up -d` can exit 0 even when the host port failed to
# publish -- the container itself starts fine, but its network binding is
# silently empty. So success is judged by inspecting the actual port
# binding, not the command's exit code.
#
# Retries briefly before treating a bind failure as a genuine conflict:
# Docker doesn't always release a just-torn-down container's port instantly,
# so a bind failure right after `down` is often transient.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

: "${ODS_POSTGRES_PORT:=5432}"
: "${WAREHOUSE_POSTGRES_PORT:=5434}"

# Checks that <service>'s container port <container_port>/tcp actually bound
# to a host port. Reusable across services -- ods-postgres and
# warehouse-postgres (M2.4) are both plain single-port Postgres containers.
service_port_is_bound() {
  service=$1
  container_port=$2
  cid=$(docker compose ps -q "$service" 2>/dev/null) || return 1
  [ -n "$cid" ] || return 1
  bound=$(docker inspect "$cid" --format "{{json (index .NetworkSettings.Ports \"${container_port}/tcp\")}}" 2>/dev/null) || return 1
  [ "$bound" != "[]" ] && [ "$bound" != "null" ] && [ -n "$bound" ]
}

# Reports a diagnosis per unbound service, based on binding state captured
# *before* any teardown -- after `docker compose down -v`, every service
# reports unbound regardless of which one actually conflicted, so that
# state must never be checked post-teardown.
port_conflict_diagnosis() {
  ods_ok=$1
  wh_ok=$2
  if [ "$ods_ok" -ne 1 ]; then
    printf 'FAIL: port %s (ODS_POSTGRES_PORT) is already in use on this machine.\n' "$ODS_POSTGRES_PORT" >&2
    printf 'Edit .env and change ODS_POSTGRES_PORT to a free port, then run this again.\n' >&2
  fi
  if [ "$wh_ok" -ne 1 ]; then
    printf 'FAIL: port %s (WAREHOUSE_POSTGRES_PORT) is already in use on this machine.\n' "$WAREHOUSE_POSTGRES_PORT" >&2
    printf 'Edit .env and change WAREHOUSE_POSTGRES_PORT to a free port, then run this again.\n' >&2
  fi
}

attempt=1
while [ "$attempt" -le 5 ]; do
  up_output=$(docker compose up -d 2>&1) || true

  ods_ok=0
  wh_ok=0
  service_port_is_bound ods-postgres 5432 && ods_ok=1
  service_port_is_bound warehouse-postgres 5432 && wh_ok=1

  if [ "$ods_ok" -eq 1 ] && [ "$wh_ok" -eq 1 ]; then
    printf '%s\n' "$up_output"
    exit 0
  fi

  # Either `up -d` reported a raw allocation error, or it exited 0 but a
  # port never actually bound -- same failure mode either way. Tear down
  # and retry before treating as terminal (a bind failure right after a
  # just-completed `down` is often transient, not a real conflict).
  docker compose down -v >/dev/null 2>&1 || true
  if [ "$attempt" -lt 5 ]; then sleep 1; attempt=$((attempt + 1)); continue; fi
  port_conflict_diagnosis "$ods_ok" "$wh_ok"
  exit 1
done

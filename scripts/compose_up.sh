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

port_is_bound() {
  cid=$(docker compose ps -q ods-postgres 2>/dev/null) || return 1
  [ -n "$cid" ] || return 1
  bound=$(docker inspect "$cid" --format '{{json (index .NetworkSettings.Ports "5432/tcp")}}' 2>/dev/null) || return 1
  [ "$bound" != "[]" ] && [ "$bound" != "null" ] && [ -n "$bound" ]
}

port_conflict_diagnosis() {
  printf 'FAIL: port %s (ODS_POSTGRES_PORT) is already in use on this machine.\n' "$ODS_POSTGRES_PORT" >&2
  printf 'Edit .env and change ODS_POSTGRES_PORT to a free port, then run this again.\n' >&2
}

attempt=1
while [ "$attempt" -le 5 ]; do
  up_output=$(docker compose up -d 2>&1) || true

  if printf '%s' "$up_output" | grep -qi "port is already allocated\|address already in use"; then
    docker compose down -v >/dev/null 2>&1 || true
    if [ "$attempt" -lt 5 ]; then sleep 1; attempt=$((attempt + 1)); continue; fi
    port_conflict_diagnosis
    exit 1
  fi

  if port_is_bound; then
    printf '%s\n' "$up_output"
    exit 0
  fi

  # up -d exited 0 but the port never actually bound -- same failure mode,
  # surfaced differently. Tear down and retry before treating as terminal.
  docker compose down -v >/dev/null 2>&1 || true
  if [ "$attempt" -lt 5 ]; then sleep 1; attempt=$((attempt + 1)); continue; fi
  port_conflict_diagnosis
  exit 1
done

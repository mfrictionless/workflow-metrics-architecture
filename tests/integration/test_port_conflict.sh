#!/bin/sh
# Regression test for a real bug found manually testing M0.2: `docker compose
# up -d` can exit 0 even when the host port failed to publish (the container
# starts, but its network binding is silently empty). scripts/compose_up.sh
# must detect this via the actual port binding, not the command's exit code,
# and fail with a message pointing at the specific env var whose port
# actually conflicted.
#
# Uses a real, independently-running container to occupy the port -- not
# just another `docker compose up`, since that was the scenario that
# originally produced a false-positive green.
#
# Also regression-tests a second bug found while adding warehouse-postgres
# (M2.4): diagnosing which port conflicted by checking binding state *after*
# the retry loop's teardown is wrong, since `docker compose down -v` leaves
# every service unbound regardless of which one actually conflicted --
# producing a false "both ports conflicted" message for a single-port
# conflict. Fixed by capturing binding state before teardown; pinned here by
# asserting the *other* service's env var is NOT named in the output.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

FIXTURE_PORT=15432
FIXTURE_NAME=port-conflict-fixture-$$

cleanup() {
  docker rm -f "$FIXTURE_NAME" >/dev/null 2>&1 || true
  docker compose down -v >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_fixture_running_or_die() {
  i=0
  running=0
  while [ "$i" -lt 15 ]; do
    status=$(docker inspect "$FIXTURE_NAME" --format '{{.State.Status}}' 2>/dev/null || echo "")
    if [ "$status" = "running" ]; then
      running=1
      break
    fi
    i=$((i + 1))
    sleep 1
  done
  if [ "$running" -ne 1 ]; then
    printf 'FAIL: fixture container never reached running state (test setup broken, not the thing under test)\n' >&2
    exit 1
  fi
}

docker run -d --name "$FIXTURE_NAME" -e POSTGRES_PASSWORD=x -p "$FIXTURE_PORT:5432" postgres:16-alpine >/dev/null 2>&1
wait_fixture_running_or_die

output=$(ODS_POSTGRES_PORT=$FIXTURE_PORT ./scripts/compose_up.sh 2>&1) && rc=0 || rc=$?

if [ "$rc" -eq 0 ]; then
  printf 'FAIL: compose_up.sh reported success while the port was genuinely occupied\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if ! printf '%s' "$output" | grep -q "ODS_POSTGRES_PORT"; then
  printf 'FAIL: compose_up.sh failed but did not point at ODS_POSTGRES_PORT in its message\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if printf '%s' "$output" | grep -q "WAREHOUSE_POSTGRES_PORT"; then
  printf 'FAIL: compose_up.sh named WAREHOUSE_POSTGRES_PORT for an ODS-only port conflict\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

docker rm -f "$FIXTURE_NAME" >/dev/null 2>&1 || true
docker compose down -v >/dev/null 2>&1 || true

# Same check, other direction: only the warehouse port conflicts.
docker run -d --name "$FIXTURE_NAME" -e POSTGRES_PASSWORD=x -p "$FIXTURE_PORT:5432" postgres:16-alpine >/dev/null 2>&1
wait_fixture_running_or_die

output=$(WAREHOUSE_POSTGRES_PORT=$FIXTURE_PORT ./scripts/compose_up.sh 2>&1) && rc=0 || rc=$?

if [ "$rc" -eq 0 ]; then
  printf 'FAIL: compose_up.sh reported success while the warehouse port was genuinely occupied\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if ! printf '%s' "$output" | grep -q "WAREHOUSE_POSTGRES_PORT"; then
  printf 'FAIL: compose_up.sh failed but did not point at WAREHOUSE_POSTGRES_PORT in its message\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if printf '%s' "$output" | grep -q "ODS_POSTGRES_PORT"; then
  printf 'FAIL: compose_up.sh named ODS_POSTGRES_PORT for a warehouse-only port conflict\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

printf 'port conflict regression check passed\n'

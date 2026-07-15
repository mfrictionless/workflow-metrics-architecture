#!/bin/sh
# M2.3 regression check: the Debezium Postgres source connector, registered
# against the Kafka Connect worker, captures ODS writes and publishes them
# as JSON messages on their per-table topics -- consuming the existing
# dbz_slot/dbz_publication from M2.1, not creating its own. See
# design/Milestones.md M2.3.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT"

cleanup() { ./scripts/compose_down.sh >/dev/null 2>&1 || true; }
trap cleanup EXIT

: "${CONNECT_REST_PORT:=8083}"
BASE_URL="http://localhost:${CONNECT_REST_PORT}"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

./scripts/compose_up.sh >/dev/null

# 1. Wait for the Connect REST API to accept connections.
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

# 2. Register the connector and wait for RUNNING status.
./scripts/register_connector.sh >/dev/null

running=0
i=0
while [ "$i" -lt 30 ]; do
  status_json=$(curl -s "${BASE_URL}/connectors/ods-source/status" 2>/dev/null || true)
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
  err "connector/task did not both reach RUNNING within 30s (connector: ${state:-unknown}, task: ${task_state:-unknown})"
fi

# 3. Insert a seed row and confirm it lands on the files topic.
./scripts/seed.sh >/dev/null

message=""
i=0
while [ "$i" -lt 30 ]; do
  message=$(docker compose exec -T kafka /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 --topic ods.public.files \
    --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null) || true
  [ -n "$message" ] && break
  i=$((i + 1))
  sleep 1
done

if [ -z "$message" ]; then
  err "no message consumed from ods.public.files within 30s"
else
  after=$(printf '%s' "$message" | jq -r '.payload.after.file_number' 2>/dev/null || true)
  before=$(printf '%s' "$message" | jq -r '.payload.before' 2>/dev/null || true)
  [ -n "$after" ] && [ "$after" != "null" ] || err "expected non-null payload.after.file_number, got: $message"
  [ "$before" = "null" ] || err "expected null payload.before for an insert, got: $before"
fi

if [ "$fail" -ne 0 ]; then
  printf '\ndebezium connector check FAILED\n' >&2
  exit 1
fi
printf 'debezium connector check passed\n'

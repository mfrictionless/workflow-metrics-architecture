#!/bin/sh
# Registers every connector config in cdc/*.json against the Kafka Connect
# worker's REST API (host-published via CONNECT_REST_PORT). Idempotent per
# connector: if a connector by a given name already exists, updates its
# config in place (PUT) instead of erroring or duplicating. See
# design/Milestones.md M2.3 (source) and M2.5 (sink).
#
# After registering, polls /status until both connector.state and
# tasks[0].state report RUNNING and prints the result -- registration
# succeeding only means the config was accepted, not that the connector is
# actually pulling data yet. connector.state can read RUNNING a moment
# before tasks[0].state does (a race found in M2.3 testing), so both must be
# checked together: this is what tells you whether to expect data in the
# warehouse after a seed or simulate run.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

: "${CONNECT_REST_PORT:=8083}"

BASE_URL="http://localhost:${CONNECT_REST_PORT}"

for CONFIG_FILE in cdc/*.json; do
  CONNECTOR_NAME=$(jq -r '.name' "$CONFIG_FILE")

  status=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/connectors/${CONNECTOR_NAME}")

  if [ "$status" = "200" ]; then
    jq '.config' "$CONFIG_FILE" | curl -s -X PUT -H "Content-Type: application/json" \
      "${BASE_URL}/connectors/${CONNECTOR_NAME}/config" -d @- >/dev/null
  else
    curl -s -X POST -H "Content-Type: application/json" \
      "${BASE_URL}/connectors" -d @"$CONFIG_FILE" >/dev/null
  fi

  printf 'connector "%s" registered, waiting for RUNNING...\n' "$CONNECTOR_NAME"

  connector_state="UNKNOWN"
  task_state="UNKNOWN"
  i=0
  while [ "$i" -lt 30 ]; do
    connector_status=$(curl -s "${BASE_URL}/connectors/${CONNECTOR_NAME}/status" 2>/dev/null || true)
    connector_state=$(printf '%s' "$connector_status" | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    task_state=$(printf '%s' "$connector_status" | jq -r '.tasks[0].state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    [ "$connector_state" = "RUNNING" ] && [ "$task_state" = "RUNNING" ] && break
    i=$((i + 1))
    sleep 1
  done

  printf 'connector "%s": %s (task: %s)\n' "$CONNECTOR_NAME" "$connector_state" "$task_state"
  if [ "$connector_state" != "RUNNING" ] || [ "$task_state" != "RUNNING" ]; then
    printf 'WARNING: "%s" did not reach RUNNING/RUNNING within 30s -- data will not flow until it does\n' "$CONNECTOR_NAME" >&2
  fi
done

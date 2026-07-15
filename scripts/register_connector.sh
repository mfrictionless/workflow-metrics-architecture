#!/bin/sh
# Registers every connector config in cdc/*.json against the Kafka Connect
# worker's REST API (host-published via CONNECT_REST_PORT). Idempotent per
# connector: if a connector by a given name already exists, updates its
# config in place (PUT) instead of erroring or duplicating. See
# design/Milestones.md M2.3 (source) and M2.5 (sink).
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

  printf 'connector "%s" registered\n' "$CONNECTOR_NAME"
done

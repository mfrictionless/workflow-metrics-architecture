#!/bin/sh
# Registers cdc/debezium-postgres-source.json against the Kafka Connect
# worker's REST API (host-published via CONNECT_REST_PORT). Idempotent: if a
# connector by this name already exists, updates its config in place (PUT)
# instead of erroring or duplicating. database.hostname/user/password in the
# connector config mirror the ODS service name and .env's default
# credentials -- same simplification already used by scripts/seed.sh, not
# wired to .env directly. See design/Milestones.md M2.3.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

: "${CONNECT_REST_PORT:=8083}"

CONFIG_FILE=cdc/debezium-postgres-source.json
CONNECTOR_NAME=$(jq -r '.name' "$CONFIG_FILE")
BASE_URL="http://localhost:${CONNECT_REST_PORT}"

status=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/connectors/${CONNECTOR_NAME}")

if [ "$status" = "200" ]; then
  jq '.config' "$CONFIG_FILE" | curl -s -X PUT -H "Content-Type: application/json" \
    "${BASE_URL}/connectors/${CONNECTOR_NAME}/config" -d @- >/dev/null
else
  curl -s -X POST -H "Content-Type: application/json" \
    "${BASE_URL}/connectors" -d @"$CONFIG_FILE" >/dev/null
fi

printf 'connector "%s" registered\n' "$CONNECTOR_NAME"

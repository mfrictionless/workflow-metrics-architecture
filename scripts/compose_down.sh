#!/bin/sh
# Tear down the compose stack and remove its volumes.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

docker compose down -v

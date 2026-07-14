#!/bin/sh
# M0.3 fast check: docker-compose.yml + .env parse and render without
# starting any containers.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

if ! docker compose config >/dev/null 2>&1; then
  printf 'FAIL: docker compose config failed to validate docker-compose.yml / .env\n' >&2
  exit 1
fi
printf 'docker compose config check passed\n'

#!/bin/sh
# Runs the simulator, creating COUNT new files (default from .env's
# SIMULATOR_FILE_COUNT). `docker compose run` targets the named service
# directly, which works despite its `profiles: ["tools"]` gate that keeps it
# out of a bare `docker compose up`. See design/Milestones.md M1.3.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

docker compose run --rm --build simulator

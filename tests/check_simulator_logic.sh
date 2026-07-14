#!/bin/sh
# M1.3 fast check: the simulator's pure row-generation logic (workflow.py),
# unit-tested with stdlib unittest -- no psycopg2, no Docker, no pip install.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT/simulator"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'FAIL: python3 not found on host\n' >&2
  exit 1
fi

if ! PYTHONPATH=. python3 -m unittest discover -s tests -p "test_*.py" -v; then
  printf 'FAIL: simulator workflow unit tests failed\n' >&2
  exit 1
fi
printf 'simulator logic check passed\n'

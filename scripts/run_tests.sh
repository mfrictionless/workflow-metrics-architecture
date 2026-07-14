#!/bin/sh
# M0.3 single-command test runner. Discovers and runs test scripts by tier:
# fast tier is any tests/*.sh (no external infrastructure); integration tier
# is any tests/integration/*.sh (needs Docker). Fail-fast: stops at the first
# failing script and names it, rather than aggregating every failure --
# revisit if the suite grows large enough that full-failure visibility per
# run outweighs the speed of stopping early (see design/Milestones.md M0.3).
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

tier="${1:-all}"

run_tier() {
  dir="$1"
  label="$2"
  for f in "$dir"/*.sh; do
    [ -e "$f" ] || continue
    printf '==> [%s] %s\n' "$label" "$f"
    if ! sh "$f"; then
      printf 'FAIL: %s\n' "$f" >&2
      exit 1
    fi
  done
}

case "$tier" in
  fast)
    run_tier tests fast
    ;;
  integration)
    run_tier tests/integration integration
    ;;
  all)
    run_tier tests fast
    run_tier tests/integration integration
    ;;
  *)
    printf 'usage: %s [fast|integration|all]\n' "$0" >&2
    exit 2
    ;;
esac

printf 'All tests passed\n'

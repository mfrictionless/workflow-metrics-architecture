#!/bin/sh
# M0.3 regression check: the single-command test runner (`make test-fast`)
# must fail fast -- stop at the first failing script, name it, and not run
# subsequent tests. Guards against a "false green" bug in the runner itself,
# mirroring the lesson from M0.2 (D002). Needs no external infrastructure,
# so this lives in the fast tier; named to sort after the other fast tests
# so it doesn't disturb their run order at the top level.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

# Sorts before check_compose_config.sh / check_structure.sh so the nested
# run below hits it first.
FIXTURE="tests/aaa_broken_fixture.sh"

cleanup() { rm -f "$FIXTURE"; }
trap cleanup EXIT

cat > "$FIXTURE" <<'EOF'
#!/bin/sh
echo "FAIL: intentional broken fixture for regression test" >&2
exit 1
EOF
chmod +x "$FIXTURE"

output=$(make test-fast 2>&1) && rc=0 || rc=$?

if [ "$rc" -eq 0 ]; then
  printf 'FAIL: make test-fast reported success with a deliberately broken fixture present\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if ! printf '%s' "$output" | grep -q "$FIXTURE"; then
  printf 'FAIL: make test-fast did not name the broken fixture in its output\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

if printf '%s' "$output" | grep -q "Repository structure check passed"; then
  printf 'FAIL: make test-fast ran check_structure.sh after the fixture failed -- fail-fast is not stopping the run\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

printf 'test runner fail-fast regression check passed\n'

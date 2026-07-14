#!/bin/sh
# M0.1 repository structure smoke check.
# Asserts the monorepo layout matches the living map in
# design/Technical-Design.md §9 (Repository layout). See design/Milestones.md M0.1.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
LAYOUT="$ROOT/design/Technical-Design.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

# Folders that exist today. Each milestone appends its own folder as it is created.
EXISTING="ods"

# Every component folder the layout map must document.
DOCUMENTED="ods simulator streaming cdc warehouse orchestration consumers"

# 1. The layout section exists.
grep -q "Repository layout" "$LAYOUT" || err "Technical-Design.md has no 'Repository layout' section"

# 2. Folders marked as existing are present on disk.
for d in $EXISTING; do
  [ -d "$ROOT/$d" ] || err "folder '$d/' is marked existing but is missing on disk"
done

# 3. ODS source DDL is where the map says it lives.
[ -f "$ROOT/ods/ddl/schema.sql" ] || err "ods/ddl/schema.sql not found"

# 4. Every planned component folder is documented in the layout map.
for name in $DOCUMENTED; do
  grep -qF "$name/" "$LAYOUT" || err "layout map does not document '$name/'"
done

if [ "$fail" -ne 0 ]; then
  printf '\nRepository structure check FAILED\n' >&2
  exit 1
fi
printf 'Repository structure check passed\n'

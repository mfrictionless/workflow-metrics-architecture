#!/bin/sh
# Applies ods/seed/seed.sql against the running ODS. Explicit and separate
# from schema init (ods/ddl/, auto-run by Postgres) so seed data never mixes
# with simulator-generated data. See design/Milestones.md M1.2.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

: "${ODS_POSTGRES_USER:=postgres}"
: "${ODS_POSTGRES_DB:=ods}"

docker compose exec -T ods-postgres psql -U "$ODS_POSTGRES_USER" -d "$ODS_POSTGRES_DB" -v ON_ERROR_STOP=1 < ods/seed/seed.sql
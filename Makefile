# .env's KEY=VALUE lines double as Make variables (e.g. SIMULATOR_FILE_COUNT),
# so its defaults are available here without duplicating them.
include .env

# A command-line override (make simulate COUNT=1000) always wins over this
# default -- Make applies COUNT ?= only when COUNT wasn't already set.
COUNT ?= $(SIMULATOR_FILE_COUNT)

.PHONY: up down seed simulate register-connector dbt-debug dbt-run test test-fast test-integration lint lint-shell lint-sql lint-py

# Bring the compose stack up. Fails with an actionable message (pointing at
# .env) on a port conflict, rather than Docker's raw daemon error.
up:
	@./scripts/compose_up.sh

# Tear the compose stack down and remove its volumes.
down:
	@./scripts/compose_down.sh

# Apply ods/seed/seed.sql against the running ODS. Explicit and separate from
# schema init, so seed data never mixes with simulator-generated data.
seed:
	@./scripts/seed.sh

# Create COUNT new files (default from .env's SIMULATOR_FILE_COUNT).
# Override per-run: make simulate COUNT=1000
simulate:
	@COUNT=$(COUNT) ./scripts/simulate.sh

# Register (or update) every connector in cdc/*.json -- the Debezium
# Postgres source (M2.3) and JDBC sink (M2.5) -- against the running Kafka
# Connect worker's REST API. Explicit and separate from `up`, same reasoning
# as `make seed`: registering a connector is a one-off action against an
# already-running worker, not part of bringing the stack up.
register-connector:
	@./scripts/register_connector.sh

# dbt Core against the warehouse (Raw -> staging -> intermediate -> marts, M3+). All
# are one-off actions against an already-running warehouse-postgres, same
# reasoning as `make seed` -- not part of bringing the stack up.
dbt-debug:
	@docker compose run --rm dbt debug

dbt-run:
	@docker compose run --rm dbt run

dbt-build:
	@docker compose run --rm dbt build

# Run every test in the repo: fast tier, then integration tier. Fail-fast --
# stops at the first failing script.
test:
	@./scripts/run_tests.sh all

# Run only the fast tier (no external infrastructure) -- the inner dev loop.
test-fast:
	@./scripts/run_tests.sh fast

# Run only the integration tier (needs Docker).
test-integration:
	@./scripts/run_tests.sh integration

# Lint shell scripts for correctness and common mistakes.
lint-shell:
	@echo "=== Shell Script Linting ===" && \
	shellcheck ./scripts/*.sh ./tests/*.sh ./tests/integration/*.sh

# Lint SQL files for style and potential issues.
lint-sql:
	@echo "=== SQL Linting ===" && \
	sqlfluff lint ./ods/ddl/ ./warehouse/ddl/ ./warehouse/dbt/models/ ./warehouse/dbt/macros/

# Lint and format-check Python (simulator) via the pinned Ruff image.
lint-py:
	@echo "=== Python Linting ===" && \
	docker run --rm -v "$$PWD:/io" -w /io ghcr.io/astral-sh/ruff:0.16.0 check ./simulator/ && \
	docker run --rm -v "$$PWD:/io" -w /io ghcr.io/astral-sh/ruff:0.16.0 format --check ./simulator/

# Run every language's linter. Each stage runs even if an earlier one fails, so
# one language's issues never hide another's; exits non-zero if any failed.
lint:
	@rc=0; \
	$(MAKE) --no-print-directory lint-shell || rc=1; \
	echo ""; \
	$(MAKE) --no-print-directory lint-sql || rc=1; \
	echo ""; \
	$(MAKE) --no-print-directory lint-py || rc=1; \
	echo ""; \
	if [ "$$rc" -ne 0 ]; then echo "=== lint FAILED ==="; else echo "=== lint passed ==="; fi; \
	exit $$rc

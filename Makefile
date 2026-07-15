# .env's KEY=VALUE lines double as Make variables (e.g. SIMULATOR_FILE_COUNT),
# so its defaults are available here without duplicating them.
include .env

# A command-line override (make simulate COUNT=1000) always wins over this
# default -- Make applies COUNT ?= only when COUNT wasn't already set.
COUNT ?= $(SIMULATOR_FILE_COUNT)

.PHONY: up down seed simulate register-connector test test-fast test-integration

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

.PHONY: up down seed test test-fast test-integration

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

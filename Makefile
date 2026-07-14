.PHONY: up down

# Bring the compose stack up. Fails with an actionable message (pointing at
# .env) on a port conflict, rather than Docker's raw daemon error.
up:
	@./scripts/compose_up.sh

# Tear the compose stack down and remove its volumes.
down:
	@./scripts/compose_down.sh

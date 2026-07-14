# Decision Log

Append-only record of *why* each Change happened. Numbered D001, D002, D003, … — newest at the bottom. See [`Process.md`](Process.md) for the workflow and the field definitions.

**Entry template:**
```markdown
## D0NN — <title> (YYYY-MM-DD)

**Change:** `change/<branch>`

**Motivation:** why (1–2 sentences).

**Design delta:** which docs changed (or "none").

**Artifacts:** DDL / SQL / diagram produced (or "none").

**Reversal:** what we'd change if the assumption breaks / how to undo.

**Validation:** rationale + the alternative you rejected — or — N/A: descriptive-only (reason). Note what you'd confirm with app eng / security / SRE.
```

---

<!-- Entries below, newest at the bottom. -->

## D001 — Monorepo repository layout (2026-07-14)

**Change:** `change/m0.1-repo-structure`

**Motivation.** M0.1 needs a documented, testable repository structure so a contributor can locate any component by folder name alone, and so the pipeline stays reproducible from one checkout (NFR-4).

**Design delta:** `design/Technical-Design.md` — new §9 "Repository layout," a living folder-per-component map with a Status column and the lazy-creation / test-co-location conventions. `design/Milestones.md` — M0.1 expanded to the full template and pointed at §9. `README.md` — one-line pointer to §9.

**Artifacts:** `tests/check_structure.sh` — a zero-dependency structure smoke check asserting the §9 map documents every component, existing folders are present, and the ODS DDL is where the map says.

**Reversal:** if the folder taxonomy proves wrong, rename/regroup in §9 and update the check's `DOCUMENTED` list; lazy creation keeps folders near-empty until their milestone, so rework is cheap.

**Validation:** choices and rejected alternatives —
- **`streaming/` split from `cdc/`** — Kafka broker + Connect worker (infrastructure) separated from the Debezium/JDBC connector configs (capture/landing). Rejected lumping both under one `cdc/` folder.
- **Layout map in Technical-Design §9, not README or Milestones.** Rejected the README (an index, not a design record) and Milestones (about testable units, not standing structure) as homes; §9 sits next to the §2 component registry it derives from and is updated as we build.
- **Test co-location + a root `tests/` for cross-cutting tests.** Rejected a pure top-level `tests/` because dbt tests must live inside the dbt project by convention, so full centralization is impossible.
- **Smoke check, not red-green test-first** — repository structure is infrastructure with no business logic to drive, per [Process.md](Process.md); the check was still observed failing for the right reason before §9 was written.

## D002 — Committed .env with local defaults; retry-aware compose bring-up (2026-07-14)

**Change:** `change/m0.2-docker-compose`

**Motivation.** M0.2 needs `docker compose up` to work from a clean checkout with zero manual setup (NFR-4), while still letting a user avoid port/credential collisions with something already running on their machine — without editing `docker-compose.yml` itself.

**Design delta:** none (`docker-compose.yml` and `.env` are artifacts, not design docs). `design/Milestones.md` — M0.2 expanded to the full template.

**Artifacts:** `docker-compose.yml` — the ODS Postgres service, all settings sourced from `.env` via `${VAR}` interpolation. `.env` — committed (not `.env.example`) with local-dev defaults (`ODS_POSTGRES_PORT=5432`, `ODS_POSTGRES_DB=ods`, etc.), commented as not for production use. `scripts/compose_up.sh` / `scripts/compose_down.sh` — shared bring-up/tear-down logic with port-conflict detection and diagnosis. `Makefile` (`up`, `down`) — the documented single-command entrypoints. `tests/integration/test_compose_up.sh` — bring-up smoke check. `tests/integration/test_port_conflict.sh` — regression test for the bug below.

**Reversal:** if committing `.env` proves wrong (e.g. real secrets end up in it later), switch to `.env.example` + a documented copy step, accepting the one-manual-step cost to NFR-4.

**Validation:** choices and rejected alternatives —
- **Committed `.env` with real defaults, not `.env.example`.** A `.env.example` requiring a manual `cp` step before first run would violate NFR-4's "one documented command." Safe here because the values are local-dev-only (no real secrets); revisit if that changes.
- **Host port kept at 5432**, not remapped to avoid collision — owner's explicit call, accepting that a user with a local Postgres already on 5432 edits `.env` rather than the port being pre-avoided.
- **`ODS_` prefix on every `.env` var**, not bare names (`POSTGRES_PORT`) — anticipates `WAREHOUSE_POSTGRES_*` and similar in the same file as later milestones add services, without a collision.
- **Bounded retry (5x, 1s apart) on a port-bind error during bring-up**, rather than failing on the first occurrence. Discovered empirically: `docker compose down -v` immediately followed by `up` can hit a transient "port already allocated" error because Docker hasn't released the port yet — not a real conflict. Only a bind error that persists past the retry budget is treated as terminal and reported with a message pointing at `ODS_POSTGRES_PORT` in `.env`.
- **Catalog check (`pg_database`), not `current_database()`, to verify the `.env` override took effect.** `psql` without `-d` connects to a database named after the user, not `POSTGRES_DB` — an early version of the test silently asserted against the wrong database. Querying `pg_database` for the overridden name directly avoids relying on the client's default-database behavior.
- **`make up` / `make down`, not bare `docker compose` commands, as the documented entrypoint.** Docker's own port-bind error is a daemon-level message with no reference to `.env` or which setting to change, and can't be customized from `docker-compose.yml` itself; a thin wrapper is the only way to make the *actual* user-facing command give an actionable message. Rejected a standalone shell script (`scripts/up.sh`) as the primary interface — `make` is the more conventional, discoverable entrypoint, and this sets the pattern M0.3 extends with a `test` target.
- **Port-conflict detection by inspecting the actual network binding, not the `up -d` exit code.** Manual testing surfaced a real bug: `docker compose up -d` can exit 0 even when the host port failed to publish — the container starts, but `NetworkSettings.Ports` for that port is silently `[]`. The original implementation only grepped `up -d`'s captured output for "port is already allocated," which is absent in this failure mode, producing a false-positive green in exactly the scenario a real user hit. Fixed by checking `docker inspect`'s `NetworkSettings.Ports` for a non-empty binding after `up -d` returns, regardless of its exit code, and treating an empty binding the same as an explicit bind error. `tests/integration/test_port_conflict.sh` pins this behavior against a real, independently-running occupant container (not another `docker compose up`, since that was the case that produced the false positive).
- **Shared `scripts/compose_up.sh` / `compose_down.sh`, called by both `make up` and the integration test**, rather than duplicating the retry/detection logic in each. One place owns "how do we know the port bound successfully."

## D003 — Fail-fast test runner discovered by directory convention (2026-07-14)

**Change:** `change/m0.3-test-runner`

**Motivation.** M0.3 needs one documented command (NFR-4) that runs every test in the repo, so future milestones (dbt tests, simulator tests, API tests) don't each need their own bespoke invocation instructions.

**Design delta:** `design/Milestones.md` — M0.3 expanded to the full template.

**Artifacts:** `scripts/run_tests.sh` — discovers and runs `tests/*.sh` (fast tier) then `tests/integration/*.sh` (integration tier), fail-fast. `Makefile` — `test`, `test-fast`, `test-integration` targets. `tests/check_compose_config.sh` — the `docker compose config` check, now a discoverable script rather than an ad-hoc command. `tests/verify_test_runner_fail_fast.sh` — regression test on the runner itself.

**Reversal:** if a future test type (pytest, `dbt test`) doesn't fit the shell-script-glob convention, extend `run_tests.sh` with a second discovery mechanism per tier rather than forcing every tool into a `.sh` wrapper.

**Validation:** choices and rejected alternatives —
- **Fail-fast, not aggregate-all-failures** — owner's explicit call for this milestone. Stops at the first failing script and skips the rest, trading full-failure visibility for a faster feedback loop. Recorded in Milestones M0.3 as a deliberate, revisitable trade-off rather than a permanent design.
- **Discovery by directory convention (`tests/*.sh` vs `tests/integration/*.sh`), not an explicit registry file.** A new fast test is picked up automatically by being added to `tests/`; no separate list to keep in sync. Rejected an explicit manifest as unnecessary ceremony at this scale.
- **`check_compose_config.sh` promoted from an ad-hoc command to a real script** — anything not in a discoverable script doesn't actually get run by `make test`, so it would silently stop being checked. This was found while building M0.3 itself: the fast tier is only as complete as what's actually a file in `tests/`.
- **A meta-test on the runner's own fail-fast behavior**, not just trusting the implementation — directly modeled on the false-positive lesson from D002 (M0.2's port detection): an infra check that "looks done" can still be silently wrong, so the fail-fast guarantee itself is pinned by a regression test, not just manual verification.

## D004 — ODS schema mounted into Postgres auto-init; enum rejection verified by constraint name (2026-07-14)

**Change:** `change/m1.1-schema-init`

**Motivation.** M1.1 needs `make up` to bring up an ODS with the correct schema fully applied — tables, FKs, ALL CAPS enum constraints, per-column comments — with no manual `psql -f` step, closing the gap between the schema built in isolation (earlier M1.1 work, before M0 existed) and the compose-based workflow M0 established.

**Design delta:** none (`docker-compose.yml` is an artifact). `design/Milestones.md` M1.1 already specified this shape from the draft stage.

**Artifacts:** `docker-compose.yml` — mounts `./ods/ddl:/docker-entrypoint-initdb.d:ro` on the `ods-postgres` service, using Postgres's official image's auto-init mechanism. `tests/integration/test_schema_init.sh` — verifies the mount, all 4 tables, FKs, ALL CAPS enum enforcement (by constraint name, not just "any failure"), and full column-comment coverage.

**Reversal:** if a second DDL file is ever needed, alphabetical execution order in `/docker-entrypoint-initdb.d/` determines sequence — name files accordingly (`001_...`, `002_...`) rather than relying on directory listing order.

**Validation:** choices and rejected alternatives —
- **Read-only mount (`:ro`)** — the container only ever needs to read `schema.sql`; nothing it does should write back to the source tree.
- **Enum-rejection assertions verify the specific CHECK constraint name in the error output, not just "the insert failed."** An earlier version of the test used "did the command fail" as the sole signal — but a failure for an *unrelated* reason (e.g. a bad `file_id`) would count as a false pass, hiding a real constraint regression. Found in this very milestone: a bug in the test's own setup (below) caused exactly that kind of unrelated failure, and the looser check would have masked it.
- **`psql -t` (tuples-only) does not suppress the `INSERT 0 1` completion tag for `INSERT...RETURNING`.** A test helper did `file_id=$(psql -t -c "INSERT ... RETURNING file_id")`, and the captured value silently became `"1INSERT01"` (the row value concatenated with the command tag) after whitespace-stripping — corrupting every downstream query that used `$file_id` for unrelated reasons, not an enum-constraint failure. Fixed by wrapping the insert in `WITH ins AS (INSERT ... RETURNING file_id) SELECT file_id FROM ins;`, which psql treats as a pure `SELECT` and `-t` suppresses correctly. Caught by the stricter constraint-name check above, not by inspection — another instance of the D002/D003 pattern: an assertion needs to verify the *right* thing failed, not just *that* something failed.

## D005 — Seed data as an explicit `make seed`, not auto-init (2026-07-14)

**Change:** `change/m1.2-seed-data`

**Motivation.** M1.2 needs one closed example file (Apply → Process → Sign → Record and close) for early testing and manual inspection. The owner's explicit call: keep it out of Postgres's auto-init mechanism, so later milestones' simulator-generated data (M1.3+) never gets silently mixed in with this fixed example on every `make up`.

**Design delta:** `design/Milestones.md` M1.2 expanded to the full template. `design/Technical-Design.md` §9 — `ods/` description updated to note it now holds seed data too.

**Artifacts:** `ods/seed/seed.sql` — the seed data, deliberately outside `ods/ddl/` so it is not picked up by `/docker-entrypoint-initdb.d/`. `scripts/seed.sh` — pipes `seed.sql` into `psql` against the running ODS via `docker compose exec`. `Makefile` `seed` target. `tests/integration/test_seed_data.sh` — asserts `make up` alone yields 0 files, then validates the full seeded row set after `make seed`.

**Reversal:** if keeping seed data separate becomes more friction than it's worth (e.g. every test setup needs an extra `make seed` call), reconsider folding it into `ods/ddl/` as a numbered init file — but only once the simulator (M1.3) exists and the mixing concern can be evaluated against real behavior rather than speculatively.

**Validation:** choices and rejected alternatives —
- **Separate `ods/seed/` + explicit `make seed`, not `ods/ddl/` auto-init.** Rejected auto-loading via the same mount as `schema.sql` (my original draft) — the owner's reasoning: once the simulator (M1.3) is generating its own rows, a fixed seed file auto-inserted on every fresh volume would sit indistinguishably alongside generated data, making it harder to reason about which rows are the "known good" fixture versus simulated noise.
- **No idempotency guard on repeated `make seed` calls.** It's a deliberate, user-invoked, additive action (confirmed empirically: running it twice produces 2 files) — not automatically run, so accidental double-seeding requires a deliberate second invocation. Revisit only if this becomes a real friction point.
- **Single `\gset`-captured timestamp (`base_ts`), reused for both `files.closed_at` and the terminal step's `received_at`.** Learned from D004: relying on two separate `now()` calls to match would be fragile (each statement's implicit transaction can get a different timestamp). Capturing one value up front and reusing it makes the equality exact by construction, not by coincidence.

## D006 — Python simulator: configurable count, pure-logic/DB split, Docker Compose profile (2026-07-14)

**Change:** `change/m1.3-simulator`

**Motivation.** M1.3 needs a way to generate ongoing simulated files, distinct from M1.2's one fixed seed file, and the owner wants the file count configurable per invocation with a `.env`-backed default (5) rather than hardcoded.

**Design delta:** `design/Milestones.md` M1.3 expanded to the full template. `design/Technical-Design.md` §9 — `simulator/` flipped to `exists`; corrected the "pytest" convention note to `unittest` (below).

**Artifacts:** `simulator/workflow.py` (pure row-generation logic, no imports beyond stdlib), `simulator/simulate.py` (the only module importing `psycopg2`; does the DB writes), `simulator/requirements.txt`, `simulator/Dockerfile`, `simulator/tests/test_workflow.py` (stdlib `unittest`). `docker-compose.yml` — new `simulator` service, `profiles: ["tools"]`. `scripts/simulate.sh`, `Makefile` `simulate` target with `include .env` + `COUNT ?= $(SIMULATOR_FILE_COUNT)`. `.env` — new `SIMULATOR_FILE_COUNT=5`. `tests/check_simulator_logic.sh` (fast), `tests/integration/test_simulator.sh` (integration).

**Reversal:** if the pure-logic/DB-writing split becomes awkward (e.g. row generation needs to know about existing DB state), fold `workflow.py` back into `simulate.py` and drop the stdlib unit tests in favor of integration-only coverage.

**Validation:** choices and rejected alternatives —
- **`COUNT` configurable via `make simulate COUNT=1000`, defaulting to `.env`'s `SIMULATOR_FILE_COUNT=5`.** Owner's explicit ask. Rejected a literal positional `make simulate 1000` — would need a Make catch-all pattern rule to swallow the argument as a phantom target, with real rough edges (a typo silently becomes a second phantom target instead of a clear error). `COUNT ?= $(SIMULATOR_FILE_COUNT)` combined with `include .env` is the standard, robust Make idiom: a command-line-supplied variable always overrides a Makefile `?=` default, so `.env`'s value and an override compose correctly with no extra logic.
- **Pure `workflow.py` (no psycopg2 import) separated from `simulate.py` (the only DB-writing module).** Per [Process.md](Process.md)'s test strategy, row-generation is business logic (RACI assignment, timestamp sequencing) and belongs to strict test-first, not just a smoke check — but only if it can be unit-tested without standing up a database. Splitting the pure logic out made that possible.
- **stdlib `unittest`, not pytest, for the simulator's fast-tier test.** Keeps the fast tier's "no external infrastructure" property completely literal — no `pip install` needed at all, not even for the test runner itself. Revises the aspirational "pytest" note in Technical-Design §9's original conventions bullet, which predated this milestone.
- **`psycopg2-binary` over `psycopg` (v3).** Owner's call — the long-standing, ubiquitous driver; binary wheel, no build tools needed.
- **Docker Compose `profiles: ["tools"]` on the `simulator` service, invoked via `docker compose run`, not a normal always-on service.** Verified empirically (not just assumed from documentation, per the D002/D004 lesson) that a bare `docker compose up -d` starts only `ods-postgres` while `docker compose run --rm simulator` still works despite the profile gate — confirming Compose's documented behavior that naming a service directly on the command line bypasses profile activation.
- **Nested `${COUNT:-${SIMULATOR_FILE_COUNT}}` interpolation in `docker-compose.yml`'s `environment:` block.** Verified empirically via `docker compose config` (with and without a `COUNT` override in the shell environment) rather than assumed, since Compose's variable substitution doesn't support the full range of shell parameter expansion and this pattern isn't universally documented as supported.
- **Every simulated file is closed (all 4 steps complete).** Matches Requirements.md's only currently-active metric (U1, per-step turnaround on closed files); open/in-progress file generation is deferred rather than speculatively built now.
- **Fresh `parties` per file, no shared "professional roster."** The current requirements don't call for a reusable roster concept; adding one now would be speculative.
- **Found and fixed while building:** mixing a positional `%s` placeholder with named `%(name)s` placeholders in the same psycopg2 query, passing a dict parameter, raised `TypeError: dict is not a sequence` — psycopg2 requires one placeholder style consistently when a dict is bound. Fixed by using `%(file_id)s` throughout.

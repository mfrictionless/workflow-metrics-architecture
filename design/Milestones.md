
# Overview

I was interviewed a principle data engineer for a small technology company working to make the clear to close decision with titles faster and with more confidence.  They are now working to improve the entire closing process for a mortgage.

- I have completed the prep work for the interview which you can find in 
- We have completed the interview with hiring manager for this problem

Now we will build out an actual working solution with the milestones identified below.

# Milestones

## Build Phase — Testable Units

M0 covers repository structure and reproducibility. Phases M1–M6 match the
architecture mapping in
[Technical-Design.md §6](Technical-Design.md#6-milestones--architecture-mapping);
M7 expands the truncated workflow once the pipeline is verified end-to-end.
Sub-milestones are the granular, independently testable units within a phase —
build and verify them in order; a phase is done when all its sub-milestones pass.

### M0: Repository structure and single-command pipeline

A monorepo: one `docker-compose.yml` at the repository root composes every
service as it comes online, and one command runs every test suite. This
satisfies NFR-4 (reproducibility — "runs from a clean checkout with one
documented command") in [Requirements.md](Requirements.md). M0 is a standing
requirement, not a one-and-done milestone: each service or test suite added in
M1–M7 is wired into the compose file and the test command as part of that
milestone's own acceptance criteria.

**M0.1 — Repository structure**
- **Test:** The repository follows a documented monorepo layout — one top-level folder per pipeline component, named after its [Technical-Design.md §2](Technical-Design.md#2-component-choices) component, plus a layout map recorded in the [README](../README.md). Component folders are created by the milestone that first needs them (lazy, not speculative — see Out-of-scope); `ods/` already exists from M1.1.
- **Acceptance:** A new contributor can locate any component's source by folder name alone, with no cross-referencing needed; the structure test (below) passes in the fast suite.
- **Dependencies:** None — foundational. M0.2–M0.3 build on this layout.
- **Out-of-scope:**
  - Creating empty placeholder folders for components not yet built — each is added by its own milestone, to avoid speculative structure.
  - The root `docker-compose.yml` (M0.2) and the single-command test runner (M0.3).
  - Any implementation code inside the component folders.
- **Layout:** The authoritative folder map and conventions live in [Technical-Design.md §9](Technical-Design.md#9-repository-layout) — a living map whose Status column flips from `planned` to `exists` as each folder is created. Only `ods/` exists today.
- **Automated Test Plan:**
  - *Fast — structure smoke check* (`tests/check_structure.sh`, no dependencies): asserts the §9 layout section exists, that folders marked existing are present on disk (`ods/` now; each later milestone appends its own), that `ods/ddl/schema.sql` exists where the map says the ODS source lives, and that every [§2](Technical-Design.md#2-component-choices) component folder is documented in the map. Exits non-zero on any missing folder or undocumented component.
- **Manual Test Plan:**
  - Read the layout map; for each [§2](Technical-Design.md#2-component-choices) component confirm there is exactly one folder with an unambiguous name.
  - Confirm no speculative/empty component folders exist yet (only `ods/`).

**M0.2 — docker-compose.yml at repo root**
- **Test:** A `docker-compose.yml` and a companion `.env` at the repository root define the ODS PostgreSQL service. `.env` holds the adjustable settings (host port, db name, user, password) with committed defaults — no manual setup required for a clean checkout, but a user can edit `.env` to fit their own environment (e.g., already running Postgres on 5432). `make up` / `make down` are the documented entrypoints, not bare `docker compose` commands, because a port conflict must fail with a message pointing at `.env` rather than Docker's raw daemon error.
- **Acceptance:** From a clean checkout, `make up` brings the ODS container up on the default settings and it accepts connections (`pg_isready` succeeds) within a bounded startup window; overriding an `.env`-sourced value (e.g. the database name) and re-running picks up the new value with no changes to `docker-compose.yml`; `make down` tears down cleanly with no orphaned volumes; if `ODS_POSTGRES_PORT` is already occupied by anything on the host — a Docker container or a native process — `make up` fails fast with a message naming the port and pointing at `.env`, rather than surfacing Docker's raw "port is already allocated" error.
- **Dependencies:** M0.1 (folder layout — `ods/` already exists and holds the DDL M1.1 wires in).
- **Out-of-scope:**
  - Applying `ods/ddl/schema.sql` on startup — that's M1.1, since it's ODS-specific wiring rather than general compose setup.
  - Any other service (simulator, Kafka, warehouse, Airflow, consumers) — added by their own milestones per §9's lazy-creation convention.
  - Real secrets management — `.env` holds local-dev-only defaults, called out via comment as not for production use.
- **Automated Test Plan:**
  - *Fast:* `docker compose config` — validates the compose file + `.env` interpolation parses and renders without starting containers.
  - *Integration:* `tests/integration/test_compose_up.sh` — brings the stack up via `scripts/compose_up.sh` on default `.env` settings, waits for readiness, then overrides `ODS_POSTGRES_DB` and confirms the overridden database actually exists (proving `.env` is wired in, not vestigial).
  - *Integration:* `tests/integration/test_port_conflict.sh` — regression test for a bug found in manual testing: occupies a port with an independently-running container, then asserts `scripts/compose_up.sh` fails (not a false-positive success) with a message naming `ODS_POSTGRES_PORT`.
- **Manual Test Plan:**
  - `make up`, confirm no errors in logs.
  - `psql` in and confirm connection succeeds (no tables yet — that's M1.1).
  - Edit `.env`, change `ODS_POSTGRES_PORT`, re-run, confirm the new port is what's listening.
  - `make down`, confirm volume removal (`docker volume ls`).
  - With the configured port already occupied by something else, confirm `make up` fails with a message pointing at `.env` — not Docker's raw daemon error.

**M0.3 — Single-command test run**
- **Test:** `make test` discovers and runs every test script in the repo — **fast** tier (`tests/*.sh`, no external infrastructure) first, then **integration** tier (`tests/integration/*.sh`, needs Docker) — stopping immediately at the first failing script (fail-fast) and naming it. `make test-fast` runs only the fast tier.
- **Acceptance:** From a clean checkout with Docker running, `make test` runs every script in order and exits 0. A deliberately broken assertion in any one script stops the run at that script, names it, exits non-zero, and does not run subsequent scripts (including the entire integration tier, if the failure is in the fast tier). `make test-fast` completes with no Docker dependency.
- **Dependencies:** M0.1 (`check_structure.sh` exists); M0.2 (compose file + the two integration scripts exist).
- **Out-of-scope:**
  - Built-in support for non-shell test tools (pytest, `dbt test`) — none exist yet. The milestone that introduces them (M1.3, M3) is responsible for making its tests discoverable under this same fast/integration glob convention.
  - Parallel test execution.
  - Test result caching / skip-unchanged-tests logic.
  - **Aggregate-all-failures mode** (run everything, report every failure instead of stopping at the first) — flagged as a known trade-off of fail-fast; deferred to a future milestone once the suite is large enough that full-failure visibility per run outweighs the speed of stopping early.
- **Automated Test Plan:**
  - *Fast:* `tests/check_compose_config.sh` — wraps the `docker compose config` check as a discoverable script (was previously an ad-hoc command run by hand during M0.2).
  - *Fast:* `tests/verify_test_runner_fail_fast.sh` — regression check on the runner itself: injects a deliberately-broken script (sorted to run first), runs `make test-fast`, asserts non-zero exit, that the broken script is named, and that `check_structure.sh` never ran afterward — proving fail-fast actually stops rather than silently continuing. Needs no Docker, so it qualifies as fast tier even though it's a meta-test.
- **Manual Test Plan:**
  - `make test` on a clean checkout with Docker running — confirm all scripts pass in order (fast tier, then integration tier).
  - Stop the Docker daemon, run `make test-fast` — confirm it still passes.
  - With Docker stopped, run `make test-integration` — confirm it fails clearly rather than hanging.
  - Temporarily add a broken fast-tier script, run `make test`, confirm it stops there and never reaches the integration tier; remove the fixture after.

### M1: Source ODS and seed data

**M1.1 — ODS schema mounted, executed, and validated via compose**
- **Test:** `make up` launches the `ods-postgres` service from `docker-compose.yml`; `ods/ddl/` is mounted into Postgres's `/docker-entrypoint-initdb.d/` directory (the official image's auto-init mechanism — any `.sql`/`.sh` there runs once, in alphabetical order, only when the data directory is empty); Postgres executes the mounted `schema.sql` on first startup, creating `files`, `file_actions`, `parties`, `audit_events` with all foreign keys and CHECK constraints intact (enumerated columns — `status`, `action_code`, `action_type`, `role` — using ALL CAPS values), and every column carrying a `COMMENT`.
- **Acceptance:** From a clean checkout, `make up` brings the ODS up with no manual `psql -f` step, and: all 4 tables exist (`information_schema.tables`); FK constraints from `file_actions`/`parties`/`audit_events` to `files` are present; CHECK constraints on the 4 enumerated columns exist and only accept ALL CAPS values (a lowercase insert, e.g. `role = 'borrower'`, is rejected); every column across all 4 tables has a non-empty `COMMENT`. Restarting the container without `make down` (volume persists) does not re-run or error on the init script, per Postgres's own init-once behavior.
- **Dependencies:** M0.2 (compose file + `.env` + `make up`/`make down`).
- **Out-of-scope:**
  - Seeding data — M1.2.
  - Schema migrations/versioning beyond this single `schema.sql`.
  - Any behavior when the data directory is *not* empty (e.g. changing `schema.sql` after a volume already exists) — Postgres's init-once semantics mean that's a `make down -v`-and-recreate case.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_schema_init.sh` — brings the stack up via `scripts/compose_up.sh`, waits for readiness, then: (a) confirms `/docker-entrypoint-initdb.d/schema.sql` exists in the container (the mount is wired correctly); (b) queries `information_schema.tables` for all 4 tables; (c) queries `information_schema.table_constraints`/`pg_constraint` for the expected FKs; (d) attempts a lowercase enum insert on each of the 4 enumerated columns and asserts each is rejected (regression-testing the ALL CAPS fix made during the original schema build, now automated instead of manual); (e) queries `pg_description` and asserts every column of all 4 tables has a non-empty comment, not just a couple of spot-checked ones. Tears down after.
- **Manual Test Plan:**
  - `make up` from a clean checkout, `docker compose exec ods-postgres ls /docker-entrypoint-initdb.d/` — confirm `schema.sql` listed.
  - `psql`/`\d+ <table>` in, confirm all 4 tables, their constraints, and column comments are present.
  - Attempt inserting a lowercase enum value (e.g. `role = 'borrower'`) and confirm rejection.
  - Restart the container (`docker compose restart ods-postgres`, not `make down`) and confirm no errors — the init script correctly does not re-run against the existing volume.

**M1.2 — Seed data (truncated workflow)**
- **Test:** Seed a truncated 4-step workflow — **Apply → Process → Sign → Record and close** (steps 1, 3, 9, 12 of the full 12-step model in [Home-Refinance-Workflow.md](Home-Refinance-Workflow.md)) — for at least one closed file.
- **Acceptance:** Query the ODS directly and retrieve all 4 steps for the file with correct timestamps, RACI-consistent sender/receiver, and party assignments

**M1.3 — Python simulator (truncated workflow)**
- **Test:** Simulator generates new `files` and `file_actions` rows on a repeatable cadence, following the same 4-step model and RACI rules as seed data
- **Acceptance:** Running the simulator for N minutes produces N files' worth of well-formed rows (no orphaned `file_actions`, custody chain intact per A2 in [Requirements.md](Requirements.md))

### M2: CDC and raw landing

**M2.1 — Postgres logical replication**
- **Test:** ODS configured with `wal_level=logical`; a replication slot and publication exist for the source tables
- **Acceptance:** `pg_replication_slots` shows an active slot; a manual `INSERT` produces a decodable WAL change

**M2.2 — Kafka (KRaft)**
- **Test:** Single-node Kafka broker running in KRaft mode; one topic per source table
- **Acceptance:** Broker starts without Zookeeper; topics list shows `files`, `file_actions`, `parties`, `audit_events` topics

**M2.3 — Debezium source connector**
- **Test:** Debezium Postgres connector deployed to Kafka Connect; captures ODS changes as JSON
- **Acceptance:** An ODS write (from M1.2 or M1.3) appears as a message on the corresponding Kafka topic within seconds, with correct before/after payload

**M2.4 — Warehouse PostgreSQL**
- **Test:** Second, separate PostgreSQL instance provisioned for Raw/Silver/Gold/Mart
- **Acceptance:** Warehouse instance is reachable and distinct from the ODS instance; confirms FR-2 (CDC adds no load to the write primary)

**M2.5 — JDBC sink connector**
- **Test:** Kafka Connect JDBC sink connector lands topic messages into Raw tables in the warehouse
- **Acceptance:** Raw tables mirror ODS row counts after a batch of simulator writes; `_cdc_op`, `_cdc_ts`, `_sink_ts` populated per row

### M3: Metric compute (dbt)

**M3.1 — dbt project scaffold**
- **Test:** dbt Core project connects to the warehouse Postgres; `dbt debug` passes
- **Acceptance:** Project runs against Raw tables as dbt sources with no connection errors

**M3.2 — Silver models**
- **Test:** Silver models deduplicate redelivered Kafka records and resolve out-of-order arrival by `_cdc_ts`, producing one current row per `file_id` / `file_action_id`
- **Acceptance:** `dbt test` on Silver enforces uniqueness on the entity key; a manually duplicated Raw row collapses to one Silver row

**M3.3 — Gold models**
- **Test:** Gold joins `file_actions` to `files` and `parties`, deriving step number and party role per step
- **Acceptance:** Gold row count equals Silver `file_actions` row count (1:1); every row resolves a non-null step number and role

**M3.4 — Metric Mart: turnaround (U1)**
- **Test:** Mart computes per-step turnaround (`received_at − sent_at`) and aggregates (mean, p90) by step, for closed/live/positive-duration steps only (FR-3)
- **Acceptance:** Hand-computed turnaround for the M1.2 seed file matches the Mart's output exactly

### M4: Governed analyst surface

**M4.1 — Analyst query interface**
- **Test:** SQL view/query interface exposes `step_turnaround_summary` (mean, p90, count by step) with no per-file or per-party detail
- **Acceptance:** Analyst can answer U1 ("average and 90th-percentile turnaround by step, for closed files") in one query

**M4.2 — PII exclusion**
- **Test:** Inspect the Mart's analyst-facing views for any user, name, email, or file-identifying column
- **Acceptance:** No such column exists in the view definition (verified by construction, not just by convention — NFR-2)

### M5: Party-scoped consumer surface

**M5.1 — RLS policies on the Mart**
- **Test:** PostgreSQL row-level security policies applied to Mart tables, scoping rows to the requesting `party_id`
- **Acceptance:** Policies exist and are enabled (`rowsecurity = true`) on every party-facing Mart table

**M5.2 — Mocked party authentication**
- **Test:** A lightweight auth mock maps a test credential to a `party_id` (or set of `party_id`s via `user_party`)
- **Acceptance:** Two different mock credentials resolve to two different, correct `party_id` sets

**M5.3 — Party consumer API**
- **Test:** Read-only REST endpoint returns workflow status for the authenticated party's file(s)
- **Acceptance:** Endpoint returns 200 with expected file data for a valid mock credential

**M5.4 — Row-scoping verification**
- **Test:** Query the same endpoint with two different party credentials on the same seeded dataset
- **Acceptance:** Each party sees only their own file(s); neither can retrieve the other's file by id or enumeration (NFR-2)

### M6: Orchestration and end-to-end freshness

**M6.1 — Airflow: simulator DAG**
- **Test:** Airflow DAG triggers the Python simulator (M1.3) on a fixed schedule
- **Acceptance:** DAG runs succeed on schedule; new ODS rows appear after each run

**M6.2 — Airflow: dbt run DAG**
- **Test:** Airflow DAG runs `dbt build` (Silver → Gold → Mart) on an interval short enough to leave headroom in the 10-minute freshness budget
- **Acceptance:** DAG runs succeed on schedule; Mart reflects new Raw data after each run

**M6.3 — End-to-end freshness**
- **Test:** Commit a simulated write to the ODS; measure time until it is visible in the analyst Mart view (NFR-1, [§7 success metrics](Requirements.md#7-success-metrics))
- **Acceptance:** Measured lag is ≤ 10 minutes across at least 3 trials; the dominant latency source (dbt run interval) is documented

### M7: Expand simulator to full workflow

**M7.1 — Expand to full 12-step workflow**
- **Test:** Once M1–M6 are verified end-to-end on the truncated workflow, re-seed and re-run the simulator against the full 12-step model
- **Acceptance:** All downstream milestones (M2–M6) continue to pass unchanged against the full workflow — the truncation should not have required pipeline changes, only additional `file_actions` rows and `action_code` values

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

### M0: Repository structure and single-command pipeline (COMPLETE)

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
  - *Fast — structure smoke check* (`tests/check_structure.sh`, no dependencies): asserts the §9 layout section exists, that folders marked existing are present on disk (`ods/` now; each later milestone appends its own), that `ods/ddl/001_schema.sql` exists where the map says the ODS source lives, and that every [§2](Technical-Design.md#2-component-choices) component folder is documented in the map. Exits non-zero on any missing folder or undocumented component.
- **Manual Test Plan:**
  - Read the layout map; for each [§2](Technical-Design.md#2-component-choices) component confirm there is exactly one folder with an unambiguous name.
  - Confirm no speculative/empty component folders exist yet (only `ods/`).

**M0.2 — docker-compose.yml at repo root**
- **Test:** A `docker-compose.yml` and a companion `.env` at the repository root define the ODS PostgreSQL service. `.env` holds the adjustable settings (host port, db name, user, password) with committed defaults — no manual setup required for a clean checkout, but a user can edit `.env` to fit their own environment (e.g., already running Postgres on 5432). `make up` / `make down` are the documented entrypoints, not bare `docker compose` commands, because a port conflict must fail with a message pointing at `.env` rather than Docker's raw daemon error.
- **Acceptance:** From a clean checkout, `make up` brings the ODS container up on the default settings and it accepts connections (`pg_isready` succeeds) within a bounded startup window; overriding an `.env`-sourced value (e.g. the database name) and re-running picks up the new value with no changes to `docker-compose.yml`; `make down` tears down cleanly with no orphaned volumes; if `ODS_POSTGRES_PORT` is already occupied by anything on the host — a Docker container or a native process — `make up` fails fast with a message naming the port and pointing at `.env`, rather than surfacing Docker's raw "port is already allocated" error.
- **Dependencies:** M0.1 (folder layout — `ods/` already exists and holds the DDL M1.1 wires in).
- **Out-of-scope:**
  - Applying `ods/ddl/001_schema.sql` on startup — that's M1.1, since it's ODS-specific wiring rather than general compose setup.
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

### M1: Source ODS and seed data (COMPLETE)

**M1.1 — ODS schema mounted, executed, and validated via compose**
- **Test:** `make up` launches the `ods-postgres` service from `docker-compose.yml`; `ods/ddl/` is mounted into Postgres's `/docker-entrypoint-initdb.d/` directory (the official image's auto-init mechanism — any `.sql`/`.sh` there runs once, in alphabetical order, only when the data directory is empty); Postgres executes the mounted `001_schema.sql` on first startup, creating `files`, `file_actions`, `parties`, `audit_events` with all foreign keys and CHECK constraints intact (enumerated columns — `status`, `action_code`, `action_type`, `role` — using ALL CAPS values), and every column carrying a `COMMENT`.
- **Acceptance:** From a clean checkout, `make up` brings the ODS up with no manual `psql -f` step, and: all 4 tables exist (`information_schema.tables`); FK constraints from `file_actions`/`parties`/`audit_events` to `files` are present; CHECK constraints on the 4 enumerated columns exist and only accept ALL CAPS values (a lowercase insert, e.g. `role = 'borrower'`, is rejected); every column across all 4 tables has a non-empty `COMMENT`. Restarting the container without `make down` (volume persists) does not re-run or error on the init script, per Postgres's own init-once behavior.
- **Dependencies:** M0.2 (compose file + `.env` + `make up`/`make down`).
- **Out-of-scope:**
  - Seeding data — M1.2.
  - Schema migrations/versioning beyond this single `001_schema.sql`.
  - Any behavior when the data directory is *not* empty (e.g. changing `001_schema.sql` after a volume already exists) — Postgres's init-once semantics mean that's a `make down -v`-and-recreate case.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_schema_init.sh` — brings the stack up via `scripts/compose_up.sh`, waits for readiness, then: (a) confirms `/docker-entrypoint-initdb.d/001_schema.sql` exists in the container (the mount is wired correctly); (b) queries `information_schema.tables` for all 4 tables; (c) queries `information_schema.table_constraints`/`pg_constraint` for the expected FKs; (d) attempts a lowercase enum insert on each of the 4 enumerated columns and asserts each is rejected (regression-testing the ALL CAPS fix made during the original schema build, now automated instead of manual); (e) queries `pg_description` and asserts every column of all 4 tables has a non-empty comment, not just a couple of spot-checked ones. Tears down after.
- **Manual Test Plan:**
  - `make up` from a clean checkout, `docker compose exec ods-postgres ls /docker-entrypoint-initdb.d/` — confirm `001_schema.sql` listed.
  - `psql`/`\d+ <table>` in, confirm all 4 tables, their constraints, and column comments are present.
  - Attempt inserting a lowercase enum value (e.g. `role = 'borrower'`) and confirm rejection.
  - Restart the container (`docker compose restart ods-postgres`, not `make down`) and confirm no errors — the init script correctly does not re-run against the existing volume.

**M1.2 — Seed data (truncated workflow)**
- **Test:** `make seed` — a separate, explicit command — applies `ods/seed/seed.sql` against the running ODS (piped into `psql` via `docker compose exec`), inserting one closed file's truncated 4-step workflow (Apply → Process → Sign → Record and close), with `parties` rows for every role involved and RACI-correct sender/receiver per steps 1, 3, 9, 12 in [Home-Refinance-Workflow.md](Home-Refinance-Workflow.md). Kept out of `ods/ddl/` (not mounted into `docker-entrypoint-initdb.d`) so `make up` alone brings up an **empty** ODS — seed data is never automatically mixed into whatever the simulator (M1.3+) generates.
- **Acceptance:** From a clean checkout, `make up` brings up an ODS with 0 files. Running `make seed` afterward results in exactly 1 file (`status='CLOSED'`) with its 4 `file_actions` rows, each `sent_at < received_at`, sender/receiver party roles matching the workflow reference; `files.closed_at` equals the `RECORDING` step's `received_at`, and that step's `received_user_id` is `NULL` (A5).
- **Dependencies:** M1.1 (schema + `make up` bringing up a clean, empty ODS).
- **Out-of-scope:**
  - The full 12-step workflow — M7.
  - Ongoing/continuous data generation — M1.3.
  - Seeding more than one file per invocation.
  - **Idempotency of repeated `make seed` calls** — it's an explicit, additive command; running it twice inserts a second file (confirmed in manual testing). Not guarded against now; revisit if that becomes a real workflow problem.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_seed_data.sh` — brings the stack up via `scripts/compose_up.sh`, asserts **0 files** present (proving `make up` alone stays empty); runs `scripts/seed.sh`; then verifies exactly 1 file, 4 `file_actions` rows with expected `action_code`s in order, every row's `sent_at < received_at`, correct sender/receiver roles per step, `RECORDING.received_user_id IS NULL`, and `files.closed_at` matching `RECORDING.received_at` exactly (the seed script captures one `now()` value via `\gset` and reuses it for both, avoiding two separate `now()` calls drifting apart). Tears down after.
- **Manual Test Plan:**
  - `make up`, confirm `SELECT count(*) FROM files;` returns 0.
  - `make seed`, confirm the 1 seeded file and its 4 steps as described.
  - Run `make seed` again and observe a second file inserted — confirms it's additive/explicit, matching the documented out-of-scope behavior.

**M1.3 — Python simulator (truncated workflow)**
- **Test:** `make simulate` (default count from `.env`'s `SIMULATOR_FILE_COUNT=5`; override per-run with `make simulate COUNT=1000`) runs the simulator in a one-off container (`docker compose run`) on the compose network, inserting `COUNT` new, independent, fully-closed files — same truncated 4-step workflow and RACI-correct sender/receiver as M1.2's seed data, fresh `parties` per file. Row-generation logic (`simulator/workflow.py`) is pure and dependency-free, separated from the DB-writing wrapper (`simulator/simulate.py`, the only module importing `psycopg2`) so it can be unit-tested without a database.
- **Acceptance:** `make simulate COUNT=n` produces exactly `n` new closed files, each with its own 4 `file_actions` and 6 `parties` rows, correct roles per step, no orphaned rows, no cross-file mixups, and `RECORDING.received_user_id IS NULL` (A5). Additive across runs, like `make seed`. `make simulate` alone (no `COUNT=`) uses the `.env` default.
- **Dependencies:** M0.2 (compose + `.env` + `make up`/`make down`); M1.1 (schema + writable ODS).
- **Out-of-scope:**
  - Internal scheduling/looping — one invocation makes `COUNT` files and exits; repeated/scheduled invocation is M6.1's job (Airflow).
  - Open/in-progress files — every simulated file is closed, matching the only currently-active metric (U1, per-step turnaround on closed files).
  - The full 12-step workflow — M7.
  - A shared "professional roster" of parties across files — each file gets its own fresh 6 parties.
- **Automated Test Plan:**
  - *Fast:* `tests/check_simulator_logic.sh` — runs `simulator/tests/test_workflow.py` via stdlib `unittest` (no pip install, no Docker): action sequence and order, `sent_at < received_at`, sender/receiver roles per step match Home-Refinance-Workflow.md, `closed_at` matches the terminal step's `received_at`, terminal step has no receiver, 6 parties, and no `user_id`/`file_number` collisions across two calls to `build_file`.
  - *Integration:* `tests/integration/test_simulator.sh` — brings the stack up, confirms 0 files before simulating, runs `COUNT=3 ./scripts/simulate.sh`, asserts 3 closed files each with exactly 4 `file_actions` / 6 `parties`, no orphans, correct roles per step (joined within the correct file, proving no cross-file mixups), `RECORDING.received_user_id IS NULL`; runs once more with `COUNT=1` and confirms the count is additive (4 total).
- **Manual Test Plan:**
  - `make up`, then `make simulate` — confirm 5 new closed files (the `.env` default).
  - `make simulate COUNT=2` — confirm 2 more files, 7 total.
  - Inspect one file's rows directly; confirm roles and timestamps are sane.

### M2: CDC and raw landing

**M2.1 — Postgres logical replication**
- **Test:** The ODS Postgres service starts with `wal_level=logical` (a command-line override in `docker-compose.yml` — a postmaster-context setting, only applied at server start). On first init, `ods/ddl/002_replication.sql` creates a `PUBLICATION` (`dbz_publication`) covering all 4 source tables and a logical replication slot (`dbz_slot`) using the `pgoutput` plugin — the same plugin Debezium's Postgres connector will consume in M2.3.
- **Acceptance:** From a clean checkout, `make up` results in: `SHOW wal_level;` = `logical`; `pg_publication_tables` lists all 4 tables under `dbz_publication`; `pg_replication_slots` shows `dbz_slot` (`plugin='pgoutput'`, `slot_type='logical'`); a manual `INSERT` produces a decodable WAL change (verified via a separate, temporary `test_decoding`-plugin slot created and dropped within the test, so the real `pgoutput` slot stays untouched for M2.3 to consume first). Restarting the container without `make down` doesn't re-run or error on the init script, and the slot/publication persist unduplicated (confirmed in manual testing).
- **Dependencies:** M1.1 (schema exists — the publication needs the tables); M0.2 (compose + `make up`/`make down`).
- **Out-of-scope:**
  - Actually consuming the slot with Debezium — M2.3.
  - Kafka / Kafka Connect — M2.2 / M2.3.
  - Replication behavior under concurrent write load — out of scope for this working example.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_replication.sh` — brings the stack up, asserts `wal_level='logical'`, all 4 tables present in `pg_publication_tables` for `dbz_publication`, and `dbz_slot` exists with `plugin='pgoutput'`, `slot_type='logical'`. Then creates a temporary `test_decoding` slot, inserts a row, calls `pg_logical_slot_get_changes()` on that temporary slot, asserts the human-readable output contains `INSERT` and references the `files` table, and drops the temporary slot.
- **Manual Test Plan:**
  - `make up`, `psql` in, `SHOW wal_level;` → `logical`.
  - `SELECT * FROM pg_publication_tables;` → all 4 tables under `dbz_publication`.
  - `SELECT * FROM pg_replication_slots;` → `dbz_slot` present, `plugin='pgoutput'`, `active=f`.
  - Restart the container (not `make down`), confirm no errors and the slot/publication persist unduplicated.

**M2.2 — Kafka (KRaft)**
- **Test:** A single-node Kafka broker (`apache/kafka`, official image; combined broker+controller, KRaft mode — no Zookeeper) starts via `docker-compose.yml`, with its host-facing listener port exposed via `.env` (`KAFKA_BROKER_PORT`, matching the `ODS_POSTGRES_PORT` pattern). Proves basic broker health and topic management — not the final CDC topic topology (Debezium, M2.3, creates its own topics with its own naming convention).
- **Acceptance:** `make up` brings the broker up and it accepts client/admin connections; creating 4 topics (`files`, `file_actions`, `parties`, `audit_events`) and listing them succeeds; no Zookeeper process/container exists anywhere in the stack. Restarting the container without `make down` preserves the cluster ID and created topics (confirmed in manual testing — no errors, no re-formatting).
- **Dependencies:** M0.2 (compose + `.env` + `make up`/`make down`).
- **Out-of-scope:**
  - The actual CDC topics Debezium will produce into (its own `topic.prefix.schema.table` naming, defined in M2.3) — these 4 health-check topics may end up unused, which is fine.
  - The Kafka Connect worker and connector plugins (Debezium source, JDBC sink) — a separate image/container decided in M2.3/M2.5, independent of the broker image choice.
  - Multi-broker / production topology — single-node only.
  - Schema Registry — already decided against (Technical-Design.md §2: plain JSON, no registry).
  - Full Kafka-protocol-level verification of the host-facing listener's advertised-address redirect — verified only via raw TCP reachability and a compose-network container client, since no native Kafka client was available on the test host to fully exercise the external-client metadata path.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_kafka.sh` — brings the broker up, waits for it to accept connections (`kafka-broker-api-versions.sh`), creates the 4 topics, asserts all 4 appear in the topic list, and confirms no Zookeeper container is running anywhere in the stack.
- **Manual Test Plan:**
  - `make up`, `docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list` — confirm the 4 topics.
  - Restart the container (not `make down`), confirm topics persist and no cluster-ID/formatting errors appear in logs.
  - `streaming/` (per Technical-Design.md §9) was not created for this milestone — Kafka's entire KRaft configuration is expressible via `docker-compose.yml` environment variables, no custom Dockerfile or config file needed. Left `planned`; M2.3 (Kafka Connect worker + connector configs) is the more likely milestone to first need real files there.

**M2.3 — Debezium source connector**
- **Test:** A Kafka Connect worker (`debezium/connect` image — Kafka Connect bundled with the Debezium Postgres connector plugin pre-installed) runs in **distributed mode with a single worker**: connector config, offsets, and status are stored in Kafka topics (`connect-configs`, `connect-offsets`, `connect-status`, replication factor 1 — same single-broker constraint as M2.2's internal topics), not local files, so the worker holds no state outside Kafka. A connector config (`cdc/debezium-postgres-source.json`) is registered against the worker's REST API (`POST /connectors`); it consumes the **existing** `dbz_slot`/`dbz_publication` created in M2.1 (`plugin.name=pgoutput`, `slot.name=dbz_slot`, `publication.name=dbz_publication`) rather than creating its own, and publishes each of the 4 source tables to its own topic under `topic.prefix=ods` (e.g. `ods.public.files`).
- **Acceptance:** From a clean checkout, `make up` brings up the Connect worker and it accepts REST calls (`GET /connectors` returns `200`) within a bounded startup window; `make register-connector` succeeds and the connector's status is `RUNNING` with its task also `RUNNING` (confirmed as a race in testing — `connector.state` can read `RUNNING` a moment before `tasks[0].state` does, so both must be polled together, not just the top-level state); inserting a row into any of the 4 ODS tables (e.g. via `make seed`) produces a message on that table's topic (`ods.public.<table>`) within seconds, with a JSON payload whose `after` block matches the inserted row and whose `before` block is `null` (insert, not update); re-running `make register-connector` against an already-registered connector is idempotent (`PUT /connectors/<name>/config`, checked via a GET first) rather than erroring or duplicating.
- **Dependencies:** M2.1 (`dbz_slot`/`dbz_publication` must already exist — this connector consumes them, it does not create them); M2.2 (Kafka broker for the Connect worker's internal topics and the tables' output topics).
- **Out-of-scope:**
  - The JDBC sink connector (landing these messages into the warehouse) — M2.5.
  - Schema Registry / Avro — already decided against (Technical-Design.md §2: plain JSON).
  - Multiple Connect workers / worker failover — single-node distributed mode only, per the working-example scope.
  - `UPDATE`/`DELETE` payload handling beyond what Debezium produces by default — this working example's ODS is insert-only (Technical-Design.md §2's no-hard-deletes assumption), so only the `INSERT` case is exercised.
  - Kafka Connect's own metrics/monitoring endpoints.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_debezium_connector.sh` — brings the stack up, waits for the Connect REST API to accept connections, registers `cdc/debezium-postgres-source.json` (or confirms it's already registered), polls connector status until `RUNNING`, inserts a seed file via `scripts/seed.sh`, then consumes from the `ods.public.files` and `ods.public.file_actions` topics and asserts a message appears for each with a non-null `after` payload matching the inserted row and a `null` `before` payload. Tears down after.
- **Manual Test Plan:**
  - `make up`, `curl localhost:${CONNECT_REST_PORT}/connectors` — confirm the worker responds.
  - `make register-connector`, `curl .../connectors/ods-source/status` — confirm both `connector.state` and `tasks[0].state` are `RUNNING`.
  - `make seed`, then consume from `ods.public.files` (`kafka-console-consumer.sh`) — confirm the seeded row appears as a JSON message within seconds.
  - Re-run `make register-connector` a second time — confirm no error and `GET /connectors` still lists exactly one `ods-source` connector.
  - `docker compose restart kafka-connect` (not `make down`) — confirm the connector config is still registered with no re-registration needed (`GET /connectors` still lists it); status briefly reports `UNASSIGNED` for the connector-level state during the worker's post-restart rebalance before settling back to `RUNNING` — noted here rather than silently assumed instantaneous.

**M2.4 — Warehouse PostgreSQL**
- **Test:** A second `warehouse-postgres` service in `docker-compose.yml` — its own container, its own `warehouse_data` volume, its own host port (`WAREHOUSE_POSTGRES_PORT` in `.env`, following the `ODS_`/`WAREHOUSE_` prefix convention anticipated back in D002) — entirely separate from `ods-postgres`. No schema is applied yet; Raw tables arrive with the JDBC sink connector (M2.5) that lands into this instance.
- **Acceptance:** From a clean checkout, `make up` brings up both `ods-postgres` and `warehouse-postgres` as distinct running containers with distinct container IDs and distinct volumes; `warehouse-postgres` accepts connections (`pg_isready`) on its own port within the same bounded startup window as `ods-postgres`; a row written to the ODS is not visible anywhere in the warehouse instance (proving these are genuinely two databases, not one instance with two schemas) — the concrete, verifiable form of FR-2 ("CDC adds no load to the write primary"), since the write primary and the warehouse now physically cannot share load by construction.
- **Dependencies:** M0.2 (compose + `.env` + `make up`/`make down` pattern this service follows).
- **Out-of-scope:**
  - Any staging/intermediate/marts model schema in the warehouse — M2.5 (JDBC sink lands Raw) and M3 (dbt builds staging/intermediate/marts) apply schema, respectively.
  - The `warehouse/` folder (Technical-Design.md §9) — left `planned`; this milestone's entire config is expressible via `docker-compose.yml`/`.env`, same reasoning as M2.2's `streaming/`. `warehouse/` is more likely first needed by M3's dbt project.
  - Cross-instance replication, backup, or HA — a single warehouse instance, matching the ODS's own scope.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_warehouse_postgres.sh` — brings the stack up, asserts `ods-postgres` and `warehouse-postgres` are running as two distinct containers (different container IDs) with two distinct volumes; waits for `warehouse-postgres` readiness the same way `test_compose_up.sh` does for the ODS; inserts a row into the ODS and confirms the warehouse instance has no table by that name to even query (proving isolation, not just "a query against it returned 0 rows" which could also be true of an empty table in the same instance).
- **Manual Test Plan:**
  - `make up`, `docker compose ps` — confirm both `ods-postgres` and `warehouse-postgres` listed as separate containers.
  - `docker volume ls` — confirm `ods_data` and `warehouse_data` are separate volumes.
  - `psql` into the warehouse instance directly (its own host port) — confirm it accepts connections and has no ODS tables.
  - `make down`, confirm both volumes are removed.

**M2.5 — JDBC sink connector**
- **Test:** A Debezium JDBC sink connector (`io.debezium.connector.jdbc.JdbcSinkConnector`) registered against the same `kafka-connect` worker from M2.3 — no new image or plugin install, since the `quay.io/debezium/connect` image already bundles this plugin. Chosen over Confluent's `kafka-connect-jdbc` to sidestep that connector's Community License question entirely (Debezium's JDBC sink is Apache 2.0). Consumes all 4 `ods.public.*` topics (M2.3) via a topic regex and lands each as its own append-only Raw table (`raw_files`, `raw_file_actions`, `raw_parties`, `raw_audit_events`) in `warehouse-postgres` (M2.4). Raw tables are **hand-written DDL** (`warehouse/ddl/001_raw_schema.sql`, mounted the same way as `ods/ddl/`), not the connector's own schema evolution — reversing the draft's original plan once testing showed schema evolution can't produce `_sink_ts` (a Postgres-side `DEFAULT now()`, not a value carried on the Kafka message) without a racy after-the-fact `ALTER TABLE`. `_cdc_op`/`_cdc_ts` are stamped onto each message by an SMT chain (`ExtractNewRecordState` + a field rename) before the sink writes it; `_cdc_ts` is Debezium's event timestamp, not the ODS row's own timestamp columns.
- **Acceptance:** From a clean checkout, `make up` + `make register-connector` (generalized to loop over every `cdc/*.json` config, registering both the source and sink connectors) results in the sink connector reaching `RUNNING` with its task also `RUNNING`; after `make seed`, each Raw table's row count matches the corresponding ODS table's row count; every landed row carries non-null `_cdc_op` (`c` for an insert-only source), `_cdc_ts`, and `_sink_ts`. Landing is append-only: a redelivered or duplicate Kafka message produces another Raw row rather than an upsert — deduplication is explicitly the staging layer's job (M3.2), not Raw's. `make register-connector` run twice is idempotent for both connectors.
- **Dependencies:** M2.3 (source connector + `ods.public.*` topics must exist); M2.4 (`warehouse-postgres` as the landing target).
- **Out-of-scope:**
  - Deduplication of redelivered records, or resolving out-of-order arrival — the staging layer's job (M3.2). Raw is a faithful, append-only landing of every message received.
  - `UPDATE`/`DELETE` handling beyond what the source connector produces — same insert-only assumption as M2.3 (Technical-Design.md §2).
  - Schema Registry / Avro — already decided against.
  - Foreign keys, `NOT NULL`, or `CHECK` constraints on Raw tables — deliberately unconstrained; Raw faithfully lands whatever arrived, per-topic, independently ordered. Correctness constraints belong to the staging layer.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_jdbc_sink.sh` — brings the stack up, registers both connectors, waits for the sink connector/task to reach `RUNNING`, runs `make seed`, polls for the row to land (the pipeline is asynchronous), then asserts each of the 3 seeded Raw tables' row count matches its ODS counterpart, `_cdc_op`/`_cdc_ts`/`_sink_ts` are non-null on every `raw_files` row, and `_cdc_op='c'`.
- **Manual Test Plan:**
  - `make up`, `make register-connector`, confirm both `ods-source` and `warehouse-raw-sink` show `RUNNING` (connector and task) via the REST API.
  - `make seed`, then `psql` into `warehouse-postgres` and confirm `raw_files` (etc.) exist with the seeded rows and populated `_cdc_op`/`_cdc_ts`/`_sink_ts`.
  - `make simulate COUNT=3`, confirm the Raw row counts grow by 3 per table, matching the ODS.
  - Re-run `make register-connector` — confirm no error and no duplicate connectors (`GET /connectors` still lists exactly `ods-source` and `warehouse-raw-sink`).

**M2.6 — Transaction metadata for cross-table correlation**
- **Test:** Enable Debezium's `provide.transaction.metadata=true` on the source connector (M2.3). This adds a `transaction: {id, total_order, data_collection_order}` block to every message envelope (previously always `null`) and creates a new `ods.transaction` topic carrying explicit BEGIN/END transaction-boundary events. Extend the JDBC sink's SMT chain (M2.5) to extract **two** fields, not one, onto every Raw table row — confirmed empirically that one alone isn't sufficient (see Decisions.md D012): `_cdc_txn_id` (`transaction.id`, a `"<txId>:<lsn>"` string — demonstrates the transaction-metadata feature itself, ties to the `ods.transaction` topic's BEGIN/END events, but is **not** equal across rows in the same transaction, since its LSN suffix advances per WAL record) and `_cdc_source_txn_id` (`source.txId`, a plain integer, present on every message regardless of this feature — the actually-stable, directly `=`-comparable correlation key). Both columns are added via a **new, numbered DDL file** (`warehouse/ddl/002_transaction_metadata.sql`), not by editing `001_raw_schema.sql` in place, since `docker-entrypoint-initdb.d` only executes on a fresh (empty) volume; this mirrors the `ods/ddl` `001_schema.sql`/`002_replication.sql` precedent from M2.1 and is this project's real schema-evolution mechanism.
- **Acceptance:** After `make down` (fresh volumes, so `002_transaction_metadata.sql` actually runs), `make up`, `make register-connector`, and `make simulate COUNT=1`: `raw_files`, `raw_parties`, and `raw_file_actions` all carry rows for that one simulated file sharing one non-null `_cdc_source_txn_id` — a real cross-table proof, since `simulator/simulate.py`'s `insert_file()` performs exactly one `conn.commit()` after inserting all three tables' rows for a file (confirmed by reading the code: psycopg2 defaults to `autocommit=False`, so every statement since the last commit is one open transaction). Two separate `make simulate COUNT=1` invocations produce rows with *different* `_cdc_source_txn_id` values, proving it's a genuine per-transaction identifier, not a constant. `_cdc_txn_id` is non-null on every row but is not asserted equal across rows — that would be asserting something untrue about the field, per the empirical finding above. (`seed.sql`, by contrast, has no explicit `BEGIN`/`COMMIT` — `psql`'s autocommit means its `files`/`parties`/`file_actions` inserts are 3 separate transactions; confirmed empirically, and left as-is rather than changed to fit the demo. `seed.sql`'s own multi-row `parties`/`file_actions` INSERTs still each share one `_cdc_source_txn_id` within that table.) The `ods.transaction` topic exists and contains BEGIN/END events bounding the observed transactions.
- **Dependencies:** M2.3 (source connector); M2.5 (sink connector, Raw DDL, SMT chain).
- **Out-of-scope:**
  - Landing the `ods.transaction` topic's BEGIN/END events into a table — this milestone only needs the per-row correlation columns, not a materialized transaction log.
  - `total_order`/`data_collection_order` — not captured. Those two fields solve a different problem (confirming every event in a transaction has been observed) that isn't needed yet.
  - Automatic migration of already-provisioned warehouse volumes — `docker-entrypoint-initdb.d` only runs `002_transaction_metadata.sql` on a fresh volume; an existing deployment would need a manual `ALTER TABLE` or a `make down`/`make up` cycle. Documented as a known limitation of this mounting mechanism, not solved here.
  - Wrapping `seed.sql` in an explicit transaction to make its 3 inserts correlate cross-table — left as-is; M2.6 doesn't reach back into M1.2's seed script for demo purposes.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_transaction_metadata.sh` — brings the stack up fresh, registers both connectors, runs `COUNT=1 make simulate`, waits for the expected row counts on all 3 tables, asserts the resulting `raw_files`/`raw_parties`/`raw_file_actions` rows for that file share one `_cdc_source_txn_id`; runs a second `COUNT=1` simulate call and asserts its `_cdc_source_txn_id` differs from the first; asserts `_cdc_txn_id` is non-null; confirms the `ods.transaction` topic exists.
- **Manual Test Plan:**
  - `make down && make up && make register-connector`, `make simulate COUNT=1`, then `psql` into `warehouse-postgres`: compare `_cdc_source_txn_id` across `raw_files`, `raw_parties`, `raw_file_actions` for that file's rows — confirm they match.
  - `make simulate COUNT=1` again, confirm the new `raw_files` row has a different `_cdc_source_txn_id` from the first.
  - Consume from `ods.transaction` (`kafka-console-consumer.sh`) — confirm BEGIN/END events are visible, and that a data message's `payload.transaction.id` shares its leading segment with the enclosing transaction's BEGIN/END `id`.

### M3: Metric compute (dbt)

**M3.1 — dbt project scaffold**
- **Test:** A dbt Core project (`warehouse/dbt/`) connects to `warehouse-postgres` and declares the 4 existing Raw tables (`raw_files`, `raw_file_actions`, `raw_parties`, `raw_audit_events` — M2.5/M2.6) as dbt sources, with no models yet. Run via a new `dbt` service in `docker-compose.yml` — `ghcr.io/dbt-labs/dbt-postgres:1.8.latest` (the official dbt Labs image with the Postgres adapter pre-installed), `profiles: ["tools"]` like the `simulator` service, invoked via `docker compose run`, not a long-running container. This image has no `arm64` build (confirmed by inspecting its manifest — every tag checked is `amd64`-only), so the service requires `platform: linux/amd64` (Rosetta emulation on Apple Silicon) — the same constraint Debezium's own docs flagged for `quay.io/debezium/connect` builds, now hit directly rather than just noted.
- **Acceptance:** From a clean checkout, `make up` followed by `make dbt-debug` runs `dbt debug` inside the container and reports all checks passing (profile found, connection OK, no version mismatch treated as fatal) against `warehouse-postgres`. `make dbt-run` (with zero models defined yet) completes successfully with "0 of 0 models" rather than erroring. `dbt source freshness` or a simple `select * from {{ source('raw', 'files') }}` compiles and executes against the real `raw_files` table, proving the source declaration resolves to the actual warehouse schema, not just a config that parses.
- **Dependencies:** M2.4 (`warehouse-postgres` exists); M2.5/M2.6 (the 4 Raw tables + their `_cdc_*` columns exist, for the source declaration to point at).
- **Out-of-scope:**
  - Any staging/intermediate/marts models — M3.2 onward.
  - dbt tests (`dbt test`) on sources or models — nothing to test yet with zero models; introduced alongside the first real model.
  - A dedicated `raw` schema in the warehouse — Raw tables stay in `public` (where M2.5 put them); the dbt source declaration points at `public`, not a renamed schema. Revisit only if staging/intermediate's own schema needs force a reorganization.
  - dbt packages / `packages.yml` (e.g. `dbt_utils`) — add only if a specific model in M3.2+ actually needs one.
- **Automated Test Plan:**
  - *Integration:* `tests/integration/test_dbt_scaffold.sh` — brings the stack up, runs `docker compose run --rm dbt debug` and asserts a zero exit code and no "ERROR" in output; runs `docker compose run --rm dbt run` and asserts it completes (0 models, not a failure); runs a one-off `dbt show` (or equivalent compiled query) against the `raw` source's `files` table and asserts it returns the seeded/simulated row count, proving the source resolves to live data.
- **Manual Test Plan:**
  - `make up`, `make dbt-debug` — confirm all checks pass, in particular the connection check against `warehouse-postgres`.
  - Inspect `warehouse/dbt/models/staging/__sources.yml` — confirm all 4 Raw tables are declared with their actual column names matching `warehouse/ddl/`.
  - `make register-connector` — confirm both `ods-source` and `warehouse-raw-sink` are reported `RUNNING` (connector and task); without this step no data reaches the warehouse and `dbt show` below would return 0, not 1.
  - `make simulate COUNT=1`, then `docker compose run --rm dbt show --inline "select count(*) from {{ source('raw','files') }}"` (run inside the `dbt` container, not the host — there is no `~/.dbt` profile on the host; `DBT_PROFILES_DIR` is only set for the container) — confirm the count reflects the real row.
- **Amended implementation (D015):** After M3.1 merged, the project adopted dbt-native project structure as its standard (`models/staging/`, `models/intermediate/`, `models/marts/`; `stg_`/`int_`/`fct_`/`dim_` naming; medallion terms kept only as a cross-reference — see [D015](Decisions.md#d015)). M3.1's one structural conflict with that standard is corrected here, scoped to M3.1's own artifacts: the source declaration moved from `warehouse/dbt/models/sources.yml` to its dbt-native home `warehouse/dbt/models/staging/__sources.yml` (content unchanged; the `raw` source still resolves, verified by `test_dbt_scaffold.sh`). Everything else M3.1 built is convention-agnostic and unchanged. This change also updates `Technical-Design.md` to document the new standard (§3 layer rename + medallion cross-reference map). The remaining applications of D015 — the `stg_`/`int_`/`fct_` model *implementations* and per-folder materialization defaults in `dbt_project.yml` — are **not** in this amendment; they belong to M3.2 and its own change, since they concern models that do not exist yet.

**M3.2 — Staging models**
- **Test:** Staging models (`stg_*`) deduplicate redelivered Kafka records and resolve out-of-order arrival by `_cdc_ts`, producing one current row per `file_id` / `file_action_id`
- **Acceptance:** `dbt test` on the staging models enforces uniqueness on the entity key; a manually duplicated Raw row collapses to one staging row

**M3.3 — Intermediate models**
- **Test:** Intermediate models (`int_*`) join `file_actions` to `files` and `parties`, deriving step number and party role per step
- **Acceptance:** Intermediate row count equals the staging `file_actions` row count (1:1); every row resolves a non-null step number and role

**M3.4 — Marts: turnaround (U1)**
- **Test:** The marts layer computes per-step turnaround (`received_at − sent_at`) in `fct_step_turnaround` and aggregates (mean, p90) by step in `agg_step_turnaround`, for closed/live/positive-duration steps only (FR-3)
- **Acceptance:** Hand-computed turnaround for the M1.2 seed file matches the marts output exactly

### M4: Governed analyst surface

**M4.1 — Analyst query interface**
- **Test:** SQL view/query interface exposes `agg_step_turnaround` (mean, p90, count by step) with no per-file or per-party detail
- **Acceptance:** Analyst can answer U1 ("average and 90th-percentile turnaround by step, for closed files") in one query

**M4.2 — PII exclusion**
- **Test:** Inspect the marts layer's analyst-facing views for any user, name, email, or file-identifying column
- **Acceptance:** No such column exists in the view definition (verified by construction, not just by convention — NFR-2)

### M5: Party-scoped consumer surface

**M5.1 — RLS policies on the marts layer**
- **Test:** PostgreSQL row-level security policies applied to marts tables, scoping rows to the requesting `party_id`
- **Acceptance:** Policies exist and are enabled (`rowsecurity = true`) on every party-facing marts table

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
- **Test:** Airflow DAG runs `dbt build` (staging → intermediate → marts) on an interval short enough to leave headroom in the 10-minute freshness budget
- **Acceptance:** DAG runs succeed on schedule; the marts layer reflects new Raw data after each run

**M6.3 — End-to-end freshness**
- **Test:** Commit a simulated write to the ODS; measure time until it is visible in the analyst marts view (NFR-1, [§7 success metrics](Requirements.md#7-success-metrics))
- **Acceptance:** Measured lag is ≤ 10 minutes across at least 3 trials; the dominant latency source (dbt run interval) is documented

### M7: Expand simulator to full workflow

**M7.1 — Expand to full 12-step workflow**
- **Test:** Once M1–M6 are verified end-to-end on the truncated workflow, re-seed and re-run the simulator against the full 12-step model
- **Acceptance:** All downstream milestones (M2–M6) continue to pass unchanged against the full workflow — the truncation should not have required pipeline changes, only additional `file_actions` rows and `action_code` values
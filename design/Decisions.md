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

## D007 — ODS logical replication for Debezium; renamed init files for ordering (2026-07-14)

**Change:** `change/m2.1-logical-replication`

**Motivation.** M2.1 needs the ODS configured for CDC — `wal_level=logical`, a publication, and a logical replication slot — ready for Debezium to consume in M2.3, without yet standing up Kafka/Debezium themselves.

**Design delta:** `design/Milestones.md` M2.1 expanded to the full template; its 3 active references to `ods/ddl/schema.sql` updated to `001_schema.sql` (in `tests/check_structure.sh`, `tests/integration/test_schema_init.sh`, and Milestones' own M1.1 section). D004 (historical) left untouched, since it accurately described the file's name at the time it was written.

**Artifacts:** `ods/ddl/001_schema.sql` (renamed from `schema.sql`), `ods/ddl/002_replication.sql` (new — publication + slot). `docker-compose.yml` — `command: ["postgres", "-c", "wal_level=logical"]` on `ods-postgres`. `tests/integration/test_replication.sh`.

**Reversal:** if a second replication slot/publication is ever needed (e.g. a second consumer), add `003_...` rather than editing `002_replication.sql` in place, preserving the numbered-ordering convention.

**Validation:** choices and rejected alternatives —
- **Renamed `schema.sql` → `001_schema.sql`, added `002_replication.sql`**, exactly as D004's reversal note anticipated when M1.1 was built ("name files accordingly — `001_...`, `002_...`"). Rejected a subdirectory-based ordering trick — `docker-entrypoint-initdb.d` does not recurse into subdirectories, so numbered top-level files are the only mechanism Postgres's own init process actually supports.
- **`wal_level=logical` via a compose `command:` override, not `ALTER SYSTEM` from SQL.** `wal_level` is a postmaster-context setting — changing it via `ALTER SYSTEM` only takes effect after a restart, whereas the command-line override applies from the very first server start, avoiding a two-step "start, configure, restart" dance for a fresh container.
- **`pgoutput` plugin for the real slot (`dbz_slot`), matching Debezium's own default/recommended choice** — no separate Postgres extension needed (unlike `wal2json`), consistent with Technical-Design.md §2's CDC component choice.
- **A separate, temporary `test_decoding`-plugin slot to verify "decodable WAL change," not the real `pgoutput` slot.** `pgoutput` emits a binary, protocol-specific format meant for a logical-replication-aware consumer (Debezium); asserting meaningful content from it via plain SQL isn't practical. `test_decoding` produces human-readable output assertable via `grep`, giving genuine proof that logical decoding works end-to-end — not just "some bytes came out" — while leaving `dbz_slot` unconsumed for M2.3.
- **No explicit `max_wal_senders`/`max_replication_slots` override** — the base image's defaults (10 each) comfortably exceed this example's single-slot need; added config surface without a present need would be speculative.

## D008 — Single-node Kafka broker: apache/kafka, KRaft, dual listeners (2026-07-14)

**Change:** `change/m2.2-kafka`

**Motivation.** M2.2 needs a working Kafka broker for Debezium (M2.3) to eventually publish into, and for the owner's manual host-side debugging convenience.

**Design delta:** `design/Milestones.md` M2.2 expanded to the full template.

**Artifacts:** `docker-compose.yml` — new `kafka` service (`apache/kafka:latest`, KRaft combined broker+controller, dual listeners: `PLAINTEXT` for the compose network, `HOST` for the host via `KAFKA_BROKER_PORT`), `kafka_data` volume. `.env` — new `KAFKA_BROKER_PORT=9094`. `tests/integration/test_kafka.sh`.

**Reversal:** if a genuine need for Kafka Connect or another consumer surfaces a config gap not expressible via env vars, create `streaming/` then (not now) and move the Kafka config there as needed.

**Validation:** choices and rejected alternatives —
- **`apache/kafka` (official image), not `confluentinc/cp-kafka`.** Investigated the actual dependency chain first: the broker image and the Kafka Connect worker (M2.3) are decoupled — any Connect worker can talk to any standards-compliant broker, so the broker choice doesn't constrain the later Debezium + JDBC-sink connector plan at all. Confirmed the official image's env-var-to-`server.properties` mapping convention (`KAFKA_<PROPERTY_NAME>`) empirically by reading its actual `configure`/`configureDefaults` scripts inside the image, rather than assuming it matched Confluent's convention.
- **No explicit `CLUSTER_ID`** — the image ships a working default (`5L6g3nShT-eMCtK--X86sw`, confirmed by reading `configureDefaults` inside the image) if unset; setting our own would be unnecessary config surface.
- **`KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1`, `KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1`, `KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1`.** A single-broker cluster can't satisfy the default replication factor of 3 for Kafka's internal topics — without this override, internal topic creation hangs waiting for replicas that will never exist. A well-known single-node dev-setup requirement, included proactively rather than discovered via a hang.
- **Dual listeners (`PLAINTEXT` internal, `HOST` external), not a single listener.** A single listener advertised for host access would break internal (compose-network) clients, and vice versa — Kafka's `advertised.listeners` mechanism means clients get redirected to whatever address is advertised, so each audience needs its own listener/advertised-address pair. Verified the internal path with a real container-to-container client (`docker run --network ... kafka-topics.sh --bootstrap-server kafka:9092`); the host path was checked only via raw TCP reachability (`nc`) and not a full Kafka-protocol round trip, since no native Kafka client was available on the test host — flagged as a real, acknowledged verification gap rather than silently treated as fully proven the way D002/D004/D006/D007's issues were caught.
- **4 plain-named health-check topics (`files`, `file_actions`, `parties`, `audit_events`), not Debezium's eventual naming convention.** Debezium's connector config (`topic.prefix`) doesn't exist yet (M2.3); pre-committing to a naming scheme now would risk being wrong once that config is written. These topics only prove the broker can create/list topics — Debezium will create its own when it starts capturing.
- **`streaming/` left uncreated.** Kafka's entire KRaft configuration was expressible via `docker-compose.yml` environment variables — no Dockerfile, no custom `server.properties`, nothing to put in a folder. Creating an empty folder just because §9 anticipates it would violate the lazy-creation convention (M0.1/D001).

## D009 — Debezium Postgres source connector: distributed single worker, existing slot/publication (2026-07-14)

**Change:** `change/m2.3-debezium-connector`

**Motivation.** M2.3 needs ODS writes to actually flow onto Kafka topics as JSON, closing the gap between M2.1's replication slot/publication and M2.2's broker — both of which existed but were unconsumed until now.

**Design delta:** `design/Milestones.md` M2.3 expanded to the full template. `design/Technical-Design.md` §9 — `cdc/` flipped to `exists`.

**Artifacts:** `docker-compose.yml` — new `kafka-connect` service (`quay.io/debezium/connect:latest`, distributed mode, single worker, `CONNECT_REST_PORT` published). `.env` — new `CONNECT_REST_PORT=8083`. `cdc/debezium-postgres-source.json` — the connector config (consumes `dbz_slot`/`dbz_publication` from M2.1, `topic.prefix=ods`). `scripts/register_connector.sh` — idempotent REST registration (GET-then-POST-or-PUT). `Makefile` `register-connector` target. `tests/integration/test_debezium_connector.sh`.

**Reversal:** if distributed mode's Kafka-topic-backed state ever becomes a debugging obstacle for this single-worker case, standalone mode with a mounted properties file is the fallback — but distributed mode has caused no friction so far.

**Validation:** choices and rejected alternatives —
- **Image is `quay.io/debezium/connect`, not `docker.io/debezium/connect`.** Verified empirically before writing any compose config — `docker pull docker.io/debezium/connect` 404s; Debezium publishes to Quay, not Docker Hub. Would have been a silent draft-time assumption error if not checked first, per the established D002/D004/D006/D007/D008 pattern of verifying image behavior empirically rather than from memory.
- **Distributed mode, single worker — owner's explicit choice, offered as the recommended option over standalone.** Connector config/offsets/status live in 3 Kafka topics (`connect-configs`, `connect-offsets`, `connect-status`, replication factor 1 — same single-broker constraint as M2.2's internal topics) rather than local files, keeping the worker itself stateless outside Kafka and the declared volumes, and matching the image's officially documented usage pattern (REST API on `:8083`).
- **The image's "friendly" env vars (`BOOTSTRAP_SERVERS`, `GROUP_ID`, `CONFIG_STORAGE_TOPIC`, etc.), plus generic `CONNECT_<PROPERTY>` passthrough for the replication-factor overrides.** Confirmed via `/docker-entrypoint.sh` inside the image: any `CONNECT_`-prefixed env var is lowercased/dotted and appended to `connect-distributed.properties` verbatim, which is how `CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1` etc. get applied — the friendly vars alone don't expose a replication-factor knob.
- **Connector consumes the *existing* `dbz_slot`/`dbz_publication` from M2.1 (`publication.autocreate.mode=disabled`), rather than letting Debezium create its own.** Makes the M2.1→M2.3 dependency explicit and fail-loud (the connector errors if the publication is ever missing) instead of silently auto-creating a duplicate.
- **`topic.prefix=ods`**, giving topics named `ods.public.<table>` — plain and legible for a working example; no collision with M2.2's health-check topic names (`files`, `file_actions`, etc., unprefixed).
- **`cdc/debezium-postgres-source.json` hardcodes the ODS host/credentials matching `.env`'s committed defaults (`ods-postgres:5432`, `postgres`/`postgres`, db `ods`), rather than being templated from `.env` at registration time.** Same simplification already accepted in `scripts/seed.sh`'s shell-default fallbacks (D002-adjacent, not separately decided until now) — if a user edits `.env`'s ODS credentials, this file needs a matching manual edit. Acceptable for a local-dev working example; real secrets management is out of scope project-wide (Technical-Design.md §2/D002).
- **`scripts/register_connector.sh` runs from the host** (`curl`/`jq` against `localhost:${CONNECT_REST_PORT}`), not via `docker compose exec` into the worker container. Both `curl` and `jq` are available on the host in this environment; running from the host avoids needing either tool installed inside the `debezium/connect` image (unconfirmed) and keeps the script simple.
- **Found and fixed while building — a status-polling race:** `connector.state` can read `RUNNING` before `tasks[0].state` does (the task hasn't been assigned/started yet), so an early version of the test asserted on `connector.state` alone, checked `tasks[0].state` once outside the retry loop, and intermittently failed on a connector that would have reached full `RUNNING` a second later. Fixed by polling both fields together in the same retry loop until both read `RUNNING`.
- **Found and fixed while building — `kafka-console-consumer.sh --timeout-ms 2000` was too tight for a first connection.** The consumer's initial metadata fetch + fetch round-trip on a freshly created topic sometimes exceeded 2 seconds, causing `TimeoutException` and zero messages read even though the message existed and a longer timeout consumed it immediately. Fixed by raising the per-attempt timeout to 5000ms (the surrounding 30-iteration retry loop already tolerates the extra latency).
- **Manual restart check (`docker compose restart kafka-connect`, not `make down`) showed a brief `UNASSIGNED` connector-level state during the worker's post-restart rebalance before settling back to `RUNNING`.** Noted explicitly in Milestones.md's manual test plan rather than claiming instant, error-free restart persistence the way M2.2 could for a stateless broker — Connect's rebalance protocol has a real, if brief, transitional window.

## D010 — Warehouse Postgres: second instance, generalized port-conflict diagnosis (2026-07-14)

**Change:** `change/m2.4-warehouse-postgres`

**Motivation.** M2.4 needs a second, genuinely separate Postgres instance for the warehouse (Raw/Silver/Gold/Mart, starting M2.5), physically distinct from the ODS so CDC can never add load to the write primary (FR-2) by construction, not just by convention.

**Design delta:** none beyond what M2.4's draft already specified in `design/Milestones.md`.

**Artifacts:** `docker-compose.yml` — new `warehouse-postgres` service (`postgres:16-alpine`, own `warehouse_data` volume, own port), no schema mounted. `.env` — new `WAREHOUSE_POSTGRES_PORT/DB/USER/PASSWORD`, following the `ODS_`/`WAREHOUSE_` prefix split D002 anticipated. `scripts/compose_up.sh` — generalized from an ODS-only port check to a per-service check (see bug below). `tests/integration/test_warehouse_postgres.sh` — isolation check. `tests/integration/test_port_conflict.sh` — extended to cover both services.

**Reversal:** if a warehouse-specific quirk emerges that the ODS's config doesn't share, split its compose block further rather than trying to keep the two services in lockstep for its own sake.

**Validation:** choices and rejected alternatives —
- **Second full Postgres instance, not a second schema/database on the same server.** The milestone's whole point (FR-2) is physical isolation of write load — a second schema on the same instance would still let warehouse query load compete with ODS write load for the same server's resources, defeating the purpose. Verified in the integration test as "no `files` table exists in the warehouse at all," not just "a query returned 0 rows," which could be true of an empty table on a shared instance.
- **No schema applied to the warehouse yet.** Raw tables are the JDBC sink connector's concern (M2.5); mounting a DDL file here now would be speculative ahead of that connector's actual column/type requirements.
- **`warehouse/` left uncreated**, same lazy-creation reasoning as M2.2's `streaming/` — this milestone's entire config is expressible via `docker-compose.yml`/`.env`.
- **Found and fixed while building — `scripts/compose_up.sh`'s port-conflict diagnosis became silently wrong once a second service was added.** The retry loop calls `docker compose down -v` on any conflict before deciding whether to retry or report; the original single-service `port_is_bound()` check, if evaluated post-teardown, would find *every* service unbound regardless of which one actually conflicted — so generalizing it naively would have made `make up` always claim both `ODS_POSTGRES_PORT` and `WAREHOUSE_POSTGRES_PORT` were conflicting, even for a single-port conflict. Confirmed this manually by occupying only `WAREHOUSE_POSTGRES_PORT` and observing the (wrong) dual-port message before the fix. Fixed by capturing each service's binding state immediately after `up -d`, before any teardown, and passing those captured booleans into the diagnosis function. `tests/integration/test_port_conflict.sh` now pins both directions — an ODS-only conflict must not mention `WAREHOUSE_POSTGRES_PORT`, and vice versa.

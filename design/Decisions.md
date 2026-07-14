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
- **`make up` / `make down`, not bare `docker compose` commands, as the documented entrypoint.** Docker's own port-bind error is a daemon-level message with no reference to `.env` or which setting to change, and can't be customized from `docker-compose.yml` itself; a thin wrapper is the only way to make the *actual* user-facing command give an actionable message. Rejected a standalone shell script (`scripts/up.sh`) as the primary interface — `make` is the more conventional, discoverable entrypoint, and this sets the pattern M0.4 extends with a `test` target.
- **Port-conflict detection by inspecting the actual network binding, not the `up -d` exit code.** Manual testing surfaced a real bug: `docker compose up -d` can exit 0 even when the host port failed to publish — the container starts, but `NetworkSettings.Ports` for that port is silently `[]`. The original implementation only grepped `up -d`'s captured output for "port is already allocated," which is absent in this failure mode, producing a false-positive green in exactly the scenario a real user hit. Fixed by checking `docker inspect`'s `NetworkSettings.Ports` for a non-empty binding after `up -d` returns, regardless of its exit code, and treating an empty binding the same as an explicit bind error. `tests/integration/test_port_conflict.sh` pins this behavior against a real, independently-running occupant container (not another `docker compose up`, since that was the case that produced the false positive).
- **Shared `scripts/compose_up.sh` / `compose_down.sh`, called by both `make up` and the integration test**, rather than duplicating the retry/detection logic in each. One place owns "how do we know the port bound successfully."

# Technical Design — Workflow Metrics Platform

**Status:** Draft · **Owner:** Michael Leslie · **Last updated:** 2026-07-14

> This is a living document. It outlines rough implementation choices for each component. Design decisions are recorded in [Decisions.md](Decisions.md). Iteration happens at the milestone level.

---

## 1. Architecture overview

End-to-end flow: **simulator → ODS → CDC (Debezium/Kafka) → raw landing → dbt transforms (staging → intermediate → marts) → governed read-only consumers**.

```
┌───────────────────┐
│  Python simulator │  (generates file / file_action writes)
└─────────┬─────────┘
          ▼
┌───────────────────┐
│   PostgreSQL ODS  │  (files, file_actions, audit_events; write source)
│   (single DB)     │
└─────────┬─────────┘
          │ logical decoding (WAL)
          ▼
┌───────────────────┐
│     Debezium      │  (Kafka Connect source connector)
│  (Postgres → Kafka)│
└─────────┬─────────┘
          │ JSON, no schema registry
          ▼
┌───────────────────┐
│  Kafka (KRaft)    │  (topics: one per source table)
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Kafka Connect      │  (JDBC sink connector)
│  JDBC Sink         │
└─────────┬─────────┘
          ▼
┌─────────────────────────────────────────────┐
│         Warehouse PostgreSQL (separate       │
│              instance from ODS)              │
│                                               │
│  Raw  ──dbt──▶  staging  ──dbt──▶  intermediate  ──▶  marts │
└──────────────────────┬────────────────────────┘
                        │
                  (orchestrated by Airflow:
                   simulator cadence + dbt run schedule)
                        │
             ┌──────────┴───────────┐
             ▼                      ▼
      ┌──────────────┐      ┌──────────────────┐
      │   Analyst    │      │  Party consumer  │
      │  (no PII)    │      │  (row-scoped)    │
      └──────────────┘      └──────────────────┘
```

Debezium's Postgres source connector (M2.3) captures ODS writes in two distinct
phases, each with its own state at the ODS, Kafka Connect, and Kafka layers:

- [Snapshot phase](diagrams/snapshot-phase.png) — the one-time initial read of rows that existed before the connector first started.
- [Streaming phase](diagrams/streaming-phase.png) — ongoing, incremental capture of new writes via WAL logical decoding.

---

## 2. Component choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Simulator | Python | Generates simulated file / file_action writes against the ODS on a schedule |
| ODS | PostgreSQL (single database) | Source of truth; `wal_level=logical` enables CDC |
| CDC capture | Debezium (Postgres source connector, Kafka Connect) | Mature, open-source; reads the WAL via logical decoding and publishes row changes to Kafka |
| Streaming backbone | Kafka, KRaft mode (no Zookeeper) | Fewer moving parts to stand up than Zookeeper-based Kafka; one topic per source table |
| Serialization | Plain JSON, no schema registry | Simplest to run for a working example; schema evolution is manual (acceptable trade-off given NFR-4) |
| Raw landing | Kafka Connect JDBC sink connector → warehouse PostgreSQL | Writes Kafka topic records into raw tables; separate instance from the ODS so CDC never adds load to the write primary (FR-2) |
| Transform (staging/intermediate/marts) | dbt, single project against the warehouse PostgreSQL | Declarative, version-controlled, testable; layers raw sources → conformed (staging) → business/dimensional (intermediate) → governed marts (served) |
| Orchestration | Airflow | Schedules the Python simulator's write cadence and the dbt run interval; Debezium and Kafka Connect run as always-on services outside Airflow's control |
| Governance | Row-level security (RLS) via PostgreSQL policies on the marts layer | Native to PostgreSQL; scopes each party to their file(s) at the served layer |
| Analyst consumer | SQL query interface (DBeaver / psql) against the marts layer | Simple read-only access; no PII visible by view definition |
| Party consumer | REST API + RLS (mocked auth) against the marts layer | Read-only; returns only the party's own file(s) |

**Assumption — no hard deletes.** `files` and `file_actions` are append-only / status-driven (a file's `status` changes, rows are not deleted). This sidesteps JDBC sink tombstone-record handling, which otherwise requires the Debezium connector to emit tombstones on delete and the sink to be configured with `delete.enabled` and a primary key. Revisit if the ODS model ever hard-deletes a row.

---

## 3. Data model

### ODS schema (source, writable)

```sql
files (
  file_id           bigint PK,
  file_number       varchar,
  status            varchar,        -- WIP, CLOSED
  opened_at         timestamptz,
  closed_at         timestamptz,
  county_fips       varchar,
  product_type      varchar,        -- REFINANCE, PURCHASE, etc.
)

file_actions (
  file_action_id    bigint PK,
  file_id           bigint FK,
  action_code       varchar,        -- APPLICATION_SUBMIT, DISCLOSURES_ACK, …
  action_type       varchar,        -- Start, Complete
  sent_at           timestamptz,
  received_at       timestamptz,
  sent_user_id      bigint,
  received_user_id  bigint,
  live_flag         boolean,
)

parties (
  party_id          bigint PK,
  file_id           bigint FK,
  role              varchar,        -- borrower, loan_officer, loan_processor, …
  user_id           bigint,         -- Autoclose user, if applicable
)

audit_events (
  audit_event_id    bigint PK,
  file_id           bigint FK,
  user_id           bigint,
  event_type        varchar,
  description       text,
  created_at        timestamptz,
)
```

### Warehouse layers (dbt-native; medallion cross-reference)

The warehouse follows dbt's native layering as the project standard. Medallion (Bronze/Silver/Gold) terms are retained only as a cross-reference — the mapping is deliberately many-to-one, not 1:1 (see [D015](Decisions.md#d015)):

| dbt layer | Location / prefix | Materialization | Medallion |
|-----------|-------------------|-----------------|-----------|
| sources | `raw` (JDBC-sink-landed tables) | — (landed) | Bronze |
| staging | `models/staging/stg_*` | view | Silver |
| intermediate | `models/intermediate/int_*` | view | Silver |
| marts | `models/marts/fct_*`, `dim_*` | table | Gold |

### Raw layer schema — dbt `sources` (JDBC-sink landed, read-only)

Mirrors ODS schema; append-only landing for Debezium change events written by the Kafka Connect JDBC sink. Declared to dbt as the `raw` source (not a model). Tracks `_cdc_op` (INSERT/UPDATE/DELETE, though deletes are not expected — see assumption above), `_cdc_ts` (Debezium event timestamp), `_sink_ts` (JDBC sink write timestamp).

### Staging layer (dbt, `stg_` — conformed)

Cleaned, deduplicated, typed versions of the raw tables — one row per business entity, latest state per `file_id` / `file_action_id`. Deduplicates any redelivered Kafka records (at-least-once delivery) and resolves out-of-order arrival by `_cdc_ts`. Materialized as views.

### Intermediate layer (dbt, `int_` — business/dimensional)

Joins `file_actions` to `files` and `parties`; derives step-level facts (open/closed, step number from `action_code`, party role). One row per step per file. Materialized as views.

### Marts layer (dbt, `fct_`/`dim_` — governed, final served layer)

```sql
-- M3: Turnaround metric
fct_step_turnaround (
  file_id           bigint,
  action_code       varchar,
  step_number       int,
  turnaround_sec    int,            -- received_at - sent_at
  step_open_at      timestamptz,
  step_close_at     timestamptz,
  file_status       varchar,
)

-- Aggregates (analyst view, no PII)
agg_step_turnaround (
  action_code       varchar,
  step_number       int,
  mean_turnaround_sec int,
  p90_turnaround_sec int,
  count_steps       int,
)
```

RLS policies are applied at the marts layer only — the `raw` sources, staging, and intermediate layers are internal to the pipeline and never queried directly by either consumer.

---

## 4. Freshness and timing

**Success metric (NFR-1):** Source commit → viewable in metric ≤ 10 minutes.

```
Source write (0s)
    ↓
Debezium capture (< 1s, logical decoding)
    ↓
Kafka publish (< 1s)
    ↓
JDBC sink → Raw land (seconds, connector poll interval)
    ↓
Airflow-scheduled dbt run: Raw → staging → intermediate → marts (must fit remaining budget)
    ↓
Consumer query (instant)
    ↓
Total: < 10min ✓ — dbt run interval is the controlling variable; it must be
scheduled tightly enough (e.g. every 2–5 min) to leave headroom for Debezium/
Kafka/JDBC-sink lag (typically seconds) within the 10-minute budget.
```

---

## 5. Governance and PII

**Principle:** No other party's PII by construction.

- **Analyst surface:** Views on turnaround metrics; user/email/name columns excluded by view definition
- **Party consumer:** Row-level security policies; user logged in as a `party_id`, queries return only `files` they are on
- **Audit events:** Not exposed to consumers; internal only

---

## 6. Milestones → architecture mapping

| Milestone | ODS | Debezium/Kafka | Raw | staging/intermediate | marts | Consumer | Test |
|-----------|-----|-----------------|-----|--------------|------|----------|------|
| M1 | ✓ | — | — | — | — | — | ODS query |
| M2 | ✓ | ✓ | ✓ | — | — | — | Raw table consistency |
| M3 | ✓ | ✓ | ✓ | ✓ | ✓ | — | Metric correctness |
| M4 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ analyst | No PII in results |
| M5 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ party | Row-level security |
| M6 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | < 10 min lag |

---

## 7. Open design questions

To be resolved as decisions.

- **dbt run interval:** Exact Airflow schedule for the Raw → staging → intermediate → marts job (e.g. every 2 min vs. 5 min) — sets how much of the 10-minute NFR-1 budget is consumed by transform latency vs. left as headroom.
- **Party auth mocking:** How do we mock Autoclose user login for the party consumer without real auth infrastructure?
- **Seed data size:** How many files and steps for realistic throughput / latency testing?
- **Kafka Connect deployment:** Standalone or distributed mode for the working example? Distributed is more realistic but adds a Connect cluster to manage; standalone is simpler for a single-node demo.
- **dbt materialization strategy:** ~~Views, tables, or incremental models for each layer?~~ *Resolved ([D015](Decisions.md#d015)):* staging and intermediate as views, marts as tables; incremental deferred until data volume warrants it. Revisit only if `dbt run` duration threatens the freshness budget.

---

## 8. Dependencies and unknowns

- PostgreSQL version and replication slot / publication configuration for Debezium (version ≥ 10 for logical decoding; `wal_level=logical`)
- Debezium and Kafka Connect versions, and whether Kafka Connect runs standalone or distributed
- dbt Core (local CLI) vs. dbt Cloud — assume dbt Core for a self-contained, one-command reproducible example (NFR-4)
- Airflow deployment: LocalExecutor is sufficient for this working example's scale; needs its own metadata Postgres, separate from both the ODS and the warehouse
- External visualization tool for analyst, or simple SQL query output?

---

## 9. Repository layout

This project is a monorepo: one top-level folder per pipeline component, named after
its [§2](#2-component-choices) component. This is a **living map** — folders are
created lazily by the milestone that first needs them (nothing speculative), and the
**Status** column flips from `planned` to `exists` as each is created. Folders are not
tied to specific milestone numbers here — see [Milestones.md](Milestones.md) for which
milestone creates each one, so this table doesn't need editing every time the milestone
sequence is reordered.

| Folder | Component ([§2](#2-component-choices)) | Status |
|--------|-----------------------------------------|--------|
| `ods/` | PostgreSQL ODS (source DDL, seed data) | exists |
| `simulator/` | Python simulator | exists |
| `cdc/` | Debezium source connector + JDBC sink connector configs | exists |
| `warehouse/` | Warehouse PostgreSQL + dbt project (Raw → staging → intermediate → marts) | exists |
| `orchestration/` | Airflow DAGs | planned |
| `consumers/` | Analyst query surface + party REST API | planned |

**Conventions:**
- **Lazy creation** — a component folder appears only when its milestone is built; its
  Status flips to `exists` at that point.
- **Test co-location** — each component holds its own tests in its native form
  (`ods/tests/` SQL assertions, `simulator/tests/` stdlib `unittest` — no pytest
  dependency needed for pure-logic unit tests, dbt tests inside `warehouse/`).
  Cross-component and repo-meta tests (the repository structure check, end-to-end
  freshness) live at the repository root under `tests/`.
- **Root** — holds `docker-compose.yml` and the single-command test runner.

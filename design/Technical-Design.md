# Technical Design — Workflow Metrics Platform

**Status:** Draft · **Owner:** Michael Leslie · **Last updated:** 2026-07-14

> This is a living document. It outlines rough implementation choices for each component. Design decisions are recorded in [Decisions.md](Decisions.md). Iteration happens at the milestone level.

---

## 1. Architecture overview

End-to-end flow: **ODS source → CDC capture → raw layer → metrics compute → governed read-only consumers**.

```
┌─────────────────┐
│  PostgreSQL ODS │  (files, file_actions, audit_events; write source)
│  (single DB)    │
└────────┬────────┘
         │ (changes)
         ▼
┌─────────────────┐
│      CDC        │  (logical decoding, replication slot)
│   (capture log) │
└────────┬────────┘
         │ (row changes: INSERT, UPDATE, DELETE)
         ▼
┌─────────────────┐
│  Raw / staging  │  (append-only landing; mirrors ODS schema)
│   (PostgreSQL)  │
└────────┬────────┘
         │ (cleaned, deduplicated)
         ▼
┌─────────────────┐
│  Metrics layer  │  (computed, governed; turnaround, SLA status)
│   (PostgreSQL)  │
└────────┬────────┘
         │
    ┌────┴────────────────┐
    ▼                     ▼
┌──────────────┐   ┌──────────────────┐
│   Analyst    │   │  Party consumer  │
│  (no PII)    │   │ (row-scoped)     │
└──────────────┘   └──────────────────┘
```

---

## 2. Component choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| ODS | PostgreSQL (single database) | Source of truth; supports logical decoding for CDC |
| CDC | PostgreSQL logical decoding + replication slots | Built-in, no external tool; low operational burden |
| Raw layer | PostgreSQL (same instance as metrics) | Simplifies cross-layer queries; one PostgreSQL instance for this working example |
| Metrics compute | SQL views + materialized views (or dbt models) | Declarative, version-controlled, reproducible |
| Governance | Row-level security (RLS) via PostgreSQL policies | Native to PostgreSQL; scopes each party to their file(s) |
| Analyst consumer | SQL query interface (DBeaver / psql) | Simple read-only access; no PII visible by view definition |
| Party consumer | REST API + RLS (mocked auth) | Read-only; returns only party's own file(s) |

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

### Raw layer schema (CDC-landed, read-only)

Mirrors ODS schema; append-only landing for CDC changes. Tracks `_cdc_op` (INSERT/UPDATE/DELETE), `_cdc_lsn` (log sequence number), `_cdc_ts` (capture timestamp).

### Metrics schema (computed, governed)

```sql
-- M3: Turnaround metric
step_turnaround_daily (
  file_id           bigint,
  action_code       varchar,
  step_number       int,
  turnaround_sec    int,            -- received_at - sent_at
  step_open_at      timestamptz,
  step_close_at     timestamptz,
  file_status       varchar,
)

-- Aggregates (analyst view, no PII)
step_turnaround_summary (
  action_code       varchar,
  step_number       int,
  mean_turnaround_sec int,
  p90_turnaround_sec int,
  count_steps       int,
)
```

---

## 4. Freshness and timing

**Success metric (NFR-1):** Source commit → viewable in metric ≤ 10 minutes.

```
Source write (0s)
    ↓
CDC capture (< 1s, logical decoding)
    ↓
Raw land (< 1s)
    ↓
Metric compute (< 5min, scheduled or triggered)
    ↓
Consumer query (instant)
    ↓
Total: < 10min ✓
```

---

## 5. Governance and PII

**Principle:** No other party's PII by construction.

- **Analyst surface:** Views on turnaround metrics; user/email/name columns excluded by view definition
- **Party consumer:** Row-level security policies; user logged in as a `party_id`, queries return only `files` they are on
- **Audit events:** Not exposed to consumers; internal only

---

## 6. Milestones → architecture mapping

| Milestone | ODS | CDC | Raw | Metrics | Consumer | Test |
|-----------|-----|-----|-----|---------|----------|------|
| M1 | ✓ | — | — | — | — | ODS query |
| M2 | ✓ | ✓ | ✓ | — | — | Raw table consistency |
| M3 | ✓ | ✓ | ✓ | ✓ | — | Metric correctness |
| M4 | ✓ | ✓ | ✓ | ✓ | ✓ analyst | No PII in results |
| M5 | ✓ | ✓ | ✓ | ✓ | ✓ party | Row-level security |
| M6 | ✓ | ✓ | ✓ | ✓ | ✓ | < 10 min lag |

---

## 7. Open design questions

To be resolved as decisions.

- **Metric compute trigger:** Scheduled job (cron), streaming trigger, or on-demand? Trade-off: latency vs. cost.
- **dbt or raw SQL?** Version control and testing ease vs. simplicity for a working example.
- **Party auth mocking:** How do we mock Autoclose user login for the party consumer without real auth infrastructure?
- **Seed data size:** How many files and steps for realistic throughput / latency testing?
- **Materialized view refresh:** Full refresh or incremental? Cadence?

---

## 8. Dependencies and unknowns

- PostgreSQL version and replication slot configuration (version ≥ 10 for logical decoding)
- dbt Cloud / local dbt CLI decision
- External visualization tool for analyst, or simple SQL query output?
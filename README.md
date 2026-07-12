# Workflow metrics — platform design spike
**Candidate:** Michael Leslie
**Date:** 2026-07-10
**Session:** Doma Principal Data Platform Engineer (1 hour)

## Summary
A design spike for a title/closing **workflow-metrics platform**: model operational
workflow data into a governed mart, replicate the source Postgres between two applications,
and serve the metrics to a read-only retrieval agent. Block 1 landed a **step-grain fact**
(`fct_file_action_step`, one row per `file_action`) with **per-step turnaround** as the
cycle-time measure on closed files. Block 2 located the replication scenario as
**unidirectional cross-application data sharing** (App A writes → App B reads), which points
to logical replication over a physical whole-cluster standby. Block 3 kept the agent
**read-only over governed gold metrics** — no free SQL, PII-free by construction.

## Assumptions
- **Workflow backbone** is the order/file lifecycle; the atomic business event modeled in v1
  is a **`file_action` send/receive step**, not the whole order. (File-grain accumulating
  snapshot for open→close cycle time is backlogged, not built.)
- **Cycle time at step grain = `received_at − sent_at`.** File-level `closed_at − opened_at`
  is a degenerate constant at this grain, so it's deferred to a later file-grain fact.
- **Population = closed files only** (`files.closed_at IS NOT NULL`) with `live_flag = true`;
  null/non-positive durations are DQ violations filtered in v1 (quarantine deferred).
- **PII/NPI concentrates in `parties`** (`ssn_last4`, contact data). The consumer tier is
  **PII-free by construction** — PII is stripped at silver→gold.
- **Replication is unidirectional / active-passive:** App A is the sole writer to Database A;
  Database B receives App A's data for App B to read. App B's target is its own database, so
  it needs a **writable, selective** target — not a read-only whole-cluster standby.
- **The agent is a read-only retrieval consumer** acting as a scoped, least-privilege
  principal over governed metric views; it does not author SQL or take actions.
- **Cloud-agnostic**, described against a Databricks/Unity-Catalog + Postgres shape.

## Key decisions
_ADR-style digest. The append-only log in [design/Decisions.md](design/Decisions.md) is to be
backfilled from these (see follow-ups)._

- **Grain — step-grain fact over pre-aggregation.** One row per `file_action`; per-step
  turnaround preserves cycle-time and rework analysis. Rejected the pre-aggregated grain
  (cheaper, discards the transitions).
- **v1 population & DQ.** Closed files, `live_flag = true`, positive durations only; drop
  bad rows in v1, quarantine later — keeps the measure never-garbage before adding coverage.
- **Layering — medallion.** Bronze (raw CDC, append, replayable) → silver (conformed,
  deduped, SCD2 dims) → gold (star marts + metric views). Business logic lives in one
  predictable place.
- **Metrics defined once.** Canonical definitions (cycle time, SLA breach, WIP, throughput,
  rework) live in a semantic layer / metric views — the single source of truth for BI *and*
  the agent, not hardcoded per mart.
- **Access tiers — three, consumer is PII-free.** raw (data eng) · curated (analysts/app eng)
  · consumer (agents/BI). Enforced by UC groups + row filters/column masks.
- **Replication — logical, not physical.** For unidirectional cross-app data sharing where
  App B reads App A's data into its own writable database, logical replication (per-table
  pub/sub, cross-version-tolerant, writable target) fits; physical whole-cluster standby is
  rejected because the target is read-only and App B owns its own tables. Guard the two
  likely failure modes: **DDL is not replicated logically** (coordinate schema on both sides)
  and **replication-slot WAL retention** (a stalled consumer can fill the primary's disk).
- **Agent — read-only retrieval.** Consumes governed gold metric views via a bounded tool /
  semantic surface, scoped to identity; action-taking is a layered extension held out of v1.

## AI usage (first block only)
- **Tool used:** Claude Code (AI was permitted in Block 1).
- **Actual use:** **Not used** during the block — the modeling and governance decisions were
  reasoned and written by hand.
- **What I corrected in the output:** N/A (no AI output to correct).

## Repo map
| Path | Contents |
|------|----------|
| [docs/modeling-and-governance.md](docs/modeling-and-governance.md) | Block 1 — operational schema, layers, access tiers, mart grain |
| [docs/workflow-metrics-mart.md](docs/workflow-metrics-mart.md) | Block 1 — iterative mart build (step-grain fact DDL + metric SQL) |
| [docs/dual-postgres-replication.md](docs/dual-postgres-replication.md) | Block 2 — dual-Postgres replication design |
| [docs/pipeline-and-agent-consumption.md](docs/pipeline-and-agent-consumption.md) | Block 3 — ingest → warehouse → agent consumption path |
| [docs/doma-title-domain.md](docs/doma-title-domain.md) | Domain grounding (title/escrow lifecycle, MISMO/ALTA, metrics) |
| [design/Decisions.md](design/Decisions.md) | Append-only decision log |
| [design/Process.md](design/Process.md) | Change-unit workflow |
| docs/pipeline.png · docs/replication.png | Block 3 / Block 2 diagrams |

## Open questions / follow-ups
- **Backfill [design/Decisions.md](design/Decisions.md)** — the log is still the template; turn the
  Key decisions above into numbered D001… entries with Motivation / Reversal / Validation.
- **Fill the empty "# Actual" section** in [dual-postgres-replication.md](docs/dual-postgres-replication.md)
  with the confirmed scenario (App A write → App B read) and the logical-vs-physical call.
- **Confirm with app eng:** stage-transition timestamps are emitted reliably, `REPLICA IDENTITY`
  is set for the replicated tables, and schema changes are coordinated across A and B.
- **Confirm the metric semantics:** business-day vs. calendar, timezone, and SLA calendar —
  the correctness gotchas that make two "cycle times" disagree.
- **Confirm the agent's freshness/latency budget** (minutes-fresh assumed) and whether any
  metric ever needs a field derived from PII, so it can be stripped upstream.

# Requirements — Workflow Metrics Platform (working example)

**Status:** Draft · **Owner:** Michael Leslie · **Last updated:** 2026-07-12

> **Format.** This is a lightweight product requirements document (PRD): a short
> statement of *what* we are building and *why*, before any *how*. The section
> headings are stable; the content is filled in and revised as recorded Changes
> (see [Process.md](./Process.md)). Acronyms are spelled out on first use and
> collected in [§9 Definitions](#9-definitions).

---

## 1. Purpose & context

**Problem.** AMOD, a title and closing technology company, already makes the
clear-to-close decision on title files quickly through its application, Autoclose.
It now wants operational *visibility* into the closing workflow itself — where
files spend time and which steps are nearing or past their targets — so that
internal analysts can see it and the parties on a file can be nudged toward the
actions they owe, all without exposing sensitive customer data.

**This working example.** An end-to-end, runnable slice of the full path — a live
source database, cross-database replication, change data capture (CDC), governed
metrics, and two read-only consumers. It is grounded in the interview scenario: a
`files` / `file_actions` source, with two metrics — **per-step turnaround**
(`received_at − sent_at`) for the analyst, and per-step **service-level-agreement
(SLA) breach / at-risk status** that the agent uses to nudge the borrower.

*Grounded in a residential refinance — see
[../docs/home-refinance-closing-workflow.md](../docs/home-refinance-closing-workflow.md).
In a refinance the external customer is the **borrower**; there is no seller or
buyer's agent.*

## 2. Goals & non-goals

**Goals**
- Demonstrate the full path — source, replication, CDC, governed metric,
  consumer — on real DDL and SQL that actually run, not sketches.
- Define each metric **once** and serve it from a single source of truth.
- Serve **two** consumers from that one source: an internal **analyst** tier, and a
  read-only **agent** that nudges a party about their own file.
- Keep the served surface **free of other parties' personally identifiable
  information (PII)** by construction, and scope each party to their own file.

**Non-goals** (for this working example)
- Not a production platform — no autoscaling, multi-tenant, or full catalog.
- No action-taking — both consumers are read-only; the agent *nudges*, it does not
  take the file action or mutate the file.
- Not the whole title lifecycle — two metrics (turnaround, SLA status), not the
  full metric catalog.

## 3. Users & personas

| Persona | Needs | Tier |
|---------|-------|------|
| Analyst / operations (internal AMOD) | Slice cycle time by step; spot breaches across all files | Curated |
| Party — the borrower, nudged by the agent | See where their refinance stands; be nudged when an action they owe nears or passes its SLA | Consumer |
| Data engineer | Build and operate the replication + pipeline | Raw |

## 4. Use cases

Concrete, testable scenarios. Each drives functional requirements below.

- **U1 — Per-step turnaround (analyst).** As an analyst, I ask "average and
  90th-percentile turnaround by step, for closed files," and get a governed answer
  with no PII.
- **U2 — SLA nudge (borrower).** As the borrower logged into Autoclose, I see where
  my refinance stands and get nudged when an action *I* owe is nearing or past its
  SLA — scoped to my own file, with no other party's data visible.
- *U3 … (backlog: aging / backlog, throughput, rework)*

## 5. Functional requirements

What the system must *do*.

- **FR-1 — ODS topology & cross-database reads.** The operational store is
  PostgreSQL, split across two application databases, **DB-A** and **DB-B**. DB-B
  must be able to read all ODS records across *both* DB-A and DB-B, while mutating
  only its own records. How this cross-database read is accomplished is design-side;
  several designs may satisfy it.
- **FR-2 — Capture changes.** Land ODS changes into the raw layer via CDC, without
  adding load to a write primary.
- **FR-3 — Turnaround (U1).** Compute per-step turnaround on closed, live,
  positive-duration steps.
- **FR-4 — SLA status (U2).** Hold per-step SLA targets as a point-in-time
  (slowly-changing) dimension, and compute at-risk / breached status for open steps
  against the target in effect. The rescission period (refinance step 10) is a
  mandated wait, not an SLA-bearing step — excluded from breach and nudges.
- **FR-5 — Party-to-file scoping (U2).** Link a logged-in user to their `parties`
  records through the `user_party` bridge, and to the file(s) those parties are on,
  so a user reaches only their own file(s) — across every role they hold.
- **FR-6 — Serve.** Expose both metrics through one governed interface: the
  party-facing surface shows workflow status and nudges only, scoped to the party's
  own file, and never exposes another party's PII.

## 6. Non-functional requirements

Qualities the system must *hold*. To be quantified.

- **NFR-1 — Freshness.** A nudge is only useful in-flight, so the party-facing
  metric must be **≤ 10 minutes behind source** — a committed source change is
  viewable within 10 minutes (see [§7](#7-success-metrics)); the analyst tolerates
  more lag.
- **NFR-2 — Governance.** The served surface exposes no other party's PII by
  construction; each party is row-scoped to their own file(s).
- **NFR-3 — Correctness.** Each metric definition is single-sourced; the same
  question returns the same number for every consumer.
- **NFR-4 — Reproducibility.** The example runs from a clean checkout with one
  documented command.
- **NFR-5 — Open source.** Every stack component is open source and runs without
  paid services. The single exception is the agent's AI model, which may be paid or
  proprietary.
- *NFR-… (security, cost, query latency to quantify)*

## 7. Success metrics

How we know the example is done and correct.

- *The path runs end to end*: a committed source change is viewable in the served
  metric in **10 minutes or less** (source commit → replication → CDC → metric).
- `U1` returns a number matching a hand-computed check against seed data.
- `U2` nudges a party about a known at-risk action on their own file, and that
  party cannot see any other file or party.
- The party-facing surface cannot reach another party's PII column.

## 8. Open questions

The load-bearing unknowns that shape everything above. Each resolves into a
recorded decision.

- **Stack — partially resolved.** Open source only (NFR-5). The source / ODS layer
  is **PostgreSQL** (confirmed). Still to confirm — all open source: the replication
  mechanism, the CDC tool, the warehouse / transform engine, the metric layer, and
  the two consumer surfaces.
- **SLA targets — source of truth.** The current source (`files` / `file_actions`)
  has no SLA targets. Where do per-step targets come from — a source table, a
  config file, or a governance-owned dimension we introduce?
- **Party-to-user link — resolved.** The `user_party` bridge (one user ↔ many
  `party_id`s) carries it; a user can hold multiple roles across files.
- **Which party is nudged — resolved (refinance).** The borrower. In a refinance the
  borrower owns every customer-side action (apply, acknowledge disclosures, supply
  documents, clear conditions, review the Closing Disclosure, sign). Resolve the open
  action's users (`sent_user_id`, `received_user_id`) through `user_party`; the
  borrower's party is the nudge target. At-risk actions awaiting AMOD staff or a
  vendor (appraisal, underwriting, title) are bottlenecks for the **analyst**, not
  borrower nudges.
- **At-risk — the threshold.** Define "at risk of breaching" — e.g., a still-open
  step that has consumed ≥ N% of its SLA (proposed: 80%).
- **Open-step modeling.** SLA status is about *in-flight* steps, so U2 keeps the
  open steps (`received_at IS NULL`) that per-step turnaround (closed only) drops.
  Confirmed direction; a full file-grain accumulating snapshot stays deferred.
- **Freshness budget — resolved.** ≤ 10 minutes end to end (source commit → viewable
  metric); see [§7](#7-success-metrics) and NFR-1.

## 9. Definitions

- **ALTA** — American Land Title Association; title-industry data standards.
- **BI** — business intelligence (dashboards and reporting tools).
- **CDC** — change data capture; streaming row-level changes out of a database.
- **DB-A / DB-B** — the two application PostgreSQL databases that make up the ODS.
- **DDL** — data definition language (the `CREATE TABLE` half of SQL).
- **GLBA** — Gramm–Leach–Bliley Act; U.S. law governing financial-data privacy.
- **MISMO** — Mortgage Industry Standards Maintenance Organization; the mortgage
  data dictionary and schema standard.
- **NPI** — nonpublic personal information (the data class GLBA protects).
- **ODS** — operational data store; the live application database we source from.
- **PII** — personally identifiable information.
- **PRD** — product requirements document (this file's format).
- **SLA** — service-level agreement; a per-step or per-stage time target.
- **SQL** — structured query language.
- **WIP** — work in progress (open, unfinished files).

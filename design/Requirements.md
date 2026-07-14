# Requirements — Workflow Metrics Platform (working example)

**Status:** Draft · **Owner:** Michael Leslie · **Last updated:** 2026-07-12

> **Format.** This is a lightweight product requirements document (PRD): a short
> statement of *what* we are building and *why*, before any *how*. The section
> headings are stable; the content is filled in and revised as recorded Changes
> (see [Decisions.md](Decisions.md)). Acronyms are spelled out on first use and
> collected in [§10 Definitions](#10-definitions).

---

## 1. Purpose & context

**Problem.** AMOD, a title and closing technology company, already makes the
clear-to-close decision on title files quickly through its application, Autoclose.
It now wants operational *visibility* into the closing workflow itself — where
files spend time and which steps are nearing or past their targets — so that
internal analysts can watch process health across all files, and the party
accountable for each late step can be nudged toward the action they owe, all
without exposing sensitive customer data.

**This working example.** An end-to-end, runnable slice of the full path — a live
source database, cross-database replication, change data capture (CDC), governed
metrics, and two read-only consumers. It is grounded in the interview scenario: a
`files` / `file_actions` source, with two metrics — **per-step turnaround**
(`received_at − sent_at`) for the analyst, and per-step **service-level-agreement
(SLA) breach / at-risk status** that the agent uses to nudge the party accountable
for the step.

*Grounded in a residential refinance — see
[Home-Refinance-Workflow.md](Home-Refinance-Workflow.md).
In a refinance the external customer is the **borrower**; there is no seller or
buyer's agent.*

## 2. Goals & non-goals

**Goals**
- Demonstrate the full path — source, replication, CDC, governed metric,
  consumer — on real DDL and SQL that actually run, not sketches.
- Define each metric **once** and serve it from a single source of truth.
- Serve **two** consumers from that one source: an internal **analyst** tier that
  watches process health across all files, and a read-only **agent** that nudges the
  party accountable for a late step.
- Keep the served surface **free of other parties' personally identifiable
  information (PII)** by construction, and scope each party to their own file(s).

**Non-goals** (for this working example)
- Not a production platform — no autoscaling, multi-tenant, or full catalog.
- No action-taking — both consumers are read-only; the agent *nudges*, it does not
  take the file action or mutate the file.
- Not the whole title lifecycle — two metrics (turnaround, SLA status), not the
  full metric catalog.

## 3. Users & personas

| Persona | Needs | Tier |
|---------|-------|------|
| Analyst / operations (internal AMOD) | Watch process health across all files — turnaround by step, breaches, bottlenecks | Curated |
| Party (an Autoclose user on a file: borrower or a professional) | See their file's status; be nudged when a step they are Accountable for nears or passes its SLA | Consumer |
| Data engineer | Build and operate the replication + pipeline | Raw |

## 4. Use cases

Concrete, testable scenarios. Each drives functional requirements below.

- **U1 — Per-step turnaround (analyst).** As an analyst, I ask "average and
  90th-percentile turnaround by step, for closed files," and get a governed answer
  with no PII — across all files, to watch process health.

## 5. Functional requirements

What the system must *do*.

- **FR-1 — ODS topology.** The operational store is PostgreSQL; it will support a simulated load of workflow data (files, file_actions, audit_events)
- **FR-2 — Capture changes.** Land ODS changes into the raw layer via CDC, without
  adding load to a write primary.
- **FR-3 — Turnaround (U1).** Compute per-step turnaround on closed, live,
  positive-duration steps.
- **FR-4 — Serve.** Expose FR-2 metric through one governed interface: the
  party-facing surface shows workflow status scoped to the party's
  own file(s), and never exposes another party's PII.


## 6. Non-functional requirements

Qualities the system must *hold*. To be quantified.

- **NFR-1 — Freshness.** a metric must be **≤ 10 minutes behind source** — a committed source change is
  viewable within 10 minutes (see [§7](#7-success-metrics)); the analyst tolerates
  more lag.
- **NFR-2 — Governance.** The served surface exposes no other party's PII by
  construction; each party is row-scoped to their own file(s).
- **NFR-3 — Correctness.** Each metric definition is single-sourced; the same
  question returns the same number for every consumer.
- **NFR-4 — Reproducibility.** The example runs from a clean checkout with one
  documented command.
- **NFR-5 — Open source.** Every stack component is free to use in this context
  with a preference for open source software.

## 7. Success metrics

How we know the example is done and correct.

- *The path runs end to end*: a simulated load committed on the source source is viewable in the served
  metric in **10 minutes or less** (simulated producer → source commit → CDC → metric).
- `U1` returns a number matching a hand-computed check against seed data.
  once (not repeatedly), and that party cannot see any other file or party.
- The party-facing surface cannot reach another party's PII column.

## 8. Assumptions and workflow model

Foundational assumptions the requirements rest on. New assumptions are added here as
recorded Changes.

**A1 — Autoclose is the system of record.** Autoclose is authoritative for workflow
state and for every step timestamp. Metrics never infer state or time from any other
source; they read what Autoclose recorded. (Borrowers may reach Autoclose through a
partner-branded / white-labelled front end for a bank or mortgage broker; it is still
one system of record.)

**A2 — Each workflow step is a task with a conventional RACI assignment.** One
`file_actions` row models one business task, with responsibility assigned as
Responsible, Accountable, Consulted, and Informed:
- The **Responsible (R)** party performs the work. More than one R is permitted.
- The **Accountable (A)** party owns the completed outcome; there is one A per task.
- `sent_at` / `sent_user_id` record custody handed off, and `received_at` /
  `received_user_id` record custody taken up. They track who is holding the file, not
  the RACI assignment.
- **Custody passes in an unbroken chain:** the Sender of a step is the Receiver of the
  step immediately before it. Only the user currently named as a row's Sender or
  Receiver may mutate its start / completion id and time values.
- A step is **open** between `sent_at` and `received_at`. 
- Every other change to the work product (notes, signatures, uploads) is written as an
  **`audit_events`** row for the acting `user_id` — never onto the `file_actions` row.

**A5 — The terminal step closes automatically.** Step 12 has no human Receiver. Once
its Accountable party (`title_agent`) submits confirmation that the security instrument
is recorded, **Autoclose itself acknowledges receipt** — closing both the step and the
file without further human action. `files.closed_at` is set to that `received_at`. (This
implies a system service principal stands in for `received_user_id`;.)
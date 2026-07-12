# Requirements — Workflow Metrics Platform (working example)

**Status:** Draft · **Owner:** Michael Leslie · **Last updated:** 2026-07-12

> **Format.** This is a lightweight product requirements document (PRD): a short
> statement of *what* we are building and *why*, before any *how*. The section
> headings are stable; the content is filled in and revised as recorded Changes
> (see [Process.md](./Process.md)). Acronyms are spelled out on first use and
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
[../docs/home-refinance-closing-workflow.md](../docs/home-refinance-closing-workflow.md).
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
- **U2 — SLA nudge (accountable party).** As the party accountable for an open step
  (for example, the loan processor coordinating Closing Disclosure delivery), I am nudged when
  that step is nearing or past its SLA — scoped to my own file(s), with no other
  party's data visible.
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
- **FR-5 — Party-to-file scoping (U2).** Link a logged-in Autoclose user to their
  `parties` records through the `user_party` bridge, and to the file(s) those parties
  are on, so a user reaches only their own file(s) — across every role they hold.
- **FR-6 — Serve.** Expose both metrics through one governed interface: the
  party-facing surface shows workflow status and nudges only, scoped to the party's
  own file(s), and never exposes another party's PII.
- **FR-7 — Nudge delivery (U2).** Evaluate open steps on a schedule and, when a step
  crosses its at-risk threshold, write a **nudge row** for the accountable party
  (mocked push — no real email / SMS), deduplicated so a party is not re-nudged for
  the same step.

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
- **NFR-6 — Governed SLA targets.** Per-step SLA targets are governed, configurable
  reference data — versioned, not hardcoded. The actual target values are set in
  design.
- *NFR-… (security, cost, query latency to quantify)*

## 7. Success metrics

How we know the example is done and correct.

- *The path runs end to end*: a committed source change is viewable in the served
  metric in **10 minutes or less** (source commit → replication → CDC → metric).
- `U1` returns a number matching a hand-computed check against seed data.
- `U2` writes a nudge row for the correct accountable party on a known at-risk step,
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
  the RACI assignment — the Sender or Receiver of a step may be R, A, or C for that
  step, whichever party currently has custody.
- **Custody passes in an unbroken chain:** the Sender of a step is the Receiver of the
  step immediately before it. Only the party currently named as a row's Sender or
  Receiver may mutate its start / completion id and time values.
- A step is **open** between `sent_at` and `received_at`. Its Accountable party owns
  resolution and is the nudge target when it becomes at risk or breached — the
  Accountable party need not be the current Sender or Receiver (for example, step 2:
  the loan officer is Accountable, but the borrower is Receiver).
- Every other change to the work product (notes, signatures, uploads) is written as an
  **`audit_events`** row for the acting `user_id` — never onto the `file_actions` row.
- **Consulted (C)** parties supply required inputs — recorded as `audit_events`
  (modeled, not enforced). **Informed (I)** parties are notified when the step completes.

**A3 — Only Autoclose users can act.** Only an Autoclose user can record task start or
completion, or be nudged. Every Autoclose R and A is therefore a user with a `parties`
record (linked through `user_party`). An external non-user may be R in the business RACI
(a county recorder, for instance), but the assigned `title_agent` records that outcome
in Autoclose and is the step's accountable user.

**A4 — The nudge target is the Accountable party.** The A owns resolution of an open,
at-risk step and is nudged — whether the borrower or a professional party. There is no
internal analyst in the nudge path; the analyst watches process health in the aggregate
(U1).

**A5 — The terminal step closes automatically.** Step 12 has no human Receiver. Once
its Accountable party (`title_agent`) submits confirmation that the security instrument
is recorded, **Autoclose itself acknowledges receipt** — closing both the step and the
file without further human action. `files.closed_at` is set to that `received_at`. (This
implies a system service principal stands in for `received_user_id`; the ODS does not
yet model one — a follow-up for [modeling-and-governance.md](../docs/modeling-and-governance.md).)

**Worked example (step 1, Apply).** The borrower logs in and submits the application —
the borrower is **R**, so `sent_user_id` = borrower and `sent_at` = submit time. The
loan officer is **A** and owns the intake outcome. The step closes when the application
is accepted into the lender workflow, stamping the user who records completion and
`received_at`.

### Refinance workflow (per-step model)

One `file_action` per step, keyed to the
[workflow reference](../docs/home-refinance-closing-workflow.md). Roles are party
identifiers (`parties.role`). RACI: **R** performs · **A** owns the outcome · **C** supplies
audited inputs · **I** is notified. The accountable party is nudged for a late open step
(see A4). (CD = Closing Disclosure.) R / A / C / I assignments are proposed; confirm with
app eng.

**1 — Apply** · `APPLICATION_SUBMIT`
The borrower submits the loan application and authorizes credit, income, asset, and
property verification.
*Complete when:* the application is submitted and the loan officer has acknowledged intake.
- **Responsible:** `borrower` (R)
- **Accountable:** `loan_officer` (A)
- **Consulted:** `loan_processor` (C) — intake-completeness support
- **Informed:** none
- **Sender:** `borrower`
- **Receiver:** `loan_officer`

**2 — Disclose & acknowledge** · `DISCLOSURES_ACK`
The loan officer issues the Loan Estimate and required disclosures; the borrower reviews
and acknowledges receipt.
*Complete when:* the borrower has acknowledged receipt within the required window.
- **Responsible:** `loan_officer` (R) — issues disclosures; `borrower` (R) — reviews and acknowledges
- **Accountable:** `loan_officer` (A)
- **Consulted:** none
- **Informed:** `loan_processor` (I) — disclosures acknowledged; processing may proceed
- **Sender:** `loan_officer`
- **Receiver:** `borrower`


**3 — Process the loan** · `LOAN_PROCESS`
The loan processor collects and validates income, asset, insurance, and property
information.
*Complete when:* all requested documentation is supplied and validated; the file is ready
for underwriting.
- **Responsible:** `loan_processor` (R)
- **Accountable:** `loan_processor` (A)
- **Consulted:** `borrower` (C) — income, assets, and insurance (for example W-2,
  paychecks, bank statements), supplied as audited uploads
- **Informed:** `loan_officer` (I), `underwriter` (I) — file progressing toward underwriting
- **Sender:** `borrower`
- **Receiver:** `loan_processor`


**4 — Appraise the property** · `APPRAISAL_COMPLETE`
The lender orders an appraisal; a licensed appraiser determines the property's current
market value.
*Complete when:* a completed appraisal is received and attached to the file.
- **Responsible:** `appraiser` (R)
- **Accountable:** `loan_processor` (A) — lender owner of the appraisal outcome
- **Consulted:** `borrower` (C) — property access for the inspection; `loan_officer` (C) — order support
- **Informed:** `underwriter` (I) — valuation available
- **Sender:** `loan_processor`
- **Receiver:** `appraiser`


**5 — Complete title work** · `TITLE_COMPLETE`
The title/settlement company searches title, identifies liens or ownership issues, obtains
payoff information, and prepares the title commitment.
*Complete when:* the title search is complete, payoff obtained, and the commitment issued.
- **Responsible:** `title_agent` (R)
- **Accountable:** `title_agent` (A)
- **Consulted:** `borrower` (C) — existing mortgage / payoff details and any known liens or HOA;
  `loan_processor` (C) — coordination on payoff and file status
- **Informed:** `underwriter` (I) — title commitment ready for review
- **Sender:** `appraiser`
- **Receiver:** `title_agent`


**6 — Underwrite** · `UNDERWRITE`
The lender's underwriter evaluates credit, capacity, collateral, and compliance and issues
conditions or approval.
*Complete when:* an underwriting decision (conditional approval or approval) is issued.
- **Responsible:** `underwriter` (R)
- **Accountable:** `underwriter` (A)
- **Consulted:** `loan_processor` (C) — clarifications on file contents
- **Informed:** `loan_officer` (I), `borrower` (I) — the decision and any conditions
- **Sender:** `title_agent`
- **Receiver:** `underwriter`


**7 — Clear conditions** · `CONDITIONS_CLEAR`
The loan processor coordinates resolution of underwriting and title conditions and confirms
the loan is clear to close.
*Complete when:* all conditions are satisfied and the loan is marked clear to close.
- **Responsible:** `loan_processor` (R)
- **Accountable:** `underwriter` (A)
- **Consulted:** `borrower` (C) — borrower-side condition items (updated documents, letters
  of explanation); `title_agent` (C) — title condition items
- **Informed:** `loan_officer` (I) — clear to close achieved
- **Sender:** `underwriter`
- **Receiver:** `loan_processor`


**8 — Prepare closing** · `CD_DELIVER`
The lender and title/settlement company set the signing date, finalize figures, and deliver
the Closing Disclosure for the borrower to review within the required timeframe.
*Complete when:* the CD is delivered and acknowledged by the borrower and signing is scheduled.
- **Responsible:** `loan_processor` (R) — lender delivery; `title_agent` (R) — settlement coordination;
  `borrower` (R) — review and acknowledgment
- **Accountable:** `loan_processor` (A)
- **Consulted:** `loan_officer` (C) — final fees and figures
- **Informed:** `notary` (I) — signing scheduled
- **Sender:** `loan_processor`
- **Receiver:** `borrower`


**9 — Sign** · `SIGNING`
The borrower verifies identity, signs the loan and security documents, and provides any
required funds; a notary or settlement agent conducts the signing.
*Complete when:* all closing documents are signed and any required funds are provided.
- **Responsible:** `borrower` (R) — signs and provides funds; `notary` (R) — verifies identity and notarizes
- **Accountable:** `title_agent` (A)
- **Consulted:** none
- **Informed:** `loan_processor` (I) — documents executed; proceed to funding
- **Sender:** `borrower`
- **Receiver:** `title_agent`


**10 — Rescission period** · `RESCISSION` *(timer, not an SLA-bearing action)*
For an eligible refinance of a primary residence, the borrower has a right-to-cancel period
before disbursement; the settlement company monitors it.
*Complete when:* the rescission window elapses without cancellation (or the borrower cancels).
- **Responsible:** `loan_processor` (R) — monitors the clock and records its outcome
- **Accountable:** `loan_processor` (A)
- **Consulted:** `title_agent` (C) — settlement coordination
- **Informed:** `borrower` (I), `loan_officer` (I) — the rescission window and deadline
- **Sender:** `title_agent`
- **Receiver:** `loan_processor`


**11 — Fund & disburse** · `DISBURSE`
The lender funds the new loan; the title/settlement company disburses — paying off the
existing mortgage and other obligations and sending any proceeds to the borrower.
*Complete when:* the loan is funded and all disbursements are sent.
- **Responsible:** `title_agent` (R) — disburses; `loan_processor` (R) — releases lender funds
- **Accountable:** `loan_processor` (A)
- **Consulted:** none
- **Informed:** `borrower` (I), `loan_officer` (I) — funded; proceeds sent
- **Sender:** `loan_processor`
- **Receiver:** `title_agent`


**12 — Record & close** · `RECORDING`
The title/settlement company records the new security instrument, confirms payoff, issues
the lender's title policy, and retains the final documents; the county recorder records.
*Complete when:* the security instrument is recorded, the title policy issued, and the file closed.
- **Responsible:** `title_agent` (R) — submits and records the outcome; `county_recorder` (R) — records the instrument
- **Accountable:** `title_agent` (A)
- **Consulted:** none
- **Informed:** `borrower` (I) — loan closed and recorded; `loan_officer` (I), `loan_processor` (I) — policy issued
- **Sender:** `title_agent`
- **Receiver:** `system` — Autoclose closes the step and the file automatically on receipt (see A5)


## 9. Open questions

The load-bearing unknowns that shape everything above. Each resolves into a
recorded decision.

- **Stack — moved to design.** Component choices (replication mechanism, CDC tool,
  warehouse / transform engine, metric layer, consumer surfaces) are design
  decisions. Requirements fix only: open source (NFR-5) and PostgreSQL as the ODS.
- **SLA targets — resolved.** The system holds and compares per-step SLA targets
  (FR-4) as governed, configurable reference data (NFR-6). The actual target values
  and their source are design-side.
- **Party-to-user link — resolved.** The `user_party` bridge (one user ↔ many
  `party_id`s) carries it; a user can hold multiple roles across files.
- **Which party is nudged — resolved.** The Accountable party of the open step (§8,
  A4) — the borrower or a professional party, always an Autoclose user. The analyst
  is not a nudge target; it watches process health across all files (U1).
- **At-risk threshold — resolved.** A still-open step that has consumed **≥ 80%** of
  its SLA target is "at risk." (The target values themselves are design-side.)
- **Open-step modeling — resolved (semantic).** The step / RACI model is defined in
  [§8](#8-assumptions-and-workflow-model): a step is open between start and completion;
  its Accountable party owns resolution. U2 keeps these open steps. The *physical* shape (one
  step fact over open and closed steps, status computed at read time) is design-side;
  a file-grain accumulating snapshot stays deferred.
- **Nudge delivery — resolved (mock push).** Push, not pull: a scheduled job evaluates
  open steps and writes a deduplicated nudge row for the accountable party (FR-7). No
  real email / SMS in the working example.
- **Freshness budget — resolved.** ≤ 10 minutes end to end (source commit → viewable
  metric); see [§7](#7-success-metrics) and NFR-1.

## 10. Definitions

- **ALTA** — American Land Title Association; title-industry data standards.
- **BI** — business intelligence (dashboards and reporting tools).
- **CD** — Closing Disclosure; the final settlement figures delivered to the borrower
  before signing.
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
- **RACI** — Responsible, Accountable, Consulted, Informed; a responsibility-assignment
  model (R performs, A owns the outcome, C is consulted, I is notified).
- **SLA** — service-level agreement; a per-step or per-stage time target.
- **SQL** — structured query language.
- **WIP** — work in progress (open, unfinished files).

# The Change-Unit Process

This is how we iterate on the design spike: small, bounded, recorded Changes — each with a clear rationale and a reversal boundary. The foundation is **"if it's a decision, it's justified and recorded"** — no design choice ships without a rationale and a decision-log entry pinning *why*.

## What is a Change?

A **Change** is a small, standalone move: a modeling decision, a governance rule, a replication tradeoff, a diagram, a piece of DDL/SQL, or a doc section. It lives on its own branch, has its own decision-log entry, and can be reverted independently. Changes are *not* whole blocks (which are big coherent design areas — modeling & governance, replication, pipeline & consumption); a block is delivered as a series of Changes.

Examples:
- "Grade the workflow-metrics mart at one row per order-stage transition" (D004)
- "Choose log-based CDC over trigger-based replication" (hypothetical)
- "Add a masked access tier for borrower PII" (hypothetical)

## Core Rule: If It's a Decision, It's Justified and Recorded

- **If a Change makes a design decision** (a grain, a layer boundary, a replication mode), record the rationale *and the alternative you rejected* before you move on. The decision log is the spec of record.
- **If a Change is descriptive-only** (a diagram cleanup, a section reword), the decision log says `N/A: descriptive-only` with your reason. Don't manufacture a rationale for a wording tweak.
- **If a Change introduces a concrete artifact** (DDL, SQL, a pipeline/config snippet), validate it: it parses, the grain holds, the join keys exist — whatever proves it's correct, not just plausible.

Rationale is not busywork — it's your reversal gate. A decision that's justified *today* survives scrutiny; when a stakeholder pushes back tomorrow, the log tells you what you assumed and what you'd revisit.

## The Workflow

Using **D004 (grade the workflow-metrics mart)** as the canonical example:

### 1. Design Phase — Surface the decision, not just the artifact

Before branching, state:
- **What's the question?** At what grain do we model workflow metrics so both operational dashboards and downstream agents can consume them?
- **What's your call?** One row per order-stage transition (event grain), rolled up to per-order and per-stage marts in gold.
- **What's the tradeoff?** Event grain costs more storage and heavier queries but preserves cycle-time and rework analysis; a pre-aggregated grain is cheaper but discards the transitions. Guard: state which consumers need transitions and which only need current status.

Write this down *before* you branch. Share it if there's a tradeoff worth a stakeholder's input (app eng, security, SRE).

### 2. Create the change branch

```bash
git checkout -b change/mart-grain-order-transition
git status  # clean
```

Branch name is `change/<descriptor>`, off `main`. Keep it short and kebab-case.

### 3. State the assumption / rationale first

Before writing the doc section, write the decision as a claim you have to defend:
- What you're deciding, and the *one* alternative you're rejecting.
- The assumption it rests on (e.g., "agents need cycle-time, not just current status").
- What you'd validate with a stakeholder to confirm that assumption.

This is the "failing test" analog: you write to the rationale, not to justify a choice after the fact.

### 4. Write the design

Write the minimal doc or artifact that answers the question. No speculative platform features, no "while I'm here" scope, no generic platform pitch untethered from the scenario.

### 5. Validate: does it hold?

- Assumptions stated and reasonable?
- Tradeoff named, alternative rejected for a stated reason?
- Any concrete artifact (DDL/SQL) parses, and the keys/grain hold?
- Consistent with decisions already in the log — no contradiction across blocks?

If it contradicts an earlier decision, stop and reconcile before merging.

### 6. Append a decision-log entry

The decision log ([`docs/Decisions.md`](./Decisions.md)) is the durable record of *why* each Change happened. It's append-only, numbered (D001, D002, D003, …), and mandatory: a Change without an entry is incomplete. Keep the README's **Key decisions** section as a short ADR-style digest that points back here.

**Template** (the `Validation:` line is mandatory):
```markdown
## D0NN — <title> (YYYY-MM-DD)

**Change:** `change/<branch>`

**Motivation:** why (1–2 sentences).

**Design delta:** which docs changed (or "none").

**Artifacts:** DDL / SQL / diagram produced (or "none").

**Reversal:** what we'd change if the assumption breaks / how to undo.

**Validation:** rationale + the alternative you rejected — or — N/A: descriptive-only (reason). Note what you'd confirm with app eng / security / SRE.
```

For D004, the entry was:
```markdown
## D004 — Grade workflow-metrics mart at order-stage transition (2026-07-10)

**Change:** `change/mart-grain-order-transition`

**Motivation.** Dashboards need current status; agents need cycle time and rework.
A single event-grain mart serves both without standing up a second pipeline.

**Design delta:** docs/modeling-and-governance.md (mart grain + gold rollups).

**Artifacts:** gold.order_stage_events DDL sketch.

**Reversal:** if agents only ever need current status, collapse to a per-order
snapshot mart and drop the event grain.

**Validation:** event grain preserves transitions; rejected the pre-aggregated grain
(cheaper, but loses cycle-time). Confirm with app eng that stage transitions are
emitted with reliable timestamps.
```

**The `Validation:` line is not optional.** If it's a decision, name the tradeoff and the rejected alternative. If it's descriptive-only, say so and reason it.

### 7. Commit and merge

Commit on the branch:
```bash
git add -A
git commit -m "Change: grade workflow-metrics mart at order-stage transition (D004)

Dashboards need current status; agents need cycle time and rework. Model the
mart at one row per order-stage transition (event grain), rolled up to per-order
and per-stage marts in gold, so one pipeline serves both consumers.

Validation: event grain preserves transitions; rejected pre-aggregated grain
(cheaper, loses cycle-time). Confirm stage-transition timestamps with app eng."
```

Then merge to main, preserving the Change boundary:
```bash
git checkout main
git merge --no-ff change/mart-grain-order-transition -m "Merge: grade workflow-metrics mart at order-stage transition (D004)"
git branch -d change/mart-grain-order-transition
```

Verify:
```bash
git log --oneline -3  # merge commit visible
git branch            # only main remains
```

## When to deviate

- **No artifact?** Skip the `Artifacts:` section or write "none".
- **Descriptive-only change?** Write `Validation: N/A: descriptive-only (reason)` and move on.
- **Reversing a decision?** Supersede it with a new numbered entry that references the old one — don't rewrite history.
- **Batch related Changes?** One branch per logical decision, even if you stack them on main.

## Decision-log discipline

The log is your source of truth for *why* Changes happened, not *what's* in them. Write it as if someone reads it 6 months from now and asks: "Why did we do this?"

- **Motivation** is the load-bearing part — constraints, domain rules, stakeholder input, incidents.
- **Design delta** + **Artifacts** let you trace impact: which docs or DDL changed.
- **Reversal** is your escape hatch — if an assumption breaks, this line tells you what to revisit.
- **Validation** is the proof — name the tradeoff and what you'd confirm with app eng, security, or SRE.

## Why this process?

1. **Design upfront** — surface tradeoffs before writing; avoid scope creep and generic platform pitches.
2. **Rationale first** — you write to the decision, not to rationalize it after the fact.
3. **One decision per Change** — every branch is one concern, one reversal.
4. **Consistency gate** — reconcile against the log before merge so blocks don't contradict each other.
5. **Durable decision log** — the *why* outlasts the artifact; graders read the log to see your reasoning.
6. **Reversal boundary** — one branch = one decision = one revert if something needs undoing.

This is change-driven iteration for a design spike — not a grand rewrite, but a series of small, justified, recorded moves. Read the log (especially the **Motivation** sections) to understand the constraints you're designing within.

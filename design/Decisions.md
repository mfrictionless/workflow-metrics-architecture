# Decision Log

Append-only record of *why* each Change happened. Numbered D001, D002, D003, … — newest at the bottom. See [`Process.md`](./Process.md) for the workflow and the field definitions.

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

## D001 — Working-example requirements baseline (2026-07-12)

**Change:** `change/requirements`

**Motivation.** Post-interview, we are building a runnable working example. This
Change fixes the requirements baseline (a lightweight PRD) so the build has a clear
target: what we are building, for whom, and under what constraints.

**Design delta:** `design/Requirements.md` (new PRD); `CLAUDE.md` (AMOD / Autoclose
naming, scenario assumptions, open-source build constraint); `docs/modeling-and-governance.md`
(added the `user_party` bridge to the ODS); `docs/home-refinance-closing-workflow.md`
(refinance lifecycle reference, added by owner).

**Artifacts:** the PRD; `user_party` table DDL sketch.

**Reversal:** requirements are `Status: Draft` — revise via further Changes. Any
"resolved" item can be reopened if its assumption breaks.

**Validation:** load-bearing decisions and the alternatives rejected —
- **Two consumers, not one** — an internal analyst tier plus a borrower-facing nudge
  agent. Rejected a single retrieval consumer: the two need different scope
  (all files vs. own file) and freshness.
- **Refinance grounding** — the borrower is the sole external customer party (no
  seller / buyer's agent), so the nudge target is unambiguous. Rejected the generic
  purchase framing for this example.
- **Cross-database read as a functional requirement** — DB-B reads DB-A + DB-B,
  mutates only its own records; the replication *mechanism* is design-side. Rejected
  pinning a read replica in the requirements.
- **Open-source-only stack** (the agent's AI model is the lone exception). Rejected
  paid / proprietary stack components, for a reproducible example.
- **10-minute end-to-end freshness** (commit → viewable) as the party-facing bar.
- **Step grain over open and closed steps** — U2 keeps the open steps that per-step
  turnaround drops; a file-grain accumulating snapshot stays deferred.

Confirm with app eng: `received_user_id` is the assigned recipient set at send time
(the nudge target depends on it); the `parties`-to-`users` link exists via signup
(modeled as `user_party`); and the source of per-step SLA targets (still open).

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

## D002 — Full RACI workflow model; nudge follows the Accountable party (2026-07-12)

**Change:** `change/resolve-open-questions`

**Motivation.** D001's borrower-only nudge and single-action-per-step model didn't hold
up against a real walk-through of the refinance lifecycle: the borrower is Accountable
on some steps but only supplies inputs (Consulted) on others, and professional parties
(loan officer, processor, underwriter, appraiser, title agent) need the same nudge
treatment the borrower gets. This Change closes out D001's remaining open questions and
replaces the single-action step model with a full per-step RACI (Responsible,
Accountable, Consulted, Informed) decomposition, keyed to the 12-step refinance
reference.

**Design delta:** `design/Requirements.md` — §8 rewritten with A2–A5 (RACI assignment,
custody-chain semantics for `sent_*`/`received_*`, the Autoclose-user constraint, the
terminal-step auto-close) and a full 12-step RACI breakdown; §9 open questions resolved
(stack moved to design, SLA targets governed as reference data, at-risk threshold fixed
at 80%, nudge delivery is mock push). `docs/home-refinance-closing-workflow.md` — added
the Parties table and full R/A/C/I matrix as the source of truth the requirements model
is keyed to.

**Artifacts:** none (model and reference data only; no DDL/SQL yet).

**Reversal:** if the Accountable-party generalization proves wrong (e.g., only the
borrower should ever be nudged), collapse the nudge target back to "borrower only" and
drop the professional-party rows from U2. If mock push turns out unnecessary, U2 can
fall back to a read-time pull view.

**Validation:** rejected alternatives —
- **Nudge = Accountable party, not "borrower only."** A single external-customer nudge
  model couldn't represent professional-party bottlenecks (appraiser, underwriter,
  title agent) without a second, redundant mechanism. One rule (A4) covers both.
- **Full R/A/C/I over single Responsible/Accountable.** Rejected collapsing the
  borrower's document-supply role into Accountable — it wrongly made the borrower the
  step-closer on steps 3 and 7, when the professional party actually owns closing.
- **Custody (Sender/Receiver) decoupled from RACI**, not restricted to R/A. Rejected
  "only R or A may mutate `sent_*`/`received_*`" once Consulted parties (e.g., the
  borrower uploading documents) needed to hold custody too.
- **Terminal step closes via a system principal (A5)**, not a human Receiver. Rejected
  requiring a human acknowledgment on step 12, since recording confirmation is the last
  human input and Autoclose can close the file the moment it's received.
- **Mock push, not pull**, for nudge delivery — rejected relying on login-time queries,
  since the point of a nudge is reaching a party who is *not* currently logged in.

Confirm with app eng: the four missing RACI cells I found by diffing `design/Requirements.md`
against the source matrix are now aligned, but the matrix itself (R/A/C/I per step) is a
proposed model — validate it against how AMOD's loan officers, processors, and title
agents actually work today. Also confirm a system service principal is an acceptable way
to model `received_user_id` on the terminal step (see A5).

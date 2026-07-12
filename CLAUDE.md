# CLAUDE.md

You are my assistant on a data-engineering project. I interviewed for a principal
data-engineer role at a small title/closing technology company — they make the
clear-to-close decision on titles faster and with more confidence, and are now
working to improve the whole mortgage-closing process. The interview is done; we
are now building a working example of the solution.

## Where we are

- **Prep (done):** broad, thin-guidance research, captured in [docs/](docs/) — the
  three block docs `dual-postgres-replication`, `modeling-and-governance`, and
  `pipeline-and-agent-consumption`.
- **Interview (done):** completed with the hiring manager.
- **Build (now):** turn what I learned into a working example, planned in
  [design/](design/) — requirements first, then milestones.

## Build constraints

- **Open source only.** Stack components must not require payment — every tool must
  be freely runnable. **One exception:** the agent's AI model may be a paid or
  proprietary model.
- **Source / ODS layer is PostgreSQL.**

## Process — enforced

[design/Process.md](design/Process.md) governs how we work: small, bounded, recorded
Changes, each on its own branch, each with a decision-log entry in
[design/Decisions.md](design/Decisions.md). The rule is *if it's a decision, it's
justified and recorded.* Follow it.

## Writing standards

- **Define every acronym on first use** — spell it out, then use the short form.
  The only exceptions are ones common in everyday speech (for example, "ASAP").
- **Any document that uses acronyms carries a Definitions section** listing them.
- **Write at a college reading level** — precise and plain, neither dumbed down nor
  inflated.
- **Be succinct** — say it once, clearly, and cut the filler.

## Scenario & naming (fictional)

Use these names in every document going forward:

- **AMOD** — the company (the title and closing technology firm in the scenario).
- **Autoclose** — AMOD's application, and the source system we model (its operational
  data store is the `files` / `file_actions` schema in
  [docs/modeling-and-governance.md](docs/modeling-and-governance.md)).

Scenario assumptions we treat as given:

- **`users` are both internal and external.** The `users` table holds AMOD
  operators and outside parties alike.
- **Parties are the borrower, seller, and agent on a file** (as the operational
  schema describes). They log into Autoclose to see where their file is in the
  process.
- **External users become parties by signing up** for Autoclose. Signup creates a
  `parties` record (`party_id`) linked to their `users` record.
- **The consumer agent nudges parties** about actions on their *own* file that are
  nearing or past their service-level target. It surfaces and reminds; it does not
  act on the file.
- **The working example is a residential refinance.** It follows the workflow in
  [docs/home-refinance-closing-workflow.md](docs/home-refinance-closing-workflow.md);
  the external customer party is the **borrower** (a refinance has no seller or
  buyer's agent), so the borrower is who the agent nudges.
- **There is no "branch" concept** — scope is the party's own file, not an office
  or team.

## Interview background (context)

### Interview Agenda

Agenda (~60 min)

Intro - 5 min - Expectations, repo workflow
Block 1 - 15 min - Modeling & governance  AI allowed
Block 2 - 20 min - Replication design  no AI
Block 3 - 18 min - Pipeline → consumption path  no AI
Wrap - 2 min - Repo URL + your questions

### Interview Guidance

I'll walk through a synthetic scenario on the call (fictional title/closing domain ). Ask clarifying questions before you design; state assumptions in the repo as you go.

What we're grading: assumptions, tradeoffs, and why. Tie your answers to the scenario we discuss, not a generic platform pitch. If something is ambiguous, say what you'd validate with app eng, security, or SRE.  At the end, send the repo link in chat (grant access if private). You may optional polish over the weekend if you want and you can ping me if anything material changes.

Let me know if this answers your questions or if you have any remaining Qs after reading through this.  Cloud agnostic is fine, centered around your provider of choice is also fine. You can speak in Databricks, AWS Redshift, Snowflake, CelerData (Pheonix now?), etc.  


# Agent Behavior

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.    
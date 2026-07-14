# Process — How We Build Milestones

**Status:** Active · **Owner:** Michael Leslie · **Last updated:** 2026-07-14

This is the working agreement between the owner and the assistant for turning
[Milestones.md](Milestones.md) into working, tested code. It defines the loop we
follow, the shape of a milestone, how we test, and when a milestone is done.

## Roles

- **Owner** — sets direction, reviews and edits each milestone draft, and gives
  the explicit go-ahead to build. Final say on scope.
- **Assistant** — drafts the milestone, writes tests, implements, and runs
  regression. Surfaces tradeoffs and stops at the review gate rather than
  guessing.

## The milestone loop

Each sub-milestone (M0.1, M1.1, …) moves through these steps in order:

1. **Draft.** Assistant writes the milestone using the
   [template](#milestone-template) below — Test, Acceptance, Automated Test Plan,
   Manual Test Plan, plus Dependencies and Out-of-scope.
2. **Review gate (hard stop).** Owner reviews and edits. The assistant does not
   write code until the owner says **"approved to build."** This prevents work on
   a milestone that is about to be reshaped.
3. **Write the tests first.** Per the [test strategy](#test-strategy): logic is
   strict test-first; infrastructure gets a bring-up smoke check.
4. **Watch the tests fail — for the right reason.** A test that fails on a missing
   import or absent fixture does not count as red. Red means the test runs,
   exercises the intended behavior, and fails on its **assertion**. Capture that
   output.
5. **Implement.** Write the minimum functionality to satisfy the milestone —
   nothing speculative (see [CLAUDE.md](../CLAUDE.md) §2).
6. **Retest the change.** The new tests go green.
7. **Full regression.** Run the entire suite (see M0.3). A milestone is not done
   until every existing test still passes.
8. **Record and merge.** Update affected design docs, add a
   [Decisions.md](Decisions.md) entry if the milestone made a non-obvious choice,
   commit, and fast-forward merge to `main` (see [Branch & merge](#branch--merge)).

## Milestone template

Every milestone draft carries these fields. The first two already appear in
[Milestones.md](Milestones.md); the rest are added when we pick the milestone up
to build.

- **Test** — the one-line statement of what is being verified.
- **Acceptance** — the observable condition that proves the milestone is met.
- **Dependencies** — which milestones must be done first (e.g. M2.3 needs
  M2.1 + M2.2). Makes branch order explicit.
- **Out-of-scope** — what this milestone deliberately does *not* do, to prevent
  scope drift.
- **Automated Test Plan** — the checks that run unattended in the suite: the tool
  (pytest, dbt test, a SQL assertion script, a connector probe), what each asserts,
  and whether it is a fast or integration check.
- **Manual Test Plan** — steps a human runs to confirm behavior the automated
  suite cannot economically cover (e.g. inspecting a Kafka topic, eyeballing a
  freshness measurement).

## Test strategy

**Test-first for logic; smoke-check for infrastructure.**

- **Logic** — business rules and computations (simulator workflow/RACI rules,
  metric math, RLS scoping, dedup/ordering) are strict red-green test-first. Write
  the failing assertion before the code.
- **Infrastructure** — standing up a broker, deploying a connector, applying DDL,
  or starting a service uses a lighter **bring-up smoke check** (the service comes
  up, a topic exists, a message flows) rather than a red-first assertion. There is
  no business logic to drive, so red-first ceremony adds nothing.

**Two tiers, one command.** Tests are split so the inner loop stays fast:

- **Fast** — unit and SQL-logic tests with no external infrastructure. Run
  constantly during development.
- **Integration** — tests that need `docker compose` services live (CDC flow,
  end-to-end freshness). Slower; run before merge.

M0.3's single command runs both tiers and exits non-zero if any test fails; a
fast-only path serves the inner loop.

## Definition of Done

A sub-milestone is done when **all** of the following hold:

- [ ] Tests written per the test strategy (logic test-first; infra smoke-checked).
- [ ] Tests were observed failing for the right reason before implementation (logic).
- [ ] New tests pass.
- [ ] Full regression passes (M0.3).
- [ ] The service and its tests are wired into `docker-compose.yml` and the
      single test command (M0.2, M0.3).
- [ ] Affected design docs updated; a [Decisions.md](Decisions.md) entry added if a
      non-obvious choice was made.
- [ ] Committed and fast-forward merged to `main`.

## Branch & merge

- One branch per sub-milestone, named `change/<milestone>-<slug>` (e.g.
  `change/m1.1-ods-schema`).
- Fast-forward merge to `main` on acceptance; no merge commits while history stays
  linear.
- Commit messages end with the standard co-author trailer.

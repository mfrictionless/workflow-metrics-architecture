# Decision Log

Append-only record of *why* each Change happened. Numbered D001, D002, D003, … — newest at the bottom. See [`Process.md`](Process.md) for the workflow and the field definitions.

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

## D001 — Monorepo repository layout (2026-07-14)

**Change:** `change/m0.1-repo-structure`

**Motivation.** M0.1 needs a documented, testable repository structure so a contributor can locate any component by folder name alone, and so the pipeline stays reproducible from one checkout (NFR-4).

**Design delta:** `design/Technical-Design.md` — new §9 "Repository layout," a living folder-per-component map with a Status column and the lazy-creation / test-co-location conventions. `design/Milestones.md` — M0.1 expanded to the full template and pointed at §9. `README.md` — one-line pointer to §9.

**Artifacts:** `tests/check_structure.sh` — a zero-dependency structure smoke check asserting the §9 map documents every component, existing folders are present, and the ODS DDL is where the map says.

**Reversal:** if the folder taxonomy proves wrong, rename/regroup in §9 and update the check's `DOCUMENTED` list; lazy creation keeps folders near-empty until their milestone, so rework is cheap.

**Validation:** choices and rejected alternatives —
- **`streaming/` split from `cdc/`** — Kafka broker + Connect worker (infrastructure) separated from the Debezium/JDBC connector configs (capture/landing). Rejected lumping both under one `cdc/` folder.
- **Layout map in Technical-Design §9, not README or Milestones.** Rejected the README (an index, not a design record) and Milestones (about testable units, not standing structure) as homes; §9 sits next to the §2 component registry it derives from and is updated as we build.
- **Test co-location + a root `tests/` for cross-cutting tests.** Rejected a pure top-level `tests/` because dbt tests must live inside the dbt project by convention, so full centralization is impossible.
- **Smoke check, not red-green test-first** — repository structure is infrastructure with no business logic to drive, per [Process.md](Process.md); the check was still observed failing for the right reason before §9 was written.

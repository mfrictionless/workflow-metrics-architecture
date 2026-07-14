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

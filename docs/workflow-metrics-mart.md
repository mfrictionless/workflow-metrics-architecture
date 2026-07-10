# Workflow Metrics Mart — Iterative Build

Single data mart built from the Block 1 operational schema (see [modeling-and-governance.md](modeling-and-governance.md)).
We build the **simplest thing that works** first, then layer on grain, dimensions, and governance.

---

## Iteration 1 — Per-step turnaround (cycle time at step grain)

**Decisions locked (interview, Block 1):**

| Decision | Choice |
|----------|--------|
| Fact grain | One row per `file_action` (a send/receive workflow step) |
| Metric | Cycle time = **per-step turnaround**, `received_at − sent_at` |
| Population | Steps on **closed files only** (`files.closed_at IS NOT NULL`) |

**Why per-step turnaround is "cycle time" here:** at `file_action` grain the only meaningful
continuous duration is how long one step took. The file-level `closed_at − opened_at` would be a
constant repeated on every step row of that file (a degenerate measure), so it is *not* used as the
iteration-1 measure — it returns as a file-grain fact in a later iteration.

### Assumptions (flag to change)

1. **Duration defined only when `received_at IS NOT NULL`.** A step can still be open even on a
   closed file; those rows are **excluded** from v1 so the measure is never garbage.
   *(Iteration 2: keep them with null duration as a "still-open steps on closed files" DQ signal.)*
2. **`live_flag = true`** — exclude voided/test actions.
3. **Non-positive durations** (`received_at <= sent_at`) are a DQ violation; v1 **filters** them.
   *(Iteration 2: route to a quarantine table instead of dropping.)*
4. **No dimensions yet** — `file_id` and `action_code` ride as degenerate attributes.
   `dim_file` (county, product_type) and a date dimension arrive in iteration 2.

### Fact table DDL

```sql
-- fct_file_action_step
-- Grain: one completed workflow step on a closed file.
CREATE TABLE gold.fct_file_action_step (
  file_action_id      bigint      NOT NULL,   -- grain / degenerate key
  file_id             bigint      NOT NULL,   -- degenerate (dim_file arrives iter 2)
  action_code         varchar     NOT NULL,   -- which step
  sent_at             timestamptz NOT NULL,
  received_at         timestamptz NOT NULL,
  step_duration_days  numeric     NOT NULL    -- MEASURE: received_at − sent_at, in days
);
```

### Transform (populate the fact)

```sql
INSERT INTO gold.fct_file_action_step
SELECT
  fa.file_action_id,
  fa.file_id,
  fa.action_code,
  fa.sent_at,
  fa.received_at,
  DATEDIFF(SECOND, fa.sent_at, fa.received_at) / 86400.0 AS step_duration_days
FROM file_actions fa
JOIN files f
  ON f.file_id = fa.file_id
WHERE f.closed_at   IS NOT NULL        -- closed files only
  AND fa.received_at IS NOT NULL       -- step completed → duration defined
  AND fa.live_flag   = true            -- exclude voided/test actions
  AND fa.received_at >  fa.sent_at;     -- drop non-positive durations (DQ)
```

### Metric on top

```sql
-- Cycle time (per-step turnaround), sliced by step
SELECT
  action_code,
  COUNT(*)                              AS steps,
  AVG(step_duration_days)               AS avg_days,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY step_duration_days) AS p50_days,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY step_duration_days) AS p90_days
FROM gold.fct_file_action_step
GROUP BY action_code;
```

---

## Backlog (next iterations)

- **Iter 2 — dimensions:** `dim_file` (county_fips, product_type, status) + `dim_date`;
  swap degenerate `file_id`/dates for surrogate keys.
- **Iter 2 — DQ:** quarantine table for null/non-positive durations instead of dropping.
- **Iter 3 — file-grain fact:** `fct_file` accumulating snapshot for open→close cycle time and WIP.
- **Iter 3 — SCD2 dims:** SLA policy / branch as-of joins for "SLA in effect then".
- **Iter 4 — governance:** access tiers, PII masking (parties/ssn), metric views as the single source of truth.


# Block 1 - Modeling and Governance Guidance

## Requirements

- 1 Mart
- 3-5 dimension columns
- Grain statement

## Input ODS

Model:

```sql
-- files: core transaction/file record
files (
  file_id           bigint PK,
  file_number       varchar,
  status            varchar,
  opened_at         timestamptz,
  closed_at         timestamptz,
  county_fips       varchar,
  product_type      varchar
)

-- file_actions: workflow steps (send/receive lifecycle)
file_actions (
  file_action_id    bigint PK,
  file_id           bigint FK → files,
  action_code       varchar,
  action_type       varchar,      -- e.g. Start, Complete
  sent_at           timestamptz,
  received_at       timestamptz,
  sent_user_id      bigint,
  received_user_id  bigint,
  live_flag         boolean
)

-- audit_events: high-volume event log; description is free text
audit_events (
  audit_id          bigint PK,
  file_id           bigint FK → files,
  user_id           bigint,
  event_at          timestamptz,
  description       text
)

-- parties: borrower/seller/agent contact data
parties (
  party_id          bigint PK,
  file_id           bigint FK → files,
  role              varchar,
  display_name      varchar,
  email             varchar,
  phone             varchar,
  ssn_last4         varchar
)

-- users: internal operators and external vendor users
users (
  user_id           bigint PK,
  team_name         varchar,
  is_external_vendor_flag boolean
)
```


# Block 1 — Modeling & Governance - Prep

**Framing:** two intertwined concerns — the **model** (how we shape workflow data into facts and dimensions) and **governance** (who may see what, under which regulatory regime). Both hinge on **two master questions** we ask first:

1. **What decisions must the metrics drive?** → sets the **mart grain** (the load-bearing modeling decision) and which metrics exist.
2. **Who consumes it, under what compliance regime?** → sets the **access tiers** and the PII/masking posture.

Everything below hangs off those two. This is the AI-allowed block, so these are the questions we'd work live.

---

## Big buckets (align on these first)

| # | Bucket | The core question it answers |
|---|--------|------------------------------|
| A | Domain, grain & workflow backbone | *What are we measuring, and at what grain?* |
| B | Layering (medallion) & where logic lives | *Bronze/silver/gold boundaries and what belongs where?* |
| C | Dimensional model & SCD | *Facts vs. dimensions, keys, and what needs history?* |
| D | Metrics & semantic definitions | *Which metrics, defined once, owned by whom?* |
| E | Access tiers & authorization model | *Who reaches which tier, enforced how?* |
| F | PII, classification & compliance | *What's sensitive, where is it stripped, what regime applies?* |
| G | Data quality & contracts | *What guarantees hold, and what's the source contract?* |
| H | Catalog organization & ownership | *How is it laid out, and who owns each product?* |

*(Confirm/adjust these buckets before we drill in.)*

---

## A. Domain, grain & workflow backbone

1. **Confirm the workflow lifecycle** — open → title search → underwriting → curative → clear-to-close → funding → recording? → *the metric spine; needs interviewer confirmation, not assumption.*
2. **What decisions must the metrics drive** — SLA management, staffing, bottleneck detection, forecasting? → *drives which metrics and the grain.*
3. **What's the mart grain** — event/transition grain vs. per-order snapshot vs. pre-aggregated? → *the load-bearing call; event grain preserves cycle-time and rework, the pre-agg throws them away.*
4. **What's the atomic business event** — a stage transition, an order, a task assignment? → *the fact grain.*
5. **How much history / point-in-time** is needed? → *drives SCD2 + as-of joins (the SLA-was-in-effect-then problem).*

## B. Layering (medallion) & where logic lives

1. **Layer boundaries** — bronze (raw CDC, append, replayable), silver (conformed, deduped, SCD), gold (star marts + metric views)? → *the contract between layers.*
2. **Where does business logic live** — silver vs. gold? → *maintainability; keep transformation in one predictable place.*
3. **Streaming vs. batch per layer** (DLT)? → *freshness budget — ties to Block 2's CDC latency.*
4. **Raw retention & replayability** in bronze? → *reprocessing / backfill without re-hitting source.*
5. **Is the consumer/serving layer distinct from gold** (the semantic layer)? → *the seam handed to Block 3.*

## C. Dimensional model & SCD

1. **Star schema — facts vs. dimensions; conformed dimensions** across marts? → *reuse and cross-mart consistency.*
2. **Fact type** — transaction, periodic snapshot, or **accumulating snapshot**? → *the order lifecycle is a classic accumulating-snapshot candidate, alongside a transaction-grain event table.*
3. **Which dimensions are SCD2** — branch, underwriter/office, **SLA policy**? → *point-in-time correctness; SLA breach must measure against the target in effect then.*
4. **Surrogate vs. natural keys**? → *stability when source keys change or are reused.*
5. **Late-arriving data / dimensions** handling? → *robustness of the validity ranges.*

## D. Metrics & semantic definitions

1. **Canonical metric list + definitions** — cycle time, SLA breach rate, WIP, throughput, rework rate? → *the content of the semantic layer.*
2. **Who owns each definition** — single source of truth? → *governance of *meaning*, not just access.*
3. **Defined in a semantic layer (UC metric views) or hardcoded in marts?** → *consistency across every consumer, including Block 3's agents.*
4. **Business-day vs. calendar, timezone, SLA calendar?** → *the correctness gotchas that make two "cycle times" disagree.*

## E. Access tiers & authorization model

1. **Which personas consume** — analysts, ops, app eng, agents, external partners (title agents/lenders)? → *the tiers and who reaches each.*
2. **What are the access tiers** — raw / curated / consumer — and who reaches each? → *least privilege by layer.*
3. **RBAC via IdP groups vs. ABAC via attribute/mapping tables?** → *how entitlements scale (per-branch, per-partner).*
4. **Row/column security requirements** — branch/partner row scoping, PII masking? → *UC row filters + column masks (the Block 3 mechanism).*
5. **Unity Catalog object model** — catalogs/schemas by env/domain/layer, and grant strategy? → *the namespace that governance hangs on.*

## F. PII, classification & compliance

1. **What PII/NPI exists, and where is it stripped/masked?** SSN, borrower financials, property/loan detail. → *the consumer tier should be PII-free by construction.*
2. **Data classification scheme** — public / internal / confidential / restricted, tagged in UC? → *tag-driven policy instead of per-object rules.*
3. **Regulatory regime** — GLBA/NPI, state DOI, retention, residency? → *retention, masking, and where data may live.*
4. **Lineage & audit requirements**? → *UC lineage + audit logs, end to end.*
5. **Deletion / right-to-be-forgotten** propagation through the medallion? → *how a source delete flows to gold (soft-delete + purge policy).*

## G. Data quality & contracts

1. **Quality gates** — nullability, referential integrity, valid stage enums, non-negative durations? → *DLT expectations at layer boundaries.*
2. **Source data contract with app eng** — schema stability, `REPLICA IDENTITY`, reliable event-time? → *ties straight to the Block 2 / app-eng conversation.*
3. **Freshness SLOs + staleness alerting**? → *the guard against "confident staleness" downstream.*
4. **Reconciliation vs. source** — row counts, drift checks? → *trust in the numbers.*
5. **Bad / late / duplicate record handling**? → *idempotency (LSN dedup) — the Block 2 seam.*

## H. Catalog organization & ownership

1. **UC catalog/schema layout** — by environment, domain, and/or medallion layer? → *discoverability + governance boundaries.*
2. **Data-product boundaries and ownership** — who owns the workflow-metrics product? → *the operating model.*
3. **Naming conventions, tags, comments** for discoverability? → *usability for humans and agents.*
4. **Environment separation (dev/test/prod) and promotion**? → *lifecycle and blast-radius control.*

---

## How we'd proceed if unanswered (likely landing)

*(Neutral defaults to state aloud — confirm, don't presume.)*
- **Medallion on DLT:** bronze (raw CDC, append-only, replayable) → silver (conformed, LSN-deduped, SCD2 dims + an append-only transition table) → gold (star-schema marts + metric views).
- **Grain:** event/transition-grain fact (`order_stage_events`) as the source of truth, rolled up to per-order (accumulating snapshot) and per-stage marts.
- **SCD:** Type 2 for branch, underwriter, and SLA policy (as-of joins on `entered_at`); Type 1 for cosmetic attributes.
- **Metrics defined once** in Unity Catalog metric views — the single source of truth consumed by BI *and* the Block 3 agents.
- **Three access tiers:** raw (data eng only) · curated (analysts/app eng) · consumer (agents/BI, **PII-free by construction**) — enforced by UC groups + row filters/masks.
- **PII stripped at silver→gold;** classification tags drive masking policy; lineage + audit on by default.
- **Quality via DLT expectations** at each boundary, with a freshness watermark carried to gold.

## Cross-block seams (state these to show the whole design connects)

- **← From Block 2 / app eng:** the source contract — reliable event-time and `REPLICA IDENTITY` — is what makes the transition grain (and thus every cycle-time metric) computable.
- **→ To Block 3:** the **gold metric views** are the governed contract the agents consume; the **access tiers + row/column security** defined here are exactly what the agent's identity is scoped against.

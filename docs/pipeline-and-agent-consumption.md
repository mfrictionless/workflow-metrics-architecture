# Block 3 — Pipeline → Agent Consumption - Prep

**Framing:** designing the ingest → warehouse → consumption path where the primary consumers are **agents** — LLM-driven, programmatic consumers — not humans in a BI tool. We do **not** assume a copilot or any single autonomy level. Agent-based consumption spans a spectrum, and the design must locate the scenario on it rather than presume:

- **Retrieval / analytical agents** — read governed metrics, answer or report. Read-only.
- **Decision-support agents** — recommend or draft, still human-gated.
- **Autonomous action-taking agents** — read metrics *and* take actions (reassign an order, open a curative task, trigger a workflow). Side effects.

The first bucket locates us on that spectrum; every later bucket's answer shifts with it.

---

## Big buckets (align on these first)

| # | Bucket | The core question it answers |
|---|--------|------------------------------|
| A | Agent profile & agency | *What kind of agent, how autonomous, read-only or acting?* |
| B | Consumption interface & access pattern | *How does the agent get data — semantic layer, tools, SQL, retrieval; pull or push?* |
| C | Data: scope, grain, freshness & source of truth | *Which metrics, at what grain and freshness, defined by whom?* |
| D | Identity, security & governance | *Whose identity does the agent act under, and what may it see?* |
| E | Actions, safety & blast radius | *If it acts — what can it change, and how do we bound the damage?* |
| F | Trust, grounding & evaluation | *How do we know an answer/action is correct and not hallucinated?* |
| G | Compliance & data boundary | *What regulatory limits apply, and can data/PII reach the model?* |
| H | Operating model: scale, cost, contracts & ops | *Will it hold up in production, and who owns it?* |

*(Confirm/adjust these buckets before we drill in — everything below hangs off them.)*

---

## A. Agent profile & agency

1. **Where on the spectrum** — retrieval, decision-support, or autonomous action-taking? → *the master switch; buckets D/E/F all pivot on this.*
2. **Attended or unattended?** Triggered by a human turn, or running on a schedule / event with no human present? → *unattended raises the bar on accuracy, guardrails, and audit.*
3. **Single agent or multi-agent / orchestrated?** One agent, or a planner delegating to sub-agents/tools? → *affects auth scope, tracing, and failure modes.*
4. **What outcomes is it accountable for?** Answer a question, surface a risk, move work through the pipeline? → *defines success and the eval bar.*
5. **Who or what invokes it** — an app, another service, a scheduler, an end user? → *drives the identity and trust model in bucket D.*

## B. Consumption interface & access pattern

1. **How does the agent reach data** — natural language over a semantic layer, governed tools/functions (e.g. MCP), direct SQL, or retrieval? → *semantic layer / tools are governable; free SQL is flexible but hard to bound.*
2. **Does the agent author SQL,** or only call pre-defined, governed metrics/tools? → *free SQL vs. a typed, bounded tool surface.*
3. **Retrieval over metrics, documents, or hybrid?** Curated marts vs. unstructured docs (title commitments, closing instructions). → *decides whether vector search sits alongside the warehouse.*
4. **Pull or push?** Interactive query vs. streaming/event-driven trigger (e.g. act on an SLA breach as it happens). → *pull-query path vs. streaming path.*
5. **Stateless lookups or multi-turn/stateful sessions?** → *context and session-state design.*

## C. Data: scope, grain, freshness & source of truth

1. **Which workflow metrics are in scope?** Cycle time per stage, SLA breaches, rework/kickback rate, aging, throughput, WIP? → *defines the gold marts this block consumes.*
2. **What's the workflow backbone?** Confirm the order/file lifecycle rather than assume it. → *the metric spine; needs interviewer confirmation.*
3. **Who owns each metric's definition** — is it agreed, or do we define it in a semantic layer? → *ownership and single-source-of-truth.*
4. **Historical/point-in-time vs. current-state only?** → *event-grain vs. snapshot mart (ties to the modeling block).*
5. **How fresh must the data be** — seconds, minutes, hourly, daily? And **acceptable query latency per agent turn?** → *streaming/DLT vs. batch; caching/materialization.*

## D. Identity, security & governance

1. **Whose identity does the agent act under** — end-user passthrough, or a service/machine principal? → *the crux of how row/column security is enforced.*
2. **Row/column-level security expectations?** Partner sees only their orders; agent sees masked PII. → *Unity Catalog row filters + column masks, scoped to identity.*
3. **What PII/NPI is present, and does the agent need any of it?** SSNs, borrower financials, property/loan detail. → *most metrics can be PII-free; confirm so we strip it upstream.*
4. **Authorization for reads *and* actions** — is the agent a first-class principal with scoped, least-privilege grants? → *credential scoping, not a god-mode service account.*
5. **Is every interaction auditable** back to an identity and a governed source? Can free-text output leak restricted data? → *audit logging + output-side guardrails, not just input authz.*

## E. Actions, safety & blast radius *(if action-taking)*

1. **What actions may it take, and against what systems?** Read-only, write-back to the warehouse, or side effects in operational systems (orders, tasks, notifications)? → *defines the write path and its trust boundary.*
2. **Idempotency & rollback** — can an action be safely retried and undone? → *dedupe keys, compensating actions.*
3. **Approval gates / human-in-the-loop** for which classes of action? → *where autonomy stops.*
4. **Blast radius limits** — rate caps, value thresholds, scope fences (one order vs. bulk)? → *bounding worst-case damage.*
5. **What's the failure/kill-switch story** if the agent misbehaves? → *circuit breaker, disablement.*

## F. Trust, grounding & evaluation

1. **Must answers/actions cite their source** (which mart, which freshness timestamp, lineage)? → *grounding + citation surface.*
2. **How do we prevent hallucinated metrics** (invented numbers, wrong joins)? → *constrain to governed definitions; no free arithmetic on raw tables.*
3. **What's the acceptance bar before it ships** — golden question set, accuracy threshold, action-precision target? → *eval harness + regression suite.*
4. **How deterministic must it be** — same question, same answer? → *caching, temperature, tool-forced paths.*

## G. Compliance & data boundary

1. **Regulatory regime?** GLBA / NPI handling, state DOI, CFPB, data residency. → *retention, masking, and where data and the model may run.*
2. **Can data leave the Databricks/VPC boundary** — e.g., to a hosted LLM API — and can PII ever reach the model? → *Databricks-served vs. external model; PII-to-model policy.*
3. **Retention & right-to-audit** on agent interactions and underlying metrics? → *logging + retention policy.*

## H. Operating model: scale, cost, contracts & ops

1. **Query volume / concurrency** — a few agents or embedded at app scale; unattended fan-out? → *warehouse sizing, serving layer, caching.*
2. **Cost guardrails** — a chatty or looping agent can fan out expensive scans. → *pre-aggregation, query/row limits, result caching.*
3. **Upstream contract** — what do the gold marts (modeling block) guarantee, and how stable is the schema? → *data contract + contract tests; what breaks the agent on a stage rename.*
4. **Production observability & feedback** — quality, latency, cost, error rate; a feedback loop into eval. → *eval-in-prod + continuous improvement.*
5. **Ownership** — who owns the agent, the tools, and the semantic layer once live? → *operating model / on-call.*

---

## How we'd proceed if unanswered

*(Neutral defaults to state aloud — not a copilot assumption. We locate on the spectrum, we don't presume it.)*
- **Design the read/consumption path first** — it's common to every agent type — and treat **action-taking as a layered extension** gated by bucket A/E answers.
- Consume via a **governed semantic layer / tool surface**, not free-form SQL on raw tables — safe across all autonomy levels.
- Treat workflow metrics as **PII-free by construction**; keep PII out of the marts agents can reach.
- Make the agent a **scoped, least-privilege principal** with Unity Catalog security enforced by identity — whether that identity is a user or a service principal.
- Assume **minutes-fresh** metrics for v1 (batch/micro-batch), with a **streaming path** held in reserve for real-time/event-triggered agents.
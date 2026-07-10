# Doma & the Title-Insurance Domain — Reference Notes

**Purpose:** domain grounding for the workflow-metrics platform design. Use it to make the block docs *specific to Doma* rather than a generic platform pitch.

> **Sourcing caveat:** Doma's public materials, industry workflow, and the MISMO/ALTA data standards are **sourced** (links at the bottom). Doma's *internal schema and API endpoint reference are partner-gated* (the company went private in 2024), so the **entities and metrics below are inferred** from the public workflow + industry standards — a good proxy for design, not Doma's literal model.

---

## 1. What Doma is (two businesses)

- **Doma Underwriting** (formerly North American Title Insurance Co) — the licensed **title insurer/underwriter**. ~49 states + DC, residential (purchase + refinance) and commercial.
- **Doma Enterprise / tech platform** — an **AI-first title & escrow platform** sold to lenders and title agents (title & escrow, CRM, market-intelligence network, AgentMarketplace).
- **Corporate:** IPO on NYSE 2021; **taken private by Centerbridge Partners in 2024.**
- **Marquee customers:** Chase, Wells Fargo, PennyMac, Homepoint.

## 2. The differentiator — instant underwriting

- ML models ingest **hundreds of property data points** (public + purchased), produce a **risk decision in <3 seconds**, and classify a property **"safe" vs "risky."**
- **~80%** of transactions get an **instant clear-to-close title commitment in minutes** vs. the traditional **5–10 days**; **"risky"** files fall back to a **traditional manual title search**.
- Premise: **<10% of properties have a title defect**, yet traditional methods examine 100% of orders.
- **Touted metrics** (useful vocabulary): <3s risk decision, ~80% instant-commitment rate, **50% fewer touches**, **15% faster closings**, **20% cost savings**.
- Related products: **Title Alternatives / Upfront Title**, **fee balancing**.
- **This instant-vs-manual fork is the Doma-specific structural feature to model** (it lets you compare the two paths' cycle time and cost).

## 3. Interfaces & integrations

- **Public API suite** for custom integrations + a dedicated integrations team. *(No public endpoint reference — partner-gated.)*
- **Title middleware integrations:** ClosingCorp, Dark Matter, ValuTrust, TitlePort.
- **LOS integration:** Encompass (largest LOS).
- **Security:** SOC 2 Type II certified.
- **Industry data standards (the modeling anchor):**
  - **MISMO** — Mortgage Industry Standards Maintenance Organization; Reference Model v3.4/3.6; the canonical mortgage data dictionary/XML schema.
  - **ALTA** — American Land Title Association; the **ALTA Title Policy Dataset** and **ALTA Settlement Statement Dataset** are now MISMO-mapped.
  - **Implication:** model source entities/fields **to MISMO/ALTA** and you approximate how Doma's API and lender integrations are actually shaped. Naming MISMO/ALTA is a strong, specific signal in the interview.

---

## 4. The order/file lifecycle (workflow backbone)

The **order (title file) is the spine.** Enriched, real-terms stages:

```
Open order → Data collection → Underwriting decision (INSTANT vs MANUAL search)
  → Title commitment issued (Schedule A/B: exceptions + requirements)
  → Curative (clear exceptions: liens, payoffs, subordinations, survey)
  → Escrow / settlement setup (earnest money, CD / settlement statement prep)
  → Clear-to-close → Closing / signing (notary / RON, CPL)
  → Funding / disbursement → Recording → Policy issuance → Post-closing QC
```

- **Instant path** skips `title_search` / `examination` (commitment issued directly).
- **Manual path** traverses `title_search → examination → commitment`.
- Some stages **overlap** (curative often runs parallel with escrow setup) — matters for additivity of durations.

## 5. Likely core entities

**Spine / facts**
- **Order (title file)** — id, type (purchase/refi/commercial), state, source (LOS/agent), status, milestone dates.
- **Order_stage_event** — transition/occupancy grain; the cycle-time / SLA source of truth.
- **Underwriting_decision** — instant vs manual, risk score, safe/risky, **model version**, decision latency *(Doma-distinct)*.
- **Curative_item** — each exception/requirement: type (lien/tax/judgment/survey), open→cleared, aging.
- **Disbursement / financial** — payoffs, wires, CD line items.

**Dimensions (several SCD2)**
- **Property** — APN/parcel, legal description, county, type, ML feature attributes.
- **Party** — borrower/seller/lender/agent + roles (**PII/NPI-heavy** → masking tier).
- **Loan** — amount, number, purpose, LOS ref (MISMO loan data).
- **Commitment / Policy** — Schedule A (insured, amount), Schedule B (exceptions), policy type (owner's/lender's, ALTA form), premium, endorsements.
- **Agent / Branch / Office** — org rollups (SCD2).
- **Jurisdiction (state/county)** — rates/requirements vary by state (SCD2).
- **SLA policy** — per-stage/state targets (SCD2; the as-of-join dimension).
- **Documents** — commitment, CD, CPL, deed of trust, tax cert, chain of title.

## 6. Likely metrics

**Operational / throughput** (most likely "workflow metrics")
- **Turn time / cycle time** — overall and **by stage**.
- **Open orders / WIP**, order **aging / backlog**, **open-vs-closed %**.
- **Pull-through / fallout rate** (closed ÷ opened; cancellations + reasons).
- **Rework / kickback rate**, **SLA breach rate by stage**.
- **Touches per file**, **throughput** (orders closed / period).

**AI / underwriting (Doma-distinct)**
- **Instant-underwriting rate** (% instant vs manual) — the signature number.
- **Risk-decision latency** (<3s), **safe/risky distribution**, **model-version performance**, instant→manual **downgrade rate**.

**Financial / risk**
- **Billable hours per file**, **revenue per FTE**, **variable cost rate**, cost per file.
- **Claims / loss ratio**, **defect rate** (the <10% premise).

## 7. Modeling implications (how this maps to the blocks)

- **Block 1 — backbone:** use the real 11-stage lifecycle and model the **instant-vs-manual fork** explicitly so path cycle-time/cost is comparable.
- **Block 1 — contracts:** cite **MISMO/ALTA** as the source-schema standard for the app-eng data contract.
- **Block 1 — governance:** **Party/Loan** are the NPI concentration; the **PII-free consumer tier** keeps order/stage facts and drops them.
- **Block 3 — agent:** highest-value questions become Doma-shaped, e.g. *"which manual-path orders are aging in curative past SLA?"* — needing the underwriting-decision fact + SCD2 SLA policy.

---

## Sources

- Doma — [Enterprise](https://www.doma.com/) · [Technology](https://www.doma.com/tech/technology/) · [Instant underwriting explainer](https://www.doma.com/3-things-you-need-to-know-about-instant-title-escrow/) · [ML to ~83% of market](https://www.doma.com/doma-brings-machine-learning-technology-to-approximately-83-of-us-residential-real-estate-market/)
- Standards — [MISMO Dataset Specifications](https://www.mismo.org/standards-resources/residential-specifications/datasets) · [HousingWire: MISMO/ALTA title & settlement standards](https://www.housingwire.com/articles/mismo-alta-title-settlement-standards/) · [ALTA: Time for Title Data Standards](https://www.alta.org/news-and-publications/news/20210825-Time-for-Title-Data-Standards-Is-Now)
- Workflow — [Old Republic Title: Escrow & Closing](https://www.oldrepublictitle.com/homeowners/escrow-closing/) · [CertifID: Clear title workflow](https://www.certifid.com/article/clear-title-workflow)
- Metrics/KPIs — [Title & Escrow KPIs](https://financialmodelslab.com/blogs/kpi-metrics/property-title-and-escrow-services) · [Single Point Solutions: Title/Escrow KPIs](https://www.spsgis.com/six-performance-indicators-every-title-escrow-company-should-monitor/)

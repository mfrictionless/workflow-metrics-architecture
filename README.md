# Workflow metrics

## Summary
Design and implementation for a title/closing **workflow-metrics platform**: model operational workflow data into a governed mart, and serve the metrics to a read-only retrieval agent.


## Repo map

For the top-level component/folder layout of the monorepo, see [Technical-Design.md §9 — Repository layout](design/Technical-Design.md#9-repository-layout).

### Design documents (`design/`)
| File | Purpose |
|------|---------|
| [Requirements.md](design/Requirements.md) | Product requirements document: problem statement, goals, metrics, and use cases for the working example |
| [Home-Refinance-Workflow.md](design/Home-Refinance-Workflow.md) | Business process reference: residential refinance closing workflow steps and parties involved |
| [Technical-Design.md](design/Technical-Design.md) | System architecture: component choices, data model, freshness analysis, and governance approach |
| [Process.md](design/Process.md) | Working agreement: the milestone loop, milestone template, test strategy, and definition of done |
| [Decisions.md](design/Decisions.md) | Append-only decision log (D001, D002, …): rationale, design changes, and trade-offs for major decisions |
| [Milestones.md](design/Milestones.md) | Testable build milestones (M0–M7): units of work with clear test and acceptance criteria |

### Reference documentation (`docs/`)
| File | Purpose |
|------|---------|
| [modeling-and-governance.md](docs/modeling-and-governance.md) | Data model design: ODS schema (files, file_actions), metrics definitions, and mart grain statement |
| [pipeline-and-agent-consumption.md](docs/pipeline-and-agent-consumption.md) | Consumer patterns: read-only agent design for SLA nudging and analyst dashboard consumption |
| [dual-postgres-replication.md](docs/dual-postgres-replication.md) | Replication architecture: CDC, cross-database replication, and change propagation strategy |
| [pipeline.png](docs/pipeline.png) | Architecture diagram showing source → replication → mart → consumers flow |
| [replication.png](docs/replication.png) | Replication and change-data-capture flow diagram |

### Root files
| File | Purpose |
|------|---------|
| [CLAUDE.md](CLAUDE.md) | Project instructions: editing standards, agent behavior guidelines, and references |
| [README.md](README.md) | This file: project overview and repository map |


## 10. Definitions

- **AMOD** — a title and closing technology company; the system owner in this working example.
- **ALTA** — American Land Title Association; title-industry data standards.
- **BI** — business intelligence (dashboards and reporting tools).
- **CD** — Closing Disclosure; the final settlement figures delivered to the borrower
  before signing.
- **CDC** — change data capture; streaming row-level changes out of a database.
- **DDL** — data definition language (the `CREATE TABLE` half of SQL).
- **GLBA** — Gramm–Leach–Bliley Act; U.S. law governing financial-data privacy.
- **HOA** — homeowners association; typically a requirement when a residential property is in a community with HOA governance.
- **MISMO** — Mortgage Industry Standards Maintenance Organization; the mortgage
  data dictionary and schema standard.
- **NPI** — nonpublic personal information (the data class GLBA protects).
- **ODS** — operational data store; the live application database we source from.
- **PII** — personally identifiable information.
- **PRD** — product requirements document (this file's format).
- **RACI** — Responsible, Accountable, Consulted, Informed; a responsibility-assignment
  model (R performs, A owns the outcome, C is consulted, I is notified).
- **SLA** — service-level agreement; a per-step or per-stage time target.
- **SQL** — structured query language.
- **WIP** — work in progress (open, unfinished files).
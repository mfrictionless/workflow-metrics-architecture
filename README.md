# Workflow metrics

## Summary
Design and implmentation for a title/closing **workflow-metrics platform**: model operational workflow data into a governed mart, and serve the metrics to a read-only retrieval agent.


## Repo map

### Design documents (`design/`)
| File | Purpose |
|------|---------|
| [Requirements.md](design/Requirements.md) | Product requirements document: problem statement, goals, metrics, and use cases for the working example |
| [Home-Refinance-Workflow.md](design/Home-Refinance-Workflow.md) | Business process reference: residential refinance closing workflow steps and parties involved |
| [Decisions.md](design/Decisions.md) | Append-only decision log (D001, D002, …): rationale, design changes, and trade-offs for major decisions |
| [Milestones.md](design/Milestones.md) | Milestone roadmap and context for the working example project |

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
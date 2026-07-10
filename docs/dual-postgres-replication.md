# Block 2 — Dual-Postgres Replication

**Framing:** two Postgres instances, and the entire design hinges on **why there are two**. We do **not** assume — we locate the scenario first, because the "why" dictates the replication *mode*, *topology*, and *consistency* target. Candidate reasons (the spectrum):

- **HA / DR** — a standby for failover; availability is the goal.
- **Read scaling** — offload read/reporting traffic from the write primary.
- **Region split** — geo-locality (latency) or data residency across regions.
- **Migration / blue-green** — version upgrade or provider move; the second is temporary.
- **Workload isolation / CDC source** — a replica that feeds the lakehouse (Block 3) without loading the primary.
- **Active-active / multi-master** — two writable instances; the hardest case (conflicts).

The first bucket locates us; every later bucket's answer shifts with it.

---

## Big buckets (align on these first)

| # | Bucket | The core question it answers |
|---|--------|------------------------------|
| A | Purpose & topology | *Why two, which direction, active-passive or active-active, same region or cross?* |
| B | Replication mechanism | *Physical/streaming, logical, CDC, or managed (DMS) — and whole-cluster or selective?* |
| C | Consistency, lag & failover | *How much data loss / downtime is tolerable (RPO/RTO), sync or async?* |
| D | Schema & change management | *How do DDL, sequences, and new tables propagate without breaking replication?* |
| E | Operations & routing | *How do clients find the primary, and how do we monitor lag and promote?* |
| F | Conflicts | *If both sides write — how are collisions resolved?* |
| G | Security & compliance | *Encryption, replication privileges, and does data cross a residency boundary?* |
| H | Consumption tie-in | *Does the replica also feed the lakehouse, or serve app reads?* |

*(Confirm/adjust these buckets before we drill in.)*

---

## A. Purpose & topology

1. **Why two instances** — HA, read scaling, region split, migration, CDC source, or active-active? → *the master switch; the replication mode follows from this.*
2. **One-way or bidirectional?** Does only the primary take writes, or both? → *unidirectional is standard; bidirectional forces conflict handling (bucket F).*
3. **Same region or cross-region?** → *cross-region adds latency, cost, and residency concerns (bucket G).*
4. **Is the second instance permanent or temporary** (e.g., a migration cutover)? → *temporary changes the ops bar and the end-state.*
5. **Same Postgres version and platform** on both? → *physical replication requires matching major version/arch; logical does not.*

## B. Replication mechanism

1. **Physical/streaming vs logical vs CDC vs managed (DMS)?** → *the core mechanism choice — see the selection logic below.*
2. **Whole cluster or selected tables?** → *physical = whole cluster; logical/CDC = per-table selectivity.*
3. **Must the target be writable** (serve its own writes) or strictly read-only? → *physical standby is read-only; logical/CDC targets can be writable.*
4. **Is this feeding a downstream consumer** (Kafka/lakehouse) rather than another live DB? → *pushes toward logical decoding / CDC (Debezium).*

## C. Consistency, lag & failover

1. **RPO — how much data loss is tolerable on failover?** Zero, seconds, minutes? → *zero-loss demands synchronous replication (latency cost); otherwise async.*
2. **RTO — how fast must we recover?** → *drives automated vs manual promotion.*
3. **Synchronous or asynchronous commit?** → *sync protects data but couples primary latency to the standby; async is faster but can lose the last transactions.*
4. **Acceptable replica lag** for read/reporting use? → *stale reads on an async replica; bounds what the replica can serve.*
5. **Failover: automatic or manual, and how is split-brain prevented?** → *fencing/STONITH, a single-writer guarantee.*

## D. Schema & change management

1. **How do DDL changes propagate?** → *physical replicates DDL automatically; **logical replication does NOT replicate DDL** — schema changes must be coordinated on both sides.*
2. **Sequences, large objects, and identity columns** — are they in scope? → *logical replication doesn't sync sequences by default; a gotcha on failover/writable targets.*
3. **How are new tables added to the replication set?** → *publication/subscription refresh for logical; automatic for physical.*
4. **Schema-drift detection** between the two? → *contract/monitoring so a divergence doesn't silently break replication.*

## E. Operations & routing

1. **How do clients discover the current primary?** Virtual IP, PgBouncer, service discovery, DNS? → *connection routing so failover is transparent to the app.*
2. **How is replication lag monitored and alerted?** → *`pg_stat_replication`, lag thresholds.*
3. **Replication slot management** — is a slot used, and what happens if the consumer lags? → *slots retain WAL; a stalled consumer can fill the primary's disk (a real outage risk).*
4. **Backups and PITR** — on primary, replica, or both? → *backup strategy independent of replication.*
5. **Rebuild/reseed process** if a replica falls too far behind? → *base backup / re-sync runbook.*

## F. Conflicts *(only if bidirectional / active-active)*

1. **Can both sides write the same rows?** → *if yes, you need a conflict-resolution policy.*
2. **Resolution strategy** — last-write-wins, per-column, app-level, or partition writes by key/region so they never collide? → *partitioning writes avoids conflicts entirely and is usually the sane answer.*
3. **Primary-key / sequence collisions** across instances? → *offset ranges, UUIDs, or composite keys.*

## G. Security & compliance

1. **Encryption in transit** between instances (TLS), and at rest on both? → *baseline for a regulated domain.*
2. **Least-privilege replication role** — scoped to replication, not superuser? → *credential hygiene.*
3. **Does replication cross a data-residency boundary** (state/region/PII)? → *GLBA/NPI and residency constraints on what may leave a region.*
4. **Audit** of the replication link and admin actions? → *compliance logging.*

---

## H. Consumption tie-in

1. **Is the replica also the CDC/extract source for the lakehouse** (Block 3's freshness)? → *offloading extract to the replica protects the primary; ties replication to the analytics pipeline.*
2. **Does the replica serve app read traffic**, or is it purely standby? → *read routing vs. cold standby changes lag tolerance.*
3. **Where does CDC latency land** relative to the "minutes-fresh" target downstream? → *connects replica lag to metric freshness.*

---

## Replication mode — selection logic (the payoff)

**Mode follows purpose.** State this explicitly:

| Why two | Mode | Why |
|---------|------|-----|
| HA / DR | **Physical streaming** (sync or async standby) | Whole-cluster, byte-exact, low lag, simple promotion. |
| Read scaling | **Physical read replica(s)** | Read-only hot standby offloads reporting. |
| Selective sync / cross-version / consolidation | **Logical replication** (pub/sub) | Per-table, cross-version, writable target. |
| Migration / blue-green | **Logical replication** | Cutover with minimal downtime, version bridge. |
| CDC into lakehouse | **Logical decoding** (pgoutput/wal2json → Debezium → Kafka) | Row-level change stream for downstream analytics. |
| Two writable regions | **Active-active** (logical, bidirectional) — *avoid unless required* | Conflict handling is the cost; partition writes if you must. |

**Physical vs. logical, in one breath:** physical = *whole cluster, byte-for-byte WAL, same version, standby read-only, simple, great for HA/read-replicas*. Logical = *selective tables, row-level, cross-version, writable target, but no DDL/sequence replication and more ops*. CDC is logical decoding aimed at a stream, not another live DB.

## How we'd proceed if unanswered

*(Neutral defaults to state aloud — locate on the spectrum, don't presume.)*
- Assume **unidirectional, active-passive** unless told otherwise — bidirectional is the exception and carries conflict cost.
- For **HA**, default to **async streaming replication** with a monitored lag threshold and a documented promotion runbook; escalate to **synchronous** only if RPO must be zero.
- If the second instance exists to **feed the lakehouse**, default to **logical decoding / CDC off a replica** (not the primary) so extract load never touches the write path.
- Route clients through a **proxy (PgBouncer / virtual IP)** so failover is transparent.
- Treat **DDL coordination** and **replication-slot disk risk** as the two most likely operational failure modes and design monitoring for both.
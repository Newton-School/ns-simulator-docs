# Budget Cost Model - All the Math (mapped to real-world cost)

> Every formula, constant, and term used to compute a design's cost, laid out as
> tables and mapped to the three dimensions of a real cloud bill. Companion to
> `budget-feature-consolidated-design-v3.md` (the design) and
> `budget-feature-implementation-v3.md` (the code). All numbers are the V3 **starting**
> values - relative order is the lesson; absolutes are tuned at implementation.

---

## 0. The master formula

```
nodeCost(node) = BASE[type] × replicas  +  ⌊ workers / CAPACITY_UNIT(type) ⌋
edgeCost(edge) = EDGE_BASE            +  ⌊ throughputMBps(edge) / NETWORK_UNIT ⌋

total = Σ nodeCost(all nodes) + Σ edgeCost(all edges)
```

Two terms per node, two per edge. That's the whole model.

> **Operator = `⌊⌋` (floor), not `⌈⌉`.** The scaling terms use **floor** so that a
> *sub-unit* value contributes **0** - you pay only for each **full unit** of capacity
> or traffic you provision. This is required for the model to behave as the design's own
> constants state ("a 1 KB/s link adds 0", "adding 50 workers to a stateless service is
> cheap"). With `ceil`, every node with ≥1 worker and every edge with any traffic would
> cost a spurious +1, and a "thin edge" or a default-sized node could never be free -
> which contradicts every worked example below. (The V3 design draft wrote `ceil`; treat
> that as a typo superseded by its own constant descriptions and by this doc.)

---

## 1. How your six headings map to the math

Your list is **3 real cost dimensions** implemented by **3 model levers**. The mapping
(with the one correction worth noting):

| Your heading | Kind | Maps to term | In the formula |
|--------------|------|--------------|----------------|
| **Compute (The Engines)** | dimension | stateless `BASE` + the capacity term | `BASE[type]×replicas` (low base) + `⌊workers/CAPACITY_UNIT⌋` |
| **Storage (The Data)** | dimension | high `BASE` of stores **× replicas** | `BASE[store]×replicas` (replicas = data stored N times) |
| **Network / Data Transfer (The Hidden Killer)** | dimension | the edge traffic term | `⌊throughputMBps/NETWORK_UNIT⌋` |
| **"Managed Service" Premium (Base Costs)** | lever | `BASE[type]` table | the base of every `nodeCost` |
| **Workers/Capacity Hurt More (Compute Cost)** | lever | `⌊workers/CAPACITY_UNIT(type)⌋` | second node term, unit is type-aware |
| **Edges Represent Data Transfer (Network Cost)** | lever | `EDGE_BASE + ⌊throughputMBps/NETWORK_UNIT⌋` | the whole `edgeCost` |

> **Correction to note:** there is **no separate "storage" term**. Storage cost is
> folded into two places - a store's **high `BASE`** (a managed DB's base already prices
> its hot SSD + backups) and the **`× replicas` multiplier** (3 replicas store the data 3×
> and stand up 3 compute standbys). So "Storage (The Data)" = `BASE[store] × replicas`,
> not a term of its own.

---

## 2. Term-by-term reference

| # | Term | Formula | Dimension | What it charges | The lesson it teaches |
|---|------|---------|-----------|-----------------|-----------------------|
| 1 | Node base | `BASE[type] × replicas` | Compute + Storage | the managed-service premium of the component *type*, multiplied by how many copies you run | "a DB costs several times a stateless worker; each replica pays again" |
| 2 | Node capacity | `⌊ workers / CAPACITY_UNIT(type) ⌋` | Compute | scaling a node's concurrency (worker/connection pool) - **0 below one full unit** | "cranking DB connections is far pricier than cranking worker threads" |
| 3 | Edge base | `EDGE_BASE` | Network | that a link exists at all | "every hop has a small fixed cost" |
| 4 | Edge traffic | `⌊ throughputMBps / NETWORK_UNIT ⌋` | Network | how much **data** flows over the link - **0 below one full unit** | "chatty, heavy links are expensive - cache/batch/trim payloads" |

---

## 3. Constants

| Symbol | Start value | Unit | Meaning |
|--------|-------------|------|---------|
| `DEFAULT_BASE` | 1 | cost | base for any type absent from `BASE` (back-compat) |
| `CAPACITY_UNIT` (stateless) | 100 | workers / cost | throughput scaling on cheap compute is coarse/cheap |
| `CAPACITY_UNIT` (stateful) | 25 | workers / cost | DB connections/IOPS are ~4× costlier per unit |
| `EDGE_BASE` | 1 | cost | fixed per-link cost |
| `NETWORK_UNIT` | 50 | MB/s / cost | a 100 MB/s link adds +2; a 1 KB/s link adds 0 |

`⌊x⌋` = `Math.floor` (pay per full unit; sub-unit = 0). `workers = node.queue.workers ?? 0`.
`replicas = node.resources.replicas ?? 1`.

---

## 4. "Managed Service" Premium - the `BASE[type]` table

Ordering follows the real-world stateless → stateful → premium-managed cost curve.

| Base | Role | Types | Real-world basis |
|-----:|------|-------|------------------|
| 0 | Free source | `api-endpoint` | traffic origin, not billed |
| 2 | Stateless compute / cheap infra | `microservice`, `batch-worker`, `queue`, `load-balancer`, `in-memory-cache`, `object-storage` | raw compute; object storage is the cheap storage tier |
| 3 | Light stateful / edge | `cdn`, `kv-store` | edge + simple managed KV |
| 4 | Managed distributed stores | `message-broker`, `nosql-db`, `time-series-db`, `search-index`, `distributed-lock` | managed distributed systems (patching, replication, failover) |
| 5 | Heavy managed / append-only | `event-sourcing-store` | durable ordered log |
| 6 | Premium managed ACID | `relational-db` | the ACID + hot-SSD + backup + failover premium (Aurora runs ~70% over a raw instance) |
| 1 | *(fallback)* any unlisted type | - | `DEFAULT_BASE`, keeps back-compat |

**Why the spread matters:** `relational-db (6)` vs `in-memory-cache (2)` **is** the
managed-ACID premium. It's what makes "cache vs replicas" a real fork (see §7).

> **Known compression:** `object-storage` is priced at base **2**, identical to
> `in-memory-cache` - even though §9 says storage tiers span ~20× and object storage is
> the *cheap* tier while a cache is a *compute*-tier thing. They collapse to the same
> base in V3 for model simplicity; the tradeoff isn't wrong for any current question, but
> a future "cache vs object-store" lesson would read as "same price," which it isn't.
> Flagged so a later pass can split them (e.g. object-storage → 1) if a question needs it.

---

## 5. Workers / Capacity Hurt More - the type-aware capacity term

```
capacityCost(node) = ⌊ workers / CAPACITY_UNIT(type) ⌋
CAPACITY_UNIT(type) = 25  if type is stateful   (storage-and-data,
                          messaging-and-streaming, consensus-and-coordination)
                    = 100 otherwise (compute/network/etc.)   default 100 if unknown
```

Same 200 workers cost very differently by type; and a **default-sized** node (below one
unit) costs **0** on this term - keeping the initial state clean:

| Node | workers | CAPACITY_UNIT | capacity cost `⌊w/unit⌋` |
|------|--------:|--------------:|-------------------------:|
| `microservice` (default) | 80 | 100 | `⌊80/100⌋` = **0** |
| `microservice` (scaled) | 200 | 100 | `⌊200/100⌋` = **2** |
| `relational-db` (default) | 20 | 25 | `⌊20/25⌋` = **0** |
| `relational-db` (scaled) | 200 | 25 | `⌊200/25⌋` = **8** |

→ Over-provisioning a **DB** connection pool is 4× costlier per unit than a stateless
service (the "workers hurt more, tied to node type" rule), while default sizing is free
until you cross a full unit.

---

## 6. Edges Represent Data Transfer - the network term

```
edgeCost(edge) = EDGE_BASE + ⌊ throughputMBps(edge) / NETWORK_UNIT ⌋
```

`throughputMBps` is **not a stored field** - it's **derived at grade time** from the
simulated per-edge transit count and the workload's payload size:

```
throughputMBps(edge) ≈ (totalSuccessfulTransits(edge) × avgPayloadBytes)
                       / (durationSec × 1e6)

avgPayloadBytes = Σ (weightᵢ × sizeBytesᵢ)   over the injected requestDistribution
durationSec     = global.simulationDuration / 1000
```

| Source of each input | Where it comes from |
|----------------------|---------------------|
| `totalSuccessfulTransits(edge)` | `SimulationOutput.perEdge[edge.id]` (seeded run) |
| `avgPayloadBytes` | weighted mean of `suite.cases[].workload.requestDistribution[].sizeBytes` |
| `durationSec` | `topology.global.simulationDuration / 1000` - **must cover the same window as the `totalSuccessfulTransits` count** (if the metric excludes warm-up, subtract `warmupDuration`); on a constant source the two cancel (see §8) so the choice only matters for transient-heavy workloads |

> ⚠️ **Coarse proxy:** one workload-wide mean payload is applied to *every* edge (ignores
> per-edge byte differences, request↔response asymmetry, cache hit-rate). Relative order
> is the lesson; the absolute MB/s is approximate. Per-edge byte tagging is a later
> refinement. Because it needs a run, the **live meter shows base+capacity only** and the
> network term appears after Run / at grade time.

Worked link costs at `NETWORK_UNIT = 50` (floor → only full 50 MB/s units are charged):

| Link | throughput | edge cost `1 + ⌊MB/s / 50⌋` |
|------|-----------:|----------------------------:|
| thin control call | 0.001 MB/s | `1 + ⌊0.001/50⌋` = `1 + 0` = **1** |
| normal API path | 20 MB/s | `1 + ⌊20/50⌋` = `1 + 0` = **1** |
| busy path | 80 MB/s | `1 + ⌊80/50⌋` = `1 + 1` = **2** |
| fat service-to-service stream | 300 MB/s | `1 + ⌊300/50⌋` = `1 + 6` = **7** |

Note the design intent "a 100 MB/s link adds +2" holds at the unit boundary
(`⌊100/50⌋ = 2`); anything under 50 MB/s adds 0, so ordinary links stay at `EDGE_BASE`.

---

## 7. Worked example - the core lesson ("cache vs 3 replicas")

Fixing a read-latency SLA two ways; assume default workers (capacity term ≈ 0) and thin
edges (cost 1 each) so the *architecture choice* is isolated:

| Design | Node costs | Edge costs | Total |
|--------|------------|-----------:|------:|
| **Add a cache** | `in-memory-cache` = `2×1` = 2 | +1 edge | **+3** |
| **Add 3 read replicas** | `relational-db` = `6×3` = 18 | +3 edges | **+21** |

With a cap set cap-last just above the cache design, the replica design **blows it** - so
the student is forced to discover caching instead of brute-forcing with replicas. That
fork exists *only* because `BASE` is type-aware.

---

## 8. Worked example - full grade-time cost (V3 `async-sla` reference)

`client → svc → queue → worker → relational-db`. This is computed as the **full
grade-time cost** the cap is built from (§1c) - capacity and traffic terms shown
**explicitly**, even where they floor to 0, so the number is right for the right reason
(not the meter's base-only shortcut).

**Nodes** - the reference is deliberately sized **below each type's capacity unit**, so
the capacity term is `0` on every row (a clean initial state) and the table foots to the
total. The `unit` column shows each type's `CAPACITY_UNIT`: `microservice`/`batch-worker`
are stateless (100); **`queue` and `relational-db` are stateful (25)**.

| Node | base×replicas | workers → capacity (unit) | node cost |
|------|--------------:|--------------------------:|----------:|
| `client` (api-endpoint) | `0×1` = 0 | 0 → `⌊0/100⌋` = 0 (100) | **0** |
| `svc` (microservice) | `2×1` = 2 | 80 → `⌊80/100⌋` = 0 (100) | **2** |
| `queue` (stateful) | `2×1` = 2 | 20 → `⌊20/25⌋` = 0 **(25)** | **2** |
| `worker` (batch-worker) | `2×1` = 2 | 80 → `⌊80/100⌋` = 0 (100) | **2** |
| `relational-db` (stateful) | `6×1` = 6 | 20 → `⌊20/25⌋` = 0 **(25)** | **6** |
| | | **nodes subtotal** | **12** |

> To scale a node *past* its unit you add the term - e.g. a `relational-db` at 60 workers
> costs `6×1 + ⌊60/25⌋ = 6 + 2 = 8`, and a `queue` at 300 costs `2 + ⌊300/25⌋ = 14`. The
> reference above avoids that on purpose; the foil below leans into it.

**Edges** - grade-time traffic from the suite (`baseRps 3000`, write payload 512 B). On a
linear path each request traverses each edge once, so
`throughputMBps ≈ (baseRps × avgPayloadBytes) / 1e6` - **the run duration cancels**
(transits ∝ duration), so warm-up windowing doesn't change the estimate as long as the
transit count and `durationSec` (§6) cover the same window:

`throughputMBps ≈ 3000 × 512 / 1e6 ≈ 1.54 MB/s` → `⌊1.54/50⌋ = 0` traffic term.

| Edges | edge base | traffic term | edge cost |
|-------|----------:|-------------:|----------:|
| 4 linear edges | `4×1` = 4 | `4×0` = 0 | **4** |

**Total:** `C_ref = 12 (nodes) + 4 (edges) = 16` - the **full** grade-time cost (§1c), not
a base-only shortcut: the traffic term was computed (~1.54 MB/s) and genuinely floors to 0
because async-sla's write path is far under the 50 MB/s network unit.

Cap-last: `cap = round(16 × 1.15)` = **18**. Foil (sync `client→svc→relational-db ×3`)
`= 0 + 2 + 6×3 + 2 edges` = **22+** → over budget. `C_ref (16) < cap (18) < C_foil (22)` ✓.

---

## 8b. Worked example - the network lesson (`chatty-services`, Phase 3)

The riskiest question to calibrate, because its whole cost is the **traffic term**, so it
must be shown before Phase 3. Throughput values below are **placeholders** pending the
§4d real-fixture measurement - the purpose here is to prove a shippable **integer cap gap
exists**.

**Reference** `client → svc-a → cache → svc-b` (cache absorbs the chatter → thin edges):

| Element | Calc | Cost |
|---------|------|-----:|
| client 0, svc-a 2, cache 2, svc-b 2 | base×1 | 6 |
| 3 edges, all < 50 MB/s → traffic 0 | `3×(1+0)` | 3 |
| **`C_ref`** | | **9** |

**Foil** `client → svc-a → svc-b` (one fat direct link ≈ 300 MB/s):

| Element | Calc | Cost |
|---------|------|-----:|
| client 0, svc-a 2, svc-b 2 | base×1 | 4 |
| `client→svc-a` thin | `1+0` | 1 |
| `svc-a→svc-b` fat ≈300 MB/s | `1 + ⌊300/50⌋` = 1+6 | 7 |
| **`C_foil`** | | **12** |

**Cap-last:** `cap = round(9 × 1.15)` = round(10.35) = **10**.

**Integer-gap check** (the calibration test §4d does *not* do):
`C_ref (9) ≤ cap (10) < C_foil (12)` ✓ - and there are **two** valid integer caps in the
gap (`10`, `11`), so `⌊⌋`-rounding hasn't squeezed out the cap. `non_binding`: `9/10 = 0.9`
(> 0.6) ✓. The foil is *more expensive with fewer nodes* - the whole network lesson: **a
fat link costs more than an extra cache node.**

> **Precondition - the foil must PASS the perf axis.** The guardrail's premise (§1b) is
> that the foil is *correct on every other axis but expensive*. So the fat `svc-a→svc-b`
> link must be provisioned to **meet the latency/SLA** (fast enough) while being **too
> expensive to afford** (over the cap on the traffic term). If dropping the cache also
> blows p99, the foil *fails perf too* and collapses back into the gamed topology §1b
> separated out - no longer a clean "affordable-vs-not" fork. This is a real constraint on
> the throughput/payload numbers §4d measures: it must find a **fast-but-unaffordable**
> link, not merely a heavy one. State it as an authoring precondition, not just `C_foil > cap`.

If the real §4d throughput can't open at least a one-integer gap here **with the foil still
passing perf**, that's the signal to add per-edge byte tagging before shipping
traffic-weighted edges.

---

## 9. Real-world anchoring (why these magnitudes)

The relative sizes aren't arbitrary - they mirror how cloud bills actually decompose:

| Dimension | Model lever | Real-world fact it encodes |
|-----------|-------------|-----------------------------|
| Compute | `BASE` (stateless=2) + capacity | billed per CPU/RAM-second; scaling out is ~linear |
| Managed premium | `BASE` gap (DB 6 vs worker 2) | managed stateful services carry ~20-30% premium (Aurora ~70%) for backups/patching/failover |
| Storage | high store `BASE` **× replicas** | hot SSD ≫ object ≫ archive (tiers span ~20×); replicas store data N× |
| Network | edge traffic term | egress/cross-AZ is ~10-15% of spend and scales with **GB moved**, not link count |

---

## 10. One-line summary

**Cost = what you choose (`BASE[type]`) × how many copies (`replicas`) + how hard you
push each node (`workers / CAPACITY_UNIT`) + how much data crosses each link
(`throughputMBps / NETWORK_UNIT`).** Count is a proxy the old flat model mistook for the
real thing; V3 charges for *choice, replication, capacity, and traffic* instead.

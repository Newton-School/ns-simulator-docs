# Resource Allocation & Derived Concurrency

Technical feature specification defining how physical resource allocation (Compute / RAM / instances) should *derive* a node's queueing capacity, so that concurrency stops being a free-floating dial and becomes a constrained consequence of provisioned hardware. This closes the "anyone can crank `workers` to 1000 and every bottleneck vanishes for free" hole.

This spec exists because the simulator today runs on `queue.workers` (the `c` in G/G/c/K) and `queue.capacity` (the `K`) as **authored magic numbers**, while `ResourceConfig` (cpu, memory, replicas) is defined in the type system, validated, scored by budget/rubric/structural analysis - and **never read by the engine**. This document specifies the derivation that makes `resources` physical.

Related: [`cost-calculation-and-budgeting.md`](./cost-calculation-and-budgeting.md) (same dormant `ResourceConfig`, cost angle), [`queue-depth-calculation.md`](./queue-depth-calculation.md), [`request-rejection-behaviour.md`](./request-rejection-behaviour.md), [`question-grading-model-and-anti-gaming.md`](./question-grading-model-and-anti-gaming.md).

---

## Table of Contents

1. [Problem Context](#problem-context)
2. [Mental model: workers, queues, and hardware](#mental-model-workers-queues-and-hardware)
3. [Design Principle: the honesty ledger](#design-principle-the-honesty-ledger)
4. [No infinite dials: the AWS instance model](#no-infinite-dials-the-aws-instance-model)
5. [The instance catalog](#the-instance-catalog)
6. [The caps: quota, cost, and per-node](#the-caps-quota-cost-and-per-node)
7. [Cost model: where cost comes from](#cost-model-where-cost-comes-from)
8. [Cost sourcing: the authoritative per-component reference](#cost-sourcing-the-authoritative-per-component-reference)
9. [The derivation model](#the-derivation-model)
9. [Worked examples](#worked-examples)
10. [Schema changes](#schema-changes)
11. [New failure modes](#new-failure-modes)
12. [What stays untouched](#what-stays-untouched)
13. [Phasing: the honest slices](#phasing-the-honest-slices)
14. [Mapping to the question bank](#mapping-to-the-question-bank)
15. [Source-to-feature map](#source-to-feature-map)
16. [Open questions](#open-questions)

---

## Problem Context

Two parallel "capacity" concepts exist in the codebase, and only one drives the simulation:

| Concept | Field | Status today |
|---|---|---|
| Concurrency (`c`) | `queue.workers` | **Drives the sim.** More workers → more parallel service → utilization drops, queue drains. Free-floating input. |
| Buffer (`K`) | `queue.capacity` | **Drives the sim** - the drop/reject boundary. Arbitrary authored constant. |
| Physical resources | `resources: { cpu, memory, replicas, maxReplicas }` | **Decorative.** Defined in `src/engine/core/types.ts:214`. The engine (`GGcKNode`) never reads it. Only `budget.ts`, `structural.ts`, `rubric.ts` touch it - for *scoring*, not physics. |

The consequence: a student types `workers: 1000` and every bottleneck disappears, backed by nothing physical. The only pushback is `estimateNodeCost` in `src/engine/analysis/budget.ts:37` - a soft heuristic (`1 + replicas + ⌈workers/50⌉`) that dings the *budget score* but does not change the *simulation*. And `replicas` is *counted* by rubric/structural scoring while being *ignored* by the engine, so the score rewards something the physics doesn't model - internally inconsistent.

The originating feedback: **"Resource allocation - Compute, RAM, instances - reasoning being anyone can increase the number of workers & queues and more."** Reframed precisely: *concurrency should be a derived consequence of provisioned resources, not a free-floating dial.* `workers` should be demoted from a pure input to a **request that resources cap**.

---

## Mental model: workers, queues, and hardware

The engine models each node as a **G/G/c/K queue**. Two of those letters are the knobs this spec is about:

- **`c` = workers = parallel servers.** A "worker" processes **one request at a time**. `c` workers means `c` requests are actively being served *simultaneously*. Think cooks in a kitchen: 8 cooks → 8 orders in progress at once. This is `queue.workers`.
- **`K` = system capacity = in-service + waiting.** Requests that arrive while all `c` workers are busy **wait in the queue**. `K` is the total the node can hold - the `c` being served **plus** the ones waiting. When the system is at `K` and another arrives, it's **rejected** (`queue_full`). This is `queue.capacity`. (The `G/G` prefix just means arrivals and service times can follow general distributions - not relevant to this spec.)

A request's life: free worker? → **served now.** All busy? → **wait in queue.** Queue full (at `K`)? → **rejected.**

**Today `c` and `K` are free-typed numbers** backed by nothing physical - you can declare 1000 workers on a machine the size of a closet. CPU and RAM are what make them physical:

- **CPU ↔ `c` (workers).** A worker doing real CPU work needs a core to run on. ~1 truly-parallel worker per vCPU. Claim 1000 workers on 4 vCPU and you don't get 1000× throughput - you get 4 cores frantically time-slicing 1000 half-done requests, so everything just slows down (**contention** → service time inflates). *Caveat:* this only bites **CPU-bound** work. An **IO-bound** worker mostly *waits* on a DB/network (not using the CPU), so workers ≫ vCPU is legitimate there - which is why the vCPU cap is gated on `workloadKind`.
- **RAM ↔ `K` (queue depth).** Every request in the node - being served *or* waiting - occupies memory (its data, buffers, connection). So `K ≤ totalRAM ÷ memory-per-request`. 8 GB at 40 MB/request → you physically cannot hold more than ~200, whatever you typed. The 201st doesn't queue - it **`oom`**s (a distinct failure with a distinct fix: add RAM/instances, not workers).

So the two things authors used to type freely become the **ceiling they're *requesting***, while CPU/RAM (from the instance type × count) are the **ceiling reality *allows***. **The node gets the smaller of the two** - that is the entire derivation:

| Authored (a request) | Physically capped by | Consequence when exceeded |
|---|---|---|
| **workers** (`c`, parallel service) | **vCPU** (CPU-bound only) | not a terminal - slows down (contention) |
| **queue capacity** (`K`, waiting room) | **RAM** (bytes per request) | `oom` terminal |
| **instance count** | **maxInstances** + env vCPU/RAM budget | build-time validation / budget error |

To go faster you don't type a bigger number - you **provision more hardware** (bigger instance type, or more instances), which spends from a capped budget. Exactly like AWS.

---

## Design Principle: the honesty ledger

The governing principle (from the honesty-redesign roadmap): **every number the UI shows is a mechanical projection of one real per-request truth - never a magic constant, a survivor-biased average, or a snapshot artifact.** A "slice" = one node property made to obey that.

Where resource allocation sits on that ledger today:

**Already honest (done & verified elsewhere):** time-weighted utilization integral (not snapshot average); success latency labeled "successful only"; closed terminal taxonomy (`queue_full/node_failed/network_error/timeout/connection_reset/rejected`); latency decomposition that sums exactly; failure-by-locus Pareto that reconciles; per-node aggregators; arrival-CV.

**Not yet honest (this spec's targets):**

| Surface | Why it's dishonest today |
|---|---|
| `queue.workers` / concurrency | Free-floating magic number; typing 1000 dissolves any bottleneck, backed by nothing. |
| `resources` (cpu/memory/replicas) | Pure decoration - on screen, changes nothing in the sim. A number that changes nothing is the definition of dishonest here. |
| `queue.capacity` (K) | Arbitrary authored constant; should be RAM-derived and defensible. |
| `replicas` | Scored by rubric/structural but doesn't multiply concurrency in the sim - score rewards what physics ignores. |
| Budget `estimateNodeCost` | Self-admittedly "without a real price sheet"; dings score not physics, so it's bypassable. |

The design converts these ❌ rows toward ✅ by making `resources` the thing that *derives* `c` and `K`, with the derived values surfaced inline with their provenance.

---

## No infinite dials: the AWS instance model

The free `{ cpu, memory }` pair in the first draft of this spec still lets a student type "6.5 vCPU, 12 GB" and, worse, ask for infinite RAM with tiny CPU. That's not how real infrastructure works, and it doesn't close the gaming hole. The corrected model mirrors AWS: **you don't free-type resources - you pick a discrete instance *type* off a menu, and you scale by instance *count*, which is quota-capped.**

Two properties fall out of this, both serving the anti-gaming goal:

1. **CPU and RAM are coupled, not independent dials.** To get more RAM you take a bigger instance, which also costs more vCPU and more money. Every axis moves together, the way real hardware does - killing the "crank the one number that unblocks me" move.
2. **Fixed CPU:RAM ratios teach a real decision.** Choosing compute-optimized (`c5`, ~2 GB/vCPU) vs memory-optimized (`r5`, ~8 GB/vCPU) is an actual system-design choice. A free `{cpu, memory}` pair lets a student sidestep it.

Scaling is then **count × capped**: you scale horizontally by instance count (`instanceCount`, the old `replicas`), never by inflating one box infinitely, and the count is bounded by a quota (see [The two-level quota](#the-two-level-quota)).

Three caps together stop infinite scaling:

- **Per-instance CPU/RAM** - fixed by the instance type picked (can't exceed the SKU).
- **Instance count** - bounded by `maxInstances` (per-node) and by the environment vCPU/RAM budget.
- **Workers / queue** - no longer free; capped by the CPU/RAM the instances actually provide (the derivation below).

---

## The instance catalog

A fixed reference table the author picks from - **not free-typed**. Curated to mirror the AWS families (general-purpose / compute-optimized / memory-optimized / burstable) with faithful CPU:RAM ratios, kept small enough to be a legible menu. `ramGbPerVcpu` is shown to make the family's character obvious.

| `instanceType` | Family | vCPU | RAM (GB) | GB/vCPU | $/hr | Character |
|---|---|---:|---:|---:|---:|---|
| `t3.small`    | Burstable        | 2  | 2   | 1  | 0.021 | Cheap, bursty; baseline CPU credits |
| `t3.medium`   | Burstable        | 2  | 4   | 2  | 0.042 | Cheap general baseline |
| `m5.large`    | General          | 2  | 8   | 4  | 0.096 | Balanced default |
| `m5.xlarge`   | General          | 4  | 16  | 4  | 0.192 | Balanced, larger |
| `m5.2xlarge`  | General          | 8  | 32  | 4  | 0.384 | Balanced, big |
| `c5.large`    | Compute-optimized | 2  | 4   | 2  | 0.085 | CPU-heavy work |
| `c5.xlarge`   | Compute-optimized | 4  | 8   | 2  | 0.170 | CPU-heavy, larger |
| `c5.2xlarge`  | Compute-optimized | 8  | 16  | 2  | 0.340 | CPU-heavy, big |
| `r5.large`    | Memory-optimized  | 2  | 16  | 8  | 0.126 | RAM-heavy (caches, in-mem stores) |
| `r5.xlarge`   | Memory-optimized  | 4  | 32  | 8  | 0.252 | RAM-heavy, larger |
| `r5.2xlarge`  | Memory-optimized  | 8  | 64  | 8  | 0.504 | RAM-heavy, big |
| `x1e.xlarge`  | Memory-extreme    | 4  | 122 | 30 | 0.834 | Extreme RAM (rare, expensive) |

The catalog is a curated pedagogical set, not the full AWS SKU list - three ratio tiers (2 / 4 / 8 GB-per-vCPU) plus a burstable floor and a memory-extreme ceiling, at 2/4/8-vCPU sizes so scaling *up* (bigger type) and scaling *out* (more instances) are both expressible. Prices are AWS-proportional on-demand `$/hr` (us-east-1 order of magnitude) so the *relative* tradeoffs are faithful - compute-optimized is cheaper per vCPU, memory-optimized costs a premium per GB, `x1e` is deliberately expensive. Lives as a frozen reference table (proposed `src/engine/catalog/instanceCatalog.ts`); authoring picks an `instanceType` key, and the engine resolves `{ vcpu, ramGb, pricePerHour }` from it.

---

## The caps: quota, cost, and per-node

**Cost and quota are two *different* caps, and both apply.** They constrain different things and a design can pass one while failing the other, which is exactly the point - real infrastructure is bounded by *both* "is the hardware available?" (quota) and "can we afford it?" (cost):

- **Quota** = physical availability. You can't provision vCPU/RAM that doesn't exist in your allocation. A hard wall.
- **Cost** = money. The hardware may be available, but the monthly bill is capped. A different wall - and often the binding one, since money runs out before a region's capacity does.

Three caps in total, composing - a node/topology must satisfy **all** of them:

**1. Per-node cap (`maxInstances`)** - author-set on a node. "This service may scale to at most N instances." Bounds horizontal scaling of one component; the author's lever for shaping a specific bottleneck ("the DB can't scale past 3"). Exceeding it is a **build-time validation error**.

**2. Per-environment resource quota (`resourceBudget`)** - a hardware wallet: total vCPU and total RAM available across the whole topology. Forces allocation tradeoffs ("you have 40 vCPU and 160 GB - spend them"). Exceeding it is a **build-time budget failure**, surfaced live.

**3. Per-environment cost budget (`costBudget`)** - a money wallet: max spend for the whole topology, in `$/hr` (derived from the instance prices). Exceeding it is a **build-time budget failure**, surfaced live, on the same channel as the resource quota.

```
// 1. Per-node
nodeInstances ≤ node.resources.maxInstances

// 2. Per-environment resource quota (summed over all nodes)
Σ (instanceType.vcpu  × instanceCount)  ≤  env.resourceBudget.totalVcpu
Σ (instanceType.ramGb × instanceCount)  ≤  env.resourceBudget.totalRamGb

// 3. Per-environment cost budget (summed over all nodes)
totalCostPerHour = Σ (instanceType.pricePerHour × instanceCount)
totalCostPerHour ≤ env.costBudget.maxPerHour
```

Budget violations (2, 3) are **build-time** failures, not runtime terminals - you can't provision hardware you can't afford or that doesn't exist. They gate authoring/submission the same way the existing budget breakdown does.

### Always show the cost - even when unbounded

**The architecture's cost is displayed at all times, regardless of whether a cap is set.** Cost is a first-class output of every topology, not just a gate that appears when a budget exists. Even in AUTHOR mode or an open build with no `costBudget`, the simulator shows `totalCostPerHour` (and the per-node breakdown - which component drives the bill). Rationale: cost-awareness is the requirement, and a number that only appears when you're failing teaches nothing; a number that's *always visible* teaches the tradeoff on every edit. When a `costBudget` *is* set, the same display gains a "X / Y ($/hr) - within/over budget" framing. This reuses `budgetBreakdown` in `src/engine/analysis/budget.ts` (already returns per-node line items) - the cost model just becomes the instance-price sum instead of the `estimateNodeCost` heuristic.

### Defaults when a question sets no budget

| Mode | Resource quota | Cost budget | Cost display |
|---|---|---|---|
| **AUTHOR** | unbounded | unbounded | **always shown** (per-node + total) |
| **Open build** (no budget set) | unbounded | unbounded | **always shown** |
| **ASSIGNMENT / PRACTICE** | author may set | author may set | **always shown**; when a cap is set, framed as used / cap |

Unbounded means "no cap," **not** "no cost" - the bill is still computed and displayed everywhere. Both `resourceBudget` and `costBudget` are optional on the environment lens; absent = that particular cap doesn't gate, but the cost readout never disappears.

---

## Cost model: where cost comes from

Cloud pricing has ~9 dimensions (compute-time, request/invocation, data volume, per-user, subscription, percentage-of-spend, feature/licensing, market/spot, physical hardware). **The simulator deliberately models only a subset**, chosen by one filter.

### The filter: only bill what the engine measures

A cost is dishonest the moment it's backed by a quantity the simulator doesn't actually produce - that's the same magic-number problem this whole spec fights, wearing a dollar sign. So the test for every pricing dimension is: **does the engine already emit the quantity it bills?** If we'd have to invent the quantity, we don't bill it.

| Pricing dimension | Quantity needed | Sim produces it? | Verdict |
|---|---|---|---|
| **Compute (time & capacity)** | instance type × count × runtime | **Yes** - `INSTANCE_CATALOG`, `instanceCount`, run horizon | **IN - axis 1 (provisioned)** |
| **Request (invocation)** | per-node request counts, read/write split | **Yes** - `MetricsCollector` counts terminals per node | **IN - axis 2 (consumption)** |
| **Volume - network transfer** | bytes/request, cross-region edges | **Partly** - edges + region/AZ composites exist; requests carry no reliable byte size yet | **IN - axis 3, GATED** |
| Volume - storage-at-rest (GB-month) | stored data footprint | No - sim models flow, not data at rest | Deferred |
| User (MAU / seats) | human identities | No - sim models requests, not users | Out |
| Subscription / flat-fee | a constant | trivial, no lesson | Out (v1) |
| Percentage (support) | % of total spend | trivial multiplier on total | Out (v1) |
| Feature / licensing / OS | price modifier on instance | possible later as a catalog flag | Deferred |
| Market (spot) | price × termination risk | ties to fault-injection (not yet wired) | Deferred (v2) |
| Physical hardware / appliances | shipped devices | No - irrelevant to a topology sim | Out |

Of nine dimensions, three are sourceable; only the first two are solid today (axis 3 waits on the request-size model - the same open dependency as `perRequestMemMb`).

### The core lesson: provisioned vs consumption

Axes 1 and 2 are not just two line items - they are the two cost **regimes**, and choosing between them is a real system-design decision the simulator should force:

- **Axis 1 - provisioned** (compute-time). You pay for the box whether or not traffic comes. An always-on fleet. `cost = pricePerHour × instanceCount`. Flat; idle capacity is wasted money. Maps to `compute-service` / `worker` / `datastore` nodes.
- **Axis 2 - consumption** (per-request). You pay per request, nothing when idle. Serverless / Lambda / on-demand DB. `cost = pricePerMillionRequests × observedThroughput`. Tracks load; a spike costs linearly. Maps to a serverless-flagged node.

Both normalize to `$/hr` given the arrival rate, so they sit on **one comparable axis**. The exam question - *"at this traffic shape, is a provisioned fleet or a per-request service cheaper?"* - only exists because both regimes are modeled. **This comparison is what makes cost worth teaching** rather than a decorative total: it turns cost from a number you avoid exceeding into a design tradeoff you reason about on every edit.

```
// axis 1 - provisioned node
nodeCostPerHour = instanceType.pricePerHour × instanceCount

// axis 2 - consumption node (billed on measured throughput, not provisioned capacity)
nodeCostPerHour = pricePerMillionRequests × (observedRps × 3600 / 1_000_000)

// axis 3 - network egress (GATED on per-request byte size)
edgeCostPerHour = pricePerGb × (observedRps × bytesPerRequest × 3600 / 1e9)
//   inter-region edges (region-crossing, from composite membership) priced higher than intra-zone

topologyCostPerHour = Σ nodeCostPerHour + Σ edgeCostPerHour
```

### Explicitly out of scope (with reasons, so nobody re-adds them blindly)

- **Storage-at-rest (GB-month)** - the sim has no concept of stored data volume; it models request flow, not a data footprint. Would be an invented number.
- **Per-user / seats** - the sim models requests, not human identities.
- **Subscription, percentage-of-spend, licensing/OS** - trivial constants or multipliers with no design tradeoff to teach at this stage.
- **Spot / market pricing** - genuinely interesting (spot *termination* ties to the fault-injection suite), but blocked until fault injection is wired; revisit in v2.
- **Physical hardware / appliances** - not part of a topology simulator.

Nobody should later bolt "S3 storage pricing" onto a simulator with no stored-bytes quantity - that reintroduces exactly the dishonesty this section exists to prevent.

---

## Cost sourcing: the authoritative per-component reference

This is the canonical answer to "where does each node's cost come from." Cost is **node-based** and resolved through a four-step lookup, all of which exist in code:

```
palette component  ──paletteTemplates──▶  componentType
componentType      ──resourceDefaults──▶  { instanceType, workloadKind, costModel, pricePerGb? }
instanceType       ──INSTANCE_CATALOG──▶  { vcpu, ramGb, pricePerHour }
node cost/hr       =  by costModel (below)                        (analysis/cost.ts)
topology cost/hr   =  Σ node costs                                (header CostChip)
```

### The `costModel` primitive (how the trait system fits)

Cost basis is a **per-type capability**, declared on `ResourceTypeDefault.costModel` - the same trait-style pattern as `base.queue` / `source.workload`. Four models, because node types cost money in fundamentally different *shapes*:

| `costModel` | Formula | Shape | Applies to |
|---|---|---|---|
| `provisioned` | `pricePerHour × instanceCount` | pure fn of topology → **live, pre-run** | compute, LB, queue, broker, cache, all DBs |
| `volume` | `pricePerGb × bytes-transferred` | needs traffic → **estimate pre-run, exact post-run** | CDN, object-storage |
| `consumption` | `pricePerMillionReq × throughput` | needs traffic → post-run (Slice 4) | serverless (deferred) |
| `none` | - | not billable | sources / client apps |

**Why volume can't be a pure pre-run number like provisioned:** provisioned cost is a function of what you *provisioned* (instances), knowable before any run. Volume cost is a function of *traffic* (bytes egressed), which only exists once requests flow. So volume nodes show a **pre-run estimate** from the configured workload (`baseRps × avg request bytes × pricePerGb`, an upper bound that assumes the node sees full offered load - routing is a post-run concern), and can be measured exactly after a run. This is real physics, not a modelling gap.

### Authoritative table - visible palette (V1 focus)

| Palette | componentType | costModel | Default instance | $/hr or $/GB | Notes |
|---|---|---|---|---|---|
| Client App / Input Source | api-endpoint (source) | `none` | - | $0 | traffic source, not infra |
| API Server / Service / My Service | microservice | provisioned | `c5.large` | 0.085/hr | compute-opt |
| Job Worker / Cron Job | batch-worker | provisioned | `c5.large` | 0.085/hr | compute-opt |
| Load Balancer | load-balancer | provisioned | `m5.large` | 0.096/hr | general |
| Message Queue | queue | provisioned | `m5.large` | 0.096/hr | backpressure |
| Event Broker | message-broker | provisioned | `r5.large` | 0.126/hr | memory-opt |
| Redis Cache | in-memory-cache | provisioned | `r5.large` | 0.126/hr | memory-opt |
| KV Store | kv-store | provisioned | `m5.large` | 0.096/hr | - |
| NoSQL DB | nosql-db | provisioned | `m5.xlarge` | 0.192/hr | - |
| Primary DB / Read Replica | relational-db | provisioned | `m5.xlarge` | 0.192/hr | - |
| Time-series DB | time-series-db | provisioned | `r5.xlarge` | 0.252/hr | memory-opt, write-heavy |
| CDN | cdn | **volume** | (n/a for cost) | **0.085/GB** | egress; `instanceType` only sizes the queue |
| Object Storage | object-storage | **volume** | (n/a for cost) | **0.09/GB** | egress; storage GB-month still unmodeled |

For `volume` types the `instanceType` is retained **only** to size the G/G/c/K queue (they still serve requests) - it does **not** drive their cost. Their cost is per-GB egress.

### CDN / Object-Storage: why they were placeholders, and the fix

They were briefly priced as an `m5.large` because the cost model only knew `provisioned`. That was wrong - CloudFront bills per-GB egress, S3 per-GB-month storage + egress, neither in instance-hours. The fix is the `volume` costModel above: they now show a per-GB rate and a workload-based egress estimate, never a fake instance price. **Object-storage's dominant real cost (GB-month storage-at-rest) stays unmodeled** - the sim has no stored-bytes quantity (see out-of-scope) - so only its egress is priced, and that limitation is stated honestly rather than faked.

### Slice 5, restated

Slice 5 **is** this volume axis. Implementing it for the visible nodes = the `volume` costModel + per-GB egress estimate above (done for CDN/object-storage). The remaining Slice-5 work is post-run *measured* egress (exact, per-node, routing-aware) and inter-region transfer pricing via composite membership - layered on once per-node throughput/byte accounting is wired.

---

## The derivation model

> **See also.** The focused explainer for the execution-profile half of this model -
> why io-bound stores show 64-128 workers while cpu-bound services show 2, the
> per-tier defaults, the "workers / connections / consumers / ops are the same
> number" vocabulary, and the `canEditExecutionProfile` lock - lives in
> `execution-profile-and-node-concurrency.md`.

**FINAL MODEL - derive & lock (supersedes the earlier "cap a requested number" drafts).** `workersPerInstance` and `queueSlots` are **not authored at all** - the instance is the *only* allocation knob. Workers and K are pure functions of the hardware, shown read-only. This is the resolution of the original decision #1: keeping them as editable inputs (even capped) let a student type `8×10²⁰` workers and defeat the whole model, so they were removed entirely.

```
{ vcpu, ramGb } = instanceCatalog[instanceType]      // fixed per-instance, from the menu

// Concurrency is DERIVED from the hardware - not a free dial.
workersPerVcpu = workloadKind === 'cpu-bound' ? 1 : IO_WORKERS_PER_VCPU   // 1 vs 32
effectiveC = vcpu × instanceCount × workersPerVcpu   // servers actually serving

// Admission K is DERIVED from RAM (a full node is out of memory → `oom`).
memCeiling = floor( ramGb × 1024 × instanceCount / perRequestMemMb )
effectiveK = max(effectiveC, memCeiling)             // RAM decides the waiting room, never below c
```

`IO_WORKERS_PER_VCPU` (=32) is the global io-bound concurrency knob: a core mostly waiting on IO multiplexes many concurrent requests, but the count is still tethered to the paid hardware tier - never infinite. cpu-bound work runs ~1 parallel worker per vCPU. To get more concurrency you provision a bigger/more instances, which costs money - that *is* the lesson.

Two derived signals the UI surfaces **inline**, read-only (per the honesty principle - every number shows its provenance):

| Derived value | Meaning | Surfaced as |
|---|---|---|
| `effectiveC` | actual `c` in the sim | "64 workers/inst → eff. concurrency 64" |
| `effectiveK` | actual `K` | "admission 256 (RAM-bound)" |

**No oversubscription / contention factor exists anymore** - since workers aren't a requested number, there's nothing to over-request. The vCPU relationship *is* the derivation, not a cap on a separate input. Utilization's time-weighted `busyAreaUs` integral divides by `effectiveC` (still true, `maxWorkers = effectiveC`).

**Separately: Timeout and Mean Service Time are clamped** (Timeout ≤ 60000 ms, service time ≤ 10000 ms) - an input-validation guard unrelated to the instance model, closing the "type `1e38` ms" hole.

---

## Worked examples

Two end-to-end examples, using the catalog numbers, to sanity-check the model before implementation.

### Example 1 - "You can't fake workers" (derivation + caps + provisioned cost)

A student has a **CPU-bound** API service that's a bottleneck. Their instinct: crank the worker count.

**Authored:**
| Field | Value |
|---|---|
| `instanceType` | `c5.xlarge` → 4 vCPU, 8 GB, $0.170/hr |
| `instanceCount` | 2 |
| `maxInstances` (author cap) | 4 |
| `workloadKind` | `cpu-bound` |
| `workersPerInstance` | **50** (the "just add workers" move) |
| `perRequestMemMb` | 40 |
| authored queue slots (waiting room) | 40 |

**Derivation:**
```
totalVcpu            = 4 × 2            = 8
totalRamMb           = 8 × 1024 × 2    = 16 384
requestedConcurrency = 2 × 50          = 100
cpuCeiling           = totalVcpu       = 8       (cpu-bound)
memCeiling           = 16 384 / 40     = 409
effectiveC           = min(100, 8)     = 8       ← 100 asked, 8 real
effectiveK           = min(8 + 40, 409) = 48
contentionFactor     = 100 / 8         = 12.5    ← informational only (oversubscribed 12.5×)
```

**What the student sees (inline provenance):** *"effective c = 8 (requested 100, CPU-capped at 8 vCPU · oversubscribed 12.5×)."* Cranking workers from 8 → 50 did **nothing** for throughput (c is still 8, capped by vCPU) and *hurt* latency - the 92 excess requested workers can't run in parallel, so they pile into the queue. Provisioned cost held flat at `0.170 × 2 = $0.34/hr` - they paid nothing extra and gained nothing. (The oversubscription is not double-charged as a separate service-time penalty; the cap alone is the physics.)

**The honest fix - buy concurrency:** to actually get ~24 parallel workers they must provision vCPU. Switch to `c5.2xlarge` (8 vCPU, $0.340/hr) × 3 = 24 vCPU → `effectiveC = 24`, cost `0.340 × 3 = $1.02/hr`. But `maxInstances = 4` caps them at 4 instances, and if the environment `resourceBudget.totalVcpu = 16`, three 8-vCPU boxes (24 vCPU) is a **build-time quota failure** - they must either raise the budget (author's call) or accept the ceiling. Concurrency now visibly *costs* money and is *capped* - exactly the intended lesson.

### Example 2 - Provisioned vs consumption (the cost-regime crossover)

Same job, two ways to pay for it. A provisioned fleet vs a per-request serverless node, compared across traffic shapes.

- **Provisioned:** 4 × `m5.large` ($0.096/hr each) = **$0.384/hr, flat**, whatever the traffic.
- **Consumption:** serverless node at `pricePerMillionRequests = $0.20`. Cost = `0.20 × (rps × 3600 / 1e6)`.

| Traffic shape | Provisioned $/hr | Consumption $/hr | Cheaper |
|---|---:|---:|---|
| Spiky, avg **50 rps** | 0.384 | 0.20 × 0.18 = **0.036** | **Consumption** (10× cheaper - you pay ~nothing when idle) |
| Steady **500 rps** | 0.384 | 0.20 × 1.8 = **0.360** | ≈ tie (near the crossover) |
| Steady **2000 rps** | 0.384 | 0.20 × 7.2 = **1.440** | **Provisioned** (flat fleet wins at high steady load) |

**Crossover:** `0.384 = 0.20 × (rps × 3600 / 1e6)` → **rps ≈ 533**. Below it, consumption wins; above it, provisioned wins. Both figures are computed from quantities the sim already produces - `instanceCount` (provisioned) and measured `observedRps` (consumption) - so the comparison is honest, always displayed, and *is* the design lesson: **match the billing regime to the traffic shape.** (Assumes each node can actually serve the load - capacity is Example 1's concern; this example isolates cost.)

---

## Schema changes

Replace the free `{ cpu, memory }` on `ResourceConfig` (`src/engine/core/types.ts:214`) with an instance-type reference + count + per-node cap. Per-instance CPU/RAM are **no longer authorable** - they resolve from the catalog.

```ts
export type InstanceType =
  | 't3.small' | 't3.medium'
  | 'm5.large' | 'm5.xlarge' | 'm5.2xlarge'
  | 'c5.large' | 'c5.xlarge' | 'c5.2xlarge'
  | 'r5.large' | 'r5.xlarge' | 'r5.2xlarge'
  | 'x1e.xlarge'

export interface InstanceSpec { vcpu: number; ramGb: number; family: string; pricePerHour: number }
export const INSTANCE_CATALOG: Record<InstanceType, InstanceSpec>  // frozen reference table

export interface ResourceConfig {
  instanceType: InstanceType   // picks (vcpu, ramGb) from the catalog - NOT free-typed
  instanceCount: number        // horizontal scale (supersedes `replicas`)
  maxInstances: number         // per-node quota (author-set); instanceCount ≤ maxInstances

  // The bindings that turn resources into queue physics:
  workloadKind: 'cpu-bound' | 'io-bound'  // decides whether vCPU caps concurrency
  workersPerInstance: number              // the old queue.workers, now per-instance
  perRequestMemMb: number                 // memory footprint of one in-flight request
}
```

`replicas` / `maxReplicas` are renamed to `instanceCount` / `maxInstances` (keep a back-compat read of the old names in the deserializer). Per-environment budget lives on the environment lens, not the node:

```ts
// on EnvironmentCapabilities (src/engine/analysis/environmentProfile.ts:38)
resourceBudget?: { totalVcpu: number; totalRamGb: number }  // hardware wallet (quota cap)
costBudget?: { maxPerHour: number }                          // money wallet (cost cap) - independent of quota
```

Both are optional. Absent = that cap doesn't gate - but the topology's cost (`Σ pricePerHour × instanceCount`) is **always computed and displayed**, cap or no cap (see [Always show the cost](#always-show-the-cost--even-when-unbounded)).

`queue.workers` / `queue.capacity` are retained on the wire for JSON-authored topologies and back-compat, but the engine prefers the `resources`-derived values when `resources` is present. **Recommended stance:** keep `workersPerInstance` authorable but *constrained* - show a warning + the derived effective value ("c5.xlarge gives 4 vCPU; 1000 workers → effective c ≈ 4") rather than making it disappear. A constrained dial teaches the tradeoff (throughput costs bigger instances × more instances × budget); a fully-derived model removes the teachable moment. This is the biggest design fork - see [Open questions](#open-questions).

`queue.workers` / `queue.capacity` are retained on the wire for JSON-authored topologies and back-compat, but the engine prefers the `resources`-derived values when `resources` is present. **Recommended stance:** keep `workers` authorable but *constrained* - show a warning + the derived effective value ("8 vCPU can't back 1000 workers; effective c ≈ 8") rather than making it disappear. A constrained dial teaches the tradeoff (throughput costs instances × compute × memory); a fully-derived model removes the teachable moment. This is the biggest design fork - see [Open questions](#open-questions).

---

## New failure modes

The closed terminal taxonomy today is `queue_full | node_failed | network_error | timeout | connection_reset | rejected`. Add one terminal:

- **`oom`** - an arrival would exceed `memCeiling`. Distinct from `queue_full`: `queue_full` = "too many waiting"; `oom` = "not enough RAM to hold them." Different lesson, different fix (add RAM/instances vs add workers). It flows through the **same** `recordTerminal` funnel / `WindowedLatencyAggregator` as any other cause; the UI renders it only when it fires.

CPU contention adds **no** terminal and **no** service-time penalty - it is realized purely by capping `effectiveC` (excess workers queue). `contentionFactor` is an informational oversubscription badge only. See the derivation-model note.

---

## What stays untouched

The `Hist` / `WindowedLatencyAggregator` / `recordTerminal` machinery carries forward unchanged. `oom` is just another cause fed into the existing funnel. Utilization stays a time-weighted integral - it just divides by `effectiveC`. No new metrics plumbing: one new upstream derivation, one new terminal cause, three inline provenance readouts.

---

## Phasing: the honest slices

**Scoping principle - the 9 questions drive priority, not the phase label.** "v1 / v2 / deferred / out of scope" in this spec describe a *default sequence*, not a blocklist. Every item here is fair game to build - the actual gate is: **does it benefit one of the 9 questions in the question-bank repo?** If a question needs GPU pricing, storage-at-rest, spot termination, or the async-worker knob, that item is pulled forward regardless of the phase it's tagged with. Conversely, a "v1" slice that no current question exercises can wait. Read the phase tags as "here's the order if all else is equal" - then reorder against what the 9 questions actually require. (Only the genuinely-unsourceable dimensions - per-user, physical hardware - stay out, because no question can honestly exercise a quantity the engine doesn't produce.)

A "first honest slice" = make one dishonest number honest, end to end (derived value shown with provenance + locked by a test), before taking on the rest.

**Slice 0 - the instance catalog + `instanceCount` multiplies concurrency (do this first).**
Add `INSTANCE_CATALOG`; author picks `instanceType` + `instanceCount` (rename of `replicas`) with a per-node `maxInstances` validation. Wire into `GGcKNode` so `effectiveC = instanceCount × workersPerInstance`, resolving per-instance vCPU/RAM from the catalog. Show the derived effective concurrency inline ("effective c = 3 × c5.xlarge = 3 × 8 = 24"). Lock with a test. Converts three ❌ rows (`resources` decoration, `replicas` inconsistency, free-typed dials) toward ✅ without yet touching CPU/RAM *physics*. Highest leverage, testable in isolation, low-risk.

**Slice 1 - Compute (vCPU) caps concurrency & bends service time.**
Add `cpuCeiling = totalVcpu` so `effectiveC = min(requested, cpuCeiling)` for `cpu-bound` nodes; `contentionFactor` surfaced as an informational oversubscription badge (no service-time penalty - cap-only, see derivation note). Requires the `workloadKind` flag so IO-bound designs aren't wrongly punished.

**Slice 2 - RAM as the admission wall.**
Derive `effectiveK` from `memCeiling = totalRamMb / perRequestMemMb`; add the `oom` terminal. Makes `queue.capacity` derived and defensible instead of a vibe. Most pedagogically valuable - it's what makes this a *resource-allocation* exercise rather than a *worker-count* exercise.

**Slice 3 - cost display + the two environment budgets (axis 1, provisioned). DONE.**
Cost is a first-class always-on output (the header CostChip + per-node breakdown, shown cap or not). `resourceBudget` (vCPU/RAM quota) and `costBudget` (money) added on `EnvironmentCapabilities`, both optional (absent = unbounded). `analysis/cost.ts` gained `topologyResources` + `evaluateBudgets` (each dimension present only when its cap is set; quota and cost independent - a design can pass one and fail the other). The CostChip reads the caps from the active environment profile, turns red over budget, shows the cap inline (`$0.09 / $0.05`), and lists per-dimension used/cap in its dropdown. Verified in-app. This turns "size each box" into "spend a fixed hardware *and money* budget across the architecture" - the core requirement.

**Slice 4 - consumption pricing (axis 2), the provisioned-vs-serverless lesson. DONE.**
`costModel: 'consumption'` + `pricePerMillionRequests` on `ResourceTypeDefault`; `serverless-function` priced at $0.20/M req. `cost.ts` bills it from the configured workload (`baseRps × 3600 / 1e6 × rate`) as a pre-run estimate (exact post-run once per-node throughput is wired). Both regimes now compare on one `$/hr` axis. The RESOURCES note + cost breakdown show `$X/M req`. Unit-tested ($0.72/hr @ 1000 rps). *Serverless is not in the curated V1 palette - a product call, not a model gap.*

**Slice 5 - network egress (axis 3). DONE (pre-run estimate).**
Per-edge inter-region/egress transfer cost keyed off `edge.latency.pathType`: `cross-zone` $0.01/GB, `cross-region` $0.02/GB, `internet` $0.09/GB, same-rack/same-dc free (`EDGE_EGRESS_RATE_PER_GB` in `cost.ts`). Egress bytes estimated from configured workload (rough - assumes the edge carries the offered load); exact per-edge egress is the remaining post-run *measurement*. Shows as a `transfer · <pathType>` line in the cost breakdown. Unit-tested + verified in-app (a cross-zone edge priced at `~$0.01/GB · $0.0033/hr` in the breakdown).

Ship Slice 0, verify in-app, then stage 1 → 2 → 3 → 4 → (5 when unblocked). (Cost display in Slice 3 has no engine-physics dependency, so it can be pulled forward to run alongside Slice 0 if cost-awareness is the priority.)

---

## Mapping to the question bank

Priority is set by the repo-local V1 question bank in `examples/question-bank/`. This maps each to the slices it needs.

### The finding that drives everything

**Every reference topology today free-types `workers` and sets a uniform `capacity: 100000` on every node.** The saturation-based questions discriminate *only because the author hand-tuned a low worker count on the bottleneck store* - `url-shortener` starves `nosql-db` at `workers: 50`, `sensor-store` starves `time-series-db` at `60`, while front-tier nodes get `500`. Nothing physical backs those numbers, and `capacity: 100000` means nothing is ever admission-rejected.

This is exactly the dishonesty the spec fixes - and it has two consequences for the bank:

1. **These discriminators are currently gameable.** In any mode where the student can edit the store node, they crank `workers: 50 → 50000` and the "add a cache" lesson evaporates - the store no longer saturates. (Today `canEditScaffoldNodes`/palette limits paper over this by *forbidding* edits; the honest fix is to make cranking *cost* something.)
2. **Migration work per question.** Making concurrency instance-derived means re-expressing each hand-tuned worker count as an `instanceType` × `instanceCount` that reproduces the same saturation point - so the reference still PASSES and the gamed design still FAILS on the intended axis (the Dual-Topology Rule). This is authoring work, tracked below.

**Coupling to watch:** Slice 0 alone just *moves* the free dial from `workers` to `instanceCount`. It only closes the hole when it ships **with a cap** - per-node `maxInstances` (in Slice 0) and/or the always-on cost readout - so scaling concurrency visibly costs money or hits a ceiling.

### Per-question map

| Question | Workload | Intended discriminator | Nature | Slices it needs |
|---|---|---|---|---|
| **url-shortener** | read-heavy | Σ p99 < 100ms - no cache → KV saturates | **saturation** | **0, 1** (+ io-bound) - makes store saturation physical & un-crankable |
| **cache-placement** | read-heavy | placement + Σ p99 < 120ms - no cache → DB saturates | **saturation** | **0, 1** (+ io-bound) |
| **news-feed** | read-heavy | Σ p99 < 200ms - no read cache → timeline store saturates | **saturation** | **0, 1** (+ io-bound) |
| **sensor-store** | write-heavy | storageFit + Σ throughput - relational can't sustain TS writes | **throughput ceiling** | **0, 1**; **2** (write buffering / oom) |
| **async-sla** | write-heavy | structural + guardedPath - synchronous, no queue/workers | **capacity/structural** | **0, 1** - honest worker capacity makes "no workers" actually fail the SLA |
| **ride-hailing** | read-heavy | storageFit + placement - payments on KV, no geo cache | semantic + partial saturation | **0, 1** (geo-cache saturation); storageFit is topology |
| **cargo-cult-cdn** | read-heavy | forbidUnjustified - CDN added, never justified | over-provisioning | **3** - always-on **cost display** gives it teeth ("the CDN costs $/hr for zero benefit"), today only justification-gated |
| **messaging-fanout** | connection-heavy | fanout - work-queue to 3 ≠ pub/sub | structural/semantic | none (topology-shaped, not resource) |
| **web-crawler** | batch-heavy | guardedPath - enqueue without dedup index | structural/semantic | none required; **2** minor (frontier depth) |

### Components used across the bank

The palette the 9 questions actually draw from - every node type the resource/cost model must serve, with the label(s) it appears under and where it's used. (Alternate labels are just templates of the same `componentType`.)

| Palette label(s) | `componentType` | Role & where used |
|---|---|---|
| Client App | `api-endpoint` | The one valid traffic **source**; every question needs exactly one - **all 9** |
| CDN | `cdn` | Edge cache - **cargo-cult-cdn** (the "is this edge cache justified?" trap) |
| Load Balancer | `load-balancer` | Fronts the service - url-shortener, cache-placement, news-feed, ride-hailing |
| API Server / Service / My Service / Input Source | `microservice` | The app tier - **all 9**. The alternates are just other `microservice` templates |
| Job Worker / Cron Job | `batch-worker` | Async workers / fan-out consumers - async-sla, messaging-fanout, news-feed, web-crawler |
| Message Queue | `queue` | Work queue / frontier - async-sla, messaging-fanout, web-crawler |
| Event Broker | `message-broker` | Pub/sub fan-out - messaging-fanout, news-feed |
| Redis Cache | `in-memory-cache` | The read cache (the reinforcing loop) - cache-placement, news-feed, ride-hailing, url-shortener |
| KV Store | `kv-store` | Point-lookup store / dedup index - news-feed, ride-hailing, url-shortener, web-crawler |
| NoSQL DB | `nosql-db` | cargo-cult-cdn's data store |
| Primary DB / Read Replica | `relational-db` | Transactional store - async-sla, cache-placement, ride-hailing, sensor-store |
| Time-series DB | `time-series-db` | sensor-store (time-series ingest) |
| Object Storage | `object-storage` | web-crawler (page storage) |

**What this means for the resource model:** these types split cleanly by how the derivation should treat them, which directly shapes the per-type defaults for `workloadKind` and pricing regime:

- **CPU/compute tier** (`microservice`, `batch-worker`, `api-endpoint`, `load-balancer`) - the nodes where `workersPerInstance` and CPU-contention actually bite; default `cpu-bound` (or io-bound for the app tier when it mostly waits on a store - the async-tuning open question).
- **IO-bound stores** (`kv-store`, `nosql-db`, `relational-db`, `time-series-db`, `in-memory-cache`) - point-lookup/read/write serving; default **`io-bound`** so the vCPU→worker cap doesn't wrongly throttle them. These are exactly the hand-tuned-saturation nodes the migration touches.
- **Fan-out / async** (`queue`, `message-broker`) - capacity/backpressure nodes; `effectiveK`/RAM and the `oom` boundary matter more than CPU concurrency.
- **Edge / storage** (`cdn`, `object-storage`) - `cdn` is the over-provisioning-cost case (Slice 3); `object-storage` is a volume/egress case (Slice 5, gated) - neither is a compute-concurrency node.

Each type will need a sensible catalog default (a starting `instanceType` + `workloadKind`) so authors aren't sizing every node from scratch - a `time-series-db` should default to a bigger/`io-bound` box than a `microservice`. That default-per-type table is a Slice 0 authoring deliverable, drafted next.

### Default instance + workloadKind per type (Slice 0 deliverable)

Starting points, not locks - every field is author-overridable within the caps. The **`workloadKind` column is the load-bearing one**: defaulting the stores to `io-bound` is what keeps Slice 1's vCPU→worker cap from throttling the (correct) reference designs. Sizes are picked so a node comfortably serves the suites' `baseRps` 2-3k without being the accidental bottleneck - the *intended* bottleneck stays the author's to create by under-provisioning a specific node.

| `componentType` | Default `instanceType` | `workloadKind` | Pricing regime | Why |
|---|---|---|---|---|
| `api-endpoint` | `m5.large` | `io-bound` | provisioned | Traffic source / gateway - forwards, doesn't compute; high concurrency, light CPU |
| `load-balancer` | `m5.large` | `io-bound` | provisioned | Fans connections out; concurrency-heavy, negligible per-request CPU |
| `microservice` | `c5.large` | `cpu-bound` | provisioned | App tier runs business logic → CPU is the real limit. **The async-tuning fork:** flip to `io-bound` when it mostly awaits a store (open question #1) |
| `batch-worker` | `c5.large` | `cpu-bound` | provisioned | Async workers do real work per job; CPU-bound and contention-sensitive |
| `queue` | `m5.large` | `io-bound` | provisioned | Backpressure buffer - RAM/`effectiveK` and `oom` matter more than CPU |
| `message-broker` | `r5.large` | `io-bound` | provisioned | Pub/sub fan-out holds messages in memory → memory-optimized for buffering |
| `in-memory-cache` | `r5.large` | `io-bound` | provisioned | Redis - RAM *is* the capacity; memory-optimized is the whole point |
| `kv-store` | `m5.large` | `io-bound` | provisioned | Point-lookup serving; IO-bound. **A hand-tuned-saturation node - migration-critical** |
| `nosql-db` | `m5.xlarge` | `io-bound` | provisioned | Document/point-lookup at higher read volume; IO-bound |
| `relational-db` | `m5.xlarge` | `io-bound` | provisioned | Transactional store; IO-bound with CPU for txn work. **Migration-critical** (cache-placement saturation) |
| `time-series-db` | `r5.xlarge` | `io-bound` | provisioned | High-rate write ingest (sensor-store: 200K writes/s) → bigger, memory-heavy box. **Migration-critical** |
| `cdn` | `m5.large` | `io-bound` | provisioned (v1) | Edge cache - the point is it *costs* $/hr, exposing the cargo-cult trap. Egress/volume pricing is Slice 5, later |
| `object-storage` | `m5.large` | `io-bound` | volume (deferred) | Not a compute-concurrency node; real cost is GB + egress (Slice 5, gated). Placeholder provisioned box until then |

Notes: (1) no current node type defaults to the **consumption** regime - there's no serverless node in the V1 palette, so Slice 4 stays dormant until one is authored. (2) The three **migration-critical** rows (`kv-store`, `relational-db`, `time-series-db`) are the nodes whose hand-tuned low worker counts *create* the saturation discriminators - their default must be sized *above* the suite load, so the author still produces the bottleneck by explicitly under-provisioning, not by accident. (3) `object-storage` and `cdn` carry a real box only so they don't break the derivation; their honest cost model (volume/egress) arrives with Slice 5.

### What this says about slice priority

- **Slices 0 + 1 are the payload for the bank** - they protect **6 of 9** questions (all the saturation/throughput/capacity discriminators) from the "just crank workers" dodge and make the hand-tuned bottlenecks physical. Highest priority, and they must land together with the per-node `maxInstances` cap or the dodge just relocates to `instanceCount`.
- **`workloadKind` is not optional for the bank** - the saturating stores are point-lookup/read (`io-bound`); a vCPU→worker cap without the flag would wrongly throttle *correct* IO-bound designs and could break the reference topologies. It must ship with Slice 1.
- **Slice 3 (cost) benefits exactly one current question** (`cargo-cult-cdn`) plus the general anti-kitchen-sink intent - no question sets a `budget` today, so cost *discrimination* requires either adding budgets to questions or authoring new cost-focused ones. The always-on cost *display* is still worth pulling forward (cheap, no physics dep) to give over-provisioning a visible price.
- **Slices 4 & 5 benefit zero current questions** - no question compares provisioned-vs-consumption or turns on egress/inter-region cost. Per the scoping principle, they wait until a question is authored that needs them. (Requests already carry `sizeBytes` in the workload cases, so the request-size dependency for 5 is partially de-risked when that time comes.)
- **fanout & crawler** are topology-shaped; the resource model doesn't move their needle. Don't hold them up for it.

**Net build order for the bank:** Slice 0 + `maxInstances` + always-on cost display → Slice 1 (with `workloadKind`) → migrate the 6 saturation/throughput references to instance types (preserving each discrimination point) → Slice 2 for the write-heavy trio → Slice 3 budgets + a cost-discriminating question → 4/5 only when a question demands them.

---

## Pricing model & compute-performance (Vantage-inspired)

Two enrichments drawn from professional instance-comparison tools (e.g. Vantage), keeping our catalog a short legible menu - *not* a searchable database (we deliberately skip filter-expression languages, compare/export, region/currency selectors).

### Pricing model - DONE

`ResourceConfig.pricingModel: 'on-demand' | 'reserved' | 'spot'` (default on-demand). Cost = `pricePerHour × PRICING_MULTIPLIER[model] × instanceCount` (`instanceCatalog.ts`): on-demand 1.0, **reserved 0.6** (~40% off, committed), **spot 0.3** (~70% off). Surfaced as a `Pricing` select in the RESOURCES section; the node note + cost breakdown show the model (e.g. `$0.026/hr (spot)`). This completes the cost story with the flexibility ↔ commitment ↔ risk tradeoff.

**The spot hook (future):** spot's discount comes with *reclaim risk* - the provider can terminate the instance. That maps cleanly onto the fault-injection suite: a spot node is a candidate for a random `node_failed`/`connection_reset` during a run. So `spot` is not just a cheaper price - it's a reliability-vs-cost lesson, wired in once fault injection is reachable in-app (the same blocker that keeps the status-timeline strip empty today).

### Compute-performance factor - DONE

Vantage shows a CoreMark/benchmark score per instance - a *speed* dimension the model previously lacked (every vCPU was equal; the instance set concurrency and cost, but not how fast a single request served). Now each catalog entry carries a **`perfFactor`** (relative single-thread speed, per family: `m5`/`r5`/`x1e` = 1.0 baseline, `c5` compute-optimized = 1.3, `t3` burstable = 0.8). A node's service time is multiplied by `serviceTimeMultiplier = 1 / effectivePerf`, so a faster instance serves each request quicker - "buy better hardware → lower latency" is now a real, visible lever.

- **`workloadKind` interaction:** cpu-bound work spends all its time on the core, so it gets the full `perfFactor`; io-bound work mostly *waits*, so it's damped: `effectivePerf = cpu-bound ? perfFactor : 1 + (perfFactor − 1) × IO_PERF_SENSITIVITY` (0.25). A faster core barely helps a request blocked on a store.
- **Surfaced** in the RESOURCES note as `service ×N.NN` (e.g. a cpu-bound `c5.large` shows `service ×0.77` - 23% faster).
- **v1 keeps it a flat multiplier** - the real burstable-credit *exhaustion* of `t3` (fast until credits run out, then throttled) is deliberately deferred.
- **Burstable-credit exhaustion - assessed, staying deferred (not a v-gate, a modelling call).** A faithful credit machine is *non-stationary*: the node serves at burst speed while a credit balance lasts, then drops to a baseline rate once it's spent. That collides with two load-bearing invariants of this engine: (a) the G/G/c/K node has a single stationary service-time distribution, and (b) every reported scalar is a **time-weighted integral over the whole run** ([[no-point-sampled-scalars]]) - a mid-run regime switch would blend two speeds into one utilization/latency number that describes neither. Under *sustained* above-baseline load (the regime these sims target), a burstable instance depletes its credits early and spends almost the entire run at baseline anyway - so the honest steady-state representation of a `t3` **is** a flat derate at its post-credit speed, which is exactly what `perfFactor` already encodes. Building the transient would add engine state and *reduce* metric honesty while modelling a window (the first few seconds) that no bank question exercises (per the "9 questions drive priority" gate). Revisit only if a question is authored specifically around burst-then-throttle behaviour; the correct implementation then is a two-phase timeline, not a knob on the node.
- **Bank impact (as predicted):** shifting service time re-tunes throughput. Re-validated after regeneration - the bottleneck `t3.small` cpu-bound stores got ~25% slower (`×1.25`), which only strengthens their saturation; cache-fronted references are unaffected. **All 9 still discriminate** (9/9 refs PASS, 9/9 gamed FAIL as intended, 0 under-constrained).

---

## Source-to-feature map

| Source | Role in this spec |
|---|---|
| `src/engine/catalog/instanceCatalog.ts` (new) | Frozen `INSTANCE_CATALOG` reference table; the menu authors pick from. |
| `src/engine/core/types.ts:214` (`ResourceConfig`) | Replace free `{cpu,memory}` with `instanceType`/`instanceCount`/`maxInstances`; currently unread by the engine. |
| `src/engine/core/types.ts:221` (`QueueConfig`) | `workers`/`capacity` become derived outputs. |
| `src/engine/nodes/GGcKNode.ts` | The consumer - resolves the catalog, builds `effectiveC`/`effectiveK`; utilization divides by `effectiveC`. |
| `src/engine/analysis/environmentProfile.ts:38` (`EnvironmentCapabilities`) | Home for `resourceBudget` (vCPU/RAM quota) + `costBudget` (money cap), beside `maxTestRuns`. |
| `src/engine/analysis/budget.ts:37` (`estimateNodeCost`) + `budgetBreakdown` | Replace the soft heuristic with the instance-price sum; `budgetBreakdown` already returns per-node line items → drives the always-on cost display. |
| `src/engine/analysis/structural.ts:247`, `rubric.ts:192` | Already sum `replicas` for scoring - retarget to `instanceCount`; become consistent with physics once Slice 0 lands. |
| `src/engine/metrics/windowedLatencyAggregator.ts` (`classifyRejectionCause`) | Add `oom` to the closed taxonomy. |
| `src/engine/validation/validator.ts:346` | `resources` zod schema - enforce `instanceType` enum + `instanceCount ≤ maxInstances`. |
| `src/engine/__mocks__/orderProcessingTopology.ts` | Carries legacy `resources: { cpu, memory, replicas }` - migrate to instance types as fixtures. |

---

## Open questions

1. **Worker/queue knobs - RESOLVED (2026-08-13).** The instance type sets the *ceiling* for both concurrency and queue depth (`cpuCeiling` from vCPU, `memCeiling` from RAM), but doesn't fully *decide* them. **Decision: derive sensible defaults for *both* `workersPerInstance` and queue-slots from `instanceType` + `workloadKind` (so a topology works out-of-the-box), but keep both as visible, editable fields** - the author can tune them or *intentionally misconfigure* (e.g. too few workers, or a fail-fast tiny queue) to author a teaching bug. `effective = min(configured, ceiling)` still applies, so an override is always capped by the hardware. Defaults: `workersPerInstance` = vCPU (cpu-bound) or vCPU × ioMultiplier (io-bound); queue-slots default = a backlog multiple of the default workers, capped by `memCeiling`. Both fields stay in the schema and examples (not dropped) - the earlier "drop queue-slots / K = memCeiling" simplification was **rejected** in favor of keeping the editable knob for the misconfiguration lesson.
2. **CPU-bound vs IO-bound signal.** The vCPU→concurrency cap only holds for CPU-bound work; IO-bound legitimately runs workers ≫ vCPU. `workloadKind` is proposed as new on `ResourceConfig` - confirm no existing node property already carries this, else the model punishes correct IO-bound designs.
3. **`perRequestMemMb` provenance.** Per-node authored constant, or derived from request/workload size (`request-type-model.md`)? A workload-derived footprint is more honest but couples this spec to the request model.
4. **Pricing & cost cap - RESOLVED.** Each instance type carries a `pricePerHour`, and **cost is a separate cap from quota - both apply** (a design can be within vCPU/RAM quota yet over the money budget, and vice versa). Cost is also an **always-on display**, shown on every topology regardless of whether a `costBudget` is set. Remaining sub-question: does the catalog need more families later (GPU/accelerated, storage-optimized `i3`)? Deferred - the 12-type set is v1.
5. **Environment budget default - RESOLVED.** No cap by default: **AUTHOR** and **open builds** are unbounded (no `resourceBudget`, no `costBudget`); **ASSIGNMENT/PRACTICE** may set either or both. But **cost is always displayed** in every mode - "unbounded" means no *gate*, never no *number*. See the defaults table in [The caps](#the-caps-quota-cost-and-per-node).
6. **`perRequestMemMb` provenance** (was #3, still open - see above).
7. **Autoscaling (`maxInstances` as a live ceiling).** Out of scope for v1 (static allocation). Reserved for a later slice where offered load drives `instanceCount` between a floor and `maxInstances` at runtime.

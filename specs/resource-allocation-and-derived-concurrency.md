# Resource Allocation & Derived Concurrency

Technical feature specification defining how physical resource allocation (Compute / RAM / instances) should *derive* a node's queueing capacity, so that concurrency stops being a free-floating dial and becomes a constrained consequence of provisioned hardware. This closes the "anyone can crank `workers` to 1000 and every bottleneck vanishes for free" hole.

This spec exists because the simulator today runs on `queue.workers` (the `c` in G/G/c/K) and `queue.capacity` (the `K`) as **authored magic numbers**, while `ResourceConfig` (cpu, memory, replicas) is defined in the type system, validated, scored by budget/rubric/structural analysis — and **never read by the engine**. This document specifies the derivation that makes `resources` physical.

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
8. [The derivation model](#the-derivation-model)
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
| Buffer (`K`) | `queue.capacity` | **Drives the sim** — the drop/reject boundary. Arbitrary authored constant. |
| Physical resources | `resources: { cpu, memory, replicas, maxReplicas }` | **Decorative.** Defined in `src/engine/core/types.ts:214`. The engine (`GGcKNode`) never reads it. Only `budget.ts`, `structural.ts`, `rubric.ts` touch it — for *scoring*, not physics. |

The consequence: a student types `workers: 1000` and every bottleneck disappears, backed by nothing physical. The only pushback is `estimateNodeCost` in `src/engine/analysis/budget.ts:37` — a soft heuristic (`1 + replicas + ⌈workers/50⌉`) that dings the *budget score* but does not change the *simulation*. And `replicas` is *counted* by rubric/structural scoring while being *ignored* by the engine, so the score rewards something the physics doesn't model — internally inconsistent.

The originating feedback: **"Resource allocation — Compute, RAM, instances — reasoning being anyone can increase the number of workers & queues and more."** Reframed precisely: *concurrency should be a derived consequence of provisioned resources, not a free-floating dial.* `workers` should be demoted from a pure input to a **request that resources cap**.

---

## Mental model: workers, queues, and hardware

The engine models each node as a **G/G/c/K queue**. Two of those letters are the knobs this spec is about:

- **`c` = workers = parallel servers.** A "worker" processes **one request at a time**. `c` workers means `c` requests are actively being served *simultaneously*. Think cooks in a kitchen: 8 cooks → 8 orders in progress at once. This is `queue.workers`.
- **`K` = system capacity = in-service + waiting.** Requests that arrive while all `c` workers are busy **wait in the queue**. `K` is the total the node can hold — the `c` being served **plus** the ones waiting. When the system is at `K` and another arrives, it's **rejected** (`queue_full`). This is `queue.capacity`. (The `G/G` prefix just means arrivals and service times can follow general distributions — not relevant to this spec.)

A request's life: free worker? → **served now.** All busy? → **wait in queue.** Queue full (at `K`)? → **rejected.**

**Today `c` and `K` are free-typed numbers** backed by nothing physical — you can declare 1000 workers on a machine the size of a closet. CPU and RAM are what make them physical:

- **CPU ↔ `c` (workers).** A worker doing real CPU work needs a core to run on. ~1 truly-parallel worker per vCPU. Claim 1000 workers on 4 vCPU and you don't get 1000× throughput — you get 4 cores frantically time-slicing 1000 half-done requests, so everything just slows down (**contention** → service time inflates). *Caveat:* this only bites **CPU-bound** work. An **IO-bound** worker mostly *waits* on a DB/network (not using the CPU), so workers ≫ vCPU is legitimate there — which is why the vCPU cap is gated on `workloadKind`.
- **RAM ↔ `K` (queue depth).** Every request in the node — being served *or* waiting — occupies memory (its data, buffers, connection). So `K ≤ totalRAM ÷ memory-per-request`. 8 GB at 40 MB/request → you physically cannot hold more than ~200, whatever you typed. The 201st doesn't queue — it **`oom`**s (a distinct failure with a distinct fix: add RAM/instances, not workers).

So the two things authors used to type freely become the **ceiling they're *requesting***, while CPU/RAM (from the instance type × count) are the **ceiling reality *allows***. **The node gets the smaller of the two** — that is the entire derivation:

| Authored (a request) | Physically capped by | Consequence when exceeded |
|---|---|---|
| **workers** (`c`, parallel service) | **vCPU** (CPU-bound only) | not a terminal — slows down (contention) |
| **queue capacity** (`K`, waiting room) | **RAM** (bytes per request) | `oom` terminal |
| **instance count** | **maxInstances** + env vCPU/RAM budget | build-time validation / budget error |

To go faster you don't type a bigger number — you **provision more hardware** (bigger instance type, or more instances), which spends from a capped budget. Exactly like AWS.

---

## Design Principle: the honesty ledger

The governing principle (from the honesty-redesign roadmap): **every number the UI shows is a mechanical projection of one real per-request truth — never a magic constant, a survivor-biased average, or a snapshot artifact.** A "slice" = one node property made to obey that.

Where resource allocation sits on that ledger today:

**Already honest (done & verified elsewhere):** time-weighted utilization integral (not snapshot average); success latency labeled "successful only"; closed terminal taxonomy (`queue_full/node_failed/network_error/timeout/connection_reset/rejected`); latency decomposition that sums exactly; failure-by-locus Pareto that reconciles; per-node aggregators; arrival-CV.

**Not yet honest (this spec's targets):**

| Surface | Why it's dishonest today |
|---|---|
| `queue.workers` / concurrency | Free-floating magic number; typing 1000 dissolves any bottleneck, backed by nothing. |
| `resources` (cpu/memory/replicas) | Pure decoration — on screen, changes nothing in the sim. A number that changes nothing is the definition of dishonest here. |
| `queue.capacity` (K) | Arbitrary authored constant; should be RAM-derived and defensible. |
| `replicas` | Scored by rubric/structural but doesn't multiply concurrency in the sim — score rewards what physics ignores. |
| Budget `estimateNodeCost` | Self-admittedly "without a real price sheet"; dings score not physics, so it's bypassable. |

The design converts these ❌ rows toward ✅ by making `resources` the thing that *derives* `c` and `K`, with the derived values surfaced inline with their provenance.

---

## No infinite dials: the AWS instance model

The free `{ cpu, memory }` pair in the first draft of this spec still lets a student type "6.5 vCPU, 12 GB" and, worse, ask for infinite RAM with tiny CPU. That's not how real infrastructure works, and it doesn't close the gaming hole. The corrected model mirrors AWS: **you don't free-type resources — you pick a discrete instance *type* off a menu, and you scale by instance *count*, which is quota-capped.**

Two properties fall out of this, both serving the anti-gaming goal:

1. **CPU and RAM are coupled, not independent dials.** To get more RAM you take a bigger instance, which also costs more vCPU and more money. Every axis moves together, the way real hardware does — killing the "crank the one number that unblocks me" move.
2. **Fixed CPU:RAM ratios teach a real decision.** Choosing compute-optimized (`c5`, ~2 GB/vCPU) vs memory-optimized (`r5`, ~8 GB/vCPU) is an actual system-design choice. A free `{cpu, memory}` pair lets a student sidestep it.

Scaling is then **count × capped**: you scale horizontally by instance count (`instanceCount`, the old `replicas`), never by inflating one box infinitely, and the count is bounded by a quota (see [The two-level quota](#the-two-level-quota)).

Three caps together stop infinite scaling:

- **Per-instance CPU/RAM** — fixed by the instance type picked (can't exceed the SKU).
- **Instance count** — bounded by `maxInstances` (per-node) and by the environment vCPU/RAM budget.
- **Workers / queue** — no longer free; capped by the CPU/RAM the instances actually provide (the derivation below).

---

## The instance catalog

A fixed reference table the author picks from — **not free-typed**. Curated to mirror the AWS families (general-purpose / compute-optimized / memory-optimized / burstable) with faithful CPU:RAM ratios, kept small enough to be a legible menu. `ramGbPerVcpu` is shown to make the family's character obvious.

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

The catalog is a curated pedagogical set, not the full AWS SKU list — three ratio tiers (2 / 4 / 8 GB-per-vCPU) plus a burstable floor and a memory-extreme ceiling, at 2/4/8-vCPU sizes so scaling *up* (bigger type) and scaling *out* (more instances) are both expressible. Prices are AWS-proportional on-demand `$/hr` (us-east-1 order of magnitude) so the *relative* tradeoffs are faithful — compute-optimized is cheaper per vCPU, memory-optimized costs a premium per GB, `x1e` is deliberately expensive. Lives as a frozen reference table (proposed `src/engine/catalog/instanceCatalog.ts`); authoring picks an `instanceType` key, and the engine resolves `{ vcpu, ramGb, pricePerHour }` from it.

---

## The caps: quota, cost, and per-node

**Cost and quota are two *different* caps, and both apply.** They constrain different things and a design can pass one while failing the other, which is exactly the point — real infrastructure is bounded by *both* "is the hardware available?" (quota) and "can we afford it?" (cost):

- **Quota** = physical availability. You can't provision vCPU/RAM that doesn't exist in your allocation. A hard wall.
- **Cost** = money. The hardware may be available, but the monthly bill is capped. A different wall — and often the binding one, since money runs out before a region's capacity does.

Three caps in total, composing — a node/topology must satisfy **all** of them:

**1. Per-node cap (`maxInstances`)** — author-set on a node. "This service may scale to at most N instances." Bounds horizontal scaling of one component; the author's lever for shaping a specific bottleneck ("the DB can't scale past 3"). Exceeding it is a **build-time validation error**.

**2. Per-environment resource quota (`resourceBudget`)** — a hardware wallet: total vCPU and total RAM available across the whole topology. Forces allocation tradeoffs ("you have 40 vCPU and 160 GB — spend them"). Exceeding it is a **build-time budget failure**, surfaced live.

**3. Per-environment cost budget (`costBudget`)** — a money wallet: max spend for the whole topology, in `$/hr` (derived from the instance prices). Exceeding it is a **build-time budget failure**, surfaced live, on the same channel as the resource quota.

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

Budget violations (2, 3) are **build-time** failures, not runtime terminals — you can't provision hardware you can't afford or that doesn't exist. They gate authoring/submission the same way the existing budget breakdown does.

### Always show the cost — even when unbounded

**The architecture's cost is displayed at all times, regardless of whether a cap is set.** Cost is a first-class output of every topology, not just a gate that appears when a budget exists. Even in AUTHOR mode or an open build with no `costBudget`, the simulator shows `totalCostPerHour` (and the per-node breakdown — which component drives the bill). Rationale: cost-awareness is the requirement, and a number that only appears when you're failing teaches nothing; a number that's *always visible* teaches the tradeoff on every edit. When a `costBudget` *is* set, the same display gains a "X / Y ($/hr) — within/over budget" framing. This reuses `budgetBreakdown` in `src/engine/analysis/budget.ts` (already returns per-node line items) — the cost model just becomes the instance-price sum instead of the `estimateNodeCost` heuristic.

### Defaults when a question sets no budget

| Mode | Resource quota | Cost budget | Cost display |
|---|---|---|---|
| **AUTHOR** | unbounded | unbounded | **always shown** (per-node + total) |
| **Open build** (no budget set) | unbounded | unbounded | **always shown** |
| **ASSIGNMENT / PRACTICE** | author may set | author may set | **always shown**; when a cap is set, framed as used / cap |

Unbounded means "no cap," **not** "no cost" — the bill is still computed and displayed everywhere. Both `resourceBudget` and `costBudget` are optional on the environment lens; absent = that particular cap doesn't gate, but the cost readout never disappears.

---

## Cost model: where cost comes from

Cloud pricing has ~9 dimensions (compute-time, request/invocation, data volume, per-user, subscription, percentage-of-spend, feature/licensing, market/spot, physical hardware). **The simulator deliberately models only a subset**, chosen by one filter.

### The filter: only bill what the engine measures

A cost is dishonest the moment it's backed by a quantity the simulator doesn't actually produce — that's the same magic-number problem this whole spec fights, wearing a dollar sign. So the test for every pricing dimension is: **does the engine already emit the quantity it bills?** If we'd have to invent the quantity, we don't bill it.

| Pricing dimension | Quantity needed | Sim produces it? | Verdict |
|---|---|---|---|
| **Compute (time & capacity)** | instance type × count × runtime | **Yes** — `INSTANCE_CATALOG`, `instanceCount`, run horizon | **IN — axis 1 (provisioned)** |
| **Request (invocation)** | per-node request counts, read/write split | **Yes** — `MetricsCollector` counts terminals per node | **IN — axis 2 (consumption)** |
| **Volume — network transfer** | bytes/request, cross-region edges | **Partly** — edges + region/AZ composites exist; requests carry no reliable byte size yet | **IN — axis 3, GATED** |
| Volume — storage-at-rest (GB-month) | stored data footprint | No — sim models flow, not data at rest | Deferred |
| User (MAU / seats) | human identities | No — sim models requests, not users | Out |
| Subscription / flat-fee | a constant | trivial, no lesson | Out (v1) |
| Percentage (support) | % of total spend | trivial multiplier on total | Out (v1) |
| Feature / licensing / OS | price modifier on instance | possible later as a catalog flag | Deferred |
| Market (spot) | price × termination risk | ties to fault-injection (not yet wired) | Deferred (v2) |
| Physical hardware / appliances | shipped devices | No — irrelevant to a topology sim | Out |

Of nine dimensions, three are sourceable; only the first two are solid today (axis 3 waits on the request-size model — the same open dependency as `perRequestMemMb`).

### The core lesson: provisioned vs consumption

Axes 1 and 2 are not just two line items — they are the two cost **regimes**, and choosing between them is a real system-design decision the simulator should force:

- **Axis 1 — provisioned** (compute-time). You pay for the box whether or not traffic comes. An always-on fleet. `cost = pricePerHour × instanceCount`. Flat; idle capacity is wasted money. Maps to `compute-service` / `worker` / `datastore` nodes.
- **Axis 2 — consumption** (per-request). You pay per request, nothing when idle. Serverless / Lambda / on-demand DB. `cost = pricePerMillionRequests × observedThroughput`. Tracks load; a spike costs linearly. Maps to a serverless-flagged node.

Both normalize to `$/hr` given the arrival rate, so they sit on **one comparable axis**. The exam question — *"at this traffic shape, is a provisioned fleet or a per-request service cheaper?"* — only exists because both regimes are modeled. **This comparison is what makes cost worth teaching** rather than a decorative total: it turns cost from a number you avoid exceeding into a design tradeoff you reason about on every edit.

```
// axis 1 — provisioned node
nodeCostPerHour = instanceType.pricePerHour × instanceCount

// axis 2 — consumption node (billed on measured throughput, not provisioned capacity)
nodeCostPerHour = pricePerMillionRequests × (observedRps × 3600 / 1_000_000)

// axis 3 — network egress (GATED on per-request byte size)
edgeCostPerHour = pricePerGb × (observedRps × bytesPerRequest × 3600 / 1e9)
//   inter-region edges (region-crossing, from composite membership) priced higher than intra-zone

topologyCostPerHour = Σ nodeCostPerHour + Σ edgeCostPerHour
```

### Explicitly out of scope (with reasons, so nobody re-adds them blindly)

- **Storage-at-rest (GB-month)** — the sim has no concept of stored data volume; it models request flow, not a data footprint. Would be an invented number.
- **Per-user / seats** — the sim models requests, not human identities.
- **Subscription, percentage-of-spend, licensing/OS** — trivial constants or multipliers with no design tradeoff to teach at this stage.
- **Spot / market pricing** — genuinely interesting (spot *termination* ties to the fault-injection suite), but blocked until fault injection is wired; revisit in v2.
- **Physical hardware / appliances** — not part of a topology simulator.

Nobody should later bolt "S3 storage pricing" onto a simulator with no stored-bytes quantity — that reintroduces exactly the dishonesty this section exists to prevent.

---

## The derivation model

`queue.workers` and `queue.capacity` become **derived outputs**, not authored inputs. The engine resolves the instance type to `{ vcpu, ramGb }`, multiplies by count, then builds its G/G/c/K.

```
{ vcpu, ramGb } = instanceCatalog[instanceType]      // fixed per-instance, from the menu

totalVcpu  = vcpu  × instanceCount
totalRamMb = ramGb × 1024 × instanceCount

requestedConcurrency = instanceCount × workersPerInstance

// vCPU only caps CPU-bound work; IO-bound legitimately runs workers ≫ vCPU
cpuCeiling = workloadKind === 'cpu-bound' ? totalVcpu : Infinity   // ~1 parallel worker / vCPU

// RAM is a hard admission wall
memCeiling = floor( totalRamMb / perRequestMemMb )

effectiveC = min(requestedConcurrency, cpuCeiling)     // servers actually serving
effectiveK = min(effectiveC + queueSlots, memCeiling)  // system limit (in-service + waiting)
```

Three derived signals the UI must surface **inline** (per the honesty principle — every number shows its provenance, not in a tooltip):

| Derived value | Meaning | Surfaced as |
|---|---|---|
| `effectiveC` | actual `c` in the sim | "effective concurrency ≈ 24 (requested 24, CPU-capped)" |
| `effectiveK` | actual `K` | "admission limit 200 (RAM-bound: 8 GB ÷ 40 MB)" |
| `contentionFactor` = `requestedConcurrency / cpuCeiling` when > 1 | CPU oversubscription | service-time inflation multiplier |

**CPU contention is not a terminal — it's service-time inflation.** When `requestedConcurrency > cpuCeiling`, multiply the service-time distribution mean by `contentionFactor`: workers past the vCPU count time-slice instead of running in parallel. This is the "you can't fake compute" physics. Utilization's time-weighted `busyAreaUs` integral then divides by `effectiveC` instead of raw `workers`.

---

## Worked examples

Two end-to-end examples, using the catalog numbers, to sanity-check the model before implementation.

### Example 1 — "You can't fake workers" (derivation + caps + provisioned cost)

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
contentionFactor     = 100 / 8         = 12.5    ← service time ×12.5
```

**What the student sees (inline provenance):** *"effective concurrency = 8 (requested 100, CPU-capped at 8 vCPU) · service time ×12.5 from oversubscription."* Cranking workers from 8 → 50 did **nothing** for throughput and *hurt* latency (12.5× contention). Provisioned cost held flat at `0.170 × 2 = $0.34/hr` — they paid nothing extra and gained nothing.

**The honest fix — buy concurrency:** to actually get ~24 parallel workers they must provision vCPU. Switch to `c5.2xlarge` (8 vCPU, $0.340/hr) × 3 = 24 vCPU → `effectiveC = 24`, cost `0.340 × 3 = $1.02/hr`. But `maxInstances = 4` caps them at 4 instances, and if the environment `resourceBudget.totalVcpu = 16`, three 8-vCPU boxes (24 vCPU) is a **build-time quota failure** — they must either raise the budget (author's call) or accept the ceiling. Concurrency now visibly *costs* money and is *capped* — exactly the intended lesson.

### Example 2 — Provisioned vs consumption (the cost-regime crossover)

Same job, two ways to pay for it. A provisioned fleet vs a per-request serverless node, compared across traffic shapes.

- **Provisioned:** 4 × `m5.large` ($0.096/hr each) = **$0.384/hr, flat**, whatever the traffic.
- **Consumption:** serverless node at `pricePerMillionRequests = $0.20`. Cost = `0.20 × (rps × 3600 / 1e6)`.

| Traffic shape | Provisioned $/hr | Consumption $/hr | Cheaper |
|---|---:|---:|---|
| Spiky, avg **50 rps** | 0.384 | 0.20 × 0.18 = **0.036** | **Consumption** (10× cheaper — you pay ~nothing when idle) |
| Steady **500 rps** | 0.384 | 0.20 × 1.8 = **0.360** | ≈ tie (near the crossover) |
| Steady **2000 rps** | 0.384 | 0.20 × 7.2 = **1.440** | **Provisioned** (flat fleet wins at high steady load) |

**Crossover:** `0.384 = 0.20 × (rps × 3600 / 1e6)` → **rps ≈ 533**. Below it, consumption wins; above it, provisioned wins. Both figures are computed from quantities the sim already produces — `instanceCount` (provisioned) and measured `observedRps` (consumption) — so the comparison is honest, always displayed, and *is* the design lesson: **match the billing regime to the traffic shape.** (Assumes each node can actually serve the load — capacity is Example 1's concern; this example isolates cost.)

---

## Schema changes

Replace the free `{ cpu, memory }` on `ResourceConfig` (`src/engine/core/types.ts:214`) with an instance-type reference + count + per-node cap. Per-instance CPU/RAM are **no longer authorable** — they resolve from the catalog.

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
  instanceType: InstanceType   // picks (vcpu, ramGb) from the catalog — NOT free-typed
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
costBudget?: { maxPerHour: number }                          // money wallet (cost cap) — independent of quota
```

Both are optional. Absent = that cap doesn't gate — but the topology's cost (`Σ pricePerHour × instanceCount`) is **always computed and displayed**, cap or no cap (see [Always show the cost](#always-show-the-cost--even-when-unbounded)).

`queue.workers` / `queue.capacity` are retained on the wire for JSON-authored topologies and back-compat, but the engine prefers the `resources`-derived values when `resources` is present. **Recommended stance:** keep `workersPerInstance` authorable but *constrained* — show a warning + the derived effective value ("c5.xlarge gives 4 vCPU; 1000 workers → effective c ≈ 4") rather than making it disappear. A constrained dial teaches the tradeoff (throughput costs bigger instances × more instances × budget); a fully-derived model removes the teachable moment. This is the biggest design fork — see [Open questions](#open-questions).

`queue.workers` / `queue.capacity` are retained on the wire for JSON-authored topologies and back-compat, but the engine prefers the `resources`-derived values when `resources` is present. **Recommended stance:** keep `workers` authorable but *constrained* — show a warning + the derived effective value ("8 vCPU can't back 1000 workers; effective c ≈ 8") rather than making it disappear. A constrained dial teaches the tradeoff (throughput costs instances × compute × memory); a fully-derived model removes the teachable moment. This is the biggest design fork — see [Open questions](#open-questions).

---

## New failure modes

The closed terminal taxonomy today is `queue_full | node_failed | network_error | timeout | connection_reset | rejected`. Add one terminal:

- **`oom`** — an arrival would exceed `memCeiling`. Distinct from `queue_full`: `queue_full` = "too many waiting"; `oom` = "not enough RAM to hold them." Different lesson, different fix (add RAM/instances vs add workers). It flows through the **same** `recordTerminal` funnel / `WindowedLatencyAggregator` as any other cause; the UI renders it only when it fires.

CPU contention adds **no** terminal — it is the service-time multiplier described above.

---

## What stays untouched

The `Hist` / `WindowedLatencyAggregator` / `recordTerminal` machinery carries forward unchanged. `oom` is just another cause fed into the existing funnel. Utilization stays a time-weighted integral — it just divides by `effectiveC`. No new metrics plumbing: one new upstream derivation, one new terminal cause, three inline provenance readouts.

---

## Phasing: the honest slices

**Scoping principle — the 9 questions drive priority, not the phase label.** "v1 / v2 / deferred / out of scope" in this spec describe a *default sequence*, not a blocklist. Every item here is fair game to build — the actual gate is: **does it benefit one of the 9 questions in the question-bank repo?** If a question needs GPU pricing, storage-at-rest, spot termination, or the async-worker knob, that item is pulled forward regardless of the phase it's tagged with. Conversely, a "v1" slice that no current question exercises can wait. Read the phase tags as "here's the order if all else is equal" — then reorder against what the 9 questions actually require. (Only the genuinely-unsourceable dimensions — per-user, physical hardware — stay out, because no question can honestly exercise a quantity the engine doesn't produce.)

A "first honest slice" = make one dishonest number honest, end to end (derived value shown with provenance + locked by a test), before taking on the rest.

**Slice 0 — the instance catalog + `instanceCount` multiplies concurrency (do this first).**
Add `INSTANCE_CATALOG`; author picks `instanceType` + `instanceCount` (rename of `replicas`) with a per-node `maxInstances` validation. Wire into `GGcKNode` so `effectiveC = instanceCount × workersPerInstance`, resolving per-instance vCPU/RAM from the catalog. Show the derived effective concurrency inline ("effective c = 3 × c5.xlarge = 3 × 8 = 24"). Lock with a test. Converts three ❌ rows (`resources` decoration, `replicas` inconsistency, free-typed dials) toward ✅ without yet touching CPU/RAM *physics*. Highest leverage, testable in isolation, low-risk.

**Slice 1 — Compute (vCPU) caps concurrency & bends service time.**
Add `cpuCeiling = totalVcpu` + `contentionFactor` for `cpu-bound` nodes. Couples `resources` to `processing.distribution` (currently unrelated). Requires the `workloadKind` flag so IO-bound designs aren't wrongly punished.

**Slice 2 — RAM as the admission wall.**
Derive `effectiveK` from `memCeiling = totalRamMb / perRequestMemMb`; add the `oom` terminal. Makes `queue.capacity` derived and defensible instead of a vibe. Most pedagogically valuable — it's what makes this a *resource-allocation* exercise rather than a *worker-count* exercise.

**Slice 3 — cost display + the two environment budgets (axis 1, provisioned).**
Make cost a first-class always-on output: replace `estimateNodeCost` with the provisioned instance-price sum (`pricePerHour × instanceCount`) in `budgetBreakdown`, and show `totalCostPerHour` + per-node breakdown on every topology (cap or not). Then add `resourceBudget` (quota) and `costBudget` (cost) on `EnvironmentCapabilities`; sum vCPU/RAM/$ across nodes and surface over/under each cap live. This is what turns "size each box" into "spend a fixed hardware *and money* budget across the architecture" — the core requirement.

**Slice 4 — consumption pricing (axis 2), the provisioned-vs-serverless lesson.**
Add a consumption-priced node flag + `pricePerMillionRequests`, billed on the throughput `MetricsCollector` already measures. Both regimes now compare on one `$/hr` axis — the exam question "provisioned fleet vs per-request service at this traffic shape."

**Slice 5 — network egress (axis 3), GATED.**
Edge/inter-region transfer cost from per-request byte size. Do **not** start until the request-size model lands (shared dependency with `perRequestMemMb`), or it's dishonest.

Ship Slice 0, verify in-app, then stage 1 → 2 → 3 → 4 → (5 when unblocked). (Cost display in Slice 3 has no engine-physics dependency, so it can be pulled forward to run alongside Slice 0 if cost-awareness is the priority.)

---

## Mapping to the question bank

Priority is set by the 9 V1 questions in `system-design-simulator-questions/questions/`. This maps each to the slices it needs.

### The finding that drives everything

**Every reference topology today free-types `workers` and sets a uniform `capacity: 100000` on every node.** The saturation-based questions discriminate *only because the author hand-tuned a low worker count on the bottleneck store* — `url-shortener` starves `nosql-db` at `workers: 50`, `sensor-store` starves `time-series-db` at `60`, while front-tier nodes get `500`. Nothing physical backs those numbers, and `capacity: 100000` means nothing is ever admission-rejected.

This is exactly the dishonesty the spec fixes — and it has two consequences for the bank:

1. **These discriminators are currently gameable.** In any mode where the student can edit the store node, they crank `workers: 50 → 50000` and the "add a cache" lesson evaporates — the store no longer saturates. (Today `canEditScaffoldNodes`/palette limits paper over this by *forbidding* edits; the honest fix is to make cranking *cost* something.)
2. **Migration work per question.** Making concurrency instance-derived means re-expressing each hand-tuned worker count as an `instanceType` × `instanceCount` that reproduces the same saturation point — so the reference still PASSES and the gamed design still FAILS on the intended axis (the Dual-Topology Rule). This is authoring work, tracked below.

**Coupling to watch:** Slice 0 alone just *moves* the free dial from `workers` to `instanceCount`. It only closes the hole when it ships **with a cap** — per-node `maxInstances` (in Slice 0) and/or the always-on cost readout — so scaling concurrency visibly costs money or hits a ceiling.

### Per-question map

| Question | Workload | Intended discriminator | Nature | Slices it needs |
|---|---|---|---|---|
| **url-shortener** | read-heavy | Σ p99 < 100ms — no cache → KV saturates | **saturation** | **0, 1** (+ io-bound) — makes store saturation physical & un-crankable |
| **cache-placement** | read-heavy | placement + Σ p99 < 120ms — no cache → DB saturates | **saturation** | **0, 1** (+ io-bound) |
| **news-feed** | read-heavy | Σ p99 < 200ms — no read cache → timeline store saturates | **saturation** | **0, 1** (+ io-bound) |
| **sensor-store** | write-heavy | storageFit + Σ throughput — relational can't sustain TS writes | **throughput ceiling** | **0, 1**; **2** (write buffering / oom) |
| **async-sla** | write-heavy | structural + guardedPath — synchronous, no queue/workers | **capacity/structural** | **0, 1** — honest worker capacity makes "no workers" actually fail the SLA |
| **ride-hailing** | read-heavy | storageFit + placement — payments on KV, no geo cache | semantic + partial saturation | **0, 1** (geo-cache saturation); storageFit is topology |
| **cargo-cult-cdn** | read-heavy | forbidUnjustified — CDN added, never justified | over-provisioning | **3** — always-on **cost display** gives it teeth ("the CDN costs $/hr for zero benefit"), today only justification-gated |
| **messaging-fanout** | connection-heavy | fanout — work-queue to 3 ≠ pub/sub | structural/semantic | none (topology-shaped, not resource) |
| **web-crawler** | batch-heavy | guardedPath — enqueue without dedup index | structural/semantic | none required; **2** minor (frontier depth) |

### Components used across the bank

The palette the 9 questions actually draw from — every node type the resource/cost model must serve, with the label(s) it appears under and where it's used. (Alternate labels are just templates of the same `componentType`.)

| Palette label(s) | `componentType` | Role & where used |
|---|---|---|
| Client App | `api-endpoint` | The one valid traffic **source**; every question needs exactly one — **all 9** |
| CDN | `cdn` | Edge cache — **cargo-cult-cdn** (the "is this edge cache justified?" trap) |
| Load Balancer | `load-balancer` | Fronts the service — url-shortener, cache-placement, news-feed, ride-hailing |
| API Server / Service / My Service / Input Source | `microservice` | The app tier — **all 9**. The alternates are just other `microservice` templates |
| Job Worker / Cron Job | `batch-worker` | Async workers / fan-out consumers — async-sla, messaging-fanout, news-feed, web-crawler |
| Message Queue | `queue` | Work queue / frontier — async-sla, messaging-fanout, web-crawler |
| Event Broker | `message-broker` | Pub/sub fan-out — messaging-fanout, news-feed |
| Redis Cache | `in-memory-cache` | The read cache (the reinforcing loop) — cache-placement, news-feed, ride-hailing, url-shortener |
| KV Store | `kv-store` | Point-lookup store / dedup index — news-feed, ride-hailing, url-shortener, web-crawler |
| NoSQL DB | `nosql-db` | cargo-cult-cdn's data store |
| Primary DB / Read Replica | `relational-db` | Transactional store — async-sla, cache-placement, ride-hailing, sensor-store |
| Time-series DB | `time-series-db` | sensor-store (time-series ingest) |
| Object Storage | `object-storage` | web-crawler (page storage) |

**What this means for the resource model:** these types split cleanly by how the derivation should treat them, which directly shapes the per-type defaults for `workloadKind` and pricing regime:

- **CPU/compute tier** (`microservice`, `batch-worker`, `api-endpoint`, `load-balancer`) — the nodes where `workersPerInstance` and CPU-contention actually bite; default `cpu-bound` (or io-bound for the app tier when it mostly waits on a store — the async-tuning open question).
- **IO-bound stores** (`kv-store`, `nosql-db`, `relational-db`, `time-series-db`, `in-memory-cache`) — point-lookup/read/write serving; default **`io-bound`** so the vCPU→worker cap doesn't wrongly throttle them. These are exactly the hand-tuned-saturation nodes the migration touches.
- **Fan-out / async** (`queue`, `message-broker`) — capacity/backpressure nodes; `effectiveK`/RAM and the `oom` boundary matter more than CPU concurrency.
- **Edge / storage** (`cdn`, `object-storage`) — `cdn` is the over-provisioning-cost case (Slice 3); `object-storage` is a volume/egress case (Slice 5, gated) — neither is a compute-concurrency node.

Each type will need a sensible catalog default (a starting `instanceType` + `workloadKind`) so authors aren't sizing every node from scratch — a `time-series-db` should default to a bigger/`io-bound` box than a `microservice`. That default-per-type table is a Slice 0 authoring deliverable, drafted next.

### Default instance + workloadKind per type (Slice 0 deliverable)

Starting points, not locks — every field is author-overridable within the caps. The **`workloadKind` column is the load-bearing one**: defaulting the stores to `io-bound` is what keeps Slice 1's vCPU→worker cap from throttling the (correct) reference designs. Sizes are picked so a node comfortably serves the suites' `baseRps` 2–3k without being the accidental bottleneck — the *intended* bottleneck stays the author's to create by under-provisioning a specific node.

| `componentType` | Default `instanceType` | `workloadKind` | Pricing regime | Why |
|---|---|---|---|---|
| `api-endpoint` | `m5.large` | `io-bound` | provisioned | Traffic source / gateway — forwards, doesn't compute; high concurrency, light CPU |
| `load-balancer` | `m5.large` | `io-bound` | provisioned | Fans connections out; concurrency-heavy, negligible per-request CPU |
| `microservice` | `c5.large` | `cpu-bound` | provisioned | App tier runs business logic → CPU is the real limit. **The async-tuning fork:** flip to `io-bound` when it mostly awaits a store (open question #1) |
| `batch-worker` | `c5.large` | `cpu-bound` | provisioned | Async workers do real work per job; CPU-bound and contention-sensitive |
| `queue` | `m5.large` | `io-bound` | provisioned | Backpressure buffer — RAM/`effectiveK` and `oom` matter more than CPU |
| `message-broker` | `r5.large` | `io-bound` | provisioned | Pub/sub fan-out holds messages in memory → memory-optimized for buffering |
| `in-memory-cache` | `r5.large` | `io-bound` | provisioned | Redis — RAM *is* the capacity; memory-optimized is the whole point |
| `kv-store` | `m5.large` | `io-bound` | provisioned | Point-lookup serving; IO-bound. **A hand-tuned-saturation node — migration-critical** |
| `nosql-db` | `m5.xlarge` | `io-bound` | provisioned | Document/point-lookup at higher read volume; IO-bound |
| `relational-db` | `m5.xlarge` | `io-bound` | provisioned | Transactional store; IO-bound with CPU for txn work. **Migration-critical** (cache-placement saturation) |
| `time-series-db` | `r5.xlarge` | `io-bound` | provisioned | High-rate write ingest (sensor-store: 200K writes/s) → bigger, memory-heavy box. **Migration-critical** |
| `cdn` | `m5.large` | `io-bound` | provisioned (v1) | Edge cache — the point is it *costs* $/hr, exposing the cargo-cult trap. Egress/volume pricing is Slice 5, later |
| `object-storage` | `m5.large` | `io-bound` | volume (deferred) | Not a compute-concurrency node; real cost is GB + egress (Slice 5, gated). Placeholder provisioned box until then |

Notes: (1) no current node type defaults to the **consumption** regime — there's no serverless node in the V1 palette, so Slice 4 stays dormant until one is authored. (2) The three **migration-critical** rows (`kv-store`, `relational-db`, `time-series-db`) are the nodes whose hand-tuned low worker counts *create* the saturation discriminators — their default must be sized *above* the suite load, so the author still produces the bottleneck by explicitly under-provisioning, not by accident. (3) `object-storage` and `cdn` carry a real box only so they don't break the derivation; their honest cost model (volume/egress) arrives with Slice 5.

### What this says about slice priority

- **Slices 0 + 1 are the payload for the bank** — they protect **6 of 9** questions (all the saturation/throughput/capacity discriminators) from the "just crank workers" dodge and make the hand-tuned bottlenecks physical. Highest priority, and they must land together with the per-node `maxInstances` cap or the dodge just relocates to `instanceCount`.
- **`workloadKind` is not optional for the bank** — the saturating stores are point-lookup/read (`io-bound`); a vCPU→worker cap without the flag would wrongly throttle *correct* IO-bound designs and could break the reference topologies. It must ship with Slice 1.
- **Slice 3 (cost) benefits exactly one current question** (`cargo-cult-cdn`) plus the general anti-kitchen-sink intent — no question sets a `budget` today, so cost *discrimination* requires either adding budgets to questions or authoring new cost-focused ones. The always-on cost *display* is still worth pulling forward (cheap, no physics dep) to give over-provisioning a visible price.
- **Slices 4 & 5 benefit zero current questions** — no question compares provisioned-vs-consumption or turns on egress/inter-region cost. Per the scoping principle, they wait until a question is authored that needs them. (Requests already carry `sizeBytes` in the workload cases, so the request-size dependency for 5 is partially de-risked when that time comes.)
- **fanout & crawler** are topology-shaped; the resource model doesn't move their needle. Don't hold them up for it.

**Net build order for the bank:** Slice 0 + `maxInstances` + always-on cost display → Slice 1 (with `workloadKind`) → migrate the 6 saturation/throughput references to instance types (preserving each discrimination point) → Slice 2 for the write-heavy trio → Slice 3 budgets + a cost-discriminating question → 4/5 only when a question demands them.

---

## Source-to-feature map

| Source | Role in this spec |
|---|---|
| `src/engine/catalog/instanceCatalog.ts` (new) | Frozen `INSTANCE_CATALOG` reference table; the menu authors pick from. |
| `src/engine/core/types.ts:214` (`ResourceConfig`) | Replace free `{cpu,memory}` with `instanceType`/`instanceCount`/`maxInstances`; currently unread by the engine. |
| `src/engine/core/types.ts:221` (`QueueConfig`) | `workers`/`capacity` become derived outputs. |
| `src/engine/nodes/GGcKNode.ts` | The consumer — resolves the catalog, builds `effectiveC`/`effectiveK`; utilization divides by `effectiveC`. |
| `src/engine/analysis/environmentProfile.ts:38` (`EnvironmentCapabilities`) | Home for `resourceBudget` (vCPU/RAM quota) + `costBudget` (money cap), beside `maxTestRuns`. |
| `src/engine/analysis/budget.ts:37` (`estimateNodeCost`) + `budgetBreakdown` | Replace the soft heuristic with the instance-price sum; `budgetBreakdown` already returns per-node line items → drives the always-on cost display. |
| `src/engine/analysis/structural.ts:247`, `rubric.ts:192` | Already sum `replicas` for scoring — retarget to `instanceCount`; become consistent with physics once Slice 0 lands. |
| `src/engine/metrics/windowedLatencyAggregator.ts` (`classifyRejectionCause`) | Add `oom` to the closed taxonomy. |
| `src/engine/validation/validator.ts:346` | `resources` zod schema — enforce `instanceType` enum + `instanceCount ≤ maxInstances`. |
| `src/engine/__mocks__/orderProcessingTopology.ts` | Carries legacy `resources: { cpu, memory, replicas }` — migrate to instance types as fixtures. |

---

## Open questions

1. **Fully-derived vs constrained `workersPerInstance` — and whether the app-level knobs stay at all (DECIDE LATER).** The instance type sets the *ceiling* for both concurrency and queue depth (`cpuCeiling` from vCPU, `memCeiling` from RAM), but doesn't fully *decide* them — `workersPerInstance` (app concurrency: gunicorn workers / thread pool) and the queue-slots depth (accept backlog / load-shedding policy) are app-level settings that live *inside* the ceiling. `effective = min(configured, ceiling)`. So the fork is three-way: (a) **keep both knobs**, capped — richest (models sync-vs-async worker tuning and fail-fast-vs-buffer queue depth, and lets an author write a misconfigured-concurrency bug on correct hardware); (b) **derive defaults from `instanceType` + `workloadKind`, override within cap** — a student who does nothing gets a correct machine, tuning stays available (recommended lean); (c) **fully derive, drop the knobs** — `workersPerInstance` defaults (= vCPU for cpu-bound, vCPU × N for io-bound) and `effectiveK` = `memCeiling` directly, with the separately-authored queue slots removed — fewest dials, tightest "pick hardware, physics follows" story, but loses the tuning lessons. The queue-slots field is the weakest and the easiest to drop independently (let RAM fully decide `K`). **Not decided — revisit before Slice 0.** Until then the spec/examples keep both knobs explicit for clarity.
2. **CPU-bound vs IO-bound signal.** The vCPU→concurrency cap only holds for CPU-bound work; IO-bound legitimately runs workers ≫ vCPU. `workloadKind` is proposed as new on `ResourceConfig` — confirm no existing node property already carries this, else the model punishes correct IO-bound designs.
3. **`perRequestMemMb` provenance.** Per-node authored constant, or derived from request/workload size (`request-type-model.md`)? A workload-derived footprint is more honest but couples this spec to the request model.
4. **Pricing & cost cap — RESOLVED.** Each instance type carries a `pricePerHour`, and **cost is a separate cap from quota — both apply** (a design can be within vCPU/RAM quota yet over the money budget, and vice versa). Cost is also an **always-on display**, shown on every topology regardless of whether a `costBudget` is set. Remaining sub-question: does the catalog need more families later (GPU/accelerated, storage-optimized `i3`)? Deferred — the 12-type set is v1.
5. **Environment budget default — RESOLVED.** No cap by default: **AUTHOR** and **open builds** are unbounded (no `resourceBudget`, no `costBudget`); **ASSIGNMENT/PRACTICE** may set either or both. But **cost is always displayed** in every mode — "unbounded" means no *gate*, never no *number*. See the defaults table in [The caps](#the-caps-quota-cost-and-per-node).
6. **`perRequestMemMb` provenance** (was #3, still open — see above).
7. **Autoscaling (`maxInstances` as a live ceiling).** Out of scope for v1 (static allocation). Reserved for a later slice where offered load drives `instanceCount` between a floor and `maxInstances` at runtime.

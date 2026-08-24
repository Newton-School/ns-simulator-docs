# Budget Feature - Consolidated Design (V3)

> **What this is.** A single, decision-ready design that merges the V1 "why it's
> broken" analysis, the V2 "how to fix it" plan, and the second-order review - then
> hardens all three against how infrastructure cost is *actually* calculated in the
> real world. It supersedes nothing structurally (the V1 decision and V2 direction
> both stand); it tightens the cost model, adds the network dimension both prior docs
> under-weighted, and turns the loose recommendations into concrete, testable numbers.
>
> **Status.** V1 decision = shipped (budget removed from `async-sla` / `sensor-store`,
> meter auto-hides). Everything below is the V2/V3 build plan - **plan only**.
>
> **Companions (authoritative for detail).** This is the *design*. The code-level
> translation lives in `budget-feature-implementation-v3.md` and the finalized cost
> arithmetic in `budget-cost-model-math.md`. Those two carry refinements that post-date
> this draft and **supersede it where they differ**: the operator is `floor` (below);
> the "foil" is a **third topology** distinct from the gamed one; the cap/guardrail read
> the **full grade-time cost** while the live meter is a degraded preview; `wrong_unit`
> is advisory; and the network term is a deliberately **coarse proxy**.

---

## 0. TL;DR

2. **V1 decision was right - keep it.** A budget that a correct 5-node design uses 5%
   of is a graded test that can't fail. It taught nothing and gave false confidence.
   It's already removed. Don't second-guess this.
3. **The real fix is not "make the cap tighter" - it's "make cost depend on the
   architectural *choice*."** A budget only teaches when a correct-but-expensive design
   *fails* while a correct-and-cheap design *passes*. That requires per-type base costs
   plus cap-last calibration. Both prior docs got this right.
4. **The one thing both docs under-model is network/data-transfer cost** - which in the
   real world is the single biggest source of surprise overruns (~10-15% of cloud
   bills, and the classic way junior architects blow budget). V3 promotes the edge from
   a flat `1` to a **traffic-weighted cost**, because that's where the richest "chatty
   architecture is expensive" lessons live.
5. **Ship in three de-risked phases**: `nodes` cap (no model) → per-type `cost` model →
   traffic-weighted edges. Each phase is independently valuable and independently
   testable. Don't wait for the perfect model to ship the anti-kitchen-sink cap.
6. **A validator guardrail makes the V1 bug unshippable.** Any budget question must
   carry a reference *and* a foil, and the harness asserts the foil actually costs more
   and actually exceeds the cap. If it can't, the budget isn't doing anything and the
   build fails.

---

## 1. The problem, stated precisely

The V1 budget model was `nodeCost = 1 + replicas + ceil(workers/50)`, summed with
`+1 per edge`, graded as one pass/fail row against a cap. Measured on the two live
questions:

| Question       | Reference cost | Gamed cost | Cap | Reference uses |
| -------------- | -------------- | ---------- | --- | -------------- |
| `async-sla`    | 36             | 21         | 600 | **6.0%**       |
| `sensor-store` | 22             | 21         | 500 | **4.4%**       |

Three independent failures, each fatal on its own:

- **The cap can't bite.** A correct design uses ~5% of the cap. Reaching the cap needs
  ~150 nodes. On a 4-6 node question that never happens → the row **always passes**.
- **It points the wrong way.** The *gamed* design is *cheaper* than the reference
  (fewer nodes), so budget separates good from gamed in the **opposite** direction from
  every other grading axis. It's not just useless, it's anti-correlated.
- **It's the wrong lesson for the question.** `async-sla` teaches async decoupling;
  `sensor-store` teaches storage-fit. Cost is bolted onto both. Neither is a
  cost/tradeoff question, so no cap value could make budget the point.

The root cause is not the cap number. It's that **every node costs the same**, so
"choose the cheaper architecture" is a meaningless instruction - there is no cheaper
architecture, only a smaller one. And "smaller" already fights the structural rules
that *require* specific components. That is why a flat-cost budget can only ever be
noise on these questions.

---

## 2. Design principle: budget grades a *decision*, not a *size*

The whole feature earns its place only if it can express exactly one thing that no
other axis expresses:

> There are two designs that **both satisfy every functional requirement**, and the
> lesson is that **one is affordable and one is not**.

If you can't name those two designs for a question, that question should not have a
budget. This is the single test that gates everything else. It reframes budget from a
"don't overbuild" penalty (which `unit: 'nodes'` already handles) into a
"cost-aware architecture" axis (which needs a real cost model).

Concretely, a budget question always ships as a **pair**:

- **Reference** - minimal, correct, *and* affordable. Cost `C_ref`.
- **Foil** - correct on every *other* axis, but takes the expensive route
  (kitchen-sink, or brute-force replicas/workers/DB). Cost `C_foil`.

The budget is meaningful iff `C_ref < cap < C_foil`. That inequality is the feature.

---

## 3. How real infrastructure cost works (and what to borrow)

Both prior docs correctly anchor on the three real cost dimensions. The research
sharpens the *magnitudes*, which is what makes the pedagogical model feel authentic
instead of arbitrary. Real cloud bills decompose into **compute, storage, and
network/data-transfer**, and each maps cleanly onto a simulator lever:

**Compute - scales with instances and instance class.** Billed per second by CPU/RAM.
Scaling out is linear (5 instances = 5× base); scaling up is roughly linear in
resource. The key pedagogical fact: a **managed, stateful** service (a managed
relational DB) carries a real premium over raw stateless compute - commonly cited at
~20-30% per compute-hour, and far more for premium engines (Aurora runs ~70% over a
plain instance), because the provider is absorbing backups, patching, failover, and
replication. → **This is exactly what a per-type base cost encodes.** A relational DB
*should* cost several times a stateless worker.

**Storage - tiered, and the tiers span ~20×.** Hot SSD block storage (what a
transactional DB sits on) is expensive; object storage is cheap; archive/cold storage
is nearly free (GCS Standard ≈ $0.02/GB-mo vs Archive ≈ $0.0012/GB-mo). And
**replicas multiply storage** - 3 replicas store the data three times. → **This is the
`BASE[type] × replicas` term.** The replica multiplier is not a fudge; it mirrors both
the compute standby cost and the triplicated storage.

**Network / data transfer - the hidden killer.** Ingress is usually free; **egress and
cross-AZ traffic are billed per GB and are where budgets actually blow up** - Gartner
puts egress at ~10-15% of total spend, and a single chatty cross-AZ Kafka stream can
run into five or six figures a year in network fees alone. Crucially, network cost
scales with **traffic volume on the link**, not with the number of links. → **This is
the strongest lesson neither prior doc fully captured.** A flat `+1 per edge` says
"fewer connections are cheaper," which is a weak and sometimes wrong lesson. A
**traffic-weighted edge** says "a chatty, high-throughput, large-payload link is
expensive" - which pushes students toward caching, batching, payload trimming, and
locality, i.e. the actual craft of cost-aware design.

The takeaway the model must embody: **cost is driven by *what you choose* (type),
*how much you replicate it* (multiplier), and *how much data you push over each link*
(traffic) - not by raw node/edge count.** Count is a proxy the V1 model mistook for
the real thing.

---

## 4. Cost model V3

```
nodeCost(node) = BASE[type] * replicas
               + floor(capacity(node) / CAPACITY_UNIT[type])
edgeCost(edge) = EDGE_BASE + floor(throughputMBps(edge) / NETWORK_UNIT)
total          = Σ nodeCost + Σ edgeCost
```

> **Operator = `floor`, not `ceil`.** The scaling terms must contribute **0 below one
> full unit** - otherwise every node with ≥1 worker and every edge with any traffic gains
> a spurious +1, contradicting §4b's own "a 1 KB/s link adds 0" and making a "thin edge"
> or a default-sized node impossible to price at base. (Corrected from the original draft;
> see the worked examples in `budget-cost-model-math.md`, which foot only under `floor`.)

Three deliberate changes from V2's `nodeCost = BASE[type]*replicas + ceil(workers/100)`
and flat `EDGE_COST * edges`:

2. **Type-aware capacity cost.** `CAPACITY_UNIT[type]` replaces a single global
   `WORKER_UNIT`. Adding 50 workers to a stateless microservice is cheap (large unit);
   adding 50 connection threads to a relational DB is expensive (small unit). This is
   the review's "make workers hurt more, tied to node type" point, made concrete.
3. **Traffic-weighted edges.** The edge term reads the simulated `throughputMBps` on
   the link, so a 100 MB/s link costs far more than a 1 KB/s link. This is the network
   dimension promoted to a first-class lever.
4. **Everything else is V2, kept.** `BASE[type] × replicas` is unchanged in spirit -
   it was the correct core insight.

### 4a. Base cost by role (the managed-service premium)

Ordering follows real-world stateless→stateful→managed premium. Numbers are
pedagogical; **relative order is the lesson**, absolute values are tuned at
implementation.

| Base | Role                                | Types                                                                                         |
| ---- | ----------------------------------- | --------------------------------------------------------------------------------------------- |
| 0    | Free source                         | `api-endpoint`                                                                                |
| 2    | Stateless compute / cheap infra     | `microservice`, `batch-worker`, `queue`, `load-balancer`, `in-memory-cache`, `object-storage` |
| 3    | Light stateful / edge               | `cdn`, `kv-store`                                                                             |
| 4    | Managed distributed stores          | `message-broker`, `nosql-db`, `time-series-db`, `search-index`, `distributed-lock`            |
| 5    | Heavy managed / append-only ledgers | `event-sourcing-store`                                                                        |
| 6    | Premium managed ACID                | `relational-db`                                                                               |

The `relational-db = 6` vs `in-memory-cache = 2` gap **is** the managed-ACID premium
the research confirms. It's what makes "cache vs replicas" a real fork:

- add a cache: `in-memory-cache` = **2** → fits.
- add 3 read replicas: `relational-db × 3` = **18** → blows the cap.

### 4b. Starting constants

| Constant                    | Start | Rationale                                                                      |
| --------------------------- | ----- | ------------------------------------------------------------------------------ |
| `CAPACITY_UNIT` (stateless) | 100   | Throughput scaling is a minor, coarse cost on cheap compute.                   |
| `CAPACITY_UNIT` (stateful)  | 25    | Connections/IOPS on a DB are ~4× more costly per unit than on a worker.        |
| `EDGE_BASE`                 | 1     | Every link has a small fixed cost (a hop exists).                              |
| `NETWORK_UNIT`              | 50    | MB/s per unit of network cost - a 100 MB/s link adds +2, a 1 KB/s link adds 0. |

> **Backward compatibility.** If a `type` is absent from `BASE`, default to the V2/V1
> behavior (base 1). If an edge has no simulated throughput, `edgeCost = EDGE_BASE`
> only. This lets the model ship without re-authoring every existing topology.

---

## 5. Unit strategy - three tools, matched to three lessons

| Unit             | Lesson it teaches                         | When to use it                                                              |
| ---------------- | ----------------------------------------- | --------------------------------------------------------------------------- |
| `nodes` (count)  | "Don't add every component just in case." | Anti-kitchen-sink. Predictable, bites instantly, needs **no** cost model.   |
| `cost` (§4)      | "Choose the cheaper architecture."        | Cost/performance tradeoffs (cache vs replicas, right-store vs brute-force). |
| `cost` + traffic | "Chatty, heavy links are expensive."      | Locality / batching / caching lessons where the network is the bottleneck.  |

`nodes` is not a lesser `cost` - it's a *different lesson* and often the right one. Use
a hard `constraints.maxNodeCount = 8` when the only goal is to stop drag-50-nodes-on-the-
canvas behavior; reserve the cost model for genuine tradeoffs. Both ship; questions
pick the one that matches their lesson.

---

## 6. Cap-last authoring procedure (the only correct order)

A cap is **derived, never guessed**. The V1 caps (600/500) were round numbers picked
before any design existed - that's the whole bug.

2. **Confirm the lesson is cost/tradeoff.** If you can't name a reference and a foil
   that both pass every other axis, *stop - no budget on this question.*

3. **Build the reference** (minimal, correct, affordable). Measure `C_ref`.

4. **Build the foil** (correct on other axes, expensive route). Measure `C_foil`.

5. **Set the cap in the gap:** `cap = round(C_ref × 1.15)` - reference just fits,
   ~15% slack. Verify `C_ref ≤ cap < C_foil`.

6. **Validate both through the harness** (`validate-question-dir.ts`):

   - reference → within budget **and** passing all axes;
   - foil → **over budget** (ideally *also* failing perf, so the affordable design is
     also the correct one - the strongest version of the lesson).

7. **Assert the discrimination:** `C_foil > cap` **and** `C_ref < C_foil`. If the foil
   is cheaper than the reference, the budget is meaningless. This assertion is exactly
   what would have caught V1.

---

## 7. Redesigned questions (concrete numbers)

### 7a. `async-sla` → "Meet a 15s SLA on a budget"

- **Tension:** an async queue + modest workers is cheap and meets the SLA; a synchronous
  path brute-forced with a big replicated DB is expensive **and still spikes** on bursts.
- **Reference:** `client → svc(2) → queue(2) → worker(2) → relational-db(6)` + 4 edges
  → `C_ref ≈ 16`. **`cap = 18`.**
- **Foil:** `client → svc → relational-db(6 × 3 = 18)` chasing the SLA
  → `C_foil ≈ 22` (`0 + 2 + 18 + 2 edges`), over budget *and* still risks the 15s SLA
  under spike. (Full worked table in `budget-cost-model-math.md` §8.)
- **Lesson:** decoupling is cheaper than scaling the datastore.

### 7b. `sensor-store` → "Ingest 200k writes/s on a budget" *(needs `storageProfile`)*

- **Tension:** a time-series DB is *both cheaper and faster* for the write workload; a
  relational DB sharded with replicas to brute-force throughput is *expensive and still
  saturates*.
- **Reference:** `client → svc(2) → time-series-db(4)` + 2 edges → `C_ref ≈ 8`.
  **`cap = 10`.**
- **Foil:** `client → svc → relational-db(6 × 3 = 18)` → `C_foil ≈ 20`, over budget;
  with `storageProfile`, the relational write path *also fails throughput*.
- **Lesson:** the right storage engine is cheaper **and** faster. This is the single
  best budget question - but it **depends on the `storageProfile` trait** to make the
  wrong store physically slower, not merely pricier.

### 7c. *(New, V3)* `chatty-services` → "Cut the network bill" *(needs traffic-weighted edges)*

- **Tension:** two microservices exchanging large payloads 100k×/s over a cross-link is
  correct but network-expensive; inserting a cache (or batching the calls) satisfies the
  same SLA far more cheaply.
- **Reference:** `client → svc-a(2) → cache(2) → svc-b(2)`, thin edges → `C_ref ≈ 9`.
  **`cap = 10`.**
- **Foil:** `client → svc-a(2) → svc-b(2)` with a fat ≈300 MB/s direct link → the edge
  term alone pushes `C_foil ≈ 12` over the cap. Two valid integer caps in the gap
  (`10`, `11`). (Worked table + integer-gap check in `budget-cost-model-math.md` §8b.)
- **Precondition:** the fat link must be **fast enough to pass the SLA** while **too
  expensive to afford** - if removing the cache also blows p99, the foil fails perf and
  collapses back into a gamed topology, not a clean "affordable-vs-not" fork.
- **Lesson:** chatty, heavy links cost real money - cache/batch to cut egress. This is
  the question the flat `+1 per edge` model *could never express*, and the reason to
  build traffic-weighted edges.

---

## 8. Guardrail - the non-binding-budget detector

Add to `authoringValidator.ts` so the V1 class of bug is **unshippable**. Given a
budget question with reference + foil topologies, fail the build (or warn hard) when:

| Check                | Condition                               | Meaning                                                |
| -------------------- | --------------------------------------- | ------------------------------------------------------ |
| `budget.non_binding` | `C_ref / cap < 0.6`                     | Cap too loose to ever bite (the V1 5% case).           |
| `budget.misaligned`  | `C_foil ≤ C_ref`                        | The "wrong" design isn't more expensive - anti-signal. |
| `budget.no_foil`     | no foil supplied                        | Discrimination can't be demonstrated at all.           |
| `budget.wrong_unit`  | `unit: cost` but all types share a base | Cost can't separate designs; use `nodes`.              |

The first three would have flagged `async-sla` 36/600 and `sensor-store` 22/500 on day
one. The fourth catches the subtler mistake of using the cost model without the
per-type differentiation that gives it meaning.

---

## 9. UI plan

- **Graded meter:** reuse the existing `BudgetMeter` (cost/cap + color states) as-is
  once questions declare a budget again.
- **Per-type breakdown:** the breakdown table shows each node's *base × replicas* and
  each edge's *traffic contribution*, so a student sees **why** they're expensive
  (`relational-db ×3 = 18`, `svc-a→svc-b link = 6`), not just that they are. This is
  where the cost *lesson* actually lands.
- **Ungraded "footprint" (optional, any question):** a no-cap, no-pass/fail readout of
  total cost on every question, purely to build cost intuition. Small, separable change.
- **Author-mode calibration hint:** show `C_ref`, `C_foil`, and `C_ref/cap` at authoring
  time so the author can *see* the cap bite before shipping.

---

## 10. Phasing (each phase independently shippable)

2. **`nodes`-unit cap.** No cost model. A hard `maxNodeCount` on one anti-kitchen-sink
   question. Lowest risk, immediate value, ship first.
3. **Cost model V3 core** (§4a + `BASE × replicas` + type-aware `CAPACITY_UNIT`) in
   `budget.ts` + `budgetBreakdown`. Backward-compatible defaults.
4. **`storageProfile` trait.** Prerequisite for the strong `sensor-store` question
   (§7b) - makes the wrong store physically slower.
5. **Traffic-weighted edges** (§4 edge term). Unlocks `chatty-services` (§7c).
6. **Validator guardrail** (§8) + calibration UI (§9).
7. **Re-attach budgets** to the redesigned questions via the cap-last procedure (§6),
   and validate end-to-end.

Phases 1-2 deliver a working, meaningful budget. 3-4 deepen it. 5 makes regressions
impossible. Nothing here blocks V1 shipping without any budget at all.

---

## 11. Test plan

- **Unit (`budget.test.ts`):** per-type base costs; replica multiplier; type-aware
  capacity units; traffic-weighted edges; a foil always costs more than its reference.
- **Authoring (`authoringValidator.test.ts`):** all four §8 checks fire on
  non-binding / misaligned / no-foil / wrong-unit budgets.
- **E2E (`validate-question-dir.ts`):** for each redesigned question - reference within
  budget + passing all axes; foil over budget (+ failing perf where applicable).
- **Regression:** replay the V1 `async-sla` 36/600 and `sensor-store` 22/500 configs
  through the validator and assert they now **fail** authoring.

---

## 12. Definition of done

2. Cost model V3 shipped + tested: per-type base, replica multiplier, type-aware
   capacity units, traffic-weighted edges.
3. At least one **real** budget question where the reference fits and a correct-but-
   expensive foil exceeds - proven by the harness, not by eye.
4. The non-binding-budget validator is active and blocks a decorative budget from
   shipping (regression test on the old V1 configs passes = they now fail authoring).
5. Meter + breakdown show per-type and per-edge cost contributions.
6. `nodes`-unit anti-kitchen-sink cap available as a distinct, documented tool.

---

## 13. What changed from V1/V2 → V3, in one paragraph

V1 correctly diagnosed a can't-fail budget and removed it. V2 correctly prescribed
per-type base costs + cap-last calibration to make cost depend on *choice*. V3 keeps
both intact and adds the dimension the real-world research says matters most and both
docs under-modeled: **network cost as a traffic-weighted edge**, which converts the
weak "fewer connections" signal into the rich "chatty, heavy links are expensive"
lesson. It also makes worker/capacity cost **type-aware** (a DB connection costs more
than a worker thread), promotes the validator guardrail from "warn" to "block," and
sequences delivery so a meaningful budget ships in two phases while the network-cost
depth follows without blocking anything.

# Memory Pressure & Memory-Bound Model

> **Purpose.** Define how the simulator should represent "memory-bound" behavior
> without overloading the existing `cpu-bound` / `io-bound` execution-profile
> model, and specify the first additive runtime slice that makes memory pressure
> visible before hard `oom`.

> **Implemented first slice.**
>
> - Trait: `src/engine/traits/memoryPressure.ts`
> - UI wiring: `src/engine/traits/capabilityModules.ts`
> - Canvas schema + round-trip:
>   - `src/engine/catalog/nodeSpecTypes.ts`
>   - `src/engine/catalog/componentSpecs.ts`
>   - `src/renderer/src/utils/topologyCanvasAdapter.ts`
> - Authored-topology validation:
>   - `src/engine/validation/validator.ts`

---

## 1. Executive Summary

The simulator already has:

- **CPU-vs-IO execution profiles** for concurrency derivation
- **RAM-capped admission** for `K`
- a distinct terminal cause: **`oom`**

That is useful, but incomplete.

It captures the **hard memory limit**:

> the node eventually cannot admit more work

but it does not capture the **soft memory-pressure regime**:

> the node gets slower before it dies

That missing regime is what students mean when they say:

- "the cache no longer fits in memory"
- "the heap is thrashing"
- "the broker is under memory pressure"
- "tail latency rises before OOM"

The right design is:

> **Keep `workloadKind` as `cpu-bound | io-bound`, and model memory as a separate
> orthogonal trait.**

We should **not** add `memory-bound` as a third `workloadKind` in the first cut.

Why:

- CPU-vs-IO decides how vCPU caps concurrency
- memory pressure is a different axis
- a node can be `io-bound` **and** memory-sensitive
- a node can be `cpu-bound` **and** memory-sensitive

So "memory-bound" belongs in the simulator as **memory pressure / working-set fit
physics**, not as a replacement for the execution-profile model.

---

## 2. What Exists Today

### 2.1 Execution profile

Today `WorkloadKind` is:

- `cpu-bound`
- `io-bound`

This is correct for the question:

> does vCPU tightly cap real parallelism, or does the node multiplex many waits?

### 2.2 RAM already caps admission `K`

Today `deriveNodeConcurrency()` computes:

- `effectiveC` from vCPU × workload kind
- `effectiveK` from RAM ÷ per-request footprint

This already makes RAM operationally real.

### 2.3 `oom` is already a first-class terminal cause

The engine already distinguishes:

- `queue_full`
- `oom`

This is important and should remain.

It correctly teaches:

- "add workers" is not the same fix as
- "add RAM / more instances"

---

## 3. The Missing Behavior

Today the simulator jumps too sharply from:

- normal behavior

to:

- hard `oom`

What is missing is the **soft-degradation region** where:

- the hot working set no longer fits
- GC/heap pressure rises
- tail latency degrades before admission failure

That region is often the real lesson.

Examples:

| Node / pattern | What should happen before OOM |
|----------------|-------------------------------|
| `in-memory-cache` with a hot set > RAM | requests get slower because the working set spills / evicts |
| `message-broker` with large backlog | queueing stays possible, but latency rises under memory pressure |
| `search-index` / `vector-db` | query latency rises when the hot index no longer fits |
| `microservice` / `batch-worker` | heap pressure creates GC-style tail-latency inflation |

---

## 4. Design Decision

### 4.1 Do **not** add `memory-bound` as a third `workloadKind` yet

`workloadKind` should stay:

- `cpu-bound`
- `io-bound`

because its job is:

- deciding how concurrency scales with vCPU
- deciding how sensitive service time is to faster CPUs

Adding `memory-bound` there would blur two unrelated concerns:

1. **parallelism shape**
2. **memory pressure**

Those should remain separate.

### 4.2 Add a new orthogonal trait: `memory.pressure`

The trait models two distinct but related ideas:

| Mechanism | Meaning |
|-----------|---------|
| **working-set oversubscription** | the hot bytes exceed available RAM |
| **live GC / heap pressure** | the node is close enough to full that memory churn adds latency |

These are different:

- the first is about **steady-state fit**
- the second is about **near-capacity pressure**

They can happen together.

---

## 5. First Slice: Implemented Runtime Model

The first slice is intentionally simple and additive.

It does **not** replace the queue model.

It adds **per-request latency penalties** before the base queue/service model runs.

### 5.1 Config fields

| Field | Meaning | Default behavior |
|------|---------|------------------|
| `workingSetRatio` | hot working set / provisioned RAM | absent = disabled |
| `workingSetPenaltyMs` | max penalty contributed by oversubscribed working set | if `workingSetRatio` is authored and this is absent, use a small default |
| `gcPressureStartRatio` | fraction of RAM-bound `K` at which pressure begins | absent = disabled unless `gcPauseMs` is authored |
| `gcPauseMs` | max extra latency at full memory pressure | absent = disabled unless `gcPressureStartRatio` is authored |

### 5.2 Pressure math

#### A. Working-set pressure

If:

- `workingSetRatio <= 1`

then:

- no working-set penalty

Else:

```text
workingSetPressure = clamp((workingSetRatio - 1) / workingSetRatio, 0, 1)
workingSetPenalty  = workingSetPressure × workingSetPenaltyMs
```

This means:

- `1.0x RAM` -> `0`
- `2.0x RAM` -> `0.5`
- `4.0x RAM` -> `0.75`

So oversubscription hurts more as the hot set grows, but it saturates rather than
exploding unboundedly.

#### B. GC / live memory pressure

Let:

```text
occupancyRatio = totalInSystem / effectiveK
```

where `effectiveK` is already RAM-derived.

If:

- `occupancyRatio <= gcPressureStartRatio`

then:

- no GC pressure penalty

Else:

```text
gcPressure = clamp(
  (occupancyRatio - gcPressureStartRatio) / (1 - gcPressureStartRatio),
  0,
  1
)
gcPenalty = gcPressure × gcPauseMs
```

#### C. Total first-slice penalty

```text
totalPenaltyMs = workingSetPenalty + gcPenalty
```

This is written into the request metadata and added to the service time for that
request.

### 5.3 What this slice intentionally does **not** do

It does not yet model:

- exact bytes in cache vs index vs heap vs buffers
- eviction policy differences
- allocator fragmentation
- page-cache interaction
- true stop-the-world pause distributions
- memory-bandwidth stalls at CPU-cacheline level

That is acceptable for v1 of the trait.

The first slice only needs to teach:

> **memory pressure can make a node slower before it makes it reject.**

---

## 6. Relationship To Existing `oom`

The new trait does **not** replace `oom`.

Instead:

- the base queueing/resource model still owns **hard admission**
- the memory-pressure trait owns **soft slowdown before the cliff**

That separation is important.

The simulator now tells a more truthful story:

1. pressure rises
2. latency degrades
3. eventually the node hits RAM-bound `K`
4. the next request becomes `oom`

That progression is much closer to how real systems feel.

---

## 7. Where The First Slice Applies

The initial trait is attached only to obviously memory-sensitive nodes:

- `microservice`
- `batch-worker`
- `in-memory-cache`
- `queue`
- `message-broker`
- `pub-sub`
- `stream`
- `event-bus`
- `search-index`
- `vector-db`
- `memory-fabric`

This keeps the model honest and avoids suggesting that every node needs a memory
story immediately.

---

## 8. Metrics And Visibility

The first slice reports generic trait counters:

- `memoryPressureEvents`
- `workingSetPressureEvents`
- `gcPressureEvents`

These are intentionally count-based first:

- cheap
- deterministic
- easy to expose in node detail

The node detail panel should present them as readable labels, not raw keys.

Future slices can add richer first-class metrics such as:

- `memoryUtilization`
- `workingSetOverflowRatio`
- `gcPauseP99Ms`
- `evictionRate`
- `spillRate`

---

## 9. Why This Is The Right First Cut

This design is good because it is:

- **additive**: it does not rewrite GGcKNode
- **orthogonal**: it does not distort CPU-vs-IO semantics
- **deterministic**: no new randomness required
- **visible**: counters and latency penalty are observable
- **compatible**: absent config = no behavior change

That last property matters most:

> existing questions and existing topologies keep their behavior unless an author
> explicitly turns memory pressure on

---

## 10. Future Slices

Once the first slice lands, the natural next steps are:

### Phase 2

- dedicated `memoryUtilization` in per-node metrics
- time-series charting for memory pressure
- event-timeline markers for GC-style slowdowns

### Phase 3

- cache-specific working-set semantics:
  - hit-rate erosion
  - eviction
  - hot-key amplification
- broker-specific memory/backlog spill semantics
- index-specific "fits in RAM vs partial scan" behavior

### Phase 4

- explicit `gcJitter` or `heapCompaction` distributions
- memory-pressure-driven rejection modes beyond `oom`
- richer grading hooks for memory-sensitive lessons

---

## 11. Bottom Line

The simulator should treat memory as:

> **an orthogonal pressure model on top of the existing queue/resource engine**

not as:

> **a third execution-profile enum next to CPU and IO**

The implemented first slice does exactly that:

- keep `cpu-bound | io-bound`
- preserve RAM-derived `K` and `oom`
- add soft latency penalties for:
  - working-set oversubscription
  - near-full GC / heap pressure

That is the right abstraction for making "memory-bound" teachable in this
simulator.

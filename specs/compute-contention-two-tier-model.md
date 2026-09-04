# Compute Contention: the Two-Tier Concurrency Model

Technical feature specification for `computeContention` — the last remaining **engine correctness gap**, not a coverage gap. It closes an active overstatement of capacity: today an io-bound node reports `c = vCPU × 32 × instances` fully-parallel servers, while the CPU-bound fraction of that work still contends for the node's few physical cores. Under exactly the high-concurrency load people stress-test, the model shows headroom the hardware does not have.

This is a **core change to `GGcKNode` service-time and concurrency semantics** — the most honesty-sensitive code in the engine (it produces the latency, throughput, and utilization integrals). It is explicitly *not* a penalty trait: a load-proportional `beforeArrival` penalty would double-charge congestion the queue's finite `c` already models. See [`resource-allocation-and-derived-concurrency.md`](./resource-allocation-and-derived-concurrency.md) (the `c`/`K` derivation this modifies), [`execution-profile-and-node-concurrency.md`](./execution-profile-and-node-concurrency.md), [`simulation-determinism-and-numerics.md`](./simulation-determinism-and-numerics.md) (the integral/determinism invariants this must preserve).

**Decision committed (Hritvik, 2026-09-03):** ship the *hard* version — two tiers, **CPU utilization as the single headline number**. No dual-utilization "caller picks" option; that reintroduces the ambiguity that is itself the doctrine problem. Spec first, no queue code, until §1 (the derivation question) resolves.

**STATUS — SHIPPED & GATE-PASSED (2026-09-03).** Implemented in `GGcKNode` + `metrics.ts` + `resourceDerivation.ts`. Two refinements emerged during implementation and are now part of the model:

1. **Headline utilization = `max(worker-occupancy, CPU-occupancy)`**, not CPU-occupancy alone. A pure-I/O node has CPU-occupancy 0, so a bare "CPU utilization" headline would read 0% while its connection pool is maxed — itself a lie. `max()` reports the *binding* resource: it collapses to worker-occupancy for legacy/pure-I/O nodes (zero regression) and to the identical value for cpu-bound nodes (`c = cores`), and only diverges upward when a compute-heavy node pins its cores while the worker pool looks idle. This is stricter-honest than the original §5 wording and supersedes it.
2. **The workloadKind-consistency rule (`effectiveCpuBoundFraction`).** The fraction must be consistent with the execution profile that derived `effectiveC`. A node's per-type `cpuBoundFraction` (§ sourcing doc) applies only when its `workloadKind` matches the type default. On an **override**: cpu-bound override → `1.0` (all on-core); **io-bound override on a cpu-bound type → a locked `IO_BOUND_OVERRIDE_CPU_FRACTION = 0.1`**, NOT the type's `1.0`. Without this, a `microservice` deliberately modelled io-bound (an app server that mostly waits on a downstream store — common in the question bank) would pair io-bound concurrency (64 workers) with cpu-bound contention (fraction 1.0, 2 cores) and be *falsely pinned*. This rule fixed 5 false reference regressions the migration gate caught.

**Migration gate result** (spec §8, `scripts/compute-contention-migration.ts`): `flipped: 0, drift-only: 17, unchanged: 11` across all 28 bank topologies — every reference still passes, every gamed still fails (discrimination preserved). Drift landed correctly: modest on app servers (io-override 0.1), large on the data tier (`db +84pp`, `tsdb +75pp` — stores honestly showing the CPU utilization they were hiding). 779 unit tests pass.

---

## Table of Contents

1. [The gating question: can `cpuBoundFraction` be *derived*, not free-typed?](#1-the-gating-question)
2. [What is actually wrong today](#2-what-is-actually-wrong-today)
3. [Why it cannot be a trait (the double-count trap)](#3-why-it-cannot-be-a-trait)
4. [The two-tier model](#4-the-two-tier-model)
5. [Utilization: one unambiguous headline number](#5-utilization-one-headline-number)
6. [Autoscaler interaction (explicit, not a follow-up)](#6-autoscaler-interaction)
7. [Determinism & the integral](#7-determinism-and-the-integral)
8. [Migration gate: before/after for existing questions](#8-migration-gate)
9. [Schema changes](#9-schema-changes)
10. [Phasing](#10-phasing)
11. [Open questions](#11-open-questions)

---

## 1. The gating question

**Everything below is conditional on this. Resolve it before any service-time math.**

`computeContention` moves the honesty burden from `c` onto a new number: **what fraction of each request's service time is CPU-bound work that contends for physical cores** (vs I/O wait that does not). Call it `cpuBoundFraction ∈ [0, 1]`.

If that fraction can only be **free-typed by the author**, we have not fixed the lie — we have *relocated* it from `c` to `cpuBoundFraction`, and re-opened the exact "crank the dial, bottleneck vanishes" hole that [derived concurrency](./resource-allocation-and-derived-concurrency.md) closed. An author who wants headroom back just sets `cpuBoundFraction = 0`.

So the honest version requires deriving it the way `c` is derived from hardware. Three candidate sources, in order of preference:

- **(A) From `workloadKind`, the existing locked axis.** We already classify each node `cpu-bound` vs `io-bound` and this drives `workersPerVcpu` (1 vs 32) in [resourceDerivation.ts](../../src/engine/nodes/resourceDerivation.ts). The cleanest honest move reuses that same classification: `cpu-bound → cpuBoundFraction ≈ 1.0`, `io-bound → cpuBoundFraction ≈ small locked constant` (the mirror of `IO_PERF_SENSITIVITY = 0.25`, which already encodes "io-bound work barely benefits from a faster core" — i.e. it is *mostly not on the core*). This is derivable, already-locked, and needs **no new authored field**. Strongest candidate.
- **(B) From a per-component-type default table**, like `getResourceDefaults`/`perRequestMemMb` — each component type ships a sourced default fraction, author may not override (or overrides only within a locked band). Derivable, but adds a table to source and defend.
- **(C) Free-typed with a locked cap.** Rejected unless (A) and (B) both fail — it is the relocated lie.

**Review outcome (2026-09-03): option (A) is rejected; option (B) is the answer.** Pressure-testing (A) against the actual [`resourceDefaults.ts`](../../src/engine/catalog/resourceDefaults.ts) table shows the io-bound types split into two populations that need *opposite* fractions, so a single binary-derived fraction cannot serve both:

- **Group 1 — negligible per-request CPU** (small fraction ≈ 0.05–0.1 correct, model becomes a near-no-op, as desired): all routers/proxies/gateways (`load-balancer`/`-l4`/`-l7`, `api-gateway`, `ingress-controller`, `reverse-proxy`, `service-mesh`, `nat-gateway`, `vpn-gateway`), serve/egress (`api-endpoint`, `cdn`, `object-storage`, `block-storage`, `distributed-file-system`, `data-lake`, `archive-storage`), backpressure (`queue`, `message-broker`, `pub-sub`, `event-bus`, `stream`, `task-queue`, `event-sourcing-store`), and O(1) lookups (`in-memory-cache`, `kv-store`, `rate-limiter`, `distributed-lock`).
- **Group 2 — io-bound-classified but genuinely CPU-heavy per request** (a small fraction *understates* them — and these are exactly the stores where CPU saturation is the real bottleneck): `vector-db` (ANN distance math), `columnar-db` / `data-warehouse` (OLAP scans, aggregation, (de)compression), `relational-db` (query planning, joins, sorts), `time-series-db` (rollups), `graph-db` (traversal), `search-index` (scoring/ranking).

Tune the single io-bound constant low → Group 2 keeps its false headroom (the lie survives on exactly the analytical stores). Tune it high → Group 1 proxies/caches are wrongly charged CPU contention. **One constant cannot be both — that is the concrete failure of (A).**

**Decision: option (B).** Add `cpuBoundFraction` to `ResourceTypeDefault` in `resourceDefaults.ts`, sourced per component type, author-locked (or locked-band) — the same mechanism that already sources `perRequestMemMb` and `workloadKind` per type. No new *kind* of knob, no free dial, natural home beside the other per-type physical defaults.

Option **(C) a third `workloadKind`** (e.g. `compute-over-data` for Group 2) was considered and set aside: `workloadKind` also drives `workersPerVcpu` (1↔32) and `IO_PERF_SENSITIVITY`, so a third value ripples into `c`-derivation and perf-factor and forces re-classifying/re-pricing existing nodes — higher blast radius for the same expressiveness (B) already provides.

**If (B) had also failed** — no per-type fraction sourceable without guessing — `computeContention` would stay deferred, because the honest version would not be achievable and the dishonest version is worse than the current known, documented overstatement.

> Gate: §1 is now resolved (option B). Proceed to the migration harness (§8) before any §4 service-time code.

---

## 2. What is actually wrong today

From [resourceDerivation.ts](../../src/engine/nodes/resourceDerivation.ts):

```
effectiveC = totalVcpu × workersPerVcpu(workloadKind) × instanceCount
             where io-bound ⇒ workersPerVcpu = 32,  cpu-bound ⇒ 1
```

A 4-vCPU io-bound node → `c = 128`. The queue then treats those 128 as **128 fully-parallel servers each running at full speed**. That is correct for the *I/O wait* portion (a core juggling 128 mostly-waiting requests is real). It is a lie for the *CPU* portion: those 128 requests still share **4 physical cores** for compute. Past ~4 simultaneously-computing requests, real CPU saturates and per-request service time stretches — the model shows none of that.

This is not a missing feature sitting in empty space. Congestion under load is *already* modeled by finite `c` (queue wait, utilization, the saturation hockey-stick all emerge from it). `computeContention` is a **correction to how `c` behaves for io-bound nodes**, not a new independent effect.

---

## 3. Why it cannot be a trait

Every latency trait shipped so far adds a penalty at `beforeArrival` via `SERVICE_TIME_LATENCY_PENALTY_MS_KEY`. If `computeContention` did the same — "add latency ∝ current load" — congestion would be charged **twice**:

1. once as **queue wait**, already produced by finite `c`, and
2. again as the **added contention penalty**.

The node would look far more saturated than physics, and the utilization/latency integrals would be untrustworthy. Avoiding the double-count means you cannot *add on top of* the queue — you must change **what `c` means and how service time is computed inside the queue**. That is a core `GGcKNode` change, not a hook. This is the structural reason `computeContention` was always the one deferred trait while windowing/fanoutQuery/autoscaler shipped.

---

## 4. The two-tier model

Split each io-bound node's concurrency into two tiers that already exist physically:

- **Tier 1 — I/O multiplexing (unbounded-ish):** the `c = vCPU × 32 × instances` worker pool stays. It models concurrent *waiting*. Unchanged.
- **Tier 2 — physical-core ceiling on CPU work:** the CPU-bound fraction of in-flight service contends for `physicalCores = totalVcpu` cores.

Each request's authored service time `S` splits:

```
S_cpu = S × cpuBoundFraction        // contends for cores (Tier 2)
S_io  = S × (1 − cpuBoundFraction)  // multiplexes freely (Tier 1)
```

The I/O part runs at full speed. The CPU part's *effective* rate is slowed by how many other requests are computing at dequeue time:

```
cpuSlowdown = max(1, activeCpuBoundWork / physicalCores)
S_effective = S_io + S_cpu × cpuSlowdown
```

When ≤ `physicalCores` requests are computing, `cpuSlowdown = 1` and behaviour is **identical to today** (zero regression for lightly-loaded nodes and for all cpu-bound nodes where the queue already caps at `c = vCPU`). Only io-bound nodes *under heavy simultaneous CPU load* diverge — precisely the regime that is currently overstated. Service time becomes load-coupled (evaluated at dequeue), so it is no longer drawn independently — this is the core semantic change and the source of every ripple below.

For `cpu-bound` nodes this collapses to the current model exactly: `c = vCPU`, so `activeCpuBoundWork ≤ physicalCores` always holds and `cpuSlowdown ≡ 1`.

---

## 5. Utilization: one headline number

Today utilization = `busyArea ÷ capacityArea` where capacity = `maxWorkers` (the integral shipped with dynamic capacity). With two tiers, worker utilization (of 128) and CPU utilization (of 4) **diverge hard**, and reporting both and letting the caller choose *is* the ambiguity that fails doctrine.

**Decision: the headline utilization is CPU utilization** — `∫ min(activeCpuBoundWork, physicalCores) dt ÷ ∫ physicalCores dt` — because that is the number that tells the truth about whether the node has headroom. Worker-pool occupancy may still be surfaced as a clearly-labelled *secondary* diagnostic (I/O multiplexing depth), never as "utilization". One word, one meaning.

This is the reason the model is worth shipping: the current headline utilization can read 60% while the CPU is pinned. After this change it reads the truth.

---

## 6. Autoscaler interaction

The [autoscaler](../../src/engine/traits/autoscaler.ts) I just shipped is a control loop on `nodeState.utilization`. If utilization changes meaning, its behaviour changes — this is specced here, not discovered later:

- The autoscaler reads `nodeState.utilization`, which becomes **CPU utilization**. This is *more correct*: an io-bound node pinned on CPU will now (rightly) scale out, where before it saw false headroom and never scaled.
- `autoscaleTargetUtilization` semantics shift from "worker-pool occupancy" to "CPU occupancy". Existing target values (default 0.7) remain sensible under the new meaning, but the doc/`why` copy must say CPU.
- `applyNodeScale` recomputes derived `c`/`K` on resize; `physicalCores = totalVcpu × instanceCount` must be recomputed on the same path so Tier 2 tracks scale-out. Adding an instance adds cores → raises the Tier-2 ceiling → relieves `cpuSlowdown`. This is the correct feedback loop and must be covered by the autoscaler integral-honesty test.

No change to the autoscaler's own code is anticipated *if* it keeps reading `nodeState.utilization` and that field is redefined at the source. Confirm this during implementation rather than adding a second utilization field for it to read.

---

## 7. Determinism & the integral

Non-negotiable invariants (see [simulation-determinism-and-numerics.md](./simulation-determinism-and-numerics.md)):

- **Deterministic:** `cpuSlowdown` is a pure function of integer `activeCpuBoundWork` and `physicalCores` at dequeue — no new RNG draw. Same seed ⇒ same result.
- **Integral, not point-sample:** CPU utilization is a time-weighted integral accrued in `accrueBusy` alongside the existing `busyArea`/`capacityArea`, using the same piecewise accrual the dynamic-capacity work established. No snapshot averaging (the utilization=80% lie must not return).
- **Load-coupled service time** means service completion times shift as concurrency changes. Recompute the remaining CPU work when `activeCpuBoundWork` crosses `physicalCores`, or accept a documented dequeue-time approximation (fix `S_effective` at dequeue). The approximation is simpler and deterministic; the exact model is a rescheduling problem. **Recommend dequeue-time fix, documented in `honesty.notModeled`.**

---

## 8. Migration gate

**This is a gate, not a footnote.** Every saved question with an io-bound node will shift numbers. Before touching the queue, we must be able to state the before/after:

- **Lightly-loaded io-bound nodes:** no change (`cpuSlowdown = 1`).
- **All cpu-bound nodes:** no change (already core-bound via `c = vCPU`).
- **Heavily-loaded io-bound nodes (the target case):** headline utilization *rises*, effective throughput *falls*, tail latency *grows*. Some questions that currently "pass" on false headroom may now correctly require more instances/budget.

Action before implementation: run the existing question bank through a before/after harness and enumerate every scenario whose verdict flips. Each flip must be explainable as "this was passing on a capacity overstatement." If any flip is *not* explainable that way, the model is wrong. A scenario that flips inexplicably blocks the merge.

---

## 9. Schema changes

- **`cpuBoundFraction` added to `ResourceTypeDefault`** in [`resourceDefaults.ts`](../../src/engine/catalog/resourceDefaults.ts), sourced per component type, author-locked or locked-band (option B, §1). Never a free node-config dial. Group 1 types (proxies/caches/queues/blob) ≈ 0.05–0.1; Group 2 stores (`vector-db`, `columnar-db`, `data-warehouse`, `relational-db`, `time-series-db`, `graph-db`, `search-index`) carry a substantially higher sourced fraction. `FALLBACK_RESOURCE_DEFAULT` needs a conservative value too.
- `GGcKNode` gains internal state: `activeCpuBoundWork` (integer, incremented/decremented as requests enter/leave CPU-tier service) and a `cpuBusyAreaUs`/`coreAreaUs` integral pair mirroring the existing capacity integral.
- `honesty` block: `simulates: ['physical-core contention on the CPU-bound fraction of io-bound service time']`, `notModeled: ['exact rescheduling on concurrency change (service time fixed at dequeue)', 'NUMA / cache effects', 'hyperthreading beyond the vCPU count']`.

---

## 10. Phasing

1. **§1 derivation review (no code).** Defend option (A). If it fails, defend (B). If both fail, stop — file the deferral with reasons. **This spec does not authorize code past this step.**
2. **Migration harness (no queue code).** Before/after the question bank; enumerate flips. Confirm all flips are overstatement-corrections.
3. **`GGcKNode` two-tier service time** + `activeCpuBoundWork` + CPU integral. Behind a flag or guarded so cpu-bound and lightly-loaded io-bound nodes are provably identical (regression tests assert bit-identical metrics).
4. **Redefine `nodeState.utilization` = CPU utilization**; add labelled secondary worker-depth diagnostic. Update autoscaler `why`/doc copy.
5. **Autoscaler integral-honesty test** extended for the recomputed `physicalCores`-on-resize feedback loop.
6. Update [node-capability-matrix.md](./node-capability-matrix.md): move `computeContention` from 🔧 deferred to shipped; update the honesty ledger.

---

## 11. Open questions

- **§1 is resolved** (option B, per-type `cpuBoundFraction`). Remaining sub-question: the exact sourced fraction per Group 2 type — `vector-db` and `data-warehouse`/`columnar-db` are the highest (near cpu-bound in practice); does the question bank contain a node where even the Group 2 default under-states real per-query CPU (e.g. a `relational-db` running a pathological join)? Locked-band with a documented ceiling handles this without reopening the free-dial hole.
- Exact rescheduling vs dequeue-time fix (§7) — is the approximation defensible for the question bank's load regimes, or does a scenario exist where it materially misreports?
- Does any existing consumer read `nodeState.utilization` expecting worker-pool occupancy (beyond the autoscaler)? Audit before redefining the field.

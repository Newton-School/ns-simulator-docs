# Execution Profiles & Node Concurrency (cpu-bound vs io-bound)

> **Scope.** The canonical explainer for a node's **execution profile**
> (`workloadKind: cpu-bound | io-bound`) and why it - not a free-typed number -
> decides how many concurrent workers a node's hardware yields. This is the
> reference answer to *"why does my database show 128 workers / connections when a
> service shows only 2?"*
>
> **Source of truth.** `workloadKind` in `src/engine/core/types.ts`
> (`ResourceConfig`); `CPU_WORKERS_PER_VCPU` / `IO_WORKERS_PER_VCPU` and
> `deriveNodeConcurrency` in `src/engine/nodes/resourceDerivation.ts`; per-type
> defaults in `src/engine/catalog/resourceDefaults.ts`; the `canEditExecutionProfile`
> capability in `src/engine/analysis/environmentProfile.ts`.
>
> **Companion specs.** The full sizing/cost model is
> `resource-allocation-and-derived-concurrency.md` (this doc is the focused
> concurrency-per-profile slice of it); authoring guidance is
> `evaluation-authoring-reference-manual.md` §9.

---

## 1. The question this answers

On the canvas, with the **Concurrency** lens active, a fresh palette drop shows
wildly different worker counts:

| Node | Instance | Reads |
|------|----------|-------|
| API Server (`microservice`) | `c5.large` (2 vCPU) | **2 workers** |
| Job Worker (`batch-worker`) | `c5.large` (2 vCPU) | **2 workers** |
| Primary DB (`relational-db`) | `m5.xlarge` (4 vCPU) | **128 connections** |
| Redis Cache (`in-memory-cache`) | `r5.large` (2 vCPU) | **64 ops** |
| Load Balancer | `m5.large` (2 vCPU) | **64 connections** |
| Message Queue | - | **64 consumers** |

**This is by design, not a bug.** The counts follow directly from each node's
execution profile.

## 2. Design principle - the execution profile is *per-tier*, not universally cpu-bound

A node is **not** cpu-bound by default. Every component type carries a default
**execution profile** that reflects what that component actually does with a CPU
core:

```
effectiveC (parallel servers) = vCPU × instanceCount × workersPerVcpu

  workersPerVcpu = 1    when workloadKind = "cpu-bound"   // CPU_WORKERS_PER_VCPU
  workersPerVcpu = 32   when workloadKind = "io-bound"    // IO_WORKERS_PER_VCPU
```

| Profile | Rule | Reasoning |
|---------|------|-----------|
| **cpu-bound** | **1 worker / vCPU** | A compute service *occupies* the core computing. Real parallelism ≈ number of cores - claiming 1000 workers on 4 vCPU just time-slices 4 cores across 1000 half-done requests (contention), it doesn't add throughput. |
| **io-bound** | **32 / vCPU** | A datastore, cache, load balancer, broker, or queue spends almost all its time *waiting* on disk / network, not using the CPU. One core legitimately juggles many concurrent in-flight requests. |

Real-world anchors for the io-bound multiplier: a Postgres box serves **hundreds of
connections per core**; Redis, a message broker, and a load balancer are the same -
they're bound by I/O and connection handling, not computation. The `32` is a fixed,
tier-wide constant (`IO_WORKERS_PER_VCPU`), generous but firmly tethered to the paid
hardware - never infinite.

## 3. Per-type default profiles

| Tier | Default `workloadKind` | Types |
|------|------------------------|-------|
| **Compute processors** | **cpu-bound** | `microservice`, `batch-worker`, `auth-service`, `search-service`, `sidecar`, `container`, `vm-instance`, `edge-compute`, `gpu-node` |
| **Sources / network / messaging / stores** | **io-bound** | `api-endpoint`, `serverless-function`, `load-balancer` (+ `-l4`/`-l7`), `api-gateway`, `ingress-controller`, `reverse-proxy`, `service-mesh`, `nat-gateway`, `vpn-gateway`, `queue`, `task-queue`, `message-broker`, `pub-sub`, `event-bus`, `stream`, `in-memory-cache`, `kv-store`, `nosql-db`, `relational-db`, `time-series-db`, `columnar-db`, `graph-db`, `vector-db`, `search-index`, `cdn`, `object-storage`, `block-storage`, `distributed-file-system`, `data-lake`, `archive-storage`, `data-warehouse`, `event-sourcing-store` |

Unknown / unmapped types fall back to **io-bound**. (Source: `RESOURCE_DEFAULTS` +
`FALLBACK_RESOURCE_DEFAULT` in `resourceDefaults.ts`.)

## 4. Worked numbers (the table in §1, derived)

- API Server - `c5.large` (2 vCPU) × 1 × **cpu-bound (1)** = **2**
- Primary DB - `m5.xlarge` (4 vCPU) × 1 × **io-bound (32)** = **128**
- Redis Cache - `r5.large` (2 vCPU) × 1 × **io-bound (32)** = **64**
- Load Balancer - `m5.large` (2 vCPU) × 1 × **io-bound (32)** = **64**

So a store reading "128 connections" or a broker reading "64 consumers" is exactly
`vCPU × 32` - correct, not inflated.

## 5. One number, many labels

The canvas shows the same underlying `effectiveC` under **per-type vocabulary**:

| Label | Shown on |
|-------|----------|
| **workers** | services, workers, stores |
| **connections** | databases, load balancers |
| **consumers** | brokers, queues |
| **ops** | caches |

They are all the one derived quantity `c = vCPU × instanceCount × workersPerVcpu`.
The label is cosmetic; the physics is identical.

## 6. The bottleneck lever - flip a store to `cpu-bound`

Because io-bound stores get 32×/vCPU, a default datastore has *lots* of headroom and
rarely saturates at the suites' ~2-3k RPS. When a question needs a store to be the
**deliberate bottleneck** (e.g. "reads collapse the DB without a cache"), the author
flips that node's execution profile to **cpu-bound on a small instance**:

- `cache-placement` reference DB - `t3.small` (2 vCPU) **cpu-bound** = **2 servers**.
  At the read-heavy load it saturates, p99 collapses, and the cache becomes
  mandatory. That is the entire lesson, and it is created by the execution profile,
  not by hand-typing a worker count.

This is a per-node modelling choice, never a global default - the compute tier is
cpu-bound, the store tier is io-bound, and an author opts a specific store into
cpu-bound only to make it bite.

## 7. Authoring & platform controls

- **Per node (topology / `question.json`):** set `resources.workloadKind` on the
  node (`"cpu-bound"` | `"io-bound"`). Absent → the per-type default (§3).
- **Editing policy (environment profile):** whether a *student* can change a node's
  execution profile is gated by the **`canEditExecutionProfile`** capability
  (`environmentProfile.capabilities`). It is `true` in AUTHOR, `false` in ASSIGNMENT
  and PRACTICE by default - so a graded student cannot dodge a cpu-bound bottleneck
  by flipping it to io-bound. A `cost`-domain question unlocks resource editing
  (which includes the profile) when allocation *is* the lesson.
- The profile is surfaced read-only in the node's RESOURCES note as part of the
  derived-concurrency provenance.

## 8. What the execution profile does *not* change

- **Service time.** How long one request takes is the node's own
  `processing.distribution`, adjusted by the instance's `perfFactor` (io-bound work
  is damped - a faster core barely helps a request blocked on I/O). Concurrency
  (`c`) and service time are orthogonal knobs.
- **Admission ceiling (`K`).** `effectiveK = max(effectiveC, memCeiling)` where
  `memCeiling = totalRAM ÷ perRequestMemMb`. RAM, not the execution profile, sets how
  many requests can be *held* (in service + waiting) before rejection/OOM.
- **Cost.** Priced off the instance (`pricePerHour × instanceCount × pricingModel`),
  independent of profile.

See `resource-allocation-and-derived-concurrency.md` for the full derivation, caps
(quota / cost / per-node), and cost model.

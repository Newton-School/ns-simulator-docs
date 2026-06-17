# Throughput Calculation

Technical feature specification defining how throughput is measured, computed, and reported across the simulation: per-node throughput, global throughput, the warmup-aware measurement window, and the relationship between arrival rate, service capacity, and effective throughput.

This spec consolidates the `MetricsCollector` throughput accounting, the `SimulationSummary.throughput` global metric, the `PerNodeMetrics.throughput` per-node metric, and the Little's Law verification that validates throughput consistency. It exists because throughput is the primary capacity planning metric — "how many requests per second can this system handle?" — and every other spec depends on understanding exactly how the simulator measures it: what counts as "processed," which time window is used, how warmup affects the denominator, and why the measured throughput may differ from the configured arrival rate.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Global Throughput Measurement](#feature-1-global-throughput-measurement)
4. [Feature 2: Per-Node Throughput Measurement](#feature-2-per-node-throughput-measurement)
5. [Feature 3: Theoretical Throughput and Capacity Relationship](#feature-3-theoretical-throughput-and-capacity-relationship)
6. [Feature 4: Little's Law Verification](#feature-4-littles-law-verification)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Throughput Calculation measures the rate at which the simulation processes requests, both globally (across the entire topology) and per-node. It distinguishes between arrival rate (how fast requests enter) and throughput (how fast requests complete), accounts for the warmup period that contaminates early metrics, and validates consistency via Little's Law. The output is a requests-per-second number that represents steady-state capacity under the configured workload.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Throughput is the headline metric shown in simulation results |
| Architectural change      |       No | Measurement infrastructure exists; this spec formalizes it |
| Domain model addition     |       No | All types exist (`SimulationSummary`, `PerNodeMetrics`, `LittlesLawResult`) |
| Validation layer          |      Yes | Little's Law check and conservation check are validation of throughput consistency |
| Refactor of existing code |       No | Existing implementation is sound |

### Current pain without this model

| Pain | Who is affected | Technical cause | Consequence |
| ---- | --------------- | --------------- | ----------- |
| Throughput definition is implicit | Users | No documentation explains that global throughput = post-warmup successes / post-warmup duration | Users may misinterpret throughput as "total requests / total duration" |
| Fan-out inflates request counts | Users | Async fan-out creates branch requests, each counted independently | A topology with 1 source and 3 async targets can show 3x the arrival throughput at downstream nodes |
| No per-edge throughput | Users | Metrics are node-only | Cannot determine which edges are bottlenecks |
| No capacity headroom metric | Users | Throughput is measured but not compared to theoretical maximum | Users see "100 req/s throughput" but don't know if the node can handle 200 or is at capacity |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Global throughput formula | Yes | `SimulationSummary.throughput` |
| Per-node throughput formula | Yes | `PerNodeMetrics.throughput` |
| Warmup-aware measurement window | Yes | How warmup affects the denominator and numerator |
| Little's Law verification | Yes | `calculateLittlesLaw` validates throughput consistency |
| Conservation check | Yes | `buildConservationCheck` validates request accounting |
| Theoretical capacity calculation | Yes | Proposed: max throughput based on workers × service time |
| Arrival rate (λ) calculation | Yes | Input to Little's Law and capacity analysis |
| Queue depth effects on throughput | No | Belongs to Queue Depth Calculation |
| Rejection effects on throughput | No | Belongs to Request Rejection Behaviour |
| Cost per request calculation | No | Belongs to Cost Calculation & Budgeting |

---

## Problem Context

### What exists today

**Global throughput (`src/engine/metrics.ts:286-309`)**

```typescript
generateSummary(duration: number): SimulationSummary {
  const effectiveDurationMs = Math.max(0, duration - this.warmupDurationMs)
  const throughput =
    effectiveDurationMs > 0 ? this.postWarmupSuccessfulRequests / (effectiveDurationMs / 1000) : 0
  // ...
}
```

Global throughput = `postWarmupSuccessfulRequests / effectiveDurationSeconds`.

- **Numerator**: Only requests with `status === 'success'` AND `createdAt >= warmupDurationUs`. Rejected and timed-out requests are excluded.
- **Denominator**: `simulationDuration - warmupDuration`, converted to seconds. The warmup period is excluded.

**Per-node throughput (`src/engine/metrics.ts:383`)**

```typescript
throughput: durationSec > 0 ? pwProcessed / durationSec : 0
```

Per-node throughput = `postWarmupProcessed / effectiveDurationSeconds`.

- **Numerator**: `postWarmupProcessed` — the count of completed processing spans where `span.arrivalTime >= warmupDurationUs`. This gates on when the request arrived at this specific node, not when it was created globally.
- **Denominator**: Same as global.

**Key difference**: Global throughput counts successful requests (end-to-end). Per-node throughput counts processed spans (per-hop). A request that passes through 3 nodes contributes 1 to global throughput but 1 to each of the 3 nodes' throughputs.

**Little's Law verification (`src/engine/analysis/output.ts:223-250`)**

```typescript
function calculateLittlesLaw(perNode, config): LittlesLawResult[] {
  const durationSec = Math.max(0.001, (config.simulationDuration - config.warmupDuration) / 1000)

  return Object.entries(perNode).map(([nodeId, metrics]) => {
    const lambda = metrics.postWarmupArrived / durationSec
    const wSeconds = metrics.postWarmupAvgTimeInSystem / 1000
    const expectedL = lambda * wSeconds
    const observedL = metrics.postWarmupAvgInSystem
    const absoluteError = Math.abs(observedL - expectedL)
    const error = absoluteError / Math.max(expectedL, 0.001)
    return {
      nodeId, observedL, expectedL, error,
      withinTolerance: error <= 0.1 || absoluteError <= 0.5,
      lambda, wSeconds
    }
  })
}
```

Little's Law: `L = λW` where:
- `L` = time-average number of items in the system (post-warmup snapshots)
- `λ` = arrival rate (post-warmup arrivals / effective duration)
- `W` = mean sojourn time (post-warmup queue wait + service time)

The dual tolerance guard: `error <= 0.1 || absoluteError <= 0.5` — either 10% relative tolerance OR 0.5 absolute tolerance. The absolute guard handles low-traffic nodes where tiny count differences produce large percentage errors.

**Conservation check (`src/engine/analysis/output.ts:308-326`)**

```
postWarmupArrived = postWarmupProcessed + postWarmupRejected + postWarmupTimedOut + inFlight
```

Every request that arrives must either be processed, rejected, timed out, or still in flight. A node is `balanced` if `inFlight / postWarmupArrived < 5%`.

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| No theoretical maximum throughput | Cannot compute capacity headroom | Requires: `maxThroughput = workers / avgServiceTime` |
| No per-edge throughput | Cannot identify edge bottlenecks | No edge-level counters in `MetricsCollector` |
| No throughput over time (time series) | Cannot see throughput trends | `TimeSeriesSnapshot` captures queue and utilization but not throughput |
| Fan-out double-counting not documented | Users may misinterpret inflated node throughput | Branch requests are counted independently |

---

## Feature 1: Global Throughput Measurement

### What it does

Computes the system-level throughput: how many requests per second successfully traverse the entire topology from source to completion, measured over the post-warmup window.

### Why it exists

Global throughput is the answer to "how fast is my system?" It is the number users see in the simulation summary and compare against their SLA targets. It must be precise about what it measures (successes only, post-warmup only) to be useful for capacity planning.

### How it works internally

**Formula**:

```
globalThroughput = postWarmupSuccessfulRequests / ((simulationDuration - warmupDuration) / 1000)
```

**Data flow**:

```
WorkloadGenerator creates request with createdAt
    │
    ▼
Request traverses topology (nodes + edges)
    │
    ▼
handleRequestComplete fires
    │
    ▼
MetricsCollector.recordRequest({status: 'success', ...})
    │
    ├─ totalRequests++
    ├─ successfulRequests++
    ├─ if createdAt >= warmupDurationUs:
    │   ├─ postWarmupTotalRequests++
    │   ├─ postWarmupSuccessfulRequests++
    │   └─ successfulLatencies.push(totalLatency)
    │
    ▼
generateSummary(simulationDuration):
    throughput = postWarmupSuccessfulRequests / effectiveDurationSec
```

**What counts as "successful"**:

A request is successful if and only if `handleRequestComplete` fires — meaning the request reached a node with no outgoing routes (a sink or terminal node) and the engine emitted a `request-complete` event. Requests that are rejected, timed out, or still in flight at simulation end are not counted.

**What "post-warmup" means**:

The warmup filter uses `request.createdAt >= warmupDurationUs`. A request created at 4999ms in a 5000ms warmup is excluded from post-warmup throughput, even if it completes well after warmup ends. This is deliberate: requests created during warmup carry transient-state characteristics (empty queues, no contention) that would inflate throughput.

**Warmup impact on throughput accuracy**:

| Scenario | Warmup | Duration | Effective window | Effect |
| --- | --- | --- | --- | --- |
| No warmup | 0 ms | 60s | 60s | Transient ramp-up inflates throughput (queues start empty → no wait time) |
| Short warmup | 1s | 60s | 59s | Some transient contamination |
| Adequate warmup | 5s | 60s | 55s | Steady-state throughput; accurate for capacity planning |
| Excessive warmup | 30s | 60s | 30s | Accurate but short measurement window → higher variance |

**Error rate complement**:

```
globalErrorRate = postWarmupFailed / postWarmupTotal
```

Where `postWarmupFailed = postWarmupTotal - postWarmupSuccessful`. This means:

```
successRate = 1 - errorRate
effectiveThroughput = arrivalRate × successRate
```

If `baseRps = 100` and `errorRate = 0.05`, effective throughput ≈ 95 req/s.

### What components it requires

- **Engine-side**: Fully implemented in `MetricsCollector.generateSummary()`. No changes needed.
- **Shared layer**: `SimulationSummary.throughput` is already shared.
- **Renderer/frontend-side**: Throughput is displayed in the simulation results summary panel.

### Explored in

`src/engine/metrics.ts:286-309` (summary generation), `src/engine/metrics.ts:144-201` (request recording).

---

## Feature 2: Per-Node Throughput Measurement

### What it does

Computes throughput at each individual node: how many requests per second that node successfully processes, measured over the post-warmup window.

### Why it exists

Global throughput masks node-level bottlenecks. If the system handles 100 req/s but a database node only processes 20 req/s (with the rest rejected or timed out), the node-level metric reveals the bottleneck that the global metric hides. Per-node throughput is essential for identifying which component to scale, optimize, or replace.

### How it works internally

**Formula**:

```
nodeThoughput[nodeId] = postWarmupProcessed[nodeId] / effectiveDurationSec
```

**What "processed" means at the node level**:

A request is "processed" at a node when `GGcKNode.handleCompletion` fires and produces a `RequestSpan`. The span records the node ID, arrival time, queue wait, and service time. This span is the evidence that the request was admitted to the queue, waited, was served, and completed at this node.

**Post-warmup gating**:

Per-node metrics use `span.arrivalTime >= warmupDurationUs` (not `request.createdAt`). This is documented in `metrics.ts:169-173`:

```typescript
// Per-node post-warmup gate uses span.arrivalTime — the moment this request
// actually reached this node in simulation time. Using request.createdAt
// instead would miscount: a request created just before warmup ends but
// processed entirely post-warmup would be excluded, inflating L relative to λW.
```

This is a deliberate design decision for Little's Law consistency: λ, W, and L must all use the same time window. Since L (items in system) is measured at the node level, λ and W must also be measured at the node level using arrival time, not creation time.

**Per-node throughput vs arrival rate**:

| Metric | Formula | Measures |
| --- | --- | --- |
| Arrival rate (λ) | `postWarmupArrived / effectiveDurationSec` | How fast requests enter the node |
| Throughput | `postWarmupProcessed / effectiveDurationSec` | How fast requests exit the node (success only) |
| Rejection rate | `postWarmupRejected / effectiveDurationSec` | How fast requests are turned away |
| Timeout rate | `postWarmupTimedOut / effectiveDurationSec` | How fast requests expire |

In steady state: `arrivalRate ≈ throughput + rejectionRate + timeoutRate + inFlightRate`.

**Utilization**:

```
utilization = avgUtilizationFromSnapshots
```

Where each snapshot records `state.utilization` from `GGcKNode.getState()`. Utilization is `activeWorkers / totalWorkers`. The time-series snapshots are taken every 1 second of simulation time (`snapshotIntervalUs = secToMicro(1)` in `engine.ts:45`).

**Throughput ≤ capacity**:

For a G/G/c queue (c workers, mean service time S):
```
theoreticalMaxThroughput = c / S
```

If `workers = 4` and `avgServiceTimeMs = 10`, then `maxThroughput = 4 / 0.01 = 400 req/s`.

Measured throughput should never exceed this. If it does, it indicates a measurement error (typically caused by warmup contamination or incorrect service time accounting).

### What components it requires

- **Engine-side**: Fully implemented. For theoretical max throughput, add `maxThroughput: workers / avgServiceTime` to `PerNodeMetrics` (~5 lines).
- **Shared layer**: `PerNodeMetrics` is already shared.
- **Renderer/frontend-side**: Per-node throughput is displayed in the node metrics panel.

### Explored in

`src/engine/metrics.ts:311-395` (per-node metrics generation), `src/engine/metrics.ts:265-284` (snapshot recording).

---

## Feature 3: Theoretical Throughput and Capacity Relationship

### What it does

Defines the relationship between a node's configuration (workers, service time distribution, queue capacity) and its theoretical maximum throughput. This is the bridge between "what I configured" and "what I should expect."

### Why it exists

Users configure `workers: 4` and `processing.distribution: { type: 'constant', value: 10 }` (10ms service time) and expect to understand what throughput that produces. The theoretical maximum is `4 / 0.01 = 400 req/s`. Without this calculation, users must run a simulation to discover capacity — and even then, they lack context for whether the measured throughput is near capacity or far below it.

### How it works internally

**G/G/c/K queue capacity model**:

Each node in the simulator is a G/G/c/K queue where:
- **G** = general arrival distribution (any pattern from the workload generator)
- **G** = general service distribution (any of the 14 supported distributions)
- **c** = number of workers (`QueueConfig.workers`)
- **K** = total system capacity (`QueueConfig.capacity`)

**Theoretical maximum throughput**:

```
μ = 1 / E[S]           // service rate per worker (1 / mean service time in seconds)
maxThroughput = c × μ   // total service rate across all workers
```

For `constant` distribution: `E[S] = value` (exact).
For `log-normal(mu, sigma)`: `E[S] = exp(mu + sigma²/2)`.
For `exponential(lambda)`: `E[S] = 1/lambda`.
For `normal(mean, stdDev)`: `E[S] = mean`.

**Stability condition**:

```
ρ = λ / (c × μ) < 1    // traffic intensity must be < 1 for stability
```

Where `λ` = arrival rate. If `ρ ≥ 1`, the queue grows without bound (in an infinite-capacity system) or rejection rate approaches 100% (in a finite-capacity system). The simulator handles the finite case: `K = queue.capacity` limits how many requests can be in the system.

**Capacity headroom** (proposed metric):

```
headroom = (maxThroughput - measuredThroughput) / maxThroughput
```

A headroom of 0.3 means the node is using 70% of its theoretical capacity. A headroom near 0 means the node is near saturation.

**How capacity is limited**:

| Limiting factor | How it affects throughput | Configuration |
| --- | --- | --- |
| Workers | Determines parallel processing capacity | `QueueConfig.workers` |
| Service time | Determines per-request processing cost | `ProcessingConfig.distribution` |
| Queue capacity | Limits admission; excess arrivals are rejected | `QueueConfig.capacity` |
| Arrival rate | If λ > maxThroughput, system saturates | `WorkloadProfile.baseRps` |
| Timeout | Requests may timeout before processing completes | `ProcessingConfig.timeout`, `GlobalConfig.defaultTimeout` |

### What components it requires

- **Engine-side**: Compute `maxThroughput` per node from config. For constant distributions, exact calculation. For stochastic distributions, use the mean formula. ~20 lines in `getPerNodeMetrics`.
- **Shared layer**: Add `maxThroughput` and `headroom` fields to `PerNodeMetrics`.
- **Renderer/frontend-side**: Display capacity headroom in node metrics panel.

### Explored in

`src/engine/core/types.ts:220-231` (QueueConfig, ProcessingConfig), `src/engine/nodes/GGcKNode.ts` (queue model), `src/engine/stochastic/distribution.ts` (distribution sampling).

---

## Feature 4: Little's Law Verification

### What it does

Validates that the simulation's throughput measurements are internally consistent by checking Little's Law (`L = λW`) at every node. This is the simulator's self-consistency test: if the law does not hold, something is wrong with the measurement window, the warmup period, or the simulation mechanics.

### Why it exists

Little's Law is a fundamental result in queuing theory that holds for any queue in steady state, regardless of arrival or service distributions. If the simulator's measurements violate it, the simulation results are unreliable. The verification serves as a quality gate on every simulation run.

### How it works internally

**Little's Law**: For any queue in steady state:
```
L = λ × W
```

Where:
- `L` = time-average number of items in the system
- `λ` = arrival rate (items per unit time)
- `W` = mean time an item spends in the system

**Measurement** (all post-warmup only):

| Quantity | How measured | Source |
| --- | --- | --- |
| `L` (observedL) | Time-average of `totalInSystem` from periodic snapshots | `postWarmupAvgInSystem` from `recordNodeSnapshot` |
| `λ` (lambda) | `postWarmupArrived / effectiveDurationSec` | Post-warmup arrival count / measurement window |
| `W` (wSeconds) | `postWarmupAvgTimeInSystem / 1000` | Mean (queueWait + serviceTime) for post-warmup spans |
| `expectedL` | `lambda × wSeconds` | Predicted L from Little's Law |

**Tolerance check**:

```typescript
withinTolerance: error <= 0.1 || absoluteError <= 0.5
```

**Dual guard**:
- **10% relative**: For high-traffic nodes, L = 50 and expectedL = 48 → error = 4.2% → passes.
- **0.5 absolute**: For low-traffic nodes, L = 0.3 and expectedL = 0.1 → error = 200% but absoluteError = 0.2 → passes.

The absolute guard prevents false alarms at low-traffic nodes where integer count quantization produces large percentage errors.

**When Little's Law fails**:

| Violation cause | Symptom | Fix |
| --- | --- | --- |
| Warmup too short | `L > expectedL` (transient ramp-up inflates L) | Increase warmup duration |
| Simulation too short | High `inFlight` count (requests didn't finish) | Increase simulation duration |
| Fan-out counting | λ includes branched arrivals, W doesn't account for branch divergence | Expected; not a bug |
| Measurement window mismatch | λ and W use different time domains | Should not happen (both use post-warmup node-level gating) |

**Warmup adequacy assessment (`output.ts:256-299`)**:

```
recommendedWarmupMs = 10 × max(p99 latency across all nodes)
adequate = warmupMs >= recommendedWarmupMs
```

This heuristic ensures the warmup is long enough for the slowest node to reach steady state. A node with p99 = 100ms needs at least 1000ms warmup for its queue to stabilize.

**Conservation check (`output.ts:308-326`)**:

```
inFlight = postWarmupArrived - postWarmupProcessed - postWarmupRejected - postWarmupTimedOut
balanced = postWarmupArrived == 0 || inFlight / postWarmupArrived < 5%
```

A balanced node has accounted for all arrivals. High `inFlight` means requests were still in queue when the simulation ended — either the simulation was too short or the node was severely overloaded.

### What components it requires

- **Engine-side**: Fully implemented. No changes needed.
- **Shared layer**: `LittlesLawResult`, `WarmupAdequacy`, `ConservationResult` are already shared.
- **Renderer/frontend-side**: Little's Law results are available in `SimulationOutput.littlesLawCheck` for display.

### Explored in

`src/engine/analysis/output.ts:223-250` (Little's Law), `src/engine/analysis/output.ts:256-299` (warmup adequacy), `src/engine/analysis/output.ts:308-326` (conservation check).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Environment Definition & Configuration Model** | Throughput as a derived metric from environment config | Node capacity config (workers, service time) | `QueueConfig`, `ProcessingConfig` |
| **Request Pattern Configuration** | Arrival rate λ from pattern config → throughput comparison | `baseRps` and pattern shape | `WorkloadProfile.baseRps` → λ |
| **Request Type Model** | Per-type throughput (proposed) | Type-level processing weights | `processingWeight` → adjusted service time |
| **Edge Properties & Defaults** | Edge-level throughput (proposed) | — | Per-edge counters |
| **Queue Depth Calculation** | Throughput as input to queue depth formulas | Queue depth as indicator of congestion | `PerNodeMetrics.throughput`, queue length |
| **Arrival, Departure & Request Lifecycle Semantics** | Request completion events that increment throughput counters | Lifecycle state machine | `request-complete` → recordRequest |
| **Request Rejection Behaviour** | Rejection rate complement to throughput | Rejection metrics | `throughput + rejectionRate ≈ arrivalRate` |
| **Cost Calculation & Budgeting** | Throughput × cost per request = total cost | — | `throughput`, cost model |
| **Simulation Validation & Pattern Accuracy** | Little's Law as a validation mechanism | Accuracy thresholds | `LittlesLawResult.withinTolerance` |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| `src/engine/metrics.ts` | Add `maxThroughput` computation to `getPerNodeMetrics` | Expose theoretical capacity | ~15 lines |
| `src/engine/metrics.ts` | Add `headroom` computation: `(max - measured) / max` | Expose capacity headroom | ~3 lines |
| `src/engine/analysis/output.ts` | Add `maxThroughput` and `headroom` to `PerNodeMetrics` type | Update shared type | ~2 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| Global Throughput | `metrics.ts:286-309` | `SimulationSummary` | `generateSummary()` |
| Per-Node Throughput | `metrics.ts:311-395` | `PerNodeMetrics` | `getPerNodeMetrics()` |
| Theoretical Capacity | `types.ts:220-231`, `GGcKNode.ts` | `QueueConfig`, `ProcessingConfig` | Proposed: capacity formula |
| Little's Law | `output.ts:223-250` | `LittlesLawResult` | `calculateLittlesLaw()` |
| Warmup Adequacy | `output.ts:256-299` | `WarmupAdequacy` | `assessWarmupAdequacy()` |
| Conservation | `output.ts:308-326` | `ConservationResult` | `buildConservationCheck()` |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | Global throughput counts only successful requests, not processed requests | Design decision (implemented) | If users expect "throughput = processed," the number will be higher than reported |
| 2 | Post-warmup gating uses `createdAt` for global metrics and `arrivalTime` for per-node metrics | Design decision (implemented) | Mixing the two would break Little's Law consistency |
| 3 | The 10% / 0.5 dual tolerance for Little's Law is appropriate | Observation | Tighter tolerance would flag more nodes; looser would miss real violations |
| 4 | Warmup adequacy heuristic (10× max p99) is sufficient | Heuristic | Some distributions (heavy-tailed) may need longer warmup |
| 5 | Conservation check's 5% in-flight threshold is appropriate | Observation | Lower threshold would flag simulations that are slightly too short |
| 6 | Fan-out branch requests should count as independent arrivals at downstream nodes | Design decision (implemented) | This inflates per-node throughput relative to original request count; alternative would be to track "original request throughput" separately |

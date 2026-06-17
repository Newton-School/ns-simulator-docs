# Queue Depth Calculation

Technical feature specification defining how queue depth is modeled, measured, and reported: the G/G/c/K queue model, admission control, queue disciplines, capacity limits, and the metrics that describe queue behaviour over time.

This spec consolidates the `GGcKNode` class, the `QueueConfig` type, the four queue disciplines (FIFO, LIFO, priority, WFQ), the admission control logic, and the queue-related metrics in `PerNodeMetrics` into a single reference for how queues work in the simulator. It exists because every node in the topology is a queue — the queue is the fundamental unit of simulation — and downstream specs (throughput, rejection, lifecycle) all depend on understanding how requests enter, wait in, and exit queues.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: G/G/c/K Queue Model](#feature-1-ggck-queue-model)
4. [Feature 2: Queue Disciplines](#feature-2-queue-disciplines)
5. [Feature 3: Admission Control](#feature-3-admission-control)
6. [Feature 4: Queue Depth Metrics](#feature-4-queue-depth-metrics)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Queue Depth Calculation models each node as a G/G/c/K queue: general arrival distribution, general service distribution, c parallel workers, and K total system capacity (workers + queue slots). The queue depth at any moment is the number of requests waiting for a worker (not yet processing). The total items in system is queue depth + active workers. Admission control rejects requests when the system is at capacity.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Queue depth is a key metric for capacity planning; disciplines affect processing order |
| Architectural change      |       No | `GGcKNode` is implemented and stable |
| Domain model addition     |       No | All types exist (`QueueConfig`, `GGcKNode`, queue-related metrics) |
| Validation layer          |      Yes | Validator checks capacity ≥ workers |
| Refactor of existing code |       No | Implementation is sound |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Queue model (G/G/c/K) | Yes | `GGcKNode` is the queue implementation |
| Queue disciplines (FIFO, LIFO, priority, WFQ) | Yes | Dequeue algorithm per discipline |
| Admission control (capacity check, failed node check) | Yes | `handleArrival` rejection logic |
| Queue depth metrics (avg, peak, time series) | Yes | Queue-related fields in `PerNodeMetrics` |
| Service time sampling | Partial | This spec covers how the sampled time drives completion; the distribution itself is documented in Request Pattern Configuration (for inter-arrival) and Edge Properties (for the stochastic layer) |
| Rejection lifecycle | No | Belongs to Request Rejection Behaviour |
| Throughput derivation from queue occupancy | No | Belongs to Throughput Calculation |
| Request timeout during queue wait | Partial | This spec covers `cancelRequest`; timeout scheduling belongs to Arrival/Departure Lifecycle |

---

## Problem Context

### What exists today

**GGcKNode class (`src/engine/nodes/GGcKNode.ts`)**

The core queue implementation. Constructed from a `ComponentNode` config with required `queue` and optional `processing` configuration.

**QueueConfig (`src/engine/core/types.ts:220-225`)**

```typescript
export interface QueueConfig {
  workers: number
  capacity: number
  discipline: 'fifo' | 'lifo' | 'priority' | 'wfq'
}
```

**Constructor constraints** (`GGcKNode.ts:47-78`):
- `workers` must be a positive integer (≥ 1)
- `capacity` must be a positive integer (≥ 1)
- `capacity >= workers` (you can't have more workers than capacity)
- `discipline` must be one of the four values

**Default queue config** (applied by engine and validator when missing):
```typescript
{ workers: 1, capacity: 100, discipline: 'fifo' }
```

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| WFQ discipline not differentiated | `wfq` is treated identically to `fifo` | `dequeue()` uses `queue.shift()` for both |
| No queue depth over time in output | Only avg and peak queue length available | `TimeSeriesSnapshot` captures `queueLength` but `PerNodeMetrics` only reports aggregate stats |
| No queue wait distribution | Only `avgQueueWait` reported; no percentiles | `MetricsCollector` sums queue wait but doesn't store per-request samples for percentile calculation |

---

## Feature 1: G/G/c/K Queue Model

### What it does

Models each simulation node as a finite-capacity multi-server queue. Requests arrive (general arrival process), wait in a queue if all workers are busy, are served by one of c workers with a service time drawn from a general distribution, and depart. If the system is at capacity K, new arrivals are rejected.

### Why it exists

The G/G/c/K model is the most general finite-capacity multi-server queue. It makes no assumptions about arrival or service distributions — any of the 14 supported distributions can be used. This generality is essential because real systems have diverse processing characteristics: a CDN might have constant 0.1ms service time, while a database might have log-normal 8ms service time with heavy right-tail variance.

### How it works internally

**State variables** (per `GGcKNode` instance):

| Variable | Type | Initial | Meaning |
| --- | --- | --- | --- |
| `queue` | `Request[]` | `[]` | Waiting requests (not yet processing) |
| `activeWorkers` | `number` | `0` | Currently processing requests (worker slots in use) |
| `status` | `'idle' \| 'busy' \| 'saturated' \| 'failed'` | `'idle'` | Aggregate node state |
| `arrivalTimes` | `Map<string, bigint>` | empty | Per-request arrival timestamp (for queue wait calculation) |
| `startTimes` | `Map<string, bigint>` | empty | Per-request processing start timestamp (for service time calculation) |

**Capacity model**:

```
totalInSystem = activeWorkers + queue.length
maxCapacity = QueueConfig.capacity      // includes both worker slots and queue slots
queueOnly = maxCapacity - maxWorkers    // pure queue slots available

Admission check: totalInSystem >= maxCapacity → REJECT
```

Important: `capacity` is the total system capacity, not just the queue size. A node with `workers: 4, capacity: 10` has 4 worker slots and 6 queue slots. When all 4 workers are busy and 6 requests are queued, the next arrival is rejected.

**Arrival flow** (`handleArrival` in `GGcKNode.ts:80-107`):

```
request arrives
    │
    ├─ node status === 'failed' → REJECT (reason: node_failed)
    │
    ├─ activeWorkers + queue.length >= maxCapacity → REJECT (reason: capacity_exceeded)
    │
    ├─ activeWorkers < maxWorkers → start processing immediately
    │   ├─ activeWorkers++
    │   ├─ sample service time from distribution
    │   ├─ schedule processing-complete event at currentTime + serviceTime
    │   └─ return { status: 'processed' }
    │
    └─ all workers busy → add to queue
        ├─ queue.push(request)
        ├─ update maxQueueLength metric
        └─ return { status: 'queued' }
```

**Completion flow** (`handleCompletion` in `GGcKNode.ts:109-152`):

```
processing-complete event fires
    │
    ├─ activeWorkers-- (free the worker slot)
    │
    ├─ compute RequestSpan: { arrivalTime, queueWait, serviceTime, departureTime }
    │
    ├─ if node is failed → return (no dequeue)
    │
    └─ if queue is non-empty → dequeue next request by discipline
        ├─ start processing the dequeued request
        └─ return { nextRequest, completedSpan }
```

**Service time sampling** (`startProcessing` in `GGcKNode.ts:220-245`):

```typescript
const rawServiceTimeMs = this.distributions.fromConfig(this.serviceDistribution)
const serviceTimeMs = Math.max(0, rawServiceTimeMs)
const serviceTimeMicro = BigInt(Math.round(serviceTimeMs * 1000))

this.scheduler.schedule(
  createEvent('processing-complete', this.id, request.id, { request },
    currentTime + serviceTimeMicro)
)
```

The service time is sampled once when processing starts. It does not change during processing. The sampled value is clamped to minimum 0 and converted to microseconds for the event scheduler.

**Status model** (`updateStatus` in `GGcKNode.ts:272-282`):

| Status | Condition |
| --- | --- |
| `idle` | `activeWorkers === 0` |
| `busy` | `activeWorkers > 0 && (activeWorkers < maxWorkers \|\| queue.length === 0)` |
| `saturated` | `activeWorkers >= maxWorkers && queue.length > 0` |
| `failed` | Set by `fail()`, cleared by `recover()` |

### What components it requires

- **Engine-side**: Fully implemented. No changes needed.
- **Shared layer**: `QueueConfig`, `NodeState` types are shared.
- **Renderer/frontend-side**: Node status visualization uses `NodeState.status` for color coding.

### Explored in

`src/engine/nodes/GGcKNode.ts` (full implementation), `src/engine/core/types.ts:220-225` (QueueConfig).

---

## Feature 2: Queue Disciplines

### What it does

Controls the order in which waiting requests are selected from the queue when a worker becomes available. Four disciplines are supported: FIFO, LIFO, priority, and WFQ (weighted fair queuing).

### Why it exists

Different systems have different scheduling requirements. A web server processes requests in arrival order (FIFO). A stack-based undo system processes the most recent first (LIFO). An alert system processes critical alerts before routine checks (priority). A multi-tenant system allocates fair processing shares across tenants (WFQ). The discipline determines which requests experience the longest queue wait, which affects per-request latency distributions and SLO compliance.

### How it works internally

**Dequeue algorithm** (`dequeue()` in `GGcKNode.ts:247-270`):

| Discipline | Algorithm | Complexity | Fairness |
| --- | --- | --- | --- |
| `fifo` | `queue.shift()` — remove first element | O(n) (array shift) | Fair: requests served in arrival order |
| `lifo` | `queue.pop()` — remove last element | O(1) | Unfair: early arrivals may starve indefinitely |
| `priority` | Linear scan for minimum `request.priority`, then `splice` | O(n) per dequeue | Priority-fair: highest priority served first; same-priority is FIFO-ish (first found) |
| `wfq` | `queue.shift()` — **identical to FIFO** | O(n) | Not implemented: WFQ should weight by some per-request or per-class attribute |

```typescript
private dequeue(): Request | undefined {
  if (this.queue.length === 0) return undefined
  switch (this.discipline) {
    case 'fifo':
    case 'wfq':
      return this.queue.shift()
    case 'lifo':
      return this.queue.pop()
    case 'priority': {
      let bestIdx = 0
      for (let i = 1; i < this.queue.length; i++) {
        if (this.queue[i].priority < this.queue[bestIdx].priority) {
          bestIdx = i
        }
      }
      return this.queue.splice(bestIdx, 1)[0]
    }
  }
}
```

**Priority discipline details**:

- Lower numeric priority = higher precedence (0 > 1 > 2)
- Linear scan finds the first element with the minimum priority value
- If multiple requests share the minimum priority, the first one found (closest to array start = earliest arrival among same-priority) is selected
- `splice(bestIdx, 1)` removes and returns the selected element — O(n)

**WFQ gap**:

WFQ (Weighted Fair Queuing) should allocate processing capacity proportionally across request classes (e.g., 70% to type A, 30% to type B). The current implementation treats it as FIFO. A proper WFQ would need:
1. Per-class virtual time tracking
2. Request classification (likely by `request.type`)
3. Selection of the request with the lowest virtual finish time

This is deferred because it requires integration with the Request Type Model (per-type weights) and adds significant complexity to the dequeue operation.

### What components it requires

- **Engine-side**: WFQ implementation requires per-class virtual time tracking (~50 lines). All other disciplines are implemented.
- **Shared layer**: `QueueConfig.discipline` type is shared.
- **Renderer/frontend-side**: Queue discipline selector in node configuration panel.

### Explored in

`src/engine/nodes/GGcKNode.ts:247-270` (dequeue implementation), `src/engine/core/types.ts:224` (discipline union).

---

## Feature 3: Admission Control

### What it does

Determines whether an arriving request is admitted to the node (queued or immediately processed) or rejected. Two rejection conditions exist: capacity exceeded and node failed.

### Why it exists

Finite capacity is the defining characteristic of the G/G/c/K model (the K). Without admission control, queues would grow without bound under overload, producing unrealistic results. Admission control is the mechanism that triggers rejection behaviour — the most visible consequence of capacity limits.

### How it works internally

**Admission decision** (`handleArrival` in `GGcKNode.ts:80-107`):

```
                    ┌──────────────────┐
                    │  Request arrives  │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Node failed?    │
                    └──┬──────────┬────┘
                   Yes │          │ No
            ┌──────────▼──┐  ┌───▼─────────────┐
            │ REJECT:     │  │ totalInSystem    │
            │ node_failed │  │ >= maxCapacity?  │
            └─────────────┘  └──┬──────────┬────┘
                            Yes │          │ No
                     ┌──────────▼──┐  ┌───▼─────────────┐
                     │ REJECT:     │  │ Worker free?     │
                     │ capacity_   │  │ active < max     │
                     │ exceeded    │  └──┬──────────┬────┘
                     └─────────────┘ Yes │          │ No
                              ┌─────────▼──┐  ┌───▼──────────┐
                              │ Start      │  │ Add to queue  │
                              │ processing │  │ (wait for     │
                              │ immediately│  │  worker)      │
                              └────────────┘  └───────────────┘
```

**Capacity check**:

```typescript
const currentLoad = this.activeWorkers + this.queue.length
if (currentLoad >= this.maxCapacity) {
  this.metrics.totalRejections++
  return { status: 'rejected', reason: 'capacity_exceeded' }
}
```

`currentLoad` is the total items in system: active workers + queued requests. If this equals or exceeds `maxCapacity`, the request is rejected. This means:
- With `workers: 4, capacity: 10`: reject when 10+ items in system
- With `workers: 4, capacity: 4`: reject when 4+ items (no queuing possible; all slots are worker slots)
- With `workers: 1, capacity: 100`: reject when 100+ items (99 queue slots + 1 worker)

**Failed node check**:

```typescript
if (this.status === 'failed') {
  this.metrics.totalRejections++
  return { status: 'rejected', reason: 'node_failed' }
}
```

A failed node rejects all arrivals regardless of capacity. The `fail()` method also clears the queue and resets workers, so a node failure causes immediate loss of all in-flight and queued requests.

**Timeout-based removal** (`cancelRequest` in `GGcKNode.ts:154-186`):

The engine can cancel a request that is queued or processing (via `request-timeout` with `scope: 'node'`). `cancelRequest` searches the queue and the active workers:
- If found in queue: splice out, free the slot
- If found processing: decrement activeWorkers, dequeue next if queue is non-empty
- Returns the arrival time for metric recording, or null if not found

### What components it requires

- **Engine-side**: Fully implemented. For more granular admission (e.g., per-type admission limits, priority-based admission), the admission check would need access to the request type registry.
- **Shared layer**: `ArrivalResult` type is module-local to `GGcKNode.ts`; could be exported if admission decisions need to be inspected by other consumers.
- **Renderer/frontend-side**: Rejection counts appear in per-node metrics.

### Explored in

`src/engine/nodes/GGcKNode.ts:80-107` (admission), `src/engine/nodes/GGcKNode.ts:154-186` (cancellation), `src/engine/nodes/GGcKNode.ts:189-203` (failure/recovery).

---

## Feature 4: Queue Depth Metrics

### What it does

Measures and reports queue depth and related queue metrics: average queue length, peak queue length, average queue wait time, average service time, average time in system, and items in system (for Little's Law).

### Why it exists

Queue depth is the leading indicator of congestion. A rising queue depth signals that arrival rate is approaching or exceeding service capacity. Peak queue depth reveals the worst-case resource consumption. Average queue wait directly contributes to end-to-end latency. These metrics are essential for capacity planning: they tell users whether their queue is appropriately sized and whether workers need to be added.

### How it works internally

**Queue metrics collected**:

| Metric | Source | When sampled | Formula in output |
| --- | --- | --- | --- |
| `avgQueueLength` | `queueLengthSum / queueSamples` | Each snapshot (1/sec) | Time-average of `state.queueLength` |
| `peakQueueLength` | `max(peakQueueLength, state.queueLength)` | Each snapshot + each arrival | Maximum observed queue length |
| `avgQueueWait` | `queueWaitSumMs / totalProcessed` | Each completed span | Mean queue wait for processed requests |
| `avgServiceTime` | `serviceTimeSumMs / totalProcessed` | Each completed span | Mean service time for processed requests |
| `avgTimeInSystem` | `(queueWaitSumMs + serviceTimeSumMs) / totalProcessed` | Each completed span | Mean sojourn time (W) for processed requests |
| `avgInSystem` | `inSystemSum / inSystemSamples` | Each snapshot (1/sec) | Time-average of `activeWorkers + queueLength` (L) |
| `postWarmupAvgInSystem` | Post-warmup snapshots only | Snapshots after warmup | Time-average L for Little's Law |
| `postWarmupAvgTimeInSystem` | Post-warmup spans only | Spans with arrivalTime ≥ warmup | Mean W for Little's Law |

**Snapshot-based sampling** (`MetricsCollector.recordNodeSnapshot` in `metrics.ts:265-284`):

Called from `SimulationEngine.takeSnapshot()` every 1 second of simulation time:

```typescript
recordNodeSnapshot(nodeId: string, state: NodeState, timestamp: bigint): void {
  const node = this.ensureNodeMetrics(nodeId)
  node.queueLengthSum += state.queueLength
  node.queueSamples++
  node.peakQueueLength = Math.max(node.peakQueueLength, state.queueLength)
  node.inSystemSum += state.totalInSystem
  node.inSystemSamples++
  // utilization tracking
  if (timestamp >= this.warmupDurationUs) {
    node.postWarmupInSystemSum += state.totalInSystem
    node.postWarmupInSystemSamples++
  }
}
```

**Span-based sampling** (`MetricsCollector.recordRequest` in `metrics.ts:167-189`):

For each completed request span:

```typescript
node.queueWaitSumMs += microToMs(span.queueWait)
node.serviceTimeSumMs += microToMs(span.serviceTime)
node.latencySamplesMs.push(microToMs(span.queueWait + span.serviceTime))
if (isSpanPostWarmup) {
  node.postWarmupQueueWaitSumMs += microToMs(span.queueWait)
  node.postWarmupServiceTimeSumMs += microToMs(span.serviceTime)
}
```

**Queue depth in time series**:

`TimeSeriesSnapshot.node[nodeId].queueLength` captures the queue depth at each 1-second snapshot. This is available for rendering time-series charts but is not aggregated into percentiles.

**Relationship to capacity**:

```
utilization (ρ) = avgActiveWorkers / maxWorkers
                ≈ throughput × avgServiceTime / workers

queueProbability = when ρ → 1, P(queue > 0) → 1
                   when ρ < 0.7, P(queue > 0) is low for most distributions
```

High utilization (> 85%) causes exponential queue growth for stochastic arrivals. This is the "hockey stick" effect visible in time-series charts: queue depth stays near 0 until a utilization threshold, then grows rapidly.

### What components it requires

- **Engine-side**: Fully implemented. For queue wait percentiles, store per-request wait times separately (~20 lines in `MetricsCollector`). For queue depth percentiles, store per-snapshot values and compute at output time (~15 lines).
- **Shared layer**: `PerNodeMetrics` is already shared.
- **Renderer/frontend-side**: Queue depth time series is available for charting. Avg/peak/utilization displayed in node metrics panel.

### Explored in

`src/engine/nodes/GGcKNode.ts:205-213` (getState → queueLength, totalInSystem), `src/engine/metrics.ts:265-284` (snapshot recording), `src/engine/metrics.ts:167-189` (span recording).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Environment Definition & Configuration Model** | Queue config (workers, capacity, discipline) as environment defaults/overrides | Default queue config values | `QueueConfig`, `EnvironmentNodeDefaults` |
| **Request Pattern Configuration** | Arrival process classification (D vs M) for queue theory analysis | Arrival rate λ that drives queue occupancy | `WorkloadProfile.pattern` → arrival process type |
| **Request Type Model** | Priority field consumed by priority discipline | Processing weight that affects service time → queue occupancy | `Request.priority`, `processingWeight` |
| **Edge Properties & Defaults** | — | Edge latency that adds to total time in system | Edge latency → total latency |
| **Throughput Calculation** | Queue occupancy as indicator of congestion | Throughput derived from processing rate | `PerNodeMetrics.throughput`, `avgInSystem` |
| **Arrival, Departure & Request Lifecycle Semantics** | Queue admission/rejection as lifecycle transitions | `request-arrival` → `handleArrival` → admit or reject | `ArrivalResult` |
| **Request Rejection Behaviour** | Admission control decisions (capacity_exceeded, node_failed) | Rejection reasons and metrics | `ArrivalResult.reason` |
| **Cost Calculation & Budgeting** | Queue depth × time as a resource consumption metric | — | `avgQueueLength`, `avgTimeInSystem` |
| **Simulation Validation & Pattern Accuracy** | Little's Law (L = λW) using queue metrics | Validation thresholds | `postWarmupAvgInSystem`, `postWarmupAvgTimeInSystem` |
| **Default-Driven Simplification Layer** | Default queue config as the baseline | Progressive disclosure of queue parameters | `{ workers: 1, capacity: 100, discipline: 'fifo' }` |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| `src/engine/nodes/GGcKNode.ts` | Implement proper WFQ discipline | Close the gap between the 4-value union and the 3 actual implementations | ~40 lines |
| `src/engine/metrics.ts` | Store per-request queue wait samples for percentile calculation | Enable queue wait P50/P95/P99 in output | ~15 lines |
| `src/engine/analysis/output.ts` | Add `queueWaitP50`, `queueWaitP95`, `queueWaitP99` to `PerNodeMetrics` | Expose queue wait distribution | ~10 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| G/G/c/K Queue Model | `GGcKNode.ts` | `ComponentNode`, `QueueConfig`, `NodeState` | `handleArrival()`, `handleCompletion()`, `startProcessing()` |
| Queue Disciplines | `GGcKNode.ts:247-270` | `QueueConfig['discipline']` | `dequeue()` |
| Admission Control | `GGcKNode.ts:80-107` | `ArrivalResult` | `handleArrival()` |
| Queue Depth Metrics | `metrics.ts:265-284, 311-395` | `PerNodeMetrics`, `InternalNodeMetrics` | `recordNodeSnapshot()`, `getPerNodeMetrics()` |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | `capacity` is total system capacity (workers + queue), not queue-only capacity | Design decision (implemented) | If users interpret capacity as queue-only, their nodes reject sooner than expected |
| 2 | WFQ treating as FIFO is acceptable for v1 | Assumption | Users selecting WFQ get FIFO behaviour with no indication |
| 3 | Priority discipline uses linear scan (O(n)) rather than a heap | Implementation choice | For large queues (>1000 requests), dequeue becomes a performance bottleneck |
| 4 | Queue depth snapshots at 1-second intervals are sufficient for time-series analysis | Assumption | High-frequency transients (sub-second bursts) are smoothed out |
| 5 | The `maxQueueLength` metric tracks both arrival-time peaks and snapshot-time peaks | Observation | Actually: `peakQueueLength` is updated at snapshot time and at queue push in `handleArrival`. Both paths capture it. |
| 6 | Failed nodes immediately reject all queued requests (queue is cleared) | Design decision (implemented) | An alternative would be to drain the queue after failure, processing requests with the remaining state |

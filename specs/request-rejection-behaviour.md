# Request Rejection Behaviour

Technical feature specification defining how requests are rejected, the five rejection pathways, the event flow from rejection trigger to terminal state, the metrics recorded for rejected requests, and the downstream effects on SLO breach detection, availability, and conservation accounting.

This spec consolidates the rejection logic scattered across `GGcKNode.handleArrival`, `engine.ts` security policy, edge transfer error handling, and post-processing error rate checks into a single reference. It exists because rejection is one of three terminal states a request can reach (alongside success and timeout), and every node in the topology can reject requests — yet the reasons, mechanics, and metric implications differ across pathways.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Rejection Triggers & Pathways](#feature-1-rejection-triggers--pathways)
4. [Feature 2: Rejection Event Handling](#feature-2-rejection-event-handling)
5. [Feature 3: Rejection Metrics & Accounting](#feature-3-rejection-metrics--accounting)
6. [Feature 4: Rejection Impact on SLOs & Availability](#feature-4-rejection-impact-on-slos--availability)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Request Rejection Behaviour defines the complete lifecycle of a rejected request: the five distinct triggers that cause rejection, the event creation and dispatch that moves a rejection through the engine, the metrics that record each rejection for post-warmup analysis, and the downstream effects on availability, error rates, SLO breach detection, and conservation accounting. A rejected request is terminal — it is removed from the active request map, its spans are flushed to the tracer, and it is never forwarded or retried.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Rejection rate drives availability, a key capacity planning metric |
| Architectural change      |       No | All five pathways are implemented |
| Domain model addition     |       No | Rejection reasons are string-typed; a typed union would improve safety |
| Validation layer          |  Partial | No dedicated rejection validation; capacity and error rate are validated on input |
| Refactor of existing code |       No | Implementation is sound but reason strings are untyped |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Rejection triggers (all 5 pathways) | Yes | Each pathway that emits a `request-rejected` event |
| Rejection event handling (`handleRequestRejected`) | Yes | The terminal handler for rejected requests |
| Rejection metrics (`recordRejection`) | Yes | Counter updates and warmup gating |
| Rejection effect on availability and SLOs | Yes | `errorRate`, `availability`, `detectSLOBreaches` |
| Rejection in conservation accounting | Yes | `postWarmupRejected` in the conservation identity |
| Admission control (capacity check) | Partial | Trigger owned here; queue model owned by Queue Depth Calculation |
| Node failure (fail/recover lifecycle) | Partial | Trigger owned here; fault injection scheduling belongs to future Fault Injection spec |
| Edge error rate (packet-level rejection) | Partial | Trigger owned here; edge transfer pipeline owned by Edge Properties & Defaults |
| Security policy (block rate) | Yes | Entire feature: config reading, random sampling, event creation |
| Node error rate (post-processing rejection) | Yes | Entire feature: config reading, random sampling, event creation |
| Timeout as terminal state | No | Belongs to Arrival, Departure & Request Lifecycle Semantics |

---

## Problem Context

### What exists today

**Five rejection pathways, each with its own trigger location:**

| # | Reason string | Trigger location | When it fires |
| - | --- | --- | --- |
| 1 | `capacity_exceeded` | `GGcKNode.handleArrival` (line 90-92) | `activeWorkers + queue.length >= maxCapacity` |
| 2 | `node_failed` | `GGcKNode.handleArrival` (line 83-85) | `this.status === 'failed'` |
| 3 | `security_blocked` | `engine.ts:applySecurityPolicy` (line 686-696) | `random() < policy.blockRate` |
| 4 | `edge_error_rate` | `engine.ts:enqueueEdgeTransfer` (line 743-753) | `random() < edge.errorRate` |
| 5 | `node_error_rate` | `engine.ts:handleProcessingComplete` (line 352-366) | `random() < nodeErrorRate` (via `shouldFailAtNode`) |

**Terminal handler:** `handleRequestRejected` at `engine.ts:468-488` — records metrics, flushes spans to tracer, marks status `'rejected'`, sets `metadata.__terminal = 'rejected'`, deletes from `requestById`.

**Metrics recording:** `MetricsCollector.recordRejection` at `metrics.ts:213-231` — increments global `totalRequests`, `failedRequests`, `rejectedRequests`; increments per-node `totalArrived`, `totalRejected`; gates post-warmup counters by `nodeArrivalTime`.

**Availability derivation:** `getPerNodeMetrics` at `metrics.ts:325-385` — computes `errorRate = (postWarmupRejected + postWarmupTimedOut) / postWarmupArrived`, then `availability = 1 - errorRate`.

### What's missing

| Gap | Impact |
| --- | --- |
| Rejection reason is an untyped `string` | No compile-time exhaustiveness check; typo in a reason string fails silently |
| `recordRejection` receives `reason` but immediately discards it (`void reason`) | Per-reason breakdown impossible in output; all rejections are a single counter |
| No per-reason metrics in `PerNodeMetrics` or `SimulationSummary` | Users cannot distinguish capacity rejections from security blocks or error rate failures |
| `node_failed` bulk rejection in `fail()` increments `metrics.totalRejections` but never calls `recordRejection` | Conservation check will under-count rejections; queued requests silently disappear |
| No rejection event in debug event log for bulk `fail()` rejects | Debugger cannot trace why queued requests vanished |
| Security policy `droppedPackets` schedules a timeout, not a rejection | A "dropped" request looks like a timeout, not a security action — misleading in metrics |
| No backpressure or retry semantics | Rejected requests are always terminal; no circuit breaker or retry-with-backoff |
| Rejection reason not stored on the request object | Tracer knows status='rejected' but not why — limits diagnostic value |

---

## Feature 1: Rejection Triggers & Pathways

### Current implementation

The simulator has five distinct code paths that produce a `request-rejected` event. Each pathway fires at a different stage of the request lifecycle, uses a different reason string, and passes the rejection through a different intermediate mechanism.

#### Pathway 1: Capacity exceeded (admission control)

**Location:** `GGcKNode.handleArrival` at `src/engine/nodes/GGcKNode.ts:80-107`

```
handleArrival(request, currentTime):
  if status === 'failed' → reject (pathway 2)
  currentLoad = activeWorkers + queue.length
  if currentLoad >= maxCapacity → reject with 'capacity_exceeded'
  else → process or queue
```

This is the queue-model admission gate. The check is `>=`, meaning `maxCapacity` is an inclusive limit — when `activeWorkers + queue.length` equals `maxCapacity`, no more requests can enter. The rejection increments `this.metrics.totalRejections` inside the node, then the engine wraps it in a `request-rejected` event at `engine.ts:324-334`.

**Configuration:** `maxCapacity` comes from `node.queue.capacity` (defaulted to `100` by `withNodeDefaults` at `engine.ts:627-636`). It represents K in the G/G/c/K model — total system capacity including both active workers and queued items.

**Lifecycle stage:** Pre-processing. The request never enters the queue or touches a worker.

#### Pathway 2: Node failed

**Location:** `GGcKNode.handleArrival` at `src/engine/nodes/GGcKNode.ts:83-85`

```
if this.status === 'failed':
  metrics.totalRejections++
  return { status: 'rejected', reason: 'node_failed' }
```

This fires when the node is in `'failed'` state, set by `GGcKNode.fail()` at line 189-197. The `fail()` method is triggered by a `node-failure` event (dispatched at `engine.ts:261-262`), which drains the queue, clears all active workers, and transitions status to `'failed'`. Recovery happens via `node-recovery` event calling `recover()` at line 201-202, which resets status to `'idle'`.

**Critical gap:** When `fail()` fires, it bulk-rejects all queued requests by setting `metrics.totalRejections += queue.length` and clearing the queue — but it never calls `recordRejection` on the `MetricsCollector` for these requests, and no `request-rejected` events are created. These requests silently vanish from the simulation.

**Lifecycle stage:** Pre-processing. Identical position to capacity-exceeded, but the node refuses all work regardless of load.

#### Pathway 3: Security blocked

**Location:** `engine.ts:applySecurityPolicy` at lines 668-700

```
applySecurityPolicy(nodeId, request):
  policy = securityPolicyByNodeId.get(nodeId)
  if !policy → return false
  if droppedPackets > 0 && random() < droppedPackets:
    schedule request-timeout → return true
  if blockRate > 0 && random() < blockRate:
    schedule request-rejected with reason='security_blocked' → return true
  return false
```

This runs at the top of `handleRequestArrival` (line 319), before the node's `handleArrival` is called. Two sub-behaviours:

- **`blockRate`**: Probability of outright rejection. Creates a `request-rejected` event with reason `'security_blocked'`. The request never reaches the node's queue.
- **`droppedPackets`**: Probability of silent drop. Creates a `request-timeout` event instead of rejection. This means a security drop looks identical to a timeout in metrics — there is no way to distinguish a security-dropped request from one that genuinely timed out.

**Configuration:** `SecurityPolicyConfig` is read from `node.config.securityPolicy` at `engine.ts:644-666`. Both `blockRate` and `droppedPackets` are clamped to `[0, 1]`. If both are zero, no policy is stored.

**Lifecycle stage:** Pre-admission. The request has arrived at the node (path is updated) but has not been offered to `handleArrival`.

#### Pathway 4: Edge error rate

**Location:** `engine.ts:enqueueEdgeTransfer` at lines 743-753

```
enqueueEdgeTransfer(request, edge, targetNodeId):
  if random() < edge.packetLossRate → schedule timeout (not rejection)
  if random() < edge.errorRate → schedule request-rejected with reason='edge_error_rate'
  else → sample latency, check deadline, schedule arrival
```

This fires during edge transfer, after the request has departed its source node but before it arrives at the target. The rejection is attributed to the *target* node (`targetNodeId`), even though the error occurred on the edge. The `nodeArrivalTime` is set to `this.clock` (the departure time from source), not the would-be arrival time.

**Note:** `packetLossRate` produces a timeout, not a rejection — similar to `droppedPackets` in security policy. Only `errorRate` produces a true rejection.

**Configuration:** `edge.errorRate` comes from `EdgeDefinition.errorRate`. Default is `0` in the engine (no edge defaults applied); the renderer applies `0.001` (0.1%) via `EDGE_DEFAULTS`.

**Lifecycle stage:** In-transit. The request is between nodes. It has a departure span from the source but no arrival at the target.

#### Pathway 5: Node error rate (post-processing)

**Location:** `engine.ts:handleProcessingComplete` at lines 352-366

```
handleProcessingComplete(event):
  completion = node.handleCompletion(request, clock)
  if completion.completedSpan → push span
  if shouldFailAtNode(nodeId):
    schedule request-rejected with reason='node_error_rate'
    (nodeArrivalTime = completedSpan.arrivalTime)
    return
  // else resolve routes and forward
```

This fires *after* the request has been fully processed — the worker has completed, the span has been recorded, and the worker slot has been freed. The random check in `shouldFailAtNode` (`engine.ts:702-706`) samples against `nodeErrorRate` from `node.config.nodeErrorRate` (read at line 638-641, clamped to `[0, 1]`).

**Key detail:** The rejection uses `completedSpan.arrivalTime` as the `nodeArrivalTime` for warmup gating. This is correct — it attributes the rejection to the time window when the request entered the node, not when processing completed.

**Lifecycle stage:** Post-processing. The request has consumed resources (worker time, queue wait) and is rejected at the point of departure. This models application-level errors (e.g., a 500 response after processing).

### Decision sequence diagram

```
Request arrives at node
  │
  ├─ applySecurityPolicy?
  │   ├─ droppedPackets hit → schedule TIMEOUT (not rejection)
  │   └─ blockRate hit → schedule REJECTED (security_blocked)
  │
  ├─ node.handleArrival
  │   ├─ status === 'failed' → REJECTED (node_failed)
  │   ├─ load >= capacity → REJECTED (capacity_exceeded)
  │   ├─ workers available → start processing
  │   └─ workers full → enqueue
  │
  └─ [after processing completes]
      └─ shouldFailAtNode? → REJECTED (node_error_rate)

Edge transfer (between nodes)
  ├─ packetLossRate hit → schedule TIMEOUT (not rejection)
  └─ errorRate hit → schedule REJECTED (edge_error_rate)
```

### Proposed types

```typescript
type RejectionReason =
  | 'capacity_exceeded'
  | 'node_failed'
  | 'security_blocked'
  | 'edge_error_rate'
  | 'node_error_rate';

interface RejectionDetail {
  reason: RejectionReason;
  nodeId: string;
  requestId: string;
  nodeArrivalTime: bigint;
  lifecycleStage: 'pre-admission' | 'admission' | 'in-transit' | 'post-processing';
  resourcesConsumed: boolean;
}
```

The `lifecycleStage` captures *when* in the request lifecycle the rejection occurred. The `resourcesConsumed` flag is `true` only for `node_error_rate` rejections, where the request used worker time before being rejected.

---

## Feature 2: Rejection Event Handling

### Current implementation

All five rejection pathways converge at `handleRequestRejected` in `engine.ts:468-488`. This handler receives a `SimulationEvent` of type `'request-rejected'` and performs four actions:

**Step 1: Extract reason**
```typescript
const reason = (event.data.reason as string | undefined) ?? 'rejected'
```
The reason is extracted from `event.data.reason` with a fallback to the generic string `'rejected'`. This cast to `string` is the only place the reason is read — there is no typed enum or validation.

**Step 2: Record metrics**
```typescript
const nodeArrivalTime =
  typeof event.data.nodeArrivalTime === 'bigint' ? event.data.nodeArrivalTime : undefined
this.metrics.recordRejection(event.nodeId, reason, {
  requestCreatedAt: request.createdAt,
  nodeArrivalTime
})
```
The `nodeArrivalTime` is pulled from event data and passed to `recordRejection` for warmup gating. Each pathway sets `nodeArrivalTime` differently:

| Pathway | `nodeArrivalTime` value |
| --- | --- |
| `capacity_exceeded` | `this.clock` at arrival time |
| `node_failed` | `this.clock` at arrival time |
| `security_blocked` | `this.clock` at arrival time |
| `edge_error_rate` | `this.clock` at departure from source |
| `node_error_rate` | `completedSpan.arrivalTime` (when request entered the node) |

**Step 3: Flush spans to tracer**
```typescript
for (const span of request.spans) {
  this.tracer.recordSpan(request.id, span)
}
this.tracer.markStatus(request.id, 'rejected')
```
All accumulated spans are flushed. For pre-admission rejections (security, capacity, node_failed), there are zero spans. For `node_error_rate`, there is at least one completed span. For `edge_error_rate`, there may be spans from prior nodes.

**Step 4: Terminal cleanup**
```typescript
request.metadata.__terminal = 'rejected'
this.requestById.delete(request.id)
```
The request is marked terminal and removed from the active map. No further events can reference it.

### Event priority

Rejection events are created with `createEvent` using default priority. Per the event system, `request-rejected` maps to `EventPriority.DEPARTURE` (3). This means rejections are processed after arrivals and processing-completes in the same time tick, which is correct — a request must arrive before it can be rejected.

### Interaction with timeout cancellation

When a request is rejected at admission (`capacity_exceeded`, `node_failed`), no timeout was ever scheduled — `scheduleNodeTimeout` at `engine.ts:337` only runs if admission succeeds. Therefore there is no dangling timeout to worry about.

When a request is rejected post-processing (`node_error_rate`), a timeout *was* scheduled at admission. However, by the time rejection fires, the request has already been through `handleCompletion`, and `handleRequestRejected` deletes it from `requestById`. If the timeout event fires later, `getRequest(event)` returns `undefined` and the handler exits early. This is the standard stale-event pattern.

When a request is rejected on the edge (`edge_error_rate`), the timeout was scheduled at the *source* node. The rejection event targets the *target* node. The source node's timeout may still fire, but `getRequest(event, false)` — called with `false` in `handleRequestRejected` — does not delete from the request map. Wait — actually `handleRequestRejected` *does* delete from `requestById` at line 487. So if the source timeout fires after the edge rejection, the request is already gone and the timeout handler exits early.

For `security_blocked`, no timeout was scheduled because the security check runs before `scheduleNodeTimeout`.

### Async fan-out and rejection

When an async edge fans out (see Request Flow Direction & Topology Rules), each branch clone gets an independent ID (`{id}::branch-{n}`). If one branch is rejected (e.g., `edge_error_rate` on one of several parallel edges), only that branch is affected. The original request and other branches continue independently. Each branch clone is in `requestById` with its own entry, so deletion of the rejected branch does not affect siblings.

### Proposed improvements

**Typed rejection reason:** Replace `(event.data.reason as string | undefined)` with a typed `RejectionReason` discriminant. The `createEvent` call sites should use the typed reason, and `handleRequestRejected` should switch on it for future per-reason handling.

**Reason stored on request:** Add `rejectionReason?: RejectionReason` to the `Request` interface. Set it in `handleRequestRejected` before flushing to tracer. This lets trace inspection show *why* a request was rejected.

**Bulk fail() event emission:** `GGcKNode.fail()` should return the list of dropped request IDs so the engine can emit individual `request-rejected` events for each, ensuring conservation accounting and debug tracing work correctly.

---

## Feature 3: Rejection Metrics & Accounting

### Current implementation

`MetricsCollector.recordRejection` at `metrics.ts:213-231` updates six counters:

| Counter | Scope | Warmup-gated? | Description |
| --- | --- | --- | --- |
| `totalRequests` | Global | No | Denominator for global error rate |
| `failedRequests` | Global | No | Numerator for global error rate (includes timeouts) |
| `rejectedRequests` | Global | No | Rejection-specific global counter |
| `postWarmupTotalRequests` | Global | Yes (by `requestCreatedAt`) | Post-warmup denominator |
| `node.totalArrived` | Per-node | No | Node-level total arrivals |
| `node.totalRejected` | Per-node | No | Node-level rejection count |
| `node.postWarmupArrived` | Per-node | Yes (by `nodeArrivalTime`) | Post-warmup arrivals at this node |
| `node.postWarmupRejected` | Per-node | Yes (by `nodeArrivalTime`) | Post-warmup rejections at this node |

**Warmup gating detail:** The per-node warmup gate uses `nodeArrivalTime` (falling back to `requestCreatedAt`). For the `edge_error_rate` pathway, `nodeArrivalTime` is the departure time from the source node, which may be within the warmup window even if the edge transfer would have completed after warmup. This is acceptable because the rejection decision was made at departure time.

**Critical gap — reason discarded:** The `reason` parameter is received but immediately voided:
```typescript
recordRejection(nodeId: string, reason: string, context: FailureMetricsContext = {}): void {
  void reason
  // ... only increments counters, never stores reason
}
```

This means all rejections — capacity, security, edge error, node error — are collapsed into a single counter. There is no way to answer "how many requests were rejected due to capacity vs. error rate?" from the output.

### Derived metrics

`getPerNodeMetrics` at `metrics.ts:311-395` derives two key metrics from rejection counters:

**Error rate:**
```typescript
const postWarmupFailed = postWarmupRejected + postWarmupTimedOut
const errorRate = postWarmupArrived > 0 ? postWarmupFailed / postWarmupArrived : 0
```

Rejections and timeouts are combined into a single failure numerator. This means a node with 50% capacity rejections and 0% timeouts has the same error rate as one with 0% rejections and 50% timeouts. For capacity planning these are very different situations — one means "add more capacity", the other means "reduce latency".

**Availability:**
```typescript
availability: 1 - errorRate
```

Availability is the complement of error rate. An availability of `0.95` means 5% of post-warmup requests failed (rejected or timed out).

### Conservation accounting

`buildConservationCheck` at `output.ts:308-326` verifies the identity:

```
postWarmupArrived = postWarmupProcessed + postWarmupRejected + postWarmupTimedOut + inFlight
```

`postWarmupRejected` is a critical term. If rejections are under-counted (as happens with bulk `fail()` — see Feature 1), the conservation check will show phantom `inFlight` requests that are actually silently dropped.

The check considers the system "balanced" if `inFlight / postWarmupArrived < 0.05` (5%). Bulk node failures during the post-warmup window could push `inFlight` above this threshold and trigger a spurious imbalance warning.

### Proposed per-reason metrics

```typescript
interface RejectionBreakdown {
  capacityExceeded: number;
  nodeFailed: number;
  securityBlocked: number;
  edgeErrorRate: number;
  nodeErrorRate: number;
}

interface PerNodeMetrics {
  // ... existing fields ...
  postWarmupRejectionBreakdown: RejectionBreakdown;
}
```

`recordRejection` should store `reason` into the appropriate bucket instead of voiding it. This enables:
- Capacity rejection rate (signals need for more capacity or higher K)
- Error rejection rate (signals need for better error handling)
- Security rejection rate (signals policy tuning)

---

## Feature 4: Rejection Impact on SLOs & Availability

### Current implementation

**SLO breach detection:** `detectSLOBreaches` at `output.ts:172-213` checks two SLO dimensions per node:

1. **Latency P99** — `nodeMetrics.latencyP99 > slo.latencyP99`. Rejections do *not* contribute to latency percentiles because rejected requests never complete processing (no `recordRequest` call). This is by design — latency metrics only measure successful requests.

2. **Availability** — `nodeMetrics.availability < slo.availabilityTarget`. This *is* affected by rejections. Every rejection lowers availability via the `errorRate` formula. The severity is computed as:
```typescript
severity: severityForRatio(slo.availabilityTarget / Math.max(nodeMetrics.availability, 0.0001))
```
Where `severityForRatio` returns `'critical'` if the ratio ≥ 1.25, else `'warning'`.

**Example:** A node with `slo.availabilityTarget = 0.999` and actual availability of `0.95` (due to capacity rejections) produces a ratio of `0.999 / 0.95 ≈ 1.052`, which is a `'warning'`. If availability drops to `0.79`, the ratio is `0.999 / 0.79 ≈ 1.264`, which is `'critical'`.

### Rejection vs. timeout in SLO context

Both rejection and timeout lower availability equally. A request that is rejected at admission (consuming zero resources) has the same SLO impact as one that times out after 30 seconds of processing. This is appropriate for external-facing SLOs (the client sees a failure either way) but may be misleading for internal capacity analysis.

### Latency impact of rejections

While rejected requests don't appear in latency percentiles, high rejection rates *indirectly* improve latency metrics. When a node rejects excess load, the remaining requests experience less queueing. This means a node with aggressive capacity limits might show excellent latency P99 but poor availability — a classic latency-vs-throughput tradeoff that the simulator correctly captures.

### Proposed SLO extensions

```typescript
interface SLOConfig {
  // ... existing fields ...
  maxRejectionRate?: number;     // e.g., 0.01 = max 1% rejections
  maxCapacityRejectionRate?: number;  // specifically capacity-based rejections
}
```

With per-reason metrics (Feature 3), SLO breach detection could distinguish between:
- "Availability is low because of capacity limits" → scale up
- "Availability is low because of error rates" → fix bugs
- "Availability is low because of security policy" → tune policy

### Throughput interaction

`throughput = postWarmupProcessed / effectiveDurationSec` (from `metrics.ts:383`). Rejections reduce throughput indirectly: a rejected request is never processed, so it doesn't contribute to `postWarmupProcessed`. However, the *theoretical* throughput of the node (`workers × (1 / avgServiceTime)`) is unaffected by rejections — it measures capacity, not realized output.

The gap between theoretical and actual throughput can be caused by rejections (requests that *could* have been processed if capacity were higher) or by low arrival rate (not enough requests to fill capacity). The current output does not separate these causes.

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | Relationship |
| --- | --- |
| **Queue Depth Calculation** | Admission control (capacity check) is the trigger for `capacity_exceeded` rejection. This spec owns the *rejection* lifecycle; Queue Depth owns the *queue model* that decides admission. |
| **Arrival, Departure & Request Lifecycle Semantics** | Rejection is one of three terminal states. Lifecycle spec defines the state machine; this spec details the rejection terminal path. |
| **Edge Properties & Defaults** | `edge.errorRate` triggers `edge_error_rate` rejection. Edge spec owns the transfer pipeline; this spec owns the rejection consequence. |
| **Throughput Calculation** | Rejections reduce realized throughput. Throughput spec computes the metric; this spec explains why it may be lower than theoretical. |
| **Request Type Model** | Currently rejection is type-agnostic. Future per-type rejection policies (e.g., high-priority requests bypass capacity limits) would bridge these specs. |
| **Cost Calculation & Budgeting** | `node_error_rate` rejections consume resources (worker time) before rejecting. Cost spec must account for this wasted processing. Other rejection types consume no resources. |
| **Simulation Validation & Pattern Accuracy** | Conservation check depends on accurate rejection counting. Under-counted rejections (from bulk `fail()`) produce spurious imbalance warnings. |
| **Default-Driven Simplification Layer** | `nodeErrorRate` and `securityPolicy.blockRate` default to absence (no rejection). `edge.errorRate` defaults to `0` in engine, `0.001` in renderer. Capacity default is `100`. |

---

## Integration Requirements

### Across features

| Integration point | Producer | Consumer | Contract |
| --- | --- | --- | --- |
| `ArrivalResult.reason` | `GGcKNode.handleArrival` | `engine.handleRequestArrival` | `'capacity_exceeded' \| 'node_failed'` string |
| `event.data.reason` | All five rejection sites | `handleRequestRejected` | Untyped `string`, should be `RejectionReason` |
| `event.data.nodeArrivalTime` | All rejection sites | `recordRejection` | `bigint` for warmup gating |
| `postWarmupRejected` | `recordRejection` | `buildConservationCheck` | Must equal actual post-warmup rejection count |
| `errorRate` / `availability` | `getPerNodeMetrics` | `detectSLOBreaches` | `errorRate = (rejected + timedOut) / arrived` |
| `tracer.markStatus('rejected')` | `handleRequestRejected` | Trace output | Terminal status for trace visualization |

### Within this feature

| Component | Responsibility | Key invariant |
| --- | --- | --- |
| `GGcKNode.handleArrival` | Capacity and failure admission check | Returns `'rejected'` before any resource allocation |
| `applySecurityPolicy` | Pre-admission security check | Runs before `handleArrival`; rejected requests never touch the queue |
| `enqueueEdgeTransfer` | Edge-level error injection | Rejection attributed to target node, not source |
| `shouldFailAtNode` | Post-processing error injection | Rejection after resources consumed; `nodeArrivalTime` from span |
| `handleRequestRejected` | Terminal handler | Flushes spans, records metrics, removes from active map |
| `recordRejection` | Metrics accumulation | Warmup-gated per-node and global counters |

---

## Source-to-Feature Map

| Source file | Lines | Feature |
| --- | --- | --- |
| `src/engine/nodes/GGcKNode.ts` | 80-107 | F1: Admission control (capacity_exceeded, node_failed) |
| `src/engine/nodes/GGcKNode.ts` | 189-203 | F1: fail()/recover() state transitions |
| `src/engine/engine.ts` | 311-338 | F1/F2: handleRequestArrival → security → admission → rejection event |
| `src/engine/engine.ts` | 340-366 | F1: handleProcessingComplete → node_error_rate rejection |
| `src/engine/engine.ts` | 468-488 | F2: handleRequestRejected terminal handler |
| `src/engine/engine.ts` | 638-641 | F1: readNodeErrorRate config parsing |
| `src/engine/engine.ts` | 644-666 | F1: readSecurityPolicy config parsing |
| `src/engine/engine.ts` | 668-700 | F1: applySecurityPolicy decision logic |
| `src/engine/engine.ts` | 702-706 | F1: shouldFailAtNode random check |
| `src/engine/engine.ts` | 728-778 | F1: enqueueEdgeTransfer → edge_error_rate rejection |
| `src/engine/metrics.ts` | 213-231 | F3: recordRejection counters and warmup gating |
| `src/engine/metrics.ts` | 325-385 | F3/F4: errorRate, availability derivation |
| `src/engine/analysis/output.ts` | 172-213 | F4: detectSLOBreaches availability check |
| `src/engine/analysis/output.ts` | 308-326 | F3: buildConservationCheck with postWarmupRejected |

---

## Assumptions and Unresolved Questions

### Assumptions

1. **Rejection is terminal.** A rejected request is never retried, re-routed, or re-queued. This is a design choice, not a limitation — retry/backoff semantics would require a separate spec.

2. **Edge rejection is attributed to the target node.** When `edge_error_rate` fires, `event.nodeId` is `targetNodeId`. This means the target node's rejection counter increases even though the target never saw the request. This attribution is debatable — the error occurred on the wire, not at the target.

3. **Post-processing rejection consumes resources.** A `node_error_rate` rejection happens after the worker has fully processed the request. The worker time is "wasted" — the request consumed c × serviceTime resources that produced no successful output. This is the correct model for application-level errors.

4. **`droppedPackets` producing timeout is intentional.** The security policy's `droppedPackets` models packet-level loss (like a firewall silently dropping traffic), where the sender waits until timeout. This is semantically different from `blockRate` (which models an immediate rejection like a 403).

### Unresolved questions

| # | Question | Why it matters |
| - | --- | --- |
| 1 | Should `fail()` emit individual rejection events for queued requests? | Conservation accounting is broken without it; debug tracing loses visibility into bulk failures |
| 2 | Should rejection reason be stored on the `Request` object for trace output? | Currently tracer knows `status='rejected'` but not why — limits diagnostics |
| 3 | Should per-reason rejection breakdowns appear in `PerNodeMetrics`? | Without it, users can't distinguish capacity limits from errors — critical for capacity planning |
| 4 | Should `edge_error_rate` rejection be attributed to source or target node? | Current target attribution inflates the target's rejection count for an error it didn't cause |
| 5 | Should `droppedPackets` produce a distinct terminal state (not timeout)? | Currently indistinguishable from genuine timeouts in metrics |
| 6 | Should there be a priority-based rejection policy (reject low-priority when near capacity)? | Would enable graceful degradation instead of all-or-nothing admission |
| 7 | Should the simulator support retry-on-rejection with configurable backoff? | Real systems retry; current terminal-only model may undercount throughput |
| 8 | Should `node_error_rate` rejection trigger at the start of processing instead of the end? | Current post-processing model wastes resources; pre-processing model would be more efficient but less realistic |

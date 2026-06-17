# Arrival, Departure & Request Lifecycle Semantics

Technical feature specification defining the complete lifecycle of a request from generation to terminal state: every event type, every state transition, every decision point, and how the event priority system resolves ordering ambiguities.

This spec consolidates the 20 `EventType` values, the `SimulationEvent` interface, the `EventPriority` constants, the `MinHeap` scheduler, and the engine's event handling pipeline into a single reference for how requests move through time and state. It exists because the lifecycle is the simulation's execution model — every metric, every trace, every debug event is a consequence of lifecycle transitions. Downstream specs (throughput, rejection, cost) all reference specific lifecycle events; this spec is the authoritative definition of what those events mean and when they fire.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Request Lifecycle State Machine](#feature-1-request-lifecycle-state-machine)
4. [Feature 2: Event Types and Priority System](#feature-2-event-types-and-priority-system)
5. [Feature 3: Event Processing Loop](#feature-3-event-processing-loop)
6. [Feature 4: Timeout Mechanics](#feature-4-timeout-mechanics)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Request Lifecycle Semantics defines the deterministic state machine that every request follows from creation to terminal state. A request is generated, optionally routed via edges, arrives at nodes, is admitted or rejected, waits in a queue, is processed, is forwarded or completes, and eventually reaches one of three terminal states: success, rejection, or timeout. The event system — a MinHeap priority queue with bigint microsecond timestamps and tie-breaking priorities — ensures that events are processed in a deterministic, reproducible order for any given seed.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Users observe lifecycle events in the debug panel; lifecycle determines metrics |
| Architectural change      |       No | The event loop and handlers are implemented and stable |
| Domain model addition     |       No | All types exist (`EventType`, `SimulationEvent`, `Request`, `EventPriority`) |
| Validation layer          |       No | Lifecycle is runtime, not validation-time |
| Refactor of existing code |       No | Implementation is sound |

---

## Problem Context

### What exists today

**20 event types** (`src/engine/core/events.ts:4-24`):

| Category | Events | Implemented? |
| --- | --- | --- |
| Request lifecycle | `request-generated`, `request-arrival`, `processing-start`, `processing-complete`, `request-forwarded`, `request-complete` | Yes (all) |
| Terminal | `request-timeout`, `request-rejected` | Yes |
| Node | `node-failure`, `node-recovery` | Yes |
| Infrastructure | `network-partition`, `latency-spike`, `scale-up`, `scale-down` | Stub (default case) |
| Resilience | `circuit-breaker-open`, `circuit-breaker-close` | Stub |
| Operational | `health-check`, `cache-hit`, `cache-miss`, `db-failover` | Stub |

Only the first 9 events have full handler implementations. The remaining 11 fall through to the `default` case in `handleEvent` with a comment "integrated in later tickets."

**Event priority system** (`events.ts:30-36`):

```typescript
export const EventPriority = {
  SYSTEM: 0,
  ARRIVAL: 1,
  PROCESSING: 2,
  DEPARTURE: 3,
  TIMEOUT: 4
}
```

Lower number = higher priority. When two events share the same timestamp, the event with the lower priority number is processed first. This ensures: system events (node failures) happen before arrivals, arrivals before processing, processing before departures, and timeouts last (giving requests a chance to complete before timing out).

**MinHeap scheduler** (`src/engine/scheduler/min-heap.ts`):

Events are ordered by `(timestamp, priority)`. The MinHeap extracts the minimum-key event at each step. Combined with seeded RNG, this produces fully deterministic, reproducible execution order.

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| 11 event types are stubs | Infrastructure and resilience events don't affect simulation | Handlers not implemented |
| `processing-start` is never explicitly emitted | The event type exists but the engine doesn't emit it; processing starts implicitly in `handleArrival`/`handleCompletion` | Only `processing-complete` is scheduled |
| No explicit lifecycle state field on Request | Terminal state is tracked via `metadata.__terminal`, not a typed field | Request interface uses `metadata` escape hatch |

---

## Feature 1: Request Lifecycle State Machine

### What it does

Defines every state a request can be in and every transition between states. This is the canonical reference for understanding what path a request takes through the simulator.

### How it works internally

**States**:

| State | Meaning | Where tracked |
| --- | --- | --- |
| Generated | Request created by WorkloadGenerator, not yet at any node | Between `request-generated` and first `request-arrival` or `request-complete` |
| In-transit | Request is on an edge between two nodes | Between `request-forwarded` and `request-arrival` (or timeout) |
| Queued | Request admitted to a node, waiting for a worker | Between admission and `startProcessing` call |
| Processing | Request being served by a worker | Between `startProcessing` and `processing-complete` |
| Forwarded | Request processing complete, being sent to next node | At `request-forwarded` event |
| **Completed** (terminal) | Request reached a sink/terminal node | `request-complete` event |
| **Rejected** (terminal) | Request rejected by node or edge | `request-rejected` event |
| **Timed out** (terminal) | Request exceeded its deadline | `request-timeout` event |

**State transitions**:

```
                                    ┌─────────────┐
                                    │  Generated   │
                                    └──────┬───────┘
                                           │
                        ┌──────────────────┼───────────────────┐
                        │                  │                   │
                        ▼                  ▼                   ▼
                 ┌──────────────┐  ┌──────────────┐   ┌───────────────┐
                 │  In-transit   │  │ Arrive at    │   │  Completed    │
                 │  (via edge)   │  │ source node  │   │  (no routes)  │
                 └──────┬───────┘  └──────┬───────┘   └───────────────┘
                        │                 │
           ┌────────────┼─────────┐       │
           │            │         │       │
           ▼            ▼         ▼       ▼
    ┌──────────┐ ┌──────────┐ ┌────────────────┐
    │ Timed out│ │ Rejected │ │    Queued or    │
    │ (loss)   │ │ (err)    │ │   Processing   │
    └──────────┘ └──────────┘ └───────┬────────┘
                                      │
                               ┌──────┼──────────┐
                               │      │          │
                               ▼      ▼          ▼
                        ┌──────────┐ ┌────────────────┐
                        │ Rejected │ │  Processing    │
                        │ (cap/fail│ │  complete      │
                        └──────────┘ └───────┬────────┘
                                             │
                                ┌────────────┼────────────┐
                                │            │            │
                                ▼            ▼            ▼
                         ┌──────────┐ ┌──────────┐ ┌──────────────┐
                         │ Rejected │ │Forwarded │ │  Completed    │
                         │ (node_err│ │(→ edge)  │ │  (no routes)  │
                         └──────────┘ └────┬─────┘ └──────────────┘
                                           │
                                           ▼
                                    ┌──────────────┐
                                    │  In-transit   │
                                    │  (next edge)  │
                                    └──────┬───────┘
                                           │
                                    (cycle back to arrival)
```

**Terminal state tracking**:

When a request reaches a terminal state, the engine sets `request.metadata.__terminal` to the terminal reason (`'success'`, `'rejected'`, `'timeout'`) and deletes the request from `requestById`. This prevents double-processing: if a timeout event fires for a request that already completed, `getRequest(event, false)` returns `undefined` because the request is no longer in the map, and the handler exits early.

**Handler mapping** (`engine.ts:238-271`):

| Event type | Handler | What it does |
| --- | --- | --- |
| `request-generated` | `handleRequestGenerated` | Generate request, resolve routes from source, initiate transfers |
| `request-arrival` | `handleRequestArrival` | Security policy check, admission to GGcKNode, schedule node timeout |
| `processing-complete` | `handleProcessingComplete` | Record span, check node error rate, resolve routes, forward or complete |
| `request-forwarded` | `handleRequestForwarded` | Extract edge/target from event data, enqueue edge transfer |
| `request-complete` | `handleRequestComplete` | Record success metrics, record spans to tracer, delete from requestById |
| `request-timeout` | `handleRequestTimeout` | Cancel at node if scope='node', record timeout metrics, delete from requestById |
| `request-rejected` | `handleRequestRejected` | Record rejection metrics, delete from requestById |
| `node-failure` | inline | `nodes.get(nodeId)?.fail(clock)` |
| `node-recovery` | inline | `nodes.get(nodeId)?.recover(clock)` |

### Explored in

`src/engine/engine.ts:238-271` (event dispatch), `src/engine/core/events.ts` (event types and priorities).

---

## Feature 2: Event Types and Priority System

### What it does

Defines the 20 event types, their default priorities, and how the priority system resolves simultaneous events.

### How it works internally

**Priority assignment** (`getDefaultPriority` in `events.ts:71-108`):

| Priority level | Value | Events | Rationale |
| --- | --- | --- | --- |
| SYSTEM | 0 | `node-failure`, `node-recovery`, `network-partition`, `latency-spike`, `scale-up`, `scale-down`, `circuit-breaker-open`, `circuit-breaker-close`, `health-check`, `db-failover` | System events must be processed before request events to ensure consistent state |
| ARRIVAL | 1 | `request-generated`, `request-arrival` | Arrivals before processing to model real causality |
| PROCESSING | 2 | `processing-start`, `processing-complete`, `request-complete`, `request-rejected`, `cache-hit`, `cache-miss` | Processing results after arrivals |
| DEPARTURE | 3 | `request-forwarded` | Departures after processing |
| TIMEOUT | 4 | `request-timeout` | Timeouts last — give the request a chance to complete first |

**Why timeout has the lowest priority**: If a `processing-complete` and a `request-timeout` share the same timestamp, the processing completes first. The request successfully finishes, its `__terminal` is set to `'success'`, and when the timeout handler runs, `getRequest` returns `undefined` and the timeout is silently discarded. This prevents false timeouts on requests that just barely made their deadline.

**MinHeap ordering**: The MinHeap compares events by `(timestamp, priority)`. Events with earlier timestamps always process first. Only when timestamps are identical does the priority break the tie.

**Determinism**: Because the RNG is seeded and the MinHeap produces a deterministic ordering for any given event sequence, the same topology + seed + pattern always produces the exact same event sequence. This is guaranteed by `SimulationOutput.reproducible: true`.

### Explored in

`src/engine/core/events.ts:30-36` (priority constants), `src/engine/core/events.ts:71-108` (default priority assignment), `src/engine/scheduler/min-heap.ts` (heap ordering).

---

## Feature 3: Event Processing Loop

### What it does

The central simulation loop that extracts events from the MinHeap, advances the clock, emits snapshots, dispatches to handlers, and tracks progress.

### How it works internally

**Loop** (`processEvents` in `engine.ts:188-236`):

```
while running AND not paused AND queue not empty:
    peek next event
    if event.timestamp > simulationDurationUs → stop
    extract event from heap
    advance clock to event.timestamp
    if snapshot interval elapsed → take and emit snapshot
    dispatch to handler
    emit debug event (if debugging)
    increment eventsProcessed
    if eventsProcessed % 1000 === 0 → emit progress
```

**Clock model**: `bigint` microsecond precision. The clock only advances forward — it jumps to each event's timestamp. Between events, no time passes. This is the fundamental property of discrete event simulation: time is event-driven, not wall-clock-driven.

**Snapshot interval**: 1 second of simulation time (`secToMicro(1)`). Snapshots capture queue depth, utilization, and active worker count at each node.

**Termination conditions**:
1. Event queue is empty (no more events to process)
2. Next event's timestamp exceeds simulation duration
3. `stop()` called externally (from Web Worker `stop` message)
4. `pause()` called externally

### Explored in

`src/engine/engine.ts:188-236` (process loop), `src/engine/engine.ts:132-141` (run method).

---

## Feature 4: Timeout Mechanics

### What it does

Defines the two timeout mechanisms: node-level timeouts (request spends too long at a single node) and deadline-level timeouts (request exceeds its absolute deadline during edge transit).

### How it works internally

**Node-level timeout** (`scheduleNodeTimeout` in `engine.ts:708-726`):

```typescript
private scheduleNodeTimeout(nodeId: string, request: Request): void {
  const nodeTimeoutUs = this.nodeTimeoutUsById.get(nodeId)
  if (!nodeTimeoutUs) return

  const timeoutAt = this.clock + nodeTimeoutUs
  const effectiveTimeoutAt = request.deadline < timeoutAt ? request.deadline : timeoutAt

  this.eventQueue.insert(
    createEvent('request-timeout', nodeId, request.id,
      { request, nodeArrivalTime: this.clock, scope: 'node' }, effectiveTimeoutAt)
  )
}
```

Scheduled when a request is admitted to a node (`handleRequestArrival`). The timeout fires at `min(clock + nodeTimeout, request.deadline)`. If the request completes processing before the timeout fires, the timeout event is a no-op (request already removed from `requestById`).

The `scope: 'node'` data field triggers the `cancelRequest` path in the timeout handler, which removes the request from the node's queue or active workers.

**Edge-transit timeout** (in `enqueueEdgeTransfer`, `engine.ts:757-766`):

Fires when `request.deadline <= arrivalTime` — the request would arrive at the target node after its deadline. Also fires on packet loss (silently dropped). Uses `scope: 'in-flight'` to distinguish from node timeouts.

**Deadline origin**: `request.deadline = createdAt + msToMicro(defaultTimeoutMs)`, where `defaultTimeoutMs = topology.global.defaultTimeout`.

**Effective timeout** per node: `min(processing.timeout, request.deadline - currentTime)`. The processing timeout is per-node; the deadline is per-request (global).

### Explored in

`src/engine/engine.ts:708-726` (node timeout), `src/engine/engine.ts:757-766` (edge timeout), `src/engine/engine.ts:438-466` (timeout handler).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Request Pattern Configuration** | `request-generated` event as the lifecycle entry point | Pattern-generated arrival times | `WorkloadGenerator.generateNext()` → `request-generated` |
| **Request Flow Direction & Topology Rules** | `request-forwarded` and `request-arrival` as routing boundary events | Routing decisions that determine next hop | `resolveTarget()` → forward/arrive |
| **Request Type Model** | Request properties (type, size, priority) that travel through the lifecycle | Type definitions | `Request` fields |
| **Edge Properties & Defaults** | Edge transfer as a lifecycle transition (forwarded → in-transit → arrived) | Edge loss/error/latency properties | `enqueueEdgeTransfer` pipeline |
| **Throughput Calculation** | `request-complete` events that increment throughput counters | — | Terminal success events |
| **Queue Depth Calculation** | Arrival admission → queued/processing state transitions | Queue state changes | `handleArrival`, `handleCompletion` |
| **Request Rejection Behaviour** | `request-rejected` as a terminal lifecycle event | — | Rejection events with reasons |
| **Cost Calculation & Budgeting** | Request lifecycle duration for cost calculation | — | `createdAt` to terminal event time |
| **Simulation Validation & Pattern Accuracy** | Event sequence as validation input | — | Event ordering, determinism |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| `src/engine/engine.ts` | Implement handlers for remaining 11 event types | Complete the lifecycle for infrastructure/resilience events | ~200 lines total |
| `src/engine/core/events.ts` | Add `processing-start` emission in `GGcKNode.startProcessing` | Currently unused; emitting it would complete the lifecycle state machine | ~5 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| Lifecycle State Machine | `engine.ts:238-488` | `Request`, `SimulationEvent` | All `handle*` methods |
| Event Types & Priority | `events.ts:4-36, 71-108` | `EventType`, `EventPriority`, `SimulationEvent` | `createEvent()`, `getDefaultPriority()` |
| Event Processing Loop | `engine.ts:188-236` | — | `processEvents()` |
| Timeout Mechanics | `engine.ts:708-726, 438-466` | — | `scheduleNodeTimeout()`, `handleRequestTimeout()` |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | Timeout priority (4) being the lowest ensures correct "just-in-time completion" semantics | Design decision (implemented) | If timeout had higher priority, requests completing at their deadline would be incorrectly timed out |
| 2 | `processing-start` event should eventually be emitted for complete lifecycle tracing | Observation | The event type exists but is never emitted; debug panels cannot show processing start time directly |
| 3 | The 11 stub event types will be implemented in future work | Assumption | Infrastructure/resilience simulation features depend on these |
| 4 | Microsecond clock precision is sufficient for all simulation scenarios | Assumption | Nanosecond precision would require `bigint` math changes but is unlikely to be needed |
| 5 | Terminal state tracking via `metadata.__terminal` is sufficient; no typed lifecycle state field needed | Implementation choice | A typed field would be cleaner but requires changing the `Request` interface |

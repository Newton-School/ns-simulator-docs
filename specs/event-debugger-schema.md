# Event Debugger — Data Model & Schema Changes

This document specifies the data model, type additions, and schema changes required to implement the event debugger features described in `event-debugger-prototypes.md`. It is organized by layer — engine core, worker protocol, renderer state — and explains what each new type represents, why it exists, where it lives, and how it connects to existing types.

---

## Table of Contents

1. [Current Data Flow](#current-data-flow)
2. [Engine Core — New Types](#engine-core--new-types)
   - [DebugEvent](#debugevent)
   - [NodeSnapshot](#nodesnapshot)
   - [RequestLifecycle](#requestlifecycle)
   - [LifecyclePhase](#lifecyclephase)
   - [ExpectedPath](#expectedpath)
   - [AdmissionDecision](#admissiondecision)
3. [Engine Core — Modified Types](#engine-core--modified-types)
   - [SimulationEvent changes](#simulationevent-changes)
   - [SimulationEngine changes](#simulationengine-changes)
   - [RequestTracer changes](#requesttracer-changes)
4. [Worker Protocol — New Messages](#worker-protocol--new-messages)
   - [Inbound: DebugRequestMessage](#inbound-debugrequestmessage)
   - [Outbound: EventBatchMessage](#outbound-eventbatchmessage)
   - [Outbound: DebugSnapshotMessage](#outbound-debugsnapshotmessage)
5. [Simulation Output — New Fields](#simulation-output--new-fields)
   - [SimulationOutput.eventLog](#simulationoutputeventlog)
6. [Renderer State — New Types](#renderer-state--new-types)
   - [DebugSession](#debugsession)
   - [DebugControls](#debugcontrols)
   - [EventFilter](#eventfilter)
   - [CanvasDebugState](#canvasdebugstate)
7. [Renderer State — Modified Types](#renderer-state--modified-types)
   - [SimulationState changes](#simulationstate-changes)
8. [Store Shape — New Slices](#store-shape--new-slices)
9. [Complete Type Inventory](#complete-type-inventory)

---

## Current Data Flow

Before detailing the new types, here is how data currently flows from engine to renderer. Every new type plugs into one of these channels.

```
┌─────────────────────────┐
│  SimulationEngine       │
│  ┌───────────────────┐  │
│  │ MinHeap<SimEvent>  │──┤── processEvents() loop
│  │ GGcKNode[]         │  │       │
│  │ RoutingTable       │  │       ├── onProgress(percent, eventsProcessed)
│  │ MetricsCollector   │  │       ├── onSnapshot(TimeSeriesSnapshot)
│  │ RequestTracer      │  │       └── [events consumed and discarded]
│  └───────────────────┘  │
│            │             │
│   getResults() ──────────┤──> SimulationOutput
└─────────────────────────┘
            │
     postMessage()
            │
            ▼
┌─────────────────────────┐
│  simulation.worker.ts   │
│  chunked execution loop │──── post('progress', ...)
│                         │──── post('snapshot', ...)
│                         │──── post('complete', { output })
└─────────────────────────┘
            │
     onmessage
            │
            ▼
┌─────────────────────────┐
│  useSimulation hook     │
│  state: SimulationState │──── status, progress, eventsProcessed
│                         │──── snapshot: TimeSeriesSnapshot
│                         │──── results: SimulationOutput
└─────────────────────────┘
            │
            ▼
┌─────────────────────────┐
│  ResultsTray component  │
│  (aggregate display)    │
└─────────────────────────┘
```

**The gap:** Events are consumed inside `processEvents()` and never leave the engine. The debugger needs them to reach the renderer.

---

## Engine Core — New Types

**File:** `src/engine/core/debugTypes.ts` (new file)

All debugger-specific types live in a dedicated file to avoid bloating the existing `events.ts` and `types.ts` which define the simulation's runtime contract.

---

### DebugEvent

The renderer-safe representation of a `SimulationEvent`. The engine's internal `SimulationEvent` uses `bigint` timestamps and carries raw `Request` objects with circular references (request → spans → request). `DebugEvent` is a serializable, flattened projection designed to cross the worker boundary via `postMessage` (which cannot transfer `bigint` or circular structures).

```typescript
export interface DebugEvent {
  /** Monotonic index assigned by the engine as events are processed. */
  index: number

  /** Milliseconds since simulation start (converted from SimulationEvent.timestamp via microToMs). */
  timestampMs: number

  /** Event type — same enum as SimulationEvent.type. */
  type: EventType

  /** Node where this event was handled. */
  nodeId: string

  /** Request this event acts on. */
  requestId: string

  /**
   * Derived status for display purposes.
   * Not stored on SimulationEvent — computed during projection.
   */
  status: 'info' | 'success' | 'warn' | 'danger'

  /**
   * Terminal reason code. Present only for request-rejected and request-timeout events.
   * Values come from GGcKNode.handleArrival ('capacity_exceeded', 'node_failed'),
   * SimulationEngine.applySecurityPolicy ('security_blocked'),
   * SimulationEngine.shouldFailAtNode ('node_error_rate'),
   * SimulationEngine.enqueueEdgeTransfer ('edge_error_rate'),
   * and timeout handlers ('node_timeout').
   */
  reason: string | null

  /**
   * Edge ID involved in this event. Present for request-forwarded and
   * request-arrival events that came from an edge transfer.
   * Extracted from event.data.edge.id.
   */
  edgeId: string | null

  /**
   * Human-readable description. Generated by the projection function
   * based on event type, node label, and reason.
   */
  message: string

  /**
   * Node state at the time of this event. Populated for all events
   * when debug mode is active; for terminal events (rejected/timeout)
   * always populated regardless of mode.
   */
  nodeState: NodeSnapshot | null

  /** Priority tier from EventPriority (0=SYSTEM, 1=ARRIVAL, 2=PROCESSING, 3=DEPARTURE, 4=TIMEOUT). */
  priority: number
}
```

**Why `index` exists:** Events can share timestamps (the min-heap breaks ties by priority). The monotonic index provides a stable, unique sort key for the event log UI and for the step-through debugger.

**Why `status` is derived, not stored:** The engine's `SimulationEvent` has no status field — status is implicit in the event type. The projection function maps:

| EventType | Status |
|---|---|
| `request-rejected` | `danger` |
| `request-timeout` | `warn` |
| `processing-complete`, `request-complete`, `cache-hit` | `success` |
| everything else | `info` |

---

### NodeSnapshot

A point-in-time capture of a `GGcKNode`'s state. This is a subset of `NodeState` (from `src/engine/core/types.ts`) enriched with the node's configured limits, so the renderer can show both current values and capacity.

```typescript
export interface NodeSnapshot {
  /** Current node status. From GGcKNode.getState().status. */
  status: 'idle' | 'busy' | 'saturated' | 'failed'

  /** Number of workers currently processing requests. From getState().activeWorkers. */
  activeWorkers: number

  /** Maximum worker count. From ComponentNode.queue.workers. */
  maxWorkers: number

  /** Number of requests waiting in queue. From getState().queueLength. */
  queueLength: number

  /** Maximum system capacity K. From ComponentNode.queue.capacity. */
  capacity: number

  /** activeWorkers / maxWorkers. From getState().utilization. */
  utilization: number

  /** activeWorkers + queueLength. From getState().totalInSystem. */
  totalInSystem: number
}
```

**Why this duplicates parts of `NodeState`:** `NodeState` (in `types.ts`) is the engine's internal runtime type — it doesn't carry configured limits (`maxWorkers`, `capacity`). The debugger needs both observed and configured values to explain admission decisions. Rather than modify the engine's runtime type (which would couple the simulation core to the debugger), `NodeSnapshot` wraps and extends it.

**Relationship to `TimeSeriesSnapshot`:** The existing `TimeSeriesSnapshot` (in `analysis/output.ts`) captures node state once per simulated second. `NodeSnapshot` captures it per event — much higher resolution but only during debug mode. They share the same underlying `GGcKNode.getState()` data source.

---

### RequestLifecycle

The complete journey of a single request through the topology, assembled from individual `DebugEvent` records. This is the data model for the step-through debugger, lifecycle rail, sequence diagram, and stack trace views.

```typescript
export interface RequestLifecycle {
  /** The request being traced. */
  requestId: string

  /** Ordered list of lifecycle phases, one per meaningful hop. */
  phases: LifecyclePhase[]

  /**
   * Terminal status of the request.
   * Derived from the last phase's event type.
   */
  terminalStatus: 'success' | 'rejected' | 'timeout' | 'in-flight'

  /**
   * If terminal, which node and why.
   * Null when terminalStatus is 'success' or 'in-flight'.
   */
  terminalNode: string | null
  terminalReason: string | null

  /** Total time from generation to terminal event, in ms. */
  totalLatencyMs: number

  /** The path the topology's edges define for this request (see ExpectedPath). */
  expectedPath: ExpectedPath

  /** The actual nodes visited, from Request.path[]. */
  actualPath: string[]
}
```

**Why `terminalStatus` has `in-flight`:** If the simulation ends (duration limit reached) while the request is still queued or being processed, it's not success/rejected/timeout — it's in-flight. The conservation check in `output.ts` already tracks this as `inFlight` count per node.

---

### LifecyclePhase

A single phase in a request's lifecycle. Maps one-to-one with a `DebugEvent` but adds contextual metadata that only makes sense in the context of a full lifecycle (e.g., phase name, hop index).

```typescript
export interface LifecyclePhase {
  /** Human-readable phase name derived from the node's label and event type.
   *  Example: "Auth", "Order Service", "Payment Canary".
   *  Falls back to nodeId if the node label is unavailable. */
  name: string

  /** Zero-based index in the lifecycle. */
  hopIndex: number

  /** The underlying debug event for this phase. */
  event: DebugEvent

  /**
   * Per-hop timing breakdown. Populated from RequestTraceSpan data when available.
   * Null for the first hop (no incoming edge) or when trace data is unavailable.
   */
  timing: PhaseTiming | null

  /**
   * Phase result — whether the request passed through this node or was stopped.
   * 'passed' = processing-complete or request-forwarded.
   * 'rejected' = request-rejected at this node.
   * 'timeout' = request-timeout at this node.
   * 'arrived' = request is here but hasn't completed yet (current step in debugger).
   */
  result: 'passed' | 'rejected' | 'timeout' | 'arrived'
}
```

---

### PhaseTiming

Per-hop time decomposition. Maps to `RequestTraceSpan` from `src/engine/tracer.ts` but uses plain numbers (ms) rather than BigInt.

```typescript
export interface PhaseTiming {
  /** Time spent waiting in this node's queue, in ms. From RequestTraceSpan.queueWait. */
  queueWaitMs: number

  /** Time spent being processed by a worker, in ms. From RequestTraceSpan.serviceTime. */
  serviceTimeMs: number

  /** Time spent on the incoming edge (network latency), in ms. From RequestTraceSpan.edgeLatency. */
  edgeLatencyMs: number

  /** Sum of all three: queue + service + edge. */
  totalMs: number

  /**
   * Absolute start time relative to request creation, in ms.
   * From RequestTraceSpan.start. Used for waterfall bar positioning.
   */
  startMs: number

  /**
   * Absolute end time relative to request creation, in ms.
   * From RequestTraceSpan.end.
   */
  endMs: number
}
```

**Why this wraps `RequestTraceSpan` instead of using it directly:** `RequestTraceSpan` is already a renderer-friendly type (uses `number` not `bigint`), but it lacks `totalMs` and uses generic field names (`start`/`end`) that don't self-document in the debugger context. `PhaseTiming` is a semantic rename with the derived total.

---

### ExpectedPath

The route a request *should* take if nothing fails, derived by walking the topology's edge graph from the source node.

```typescript
export interface ExpectedPath {
  /** Ordered list of node IDs from source to terminal leaf. */
  nodeIds: string[]

  /** The edges connecting consecutive nodes. nodeIds.length - 1 entries. */
  edgeIds: string[]

  /**
   * Whether this path is deterministic.
   * False when the topology has weighted/random routing or conditional edges,
   * meaning the actual path may legitimately differ from the expected path
   * even without failures.
   */
  deterministic: boolean
}
```

**How it's computed:** Walk from the source node's ID through `RoutingTable.getOutgoingEdges()`. At each node, pick the single sync edge (or the highest-weight edge if multiple). Stop when a node has no outgoing edges (leaf / terminal). If any node has multiple sync edges with no clear winner, mark `deterministic: false`.

**Why `deterministic` matters:** The Actual vs Expected Path Diff feature (Feature 11) compares these two paths. If the expected path isn't deterministic (e.g., a load balancer with 50/50 split), showing a "difference" is misleading — the actual path may be correct even though it differs from the expected path.

---

### AdmissionDecision

The exact state of the admission check at the moment a request was accepted or rejected by a node. This powers the Node Intake Lens feature (Feature 10).

```typescript
export interface AdmissionDecision {
  /** The node that made the decision. */
  nodeId: string

  /** Whether the request was admitted. */
  outcome: 'admitted' | 'rejected'

  /** The admission rule that was evaluated.
   *  'capacity' = activeWorkers + queueLength >= capacity (from GGcKNode.handleArrival).
   *  'node_failed' = node status is 'failed'.
   *  'security_blocked' = security policy blocked the request.
   */
  rule: 'capacity' | 'node_failed' | 'security_blocked'

  /** Node state at decision time. */
  nodeState: NodeSnapshot

  /**
   * Slot-level breakdown for the intake lens visualization.
   * Each slot is one "position" in the node's system (capacity K).
   */
  slots: {
    /** How many slots are occupied by active workers (blue in the UI). */
    activeWorkerSlots: number
    /** How many slots are occupied by queued requests (amber in the UI). */
    queuedSlots: number
    /** How many slots are available (would be empty in the UI). 0 when rejected. */
    availableSlots: number
  }

  /**
   * The admission equation values, for display.
   * activeWorkers + queueLength [operator] capacity
   */
  equation: {
    left: number    // activeWorkers + queueLength
    operator: '>=' | '<'
    right: number   // capacity
    result: boolean // true = rejected
  }
}
```

**Where it's populated:** Inside `GGcKNode.handleArrival()`, after the `currentLoad >= this.maxCapacity` check. The engine already has all three values at this point — the `AdmissionDecision` is just a structured projection.

---

## Engine Core — Modified Types

### SimulationEvent changes

**File:** `src/engine/core/events.ts`

No structural changes to the `SimulationEvent` interface itself. The `data: Record<string, unknown>` payload already carries event-specific context (`request`, `reason`, `edge`, `targetNodeId`, `nodeArrivalTime`, `scope`). The debugger reads from this bag via the `DebugEvent` projection function.

**New: `projectToDebugEvent` function** (in `src/engine/core/debugTypes.ts`):

```typescript
/**
 * Projects an internal SimulationEvent into a renderer-safe DebugEvent.
 * Called inside the engine's event processing loop when debug emission is active.
 *
 * @param event        The raw SimulationEvent being processed.
 * @param index        Monotonic counter incremented per event.
 * @param nodeState    GGcKNode.getState() at the time of this event, if available.
 * @param nodeConfig   The ComponentNode config for this event's nodeId.
 * @param nodeLabels   Map of nodeId → label for human-readable messages.
 */
export function projectToDebugEvent(
  event: SimulationEvent,
  index: number,
  nodeState: NodeState | null,
  nodeConfig: ComponentNode | null,
  nodeLabels: Map<string, string>
): DebugEvent
```

This function:
1. Converts `event.timestamp` from `bigint` to `number` via `microToMs`.
2. Extracts `reason` from `event.data.reason` (string cast).
3. Extracts `edgeId` from `(event.data.edge as EdgeDefinition)?.id`.
4. Derives `status` from `event.type` using the mapping table above.
5. Builds `message` from type + node label + reason (e.g., "Rejected at Payment Canary: capacity_exceeded").
6. Builds `NodeSnapshot` by merging `nodeState` with `nodeConfig.queue` limits.

---

### SimulationEngine changes

**File:** `src/engine/engine.ts`

New optional callbacks alongside existing `onProgress` and `onSnapshot`:

```typescript
export class SimulationEngine {
  onProgress?: (percent: number, eventsProcessed: number) => void
  onSnapshot?: (snapshot: TimeSeriesSnapshot) => void

  // ─── New ───────────────────────────────────────────────────────────────────
  /** When set, every processed event is projected and emitted. */
  onDebugEvent?: (event: DebugEvent) => void

  /** When set, admission decisions are emitted for the intake lens. */
  onAdmissionDecision?: (decision: AdmissionDecision) => void
  // ────────────────────────────────────────────────────────────────────────────
}
```

**Where they fire:**

`onDebugEvent` fires at the end of `handleEvent()`, after the type-specific handler returns. At this point the engine has advanced the clock, the node state reflects the event's effect, and all metadata is available:

```
// In processEvents(), after handleEvent(event):
if (this.onDebugEvent) {
  const node = this.nodes.get(event.nodeId)
  const nodeState = node?.getState() ?? null
  const nodeConfig = this.topology.nodes.find(n => n.id === event.nodeId) ?? null
  this.onDebugEvent(projectToDebugEvent(event, this.eventsProcessed, nodeState, nodeConfig, this.nodeLabelMap))
}
```

`onAdmissionDecision` fires inside `handleRequestArrival()` after the `GGcKNode.handleArrival()` call returns — for both admitted and rejected requests. This captures the exact state at the admission boundary.

**Performance consideration:** `onDebugEvent` is only wired up by the worker when debug mode is requested. During normal (non-debug) runs, the callback is `undefined` and the `if` check short-circuits with zero overhead. When active, the `postMessage` cost is amortized by batching (see [EventBatchMessage](#outbound-eventbatchmessage)).

---

### RequestTracer changes

**File:** `src/engine/tracer.ts`

```typescript
export class RequestTracer {
  // ─── Existing ──────────────────────────────────────────────────────────────
  private readonly sampleRate: number
  // ...

  // ─── New ───────────────────────────────────────────────────────────────────
  /**
   * Set of request IDs that must always be traced regardless of sample rate.
   * Used by the debugger to force tracing for a specific request.
   */
  private readonly forcedRequestIds = new Set<string>()

  /** Force-trace a specific request. Called when the user debugs a request. */
  forceTrace(requestId: string): void {
    this.forcedRequestIds.add(requestId)
  }

  /** Remove force-trace for a request. */
  unforceTrace(requestId: string): void {
    this.forcedRequestIds.delete(requestId)
  }
  // ────────────────────────────────────────────────────────────────────────────
}
```

**Modified `shouldTrace`:** The existing `shouldTrace` method adds a check at the top:

```typescript
shouldTrace(requestId: string): boolean {
  if (this.forcedRequestIds.has(requestId)) return true  // ← new
  if (this.traces.has(requestId)) return true
  const hash = this.hash32(requestId)
  const normalized = hash / 0x100000000
  return normalized < this.sampleRate
}
```

**Why:** The default `traceSampleRate` is 1% (`DEFAULT_SCENARIO_STATE.global.traceSampleRate`). When the user debugs request `req-9148`, we need its spans regardless of whether it falls in the 1% sample. `forceTrace` guarantees it.

---

## Worker Protocol — New Messages

**File:** `src/engine/worker/protocols.ts`

---

### Inbound: DebugRequestMessage

Tells the worker to enable debug event emission for a specific request (or all requests).

```typescript
export interface DebugRequestMessage {
  type: 'debug-request'
  payload: {
    /**
     * Which request to debug.
     * 'all' = emit events for every request (full event log mode).
     * A specific requestId = emit events only for that request (focused debug mode).
     */
    target: 'all' | string

    /**
     * When true, force-trace the target request so its spans are always collected
     * regardless of traceSampleRate.
     */
    forceTrace: boolean
  }
}

export interface DebugStopMessage {
  type: 'debug-stop'
}
```

**Updated union:**

```typescript
export type WorkerInboundMessage =
  | RunMessage
  | PauseMessage
  | ResumeMessage
  | StopMessage
  | StepMessage
  | DebugRequestMessage    // new
  | DebugStopMessage       // new
```

---

### Outbound: EventBatchMessage

Streams batches of `DebugEvent` records from the worker to the main thread.

```typescript
export interface EventBatchMessage {
  type: 'event-batch'
  payload: {
    events: DebugEvent[]
  }
}
```

**Batching strategy:** The worker accumulates `DebugEvent` records in a buffer. The buffer is flushed:
1. Every `CHUNK_SIZE` (20,000) events — alongside the existing `await sleep(0)` yield point in `runChunked`.
2. When the buffer reaches a size threshold (e.g., 500 events) — to keep latency bounded during slow simulations.
3. On simulation completion — flush any remaining events before posting `complete`.

**Why batching:** `postMessage` has per-call overhead (structured clone). Sending one message per event at 100k+ events/second would saturate the message channel. Batching amortizes the cost.

**Serialization:** `DebugEvent` uses only `number`, `string`, `null`, and plain objects — no `bigint`, `Map`, or class instances. It survives `postMessage`'s structured clone algorithm without transformation.

---

### Outbound: DebugSnapshotMessage

Emits a `RequestLifecycle` for the focused request whenever debug state changes (after each step, or on completion).

```typescript
export interface DebugSnapshotMessage {
  type: 'debug-snapshot'
  payload: {
    lifecycle: RequestLifecycle
  }
}
```

**When emitted:** After each chunk completes (during `runChunked`), if a specific request is being debugged, the worker assembles the lifecycle from accumulated `DebugEvent` records and trace spans.

**Updated union:**

```typescript
export type WorkerOutboundMessage =
  | ProgressMessage
  | SnapshotMessage
  | CompleteMessage
  | ErrorMessage
  | EventBatchMessage        // new
  | DebugSnapshotMessage     // new
```

---

## Simulation Output — New Fields

**File:** `src/engine/analysis/output.ts`

### SimulationOutput.eventLog

When debug mode was active during the run, the full event log is included in the output so it can be explored post-run without needing the worker alive.

```typescript
export interface SimulationOutput {
  // ─── Existing fields ───────────────────────────────────────────────────────
  summary: SimulationSummary
  perNode: Record<string, PerNodeMetrics>
  timeSeries: TimeSeriesSnapshot[]
  traces: RequestTrace[]
  causalGraph: CausalGraph | null
  sloBreaches: SLOBreach[]
  invariantViolations: InvariantViolation[]
  littlesLawCheck: LittlesLawResult[]
  warmupAdequacy: WarmupAdequacy
  conservationCheck: ConservationResult[]
  seed: string
  reproducible: true
  eventsProcessed: number
  simulationDuration: number
  warmupDuration: number

  // ─── New ───────────────────────────────────────────────────────────────────
  /**
   * Full event log collected during the run.
   * Only populated when debug mode was active (debug-request message was sent).
   * Null during normal (non-debug) runs to avoid memory overhead.
   */
  eventLog: DebugEvent[] | null

  /**
   * Pre-assembled lifecycle for the debugged request.
   * Null during non-debug runs or when target was 'all'.
   */
  debuggedLifecycle: RequestLifecycle | null
}
```

**Memory consideration:** A 60-second simulation at 100 RPS with a 7-node topology generates roughly 4,200 events (100 requests × ~6 events each × ~7 hops). Each `DebugEvent` is ~200 bytes serialized. Total: ~840 KB — well within budget. At higher RPS (10,000), the log could reach 80+ MB. Options:
- Cap the event log at a configurable limit (e.g., 50,000 events) and discard oldest.
- Only record events for the debugged request when `target` is a specific ID.
- Let the worker stream events but not store them in the output.

---

## Renderer State — New Types

**File:** `src/renderer/src/types/debug.ts` (new file)

---

### DebugSession

The renderer-side state for an active debug session. Managed by a new `useDebugger` hook.

```typescript
export interface DebugSession {
  /** Whether debug mode is active. */
  active: boolean

  /** The request being debugged, or 'all' for full event log mode. */
  target: 'all' | string

  /**
   * All debug events received from the worker.
   * When target is a specific requestId, this contains only that request's events.
   * When target is 'all', this contains everything.
   */
  events: DebugEvent[]

  /**
   * The assembled lifecycle for the debugged request.
   * Null when target is 'all' or when not enough events have arrived yet.
   */
  lifecycle: RequestLifecycle | null

  /**
   * Current position in the lifecycle during step-through debugging.
   * Index into lifecycle.phases[].
   */
  currentPhaseIndex: number

  /** Auto-play state. */
  playback: {
    playing: boolean
    intervalMs: number    // default 800
    timerId: number | null
  }
}
```

---

### DebugControls

The actions the debug UI can dispatch.

```typescript
export interface DebugControls {
  /** Enter debug mode for a specific request. */
  startDebug: (requestId: string) => void

  /** Enter event log mode (all events). */
  startEventLog: () => void

  /** Exit debug mode. */
  stopDebug: () => void

  /** Advance to next phase. */
  stepForward: () => void

  /** Go back to previous phase. */
  stepBack: () => void

  /** Jump to the first phase with the given result. */
  jumpTo: (result: 'rejected' | 'timeout') => void

  /** Start auto-play. */
  play: () => void

  /** Pause auto-play. */
  pause: () => void

  /** Jump to a specific phase index. */
  goToPhase: (index: number) => void
}
```

---

### EventFilter

Parsed representation of the filter bar query.

```typescript
export interface EventFilter {
  /** Raw query string as typed by the user. */
  raw: string

  /** Parsed filter clauses. Evaluated as OR within a group, AND across groups. */
  clauses: EventFilterClause[]
}

export type EventFilterClause =
  | { field: 'requestId'; operator: 'eq'; value: string }
  | { field: 'nodeId'; operator: 'eq'; value: string }
  | { field: 'type'; operator: 'eq'; value: EventType }
  | { field: 'status'; operator: 'eq'; value: DebugEvent['status'] }
  | { field: 'reason'; operator: 'eq'; value: string }
  | { field: 'timestampMs'; operator: 'gt' | 'lt' | 'gte' | 'lte'; value: number }
```

**Filter syntax:** The prototypes show queries like `status:rejected OR node:payment-svc-v2`. The parser maps:
- `request:<id>` → `{ field: 'requestId', operator: 'eq', value: id }`
- `node:<id>` → `{ field: 'nodeId', operator: 'eq', value: id }`
- `status:<level>` → `{ field: 'status', operator: 'eq', value: level }`
- `type:<eventType>` → `{ field: 'type', operator: 'eq', value: eventType }`
- `reason:<code>` → `{ field: 'reason', operator: 'eq', value: code }`

---

### CanvasDebugState

State that drives the canvas debug overlay (Feature 5). Consumed by node and edge components to apply visual highlights.

```typescript
export interface CanvasDebugState {
  /** Whether debug overlay is active. When false, all highlights are cleared. */
  active: boolean

  /** Node IDs on the debugged request's path. Non-path nodes are dimmed. */
  pathNodeIds: Set<string>

  /** Edge IDs on the debugged request's path. Non-path edges are dimmed. */
  pathEdgeIds: Set<string>

  /** The node currently highlighted (blue glow). Null when between nodes. */
  currentNodeId: string | null

  /** The edge currently highlighted (blue glow). Null when at a node. */
  currentEdgeId: string | null

  /**
   * Highlight mode for the current element.
   * 'active' = blue glow (normal progression).
   * 'rejected' = red glow (terminal failure).
   */
  highlightMode: 'active' | 'rejected'

  /**
   * Packet dot position in React Flow coordinates.
   * Derived from the current node/edge's position on the canvas.
   * Null when debug overlay is inactive.
   */
  packetPosition: { x: number; y: number } | null
}
```

**How `packetPosition` is computed:** When the current event is at a node, the position is the node's center (from React Flow `getNodes()`, using `node.position.x + node.width/2`, `node.position.y + node.height/2`). When the current event is on an edge (request-forwarded), the position is the edge midpoint (computed from the source and target node centers).

---

## Renderer State — Modified Types

### SimulationState changes

**File:** `src/renderer/src/hooks/useSimulation.ts`

The `SimulationState` interface gains debug-related fields:

```typescript
export interface SimulationState {
  // ─── Existing ──────────────────────────────────────────────────────────────
  status: SimulationStatus
  progress: number
  eventsProcessed: number
  snapshot: TimeSeriesSnapshot | null
  results: SimulationOutput | null
  error: string | null

  // ─── New ───────────────────────────────────────────────────────────────────
  /** Debug events received via event-batch messages. */
  debugEvents: DebugEvent[]

  /** Lifecycle snapshot for the focused request, from debug-snapshot messages. */
  debugLifecycle: RequestLifecycle | null
}
```

The `spawnWorker` handler gains two new cases in the `switch`:

```typescript
case 'event-batch':
  setState(s => ({
    ...s,
    debugEvents: [...s.debugEvents, ...msg.payload.events]
  }))
  break

case 'debug-snapshot':
  setState(s => ({
    ...s,
    debugLifecycle: msg.payload.lifecycle
  }))
  break
```

**Optimization note:** Appending to `debugEvents` via spread creates a new array on every batch. For high-event-count runs, this should use a ref-based buffer or an append-only data structure to avoid re-renders on every batch. The `DebugSession` in the store could hold events in a `useRef` and only trigger re-renders when the user scrolls or the current phase changes.

---

## Store Shape — New Slices

**File:** `src/renderer/src/store/useStore.ts`

New state slice alongside the existing graph/file/scenario state:

```typescript
interface RFState {
  // ─── Existing ──────────────────────────────────────────────────────────────
  nodes: Node[]
  edges: Edge[]
  simulationMetricsByNode: Record<string, NodeSimulationMetrics>
  fileName: string | null
  isUnsaved: boolean
  scenario: ScenarioState

  // ─── New: Debug ────────────────────────────────────────────────────────────
  debugSession: DebugSession | null

  /** Canvas overlay state consumed by node/edge components. */
  canvasDebugState: CanvasDebugState

  // ─── New: Actions ──────────────────────────────────────────────────────────
  setDebugSession: (session: DebugSession | null) => void
  updateDebugSession: (updater: (current: DebugSession) => DebugSession) => void
  setCanvasDebugState: (state: CanvasDebugState) => void
}
```

**Why it's in the store, not local state:** The canvas debug state must be readable by every node and edge component on the canvas (to apply dimming and highlighting). Putting it in the Zustand store allows `BaseNode`, `ServiceNode`, `ComputeNode`, `SecurityNode`, and `PacketEdge` to subscribe to the slice they need via a shallow selector, just like `useFlowStore` selects the graph slice.

---

## Complete Type Inventory

Summary of every new and modified type, organized by file.

### New files

| File | Types | Purpose |
|---|---|---|
| `src/engine/core/debugTypes.ts` | `DebugEvent`, `NodeSnapshot`, `RequestLifecycle`, `LifecyclePhase`, `PhaseTiming`, `ExpectedPath`, `AdmissionDecision`, `projectToDebugEvent()` | Engine-side debug data model |
| `src/renderer/src/types/debug.ts` | `DebugSession`, `DebugControls`, `EventFilter`, `EventFilterClause`, `CanvasDebugState` | Renderer-side debug state |

### Modified files

| File | Change |
|---|---|
| `src/engine/worker/protocols.ts` | Add `DebugRequestMessage`, `DebugStopMessage` to inbound union. Add `EventBatchMessage`, `DebugSnapshotMessage` to outbound union. |
| `src/engine/engine.ts` | Add `onDebugEvent` and `onAdmissionDecision` optional callbacks. Call `projectToDebugEvent` in `processEvents` loop. Emit `AdmissionDecision` in `handleRequestArrival`. Add `nodeLabelMap` built from topology. |
| `src/engine/tracer.ts` | Add `forcedRequestIds` set, `forceTrace()`, `unforceTrace()` methods. Update `shouldTrace()` to check forced set first. |
| `src/engine/worker/simulation.worker.ts` | Handle `debug-request` and `debug-stop` messages. Wire `engine.onDebugEvent` to buffer and flush via `EventBatchMessage`. Wire `engine.onAdmissionDecision` if needed. Build and post `DebugSnapshotMessage` after chunks when focused request is being debugged. |
| `src/engine/analysis/output.ts` | Add `eventLog: DebugEvent[] \| null` and `debuggedLifecycle: RequestLifecycle \| null` to `SimulationOutput`. Pass through from engine in `generateSimulationOutput`. |
| `src/renderer/src/hooks/useSimulation.ts` | Add `debugEvents` and `debugLifecycle` to `SimulationState`. Handle `event-batch` and `debug-snapshot` in worker message handler. Add `debugRequest()` and `debugStop()` to controls. |
| `src/renderer/src/store/useStore.ts` | Add `debugSession`, `canvasDebugState`, and their setters to `RFState`. |
| `src/renderer/src/types/ui.ts` | No changes — `CanvasDebugState` lives in the new `debug.ts` file. |

### Unchanged files

| File | Why no changes |
|---|---|
| `src/engine/core/events.ts` | `SimulationEvent` interface untouched. `DebugEvent` is a projection, not a modification. |
| `src/engine/core/types.ts` | `NodeState`, `ComponentNode`, `EdgeDefinition` unchanged. `NodeSnapshot` wraps rather than extends. |
| `src/engine/nodes/GGcKNode.ts` | No interface changes. `handleArrival` already returns `ArrivalResult` with reason. The engine calls `getState()` externally. |
| `src/engine/routing.ts` | `RoutingTable` unchanged. Expected path computation uses the existing `getOutgoingEdges` public method. |
| `src/engine/metrics.ts` | Metrics collection unchanged. Debug features read from events, not metrics. |

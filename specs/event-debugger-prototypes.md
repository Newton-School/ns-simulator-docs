# Event Debugger & Log System — Prototype Feature Specification

This document describes the features explored across five HTML prototypes for the NS Simulator's event debugging and request lifecycle inspection system. It is written from a feature perspective: what each capability does, why it exists, how it works internally, what engine data it consumes, and what components it requires to be built.

The prototypes were generated as static HTML mockups to explore different approaches to the same core problem: the simulator currently runs to completion and produces aggregate results (`SimulationOutput`), but users have no way to inspect **individual events** as they happen, trace a **single request** through its lifecycle, or understand **why** a specific node rejected or timed out a request. The event debugger fills that gap.

---

## Table of Contents

1. [Problem Context](#problem-context)
2. [Feature 1 — Event Log](#feature-1--event-log)
3. [Feature 2 — Request Detail Inspector](#feature-2--request-detail-inspector)
4. [Feature 3 — Request Trace Waterfall](#feature-3--request-trace-waterfall)
5. [Feature 4 — Step-Through Request Debugger](#feature-4--step-through-request-debugger)
6. [Feature 5 — Canvas Debug Overlay](#feature-5--canvas-debug-overlay)
7. [Feature 6 — Request Path Mini-Map](#feature-6--request-path-mini-map)
8. [Feature 7 — Request Lifecycle Rail](#feature-7--request-lifecycle-rail)
9. [Feature 8 — Sequence Diagram Debugger](#feature-8--sequence-diagram-debugger)
10. [Feature 9 — Stack Trace Debugger](#feature-9--stack-trace-debugger)
11. [Feature 10 — Node Intake Lens](#feature-10--node-intake-lens)
12. [Feature 11 — Actual vs Expected Path Diff](#feature-11--actual-vs-expected-path-diff)
13. [Feature 12 — State Machine View](#feature-12--state-machine-view)
14. [Feature 13 — Event Log Display Variants](#feature-13--event-log-display-variants)
15. [Layout Options](#layout-options)
16. [Engine Integration Requirements](#engine-integration-requirements)
17. [Prototype-to-Feature Map](#prototype-to-feature-map)

---

## Problem Context

### What exists today

The simulation pipeline today works as follows:

1. `useTopologySerializer` converts the React Flow canvas into a `TopologyJSON`.
2. `useSimulation` posts the topology to a Web Worker running `SimulationEngine`.
3. The engine processes events through a min-heap priority queue, dispatching each `SimulationEvent` to `handleEvent()`, which routes to type-specific handlers (`handleRequestGenerated`, `handleRequestArrival`, `handleProcessingComplete`, `handleRequestForwarded`, `handleRequestComplete`, `handleRequestTimeout`, `handleRequestRejected`).
4. Every 1 second of sim-time, the engine emits a `TimeSeriesSnapshot` (per-node queue length, active workers, utilization, status).
5. On completion, the engine returns a `SimulationOutput` containing: aggregate summary, per-node metrics (`PerNodeMetrics`), time series, sampled traces (`RequestTrace[]`), SLO breaches, Little's Law checks, conservation checks, and warmup adequacy.
6. `ResultsTray` renders this as aggregate tables and health checks.

### What's missing

- **No event-level visibility.** The engine processes events internally but does not expose them to the renderer. Users see aggregate metrics but cannot inspect individual events or understand the sequence of decisions that led to a rejection.
- **No single-request tracing in the UI.** The `RequestTracer` collects span data (arrival time, queue wait, service time, departure time per node), but this data only appears in the final `traces` array. There is no way to follow one request through the topology in real-time.
- **No debugging controls.** The worker supports `pause`/`resume`/`step(count)` messages (see `simulation.worker.ts` — `runChunked` processes 20,000 events per chunk with `await sleep(0)` for message pickup), but the renderer's `SimulationControls` only exposes Run/Pause/Resume/Stop. There is no step-through mode or request-level debugging.
- **No canvas feedback during simulation.** Nodes on the canvas show static configuration. There is no visual indication of which nodes are processing, which are saturated, or where a specific request currently is.

### What the prototypes explore

The five prototypes collectively explore ~13 distinct features that address these gaps. Each feature is documented below independently of which prototype introduced it.

---

## Feature 1 — Event Log

### What it does

A scrollable, filterable table of every `SimulationEvent` processed by the engine during a run. This is the foundational display — most other features build on top of it.

### Why it exists

Aggregate metrics hide causality. When `ResultsTray` shows "342 rejections at payment-svc-v2", the user's next question is always "which requests were rejected, when, and what was the node state at that moment?" The event log answers this by exposing the raw event stream.

### How it works internally

**Data source:** Each `SimulationEvent` (defined in `src/engine/core/events.ts`) carries:

```typescript
{
  timestamp: bigint,     // microseconds since sim start
  type: EventType,       // 'request-generated' | 'request-arrival' | 'processing-complete' | ...
  nodeId: string,        // which GGcKNode this event targets
  requestId: string,     // which Request object this event acts on
  data: Record<string, unknown>,  // event-specific payload (request object, reason, edge, etc.)
  priority: number       // tie-breaking priority from EventPriority
}
```

The engine currently consumes events in `processEvents()` and discards them after handling. To power the event log, the engine needs to emit events to the renderer — either by buffering them in the worker and streaming via the existing `postMessage` protocol, or by adding a new `EventsMessage` type to the worker's outbound protocol (`src/engine/worker/protocols.ts`).

**Filtering:** The prototypes show a query-syntax filter bar (e.g., `status:rejected OR node:payment-svc-v2`, `request:req-9148`). This requires client-side filtering across the event fields:
- `request:<id>` — match `requestId`
- `node:<id>` — match `nodeId`
- `status:<level>` — match derived status (rejected/timeout/success/info)
- `type:<eventType>` — match `EventType` directly
- Boolean operators (OR, AND)

**Row data per event:**
- Timestamp (converted from microseconds via `microToMs` from `src/engine/core/time.ts`)
- Request ID
- Event type
- Node ID
- Human-readable message (derived from event type + data payload)
- Status badge (derived: `request-rejected` → danger, `request-timeout` → warn, `processing-complete` → success, everything else → info)
- Reason code (extracted from `event.data.reason` — values like `capacity_exceeded`, `node_failed`, `node_timeout`, `security_blocked`, `edge_error_rate` come from the engine's rejection/timeout handlers)

**Summary badges:** The filter bar shows aggregate counts ("3 rejected", "1 timeout") computed by reducing the visible event set.

### What components it requires

- **Engine-side:** An event emission mechanism. Options: (a) a ring buffer in `SimulationEngine` that the worker drains periodically, (b) a new `EventBatchMessage` in the worker protocol, (c) a post-run event log stored alongside `SimulationOutput`.
- **Renderer-side:** An `EventLog` component with virtual scrolling (event counts can reach tens of thousands), a filter parser, and row click handling that drives the detail inspector.

### Explored in

Prototype 1 (Options A, B, C), Prototype 2, Prototype 3 (DevTools Table, Waterfall), Prototype 5 (Filmstrip frames).

---

## Feature 2 — Request Detail Inspector

### What it does

When the user clicks an event log row, a detail panel shows the full context of that event: all known metadata, the request's journey so far, and the node's runtime state at the time of the event.

### Why it exists

An event row shows *what* happened. The detail inspector answers *why*. For a `request-rejected` event, the user needs to see:
- What was the rejection reason? (`capacity_exceeded` means `activeWorkers + queue.length >= maxCapacity` in `GGcKNode.handleArrival`)
- What was the queue state? (queue length, active workers, capacity — the three values that determine admission in the G/G/c/K model)
- What path did the request take to get here? (which nodes did it pass through before being rejected?)

### How it works internally

**Key-value metadata display:** Pulls directly from the `SimulationEvent` fields and `event.data`:
- Request ID, Node ID, Event type, Timestamp
- Reason code (from `event.data.reason`)
- Edge ID (from `event.data.edge`, if the event is a forwarding event)

**Node runtime state at event time:** This is the critical data the prototypes emphasize. At the moment a rejection occurs, the user needs to see `GGcKNode.getState()` values:

```typescript
// from NodeState in src/engine/core/types.ts
{
  id: string,
  status: 'idle' | 'busy' | 'saturated' | 'failed',
  activeWorkers: number,
  queueLength: number,
  utilization: number,        // activeWorkers / maxWorkers
  totalInSystem: number       // activeWorkers + queueLength
}
```

Plus the node's configured capacity (`queue.capacity`, `queue.workers`) from the `ComponentNode` definition. The prototypes display this as: "Queue length: 100", "Workers: 8/8", "Capacity: 100".

**Trace waterfall:** The detail panel also shows the request's per-hop timing breakdown — see [Feature 3](#feature-3--request-trace-waterfall).

### What components it requires

- **Engine-side:** Events need to carry or reference `NodeState` at the time of the event. Currently `GGcKNode.getState()` is only called during snapshot emission (`takeSnapshot()`). The engine would need to either (a) embed a state snapshot in the event's `data` payload for terminal events, or (b) provide a way to reconstruct node state at a given timestamp from the time series.
- **Renderer-side:** A `RequestDetail` panel component. Receives a selected event and renders KV pairs, the trace waterfall, and node state.

### Explored in

All five prototypes. Every prototype includes a detail panel triggered by clicking an event or lifecycle step.

---

## Feature 3 — Request Trace Waterfall

### What it does

A per-hop timing breakdown showing how long a request spent at each node — decomposed into queue wait, service time, and edge latency. Renders as horizontal bars per node, with the bar width proportional to time.

### Why it exists

When a request takes 71.9ms end-to-end, the user needs to know where that time was spent. Was it 30ms queued at order-svc-b? Was it 15ms on the network between redis and payment-svc-v2? The waterfall decomposes total latency into its constituent parts.

### How it works internally

**Data source:** The engine's `RequestTracer` (in `src/engine/tracer.ts`) collects `RequestSpan` objects per node:

```typescript
// from RequestSpan in src/engine/core/events.ts
{
  nodeId: string,
  arrivalTime: bigint,    // when the request entered the node
  queueWait: bigint,      // time spent waiting in queue
  serviceTime: bigint,    // time spent being processed
  departureTime: bigint   // when the request left the node
}
```

`RequestTracer.getTraces()` converts these into `RequestTraceSpan` objects:

```typescript
// from src/engine/tracer.ts
{
  nodeId: string,
  start: number,       // ms from request creation
  end: number,         // ms from request creation
  queueWait: number,   // ms
  serviceTime: number, // ms
  edgeLatency: number  // ms — inferred: start - previousSpan.end
}
```

The edge latency is derived, not directly measured — it's the gap between when the previous node released the request and when this node received it. This gap includes the stochastic edge latency sampled from `edge.latency.distribution` in `SimulationEngine.sampleEdgeLatencyUs()`.

**Rendering:** Each hop is a row. The bar fill width = `(hop.total / maxTotal) * 100%`. Rejected hops (where the request never entered processing) show a minimal red bar with "Rejected before processing" text.

**Limitation:** The `RequestTracer` is sample-based — it uses `traceSampleRate` (default 1%) to decide whether to trace a request, using FNV-1a hash of the request ID. For the debugger to work on arbitrary requests, the sample rate would need to be raised for debugged requests, or the engine would need to always trace when in debug mode.

### What components it requires

- **Engine-side:** Access to `RequestTrace.spans` for the selected request. In debug mode, tracing should be forced (100% sample rate) for the request being debugged.
- **Renderer-side:** A `TraceWaterfall` component. Takes `RequestTraceSpan[]` and renders proportional bars.

### Explored in

Prototype 1 (all options), Prototype 2 (detail panel), Prototype 4 (all views).

---

## Feature 4 — Step-Through Request Debugger

### What it does

Allows the user to follow a single request through the simulation one event at a time. The user presses "Debug Request" to enter debug mode, then uses Step/Play/Pause controls to advance through the request's lifecycle event by event. A "Next Rejection" / "Jump To Failure" button skips directly to the terminal event.

### Why it exists

The event log is post-hoc — it shows what happened after the fact. The step-through debugger lets users *experience* the request's journey in order, watching the system state change at each hop. This is the difference between reading a stack trace and stepping through code in a debugger.

### How it works internally

**Debug state:**

```
{
  active: boolean,           // whether debug mode is on
  currentIndex: number,      // which event in the request's lifecycle we're viewing
  requestId: string,         // the request being debugged
  events: SimulationEvent[], // all events for this request, ordered by timestamp
  timer: interval | null     // auto-play interval (null when paused/stopped)
}
```

**Controls:**

| Control | Action |
|---|---|
| Debug Request | Filter all events for a specific `requestId`, set `currentIndex = 0`, enter debug mode |
| Step | `currentIndex = min(currentIndex + 1, events.length - 1)` |
| Prev | `currentIndex = max(currentIndex - 1, 0)` |
| Play | Start interval that calls Step every 800-850ms. Button becomes "Pause" |
| Pause | Clear interval |
| Next Rejection / Jump To Failure | `currentIndex = events.findIndex(e => e.status === 'rejected')` |
| Reset | Exit debug mode, clear highlights |

**How events are filtered for a single request:** Walk the full event log and filter by `event.requestId === targetId`. The engine assigns request IDs in `WorkloadGenerator.generateNext()`. For branching requests (fan-out), the engine creates branch IDs like `req-9148::branch-1` in `cloneRequestForBranch()` — the debugger would need to decide whether to follow branches.

**Relationship to engine pause/step:** The worker already supports `step(count)` messages (see `simulation.worker.ts`). The prototype's step-through operates on a *recorded* event stream (post-run), not on live simulation stepping. A live version would require posting `step` messages to the worker and receiving individual events back, which is architecturally different from the current chunked execution model.

### What components it requires

- **Engine-side:** Either (a) a recorded event stream that can be replayed post-run, or (b) modifications to the worker protocol to support single-event stepping with event emission.
- **Renderer-side:** A `DebugControls` component (Step/Play/Prev/NextRejection/Reset buttons), debug state management (could be a `useDebugger` hook), and integration with the canvas overlay ([Feature 5](#feature-5--canvas-debug-overlay)).

### Explored in

Prototype 2 (primary feature), Prototype 4 (all three views), Prototype 5 (Filmstrip, State Machine).

---

## Feature 5 — Canvas Debug Overlay

### What it does

While debugging a request, the React Flow canvas visually highlights the request's current position: the active node glows, the active edge glows, non-path nodes dim, and an animated dot ("packet") moves along the path.

### Why it exists

The topology is already on screen. Using it as a spatial debugger lets users see *where* in the architecture the request is, not just which node ID is in the log. When a request is rejected at `payment-svc-v2`, the user sees the red glow on that specific node on the canvas, in the context of the surrounding topology.

### How it works internally

**Node highlighting:** Three visual states applied via CSS classes on React Flow nodes:
- `current` (blue border, 4px box-shadow ring, slight translateY(-2px) lift) — the node the request is currently at.
- `rejected` (red border, red ring) — the node where the request was terminally rejected.
- Dimmed (opacity: 0.38) — all nodes NOT on the request's path. Applied via a parent `debug-mode` class on the canvas container.

**Edge highlighting:** SVG path elements get `active` (blue, 5px stroke, drop-shadow glow) or `rejected` (red equivalent) classes. Non-path edges dim to 28% opacity.

**Packet dot animation:** An absolutely positioned 13px circle that moves to each event's canvas coordinates. The prototypes store `position: {x, y}` per event — in the real implementation, these coordinates would be derived from the React Flow node positions (the node's center or handle position).

**Coordination with existing canvas:** The existing `useHandleProximity` and `useMagneticSnap` hooks both operate on node handle positions. The debug overlay would need to:
1. Read node positions from the React Flow `getNodes()` API.
2. Compute edge midpoints from React Flow's edge internals.
3. Apply highlight classes without interfering with the existing selection system (the canvas already has `selected` state on nodes via React Flow's built-in selection).

### What components it requires

- **Renderer-side:** A `useDebugOverlay` hook that subscribes to debug state and applies CSS classes to React Flow nodes/edges. A `PacketDot` component that renders the animated position indicator. Modifications to existing node components (`BaseNode`, `ServiceNode`, `ComputeNode`, `SecurityNode`) to accept and render debug highlight states.

### Explored in

Prototype 2 (primary feature — full SVG edge highlighting, packet animation, node dimming), Prototype 5 (Filmstrip — simplified version with div-based edges).

---

## Feature 6 — Request Path Mini-Map

### What it does

A vertical list of all nodes on the request's configured path, with colored dots showing progress: green (visited/done), blue (current), red (rejected), gray (pending/not reached).

### Why it exists

The canvas shows the full topology — which can have dozens of nodes. The mini-map provides a focused, linear view of just the nodes this specific request will visit (or has visited), making it easy to see how far through the path the request got before failing.

### How it works internally

**Path construction:** The `Request` object (in `src/engine/core/events.ts`) maintains a `path: string[]` array. Each time `handleRequestArrival` fires, the engine calls `appendNodeToPath(request, nodeId)`, pushing the node ID. The mini-map uses this array.

**Expected path vs actual path:** The expected path comes from the `RoutingTable` — walking the topology's edges from the source node. The actual path comes from the `request.path` array. The mini-map compares these: nodes in the actual path get "done" or "current" status; nodes in the expected path but not in the actual path get "pending".

**Dot states:**

| State | Color | Condition |
|---|---|---|
| done | Green | Node index < currentEventNodeIndex in path |
| current | Blue (with ring) | Node is the current event's nodeId |
| rejected | Red (with ring) | Node is current AND event status is rejected |
| pending | Gray | Node is in expected path but request hasn't reached it yet |

### What components it requires

- **Engine-side:** Access to `request.path` (already tracked) and the expected route (from `RoutingTable.resolveTarget` chain).
- **Renderer-side:** A `RequestPathMap` component. Takes the expected path, actual path, and current event index.

### Explored in

Prototype 2 (inspector panel), Prototype 3 (Request-Centric view — as a "hop trail" under each request card).

---

## Feature 7 — Request Lifecycle Rail

### What it does

A horizontal row of "phase cards" representing the high-level stages of a request's lifecycle (Generated → Gateway → Auth → Route → Order → Cache → Payment). A progress bar connector fills left-to-right as the user steps through. A red rejection marker appears at the failure point.

### Why it exists

The event log is low-level — it shows raw `SimulationEvent` types. The lifecycle rail abstracts these into human-meaningful phases ("this request was in the Auth phase", "it failed at the Payment phase"). This is useful for users who think in terms of system architecture rather than event queues.

### How it works internally

**Phase derivation:** Each phase maps to one or more events at a specific node. A phase is derived from `(nodeId, eventType)` pairs:
- "Generated" = `(sourceNode, request-generated)`
- "Gateway" = `(api-gw, processing-complete)`
- "Auth" = `(auth-svc, processing-complete)`
- etc.

The phase model is a higher-level abstraction over the raw events. For the real implementation, phases would be derived from the topology's node ordering (the path from source to terminal).

**Phase states:**
- Default (white) — not yet reached.
- Done (green border/background) — request has passed this phase.
- Current (blue, lifted with shadow) — request is at this phase now.
- Failed (red, lifted with red shadow) — request was rejected at this phase.

**Connector bar:** A 4px horizontal line spanning all phases. The blue fill width = `(currentPhaseIndex / totalPhases) * 100%`.

**Rejection marker:** A 22px red circle positioned at the current fill percentage. Only visible when the current phase has `result: "rejected"`.

**State cards below the rail:** Four summary cards that update on each step: "Lifecycle state", "Current node", "Current event", "Terminal reason". These provide at-a-glance context.

**Enriched phase data:** Each phase carries node runtime state at the time of the event:
- `queue: number` — current queue length
- `workers: string` — format "active/total" (e.g., "8/8")
- `capacity: string` — max capacity K

These map directly to `GGcKNode.getState()` values. The payment node's rejection data (`queue: 100, workers: "8/8", capacity: "100"`) shows the exact state that triggered the admission check failure in `handleArrival()`: `currentLoad (100) >= maxCapacity (100)`.

### What components it requires

- **Engine-side:** Phase data with embedded node state. See [Engine Integration Requirements](#engine-integration-requirements).
- **Renderer-side:** A `LifecycleRail` component with phase cards, connector bar, rejection marker, and state cards.

### Explored in

Prototype 4 (Lifecycle Rail view).

---

## Feature 8 — Sequence Diagram Debugger

### What it does

A UML-style sequence diagram showing the request's journey between nodes as messages flowing between actor lifelines. Messages are positioned vertically by time order and horizontally by which node they involve. Arrow lines connect consecutive events.

### Why it exists

Sequence diagrams are a familiar notation for distributed system interactions. They make inter-node communication patterns visible: you can see that the request went from api-gw → auth-svc → lb → order-svc-b → inventory-svc → redis → payment-svc-v2, and that the last hop resulted in rejection. The spatial arrangement emphasizes the *communication* between services rather than the state within a single node.

### How it works internally

**Actor columns:** One column per node on the request's path. Positioned as a `repeat(N, 1fr)` grid with sticky headers. Dashed vertical lifelines extend down from each actor.

**Message pills:** Absolutely positioned at:
- x = `actorColumnIndex * columnWidth + offset`
- y = `eventIndex * rowHeight + offset`

Each message shows: `timestamp + eventType`. States: default (blue), current (blue with ring and scale), failed (red with ring).

**Arrow lines:** Horizontal bars connecting consecutive messages when they involve different actors. Positioned between the two actor columns. Width = absolute distance between the two actors' x positions. States follow the same current/failed pattern.

**Interaction:** Clicking a message pill updates the current event index and triggers the full debug update cycle.

### What components it requires

- **Renderer-side:** A `SequenceDiagram` component. Takes the actor list and event list, computes positions, renders messages and arrows. Needs to handle variable node counts and long sequences (scrollable container).

### Explored in

Prototype 4 (Sequence Debugger view).

---

## Feature 9 — Stack Trace Debugger

### What it does

Presents the request's lifecycle as a "call stack" — a vertical list of frames on the left (like an IDE's debugger sidebar), with a main panel showing a "debug card" displaying the current frame's variables (nodeId, eventType, reason, queueLength, workers, capacity) in a grid layout, plus a progress bar.

### Why it exists

This is the most developer-familiar metaphor. Software engineers are trained to read call stacks and watch local variables change as they step through code. This view maps that mental model onto the request lifecycle: each "frame" is a hop, and the "local variables" are the node's queue state at the time of that hop.

### How it works internally

**Left panel — call stack frames:** One card per lifecycle phase, stacked vertically. Newest frame at current index is highlighted. States: default, done (green), current (blue with ring), failed (red with ring). Each frame shows: phase name, result badge, node ID, event type + timestamp.

**Main panel — debug card:**
- Request badge (e.g., "req-9148")
- Big status text (24px, 950 weight): "Rejected at {node}" or "Paused at {node}"
- Description paragraph
- Progress bar: fill width = `(currentIndex / totalFrames) * 100%`. Blue for normal, red for rejection.
- **Locals grid** (3-column): Renders like IDE watch variables.
  - `nodeId` — current node
  - `eventType` — current event type
  - `reason` — rejection reason or "-"
  - `queueLength` — from `GGcKNode.getState().queueLength`
  - `workers` — from `GGcKNode.getState().activeWorkers` / `ComponentNode.queue.workers`
  - `capacity` — from `ComponentNode.queue.capacity`

**Right panel:** Standard detail panel with full event metadata and trace waterfall.

### What components it requires

- **Renderer-side:** A `StackTraceDebugger` component with three-panel layout. The "locals" concept is novel and requires careful mapping from engine state to display variables.

### Explored in

Prototype 4 (Stack Trace view).

---

## Feature 10 — Node Intake Lens

### What it does

A zoomed-in explainer view of the **admission decision** at the node that rejected a request. Shows three gauges (workers, queue, capacity), a slot-level visualization of every position in the node's system, the admission equation, and a plain-English explanation of why the request was rejected.

### Why it exists

This is the most pedagogically valuable view. The G/G/c/K model's admission check is simple (`activeWorkers + queueLength >= capacity → reject`), but users don't always understand *why* a node is at capacity. The intake lens makes the mechanics visceral: you see 8 blue slots (busy workers), 92 amber slots (queued requests), and 1 red slot (the request that couldn't enter).

### How it works internally

**Data source:** All values come from `GGcKNode` state and configuration:

| Display | Source |
|---|---|
| Workers gauge: "8 / 8 busy" | `getState().activeWorkers` / `config.queue.workers` |
| Queue gauge: "92 / 92 queued" | `getState().queueLength` / `(config.queue.capacity - config.queue.workers)` |
| Capacity gauge: "100 / 100 in system" | `getState().totalInSystem` / `config.queue.capacity` |

**Meter bars:** Three horizontal bars, each showing utilization ratio. When at 100%, the bar is red; otherwise blue. The meter fill width = `(current / max) * 100%`.

**Slot grid:** A grid of `capacity` small squares (20 columns). Each slot is colored:
- Blue (`used`) — first `activeWorkers` slots (busy workers)
- Amber (`queued`) — next `queueLength` slots (requests waiting)
- Red (`reject`) — one extra slot representing the incoming request that was turned away

This maps exactly to the admission check in `GGcKNode.handleArrival()`:
```typescript
const currentLoad = this.activeWorkers + this.queue.length
if (currentLoad >= this.maxCapacity) {
  return { status: 'rejected', reason: 'capacity_exceeded' }
}
```

**Decision box:** Red-bordered box showing:
- Badge: "Rejected"
- Equation (large text): `activeWorkers + queueLength >= capacity`
- Explanation: "8 active + 92 queued = 100. Capacity is 100, so the arriving request cannot enter the node."

### What components it requires

- **Engine-side:** `NodeState` at the time of rejection (activeWorkers, queueLength) plus `ComponentNode` configuration (queue.workers, queue.capacity).
- **Renderer-side:** A `NodeIntakeLens` component with gauges, slot grid, and decision explainer.

### Explored in

Prototype 5 (Node Intake Lens view).

---

## Feature 11 — Actual vs Expected Path Diff

### What it does

Side-by-side comparison of two paths:
1. **Expected path** — the full route the request *would* take if no failures occurred (derived from the topology's edge graph).
2. **Actual path** — the route the request *actually* took before being rejected.

A third section explains the difference: where the paths diverge and why.

### Why it exists

When a request is rejected mid-path, the user may not realize it was *supposed* to continue to additional downstream services. The diff makes this visible: "Expected: api-gw → auth-svc → lb → order-svc-b → redis → payment-svc-v2 → **orders-db**. Actual: stopped at payment-svc-v2." This immediately tells the user that orders-db never received the data it was supposed to get.

### How it works internally

**Expected path construction:** Walk the topology's edges from the source node, following `RoutingTable.resolveTarget()` at each hop. For topologies with conditional or weighted routing, this would need to use the "most likely" or "configured default" path.

**Actual path:** From `request.path[]` — the array of nodeIds visited.

**Rendering:** Each path is a horizontal chain of "stop" badges connected by colored connectors.
- Expected path: all stops green, all connectors green.
- Actual path: stops green up to the terminal node, terminal stop red, followed by a red connector and a "STOP" badge.

**Difference section:** A text explanation combining:
- Where the paths diverge (first node in expected but not in actual).
- Terminal metadata: `terminal = request-rejected · nodeId = payment-svc-v2 · reason = capacity_exceeded`.

### What components it requires

- **Engine-side:** The expected path (from topology edge walking) and actual path (from `request.path`).
- **Renderer-side:** A `PathDiff` component with two route visualizations and a diff explanation.

### Explored in

Prototype 5 (Actual vs Expected view).

---

## Feature 12 — State Machine View

### What it does

Represents the request lifecycle as a finite state machine with named states (Generated, In Flight, Queued, Processing, Routing, Rejected) and transitions between them. Guard conditions are shown on transitions (e.g., `guard: currentLoad >= K`).

### Why it exists

This view formalizes the request lifecycle as a state machine, which maps directly to the engine's internal event dispatch. Each state corresponds to a handler in `SimulationEngine.handleEvent()`:

| State | Engine handler |
|---|---|
| Generated | `handleRequestGenerated` |
| In Flight | `enqueueEdgeTransfer` (request is on an edge) |
| Queued | `GGcKNode.handleArrival` returned `{ status: 'queued' }` |
| Processing | `GGcKNode.startProcessing` — worker assigned |
| Routing | `handleProcessingComplete` → `routing.resolveTarget` |
| Rejected | `handleRequestRejected` |

The guard condition `currentLoad >= K` is the exact admission check in `GGcKNode.handleArrival()`.

### How it works internally

**States:** Absolutely positioned cards on a board. Each state has: name, description, a badge, and visual states (default, done/green, active/blue, fail/red).

**Arrows:** Connection lines between states with CSS transforms. States: default gray, done (green), active (blue, thicker), fail (red, thicker).

**Guard labels:** Positioned between the "Routing" → "Rejected" transition. Shows the condition that causes the transition to fire.

### What components it requires

- **Renderer-side:** A `StateMachineView` component. The state machine is static (same for all requests) — only the current state and transition highlighting changes per step.

### Explored in

Prototype 5 (State Machine view).

---

## Feature 13 — Event Log Display Variants

### What it does

Explores five different ways to organize and present the same event log data, each optimized for a different analytical question.

### Variants

**1. DevTools Table (Prototype 3)**
A flat, Chrome-DevTools-style table. Best for: scanning all events chronologically, correlating timestamps across nodes. Includes a "Recommended event payload" JSON block showing the exact fields each event should carry.

**2. Request-Centric Grouping (Prototype 3)**
Events grouped by `requestId`. Each request becomes a card showing its terminal status, the node where it stopped, and a visual hop trail. Best for: answering "which requests failed?" and "what path did request X take?".

**3. Node-Centric Grouping (Prototype 3)**
Events grouped by `nodeId`. Each node becomes a card with aggregate stats (event count, rejection count, latest timestamp, utilization bar). Best for: answering "which nodes are unhealthy?" and "is this node rejecting requests?".

**4. Incident Feed (Prototype 3)**
Filtered to only show terminal events (rejections, timeouts). Styled as incident cards with severity-colored borders. Best for: rapid triage — seeing only the failures, sorted by severity.

**5. Waterfall / Timeline (Prototype 1 Option C, Prototype 3)**
Swim-lane timeline with one lane per node. Events are positioned horizontally by timestamp. Best for: understanding timing relationships — which events happened concurrently, where there are gaps or bursts.

### What components each requires

All variants consume the same `SimulationEvent[]` data. The difference is in grouping, filtering, and layout:
- DevTools Table: Virtual-scrolled flat table.
- Request-Centric: `groupBy(events, 'requestId')` → card list.
- Node-Centric: `groupBy(events, 'nodeId')` → grid of node cards.
- Incident Feed: `events.filter(e => isTerminal(e))` → incident cards.
- Waterfall: Swim-lane component with time-positioned pills.

### Explored in

Prototype 3 (all five), Prototype 1 (Option C — waterfall).

---

## Layout Options

The prototypes explore where in the existing workspace these features should live. The workspace today is: left sidebar (LibrarySidebar) | canvas (FlowCanvas) | right sidebar (PropertiesPanel), with `ResultsTray` in a resizable bottom panel.

### Option A: Bottom Debug Dock

Add the event log and detail inspector as a new tab in the existing `ResultsTray` bottom panel, alongside Summary, Per-node, etc. The canvas highlights nodes/edges during debugging.

**Pros:** No layout disruption. Fits naturally into the existing `WorkspaceLayout` resizable split.
**Cons:** Vertical space is limited — the bottom panel is currently 305px.

### Option B: Right Debugger Inspector

Replace or augment the right `PropertiesPanel` with a dedicated debugger inspector when in debug mode. Shows the mini-map, current event details, and a compact event stream.

**Pros:** Debug info is always visible without stealing vertical space.
**Cons:** Hides the properties panel. Would need a toggle or tab system.

### Option C: Focus Mode

Hide both sidebars, maximize the canvas, and use the bottom panel as the sole control surface. Non-path nodes dim.

**Pros:** Maximum visual focus on the request path.
**Cons:** Loses access to library and properties during debugging.

### Current workspace structure (for reference)

```
WorkspaceLayout
├── Header (SimulationControls, FileStatus, Branding)
├── LibrarySidebar (left, 190px)
├── FlowCanvas (center, flex)
├── PropertiesPanel (right, 340px)
└── ResultsTray (bottom, resizable)
```

---

## Engine Integration Requirements

All features above require changes to how the engine communicates with the renderer. The current architecture is:

```
Renderer → Worker: run(TopologyJSON) | pause | resume | stop | step(count)
Worker → Renderer: progress(percent, eventsProcessed) | snapshot(TimeSeriesSnapshot) | complete(SimulationOutput) | error(message)
```

### Required additions

**1. Event streaming.** A new outbound message type:

```typescript
interface EventBatchMessage {
  type: 'event-batch'
  events: SimulationEvent[]  // batch of events since last emission
}
```

The worker would accumulate events in a buffer during `processEvents()` and flush periodically (e.g., every chunk of 20,000 events, alongside the existing `sleep(0)` yield point in `runChunked`).

**2. Node state snapshots per event.** For the detail inspector and intake lens, terminal events (rejected, timeout) need the `NodeState` at the time of the event. Options:
- Embed `NodeState` in the event's `data` payload for terminal events only.
- Store periodic `NodeState` snapshots (already done in `takeSnapshot()`) and interpolate.

**3. Debug mode tracing.** When debugging a specific request, force `RequestTracer.shouldTrace()` to return `true` for that request ID, overriding the sample rate.

**4. Expected path computation.** A utility that walks the topology's edges from a source node to compute the expected full path. This doesn't exist today — `RoutingTable.resolveTarget` only resolves one hop at a time and depends on the request's runtime state.

---

## Prototype-to-Feature Map

| Feature | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|
| 1. Event Log | A,B,C | Yes | DevTools, Waterfall | — | Filmstrip |
| 2. Request Detail Inspector | Yes | Yes | Yes | Yes | Yes |
| 3. Request Trace Waterfall | Yes | Yes | — | Yes | — |
| 4. Step-Through Debugger | — | Yes | — | Yes | Yes |
| 5. Canvas Debug Overlay | — | Yes | — | — | Yes |
| 6. Request Path Mini-Map | — | Yes | Req-Centric | — | — |
| 7. Lifecycle Rail | — | — | — | Yes | — |
| 8. Sequence Diagram | — | — | — | Yes | — |
| 9. Stack Trace Debugger | — | — | — | Yes | — |
| 10. Node Intake Lens | — | — | — | — | Yes |
| 11. Actual vs Expected Diff | — | — | — | — | Yes |
| 12. State Machine View | — | — | — | — | Yes |
| 13. Display Variants (5) | C | — | All 5 | — | — |
| Layout: Bottom Dock | A | Yes | — | — | — |
| Layout: Side Inspector | B | Yes | — | — | — |
| Layout: Focus Mode | — | Yes | — | — | — |

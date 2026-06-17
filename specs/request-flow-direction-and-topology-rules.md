# Request Flow Direction & Topology Rules

Technical feature specification defining how requests move through the topology graph: edge directionality, routing strategies, condition-based filtering, async fan-out, and the structural rules that govern valid request paths.

This spec consolidates the `RoutingTable` class, the `EdgeDefinition.mode` discriminant, the condition matching subsystem, the engine's edge transfer mechanics, and the validator's connectivity checks into a single reference for how request flow is directed at each hop. It exists because the routing decision is the branching point of every request's lifecycle — after a node completes processing, the routing table determines whether the request continues forward, fans out to multiple targets, terminates, or is filtered by a condition. Downstream specs (throughput calculation, rejection behaviour, lifecycle semantics) all depend on understanding the routing contract: how many targets a request reaches, in what order, and under what conditions.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Edge Directionality and Mode Classification](#feature-1-edge-directionality-and-mode-classification)
4. [Feature 2: Routing Strategy Selection](#feature-2-routing-strategy-selection)
5. [Feature 3: Condition-Based Edge Filtering](#feature-3-condition-based-edge-filtering)
6. [Feature 4: Async Fan-Out and Request Branching](#feature-4-async-fan-out-and-request-branching)
7. [Feature 5: Topology Connectivity Validation](#feature-5-topology-connectivity-validation)
8. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
9. [Integration Requirements](#integration-requirements)
10. [Source-to-Feature Map](#source-to-feature-map)
11. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Request Flow Direction & Topology Rules is the subsystem that resolves "where does this request go next?" at every routing decision point. Given a source node, a request, and the set of outgoing edges, it: (1) filters edges by condition eligibility, (2) partitions eligible edges into async and sync groups, (3) fans out to all async targets, (4) selects exactly one sync target via round-robin, weighted random, or uniform random, and (5) for each selected target, initiates an edge transfer with latency, packet loss, and error rate sampling.

It also encompasses the structural topology rules enforced at validation time: source nodes should not have incoming edges, sink nodes should not have outgoing edges, routers with routing strategies need multiple outgoing edges, and all non-source nodes must be reachable from at least one source.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Users configure edge modes, routing strategies, and conditions as part of topology design |
| Architectural change      |       No | The `RoutingTable` class is implemented and stable; this spec formalizes it |
| Domain model addition     |  Partial | Proposes `RequestDirection` enum and topology rule types for the Environment Model; existing types are implemented |
| Validation layer          |      Yes | Documents existing connectivity validation and proposes additional structural rules |
| Refactor of existing code |       No | No refactoring needed; the routing subsystem is clean |

### Current pain without this model

| Pain | Who is affected | Technical cause | Consequence |
| ---- | --------------- | --------------- | ----------- |
| Edges are unidirectional only | Users | `EdgeDefinition` has `source` and `target` — no concept of bidirectional edges | Modeling request-response patterns (e.g., DB read → response) requires a separate return edge or is simply omitted, losing response latency |
| Round-robin detection uses ID heuristic | Engine developers | `RoutingTable.isRoundRobinSource()` falls back to substring matching (`id.includes('load-balancer')`) when no explicit `routingStrategy` is set in node config | Renaming a load balancer node can silently change its routing strategy |
| Condition expressions are limited | Users | `matchesCondition()` only supports `request.type === "X"` and `request.type !== "X"` via regex | Cannot route on request priority, size, metadata, or compound conditions |
| No support for response flow | Users, engine developers | Requests flow source → sink but there is no return path model | Latency metrics only capture one-way traversal; round-trip time requires manual calculation |
| No cycle detection | Engine developers | The validator checks reachability from source but does not detect cycles in synchronous edges | A synchronous cycle would cause infinite request forwarding (each hop triggers the next) |
| Edge mode inference is renderer-only | Engine developers | `useTopologySerializer.ts:196-197` infers `asynchronous` mode from `asyncBoundary` on the template/spec, but this logic is not available outside the serializer | Topology JSON created without the serializer (e.g., from CLI) must explicitly set edge modes |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Edge mode semantics (sync, async, streaming, conditional) | Yes | Defines what each mode means for routing decisions |
| Routing strategy selection (round-robin, weighted, uniform) | Yes | The `pickSyncRoute` algorithm is a routing concern |
| Condition expression evaluation | Yes | `matchesCondition` is part of edge filtering |
| Async fan-out and request cloning | Yes | `prepareRequestsForRoutes` is triggered by routing decisions |
| Edge transfer mechanics (latency, loss, error sampling) | Partial | Owned jointly with Edge Properties & Defaults; this spec covers the flow decision, that spec covers property semantics |
| Topology connectivity rules (source/sink, reachability, self-loops) | Yes | Validator connectivity checks are structural topology rules |
| Bidirectional edge model | Yes | Proposed extension to `EdgeDefinition` for response-path modeling |
| Edge latency distribution semantics | No | Belongs to Edge Properties & Defaults |
| Request lifecycle state transitions | No | Belongs to Arrival, Departure & Request Lifecycle Semantics |
| Throughput effects of fan-out | No | Belongs to Throughput Calculation |

### Smallest useful v1

| v1 capability | Required? | Why |
| --- | ---: | --- |
| Formal documentation of edge modes | Yes | Undocumented; critical for understanding routing behaviour |
| Routing strategy algorithm specification | Yes | Round-robin, weighted, and uniform are implemented but not specified |
| Condition matching rules | Yes | Users need to know what expressions are supported |
| Fan-out and branching semantics | Yes | Async fan-out creates request clones; this has throughput and lifecycle implications |
| Connectivity validation rules | Yes | Already implemented; needs formal specification |
| Bidirectional edge model | Deferred | Valuable but requires `EdgeDefinition` schema change |
| Cycle detection for sync edges | Deferred | Important safety guard but not blocking current simulations |
| Extended condition expressions | Deferred | `request.type` matching covers the primary use case |

### Deferred capabilities

| Deferred capability | Later spec | Why deferred |
| --- | --- | --- |
| Bidirectional/response-path edge model | This spec (future version) or Edge Properties & Defaults | Requires schema change and engine support for return paths |
| Sync cycle detection and prevention | Simulation Validation & Pattern Accuracy | Safety guard that requires graph analysis beyond connectivity |
| Compound condition expressions | This spec (future version) | Requires expression parser beyond current regex matching |
| Topology-level multi-workload routing | Request Pattern Configuration | Multiple workload sources need pattern assignment before routing |
| Edge bandwidth shaping effects on routing | Edge Properties & Defaults | Bandwidth limits on edges could inform routing decisions |

---

## Problem Context

### What exists today

**EdgeDefinition type (`src/engine/core/types.ts:309-339`)**

```typescript
export interface EdgeDefinition {
  id: string
  source: string
  target: string
  label?: string
  mode: 'synchronous' | 'asynchronous' | 'streaming' | 'conditional'
  protocol: 'https' | 'grpc' | 'tcp' | 'udp' | 'websocket' | 'amqp' | 'kafka'
  latency: {
    distribution: DistributionConfig
    pathType: 'same-rack' | 'same-dc' | 'cross-zone' | 'cross-region' | 'internet'
  }
  bandwidth: number
  maxConcurrentRequests: number
  packetLossRate: number
  errorRate: number
  weight?: number
  condition?: string
  sourceHandle?: string
  targetHandle?: string
  animated?: boolean
}
```

Edges are strictly directional: `source` → `target`. There is no concept of a return path, bidirectional mode, or response edge. The `mode` field is the primary routing discriminant — it determines whether the edge participates in fan-out (async) or competition (sync/streaming/conditional).

**RoutingTable class (`src/engine/routing.ts`)**

The `RoutingTable` is constructed once during engine initialization (`engine.ts:61`) from `topology.edges` and optional `topology.nodes`. It builds an adjacency list keyed by source node ID and identifies round-robin sources from node config.

The core method `resolveTarget(sourceNodeId, request)` implements the routing algorithm:

```
1. Look up outgoing edges for sourceNodeId
2. Filter by condition eligibility (matchesCondition)
3. Partition: asyncEdges = mode === 'asynchronous', syncEdges = everything else
4. Fan-out: all async edges → one ResolveRoute each
5. Compete: sync edges → pickSyncRoute → exactly one ResolveRoute
6. Return combined results
```

**Routing strategy selection (`routing.ts:115-129`)**

Three strategies implemented in `pickSyncRoute`:

1. **Round-robin**: If `isRoundRobinSource(sourceNodeId)` returns true, cycle through edges using a per-source cursor (`roundRobinIndexBySource`). The cursor is stored modulo edge count and incremented after each selection.

2. **Weighted random**: If any edge in the candidate set has a `weight` field defined, use `pickByWeight`. This sums all weights (defaulting undefined weights to 1), generates a random threshold, and walks the cumulative distribution.

3. **Uniform random**: Fallback when neither round-robin nor weighted applies. Uses `rng.integer(0, edges.length - 1)`.

**Edge mode inference during serialization (`useTopologySerializer.ts:195-197`)**

```typescript
const mode =
  asEdgeMode(edgeData.mode) ??
  (targetTemplate?.asyncBoundary || targetSpec?.asyncBoundary ? 'asynchronous' : 'synchronous')
```

If the canvas edge has no explicit mode, the serializer infers it from the target node's component spec. Nodes like `queue`, `pub-sub`, `stream`, `event-bus` have `asyncBoundary: true` in their palette template, which makes inbound edges default to `asynchronous`.

**Edge transfer mechanics (`engine.ts:728-770`)**

When a route is resolved, the engine calls `enqueueEdgeTransfer(request, edge, targetNodeId)`:

```
1. Packet loss check: if rng < edge.packetLossRate → schedule request-timeout
2. Error rate check: if rng < edge.errorRate → schedule request-rejected (reason: edge_error_rate)
3. Latency sampling: arrivalTime = clock + sampleEdgeLatencyUs(edge)
4. Deadline check: if request.deadline <= arrivalTime → schedule request-timeout
5. Otherwise: schedule request-arrival at targetNodeId at arrivalTime
```

This is the bridge between routing (which edges to use) and transfer (what happens on the edge).

**Validator connectivity checks (`validator.ts:700-847`)**

The validator performs these topology structure checks:
- Source/target node IDs on edges must exist in the node set
- Workload `sourceNodeId` must reference an existing node
- At least one source node must exist
- Selected source must reach at least one non-source downstream node
- Self-loop edges produce warnings
- Source-to-source edges produce warnings
- Source nodes with incoming edges produce warnings
- Sink nodes with outgoing edges produce warnings
- Router nodes with ≤1 outgoing edges and a routing strategy produce warnings
- Nodes unreachable from any source produce warnings

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| No bidirectional/response edge model | Cannot model request-response round-trip latency | `EdgeDefinition` is unidirectional only |
| No sync cycle detection | Infinite forwarding loop possible if synchronous edges form a cycle | Validator checks reachability but not cycles |
| Round-robin falls back to ID heuristic | Fragile; renaming a node changes routing | `isRoundRobinSource` substring matching in `routing.ts:215-221` |
| Condition expressions limited to `request.type` | Cannot route on priority, size, or metadata | `matchesCondition` uses a single regex pattern |
| `streaming` mode treated identically to `synchronous` | No streaming-specific semantics | `routing.ts:98`: `syncEdges = eligible.filter(edge => edge.mode !== 'asynchronous')` groups streaming with sync |
| No route-level metrics | Cannot measure per-edge throughput or per-route utilization | Metrics are node-level only |
| Edge mode inference is renderer-only | CLI-created topologies must set modes explicitly | `asyncBoundary` logic lives in `useTopologySerializer` |

### What the source material explores

The Environment Definition & Configuration Model spec proposes a `RequestDirection` enum (`unidirectional | request-response | bidirectional`) on per-edge environment config, with direction inference rules as a deferred capability owned by this spec. The system mind map positions routing as a central engine subsystem connecting edge definitions to node processing. The product discussions identify conditional routing and fan-out as key differentiators of the simulator's topology model.

---

## Feature 1: Edge Directionality and Mode Classification

### What it does

Classifies each edge in the topology by its `mode` field, which determines how the edge participates in routing decisions. The mode is the primary discriminant that controls whether a request fans out (async) or competes for a single route (sync/streaming/conditional).

### Why it exists

Real distributed systems have fundamentally different communication patterns. A synchronous HTTP call blocks the caller until the response arrives. An asynchronous message to a queue fires and forgets. A conditional route only applies when the request matches a predicate. These patterns produce different throughput characteristics, different failure modes, and different lifecycle paths. The mode field captures this distinction at the edge level so the routing algorithm can handle each pattern correctly.

### How it works internally

**Data source**: `EdgeDefinition.mode` — a required literal union defined in `src/engine/core/types.ts:314`.

**Mode semantics**:

| Mode | Routing behaviour | Multiplicity | Use case |
| --- | --- | --- | --- |
| `synchronous` | Competes with other sync edges for selection | One selected per hop | HTTP calls, gRPC, direct DB queries |
| `asynchronous` | Always selected if condition matches | All async edges selected (fan-out) | Message queues, event buses, pub-sub |
| `streaming` | Treated identically to `synchronous` in current implementation | One selected per hop | WebSocket connections, streaming APIs (semantics not yet differentiated) |
| `conditional` | Competes with sync edges BUT only if its `condition` string evaluates to true for the request; treated as ineligible if condition is empty | One selected per hop (after filtering) | Content-based routing, request type branching |

**Mode assignment flow**:

```
Canvas edge (no explicit mode)
    │
    ▼
useTopologySerializer: infer from target node's asyncBoundary
    │
    ├─ asyncBoundary = true → mode: 'asynchronous'
    └─ asyncBoundary = false/undefined → mode: 'synchronous'
    │
    ▼
TopologyJSON edge (explicit mode)
    │
    ▼
RoutingTable.resolveTarget: partition by mode
    │
    ├─ mode === 'asynchronous' → asyncEdges (fan-out all)
    └─ mode !== 'asynchronous' → syncEdges (pick one)
```

**Component types with `asyncBoundary: true`**:

From the palette templates in `src/engine/catalog/paletteTemplates.ts`, the following component types are async boundaries: `queue`, `pub-sub`, `stream`, `event-bus`, `event-sourcing-store`, `message-broker`, `task-queue`. Edges targeting these nodes default to `asynchronous` mode during serialization.

**Proposed `RequestDirection` enum (from Environment Model spec)**:

```typescript
export type RequestDirection = 'unidirectional' | 'request-response' | 'bidirectional'
```

This would extend the edge model to indicate whether the edge represents a one-way flow, a request-response pair (implicit return path), or a bidirectional channel. In v1, all edges are effectively `unidirectional`. The direction field would live on `EnvironmentEdgeConfig` and inform future response-path modeling.

### What components it requires

- **Engine-side**: No changes for current mode semantics. For streaming differentiation (deferred), `resolveTarget` would need a streaming-specific path.
- **Shared layer**: Mode inference logic could be extracted from `useTopologySerializer` into a shared utility for CLI consumption.
- **Renderer/frontend-side**: Edge mode selector already exists on the canvas. Animated edges (`animated: true`) visually indicate async mode.

### Explored in

`src/engine/core/types.ts:314` (mode union), `src/engine/routing.ts:97-98` (partition logic), `src/renderer/src/hooks/useTopologySerializer.ts:195-197` (mode inference), Environment Definition & Configuration Model spec (RequestDirection proposal).

---

## Feature 2: Routing Strategy Selection

### What it does

When multiple synchronous edges leave a node, selects exactly one target using one of three strategies: round-robin, weighted random, or uniform random. The strategy is determined by the source node's configuration, not the edges themselves.

### Why it exists

A load balancer distributes traffic evenly (round-robin). A weighted router sends 80% of traffic to a primary and 20% to a canary (weighted). A simple fork with no preference picks randomly (uniform). Without configurable strategies, all multi-target nodes would behave identically, making it impossible to model common load-distribution patterns.

### How it works internally

**Data source**: The strategy is determined by a priority cascade in `RoutingTable`:

1. **Explicit config**: `node.config?.['routingStrategy'] === 'round-robin'` — checked during construction (`routing.ts:61-65`). Stored in `this.roundRobinSourceIds`.
2. **Edge weights**: If any candidate edge has `weight !== undefined`, use weighted selection (`routing.ts:124`).
3. **Fallback**: Uniform random.

The node-level `routingStrategy` field is stored in the generic `config: Record<string, unknown>` on `ComponentNode`, not as a typed field. It's accessed via string key lookup. Only `'round-robin'` is checked explicitly; the RoutingTable does not read `'weighted'`, `'random'`, `'least-conn'`, `'broadcast'`, `'conditional'`, or `'passthrough'` from the config.

**Available strategies (from `RoutingStrategy` type in `src/engine/catalog/nodeSpecTypes.ts:27-34`)**:

| Strategy | Implementation status | Behaviour |
| --- | --- | --- |
| `round-robin` | Implemented | Cycles through edges using a bounded per-source cursor |
| `weighted` | Implemented (via edge weights) | Selects one edge proportional to its `weight` value |
| `random` | Implemented (fallback) | Uniform random selection among candidates |
| `least-conn` | Not implemented | Would select the target with fewest in-flight requests |
| `broadcast` | Not implemented | Would send to all targets (similar to async fan-out but synchronous) |
| `conditional` | Partially implemented | Condition matching exists on edges, but `routingStrategy: 'conditional'` as a node-level strategy is not consumed |
| `passthrough` | Not implemented | Would forward to the single outgoing edge without selection logic |

**Round-robin algorithm (`routing.ts:116-122`)**:

```typescript
const current = this.roundRobinIndexBySource.get(sourceNodeId) ?? 0
const safeIndex = current % edges.length
const edge = edges[safeIndex]
this.roundRobinIndexBySource.set(sourceNodeId, (safeIndex + 1) % edges.length)
return edge
```

The cursor is stored modulo edge count to prevent integer overflow. It starts at 0 and increments by 1 after each selection. The modulo is applied twice (once on read, once on write) for safety.

**Round-robin source detection (`routing.ts:211-222`)**:

```typescript
private isRoundRobinSource(sourceNodeId: string): boolean {
  if (this.roundRobinSourceIds.size > 0) {
    return this.roundRobinSourceIds.has(sourceNodeId)
  }
  const id = sourceNodeId.toLowerCase()
  return (
    id.includes('load-balancer') ||
    id.includes('lb') ||
    id.includes('ingress') ||
    id.includes('reverse-proxy')
  )
}
```

When node definitions are provided to the constructor (which they always are from the engine: `routing.ts:61`), the explicit config set takes precedence. The substring heuristic only fires when `roundRobinSourceIds` is empty — which happens when no node in the topology has `config.routingStrategy === 'round-robin'`. This means the heuristic is a legacy fallback for older topology JSON that predates the `routingStrategy` config field.

**Weighted selection algorithm (`routing.ts:177-204`)**:

```
1. For each edge: weight = edge.weight ?? 1 (default 1 if not set)
2. Normalize: if weight <= 0 or non-finite, treat as 0
3. Sum all weights → total
4. If total <= 0: fall back to uniform random
5. Generate threshold = rng.next() * total
6. Walk edges, accumulating weights:
   cumulative += weights[i]
   if threshold < cumulative → return edges[i]
7. Fallback: return last edge
```

Note: `weight` is optional on `EdgeDefinition`. When present on any edge in the set, it triggers weighted selection. Edges without explicit weights default to 1, not 0 — so they participate equally with a weight of 1.

### What components it requires

- **Engine-side**: For `least-conn`, the routing table would need access to per-node in-flight counts (available via `GGcKNode.getState().totalInSystem`). For `broadcast`, a sync fan-out path parallel to async. For `passthrough`, a fast-path that skips selection logic. ~50 lines each.
- **Shared layer**: The `RoutingStrategy` type in `nodeSpecTypes.ts` is already shared. The gap is that the engine only consumes `'round-robin'` from config.
- **Renderer/frontend-side**: Node configuration panels already expose routing strategy selection for router-profile nodes.

### Explored in

`src/engine/routing.ts` (full implementation), `src/engine/catalog/nodeSpecTypes.ts:27-34` (strategy union type), `src/engine/engine.ts:61` (routing table construction).

---

## Feature 3: Condition-Based Edge Filtering

### What it does

Evaluates a string expression on each edge against the current request to determine whether the edge is eligible for routing. This is the mechanism for content-based routing: directing different request types to different downstream services.

### Why it exists

In a real system, an API gateway routes `/api/users` to the user service and `/api/orders` to the order service. A message router sends priority alerts to a fast-track queue and standard messages to the normal queue. Condition-based filtering enables these patterns by allowing each edge to specify which requests it accepts.

### How it works internally

**Data source**: `EdgeDefinition.condition` — an optional string field. `EdgeDefinition.mode` — when `'conditional'`, the condition is required (edges with empty conditions are treated as ineligible).

**Evaluation algorithm — `matchesCondition(edge, request)` in `routing.ts:142-172`**:

```
1. If mode === 'conditional' and condition is empty → return false (ineligible)
2. If condition is empty/undefined → return true (no filter)
3. Normalize whitespace
4. Attempt regex match: /^request\.type\s*(===|==|!==|!=)\s*["']([^"']+)["']$/
5. If matched:
   - Extract operator (===, ==, !==, !=) and expected type string
   - Evaluate: request.type === expectedType (or !==)
6. If regex doesn't match → return false (unknown expression format = ineligible)
```

**Supported expression formats**:

| Expression | Matches when |
| --- | --- |
| `request.type === "api-read"` | `request.type` equals `"api-read"` |
| `request.type == "api-read"` | Same (loose equality treated as strict) |
| `request.type !== "api-read"` | `request.type` does not equal `"api-read"` |
| `request.type != "api-read"` | Same |
| `request.type === 'api-read'` | Same (single quotes supported) |
| Any other expression | Never matches (returns false) |

**Key design decisions**:

1. **No eval / no arbitrary JS**: The condition is parsed by regex, not evaluated as JavaScript. This prevents injection and keeps the expression language predictable. The tradeoff is limited expressiveness.

2. **Only `request.type` is queryable**: Cannot match on `request.priority`, `request.sizeBytes`, `request.metadata`, or any other field. The request object is not exposed beyond the type string.

3. **Conditional mode edges without conditions are dead**: If `mode === 'conditional'` but the condition string is empty, the edge never matches. This is a validator-catchable error that is currently only a runtime no-op.

4. **Non-conditional mode edges with conditions are honored**: An edge with `mode: 'synchronous'` and `condition: 'request.type === "X"'` will be filtered by the condition. Mode and condition are evaluated independently.

**Integration with request distribution**:

The condition string values must match the `type` strings in `WorkloadProfile.requestDistribution`. For example, if the distribution has `[{ type: 'GET', weight: 0.7, ... }, { type: 'POST', weight: 0.3, ... }]`, then conditional edges should use `request.type === "GET"` or `request.type === "POST"`. There is no runtime validation that condition strings reference existing distribution types.

### What components it requires

- **Engine-side**: For extended expressions (priority, size, metadata matching), `matchesCondition` would need a mini expression evaluator instead of the current regex. ~100 lines.
- **Shared layer**: Condition validation (checking that condition strings reference valid request types from the workload distribution) would be a new cross-reference validation in `validator.ts`.
- **Renderer/frontend-side**: Condition editor UI on conditional edges. Currently the condition string is a free-text field.

### Explored in

`src/engine/routing.ts:142-172` (condition matching), `src/engine/core/types.ts:333` (condition field), `src/engine/workload.ts:155-171` (request type assignment).

---

## Feature 4: Async Fan-Out and Request Branching

### What it does

When a routing decision yields multiple target edges (specifically, all eligible async edges plus one sync edge), the engine creates request clones so each target receives an independent copy. The original request follows the first route; additional routes receive branched copies with unique IDs.

### Why it exists

Async fan-out models real patterns: an event bus publishes to multiple subscribers, a microservice emits events to both a logging pipeline and an analytics system, a message broker delivers to all topic consumers. Each subscriber receives and processes the message independently. Without request cloning, fan-out would require all targets to share a single request object, which would create aliasing bugs in path tracking, span recording, and lifecycle management.

### How it works internally

**Data source**: The count of resolved routes from `RoutingTable.resolveTarget()`. If `routes.length > 1`, branching is needed.

**Branching algorithm — `prepareRequestsForRoutes(request, routeCount)` in `engine.ts:543-554`**:

```typescript
if (routeCount <= 1) {
  return [request]  // no cloning needed
}

const routedRequests: Request[] = [request]  // original gets route[0]
for (let i = 1; i < routeCount; i++) {
  routedRequests.push(this.cloneRequestForBranch(request))
}
return routedRequests
```

**Clone construction — `cloneRequestForBranch(request)` in `engine.ts:556-565`**:

```typescript
const branchId = `${request.id}::branch-${++this.forkCounter}`
return {
  ...request,
  id: branchId,
  path: [...request.path],
  spans: request.spans.map(span => ({ ...span })),
  metadata: { ...request.metadata }
}
```

Key properties of a clone:
- **ID**: `{originalId}::branch-{counter}` — globally unique, traceable back to the original.
- **Path**: Shallow copy — the clone starts with the same path history but diverges from this point.
- **Spans**: Shallow copy of each span — past spans are shared by value, future spans are independent.
- **Metadata**: Shallow copy — clone gets its own metadata map.
- **Other fields**: `type`, `sizeBytes`, `priority`, `createdAt`, `deadline`, `retryCount` are copied by value via spread.

**Where branching occurs**:

Branching happens at two points in the engine:

1. **`handleRequestGenerated` (`engine.ts:273-308`)**: After generating a request, the engine resolves routes from the source node. If the source has both async and sync outgoing edges, the request is cloned.

2. **`handleProcessingComplete` (`engine.ts:340-396`)**: After a node finishes processing, the engine resolves routes to the next hop. If the node has multiple outgoing routes, the request is cloned.

**Lifecycle implications**:

Each branch is an independent request in the system:
- Tracked separately in `requestById` map
- Gets its own tracer entry via `tracer.setRequestCreatedAt`
- Can complete, reject, or timeout independently
- Counted independently in metrics

This means a single original request entering a topology with fan-out can produce N terminal events (completions, rejections, timeouts) — one per branch. The `forkCounter` on the engine tracks total branches created across all requests.

**Fan-out triggering conditions**:

| Source node edges | Async edges | Sync edges | Behaviour |
| --- | --- | --- | --- |
| 0 total | 0 | 0 | Request completes at source (no downstream) |
| 1 async only | 1 | 0 | Single route, no cloning |
| 1 sync only | 0 | 1 | Single route, no cloning |
| 2 async | 2 | 0 | Fan-out: 2 routes, 1 clone |
| 1 async + 1 sync | 1 | 1 | Fan-out: 2 routes, 1 clone |
| 3 sync | 0 | 3 | Competition: 1 route selected, no cloning |
| 2 async + 3 sync | 2 | 3 | Fan-out + competition: 3 routes (2 async + 1 sync), 2 clones |

### What components it requires

- **Engine-side**: Fully implemented. No changes needed.
- **Shared layer**: Branch ID format (`{id}::branch-{n}`) should be documented as a contract for trace analysis and debugger tools that need to correlate branches back to their parent request.
- **Renderer/frontend-side**: The event debugger's `RequestLifecycle` view should be aware that branches exist. `buildRequestLifecycle` in `debugTypes.ts` already handles this by filtering events by `requestId`, which naturally scopes to a single branch.

### Explored in

`src/engine/engine.ts:273-308` (request-generated routing), `src/engine/engine.ts:340-396` (processing-complete routing), `src/engine/engine.ts:543-565` (branching and cloning).

---

## Feature 5: Topology Connectivity Validation

### What it does

Enforces structural rules on the topology graph before simulation begins: node role constraints, edge reference integrity, reachability from source nodes, and warning-level diagnostics for suspicious configurations (self-loops, source-to-source edges, disconnected nodes).

### Why it exists

An invalid topology produces either engine errors (missing node references, no traffic source) or meaningless results (disconnected nodes contribute nothing, self-loops cause infinite processing). Validation catches these at topology parse time, before the simulation runs, with clear error messages that guide correction.

### How it works internally

**Data source**: `TopologyJSON` after Zod schema parsing in `validateTopology()` (`src/engine/validation/validator.ts:570-847`).

**Validation phases**:

| Phase | Checks | Severity | Lines |
| --- | --- | --- | --- |
| Schema parse | Zod structural validation of all fields | Error | 574-584 |
| Node uniqueness | Duplicate node IDs | Error | 599-604 |
| Source existence | At least one source node (by role or workload assignment) | Error | 701-707 |
| Edge reference integrity | Edge source/target IDs exist in node set | Error | 710-727 |
| Workload source validity | `workload.sourceNodeId` references existing node | Error | 693-699 |
| Source reachability | Selected source reaches at least one non-source downstream node | Error | 765-786 |
| Dependency references | Optional dependency IDs exist in node set | Error | 736-745 |
| Fault target validity | Fault targetIds reference existing nodes or edges | Error | 748-755 |
| Time logic | `simulationDuration > warmupDuration` | Error | 757-763 |
| Self-loops | Edge where source === target | Warning | 805-807 |
| Source-to-source edges | Edge connecting two source nodes | Warning | 809-817 |
| Source with incoming edges | Source node has incoming connections | Warning | 825-827 |
| Sink with outgoing edges | Sink node has outgoing connections | Warning | 829-831 |
| Router with ≤1 outgoing edges | Router node with routing strategy but insufficient fan-out | Warning | 833-837 |
| Disconnected nodes | Nodes unreachable from any source via BFS | Warning | 839-843 |
| Node defaults | Non-source node missing queue or processing config → apply legacy defaults | Warning | 614-632 |
| Queue sanity | `capacity < workers` | Error | 634-639 |
| Processing sanity | `timeout <= 0` | Error | 641-646 |
| Security filter requirements | WAF/firewall nodes must have blockRate or droppedPackets | Error | 669-690 |

**Reachability algorithm — `collectReachableNodeIds()` in `validator.ts:545-568`**:

```typescript
function collectReachableNodeIds(
  startNodeIds: string[],
  adjacencyList: Map<string, string[]>
): Set<string> {
  const visited = new Set<string>()
  const queue = [...startNodeIds]

  for (let index = 0; index < queue.length; index++) {
    const current = queue[index]
    if (visited.has(current)) continue
    visited.add(current)
    for (const neighbor of adjacencyList.get(current) ?? []) {
      if (!visited.has(neighbor)) queue.push(neighbor)
    }
  }
  return visited
}
```

Standard BFS using the adjacency list built from topology edges. The adjacency list is directional (source → target), so reachability follows edge direction.

**Source node detection — `isSourceNode()` in `validator.ts:541-543`**:

```typescript
function isSourceNode(node, topology): boolean {
  return resolvedRole(node) === 'source' || topology.workload?.sourceNodeId === node.id
}
```

A node is a source if its resolved structural role is `'source'` OR if it is the workload's designated source. The role is resolved via `node.role ?? inferStructuralRole(node.type)` in `resolvedRole()`.

**Proposed additional validation rules**:

| Rule | Condition | Severity | Why |
| --- | --- | --- | --- |
| Sync cycle detection | Synchronous edges form a cycle (DFS back-edge check) | Error | Prevents infinite request forwarding |
| Conditional edge condition required | `mode === 'conditional'` with empty condition | Warning | Currently a runtime no-op; should be caught at validation |
| Condition references valid request types | Condition strings reference types in `workload.requestDistribution` | Warning | Catches typos in condition expressions |
| Edge count for workload source | Source node has no outgoing edges | Warning | Workload generates requests but they have nowhere to go |

### What components it requires

- **Engine-side**: For sync cycle detection, add a DFS-based cycle check after building the adjacency list (~30 lines). For condition validation, add cross-reference between edge conditions and workload distribution types (~20 lines).
- **Shared layer**: Validation result types are already shared.
- **Renderer/frontend-side**: Validation warnings are already displayed in the simulation panel before run.

### Explored in

`src/engine/validation/validator.ts:570-847` (full validation), `src/engine/catalog/componentSpecs.ts` (inferStructuralRole referenced by resolvedRole).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Environment Definition & Configuration Model** | Topology structural rules, direction inference results | `RequestDirection` enum, per-edge environment config | `EdgeDefinition`, `RequestDirection` |
| **Request Pattern Configuration** | Request type strings that condition expressions match on (via `requestDistribution`) | `request.type` values generated by the workload | `request.type`, `EdgeDefinition.condition` |
| **Request Type Model** | Condition expression evaluation that filters by request type | Request type properties beyond the type string (deferred) | `request.type` |
| **Edge Properties & Defaults** | Route selection (which edge is chosen) | Edge properties (latency, loss, error rate) consumed during transfer | `EdgeDefinition` |
| **Throughput Calculation** | Fan-out multiplier (async branching increases effective request count) | Effective arrival rate at each node post-routing | `resolveTarget()` → route count per hop |
| **Queue Depth Calculation** | Arrival rate at a node (determined by routing decisions upstream) | Queue capacity that determines whether arrivals are accepted or rejected | Routing → arrival rate → queue occupancy |
| **Arrival, Departure & Request Lifecycle Semantics** | The routing decision that determines the next hop after processing-complete | Event types (`request-forwarded`, `request-arrival`) that bookend an edge transfer | `ResolveRoute`, edge transfer events |
| **Request Rejection Behaviour** | Edge error rate rejections (`edge_error_rate` reason) | Rejection metrics that include routing-caused failures | `enqueueEdgeTransfer` → `request-rejected` |
| **Simulation Validation & Pattern Accuracy** | Topology connectivity rules as input to structural validation | Validation regression fixtures for topology edge cases | `validateTopology()` |
| **Default-Driven Simplification Layer** | Mode inference from async boundaries, protocol inference from target type | Default values applied during serialization | `useTopologySerializer` inference logic |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| `src/engine/routing.ts` | Consume `routingStrategy` values beyond `'round-robin'` (`'weighted'`, `'passthrough'`, `'broadcast'`, `'conditional'`, `'least-conn'`) | Close the gap between the 7-value `RoutingStrategy` type and the 1 value actually consumed | ~60 lines |
| `src/engine/routing.ts` | Replace ID-substring heuristic in `isRoundRobinSource` with a deprecation warning or removal | Prevent silent routing changes from node renames | ~5 lines |
| `src/engine/validation/validator.ts` | Add sync cycle detection (DFS back-edge check) | Prevent infinite forwarding loops | ~30 lines |
| `src/engine/validation/validator.ts` | Add conditional edge condition-required check | Catch dead conditional edges at validation time | ~10 lines |
| `src/engine/validation/validator.ts` | Add condition-references-distribution-type cross-reference | Catch typos in condition expressions | ~20 lines |
| `src/engine/core/types.ts` | Add `direction?: RequestDirection` to `EdgeDefinition` (optional, for future use) | Reserve the slot for bidirectional/response-path modeling | ~3 lines |
| Shared utility (proposed) | Extract async boundary inference from `useTopologySerializer` into `src/engine/catalog/edgeModeInference.ts` | Allow CLI and other non-renderer consumers to infer edge modes | ~20 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| Edge Directionality and Mode | `types.ts:309-339`, `useTopologySerializer.ts:195-197` | `EdgeDefinition`, `EdgeDefinition['mode']` | `serializeEdge()`, mode inference |
| Routing Strategy Selection | `routing.ts:86-129`, `routing.ts:211-222` | `RoutingStrategy`, `ResolveRoute` | `resolveTarget()`, `pickSyncRoute()`, `isRoundRobinSource()` |
| Condition-Based Filtering | `routing.ts:142-172` | `EdgeDefinition.condition` | `matchesCondition()` |
| Async Fan-Out and Branching | `engine.ts:273-308`, `engine.ts:543-565` | `Request` (cloned) | `prepareRequestsForRoutes()`, `cloneRequestForBranch()` |
| Topology Connectivity Validation | `validator.ts:570-847` | `ValidationResult`, `ValidationError` | `validateTopology()`, `collectReachableNodeIds()`, `isSourceNode()` |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | `streaming` mode will eventually have differentiated semantics (e.g., persistent connection, multiplexed messages) | Assumption | If not, `streaming` is a misleading synonym for `synchronous` |
| 2 | The round-robin ID heuristic is legacy and should be deprecated once all topologies use explicit `routingStrategy` | Assumption | Removing it would break old topology JSON files that rely on node naming conventions |
| 3 | Sync cycle detection should be an error, not a warning | Design decision | If warnings are preferred, cycles would need a depth limit or TTL to prevent infinite loops at runtime |
| 4 | Branch request IDs (`{id}::branch-{n}`) are stable and can be relied upon by external trace analysis tools | Assumption | Changing the format would break downstream consumers |
| 5 | `least-conn` routing strategy requires node state access during routing, which is not currently available to `RoutingTable` | Design constraint | Implementing `least-conn` requires either passing node state to `resolveTarget` or giving `RoutingTable` a reference to the node map |
| 6 | Fan-out from a single request does not create a "join" or "gather" pattern — each branch terminates independently | Observation | If scatter-gather semantics are needed, a new mechanism (deferred request completion until all branches complete) would be required |
| 7 | The validator's reachability check uses forward-direction BFS only; reverse reachability (can a node reach a sink?) is not checked | Observation | Nodes reachable from source but with no path to a terminal point would accumulate in-flight requests indefinitely |

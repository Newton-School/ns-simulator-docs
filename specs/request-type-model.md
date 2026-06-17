# Request Type Model

Technical feature specification defining what a "request type" is in the simulator, how types are created, how they flow through the topology, and what downstream effects they produce.

This spec consolidates the `Request` interface, the `requestDistribution` array on `WorkloadProfile`, the type-based condition matching in `RoutingTable`, and the untyped `metadata` escape hatch into a unified model of request identity. It exists because request type is the primary mechanism for heterogeneous traffic — different types consume different resources, follow different routes, and trigger different SLO evaluations — yet the current model treats type as an opaque string with no schema, no per-type properties, and no lifecycle effects beyond routing conditions. Downstream specs (throughput, queue depth, rejection, cost) all operate on requests, and their accuracy depends on whether the type model captures enough about each request to differentiate its behaviour.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Request Identity and Core Properties](#feature-1-request-identity-and-core-properties)
4. [Feature 2: Type Definition and Registration](#feature-2-type-definition-and-registration)
5. [Feature 3: Type-Aware Processing and Routing](#feature-3-type-aware-processing-and-routing)
6. [Feature 4: Type-Level SLO and Metrics](#feature-4-type-level-slo-and-metrics)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

The Request Type Model defines the schema for what distinguishes one kind of request from another in the simulation. Today, a request has a `type` string, a `sizeBytes` number, and a `priority` number — but these exist as flat fields on the `Request` interface with no type-level definition that binds them together or assigns per-type behaviour. This spec formalizes the concept of a "request type definition" that associates a type name with its properties (size, priority distribution, processing weight, SLO tier) and traces how that definition flows from workload configuration through routing and processing to metrics and analysis.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Users define request types as part of workload configuration; types appear in metrics and debugging |
| Architectural change      |  Partial | Proposes a `RequestTypeDefinition` registry that does not exist today; existing `Request` interface is unchanged |
| Domain model addition     |      Yes | Proposes `RequestTypeDefinition`, `RequestTypeId`, `RequestTypeRegistry` types |
| Validation layer          |      Yes | Proposes cross-reference validation between type definitions and condition expressions |
| Refactor of existing code |       No | Existing code works; new types extend rather than replace |

### Current pain without this model

| Pain | Who is affected | Technical cause | Consequence |
| ---- | --------------- | --------------- | ----------- |
| Request type is an opaque string | Engine developers | `Request.type` is `string` with no schema, no enum, no registry | Any string is a valid type; no compile-time or validation-time check that types used in conditions match types in the distribution |
| No per-type processing weight | Users | All requests at a node have the same service time distribution (from `ProcessingConfig.distribution`) regardless of type | Cannot model that GET requests are 10x faster than POST requests at the same service |
| No per-type SLO | Users | `SLOConfig` is per-node, not per-type | Cannot set different latency targets for read vs write requests |
| Priority is not type-derived | Users | Priority is assigned randomly (10% high, 90% normal) in `workload.ts:164`, independent of type | Cannot model that "alert" type requests always get high priority while "batch" type requests always get low priority |
| sizeBytes is per-distribution-entry, not per-type-definition | Engine developers | `requestDistribution[].sizeBytes` is a flat number alongside `type` and `weight` | If the same type appears in multiple distributions (proposed multi-workload), its size could differ — no single source of truth for type properties |
| No type-level metrics | Users | Metrics are aggregated per-node, not per-type | Cannot answer "what is the P99 latency for GET requests?" without post-processing trace data |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Request type name and identity | Yes | The `type` string and its meaning |
| Per-type properties (sizeBytes, priority, processingWeight) | Yes | Properties that travel with the request and affect processing |
| Request type definition registry | Yes | The proposed `RequestTypeDefinition` type and lookup mechanism |
| Type-to-condition mapping | Partial | This spec defines what types exist; Request Flow Direction spec defines how conditions match on them |
| Type-level SLO definitions | Yes | Proposed per-type SLO targets |
| Type-level metrics aggregation | Yes | Proposed per-type throughput, latency, rejection counts |
| Request creation and distribution selection | No | Belongs to Request Pattern Configuration |
| Request lifecycle state machine | No | Belongs to Arrival, Departure & Request Lifecycle Semantics |
| Type-based cost weighting | No | Belongs to Cost Calculation & Budgeting |

### Smallest useful v1

| v1 capability | Required? | Why |
| --- | ---: | --- |
| Formal documentation of existing Request interface | Yes | The `Request` type is central to the engine; documenting its fields and semantics is foundational |
| Type definition type proposal | Yes | Needed for environment model integration and future per-type behaviour |
| Type-condition cross-reference validation | Yes | Catches typos in condition expressions at validation time |
| Per-type processing weight | Maybe | Significant modelling improvement but requires engine changes to service time sampling |
| Per-type SLO | Deferred | Requires SLO evaluation refactoring from per-node to per-node-per-type |
| Per-type metrics | Deferred | Requires MetricsCollector refactoring for type-keyed counters |

### Deferred capabilities

| Deferred capability | Later spec | Why deferred |
| --- | --- | --- |
| Per-type cost weighting | Cost Calculation & Budgeting | Cost model does not exist yet |
| Per-type processing time distributions | This spec (future version) | Requires engine changes to select distribution based on request type |
| Per-type rejection thresholds | Request Rejection Behaviour | Rejection is currently type-agnostic |
| Type-level trace filtering | This spec (future version) | Tracer samples by request id hash, not type |

---

## Problem Context

### What exists today

**Request interface (`src/engine/core/events.ts:55-66`)**

```typescript
export interface Request {
  id: string
  type: string
  sizeBytes: number
  priority: number       // 0 = high, 1 = normal, 2 = low
  createdAt: bigint
  deadline: bigint
  path: string[]
  spans: RequestSpan[]
  retryCount: number
  metadata: Record<string, unknown>
}
```

The `Request` is the fundamental unit of work in the simulator. Every event in the system operates on a request. Key observations:

- `type` is a bare `string`. No enum, no union, no registry. The JSDoc says `"GET"`, `"POST"`, `"DB_QUERY"` — these are examples, not constraints.
- `sizeBytes` is a number assigned at creation time from `requestDistribution[].sizeBytes`. It is consumed by edge bandwidth calculations (conceptually — the engine does not currently throttle by bandwidth) and by the tracer.
- `priority` is a number where 0 = high, 1 = normal, 2 = low. Assigned randomly at creation time: `this.rng.boolean(0.1) ? 0 : 1` (10% high, 90% normal, never low). Consumed by priority queue discipline in `GGcKNode` when `discipline === 'priority'`.
- `metadata` is an untyped escape hatch. The engine uses it internally for terminal status tracking (`__terminal`). No user-facing metadata is defined.

**Request distribution (`src/engine/core/types.ts:404-412`)**

```typescript
requestDistribution: Array<{
  type: string
  weight: number
  sizeBytes: number
}>
```

This is the closest thing to a type definition: each entry associates a type string with a weight (relative frequency) and a size (bytes). But it is a workload-level construct, not a system-level type registry. Properties are coupled to the distribution rather than to the type itself.

**Type consumption points**:

| Consumer | How it uses `request.type` | File |
| --- | --- | --- |
| Conditional routing | `request.type === "X"` matching in `matchesCondition` | `routing.ts:155-168` |
| Request creation | Assigns type from distribution entry | `workload.ts:156-161` |
| Debug event projection | Included in `DebugEvent` via the underlying `SimulationEvent` | `debugTypes.ts:287-311` |
| Tracer | Not type-aware; samples by request id hash | `tracer.ts` |
| Metrics | Not type-aware; aggregates per-node only | `metrics.ts` |
| Analysis output | Not type-aware; summary and per-node only | `output.ts` |

**Priority consumption**:

`GGcKNode.dequeue()` uses `request.priority` when `discipline === 'priority'`:

```typescript
// In GGcKNode (src/engine/nodes/GGcKNode.ts)
// Priority dequeue selects the request with the lowest priority number (highest priority)
```

The priority queue uses a linear scan to find the minimum priority value. Priority 0 (high) is dequeued before priority 1 (normal). Priority 2 (low) is documented but never assigned by the workload generator.

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| No type definition separate from distribution | Type properties (size, priority) are embedded in the distribution entry, not in a reusable definition | No `RequestTypeDefinition` type exists |
| No type-aware processing | All requests take the same service time at a given node regardless of type | `GGcKNode.startProcessing` samples from `processing.distribution` without considering request type |
| No type-aware metrics | Cannot filter metrics by request type | `MetricsCollector` has no type dimension |
| No type-aware SLO | SLO evaluation is per-node only | `SLOConfig` on `ComponentNode`, not per-type |
| Priority assignment ignores type | Priority is random, not type-derived | Hardcoded in `workload.ts:164` |
| No validation of type strings | Condition expressions can reference types that don't exist in the distribution | No cross-reference check in `validateTopology` |

### What the source material explores

The Environment Definition & Configuration Model spec references request types via the workload config and defers type semantics to this spec. The Request Pattern Configuration spec defines how types are composed (via `requestDistribution`) and generated (via `pickRequestDistributionEntry`). The system mind map positions request types as a cross-cutting concern that flows from workload generation through routing to metrics.

---

## Feature 1: Request Identity and Core Properties

### What it does

Defines the set of properties that every request carries from creation to termination. These properties are the identity of the request — they determine how it is routed, processed, measured, and reported.

### Why it exists

The `Request` interface is the most-touched type in the engine: every event handler, every node operation, every metric recording, and every trace span operates on a `Request`. Understanding exactly what fields exist, where they come from, and what consumes them is prerequisite knowledge for every downstream spec.

### How it works internally

**Data source**: `Request` interface in `src/engine/core/events.ts:55-66`.

**Field-by-field data lineage**:

| Field | Set by | Set when | Consumed by | Mutable? |
| --- | --- | --- | --- | --- |
| `id` | `WorkloadGenerator.createRequest` | Request creation | Everything — primary key for maps, traces, metrics, events | No |
| `type` | `WorkloadGenerator.pickRequestDistributionEntry` | Request creation | `RoutingTable.matchesCondition` for conditional routing | No |
| `sizeBytes` | `WorkloadGenerator.pickRequestDistributionEntry` | Request creation | Edge bandwidth calculations (conceptual — not yet implemented) | No |
| `priority` | `WorkloadGenerator.createRequest` (random) | Request creation | `GGcKNode.dequeue` when discipline is `priority` | No |
| `createdAt` | `WorkloadGenerator.createRequest` | Request creation | Latency calculation: `totalLatency = clock - createdAt` | No |
| `deadline` | `WorkloadGenerator.createRequest` | Request creation | Timeout scheduling: `request.deadline <= arrivalTime` triggers timeout | No |
| `path` | `SimulationEngine.appendNodeToPath` | Each node arrival | Debug lifecycle, trace analysis | Yes — appended |
| `spans` | `GGcKNode.handleCompletion` | Each processing completion | Tracer recording, latency breakdown | Yes — appended |
| `retryCount` | Initialized to 0 | Request creation | Not currently consumed (retry logic not implemented) | Conceptually mutable |
| `metadata` | Engine internals | Various | `__terminal` flag prevents double-processing of completed requests | Yes — mutated |

**Request ID format**:

- Original requests: `req-000001`, `req-000002`, ... (zero-padded 6-digit counter)
- Branched requests: `req-000001::branch-1`, `req-000001::branch-2`, ... (original ID + branch suffix)
- The counter is per-`WorkloadGenerator` instance, the branch counter is per-`SimulationEngine` instance.

**Priority model**:

```
Priority 0 = high   (10% of requests, randomly assigned)
Priority 1 = normal (90% of requests, randomly assigned)
Priority 2 = low    (documented in JSDoc, never assigned)
```

The priority numeric value is used directly as a sort key in priority queue discipline: lower number = dequeued first. The `wfq` (weighted fair queuing) discipline does not currently use priority.

**Deadline model**:

```
deadline = createdAt + msToMicro(defaultTimeoutMs)
```

Where `defaultTimeoutMs` comes from `topology.global.defaultTimeout` (passed via `WorkloadGeneratorOptions`). The deadline is an absolute bigint microsecond timestamp. It is checked at two points:

1. **Edge transfer** (`engine.ts:757`): If `request.deadline <= arrivalTime` (the time the request would arrive at the target), a timeout is scheduled instead of an arrival.
2. **Node timeout** (`engine.ts:715`): `effectiveTimeoutAt = min(request.deadline, clock + nodeTimeout)`.

### What components it requires

- **Engine-side**: The `Request` interface is stable and complete for current functionality. No changes needed.
- **Shared layer**: Request ID format should be documented as a contract.
- **Renderer/frontend-side**: Debug panels already display all `Request` fields via `DebugEvent` projections.

### Explored in

`src/engine/core/events.ts:55-66` (Request interface), `src/engine/workload.ts:155-171` (creation), `src/engine/engine.ts:273-308` (generated event handling), `src/engine/nodes/GGcKNode.ts` (priority dequeue).

---

## Feature 2: Type Definition and Registration

### What it does

Proposes a `RequestTypeDefinition` type that formalizes the properties associated with each request type string, and a registry mechanism that makes these definitions available to the engine, validator, and analysis layer.

### Why it exists

Currently, request type properties are scattered: `type` and `sizeBytes` live in `requestDistribution`, `priority` is assigned randomly at creation time, and there are no per-type processing weights or SLO targets. This means the same type string could have different `sizeBytes` in different distributions (if multi-workload is implemented), and there is no way to express "all GET requests should have priority 1 and take 2x longer to process at database nodes."

A type definition registry centralizes these properties so every consumer — workload generator, routing table, metrics collector, SLO evaluator — can look up a type's characteristics by name.

### How it works internally

**Proposed types** (would live in `src/engine/core/types.ts` or a new `src/engine/core/requestTypes.ts`):

```typescript
/** Unique identifier for a request type. Matches the `type` string on Request. */
export type RequestTypeId = string

/**
 * Defines the properties and behaviour modifiers for a request type.
 * Replaces the flat { type, weight, sizeBytes } entry in requestDistribution
 * with a richer, reusable definition.
 */
export interface RequestTypeDefinition {
  /** Type identifier, e.g., 'GET', 'POST', 'db-read', 'alert'. */
  id: RequestTypeId

  /** Human-readable name for display in UI and reports. */
  name: string

  /** Default payload size in bytes. Overrides requestDistribution.sizeBytes when present. */
  sizeBytes: number

  /**
   * Priority assignment rule.
   * - 'fixed': all requests of this type get the specified priority.
   * - 'weighted': priority is assigned randomly with the given distribution.
   */
  priority:
    | { mode: 'fixed'; value: number }
    | { mode: 'weighted'; distribution: Array<{ priority: number; weight: number }> }

  /**
   * Processing weight multiplier applied to the node's service time distribution.
   * 1.0 = use the node's distribution as-is.
   * 2.0 = double the sampled service time.
   * 0.5 = halve the sampled service time.
   */
  processingWeight: number

  /**
   * Optional per-type SLO targets. When present, SLO evaluation considers
   * this type's requests separately from the node-level SLO.
   */
  slo?: {
    latencyP99?: number   // ms
    errorBudget?: number  // fraction [0, 1]
  }
}
```

**Proposed distribution entry update**:

```typescript
// Current:
requestDistribution: Array<{ type: string; weight: number; sizeBytes: number }>

// Proposed extension (backward-compatible):
requestDistribution: Array<{
  type: RequestTypeId        // references a type definition
  weight: number
  sizeBytes?: number         // override; falls back to type definition's sizeBytes
}>
```

The `sizeBytes` on the distribution entry becomes an optional override. If omitted, the type definition's `sizeBytes` is used. This preserves backward compatibility — existing distributions with explicit `sizeBytes` continue to work.

**Resolution flow**:

```
RequestTypeDefinition (registered)
         │
         ▼
requestDistribution[].type ──matches──> definition.id
         │
         ▼
WorkloadGenerator.createRequest():
  - type = entry.type
  - sizeBytes = entry.sizeBytes ?? definition.sizeBytes
  - priority = resolve(definition.priority)
  - metadata.processingWeight = definition.processingWeight
```

**Registry model**:

```typescript
export class RequestTypeRegistry {
  private readonly types = new Map<RequestTypeId, RequestTypeDefinition>()

  register(definition: RequestTypeDefinition): void {
    this.types.set(definition.id, definition)
  }

  get(id: RequestTypeId): RequestTypeDefinition | undefined {
    return this.types.get(id)
  }

  has(id: RequestTypeId): boolean {
    return this.types.has(id)
  }

  all(): ReadonlyMap<RequestTypeId, RequestTypeDefinition> {
    return this.types
  }
}
```

The registry would be constructed during topology normalization (after validation, before engine construction) by iterating `requestDistribution` entries and resolving type definitions from the environment config or from inline definitions. If no explicit definition exists for a type string, a default definition is synthesized:

```typescript
function defaultDefinition(entry: { type: string; sizeBytes: number }): RequestTypeDefinition {
  return {
    id: entry.type,
    name: entry.type,
    sizeBytes: entry.sizeBytes,
    priority: { mode: 'weighted', distribution: [
      { priority: 0, weight: 0.1 },
      { priority: 1, weight: 0.9 }
    ]},
    processingWeight: 1.0
  }
}
```

This preserves current behaviour (10/90 priority split, no processing weight modification) when no explicit type definitions are provided.

### What components it requires

- **Engine-side**: New `RequestTypeDefinition` and `RequestTypeRegistry` types (~60 lines). Modify `WorkloadGenerator.createRequest` to use type definitions for priority and size (~15 lines). Modify `GGcKNode.startProcessing` to apply `processingWeight` to sampled service time (~5 lines).
- **Shared layer**: Type definitions shared between engine, renderer, and environment config.
- **Renderer/frontend-side**: Type definition editor in source node configuration (alongside existing `requestDistribution` editor).

### Explored in

`src/engine/core/events.ts:55-66` (current Request), `src/engine/core/types.ts:404-412` (current distribution), `src/engine/workload.ts:155-171` (creation), Environment Model spec (type reference slots).

---

## Feature 3: Type-Aware Processing and Routing

### What it does

Describes how request type affects two runtime behaviours: (1) service time at a node (via `processingWeight` on the type definition), and (2) route selection (via condition expressions that match on `request.type`).

### Why it exists

In real systems, a database node processes a simple key-value lookup in 1ms but a complex aggregation query in 50ms. An API gateway routes `/users` requests to the user service and `/orders` requests to the order service. The current simulator models the second pattern (conditional routing) but not the first (type-dependent processing time). Both are needed for realistic capacity planning.

### How it works internally

**Routing by type (implemented)**:

As documented in the Request Flow Direction & Topology Rules spec, `RoutingTable.matchesCondition()` evaluates `request.type === "X"` expressions on conditional edges. The flow:

```
Request with type "GET"
    │
    ▼
RoutingTable.resolveTarget(sourceNodeId, request)
    │
    ▼
For each outgoing edge:
    matchesCondition(edge, request)
        │
        ├─ edge.condition = 'request.type === "GET"' → true (eligible)
        ├─ edge.condition = 'request.type === "POST"' → false (filtered out)
        └─ edge.condition = undefined → true (no filter)
    │
    ▼
Eligible edges partitioned into async/sync → route selection
```

This is the only runtime behaviour that currently differentiates requests by type.

**Processing by type (proposed)**:

Currently, `GGcKNode.startProcessing` samples service time from `this.config.processing.distribution` — the same distribution for all requests at that node. The proposal:

```
serviceTimeMs = distributions.fromConfig(node.processing.distribution)
processingWeight = requestTypeRegistry.get(request.type)?.processingWeight ?? 1.0
adjustedServiceTimeMs = serviceTimeMs * processingWeight
```

This is a simple multiplicative adjustment. A `processingWeight` of 2.0 doubles the sampled service time; 0.5 halves it. The underlying distribution shape is unchanged — only the scale is modified.

**When processing weight helps**:

| Scenario | Type | processingWeight | Effect |
| --- | --- | --- | --- |
| API service | GET (read) | 0.3 | 30% of base service time (fast reads) |
| API service | POST (write) | 1.5 | 150% of base service time (slower writes) |
| Database | key-lookup | 0.2 | Very fast lookups |
| Database | aggregation | 5.0 | 5x base time for complex queries |
| CDN | cache-hit | 0.1 | Near-instant for cached content |
| CDN | cache-miss | 3.0 | 3x base time for origin fetch |

### What components it requires

- **Engine-side**: Modify `GGcKNode.startProcessing` to accept and apply `processingWeight` (~5 lines). Pass the type registry to `GGcKNode` constructor or provide a weight lookup function.
- **Shared layer**: `processingWeight` field on `RequestTypeDefinition`.
- **Renderer/frontend-side**: Per-type processing weight editor in type definition UI.

### Explored in

`src/engine/routing.ts:142-172` (condition matching), `src/engine/nodes/GGcKNode.ts` (processing start), Request Flow Direction spec (condition feature section).

---

## Feature 4: Type-Level SLO and Metrics

### What it does

Proposes extending the SLO evaluation and metrics aggregation systems to operate per-request-type in addition to per-node. This would enable questions like "what is the P99 latency for GET requests at the API gateway?" and "is the error budget for write requests exhausted?"

### Why it exists

Per-node SLOs mask type-level problems. If an API service handles 70% GETs (fast) and 30% POSTs (slow), the node-level P99 might be healthy even when POST P99 is severely degraded — the fast GETs dilute the metric. Real SRE practice defines SLOs per endpoint (which maps to per type in the simulator). Without type-level metrics, the simulator cannot surface the most actionable capacity insights.

### How it works internally

**Current SLO evaluation (`src/engine/analysis/output.ts` — `detectSLOBreaches`)**:

SLO evaluation operates on `PerNodeMetrics` which are aggregated across all request types at each node. The check compares `latencyP99` and `errorRate` against `SLOConfig.latencyP99`, `SLOConfig.availabilityTarget`, and `SLOConfig.errorBudget`.

**Proposed per-type metrics extension**:

```typescript
export interface PerTypeNodeMetrics {
  nodeId: string
  requestType: RequestTypeId
  arrivals: number
  completions: number
  rejections: number
  timeouts: number
  latencyP50: number
  latencyP99: number
  throughput: number
  errorRate: number
}
```

This would be produced by a type-aware extension to `MetricsCollector` that maintains per-`(nodeId, requestType)` counters alongside the existing per-`nodeId` counters.

**Proposed per-type SLO evaluation**:

```typescript
export interface TypeSLOBreach {
  nodeId: string
  requestType: RequestTypeId
  metric: 'latencyP99' | 'errorBudget'
  threshold: number
  actual: number
}
```

Type-level SLO evaluation would check `RequestTypeDefinition.slo` targets (when defined) against `PerTypeNodeMetrics` for that type at each node.

**Data flow**:

```
MetricsCollector.recordRequest(request)
    │
    ├─ Existing: aggregate into PerNodeMetrics
    └─ Proposed: also aggregate into PerTypeNodeMetrics[request.type]

generateSimulationOutput()
    │
    ├─ Existing: perNode metrics, SLO breaches
    └─ Proposed: perTypePerNode metrics, type-level SLO breaches
```

### What components it requires

- **Engine-side**: Extend `MetricsCollector` with type-keyed counters (~50 lines). Extend `generateSimulationOutput` to produce per-type metrics and SLO breaches (~30 lines).
- **Shared layer**: `PerTypeNodeMetrics` and `TypeSLOBreach` types.
- **Renderer/frontend-side**: Type-filtered views in metrics dashboards and SLO breach panels.

### Explored in

`src/engine/analysis/output.ts` (SLO evaluation), `src/engine/metrics.ts` (metrics collection), `src/engine/core/events.ts:55-66` (Request.type field).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Environment Definition & Configuration Model** | Type definitions as part of environment config | Environment-level type defaults and overrides | `RequestTypeDefinition`, `RequestTypeId` |
| **Request Pattern Configuration** | Type identity (name, properties) for each distribution entry | Type strings and weights from `requestDistribution` | `RequestTypeId`, `requestDistribution[].type` |
| **Request Flow Direction & Topology Rules** | Type strings that condition expressions evaluate | Condition matching results | `request.type`, `EdgeDefinition.condition` |
| **Edge Properties & Defaults** | `request.sizeBytes` for bandwidth calculations | Edge properties consumed during transfer | `Request.sizeBytes` |
| **Throughput Calculation** | Per-type arrival rate (type weight * total arrival rate) | Per-type throughput as a derived metric | Type weights → per-type λ |
| **Queue Depth Calculation** | Processing weight that affects service time → queue occupancy | Queue depth per type (proposed) | `processingWeight` → adjusted service time |
| **Arrival, Departure & Request Lifecycle Semantics** | Request properties (priority, deadline, type) that affect lifecycle transitions | Lifecycle events that produce per-type metrics | `Request` fields |
| **Request Rejection Behaviour** | Per-type rejection rates and reasons | Rejection metrics aggregated by type | `request.type` on rejected requests |
| **Cost Calculation & Budgeting** | Per-type resource consumption weights for cost modeling | Cost per request type | `processingWeight`, `sizeBytes` |
| **Simulation Validation & Pattern Accuracy** | Type definitions as input to distribution accuracy checks | Validation fixtures for type consistency | `RequestTypeDefinition` |
| **Default-Driven Simplification Layer** | Type definition presets for common scenarios | Preset selection UI that hides type complexity | `RequestTypeDefinition` |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| `src/engine/core/types.ts` (or new `requestTypes.ts`) | Add `RequestTypeDefinition`, `RequestTypeId`, `RequestTypeRegistry` types | Formalize type definitions | ~70 lines new types |
| `src/engine/workload.ts` | Modify `createRequest` to resolve priority and sizeBytes from type registry | Replace hardcoded priority assignment with type-derived values | ~15 lines |
| `src/engine/nodes/GGcKNode.ts` | Apply `processingWeight` in `startProcessing` | Enable type-dependent service times | ~5 lines |
| `src/engine/metrics.ts` | Add per-`(nodeId, type)` counters to `MetricsCollector` | Enable type-level metrics | ~50 lines |
| `src/engine/analysis/output.ts` | Extend `SimulationOutput` with `perTypePerNode` metrics and type-level SLO breaches | Expose type-level analysis | ~40 lines |
| `src/engine/validation/validator.ts` | Add cross-reference: condition strings reference existing distribution types | Catch condition typos | ~20 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| Request Identity | `events.ts:55-66` | `Request`, `RequestSpan` | `createEvent()` |
| Type Definition | Proposed: `requestTypes.ts` | `RequestTypeDefinition`, `RequestTypeId`, `RequestTypeRegistry` | `register()`, `get()` |
| Type-Aware Processing | `GGcKNode.ts`, `workload.ts:155-171` | `Request.type`, `processingWeight` | `startProcessing()`, `createRequest()` |
| Type-Level SLO/Metrics | `metrics.ts`, `output.ts` | `PerTypeNodeMetrics`, `TypeSLOBreach` | `recordRequest()`, `generateSimulationOutput()` |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | `processingWeight` is a multiplicative scalar applied to the sampled service time, not an additive offset | Design decision | Additive would give different distributional properties; multiplicative preserves the shape |
| 2 | Type definitions are optional — existing topologies with plain `requestDistribution` entries continue to work with synthesized default definitions | Assumption | If required, backward compatibility breaks |
| 3 | Per-type metrics are additive to, not replacing, per-node metrics | Assumption | Replacing would break existing dashboards and analysis |
| 4 | The `metadata` field on `Request` can carry the `processingWeight` as a computed property without adding a new field to the `Request` interface | Implementation choice | Adding a field to `Request` is cleaner but requires broader changes |
| 5 | Priority model should support both fixed (type-determined) and weighted (probabilistic) assignment | Design decision | Fixed-only is simpler but loses the ability to model priority jitter |
| 6 | `sizeBytes` override on distribution entry takes precedence over type definition's `sizeBytes` | Backward-compatibility requirement | If reversed, existing distributions with explicit sizes would change behaviour |

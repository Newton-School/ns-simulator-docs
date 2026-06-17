# Edge Properties & Defaults

Technical feature specification defining the property model for edges in the simulation topology: latency distributions, packet loss, error rates, bandwidth, concurrency limits, protocol semantics, path type classification, and the default value system that populates these properties when users don't specify them.

This spec consolidates the `EdgeDefinition` type, the `EDGE_DEFAULTS` constant in the serializer, the engine's edge transfer logic, and the validator's edge-level checks into a single reference for what an edge is, what properties it carries, and how those properties affect request transit. It exists because edges are the transport layer of the simulation — every request that moves between nodes passes through an edge, and the edge's properties determine whether the request arrives (packet loss), arrives in error (error rate), arrives late (latency distribution), or arrives at all (deadline check). The Environment Definition & Configuration Model spec proposes edge-level defaults and overrides; this spec defines what those defaults and overrides contain.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Edge Property Schema](#feature-1-edge-property-schema)
4. [Feature 2: Edge Default Value System](#feature-2-edge-default-value-system)
5. [Feature 3: Edge Transfer Mechanics](#feature-3-edge-transfer-mechanics)
6. [Feature 4: Protocol and Path Type Semantics](#feature-4-protocol-and-path-type-semantics)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Edge Properties & Defaults is the subsystem that models the network transport between nodes. Each edge carries a latency distribution (how long transit takes), a packet loss rate (probability of silent failure), an error rate (probability of explicit failure), bandwidth and concurrency limits (capacity constraints), a protocol (communication semantics), and a path type (network topology classification). The default system provides sensible values for all properties so users can draw edges without configuring each one.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Users configure edge properties on the canvas; properties affect simulation results |
| Architectural change      |       No | The edge property model is implemented; this spec formalizes it |
| Domain model addition     |  Partial | Proposes formalized path-type latency profiles; existing types are implemented |
| Validation layer          |      Yes | Documents existing edge validation and proposes additional property-level checks |
| Refactor of existing code |  Partial | Proposes migrating `EDGE_DEFAULTS` from the renderer to the environment model |

### Current pain without this model

| Pain | Who is affected | Technical cause | Consequence |
| ---- | --------------- | --------------- | ----------- |
| Edge defaults are renderer-only | Engine developers, CLI users | `EDGE_DEFAULTS` is defined in `src/renderer/src/hooks/useTopologySerializer.ts:28-36` — a renderer concern | Topology JSON created outside the renderer (CLI, tests, API) must specify all edge properties explicitly or rely on the engine's Zod defaults |
| Path type is cosmetic | Users | `latency.pathType` is set on each edge but the engine does not adjust latency based on it | `same-rack` and `cross-region` edges can have identical latency distributions, misleading users who expect path type to matter |
| Bandwidth is not enforced | Users | `EdgeDefinition.bandwidth` is a required field set to 1000 Mbps by default, but the engine never throttles or queues based on it | Bandwidth appears in the config but has no runtime effect |
| maxConcurrentRequests is not enforced | Users | `EdgeDefinition.maxConcurrentRequests` is required and defaulted to 100, but the engine never tracks or limits concurrent in-flight requests per edge | Concurrency limits appear in the config but have no runtime effect |
| Error rate and packet loss rate are percentages in the renderer, ratios in the engine | Developers | `useTopologySerializer` converts percent → ratio via `normalizePercentToRatio`; the `EdgeDefinition` stores ratios (0.0-1.0) | Confusion over whether a value is a percentage or ratio; the serializer silently clamps and converts |
| No edge-level metrics | Users | The engine does not track per-edge throughput, latency percentiles, loss count, or error count | Cannot answer "how much traffic flows through edge X?" or "what is the P99 latency on this link?" |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Edge property schema (all fields on EdgeDefinition) | Yes | Defines what each field means and how it's used |
| Edge default values and fallback chain | Yes | Defines the default system |
| Edge transfer mechanics (loss, error, latency sampling) | Yes | Defines what happens during transit |
| Protocol semantic effects | Partial | Documents current protocol values; actual protocol-level behaviour is mostly unimplemented |
| Path type to latency mapping | Yes | Proposes formalizing what path type means for latency |
| Edge mode semantics | No | Belongs to Request Flow Direction & Topology Rules |
| Routing strategy (which edge is selected) | No | Belongs to Request Flow Direction & Topology Rules |
| Environment-level edge defaults and overrides | No (attachment point) | Belongs to Environment Definition & Configuration Model; this spec defines what can be defaulted |

### Smallest useful v1

| v1 capability | Required? | Why |
| --- | ---: | --- |
| Formal documentation of all EdgeDefinition fields | Yes | Undocumented beyond JSDoc; critical for understanding simulation behaviour |
| Default value system documentation | Yes | Defaults are scattered across renderer and validator; need a single reference |
| Edge transfer mechanics documentation | Yes | The loss → error → latency → deadline pipeline is the core of edge behaviour |
| Path type latency profiles | Maybe | Would make path type meaningful at runtime; can be deferred |
| Bandwidth enforcement | Deferred | Requires queuing model per edge; significant engine change |
| Concurrency enforcement | Deferred | Requires in-flight tracking per edge; moderate engine change |
| Per-edge metrics | Deferred | Requires MetricsCollector extension |

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
  bandwidth: number           // Mbps
  maxConcurrentRequests: number
  packetLossRate: number      // [0.0, 1.0]
  errorRate: number           // [0.0, 1.0]
  weight?: number
  condition?: string
  sourceHandle?: string
  targetHandle?: string
  animated?: boolean
}
```

All properties except `label`, `weight`, `condition`, `sourceHandle`, `targetHandle`, and `animated` are required on the wire. Defaults are applied during serialization, not at the engine level.

**EDGE_DEFAULTS (`src/renderer/src/hooks/useTopologySerializer.ts:28-36`)**

```typescript
const EDGE_DEFAULTS = {
  latencyMu: 2.3,
  latencySigma: 0.5,
  pathType: 'same-dc' as const,
  bandwidth: 1000,
  maxConcurrentRequests: 100,
  packetLossRatePercent: 0,
  errorRatePercent: 0.1
}
```

These defaults are applied during canvas-to-topology serialization in `serializeEdge()`:
- `latencyMu` and `latencySigma` become a `log-normal` distribution: `{ type: 'log-normal', mu: 2.3, sigma: 0.5 }`. The mean latency is `e^(2.3 + 0.5²/2) ≈ 11.2 ms` with significant right-tail variance.
- `packetLossRatePercent: 0` → `packetLossRate: 0.0` (zero loss)
- `errorRatePercent: 0.1` → `errorRate: 0.001` (0.1% error rate)

**Edge transfer in the engine (`src/engine/engine.ts:728-770`)**

`enqueueEdgeTransfer(request, edge, targetNodeId)` implements the transit pipeline:

```
Step 1: Packet loss check
  rng < edge.packetLossRate → schedule request-timeout (silently dropped)

Step 2: Error rate check
  rng < edge.errorRate → schedule request-rejected (reason: edge_error_rate)

Step 3: Sample latency
  latencyMs = distributions.fromConfig(edge.latency.distribution)
  arrivalTime = clock + msToMicro(max(0, latencyMs))

Step 4: Deadline check
  request.deadline <= arrivalTime → schedule request-timeout (too slow)

Step 5: Schedule arrival
  schedule request-arrival at targetNodeId at arrivalTime
```

Steps 1-4 are short-circuit exits — if any triggers, subsequent steps are skipped. This means a lost packet never incurs latency, and an error never incurs latency either.

**Latency sampling (`engine.ts:490-493`)**

```typescript
private sampleEdgeLatencyUs(edge: EdgeDefinition): bigint {
  const latencyMs = Math.max(0, this.distributions.fromConfig(edge.latency.distribution))
  return msToMicro(latencyMs)
}
```

The sampled value is clamped to a minimum of 0 ms. The distribution config can be any of the 14 supported distributions — while the serializer always produces `log-normal`, topology JSON from other sources can use `constant`, `uniform`, `exponential`, etc.

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| Path type has no runtime effect | Users expect `cross-region` to be slower than `same-rack` | Engine ignores `pathType`; latency comes only from the distribution |
| Bandwidth not enforced | `bandwidth: 1000` Mbps appears in config but requests are never throttled | No per-edge queuing or rate limiting in the engine |
| Concurrency not enforced | `maxConcurrentRequests: 100` appears but is never checked | No in-flight counter per edge |
| Protocol has no runtime effect | `https` and `grpc` produce identical behaviour | Protocol is informational only; no overhead, framing, or connection semantics |
| Edge defaults are not accessible outside the renderer | CLI-created topologies must hardcode all values | `EDGE_DEFAULTS` is in `useTopologySerializer.ts` |
| No per-edge metrics | Cannot measure edge utilization, loss events, or latency distribution | `MetricsCollector` has no edge dimension |
| Percent-to-ratio conversion is implicit | Developers must know the serializer converts percents | `normalizePercentToRatio` is called silently in `serializeEdge` |

### What the source material explores

The Environment Definition & Configuration Model spec proposes `EnvironmentEdgeDefaults` and `EnvironmentEdgeConfig` types that would own edge default values (replacing `EDGE_DEFAULTS`) and per-edge overrides. The system mind map positions edge transfer as a pipeline step between routing decisions and node arrival.

---

## Feature 1: Edge Property Schema

### What it does

Defines every property on `EdgeDefinition`, its type, its valid range, its default value, and its runtime effect (or lack thereof).

### Why it exists

`EdgeDefinition` has 15+ fields, some with runtime effects and some purely informational. Without a single reference, users and developers must infer behaviour from reading the engine code.

### How it works internally

**Complete property table**:

| Property | Type | Required | Default (from serializer) | Runtime effect | Range |
| --- | --- | --- | --- | --- | --- |
| `id` | `string` | Yes | Auto-generated: `${source}->${target}` | Edge identity for routing, debugging, tracing | Non-empty |
| `source` | `string` | Yes | From canvas edge | Edge origin node — routing table adjacency list key | Must reference existing node |
| `target` | `string` | Yes | From canvas edge | Edge destination node — where requests arrive | Must reference existing node |
| `label` | `string?` | No | `undefined` | Display only — shown on canvas edge | Any string |
| `mode` | Literal union | Yes | Inferred from target's `asyncBoundary` | Routing: async = fan-out, sync = compete | `synchronous\|asynchronous\|streaming\|conditional` |
| `protocol` | Literal union | Yes | Inferred from target component type | **None** — informational only | `https\|grpc\|tcp\|udp\|websocket\|amqp\|kafka` |
| `latency.distribution` | `DistributionConfig` | Yes | `{ type: 'log-normal', mu: 2.3, sigma: 0.5 }` | Sampled for each transit; determines arrival time | Any valid distribution config |
| `latency.pathType` | Literal union | Yes | `'same-dc'` | **None** — informational only | `same-rack\|same-dc\|cross-zone\|cross-region\|internet` |
| `bandwidth` | `number` | Yes | `1000` (Mbps) | **None** — not enforced | Positive number |
| `maxConcurrentRequests` | `number` | Yes | `100` | **None** — not enforced | Positive integer |
| `packetLossRate` | `number` | Yes | `0.0` (from 0%) | Probability of silent drop → request-timeout | `[0.0, 1.0]` |
| `errorRate` | `number` | Yes | `0.001` (from 0.1%) | Probability of explicit failure → request-rejected (edge_error_rate) | `[0.0, 1.0]` |
| `weight` | `number?` | No | `undefined` (treated as 1 in weighted selection) | Routing: weighted random selection probability | Positive number or undefined |
| `condition` | `string?` | No | `undefined` | Routing: condition-based edge filtering | `request.type === "X"` format |
| `sourceHandle` | `string?` | No | From canvas | React Flow metadata — no engine effect | Any string |
| `targetHandle` | `string?` | No | From canvas | React Flow metadata — no engine effect | Any string |
| `animated` | `boolean?` | No | `undefined` | React Flow metadata — no engine effect | boolean |

**Properties with runtime effect**: `mode`, `latency.distribution`, `packetLossRate`, `errorRate`, `weight`, `condition`.

**Properties without runtime effect**: `protocol`, `latency.pathType`, `bandwidth`, `maxConcurrentRequests`, `label`, `sourceHandle`, `targetHandle`, `animated`.

### What components it requires

- **Engine-side**: No changes for documenting existing properties. For enforcing bandwidth and concurrency, see deferred capabilities.
- **Shared layer**: Property documentation should be reflected in updated JSDoc on `EdgeDefinition`.
- **Renderer/frontend-side**: Edge configuration panels already expose most properties.

### Explored in

`src/engine/core/types.ts:309-339` (type definition), `src/renderer/src/hooks/useTopologySerializer.ts:180-223` (serialization with defaults).

---

## Feature 2: Edge Default Value System

### What it does

Defines the cascade of default values that populate edge properties when users don't specify them. Currently, defaults are applied in the renderer during serialization. This feature documents the current system and proposes migrating defaults to the environment model for engine-level accessibility.

### Why it exists

Most users draw edges on the canvas and accept default values — they don't configure latency distributions or error rates per edge. The default system must be sensible, consistent, and accessible to all topology creators (renderer, CLI, tests, API). Currently, only the renderer applies defaults, creating an asymmetry.

### How it works internally

**Current default application flow**:

```
Canvas edge (partial data: EdgeRuntimeData)
    │
    ▼
serializeEdge() in useTopologySerializer.ts:180-223
    │
    ├─ mode: infer from target asyncBoundary, fallback 'synchronous'
    ├─ protocol: infer from target componentType, fallback 'https'
    ├─ latency.distribution: log-normal(mu=2.3, sigma=0.5) if not specified
    ├─ latency.pathType: 'same-dc' if not specified
    ├─ bandwidth: 1000 Mbps if not specified
    ├─ maxConcurrentRequests: 100 if not specified
    ├─ packetLossRate: 0% → 0.0 if not specified
    └─ errorRate: 0.1% → 0.001 if not specified
    │
    ▼
TopologyJSON.edges[] (all properties populated)
    │
    ▼
validateTopology() — schema validation (all required fields present)
    │
    ▼
SimulationEngine constructor — no additional edge defaults applied
```

Note: Unlike nodes (where both `validator.ts` and `engine.ts` apply defaults), edges have a single default application point: the serializer. The engine and validator assume all edge properties are already populated.

**Default value semantics**:

| Default | Value | Rationale |
| --- | --- | --- |
| `latency: log-normal(mu=2.3, sigma=0.5)` | Mean ≈ 11.2 ms, median ≈ 10.0 ms, P99 ≈ 40 ms | Realistic for same-datacenter service-to-service calls with log-normal tail |
| `pathType: 'same-dc'` | Same datacenter | Most microservice communication is within a datacenter |
| `bandwidth: 1000` Mbps | 1 Gbps | Standard datacenter NIC speed |
| `maxConcurrentRequests: 100` | 100 connections | Reasonable HTTP/2 or gRPC connection pool |
| `packetLossRate: 0%` | Zero loss | Datacenter networks have negligible packet loss |
| `errorRate: 0.1%` | 1 in 1000 | Baseline error rate for inter-service communication |
| `protocol: 'https'` | HTTPS | Default web protocol; inferred as `amqp` for queues, `kafka` for streams |

**Protocol inference logic (`useTopologySerializer.ts:162-178`)**:

```typescript
function inferProtocol(targetNode): EdgeDefinition['protocol'] {
  if (!targetNode?.componentType) return 'https'
  if (type === 'queue' || type === 'message-broker' || type === 'pub-sub') return 'amqp'
  if (type === 'stream') return 'kafka'
  return 'https'
}
```

Only 4 component types trigger protocol inference. All other ~109 types default to `https`.

**Proposed environment-level edge defaults**:

From the Environment Definition & Configuration Model spec:

```typescript
export interface EnvironmentEdgeDefaults {
  latency: {
    distribution: DistributionConfig
    pathType: EdgeDefinition['latency']['pathType']
  }
  bandwidth: number
  maxConcurrentRequests: number
  packetLossRate: number
  errorRate: number
  protocol: EdgeDefinition['protocol']
}
```

This type would live in the environment model and replace `EDGE_DEFAULTS`. The resolution order for each edge property:

```
1. Explicit per-edge value in topology JSON (or canvas edge data)
2. Per-edge override in EnvironmentEdgeConfig (by edge id)
3. Global edge default in EnvironmentEdgeDefaults
4. Hardcoded fallback (current EDGE_DEFAULTS values)
```

**Proposed path-type-aware latency defaults**:

| Path type | Default distribution | Approximate mean | Rationale |
| --- | --- | --- | --- |
| `same-rack` | `log-normal(mu=0.1, sigma=0.3)` | ~1.2 ms | Sub-millisecond network hop |
| `same-dc` | `log-normal(mu=2.3, sigma=0.5)` | ~11.2 ms | Current default; datacenter cross-rack |
| `cross-zone` | `log-normal(mu=3.0, sigma=0.4)` | ~22 ms | Multi-AZ within a region |
| `cross-region` | `log-normal(mu=4.5, sigma=0.3)` | ~95 ms | Inter-region (e.g., us-east to eu-west) |
| `internet` | `log-normal(mu=5.0, sigma=0.7)` | ~200 ms | Public internet with high variance |

These would be used when no explicit latency distribution is set on the edge and the path type is specified. This makes path type meaningful at runtime — a `cross-region` edge would automatically have higher latency than a `same-dc` edge.

### What components it requires

- **Engine-side**: For path-type-aware defaults, an edge normalization step that applies path-type latency profiles before engine construction. ~30 lines.
- **Shared layer**: Migrate `EDGE_DEFAULTS` to a shared module (e.g., `src/engine/defaults/edgeDefaults.ts`) importable by both renderer and engine.
- **Renderer/frontend-side**: Update `useTopologySerializer` to import shared defaults instead of defining local constants.

### Explored in

`src/renderer/src/hooks/useTopologySerializer.ts:28-36` (current defaults), `src/renderer/src/hooks/useTopologySerializer.ts:180-223` (serialization), Environment Model spec (EnvironmentEdgeDefaults proposal).

---

## Feature 3: Edge Transfer Mechanics

### What it does

Defines the pipeline that a request passes through when traversing an edge: packet loss sampling, error rate sampling, latency sampling, and deadline checking. This is the runtime implementation of edge properties.

### Why it exists

Edge properties are only meaningful if they produce observable effects during simulation. The transfer pipeline is where latency slows down requests, packet loss creates silent timeouts, error rates cause explicit rejections, and deadline checks prevent stale arrivals. Understanding this pipeline is essential for interpreting simulation results — users need to know why a request timed out (was it node processing or edge latency?) and what properties to tune.

### How it works internally

**Pipeline implementation — `enqueueEdgeTransfer()` in `src/engine/engine.ts:728-770`**:

```
                    ┌──────────────────┐
                    │  Request enters  │
                    │   edge transfer  │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Packet loss?    │
                    │  rng < lossRate  │
                    └──┬──────────┬────┘
                   Yes │          │ No
            ┌──────────▼──┐  ┌───▼────────────┐
            │ schedule    │  │  Error rate?    │
            │ timeout     │  │  rng < errRate  │
            │ (silently)  │  └──┬──────────┬───┘
            └─────────────┘  Yes│          │ No
                      ┌─────────▼──┐  ┌───▼────────────┐
                      │ schedule   │  │ Sample latency  │
                      │ rejected   │  │ from edge dist  │
                      │ (err_rate) │  └──────┬──────────┘
                      └────────────┘         │
                                    ┌────────▼─────────┐
                                    │ Deadline check?  │
                                    │ deadline <=      │
                                    │ arrivalTime      │
                                    └──┬──────────┬────┘
                                   Yes │          │ No
                            ┌──────────▼──┐  ┌───▼────────────┐
                            │ schedule    │  │ schedule        │
                            │ timeout     │  │ request-arrival │
                            │ (in-flight) │  │ at target node  │
                            └─────────────┘  └─────────────────┘
```

**Step 1: Packet loss** (`engine.ts:729-741`)

```typescript
if (this.distributions.random() < edge.packetLossRate) {
  const timeoutAt = request.deadline > this.clock ? request.deadline : this.clock
  this.eventQueue.insert(
    createEvent('request-timeout', targetNodeId, request.id,
      { request, nodeArrivalTime: this.clock, scope: 'in-flight' }, timeoutAt)
  )
  return
}
```

If the random sample is below the loss rate, the request is silently dropped — it never arrives at the target. A `request-timeout` event is scheduled at the request's deadline (or immediately if the deadline has passed). The `scope: 'in-flight'` data field indicates this is a transit loss, not a node timeout.

**Step 2: Error rate** (`engine.ts:743-754`)

```typescript
if (this.distributions.random() < edge.errorRate) {
  this.eventQueue.insert(
    createEvent('request-rejected', targetNodeId, request.id,
      { request, reason: 'edge_error_rate', nodeArrivalTime: this.clock }, this.clock)
  )
  return
}
```

If the random sample is below the error rate, the request fails explicitly with reason `'edge_error_rate'`. The rejection is immediate (at `this.clock`), not delayed by latency. This models scenarios like TLS handshake failures or connection refused errors.

**Step 3: Latency sampling** (`engine.ts:756`)

```typescript
const arrivalTime = this.clock + this.sampleEdgeLatencyUs(edge)
```

Samples from `edge.latency.distribution` via `Distributions.fromConfig()`. The sampled value is clamped to `max(0, ...)` and converted to microseconds. The arrival time is absolute: `currentClock + latency`.

**Step 4: Deadline check** (`engine.ts:757-766`)

```typescript
if (request.deadline <= arrivalTime) {
  this.eventQueue.insert(
    createEvent('request-timeout', targetNodeId, request.id,
      { request, nodeArrivalTime: this.clock, scope: 'in-flight' }, request.deadline)
  )
  return
}
```

If the request's absolute deadline is at or before the calculated arrival time, the request times out in transit. The timeout fires at `request.deadline`, not at `arrivalTime`.

**Step 5: Schedule arrival** (`engine.ts:767-770`)

```typescript
this.eventQueue.insert(
  createEvent('request-arrival', targetNodeId, request.id,
    { request, edge, edgeId: edge.id }, arrivalTime)
)
```

The request arrives at the target node at the sampled arrival time. The edge metadata is attached to the event data for debugging and trace correlation.

**Key observations**:

1. **Loss and error are independent**: Two separate `rng` calls. A request can "survive" loss but fail on error.
2. **Loss is silent, error is explicit**: Lost packets produce timeouts (delayed); errors produce rejections (immediate).
3. **Latency is only sampled for surviving requests**: A lost or errored request incurs no latency.
4. **Deadline is checked after latency**: A request with 50ms deadline on a `cross-region` edge (95ms mean latency) will frequently timeout in transit.

### What components it requires

- **Engine-side**: Fully implemented. For bandwidth enforcement (deferred), the transfer would need a per-edge token bucket or queue. For concurrency enforcement (deferred), the transfer would check an in-flight counter and reject or queue if at limit.
- **Shared layer**: No changes.
- **Renderer/frontend-side**: Edge inspector could show the transfer pipeline step-by-step for debugged requests (via `DebugEvent` with `edgeId`).

### Explored in

`src/engine/engine.ts:728-770` (transfer pipeline), `src/engine/engine.ts:490-493` (latency sampling), `src/engine/stochastic/distribution.ts:199-230` (fromConfig dispatch).

---

## Feature 4: Protocol and Path Type Semantics

### What it does

Documents the current semantic model (or lack thereof) for the `protocol` and `pathType` fields, and proposes making path type affect runtime latency defaults.

### Why it exists

Users configure protocol and path type on edges expecting them to matter. Currently, `protocol: 'grpc'` and `protocol: 'https'` produce identical simulation behaviour, and `pathType: 'cross-region'` and `pathType: 'same-rack'` produce identical latency (if the same distribution is configured). This gap between user expectation and runtime reality undermines trust in simulation results.

### How it works internally

**Protocol — current state**:

The 7 supported protocols (`https`, `grpc`, `tcp`, `udp`, `websocket`, `amqp`, `kafka`) are:
- Set during serialization (inferred from target component type or user-specified)
- Stored on `EdgeDefinition.protocol`
- Validated by Zod schema (must be one of the 7 values)
- **Not consumed by any engine logic**

In a real system, protocol affects overhead (HTTP/2 framing vs gRPC binary encoding), connection behavior (persistent vs per-request), and failure modes (TCP RST vs HTTP 503). None of this is modeled.

**Proposed protocol effects** (deferred):

| Protocol | Proposed effect | Why |
| --- | --- | --- |
| `https` | +0.5ms connection overhead per request (no keepalive) or 0ms (with keepalive) | TLS handshake and HTTP overhead |
| `grpc` | +0.2ms framing overhead | Binary serialization, smaller than HTTP |
| `tcp` | No additional overhead | Raw TCP is the baseline |
| `udp` | Increased `packetLossRate` modifier | UDP is lossy by nature |
| `websocket` | 0ms overhead after connection (persistent) | Single connection, no per-request overhead |
| `amqp` | +1ms broker acknowledgment | Message broker protocol overhead |
| `kafka` | +2ms batch/partition overhead | Kafka's partition-based delivery adds latency |

These would be applied as additive latency modifiers or loss rate modifiers during edge transfer.

**Path type — current state**:

The 5 path types (`same-rack`, `same-dc`, `cross-zone`, `cross-region`, `internet`) are:
- Set during serialization (user-specified or `'same-dc'` default)
- Stored on `EdgeDefinition.latency.pathType`
- Validated by Zod schema
- **Not consumed by any engine logic**

**Proposed path-type-aware defaults** (from Feature 2):

When no explicit latency distribution is configured on an edge, the path type would determine the default latency distribution. This is the lowest-effort way to make path type meaningful:

```
Edge with pathType='cross-region' and no explicit distribution
    │
    ▼
Environment edge normalization step:
    pathType → PATH_TYPE_LATENCY_PROFILES['cross-region']
             → { type: 'log-normal', mu: 4.5, sigma: 0.3 }
    │
    ▼
Edge now has meaningful latency reflecting its network topology
```

This only applies when the user has not set an explicit distribution. If they have, their distribution takes precedence regardless of path type.

### What components it requires

- **Engine-side**: For path-type defaults, a normalization step before engine construction (~20 lines). For protocol effects, additive latency/loss modifiers in `enqueueEdgeTransfer` (~30 lines each protocol).
- **Shared layer**: Path type latency profile lookup table.
- **Renderer/frontend-side**: Path type selector could show expected latency range.

### Explored in

`src/engine/core/types.ts:316-319` (protocol and path type definitions), `src/renderer/src/hooks/useTopologySerializer.ts:162-178` (protocol inference).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Environment Definition & Configuration Model** | Edge property schema, default values, path type profiles | `EnvironmentEdgeDefaults`, per-edge overrides | `EdgeDefinition`, `EnvironmentEdgeConfig` |
| **Request Pattern Configuration** | — | Request `sizeBytes` consumed by bandwidth calculations (deferred) | `Request.sizeBytes` |
| **Request Flow Direction & Topology Rules** | Edge properties consumed during transfer after route selection | Route selection results (which edges) | `ResolveRoute.edge` → `enqueueEdgeTransfer` |
| **Request Type Model** | — | `request.sizeBytes` per type for bandwidth modeling | `Request.sizeBytes` |
| **Throughput Calculation** | Edge-level throughput (requests/sec per edge, deferred) | — | Per-edge metrics |
| **Queue Depth Calculation** | Edge-induced latency that affects total latency and deadline pressure | — | Sampled latency values |
| **Arrival, Departure & Request Lifecycle Semantics** | Edge transfer as the transition between forwarded and arrived states | `request-forwarded` → edge → `request-arrival` event sequence | Edge transfer events |
| **Request Rejection Behaviour** | `edge_error_rate` rejection reason | Rejection metrics and causes | `request-rejected` with `reason: 'edge_error_rate'` |
| **Cost Calculation & Budgeting** | Bandwidth and protocol as cost factors (data transfer costs) | — | `bandwidth`, `protocol` |
| **Simulation Validation & Pattern Accuracy** | Edge latency distributions as validation targets | Empirical latency measurements vs configured distributions | `latency.distribution` vs observed |
| **Default-Driven Simplification Layer** | Edge defaults as the simplification mechanism (draw edge, accept defaults) | Progressive disclosure rules for edge properties | `EDGE_DEFAULTS`, path type presets |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| New: `src/engine/defaults/edgeDefaults.ts` | Extract `EDGE_DEFAULTS` to a shared module | Enable CLI and engine-level access to edge defaults | ~20 lines |
| `src/renderer/src/hooks/useTopologySerializer.ts` | Import shared defaults instead of local constant | Single source of truth for default values | ~5 lines |
| `src/engine/engine.ts` or new normalization step | Apply path-type-aware latency defaults for edges without explicit distributions | Make path type meaningful at runtime | ~30 lines |
| `src/engine/validation/validator.ts` | Add edge property range checks (packetLossRate ∈ [0,1], errorRate ∈ [0,1], bandwidth > 0) | Catch out-of-range values at validation | ~15 lines |
| `src/engine/metrics.ts` | Add per-edge counters (deferred) | Enable edge-level metrics | ~40 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| Edge Property Schema | `types.ts:309-339` | `EdgeDefinition` | — |
| Edge Default System | `useTopologySerializer.ts:28-36, 180-223` | `EDGE_DEFAULTS`, `EdgeRuntimeData` | `serializeEdge()`, `inferProtocol()` |
| Edge Transfer Mechanics | `engine.ts:728-770, 490-493` | — | `enqueueEdgeTransfer()`, `sampleEdgeLatencyUs()` |
| Protocol/Path Semantics | `types.ts:315-319` | Protocol union, PathType union | — |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | Bandwidth enforcement (per-edge queuing/throttling) is deferred to a later version | Assumption | Users expecting bandwidth to limit throughput will get inaccurate results |
| 2 | Concurrency enforcement is deferred | Assumption | Same: `maxConcurrentRequests` is cosmetic |
| 3 | Path-type-aware latency defaults should only apply when no explicit distribution is configured | Design decision | If always applied (as a modifier on top of explicit distributions), it changes the meaning of user-configured latency |
| 4 | Protocol effects should be additive latency modifiers, not multiplicative | Design decision | Multiplicative would scale with the base distribution; additive is constant overhead |
| 5 | The packet loss → error rate → latency → deadline order in the transfer pipeline is intentional and should not change | Observation | Reordering (e.g., latency before loss) would change which events are produced for the same configuration |
| 6 | Error rate rejections are immediate (at `this.clock`), not delayed by latency | Observation | Real errors arrive after some latency; the current model is a simplification |
| 7 | Log-normal is the right default distribution for network latency | Assumption | Empirically validated for datacenter traffic; may not fit internet-path or satellite links |

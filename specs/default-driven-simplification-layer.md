# Default-Driven Simplification Layer

Technical feature specification defining the three-tier default system that allows users to run meaningful simulations without configuring every parameter: product-level hard defaults built into the engine and renderer, per-component-type computed defaults from the catalog, and the proposed environment-level global defaults. This spec consolidates the scattered default application points into a single reference and identifies the duplication, inconsistency, and missing abstraction that a unified default layer would resolve.

This spec exists because defaults are the primary simplification mechanism — a user can drop a node on the canvas, connect an edge, and click "simulate" without setting a single parameter. Every parameter that isn't explicitly configured gets a default from one of three sources, and those sources currently don't coordinate.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Engine & Renderer Hard Defaults](#feature-1-engine--renderer-hard-defaults)
4. [Feature 2: Catalog-Computed Defaults](#feature-2-catalog-computed-defaults)
5. [Feature 3: Environment-Level Global Defaults](#feature-3-environment-level-global-defaults)
6. [Feature 4: Default Resolution & Precedence](#feature-4-default-resolution--precedence)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

The Default-Driven Simplification Layer provides sensible parameter values at every level of the simulation so that users only configure what they care about. It operates in three tiers: (1) hard defaults embedded in engine and renderer code, (2) per-component-type computed defaults from the catalog system, and (3) a proposed environment-level global default layer that would sit between product defaults and user overrides. The layer's goal is zero-configuration simulation with reasonable results.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Users rely on defaults for every simulation; bad defaults produce misleading output |
| Architectural change      |      Yes | Unifying three independent default sources requires a resolution pipeline |
| Domain model addition     |      Yes | Proposed `EnvironmentConfig` and `DefaultResolutionTrace` |
| Validation layer          |  Partial | Validator applies defaults and warns; this spec owns the default values themselves |
| Refactor of existing code |      Yes | Eliminate duplication between engine.ts and validator.ts default application |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Engine hard defaults (`withNodeDefaults`) | Yes | Values and application logic |
| Renderer edge defaults (`EDGE_DEFAULTS`) | Yes | Values and serialization logic |
| Scenario state defaults (`DEFAULT_SCENARIO_STATE`) | Yes | Global config defaults |
| Workload pattern sub-object defaults | Yes | Bursty, spike, sawtooth, diurnal defaults in `mergeWorkload` |
| Workload generator fallback constants | Yes | `DEFAULT_TIMEOUT_MS`, `DEFAULT_BURST_MULTIPLIER`, etc. |
| Catalog computed defaults (`buildSeededSimulationConfig`) | Yes | Per-type default derivation algorithm |
| Per-type service time defaults (`TYPE_MEAN_SERVICE_MS`) | Yes | Default service times for ~40 component types |
| Environment-level global defaults (proposed) | Yes | New configuration layer |
| Default resolution precedence | Yes | Which default wins when multiple sources apply |
| Parameter accuracy classification of defaults | Partial | Classification belongs to Simulation Validation; this spec tags values as defaulted |

---

## Problem Context

### What exists today

Defaults are applied at five independent locations in the codebase, with no coordination between them:

| Location | File | What it defaults | When it runs |
| --- | --- | --- | --- |
| Engine node defaults | `engine.ts:627-636` | `queue`, `processing` | Engine construction (runtime) |
| Validator node defaults | `validator.ts:616-631` | `queue`, `processing` (identical values) | Pre-run validation |
| Renderer edge defaults | `useTopologySerializer.ts:28-36` | Edge latency, bandwidth, packetLoss, errorRate | Canvas → JSON serialization |
| Scenario state defaults | `ui.ts:77-87` | Duration, warmup, seed, timeout, traceSampleRate | UI initialization |
| Workload generator defaults | `workload.ts:5-9` | Timeout, burst multiplier, burst/normal/ramp duration | Workload generation |
| Catalog computed defaults | `componentSpecs.ts:95-177` | Workers, capacity, service time, timeout, error rates | Node serialization from canvas |
| Workload merge defaults | `useTopologySerializer.ts:114-160` | Bursty, spike, sawtooth, diurnal sub-objects | Workload merging |

### What's missing

| Gap | Impact |
| --- | --- |
| Validator and engine apply identical defaults independently | Code duplication; risk of divergence if one is updated without the other |
| No single registry of all defaults | Impossible to answer "what defaults does this node get?" without reading 5 files |
| Edge defaults are renderer-only | Engine never applies edge defaults; a topology created programmatically (not via canvas) gets no edge defaults |
| No environment-level defaults | Users who want "all nodes in staging have 2 workers" must configure each node individually |
| No default provenance tracking | Output cannot distinguish user-configured from defaulted parameters |
| Catalog defaults and engine defaults have different scopes | Catalog uses exponential distribution; engine falls back to constant — contradictory |
| `timeResolution` is hardcoded to `'millisecond'` | Not configurable; always defaulted in `buildScenarioGlobal` |

---

## Feature 1: Engine & Renderer Hard Defaults

### Engine node defaults

**Location:** `withNodeDefaults` at `engine.ts:627-636`

```typescript
private withNodeDefaults(node: ComponentNode): ComponentNode {
  return {
    ...node,
    queue: node.queue ?? { workers: 1, capacity: 100, discipline: 'fifo' },
    processing: node.processing ?? {
      distribution: { type: 'constant', value: 1 },
      timeout: 30_000
    }
  }
}
```

Applied to every node during engine construction (line 78). Uses nullish coalescing — the entire `queue` or `processing` block is replaced if absent, but individual fields within a present block are not defaulted.

**Default values:**

| Parameter | Default | Meaning |
| --- | --- | --- |
| `queue.workers` | 1 | Single worker (no parallelism) |
| `queue.capacity` | 100 | 100 total slots (workers + queue) |
| `queue.discipline` | `'fifo'` | First-in-first-out |
| `processing.distribution` | `{ type: 'constant', value: 1 }` | 1ms constant service time |
| `processing.timeout` | 30,000 | 30 second timeout |

### Validator node defaults (duplicate)

**Location:** `validator.ts:616-631`

Identical values applied during validation. The validator also emits warnings:
- `"Node '${node.label}' is missing queue config; applying legacy default queue settings."`
- `"Node '${node.label}' is missing processing config; applying legacy default processing settings."`

The validator *mutates* the node in place (not a copy), so the defaults are baked into the `TopologyJSON` data that the engine receives. This means `withNodeDefaults` in the engine is actually redundant — by the time the engine sees the node, the validator has already applied defaults. The engine defaults serve as a safety net for topologies that bypass validation (e.g., programmatic construction).

### Renderer edge defaults

**Location:** `EDGE_DEFAULTS` at `useTopologySerializer.ts:28-36`

```typescript
const EDGE_DEFAULTS = {
  latencyMu: 2.3,           // log-normal mu (≈10ms median)
  latencySigma: 0.5,        // log-normal sigma
  pathType: 'same-dc',      // same data center
  bandwidth: 1000,           // 1000 Mbps
  maxConcurrentRequests: 100,
  packetLossRatePercent: 0,  // 0% loss
  errorRatePercent: 0.1      // 0.1% error rate
}
```

Applied during `serializeEdge` (lines 180-223). Unlike node defaults, these are only applied in the renderer serializer — the engine has no edge defaults. A programmatically created `EdgeDefinition` without these values would get `0` for packetLoss and errorRate (from Zod defaults in the schema), but no latency distribution default.

**Gap:** `bandwidth`, `maxConcurrentRequests`, and `pathType` have no runtime effect. They're serialized into the `EdgeDefinition` but never consumed by the engine.

### Scenario state defaults

**Location:** `DEFAULT_SCENARIO_STATE` at `ui.ts:77-87`

```typescript
export const DEFAULT_SCENARIO_STATE: ScenarioState = {
  global: {
    simulationDuration: 60_000,   // 60 seconds
    warmupDuration: 5_000,        // 5 seconds
    seed: 'default-seed',
    defaultTimeout: 5_000,        // 5 seconds
    traceSampleRate: 0.01         // 1% of requests traced
  },
  selectedSourceNodeId: undefined,
  workloadOverride: {}
}
```

Applied when the UI initializes or when saved state is invalid. Note that `defaultTimeout` here is 5,000ms, while the engine's `processing.timeout` default is 30,000ms. These are different parameters — `defaultTimeout` is a global fallback for nodes without per-node timeout, while `processing.timeout` is the per-node timeout. But the naming suggests they serve the same purpose, which is confusing.

### Workload generator defaults

**Location:** `workload.ts:5-9`

```typescript
const DEFAULT_TIMEOUT_MS = 30_000
const DEFAULT_BURST_MULTIPLIER = 5
const DEFAULT_BURST_DURATION_MS = 5_000
const DEFAULT_NORMAL_DURATION_MS = 10_000
const DEFAULT_RAMP_DURATION_MS = 10_000
```

These are internal fallbacks for when workload pattern sub-objects don't specify all parameters. They're never exposed to the user or documented.

---

## Feature 2: Catalog-Computed Defaults

### buildSeededSimulationConfig

**Location:** `componentSpecs.ts:95-177`

The catalog computes per-component-type defaults from seed metrics (UI panel values) and component type knowledge. This is a more sophisticated default system than the engine's flat fallbacks.

**Input:** `LegacySeedMetrics` (optional) + `ComponentType` + `ComponentCategory`

**Algorithm:**
1. Start with resource hints: `vCPU` (default 4), `ram` (default 8 GB)
2. Derive workers from multiple signals:
   - `workersFromThroughput = ceil(throughput / 10,000)`
   - `workersFromQueueDepth = max(1, round(sqrt(queueDepth + 1)))`
   - `workersFromUtilization = max(1, round(utilization × 8))`
   - `workersFromCpu = max(1, round(vCPU × 2))`
   - Final: `min(MAX_DERIVED_WORKERS, max(all four))`
3. Derive capacity from workers + queue depth + memory boost
4. Derive service time from:
   - Seed value (explicit) OR
   - `TYPE_MEAN_SERVICE_MS[componentType]` (per-type lookup, ~40 types) OR
   - Throughput-based derivation OR
   - Fallback: `10 + utilization × 90` ms
5. Apply overload preview: if `seed.overloadPreview`, reduce workers by 25% and double service time
6. Apply CPU scaling factor: `cpuServiceFactor = clamp(4 / vCPU, 0.2, 4)`
7. Apply category minimum: e.g., `storage-and-data` ≥ 3ms, `external-and-integration` ≥ 50ms
8. Derive timeout: `max(100, round(meanServiceMs × 40))`
9. Build `NodeSimulationConfig` with exponential distribution (not constant!)

### TYPE_MEAN_SERVICE_MS

**Location:** `componentSpecs.ts:17-59`

A partial map of ~40 component types to default mean service times:

| Type | Default ms | Category |
| --- | --- | --- |
| `in-memory-cache` | 0.1 | storage-and-data |
| `relational-db` | 8 | storage-and-data |
| `api-gateway` | 1 | network-and-edge |
| `load-balancer` | 0.2 | network-and-edge |
| `third-party-api-connector` | 150 | external-and-integration |
| `llm-gateway` | 6 | data-infra-and-analytics |
| (other types) | varies | varies |

Types not in this map fall through to the throughput-based or utilization-based derivation.

### Inconsistency: constant vs. exponential

The engine's `withNodeDefaults` uses `{ type: 'constant', value: 1 }` — deterministic 1ms service time. The catalog's `buildSeededSimulationConfig` uses `{ type: 'exponential', lambda: 1 / meanServiceMs }` — stochastic service time with the correct distribution for a queuing model.

This means:
- A node created via the canvas (with catalog defaults) gets an exponential distribution
- A node created programmatically (without catalog, falling back to engine defaults) gets a constant distribution
- The engine default is unrealistic for queuing analysis; the catalog default is correct

---

## Feature 3: Environment-Level Global Defaults

### Proposed design

An environment configuration layer sits between product hard defaults and per-node user overrides. This allows topology-wide settings like "all nodes in staging have 2 workers and 200 capacity" without configuring each node individually.

### Proposed types

```typescript
interface EnvironmentConfig {
  name: string;                    // e.g., 'production', 'staging', 'load-test'
  nodeDefaults?: {
    queue?: Partial<QueueConfig>;
    processing?: Partial<ProcessingConfig>;
    nodeErrorRate?: number;
  };
  edgeDefaults?: {
    latency?: { distribution: DistributionConfig };
    bandwidth?: number;
    packetLossRate?: number;
    errorRate?: number;
  };
  globalDefaults?: Partial<GlobalConfig>;
}
```

### Placement in TopologyJSON

```typescript
interface TopologyJSON {
  // ... existing fields ...
  environment?: EnvironmentConfig;
}
```

When present, `environment.nodeDefaults` override product hard defaults but are overridden by per-node configuration. Similarly for edges and global config.

### Resolution order (proposed)

For a node parameter like `queue.workers`:
1. **Per-node value** — explicitly set on the node → use it
2. **Environment default** — set on `environment.nodeDefaults.queue.workers` → use it
3. **Catalog computed default** — from `buildSeededSimulationConfig` → use it
4. **Product hard default** — from `withNodeDefaults` → use it

For an edge parameter like `latency.distribution`:
1. **Per-edge value** — explicitly set on the edge → use it
2. **Environment default** — set on `environment.edgeDefaults.latency` → use it
3. **Renderer default** — from `EDGE_DEFAULTS` → use it

For a global parameter like `simulationDuration`:
1. **Per-scenario value** — set in scenario state → use it
2. **Environment default** — from `environment.globalDefaults` → use it
3. **Product default** — from `DEFAULT_SCENARIO_STATE` → use it

### Environment presets

```typescript
const ENVIRONMENT_PRESETS: Record<string, EnvironmentConfig> = {
  production: {
    name: 'production',
    nodeDefaults: {
      queue: { workers: 4, capacity: 500, discipline: 'fifo' },
      nodeErrorRate: 0.001
    },
    edgeDefaults: {
      latency: { distribution: { type: 'log-normal', mu: 2.3, sigma: 0.5 } },
      errorRate: 0.001
    }
  },
  staging: {
    name: 'staging',
    nodeDefaults: {
      queue: { workers: 2, capacity: 200, discipline: 'fifo' },
      nodeErrorRate: 0.005
    },
    edgeDefaults: {
      latency: { distribution: { type: 'log-normal', mu: 2.0, sigma: 0.4 } },
      errorRate: 0.005
    }
  },
  'load-test': {
    name: 'load-test',
    nodeDefaults: {
      queue: { workers: 8, capacity: 1000, discipline: 'fifo' }
    },
    globalDefaults: {
      simulationDuration: 300_000,
      warmupDuration: 30_000
    }
  }
};
```

---

## Feature 4: Default Resolution & Precedence

### Current resolution (implicit)

There is no explicit resolution pipeline. Defaults are applied at different stages:

```
Canvas → serializeEdge (EDGE_DEFAULTS) → serializeNode (catalog defaults)
       → validate (validator defaults) → engine (withNodeDefaults)
```

Each stage applies its own defaults independently. A value set by the renderer might be overwritten by the validator or engine if the stages don't agree on what's "absent."

### Current precedence issues

1. **Validator vs. engine:** Both apply the same defaults to `queue` and `processing`. The validator applies first (and mutates), so the engine's `withNodeDefaults` is effectively dead code for validated topologies. But for programmatic topologies that skip validation, only the engine defaults apply.

2. **Catalog vs. engine:** The catalog uses exponential distributions; the engine uses constant. If a node goes through the catalog, it gets exponential. If it doesn't (e.g., missing seed metrics), the engine applies constant. The catalog is more realistic.

3. **Renderer vs. engine for edges:** The renderer applies `EDGE_DEFAULTS` during serialization. The engine has no edge defaults. If an edge is created outside the renderer (programmatic), it has no default latency distribution.

### Proposed unified resolution

```typescript
interface ResolvedDefaults {
  value: unknown;
  source: 'user' | 'environment' | 'catalog' | 'product';
  sourceDetail: string;  // e.g., "componentSpecs.ts TYPE_MEAN_SERVICE_MS['api-gateway']"
}

function resolveNodeDefaults(
  node: ComponentNode,
  environment?: EnvironmentConfig,
  catalogConfig?: NodeSimulationConfig
): Record<string, ResolvedDefaults>;
```

**Single application point:** Defaults should be resolved once, in one location, with clear precedence. The proposed location is a new `resolveDefaults.ts` module called by the engine constructor, replacing both `withNodeDefaults` in the engine and the default application in the validator.

### Default provenance in output

```typescript
interface DefaultResolutionTrace {
  nodeId: string;
  parameter: string;
  finalValue: unknown;
  source: 'user' | 'environment' | 'catalog' | 'product';
  sourceFile: string;
  wasDefaulted: boolean;
}
```

This enables the accuracy classification from Simulation Validation & Pattern Accuracy — every parameter in the output can be traced to its source, and `wasDefaulted: true` parameters can be flagged as lower confidence.

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | Relationship |
| --- | --- |
| **Simulation Validation & Pattern Accuracy** | Validator applies defaults during validation; accuracy classification depends on knowing which values are defaulted |
| **Edge Properties & Defaults** | `EDGE_DEFAULTS` is the renderer's edge default system; this spec proposes unifying it with engine-level defaults |
| **Queue Depth Calculation** | Queue defaults (`workers:1, capacity:100, discipline:'fifo'`) determine admission control behaviour |
| **Request Pattern Configuration** | Workload pattern sub-object defaults (burst multiplier, ramp duration) live in workload.ts |
| **Throughput Calculation** | Default service time directly determines theoretical throughput; constant(1) vs. exponential produce very different results |
| **Request Rejection Behaviour** | Default `capacity:100` is the admission threshold; default `nodeErrorRate:0` means no error rejections by default |
| **Cost Calculation & Budgeting** | Proposed `CostConfig` defaults (pricing) belong to this layer |
| **Request Type Model** | Default request type is implicit (single type); no default request distribution |

---

## Integration Requirements

### Across features

| Integration point | Producer | Consumer | Contract |
| --- | --- | --- | --- |
| `withNodeDefaults` | `engine.ts:627` | Engine constructor | Applies `queue` and `processing` defaults |
| Validator defaults | `validator.ts:616-631` | `validateTopology` | Same values as engine; mutates node in place |
| `EDGE_DEFAULTS` | `useTopologySerializer.ts:28` | `serializeEdge` | Renderer-only; engine has no edge defaults |
| `DEFAULT_SCENARIO_STATE` | `ui.ts:77` | UI initialization | Global config defaults |
| `buildSeededSimulationConfig` | `componentSpecs.ts:95` | Node serialization | Per-type computed defaults |
| `TYPE_MEAN_SERVICE_MS` | `componentSpecs.ts:17` | `buildSeededSimulationConfig` | ~40 per-type service time defaults |
| `DEFAULT_*` constants | `workload.ts:5-9` | `WorkloadGenerator` | Pattern sub-object fallbacks |
| `mergeWorkload` | `useTopologySerializer.ts:114` | Workload serialization | Pattern sub-object defaults for bursty/spike/sawtooth/diurnal |

### Within this feature

| Component | Responsibility | Key invariant |
| --- | --- | --- |
| Product hard defaults | Last-resort values for any missing parameter | Must produce a runnable simulation (no NaN, no zero-division) |
| Catalog computed defaults | Per-type realistic values from component knowledge | Exponential distribution, not constant |
| Environment defaults (proposed) | Topology-wide overrides for scenarios | Override product defaults; overridden by per-node values |
| Resolution pipeline (proposed) | Single point of default application | Each parameter resolved exactly once |

---

## Source-to-Feature Map

| Source file | Lines | Feature |
| --- | --- | --- |
| `src/engine/engine.ts` | 627-636 | F1: `withNodeDefaults` — engine hard defaults |
| `src/engine/validation/validator.ts` | 616-631 | F1: Validator defaults (duplicate of engine) |
| `src/renderer/src/hooks/useTopologySerializer.ts` | 28-36 | F1: `EDGE_DEFAULTS` — renderer edge defaults |
| `src/renderer/src/types/ui.ts` | 77-87 | F1: `DEFAULT_SCENARIO_STATE` — global defaults |
| `src/engine/workload.ts` | 5-9 | F1: Workload pattern fallback constants |
| `src/renderer/src/hooks/useTopologySerializer.ts` | 114-160 | F1: `mergeWorkload` — pattern sub-object defaults |
| `src/engine/catalog/componentSpecs.ts` | 17-59 | F2: `TYPE_MEAN_SERVICE_MS` — per-type service times |
| `src/engine/catalog/componentSpecs.ts` | 95-177 | F2: `buildSeededSimulationConfig` — computed defaults |
| `src/engine/catalog/componentSpecs.ts` | 10-15 | F2: `CATEGORY_MIN_SERVICE_MS` — per-category minimums |
| `src/engine/core/types.ts` | 435-442 | F3: `GlobalConfig` — target for environment defaults |
| `src/engine/core/types.ts` | 291-307 | F3: `ComponentNode` — target for node defaults |
| `src/engine/core/types.ts` | 309-339 | F3: `EdgeDefinition` — target for edge defaults |

---

## Assumptions and Unresolved Questions

### Assumptions

1. **Defaults must produce runnable simulations.** A topology with zero explicit configuration should simulate without errors. This requires every parameter that the engine reads to have a reachable default.

2. **Defaults should be conservative, not optimal.** Default values should produce stable simulations with clear metrics, even if unrealistic. A constant 1ms service time is unrealistic but predictable; an exponential with lambda=1/150 (for a third-party API) is realistic but can produce extreme tail values that confuse first-time users.

3. **Catalog defaults are more accurate than engine defaults.** The catalog uses component-type knowledge and exponential distributions. The engine uses flat constants. When both apply, catalog should win.

4. **Environment defaults are optional.** The existing system works without them. The environment layer adds convenience for users managing multiple scenarios but should not change behaviour for users who don't use it.

5. **The validator should not apply defaults.** Validation should check, not modify. Default application belongs in the engine or a dedicated resolution layer. The validator's current default application is a workaround for the lack of a proper default system.

### Unresolved questions

| # | Question | Why it matters |
| - | --- | --- |
| 1 | Should the validator stop applying defaults and leave it to the engine? | Eliminates duplication but requires the engine to handle nodes without queue/processing config |
| 2 | Should `constant(1)` be replaced with `exponential(lambda=1)` as the product default? | Exponential is more realistic for queuing; constant is more predictable for debugging |
| 3 | Should edge defaults be applied in the engine, not just the renderer? | Programmatic topologies currently get no edge defaults |
| 4 | Should `TYPE_MEAN_SERVICE_MS` be exposed as user-editable configuration? | Users with domain knowledge could improve accuracy by adjusting per-type defaults |
| 5 | Should the environment layer support per-component-type overrides? | e.g., "all databases in production get 8 workers" — more expressive but more complex |
| 6 | Should default provenance be tracked in the output? | Enables accuracy classification but adds output size |
| 7 | How should defaults interact with the overload preview mode? | `seed.overloadPreview` reduces workers by 25% and doubles service time — is this a "default" or a "transform"? |
| 8 | Should `defaultTimeout` (global) and `processing.timeout` (per-node) be unified? | Two different timeout concepts with similar names cause confusion |

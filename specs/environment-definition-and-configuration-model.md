# Environment Definition & Configuration Model

Technical feature specification defining the shared environment configuration contract that all simulation features depend on.

This spec consolidates the product discussion notes around environment definition, global defaults, node-level settings, edge-level settings, constraints, allowed/disallowed behaviours, and request movement rules into a single architectural model. It exists because every downstream simulation feature — throughput calculation, queue depth, rejection behaviour, cost estimation, request pattern configuration — needs to read from a stable, validated, normalized source of truth. Without this contract, each feature would independently derive its inputs from scattered sources, leading to inconsistent defaults, duplicated validation, and configuration drift between the topology JSON, the canvas UI, and the engine runtime.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Environment Configuration Object](#feature-1-environment-configuration-object)
4. [Feature 2: Global Defaults and Node-Level Overrides](#feature-2-global-defaults-and-node-level-overrides)
5. [Feature 3: Environment Validation and Constraints](#feature-3-environment-validation-and-constraints)
6. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
7. [Integration Requirements](#integration-requirements)
8. [Source-to-Feature Map](#source-to-feature-map)
9. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)
10. [Validation Step](#validation-step)

---

## Feature/Architecture Ideation

### Capability definition

The Environment Definition & Configuration Model is a typed, normalized configuration contract that captures everything the simulation engine needs to know before a run begins: global defaults for request patterns, node capacity, queue depth, edge properties, and behaviour rules; per-node and per-edge overrides; and constraints that gate whether a simulation is valid to execute.

It lets the product offer a default-driven setup where users define a topology and press Run without manually configuring every node or edge. It lets the engine consume a single `NormalizedSimulationEnvironment` object instead of re-deriving defaults from scattered sources at runtime. It is foundational because every later spec — throughput calculation, queue depth formulas, rejection behaviour, cost budgeting — reads its input parameters from this environment contract rather than from raw topology JSON or ad-hoc inline defaults.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Enables users to configure a simulation environment with sensible defaults and optional overrides, reducing setup burden |
| Architectural change      |      Yes | Introduces a normalized configuration layer between raw topology JSON and the simulation engine, replacing scattered inline defaults |
| Domain model addition     |      Yes | Defines new types (`SimulationEnvironmentConfig`, `NormalizedSimulationEnvironment`, `EnvironmentDefaults`, etc.) that do not exist in the codebase today |
| Validation layer          |      Yes | Adds environment-level validation (constraint checking, behaviour rule enforcement) that runs before simulation, complementing the existing `validateTopology` |
| Refactor of existing code |      Yes | Requires extracting hardcoded defaults from `SimulationEngine.withNodeDefaults`, `useTopologySerializer.EDGE_DEFAULTS`, and `componentSpecs` into the environment defaults model |

### Current pain without this model

| Pain | Who is affected | Technical cause | Consequence |
| ---- | --------------- | --------------- | ----------- |
| Node defaults are hardcoded in two places | Engine developers | `SimulationEngine.withNodeDefaults()` in `src/engine/engine.ts:627-635` applies `{ workers: 1, capacity: 100, discipline: 'fifo' }` and `{ distribution: { type: 'constant', value: 1 }, timeout: 30_000 }`. The validator in `src/engine/validation/validator.ts:617-630` applies identical defaults independently. Both must stay in sync manually. | A default changed in one location but not the other produces silent divergence between validation and execution |
| Edge defaults are hardcoded in the renderer | Frontend developers | `useTopologySerializer.ts:28-36` defines `EDGE_DEFAULTS` (latencyMu, latencySigma, bandwidth, etc.) as a local constant. The engine has no corresponding edge default object. | Edge defaults are invisible to the engine; any future edge-level calculation must re-derive them or accept the serializer's baked-in values |
| No single environment config object | All consumers | `TopologyJSON` combines topology structure (nodes, edges) with runtime config (`global`, `workload`) and optional test harness fields (`faults`, `invariants`, `scenarios`). There is no separation between "environment setup" and "topology shape". | Downstream features (throughput, cost, rejection) must pick individual fields from `TopologyJSON` and know which are environment concerns vs topology concerns |
| Behaviour rules are implicit | Engine developers, product team | Whether rejection is enabled, whether bidirectional edges are supported, whether node-level pattern overrides are allowed — none of these are represented as configuration. They are implicit in code paths. | Adding or changing a behaviour requires modifying engine internals rather than flipping an environment-level flag |
| No constraint model | Engine developers, users | `validateTopology` validates structural correctness (Zod schema, cross-references, connectivity) but has no concept of environment-level constraints like "capacity must not exceed X" or "this behaviour combination is unsupported". | Invalid environment configurations reach the simulation engine and produce confusing runtime failures instead of clear pre-simulation diagnostics |
| Scenario state is renderer-only | Engine developers | `ScenarioState` in `src/renderer/src/types/ui.ts:55-63` holds global overrides and workload overrides, but this type is a renderer concern and is not shared with the engine. | The engine cannot validate or normalize scenario-level configuration independently of the UI |

### Proposed responsibility boundary

| Responsibility | Owned by Environment Model? | Reason |
| --- | ---: | --- |
| Global request pattern assignment | Yes | The environment declares which pattern id is the default for all nodes |
| Node-level request pattern override location | Yes | The environment's node config map stores the override slot |
| Exact request pattern algorithm | No | Belongs to Request Pattern Configuration spec |
| Node capacity config (workers, queue capacity) | Yes | Stored in environment node defaults and per-node overrides |
| Exact throughput formula | No | Belongs to Throughput Calculation spec |
| Queue limit config (maxQueueDepth) | Yes | Stored in environment node defaults and per-node overrides |
| Exact queue depth formula | No | Belongs to Queue Depth Calculation spec |
| Rejection enabled/disabled rule | Yes | Stored as a behaviour rule in the environment |
| Rejection lifecycle semantics | No | Belongs to Request Rejection Behaviour spec |
| Edge default/override location | Yes | The environment stores edge defaults and per-edge overrides |
| Full edge property model | No | Belongs to Edge Properties & Defaults spec |
| Request direction config location | Yes | Stored on per-edge config as a direction field |
| Direction inference/routing semantics | No | Belongs to Request Flow Direction & Topology Rules spec |
| Cost-related config attachment point | Maybe | The environment model should reserve a slot for cost config if the product direction supports it, but should not define cost formulas |
| Cost formula | No | Belongs to Cost Calculation & Budgeting spec |

### Smallest useful v1

| v1 capability | Required? | Why |
| --- | ---: | --- |
| Global defaults | Yes | Eliminates scattered hardcoded defaults; enables default-driven simulation runs |
| Node-level overrides | Yes | Already implicitly supported via `ComponentNode.queue`/`processing`/`config`; the environment model formalizes the override mechanism |
| Edge-level overrides | Maybe | `EDGE_DEFAULTS` in the serializer already applies defaults; the environment model should at minimum own those defaults, with per-edge overrides modeled but not required for v1 |
| Behaviour rules | Yes | Even v1 needs to express whether rejection is on/off and whether node overrides are allowed, since the engine already handles rejection |
| Constraints | Yes | Minimum viable: required-field constraints and capacity/queue sanity checks, replacing the ad-hoc checks in `validateTopology` |
| Request type support | Deferred | `WorkloadProfile.requestDistribution` already models request types; the environment model should reference this but not own the type model |
| Cost/budget support | Deferred | No cost model exists in the codebase; adding a config slot is acceptable but implementation belongs to a later spec |
| Advanced presets | Deferred | Named environment presets (e.g., "low-traffic web app", "high-throughput pipeline") are a simplification-layer concern |

### Deferred capabilities

| Deferred capability | Later spec | Why deferred |
| --- | --- | --- |
| Request pattern presets and algorithms | Request Pattern Configuration | Environment model only stores the pattern id assignment, not the pattern shape or algorithm |
| Direction inference from topology structure | Request Flow Direction & Topology Rules | Environment model stores the direction config; inference rules are a routing concern |
| Request type properties and lifecycle effects | Request Type Model | Environment model references request types via workload config; type semantics are a separate domain |
| Full edge property semantics (bandwidth shaping, protocol effects) | Edge Properties & Defaults | Environment model stores edge defaults and overrides; property semantics belong to the edge spec |
| Throughput formula | Throughput Calculation | Environment model provides the input parameters (capacity, workers); the formula is a calculation concern |
| Queue depth formula and overflow semantics | Queue Depth Calculation | Environment model provides queue config; depth formulas are a calculation concern |
| Arrival/departure lifecycle and request state machine | Arrival, Departure & Request Lifecycle Semantics | Environment model enables/disables behaviours; lifecycle semantics are a runtime concern |
| Rejection metrics, causes, and cascading effects | Request Rejection Behaviour | Environment model enables/disables rejection; rejection mechanics are a runtime concern |
| Cost formula and budget warnings | Cost Calculation & Budgeting | No cost model exists yet; the environment reserves an attachment point |
| Regression fixtures for pattern accuracy | Simulation Validation & Pattern Accuracy | Environment model defines validation types; accuracy test fixtures belong to the validation spec |
| Progressive disclosure of advanced config | Default-Driven Simplification Layer | Environment model defines the inheritance chain; progressive disclosure is a UX/product concern |

---

## Problem Context

### What exists today

The current architecture distributes simulation configuration across four layers with no shared environment contract:

**Topology JSON (the engine's input contract)**

- `src/engine/core/types.ts` defines `TopologyJSON`, the top-level input to the simulation engine. It combines structural concerns (nodes array, edges array) with runtime configuration (`global: GlobalConfig`, `workload?: WorkloadProfile`) and optional test harness fields (`faults`, `invariants`, `scenarios`). There is no separation between "environment setup" and "topology shape".
- `GlobalConfig` (same file, lines 435–442) holds `simulationDuration`, `seed`, `warmupDuration`, `timeResolution`, `defaultTimeout`, and `traceSampleRate`. These are the closest thing to global environment settings, but they cover only time and sampling — not capacity defaults, queue defaults, edge defaults, or behaviour rules.
- `ComponentNode` (lines 291–307) carries per-node configuration: `resources`, `queue`, `processing`, `resilience`, `slo`, `failureModes`, `scaling`, and an escape-hatch `config: Record<string, unknown>`. There is no standard "node override" structure — overrides are implicit in whether these optional fields are present.
- `EdgeDefinition` (lines 309–339) carries per-edge configuration with required fields for `mode`, `protocol`, `latency`, `bandwidth`, `maxConcurrentRequests`, `packetLossRate`, and `errorRate`. Every field is required on the wire; defaults are applied during serialization, not at the engine level.

**Validation layer**

- `src/engine/validation/validator.ts` exports `validateTopology(input: unknown): ValidationResult`. It performs Zod schema parsing via `TopologyJSONSchema`, then cross-reference validation (node id uniqueness, edge source/target existence, workload sourceNodeId validity), then structural warnings (connectivity, source/sink role checks). It also applies hardcoded defaults: lines 617–630 mutate nodes missing `queue` or `processing` config with `{ workers: 1, capacity: 100, discipline: 'fifo' }` and `{ distribution: { type: 'constant', value: 1 }, timeout: 30_000 }`.
- `ValidationResult` (lines 525–535) returns `{ valid: boolean; data?: TopologyJSON; errors?: ValidationError[]; warnings?: string[] }`. `ValidationError` has `path` and `message` fields. There is no concept of constraint severity, diagnostic codes, or structured constraint types.

**Engine runtime defaults**

- `src/engine/engine.ts` line 627–635: `SimulationEngine.withNodeDefaults()` applies the same queue and processing defaults as the validator, independently. This is the second copy of these defaults.
- `src/engine/engine.ts` line 59–71: The `SimulationEngine` constructor reads `topology.global.seed`, `topology.global.warmupDuration`, `topology.global.traceSampleRate`, `topology.global.simulationDuration`, and `topology.global.defaultTimeout` directly from the `TopologyJSON` object. There is no normalization step.

**Renderer-side serialization and defaults**

- `src/renderer/src/hooks/useTopologySerializer.ts` lines 28–36: `EDGE_DEFAULTS` defines `latencyMu: 2.3`, `latencySigma: 0.5`, `pathType: 'same-dc'`, `bandwidth: 1000`, `maxConcurrentRequests: 100`, `packetLossRatePercent: 0`, `errorRatePercent: 0.1`. These defaults are applied during serialization from canvas state to `TopologyJSON`. The engine never sees them as defaults — it receives fully populated `EdgeDefinition` objects.
- `src/renderer/src/types/ui.ts` lines 77–87: `DEFAULT_SCENARIO_STATE` defines default global config values: `simulationDuration: 60_000`, `warmupDuration: 5_000`, `seed: 'default-seed'`, `defaultTimeout: 5_000`, `traceSampleRate: 0.01`. These are renderer-only defaults that feed into `TopologyJSON.global` during serialization.
- `src/engine/catalog/componentSpecs.ts`: `ComponentSpec.createDefaultSimulationConfig()` generates per-component-type defaults for queue workers, capacity, and processing distribution. These defaults are baked into canvas node data at drag-and-drop time and serialized into `ComponentNode` fields. They are not accessible as "environment defaults" at runtime.

**Data flow summary**

```
Canvas state (React Flow nodes/edges + ScenarioState)
  → useTopologySerializer.serialize()
    → applies EDGE_DEFAULTS, mergeWorkload(), buildScenarioGlobal()
    → produces TopologyJSON
  → validateTopology(topologyJSON)
    → applies node defaults (queue, processing) as mutations
    → returns ValidationResult
  → SimulationEngine(topologyJSON)
    → applies withNodeDefaults() again
    → reads global config fields directly
    → runs simulation
```

### What's missing

| Gap | Current limitation | Why it blocks users/developers | Related future spec |
| --- | --- | --- | --- |
| No environment-level configuration object | `TopologyJSON` mixes topology structure with runtime config; there is no type that says "this is the environment setup" | Downstream features cannot import a single contract; each must know which `TopologyJSON` fields are environment concerns | All future specs |
| No unified global defaults model | Node defaults are hardcoded in `engine.ts:627` and `validator.ts:617`; edge defaults are in `useTopologySerializer.ts:28`; global config defaults are in `ui.ts:77` | Changing a default requires updating 2-4 locations; the engine and validator can silently diverge | Default-Driven Simplification Layer |
| No standard node override mechanism | Node overrides are implicit: if `ComponentNode.queue` is present, it overrides the hardcoded default; there is no merge semantics or precedence model | Cannot implement "environment says X, but this node says Y" as a first-class concept | Throughput Calculation, Queue Depth Calculation |
| No edge default ownership in the engine | `EDGE_DEFAULTS` lives in the renderer; the engine receives fully populated edges | Future edge-level calculations (throughput, cost) cannot distinguish "user chose this value" from "serializer applied the default" | Edge Properties & Defaults |
| No behaviour rules | Whether rejection is enabled, whether bidirectional edges exist, whether node-level overrides are allowed — these are implicit in code paths, not configuration | Adding a new behaviour (e.g., "allow node-level pattern overrides") requires engine code changes rather than environment config changes | Request Rejection Behaviour, Request Flow Direction |
| No constraint schema | `validateTopology` checks structural correctness but has no environment-level constraint concept | Cannot express "capacity must be ≤ 10,000" or "this behaviour combination is unsupported" as declarative rules | Simulation Validation & Pattern Accuracy |
| No shared validation contract for environment | `ValidationResult` has `path` and `message` but no severity levels, diagnostic codes, or structured constraint types | Future features cannot programmatically handle specific validation failures | All validation-dependent specs |
| No stable data contract for calculation inputs | Throughput, queue depth, rejection, and cost features do not have a typed contract for their inputs | Each calculation feature must independently extract its parameters from `TopologyJSON` and `ComponentNode`, risking inconsistent reads | Throughput Calculation, Queue Depth Calculation, Cost Calculation |

### What the source material explores

The product discussion notes frame environment definition as the foundational layer for the entire simulation system. They specify that an environment should include: a request pattern (global default, with optional per-node overrides); configuration parameters for capacity, queue depth, and throughput; constraints that prevent invalid setups; allowed and disallowed behaviours (rejection, bidirectional flow, node-level overrides); node-level and global-level settings with a clear inheritance model; and rules that control how requests move through the system. The notes emphasize a default-driven, progressive-disclosure approach: v1 should let users define a topology, choose or accept a default request pattern, and run a simulation without configuring every node or edge. Advanced configuration — per-node patterns, custom edge properties, request types, detailed rejection rules — should be introduced progressively once the core model is stable.

---

## Feature 1: Environment Configuration Object

### What it does

The environment configuration object is the top-level model that defines everything a simulation needs to know about its operating context before execution begins. It collects global defaults (request pattern, node capacity, queue limits, edge properties), per-node overrides, per-edge overrides, behaviour rules, and constraints into a single typed contract. The simulation engine, validation layer, and future calculation modules all consume this contract instead of reading from scattered sources.

### Why it exists

Today, simulation configuration is assembled ad-hoc: the renderer serializes canvas state into `TopologyJSON`, applying renderer-local edge defaults and scenario defaults along the way. The validator applies its own node defaults via mutation. The engine applies its own node defaults via `withNodeDefaults()`. Each layer independently decides what the defaults are, and there is no contract that downstream features can depend on.

The environment configuration object eliminates this by:
1. Centralizing all defaults in one place.
2. Making the override mechanism explicit and typed.
3. Providing a stable input contract for every future calculation feature.
4. Separating "environment setup" from "topology structure".

### How it works internally

#### Data source

The environment configuration object is assembled from existing data that is currently scattered across the codebase.

Existing global config (`src/engine/core/types.ts`):

```ts
export interface GlobalConfig {
  simulationDuration: number
  seed: string
  warmupDuration: number
  timeResolution: 'microsecond' | 'millisecond'
  defaultTimeout: number
  traceSampleRate?: number
}
```

Existing node config (same file):

```ts
export interface ComponentNode {
  id: string
  type: ComponentType
  category: ComponentCategory
  // ... position, label ...
  resources?: ResourceConfig
  queue?: QueueConfig
  processing?: ProcessingConfig
  // ... resilience, slo, failureModes, scaling ...
  config?: Record<string, unknown>
}
```

Existing edge defaults (`src/renderer/src/hooks/useTopologySerializer.ts`):

```ts
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

Existing scenario defaults (`src/renderer/src/types/ui.ts`):

```ts
export const DEFAULT_SCENARIO_STATE: ScenarioState = {
  global: {
    simulationDuration: 60_000,
    warmupDuration: 5_000,
    seed: 'default-seed',
    defaultTimeout: 5_000,
    traceSampleRate: 0.01
  }
}
```

Existing engine-side node defaults (`src/engine/engine.ts`):

```ts
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

The repository does not currently define a single environment-level configuration object. The closest existing concepts are `TopologyJSON` (which bundles topology + config), `GlobalConfig` (which covers time and sampling only), and `ScenarioState` (which is renderer-only).

#### Processing/logic

The environment configuration should be assembled through a defined merge pipeline that runs after topology serialization and before simulation execution.

**Merge order:**

| Step | Input | Output | Why |
| ---- | ----- | ------ | --- |
| 1. Load product hard defaults | Built-in constants | `ProductDefaults` | Provides a known baseline that never changes across environments; replaces the scattered hardcoded values in `engine.ts`, `validator.ts`, and `useTopologySerializer.ts` |
| 2. Apply environment global defaults | Product defaults + user-specified environment defaults | `EnvironmentDefaults` | User can override product defaults for the entire environment (e.g., change default queue capacity from 100 to 500) |
| 3. Attach node overrides | Environment defaults + per-node config from topology | `EnvironmentNodeConfig` map | Nodes that specify explicit queue, processing, or pattern config override the global defaults |
| 4. Attach edge overrides | Environment defaults + per-edge config from topology | `EnvironmentEdgeConfig` map | Edges that specify explicit latency, bandwidth, or direction config override the global edge defaults |
| 5. Attach behaviour rules | Environment-level rules + any node-level behaviour overrides | `EnvironmentBehaviourRules` | Determines what is allowed/disallowed before validation runs |
| 6. Attach constraints | Built-in constraints + environment-level constraints | `EnvironmentConstraint[]` | Declares what must be true for the environment to be valid |
| 7. Validate | Complete `SimulationEnvironmentConfig` | `EnvironmentValidationResult` | Catches invalid configurations before they reach the engine |
| 8. Normalize | Validated config | `NormalizedSimulationEnvironment` | Resolves all inheritance; every node and edge has fully populated fields; no optional values remain |
| 9. Execute | Normalized environment | `SimulationEngine` input | Engine consumes only the normalized form |

#### New types

All new types should live in `src/engine/core/environmentTypes.ts`. This file is new and sits alongside the existing `types.ts` and `events.ts` in the core module.

```ts
import type { DistributionConfig, QueueConfig, ProcessingConfig } from './types'

/**
 * Top-level configuration contract for a simulation environment.
 * Produced by the environment assembly pipeline and consumed by
 * validation and normalization before simulation starts.
 */
export interface SimulationEnvironmentConfig {
  /** Stable identifier for this environment configuration. */
  id: string

  /** Human-readable name. Metadata only — does not affect simulation. */
  name: string

  /** Global simulation parameters (duration, seed, warmup, timeout). */
  global: EnvironmentGlobalConfig

  /**
   * Default values inherited by nodes and edges that lack explicit overrides.
   * This is the primary mechanism for default-driven simplification.
   */
  defaults: EnvironmentDefaults

  /**
   * Node-level configuration keyed by node id.
   * Each entry may override selected global defaults for that node.
   */
  nodes: Record<string, EnvironmentNodeConfig>

  /**
   * Edge-level configuration keyed by edge id.
   * Each entry may override selected global defaults for that edge.
   */
  edges: Record<string, EnvironmentEdgeConfig>

  /**
   * Rules describing which behaviours are allowed or disallowed.
   * Evaluated by the validation layer and later by request movement logic.
   */
  behaviourRules: EnvironmentBehaviourRules

  /**
   * Constraints that must be satisfied before simulation can run.
   * Evaluated during validation; error-level constraints block execution.
   */
  constraints: EnvironmentConstraint[]
}
```

```ts
/**
 * Global simulation parameters that apply to the entire environment.
 * Extends the existing GlobalConfig with environment-specific fields.
 */
export interface EnvironmentGlobalConfig {
  /** Total simulation duration in milliseconds, including warmup. */
  simulationDuration: number

  /** Random seed for reproducibility. */
  seed: string

  /** Warmup period in milliseconds; metrics are excluded during warmup. */
  warmupDuration: number

  /** Time resolution for the simulation clock. */
  timeResolution: 'microsecond' | 'millisecond'

  /** Default request timeout in milliseconds, used when a node does not specify one. */
  defaultTimeout: number

  /** Fraction [0, 1] of requests to trace. */
  traceSampleRate: number
}
```

```ts
/**
 * Default configuration values inherited by nodes and edges.
 * These keep v1 opinionated and easy to run without per-node configuration.
 */
export interface EnvironmentDefaults {
  /**
   * Default request pattern identifier.
   * The pattern model itself is defined in the Request Pattern Configuration spec.
   * v1 value: 'constant' (matching the current hardcoded default).
   */
  requestPatternId: string

  /** Default node configuration applied when a node has no explicit overrides. */
  node: EnvironmentNodeDefaults

  /** Default edge configuration applied when an edge has no explicit overrides. */
  edge: EnvironmentEdgeDefaults
}
```

```ts
/**
 * Default node-level values.
 * Replaces the hardcoded defaults in engine.ts:withNodeDefaults()
 * and validator.ts:617-630.
 */
export interface EnvironmentNodeDefaults {
  /** Default queue configuration. */
  queue: QueueConfig

  /** Default processing configuration. */
  processing: ProcessingConfig

  /**
   * Default maximum total capacity (workers + queue slots) for a node.
   * This is the K in the G/G/c/K model. Equivalent to QueueConfig.capacity
   * but expressed here for clarity as an environment-level default.
   */
  maxCapacity: number
}
```

```ts
/**
 * Default edge-level values.
 * Replaces EDGE_DEFAULTS in useTopologySerializer.ts.
 */
export interface EnvironmentEdgeDefaults {
  /** Default latency distribution parameters. */
  latency: {
    distribution: DistributionConfig
    pathType: 'same-rack' | 'same-dc' | 'cross-zone' | 'cross-region' | 'internet'
  }

  /** Default bandwidth in Mbps. */
  bandwidth: number

  /** Default max concurrent requests per edge. */
  maxConcurrentRequests: number

  /** Default packet loss rate [0, 1]. */
  packetLossRate: number

  /** Default error rate [0, 1]. */
  errorRate: number

  /** Default edge mode. */
  mode: 'synchronous' | 'asynchronous' | 'streaming' | 'conditional'

  /** Default protocol. */
  protocol: 'https' | 'grpc' | 'tcp' | 'udp' | 'websocket' | 'amqp' | 'kafka'
}
```

```ts
/**
 * Node-specific environment configuration.
 * Stores only overrides; inherited values are resolved during normalization.
 */
export interface EnvironmentNodeConfig {
  /** Must match an existing node id from the topology. */
  nodeId: string

  /**
   * Optional request pattern override.
   * If absent, the node inherits the environment default.
   */
  requestPatternId?: string

  /** Optional queue configuration override. */
  queue?: Partial<QueueConfig>

  /** Optional processing configuration override. */
  processing?: Partial<ProcessingConfig>

  /** Optional node error rate override [0, 1]. */
  nodeErrorRate?: number

  /**
   * Optional behaviour overrides for this node.
   * Allows specific nodes to opt into or out of globally allowed behaviours.
   */
  behaviourOverrides?: Partial<EnvironmentBehaviourRules>
}
```

```ts
/**
 * Edge-specific environment configuration.
 * Stores only overrides; inherited values are resolved during normalization.
 */
export interface EnvironmentEdgeConfig {
  /** Must match an existing edge id from the topology. */
  edgeId: string

  /**
   * Optional request direction override.
   * If absent, direction is inferred from topology or environment defaults.
   */
  direction?: RequestDirection

  /** Optional latency distribution override. */
  latency?: {
    distribution?: DistributionConfig
    pathType?: 'same-rack' | 'same-dc' | 'cross-zone' | 'cross-region' | 'internet'
  }

  /** Optional bandwidth override in Mbps. */
  bandwidth?: number

  /** Optional max concurrent requests override. */
  maxConcurrentRequests?: number

  /** Optional packet loss rate override [0, 1]. */
  packetLossRate?: number

  /** Optional error rate override [0, 1]. */
  errorRate?: number
}
```

```ts
/**
 * Rules describing which behaviours are supported in this environment.
 */
export interface EnvironmentBehaviourRules {
  /**
   * Whether requests may be rejected when node or queue capacity is exceeded.
   * Currently always true in the engine (GGcKNode.handleArrival rejects on
   * capacity_exceeded). This flag makes the behaviour explicit and toggleable.
   */
  allowRejection: boolean

  /**
   * Whether requests may move in both directions along eligible edges.
   * Currently not supported; all edges are source→target only.
   * Modeled here for future use by the Request Flow Direction spec.
   */
  allowBidirectionalRequests: boolean

  /**
   * Whether individual nodes may override the global request pattern.
   * When false, all nodes use the environment default pattern.
   */
  allowNodePatternOverrides: boolean

  /**
   * Whether individual edges may override the global edge defaults.
   * When false, all edges use the environment default edge config.
   */
  allowEdgeOverrides: boolean
}
```

```ts
/**
 * Supported request direction values for edge-level configuration.
 * Detailed routing semantics belong to the Request Flow Direction spec.
 */
export type RequestDirection =
  | 'topology'       // follow the edge's source→target direction
  | 'forward'        // explicit forward direction
  | 'reverse'        // explicit reverse direction
  | 'bidirectional'  // requests may traverse in either direction
```

```ts
/**
 * Environment-level constraint evaluated before simulation starts.
 */
export interface EnvironmentConstraint {
  /** Stable identifier used in validation errors and tests. */
  id: string

  /** Category of constraint. */
  type: EnvironmentConstraintType

  /**
   * Error-level constraints block simulation.
   * Warning-level constraints allow simulation but surface diagnostics.
   */
  severity: 'error' | 'warning'

  /** Human-readable explanation. */
  message: string
}

/**
 * Supported constraint categories.
 */
export type EnvironmentConstraintType =
  | 'missing-required-node-config'
  | 'invalid-request-pattern'
  | 'invalid-edge-direction'
  | 'capacity-exceeded'
  | 'queue-limit-exceeded'
  | 'unsupported-behaviour'
  | 'node-id-mismatch'
  | 'edge-id-mismatch'
```

**Type placement and rationale:**

| Type | Proposed file | Why |
| --- | --- | --- |
| `SimulationEnvironmentConfig` | `src/engine/core/environmentTypes.ts` | Core contract consumed by engine and validation; must be engine-side |
| `EnvironmentDefaults`, `EnvironmentNodeDefaults`, `EnvironmentEdgeDefaults` | Same file | Coupled to the environment config; no reason to separate |
| `EnvironmentNodeConfig`, `EnvironmentEdgeConfig` | Same file | Override types for the environment config |
| `EnvironmentBehaviourRules` | Same file | Behaviour rules are environment-level concerns |
| `EnvironmentConstraint`, `EnvironmentConstraintType` | Same file | Constraints are part of the environment contract |
| `RequestDirection` | Same file | Used by `EnvironmentEdgeConfig`; a simple enum that does not warrant its own file |

**Where each field gets its value:**

| Field | Value source in v1 |
| --- | --- |
| `id` | Generated by the renderer or CLI when an environment is created; `'default'` for the implicit environment |
| `name` | User-provided or `'Default Environment'` |
| `global.*` | Mapped from `ScenarioState.global` (renderer) or `GlobalConfig` (CLI/JSON) |
| `defaults.requestPatternId` | `'constant'` — matching current hardcoded behaviour |
| `defaults.node.queue` | `{ workers: 1, capacity: 100, discipline: 'fifo' }` — extracted from `engine.ts:628` |
| `defaults.node.processing` | `{ distribution: { type: 'constant', value: 1 }, timeout: 30_000 }` — extracted from `engine.ts:629-631` |
| `defaults.node.maxCapacity` | `100` — matching `QueueConfig.capacity` default |
| `defaults.edge.*` | Extracted from `useTopologySerializer.ts:EDGE_DEFAULTS` and converted to engine units |
| `nodes[id]` | Populated from `ComponentNode` optional fields during environment assembly |
| `edges[id]` | Populated from `EdgeDefinition` fields that differ from defaults during environment assembly |
| `behaviourRules.*` | Product hard defaults in v1: `{ allowRejection: true, allowBidirectionalRequests: false, allowNodePatternOverrides: false, allowEdgeOverrides: true }` |
| `constraints` | Built-in structural constraints generated during validation |

**Alternatives rejected:**

1. *Extending `TopologyJSON` directly* — rejected because `TopologyJSON` is an existing serialization contract used by the CLI, file persistence, and the worker protocol. Adding environment fields to it would mix concerns and break backward compatibility.
2. *Storing defaults only in the renderer* — rejected because the engine and CLI need access to the same defaults without depending on renderer code.
3. *Using a flat config object instead of nested defaults/overrides* — rejected because the inheritance model (global → node → edge) requires a hierarchical structure to express precedence clearly.

#### Integration points

| Integration point | Current code | Required change |
| --- | --- | --- |
| Topology serializer | `src/renderer/src/hooks/useTopologySerializer.ts` | Should produce a `SimulationEnvironmentConfig` in addition to or instead of raw `TopologyJSON`; `EDGE_DEFAULTS` should be replaced by reading from `EnvironmentDefaults` |
| Validation entry point | `src/engine/validation/validator.ts:validateTopology()` | Should accept `SimulationEnvironmentConfig` (or produce it internally) and validate against the constraint model; the hardcoded node default mutations (lines 617-630) should be removed in favor of the normalization step |
| Engine constructor | `src/engine/engine.ts:SimulationEngine(topology)` | Should accept `NormalizedSimulationEnvironment` + `TopologyJSON` (for topology structure); `withNodeDefaults()` should be removed since normalization handles defaults |
| Worker protocol | `src/engine/worker/protocols.ts:RunMessage` | Should carry either `SimulationEnvironmentConfig` or the already-normalized environment alongside the topology |
| Store/state | `src/renderer/src/store/useStore.ts` | Should add an `environment` slice of type `SimulationEnvironmentConfig` or a simpler `EnvironmentDefaults` for the current session |
| Scenario state | `src/renderer/src/types/ui.ts:ScenarioState` | `ScenarioState.global` values should feed into `SimulationEnvironmentConfig.global`; the assembly function maps between them |
| Component specs | `src/engine/catalog/componentSpecs.ts` | `createDefaultSimulationConfig()` should read from `EnvironmentDefaults.node` instead of independently computing defaults |
| Tests | `src/engine/engine.test.ts`, `src/engine/validation/validator.test.ts` | Should construct `SimulationEnvironmentConfig` objects in test fixtures; existing tests that pass raw `TopologyJSON` should continue to work via a compatibility adapter |

### What components it requires

**Engine-side:**
- `src/engine/core/environmentTypes.ts` — new file defining all environment types
- `src/engine/environment/assembleEnvironment.ts` — new module: function to assemble `SimulationEnvironmentConfig` from `TopologyJSON` + user overrides
- `src/engine/environment/normalizeEnvironment.ts` — new module: function to produce `NormalizedSimulationEnvironment` from validated config
- `src/engine/environment/productDefaults.ts` — new module: single source of truth for all product hard defaults
- Update `src/engine/engine.ts` to consume `NormalizedSimulationEnvironment`
- Update `src/engine/validation/validator.ts` to validate against the constraint model

**Shared layer:**
- All types in `src/engine/core/environmentTypes.ts` are importable by both engine and renderer
- Product defaults in `src/engine/environment/productDefaults.ts` are importable by renderer for display

**Renderer/frontend-side:**
- Update `src/renderer/src/hooks/useTopologySerializer.ts` to produce `SimulationEnvironmentConfig`
- Add environment state to `src/renderer/src/store/useStore.ts`
- Update `src/renderer/src/hooks/useSimulation.ts` to pass environment config through the worker

### Explored in

- Product discussion notes: Environment Definition
- Product discussion notes: Global Default Pattern
- Product discussion notes: Request Pattern Configuration
- Product discussion notes: Simplifying the Application
- Product discussion notes: Request Direction
- Product discussion notes: Edge Properties

---

## Feature 2: Global Defaults and Node-Level Overrides

### What it does

The environment provides a three-level inheritance model for simulation configuration: product hard defaults → environment global defaults → node/edge-level overrides. When a user creates a topology and runs a simulation without configuring individual nodes, every node inherits from the environment defaults. When a user explicitly configures a node's queue capacity or processing distribution, that override takes precedence. The same model applies to edges.

### Why it exists

The v1 product direction is "simple and default-driven." Users should be able to draw a topology and press Run. Today, this works because the serializer and engine each apply their own hardcoded defaults — but these defaults are invisible, duplicated, and not overridable at the environment level. The inheritance model makes defaults explicit, centralizes them, and provides a clean override path for progressive configuration.

### How it works internally

#### Data source

**Current node defaults** — applied in two places:

`src/engine/engine.ts:627-635`:
```ts
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

`src/engine/validation/validator.ts:617-630`:
```ts
if (!node.queue) {
  warnings.push(`Node '${node.label}' is missing queue config; applying legacy default queue settings.`)
  node.queue = { workers: 1, capacity: 100, discipline: 'fifo' }
}
if (!node.processing) {
  warnings.push(`Node '${node.label}' is missing processing config; applying legacy default processing settings.`)
  node.processing = { distribution: { type: 'constant', value: 1 }, timeout: 30_000 }
}
```

**Current edge defaults** — applied only in the serializer:

`src/renderer/src/hooks/useTopologySerializer.ts:28-36` (as shown above).

**Current component-specific defaults:**

`src/engine/catalog/componentSpecs.ts` computes per-type defaults via `createDefaultSimulationConfig(seed)`. For example, a `relational-db` node gets `meanServiceMs: 8`, while a `load-balancer` gets `meanServiceMs: 0.2`. These are baked into canvas node data at creation time.

#### Processing/logic

**Inheritance and override rules:**

| Config value | Product hard default | Environment default source | Override source | Resolution rule |
| --- | --- | --- | --- | --- |
| Request pattern | `'constant'` | `EnvironmentDefaults.requestPatternId` | `EnvironmentNodeConfig.requestPatternId` | Node override wins if `behaviourRules.allowNodePatternOverrides` is true |
| Queue workers | `1` | `EnvironmentDefaults.node.queue.workers` | `EnvironmentNodeConfig.queue.workers` | Node override wins if present |
| Queue capacity | `100` | `EnvironmentDefaults.node.queue.capacity` | `EnvironmentNodeConfig.queue.capacity` | Node override wins if present |
| Queue discipline | `'fifo'` | `EnvironmentDefaults.node.queue.discipline` | `EnvironmentNodeConfig.queue.discipline` | Node override wins if present |
| Processing distribution | `{ type: 'constant', value: 1 }` | `EnvironmentDefaults.node.processing.distribution` | `EnvironmentNodeConfig.processing.distribution` | Node override wins if present |
| Processing timeout | `30_000` | `EnvironmentDefaults.node.processing.timeout` | `EnvironmentNodeConfig.processing.timeout` | Node override wins if present |
| Edge latency | `{ type: 'log-normal', mu: 2.3, sigma: 0.5 }` | `EnvironmentDefaults.edge.latency.distribution` | `EnvironmentEdgeConfig.latency.distribution` | Edge override wins if `behaviourRules.allowEdgeOverrides` is true |
| Edge bandwidth | `1000` | `EnvironmentDefaults.edge.bandwidth` | `EnvironmentEdgeConfig.bandwidth` | Edge override wins if allowed |
| Edge packet loss | `0` | `EnvironmentDefaults.edge.packetLossRate` | `EnvironmentEdgeConfig.packetLossRate` | Edge override wins if allowed |
| Edge error rate | `0.001` | `EnvironmentDefaults.edge.errorRate` | `EnvironmentEdgeConfig.errorRate` | Edge override wins if allowed |
| Behaviour rules | Product defaults | `EnvironmentBehaviourRules` | `EnvironmentNodeConfig.behaviourOverrides` | Most restrictive rule wins: if the global rule disallows a behaviour, a node cannot re-enable it; if the global rule allows it, a node can opt out |

**Precedence (highest to lowest):**

1. **Validation constraints** — constraints can block a configuration regardless of what defaults or overrides say
2. **Node/edge-level overrides** — explicit per-node or per-edge values, if allowed by behaviour rules
3. **Environment global defaults** — `EnvironmentDefaults` values
4. **Product hard defaults** — built-in constants that never change

#### New types

```ts
/**
 * Fully resolved environment configuration consumed by simulation logic.
 * Every node and edge has complete configuration; no optional fields remain.
 * This is the output of normalizeSimulationEnvironment().
 */
export interface NormalizedSimulationEnvironment {
  /** Source environment identifier. */
  environmentId: string

  /** Resolved global simulation parameters. */
  global: EnvironmentGlobalConfig

  /** Fully resolved node configurations keyed by node id. */
  nodes: Record<string, ResolvedNodeConfig>

  /** Fully resolved edge configurations keyed by edge id. */
  edges: Record<string, ResolvedEdgeConfig>

  /** Behaviour rules after global and local rules have been merged. */
  behaviourRules: EnvironmentBehaviourRules
}
```

```ts
/**
 * Node configuration after defaults and overrides have been resolved.
 * Every field is required — no optional values.
 */
export interface ResolvedNodeConfig {
  /** Node identifier from the topology. */
  nodeId: string

  /** Final request pattern id. */
  requestPatternId: string

  /** Final queue configuration. */
  queue: QueueConfig

  /** Final processing configuration. */
  processing: ProcessingConfig

  /** Final node error rate [0, 1]. 0 if not configured. */
  nodeErrorRate: number

  /** Final behaviour rules applying to this node. */
  behaviourRules: EnvironmentBehaviourRules
}
```

```ts
/**
 * Edge configuration after defaults and overrides have been resolved.
 * Every field is required.
 */
export interface ResolvedEdgeConfig {
  /** Edge identifier from the topology. */
  edgeId: string

  /** Final request direction. */
  direction: RequestDirection

  /** Final latency configuration. */
  latency: {
    distribution: DistributionConfig
    pathType: 'same-rack' | 'same-dc' | 'cross-zone' | 'cross-region' | 'internet'
  }

  /** Final bandwidth in Mbps. */
  bandwidth: number

  /** Final max concurrent requests. */
  maxConcurrentRequests: number

  /** Final packet loss rate [0, 1]. */
  packetLossRate: number

  /** Final error rate [0, 1]. */
  errorRate: number
}
```

These types should live in `src/engine/core/environmentTypes.ts` alongside the source config types. They are separate because `SimulationEnvironmentConfig` is editable/persisted (contains optional fields, overrides), while `NormalizedSimulationEnvironment` is derived (all fields required, ready for consumption). Keeping them separate prevents accidental mutation of the editable config and makes the normalization contract explicit.

#### Integration points

The normalization function should be called in the assembly pipeline, after validation passes and before the engine constructor receives the config.

Proposed function signature (`src/engine/environment/normalizeEnvironment.ts`):

```ts
import type {
  SimulationEnvironmentConfig,
  NormalizedSimulationEnvironment
} from '../core/environmentTypes'
import type { TopologyJSON } from '../core/types'

/**
 * Resolves an editable environment configuration into the normalized
 * form consumed by simulation. Requires the topology for node/edge
 * id resolution and structural role inference.
 */
export function normalizeSimulationEnvironment(
  config: SimulationEnvironmentConfig,
  topology: TopologyJSON
): NormalizedSimulationEnvironment
```

The engine should consume only the normalized object:

```ts
// Current:
constructor(private readonly topology: TopologyJSON) { ... }

// Proposed:
constructor(
  private readonly topology: TopologyJSON,
  private readonly environment: NormalizedSimulationEnvironment
) { ... }
```

This allows the engine to read node config from `environment.nodes[nodeId]` instead of calling `withNodeDefaults()`, and to read edge config from `environment.edges[edgeId]` instead of relying on the serializer's baked-in values.

### What components it requires

**Engine-side:**
- `src/engine/environment/normalizeEnvironment.ts` — normalization function
- `src/engine/environment/productDefaults.ts` — product hard defaults (single source of truth)
- Update `src/engine/engine.ts` — accept `NormalizedSimulationEnvironment`, remove `withNodeDefaults()`
- Update `src/engine/validation/validator.ts` — remove inline default mutations

**Shared layer:**
- `ResolvedNodeConfig`, `ResolvedEdgeConfig`, `NormalizedSimulationEnvironment` in `src/engine/core/environmentTypes.ts`

**Renderer/frontend-side:**
- Update `src/renderer/src/hooks/useTopologySerializer.ts` — replace `EDGE_DEFAULTS` with reads from environment defaults
- Display which values are inherited vs overridden (data support only; no visual spec)

### Explored in

- Product discussion notes: Customisation Scope
- Product discussion notes: Request Pattern Configuration
- Product discussion notes: Global Default Pattern
- Product discussion notes: Simplifying the Application

---

## Feature 3: Environment Validation and Constraints

### What it does

Environment validation checks that a `SimulationEnvironmentConfig` is valid before normalization and simulation. It evaluates the shape of the config, cross-references node and edge ids against the topology, enforces behaviour rules, and checks constraints. The result is a structured diagnostic list with severity levels and stable codes that can be used by the UI, CLI, and tests.

### Why it exists

Today, `validateTopology()` in `src/engine/validation/validator.ts` validates structural correctness of `TopologyJSON` — Zod schema conformance, node/edge id uniqueness, cross-references, connectivity. But it has no concept of environment-level constraints, behaviour rule enforcement, or diagnostic severity beyond error/warning strings.

When downstream features introduce throughput limits, capacity ceilings, and behaviour-gated configurations, the validation layer must be able to express: "this environment allows rejection, but this node's capacity is set to 0, which would reject all requests — that's an error." The current validator cannot express such constraints because it has no environment model to validate against.

### How it works internally

#### Data source

Existing validation (`src/engine/validation/validator.ts`):

```ts
export interface ValidationError {
  path: string
  message: string
}

export interface ValidationResult {
  valid: boolean
  data?: TopologyJSON
  errors?: ValidationError[]
  warnings?: string[]
}

export const validateTopology = (input: unknown): ValidationResult => { ... }
```

The function performs:
1. Zod structural parse via `TopologyJSONSchema.safeParse(input)`
2. Cross-reference validation (duplicate ids, missing source/target nodes, workload source existence)
3. Per-node structural checks (queue capacity vs workers, processing timeout, error rate range, security filter validation)
4. Time logic checks (simulationDuration > warmupDuration)
5. Graph connectivity checks (reachability from source nodes)

This covers topology-level validation. Environment-level validation — constraint checking, behaviour rule enforcement, override permission checks — does not exist.

#### Processing/logic

Environment validation should run as a multi-phase pipeline:

| Phase | Input | Validation examples | Output |
| --- | --- | --- | --- |
| Shape validation | Raw `SimulationEnvironmentConfig` | Required fields present, `id` is non-empty, `global` has valid ranges, `behaviourRules` has boolean values | Typed config or shape error diagnostics |
| Reference validation | Config + `TopologyJSON` | Every key in `config.nodes` matches a `TopologyJSON.nodes[].id`; every key in `config.edges` matches a `TopologyJSON.edges[].id` | Reference error diagnostics |
| Behaviour rule validation | Config + behaviour rules | If `allowNodePatternOverrides` is false, no node in `config.nodes` has a `requestPatternId` override; if `allowEdgeOverrides` is false, no edge in `config.edges` has non-default values | Behaviour violation diagnostics |
| Constraint validation | Normalized config | Queue capacity ≥ queue workers for every node; node error rate in [0, 1]; edge packet loss and error rates in [0, 1]; `simulationDuration > warmupDuration`; at least one source node reachable | Blocking or warning diagnostics |

**Relationship to existing `validateTopology()`:**

The existing `validateTopology()` should continue to validate topology structure (Zod schema, cross-references, connectivity). The new environment validation runs after topology validation passes and covers environment-specific concerns. The two can be composed:

```
validateTopology(topologyJSON)  → topology-level errors/warnings
validateEnvironment(envConfig, topologyJSON)  → environment-level errors/warnings
```

Both must pass before normalization proceeds.

#### New types

```ts
/**
 * Result of validating a simulation environment.
 */
export interface EnvironmentValidationResult {
  /** Whether the environment can be used to run a simulation. */
  valid: boolean

  /** Structured diagnostics produced during validation. */
  diagnostics: EnvironmentDiagnostic[]
}
```

```ts
/**
 * Structured diagnostic for an environment configuration issue.
 */
export interface EnvironmentDiagnostic {
  /**
   * Stable diagnostic code for tests and programmatic handling.
   * Format: 'ENV_XXX' where XXX is a mnemonic (e.g., 'ENV_NODE_ID_MISMATCH').
   */
  code: string

  /** Error diagnostics block simulation; warning diagnostics allow it but surface feedback. */
  severity: 'error' | 'warning'

  /** Dot-separated path to the invalid part of the config (e.g., 'nodes.lb-1.queue.capacity'). */
  path: string

  /** Human-readable message. */
  message: string

  /** Optional related node or edge identifier. */
  targetId?: string

  /** Optional related constraint id. */
  constraintId?: string
}
```

These types should live in `src/engine/core/environmentTypes.ts`.

Proposed function signatures (`src/engine/environment/validateEnvironment.ts`):

```ts
import type {
  SimulationEnvironmentConfig,
  NormalizedSimulationEnvironment,
  EnvironmentValidationResult
} from '../core/environmentTypes'
import type { TopologyJSON } from '../core/types'

/**
 * Validates an environment config before normalization.
 * Checks shape, references, behaviour rules, and constraints.
 */
export function validateSimulationEnvironment(
  config: SimulationEnvironmentConfig,
  topology: TopologyJSON
): EnvironmentValidationResult

/**
 * Validates a normalized environment immediately before simulation.
 * This is a safety net that catches issues introduced during normalization.
 */
export function validateNormalizedEnvironment(
  environment: NormalizedSimulationEnvironment
): EnvironmentValidationResult
```

Both raw-config and normalized-config validation are useful because:
- Raw-config validation catches user input errors early (before the normalization step runs), producing diagnostics with paths that map to the user's configuration.
- Normalized-config validation is a safety net: it catches bugs in the normalization logic itself, and it validates derived values (e.g., a node's resolved capacity after merging defaults + overrides).

**Proposed diagnostic codes (v1):**

| Code | Severity | Phase | Condition |
| --- | --- | --- | --- |
| `ENV_MISSING_ID` | error | shape | `config.id` is empty or missing |
| `ENV_INVALID_GLOBAL` | error | shape | `config.global` has out-of-range values |
| `ENV_NODE_ID_MISMATCH` | error | reference | A key in `config.nodes` does not match any topology node id |
| `ENV_EDGE_ID_MISMATCH` | error | reference | A key in `config.edges` does not match any topology edge id |
| `ENV_DISALLOWED_NODE_OVERRIDE` | error | behaviour | Node specifies an override that `behaviourRules` disallows |
| `ENV_DISALLOWED_EDGE_OVERRIDE` | error | behaviour | Edge specifies an override that `behaviourRules` disallows |
| `ENV_CAPACITY_INVALID` | error | constraint | Queue capacity < queue workers after merge |
| `ENV_ERROR_RATE_RANGE` | error | constraint | Node error rate outside [0, 1] |
| `ENV_LOSS_RATE_RANGE` | error | constraint | Edge packet loss outside [0, 1] |
| `ENV_WARMUP_EXCEEDS_DURATION` | error | constraint | `warmupDuration >= simulationDuration` |
| `ENV_NO_SOURCE_NODE` | error | constraint | No source node reachable in topology |
| `ENV_UNUSED_NODE_CONFIG` | warning | reference | Node config exists for a node with `structuralRole: 'composite'` (not simulated) |
| `ENV_DEFAULT_QUEUE_APPLIED` | warning | normalization | Node is missing queue config; environment default was applied |

#### Integration points

Environment validation should run:

1. **Before simulation** — in the assembly pipeline, after topology validation passes and before normalization. This is the primary validation point.
2. **Before persistence** — if the renderer supports saving environment configs, validation should run before writing to detect issues before the user closes the session.
3. **In tests** — test fixtures should construct `SimulationEnvironmentConfig` objects and validate them before passing to the engine. This replaces the current pattern of passing raw `TopologyJSON` and relying on the engine's internal defaults.

Integration with existing code:

- `src/engine/validation/validator.ts` should export `validateTopology()` unchanged for backward compatibility. A new `validateSimulationEnvironment()` function in `src/engine/environment/validateEnvironment.ts` handles environment validation.
- The worker protocol (`src/engine/worker/protocols.ts`) should pass environment validation results back to the main thread for display.
- `src/renderer/src/hooks/useSimulation.ts` should check `EnvironmentValidationResult.valid` before posting the `run` message to the worker.

### What components it requires

**Engine-side:**
- `src/engine/environment/validateEnvironment.ts` — new module: `validateSimulationEnvironment()` and `validateNormalizedEnvironment()`
- `src/engine/core/environmentTypes.ts` — `EnvironmentValidationResult`, `EnvironmentDiagnostic` types
- Update `src/engine/worker/simulation.worker.ts` — run environment validation before constructing `SimulationEngine`

**Shared layer:**
- `EnvironmentValidationResult` and `EnvironmentDiagnostic` are importable by both engine and renderer

**Renderer/frontend-side:**
- Update `src/renderer/src/hooks/useSimulation.ts` — validate before running
- Expose validation diagnostics in store for display (data only; no visual spec)

### Explored in

- Product discussion notes: Environment Definition
- Product discussion notes: Request Rejection Behaviour
- Product discussion notes: Pattern Accuracy
- Product discussion notes: Simplifying the Application

---

## Relationship to Adjacent Feature Domains

| Adjacent feature domain | Shared data source | What this spec defines | What the adjacent spec adds |
| --- | --- | --- | --- |
| Request Pattern Configuration | `EnvironmentDefaults.requestPatternId`, `EnvironmentNodeConfig.requestPatternId` | Where the pattern assignment lives; global default and per-node override location | Pattern shapes (constant, poisson, bursty, etc.), presets, validation, and simulation effect |
| Request Flow Direction & Topology Rules | `EnvironmentEdgeConfig.direction`, `EnvironmentBehaviourRules.allowBidirectionalRequests` | Where direction is configured; whether bidirectional is allowed | Direction inference from topology, routing semantics, and path resolution |
| Request Type Model | `SimulationEnvironmentConfig` (attachment point) | Where request type support would live in the environment | Request type properties, effects on processing time, and routing decisions |
| Edge Properties & Defaults | `EnvironmentEdgeDefaults`, `EnvironmentEdgeConfig` | Default/override structure for edge configuration | Full edge property model (bandwidth shaping, protocol effects, congestion) |
| Throughput Calculation | `ResolvedNodeConfig.queue`, `ResolvedEdgeConfig.bandwidth` | Node and edge capacity data contract | Throughput formulas, result semantics, and visualization |
| Queue Depth Calculation | `ResolvedNodeConfig.queue.capacity`, `ResolvedNodeConfig.queue.workers` | Queue-related config fields | Queue depth formulas, overflow semantics, and visual representation |
| Request Rejection Behaviour | `EnvironmentBehaviourRules.allowRejection`, `EnvironmentConstraint` | Where rejection is enabled/disabled; constraint that gates it | Rejection causes, metrics, lifecycle impact, and cascading effects |
| Cost Calculation & Budgeting | `SimulationEnvironmentConfig` (attachment point) | Where cost-related config may attach | Cost formulas, budget thresholds, and warnings |
| Simulation Validation & Pattern Accuracy | `EnvironmentValidationResult`, `EnvironmentDiagnostic` | Validation contract and diagnostic model | Test cases, fixtures, expected outputs, and accuracy regression tests |
| Default-Driven Simplification Layer | `EnvironmentDefaults`, inheritance model | Configuration inheritance chain and override semantics | Progressive disclosure rules, simplified setup UX, and preset management |

---

## Integration Requirements

| Layer | File/module | Change required | Why needed | Size/complexity |
| --- | --- | --- | --- | --- |
| Engine core | `src/engine/core/environmentTypes.ts` (new) | Create file with all environment types | Central type definitions for the environment model | Medium |
| Engine environment | `src/engine/environment/productDefaults.ts` (new) | Create file with product hard defaults | Single source of truth replacing 4 scattered default locations | Small |
| Engine environment | `src/engine/environment/assembleEnvironment.ts` (new) | Create function to build `SimulationEnvironmentConfig` from `TopologyJSON` + user overrides | Assembly pipeline entry point | Medium |
| Engine environment | `src/engine/environment/normalizeEnvironment.ts` (new) | Create normalization function | Resolves inheritance; produces fully populated config | Medium |
| Engine environment | `src/engine/environment/validateEnvironment.ts` (new) | Create environment validation functions | Multi-phase validation with structured diagnostics | Medium |
| Engine core | `src/engine/engine.ts` | Accept `NormalizedSimulationEnvironment` in constructor; remove `withNodeDefaults()` | Engine consumes normalized config instead of deriving defaults | Medium |
| Engine validation | `src/engine/validation/validator.ts` | Remove inline node default mutations (lines 617-630); keep topology-level validation | Defaults now come from environment normalization, not validator mutations | Small |
| Engine worker | `src/engine/worker/protocols.ts` | Add environment config to `RunMessage.payload` | Worker needs environment to validate and normalize before engine construction | Small |
| Engine worker | `src/engine/worker/simulation.worker.ts` | Add environment validation and normalization before `new SimulationEngine()` | Validation runs in the worker thread | Small |
| Renderer hooks | `src/renderer/src/hooks/useTopologySerializer.ts` | Replace `EDGE_DEFAULTS` with environment defaults; optionally produce `SimulationEnvironmentConfig` | Edge defaults should come from the environment model | Medium |
| Renderer hooks | `src/renderer/src/hooks/useSimulation.ts` | Pass environment config through worker; check validation result | Environment validation before simulation | Small |
| Renderer store | `src/renderer/src/store/useStore.ts` | Add environment state slice | Store environment config for the current session | Small |
| Renderer types | `src/renderer/src/types/ui.ts` | Map `ScenarioState` to `EnvironmentGlobalConfig` | Scenario state feeds into environment global config | Small |
| Engine tests | `src/engine/engine.test.ts` | Update test fixtures to use environment config; add normalization tests | Tests should exercise the new environment pipeline | Medium |
| Engine tests | `src/engine/validation/validator.test.ts` | Add environment validation tests | Test diagnostic codes and constraint checking | Medium |
| Engine mocks | `src/engine/__mocks__/sampleTopology.ts` | Add companion `SimulationEnvironmentConfig` fixture | Test helpers need environment configs | Small |

---

## Source-to-Feature Map

| Source material item | Feature(s) covered | Notes |
| --- | --- | --- |
| Product notes: Environment Definition | Feature 1 (Environment Configuration Object), Feature 3 (Validation and Constraints) | Defines what an environment includes and what constraints it must satisfy |
| Product notes: Global Default Pattern | Feature 1 (defaults), Feature 2 (inheritance model) | Establishes the default-driven approach |
| Product notes: Request Pattern Configuration | Feature 1 (requestPatternId field), Feature 2 (node override) | Environment model stores the pattern assignment; pattern algorithms belong to the adjacent spec |
| Product notes: Simplifying the Application | Feature 1 (defaults), Feature 2 (inheritance), Feature 3 (validation) | The entire environment model is a simplification mechanism |
| Product notes: Request Direction | Feature 1 (edge direction config), Feature 2 (edge override) | Environment model stores direction; inference belongs to the adjacent spec |
| Product notes: Edge Properties | Feature 1 (edge defaults), Feature 2 (edge override) | Environment model stores edge defaults and overrides; full property model belongs to the adjacent spec |
| Product notes: Request Rejection Behaviour | Feature 1 (allowRejection rule), Feature 3 (constraint model) | Environment model enables/disables rejection; rejection mechanics belong to the adjacent spec |
| Product notes: Customisation Scope | Feature 2 (inheritance and overrides) | Defines what can be overridden at node vs global level |

---

## Assumptions and Unresolved Questions

| Assumption/question | Affected feature | Risk if wrong | Needs product answer? |
| --- | --- | --- | --- |
| v1 environment config is assembled automatically from `TopologyJSON` + `ScenarioState`; users do not manually edit a raw environment JSON | Feature 1 | If users need to edit environment JSON directly, a schema and editor are needed earlier | Yes |
| Node-level overrides for queue and processing are enabled in v1 (they already exist implicitly via `ComponentNode` optional fields) | Feature 2 | If overrides should be disabled in v1, the behaviour rule `allowNodePatternOverrides: false` must be the default and the normalization logic must enforce it | No — current codebase already supports overrides |
| Edge-level overrides exist in v1 (the serializer already populates per-edge values) | Feature 2 | If edge overrides should be deferred, `allowEdgeOverrides: false` must be the default and all edges must use environment defaults | Yes — product should confirm whether edge customization is v1 |
| `allowRejection: true` is the v1 default (the engine already rejects on `capacity_exceeded`) | Feature 1 | If rejection should be off by default, `GGcKNode.handleArrival` needs a guard that checks the behaviour rule | No — current engine already rejects |
| `allowBidirectionalRequests: false` is the v1 default (the engine only supports source→target traversal) | Feature 1 | If bidirectional is needed in v1, the routing table needs changes beyond this spec | No — current engine does not support it |
| Request direction lives on edges (as `EnvironmentEdgeConfig.direction`), not on nodes or topology-level config | Feature 1 | If direction should be a topology-level or node-level concern, the type model changes | Yes — product should confirm |
| Request type is NOT part of the v1 environment model (it is already modeled in `WorkloadProfile.requestDistribution`) | Feature 1 | If request type needs environment-level config (e.g., "this environment supports GET and POST"), a `requestTypes` field is needed | Yes — likely deferred |
| Cost/budget config is deferred (no cost model exists in the codebase) | Feature 1 | If cost config is needed in v1, a `cost` field must be added to `SimulationEnvironmentConfig` | Yes — likely deferred |
| Environment constraints that block simulation are limited to structural issues in v1 (missing config, id mismatches, range violations) | Feature 3 | If product-level constraints (e.g., "max 50 nodes per environment") are needed, the constraint model must support them | Yes |
| The environment config is not persisted separately from the topology JSON file in v1 | Feature 1 | If environments should be saved and loaded independently of topologies, a persistence layer is needed | Yes |
| `SimulationEngine` constructor should accept both `TopologyJSON` (for structure) and `NormalizedSimulationEnvironment` (for config) rather than a single merged object | Feature 1 | If the engine should receive a single object, the topology structure must be embedded in the normalized environment, increasing coupling | No — separation is cleaner |

---

## Validation Step

```
$ npm run typecheck
$ npm run lint
$ npm test
```

These commands validate the existing codebase. Since this document is a specification (markdown only, no code changes), the checks confirm that the current codebase is in a buildable state and that the proposed types and integration points are consistent with the existing architecture.

No code was modified by this document. The proposed types, modules, and integration points are described for future implementation.

---

*This document covers only the Environment Definition & Configuration Model. The following specs are intentionally not written yet:*

1. *Request Pattern Configuration*
2. *Request Flow Direction & Topology Rules*
3. *Request Type Model*
4. *Edge Properties & Defaults*
5. *Throughput Calculation*
6. *Queue Depth Calculation*
7. *Arrival, Departure & Request Lifecycle Semantics*
8. *Request Rejection Behaviour*
9. *Cost Calculation & Budgeting*
10. *Simulation Validation & Pattern Accuracy*
11. *Default-Driven Simplification Layer*

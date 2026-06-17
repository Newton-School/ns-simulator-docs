# Simulation Validation & Pattern Accuracy

Technical feature specification defining the four layers of simulation validation: pre-run topology validation, post-run statistical checks, pattern accuracy classification, and reproducibility guarantees. This spec consolidates the validator, Little's Law verification, conservation checking, warmup adequacy assessment, SLO breach detection, invariant checking (stub), and the seeded RNG reproducibility system into a single reference.

This spec exists because validation is the trust layer — every metric, recommendation, and SLO breach reported by the simulator is only meaningful if the simulation ran correctly on valid input. A broken topology, an inadequate warmup, or a non-reproducible RNG would silently invalidate all downstream analysis.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Pre-Run Topology Validation](#feature-1-pre-run-topology-validation)
4. [Feature 2: Post-Run Statistical Checks](#feature-2-post-run-statistical-checks)
5. [Feature 3: Parameter Accuracy Classification](#feature-3-parameter-accuracy-classification)
6. [Feature 4: Reproducibility & Determinism](#feature-4-reproducibility--determinism)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Simulation Validation & Pattern Accuracy provides four layers of trust:

1. **Pre-run validation**: Ensures the topology is structurally sound before simulation starts — valid types, referential integrity, connectivity, and semantic constraints.
2. **Post-run statistical checks**: Verifies that simulation output is internally consistent — Little's Law holds, conservation accounting balances, warmup was adequate, and SLO breaches are detected.
3. **Parameter accuracy classification**: Classifies every simulation parameter by its fidelity to reality — invariant constants, user-supplied values, default overrides, or not-simulated placeholders.
4. **Reproducibility**: Guarantees that the same seed + topology produces identical results, enabling regression testing and comparative analysis.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Validation results and accuracy flags are user-visible output |
| Architectural change      |       No | All validation infrastructure exists; gaps are in coverage |
| Domain model addition     |  Partial | `ParameterAccuracyClass` is defined but unused; `InvariantCheck` is a stub |
| Validation layer          |      Yes | This is the validation spec |
| Refactor of existing code |       No | Existing code is sound; spec documents gaps |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Topology structural validation (Zod parse) | Yes | `validateTopology` Zod schema and cross-reference checks |
| Topology semantic validation (connectivity, roles) | Yes | BFS reachability, role-based warnings, self-loop detection |
| Little's Law verification | Yes | `calculateLittlesLaw` with dual tolerance guard |
| Conservation accounting | Yes | `buildConservationCheck` identity verification |
| Warmup adequacy assessment | Yes | `assessWarmupAdequacy` heuristic |
| SLO breach detection | Partial | Mechanism owned here; SLO *definition* owned by each metric spec |
| Invariant checking | Yes | `InvariantCheck` type and stub infrastructure |
| Parameter accuracy classification | Yes | `ParameterAccuracyClass` type and proposed usage |
| Seeded RNG and reproducibility | Yes | `createRandom` and determinism guarantees |
| Node defaults application | Partial | Validation defaults documented here; ownership belongs to Default-Driven Simplification Layer |
| Error budget checking | No | Belongs to Cost Calculation & Budgeting |
| Rejection metrics accuracy | No | Belongs to Request Rejection Behaviour |

---

## Problem Context

### What exists today

**Pre-run validation** — `validateTopology` at `src/engine/validation/validator.ts:570-847`:
- Zod structural parse against `TopologyJSONSchema`
- Duplicate node/edge ID detection
- Edge source/target reference validity
- Dependency reference validity
- Fault target ID validity
- `simulationDuration > warmupDuration` check
- `capacity >= workers` check
- `timeout > 0` check
- `nodeErrorRate` in [0, 1] check
- Security filter node requires `blockRate` or `droppedPackets`
- Sink nodes cannot have routing strategy
- Source node existence check
- Workload source node reachability check
- Connectivity warnings: disconnected nodes, source-to-source edges, self-loops, source with incoming edges, sink with outgoing edges, router with ≤1 outgoing edge

**Post-run statistical checks** — `src/engine/analysis/output.ts`:
- Little's Law: `calculateLittlesLaw` (lines 223-250)
- Conservation: `buildConservationCheck` (lines 308-326)
- Warmup adequacy: `assessWarmupAdequacy` (lines 256-299)
- SLO breaches: `detectSLOBreaches` (lines 172-213)

**Invariant checking** — `InvariantCheck` at `types.ts:423-427` and `InvariantViolation` at `output.ts:37-44`:
Both types exist, validated by Zod (`InvariantCheckSchema` at `validator.ts:498`), and `invariantViolations` is a field on `SimulationOutput`. But the engine always passes `[]` at `engine.ts:604` — no invariants are ever evaluated.

**Parameter accuracy** — `ParameterAccuracyClass` at `types.ts:11-15`:
Four classification levels defined (`'invariant'`, `'default-override'`, `'user-parameter'`, `'not-simulated'`) with a comment explaining each. Never referenced outside the type definition.

**Reproducibility** — `createRandom` at `src/engine/stochastic/random.ts:37-74`:
Uses xmur3 hash for seed initialization and sfc32 PRNG. `SimulationOutput.reproducible` is hardcoded to `true` at `output.ts:117`. `SimulationOutput.seed` records the seed used.

### What's missing

| Gap | Impact |
| --- | --- |
| Invariant evaluation is stubbed (`[]` always) | User-defined invariants on `TopologyJSON.invariants` are validated but never checked at runtime |
| `ParameterAccuracyClass` is never used | No way to communicate which parameters are real vs. defaults vs. not-simulated |
| No causal graph analysis | `causalGraph` is always `null` (`engine.ts:603`); cascade analysis is not implemented |
| Validator defaults duplicate engine defaults | `validator.ts:620-631` and `engine.ts:627-636` both apply `{workers:1, capacity:100, discipline:'fifo'}` independently |
| No distribution fit testing | No way to verify that a configured distribution (e.g., log-normal with specific mu/sigma) produces the expected statistical properties |
| No cross-node consistency checks | No validation that total edge throughput into a node is compatible with its capacity |
| `reproducible: true` is hardcoded | No runtime verification that determinism actually held; parallel execution or floating-point non-determinism could break it |
| Conservation check doesn't account for bulk `fail()` drops | Queued requests cleared by `GGcKNode.fail()` don't go through `recordRejection` |

---

## Feature 1: Pre-Run Topology Validation

### Current implementation

`validateTopology` at `validator.ts:570-847` performs validation in four phases:

**Phase 1: Structural parse (Zod)**

The `TopologyJSONSchema` at `validator.ts:506-525` uses Zod to validate the JSON structure:
- `nodes`: array of `ComponentNodeSchema` (types, categories, optional configs)
- `edges`: array of `EdgeDefinitionSchema` (source, target, mode, latency distribution)
- `global`: `GlobalConfigSchema` (duration, seed, warmup, timeout)
- `workload`: optional `WorkloadProfileSchema`
- `faults`: optional array of `FaultSpecSchema`
- `invariants`: optional array of `InvariantCheckSchema`

If Zod parse fails, validation returns immediately with structural errors.

**Phase 2: Cross-reference checks**

After parse, the validator builds auxiliary data structures and checks referential integrity:
- Node ID uniqueness (error on duplicate)
- Edge ID uniqueness (error on duplicate)
- Edge source/target existence (error if node doesn't exist)
- Dependency ID existence (error if optional dependency not found)
- Fault target existence (error if fault references unknown node/edge)
- Workload source node existence (error if referenced node doesn't exist)
- Source node existence (error if no source node in topology)
- Workload source reachability (error if source can't reach any downstream non-source node)

**Phase 3: Semantic defaults and constraints**

For non-source nodes, the validator applies defaults if configs are missing:
```typescript
// validator.ts:616-631
if (!node.queue) {
  warnings.push(`Node '${node.label}' is missing queue config; applying legacy default queue settings.`)
  node.queue = { workers: 1, capacity: 100, discipline: 'fifo' }
}
if (!node.processing) {
  warnings.push(`Node '${node.label}' is missing processing config; applying legacy default processing settings.`)
  node.processing = { distribution: { type: 'constant', value: 1 }, timeout: 30_000 }
}
```

Then validates semantic constraints:
- `capacity >= workers` (error)
- `timeout > 0` (error)
- `nodeErrorRate` in [0, 1] (error)
- Security filter nodes must have `blockRate` or `droppedPackets` (error)
- Sink nodes cannot have routing strategy (error)
- `simulationDuration > warmupDuration` (error)

**Phase 4: Connectivity analysis (warnings only)**

Uses BFS via `collectReachableNodeIds` (validator.ts:545-568) to find all nodes reachable from source nodes, then reports:
- Disconnected nodes (warning)
- Self-loops (warning)
- Source-to-source edges (warning)
- Source with incoming edges (warning)
- Sink with outgoing edges (warning)
- Router with ≤1 outgoing edge and routing strategy defined (warning)

### Return type

```typescript
interface ValidationResult {
  valid: boolean;
  data?: TopologyJSON;    // present only when valid=true
  errors: ValidationError[];
  warnings: string[];
}

interface ValidationError {
  path: string;     // dot-notation path (e.g., "nodes[2].queue.capacity")
  message: string;
}
```

### Gaps in pre-run validation

| Missing check | Impact |
| --- | --- |
| Cycle detection | A cycle (A→B→A) creates infinite request loops that exhaust the event queue |
| Edge weight consistency | Weighted routing requires at least one edge with `weight > 0`; not validated |
| Conditional edge regex validation | `matchesCondition` only supports `request.type === "X"`; arbitrary strings are silently ignored |
| Distribution parameter validity | Zod validates structure but not statistical validity (e.g., sigma ≤ 0 for log-normal) |
| Workload pattern parameter completeness | e.g., `bursty` pattern requires `burstMultiplier` and `burstDuration` but defaults silently if absent |
| Capacity vs. arrival rate feasibility | No warning when configured capacity is clearly insufficient for the workload |

### Proposed cycle detection

```typescript
function detectCycles(adjacencyList: Map<string, string[]>): string[][] {
  const visited = new Set<string>();
  const stack = new Set<string>();
  const cycles: string[][] = [];

  function dfs(node: string, path: string[]): void {
    if (stack.has(node)) {
      const cycleStart = path.indexOf(node);
      cycles.push(path.slice(cycleStart));
      return;
    }
    if (visited.has(node)) return;

    visited.add(node);
    stack.add(node);
    for (const neighbor of adjacencyList.get(node) ?? []) {
      dfs(neighbor, [...path, node]);
    }
    stack.delete(node);
  }

  for (const node of adjacencyList.keys()) {
    dfs(node, []);
  }
  return cycles;
}
```

Cycles should be warnings (not errors) because some topologies intentionally model retry loops or feedback paths. The warning should note the cycle and its length.

---

## Feature 2: Post-Run Statistical Checks

### Little's Law verification

**Implementation:** `calculateLittlesLaw` at `output.ts:223-250`

Little's Law states L = λW for any stable queuing system:
- **L** = time-average number of items in system (observed via `postWarmupAvgInSystem`)
- **λ** = arrival rate in requests/second (`postWarmupArrived / effectiveDurationSec`)
- **W** = mean sojourn time in seconds (`postWarmupAvgTimeInSystem / 1000`)

The check computes `expectedL = λ × W` and compares against `observedL`:

```typescript
const absoluteError = Math.abs(observedL - expectedL)
const error = absoluteError / Math.max(expectedL, 0.001)
withinTolerance: error <= 0.1 || absoluteError <= 0.5  // dual guard
```

**Dual tolerance guard:** The `OR` condition means a node passes if *either*:
1. Relative error ≤ 10% — works well for busy nodes where L > 5
2. Absolute error ≤ 0.5 — works well for lightly loaded nodes where L ≈ 0.1 and 10% is too tight

**When Little's Law fails:**
- Inadequate warmup (transient ramp-up inflates W)
- Non-stationary arrival process (spike/diurnal patterns violate steady-state assumption)
- Simulation too short (insufficient samples for stable averages)
- Conservation imbalance (requests leaked or double-counted)

**Output type:** `LittlesLawResult` per node with `observedL`, `expectedL`, `error`, `withinTolerance`, `lambda`, `wSeconds`.

### Conservation accounting

**Implementation:** `buildConservationCheck` at `output.ts:308-326`

The conservation identity for the post-warmup window:
```
postWarmupArrived = postWarmupProcessed + postWarmupRejected + postWarmupTimedOut + inFlight
```

Where `inFlight = max(0, arrived - processed - rejected - timedOut)`.

A node is "balanced" if `inFlight / postWarmupArrived < 0.05` or `postWarmupArrived == 0`.

**When conservation fails:**
- Bulk `fail()` drops queued requests without calling `recordRejection` (known bug — see Request Rejection Behaviour)
- Simulation duration too short — many requests still in queue at cutoff
- Bug in metrics recording — double-counting or missing counts

**Output type:** `ConservationResult` per node with all five counters plus `balanced` boolean.

### Warmup adequacy assessment

**Implementation:** `assessWarmupAdequacy` at `output.ts:256-299`

Heuristic: warmup should be ≥ 10× the maximum per-node p99 latency. This ensures the system has cycled through at least 10 "slow request" durations before metrics start accumulating.

```typescript
const WARMUP_MULTIPLIER = 10
const recommendedWarmupMs = Math.ceil(maxP99Ms * WARMUP_MULTIPLIER)
adequate = warmupMs >= recommendedWarmupMs
```

**Edge cases:**
- If no traffic observed (`maxP99Ms === 0`): returns adequate (cannot assess)
- If warmup is shorter than recommended: returns inadequate with specific recommendation

**Output type:** `WarmupAdequacy` with `adequate`, `warmupMs`, `recommendedWarmupMs`, `reason`.

### SLO breach detection

**Implementation:** `detectSLOBreaches` at `output.ts:172-213`

Checks two dimensions per node (only if `slo` is defined via node metadata):

1. **Latency P99:** `nodeMetrics.latencyP99 > slo.latencyP99` — breach if actual exceeds target
2. **Availability:** `nodeMetrics.availability < slo.availabilityTarget` — breach if actual is below target

Severity: `severityForRatio(ratio)` returns `'critical'` if ratio ≥ 1.25, else `'warning'`.

**Missing dimension:** `errorBudget` is defined on `SLOConfig` but never checked (documented in Cost Calculation & Budgeting).

**Output type:** `SLOBreach` with `nodeId`, `nodeLabel`, `metric`, `target`, `actual`, `severity`.

### Invariant checking (stub)

**Current state:** `InvariantCheck` at `types.ts:423-427` defines:
```typescript
interface InvariantCheck {
  id: string;
  description: string;
  condition: string;  // expression to evaluate
}
```

The Zod schema validates this structure. `TopologyJSON.invariants` can contain user-defined invariants. But `engine.ts:604` passes `[]` for `invariantViolations` — no invariants are ever evaluated.

**Proposed evaluation model:**

Invariants should be evaluated against `PerNodeMetrics` and `SimulationSummary` at the end of the simulation:

```typescript
interface InvariantContext {
  summary: SimulationSummary;
  perNode: Record<string, PerNodeMetrics>;
  conservationCheck: ConservationResult[];
  littlesLawCheck: LittlesLawResult[];
}

function evaluateInvariants(
  invariants: InvariantCheck[],
  context: InvariantContext
): InvariantViolation[];
```

The `condition` string would need a safe expression evaluator (not `eval`) — a simple predicate language supporting:
- Node metric access: `node["api-gateway"].latencyP99 < 100`
- Global metric access: `summary.throughput > 1000`
- Boolean operators: `&&`, `||`, `!`
- Comparisons: `>`, `<`, `>=`, `<=`, `==`

---

## Feature 3: Parameter Accuracy Classification

### Current type definition

`ParameterAccuracyClass` at `types.ts:11-15`:
```typescript
export type ParameterAccuracyClass =
  | 'invariant'         // internal mechanics/safety constants, not scenario knobs
  | 'default-override'  // system-applied default, user hasn't set it
  | 'user-parameter'    // explicitly configured by the user
  | 'not-simulated'     // defined in type system but has no runtime effect
```

This type is defined with a comment explaining each level but is never referenced in any other file.

### Proposed usage

Parameter accuracy classification answers: "How much should I trust this metric?" If a node's service time is a hardcoded default (constant 1ms), the throughput metric is based on an assumption, not a measurement. If it's a user-supplied log-normal distribution fitted to production data, the metric is grounded.

**Per-parameter accuracy map:**

```typescript
interface ParameterAccuracy {
  parameter: string;         // e.g., "queue.workers", "processing.distribution"
  accuracy: ParameterAccuracyClass;
  source: string;            // e.g., "user config", "withNodeDefaults", "EDGE_DEFAULTS"
  confidence: number;        // 0–1 heuristic
}

interface NodeAccuracyReport {
  nodeId: string;
  parameters: ParameterAccuracy[];
  overallConfidence: number;  // geometric mean of parameter confidences
}
```

**Classification rules:**

| Parameter | `invariant` | `user-parameter` | `default-override` | `not-simulated` |
| --- | --- | --- | --- | --- |
| `queue.workers` | — | User set explicitly | Default 1 from `withNodeDefaults` | — |
| `queue.capacity` | — | User set explicitly | Default 100 from `withNodeDefaults` | — |
| `queue.discipline` | — | User set explicitly | Default 'fifo' from `withNodeDefaults` | — |
| `processing.distribution` | — | User set explicitly | Default constant(1) from `withNodeDefaults` | — |
| `processing.timeout` | — | User set explicitly | Default 30000 from `withNodeDefaults` | — |
| `edge.latency.distribution` | — | User set explicitly | Default log-normal(2.3, 0.5) from renderer | — |
| `edge.bandwidth` | — | User set explicitly | — | Has no runtime effect |
| `edge.protocol` | — | User set explicitly | — | Has no runtime effect |
| `edge.pathType` | — | User set explicitly | — | Has no runtime effect |
| `resources.cpu` | — | User set explicitly | — | Has no runtime effect |
| `resources.memory` | — | User set explicitly | — | Has no runtime effect |
| `resilience.circuitBreaker` | — | User set explicitly | — | Has no runtime effect |
| `resilience.retry` | — | User set explicitly | — | Has no runtime effect |
| `scaling` | — | User set explicitly | — | Has no runtime effect |
| Event priority mapping | `SYSTEM=0, ARRIVAL=1...` | — | — | — |
| Warmup multiplier (10×) | `10` | — | — | — |
| Conservation threshold (5%) | `0.05` | — | — | — |
| Little's Law tolerance (10%/0.5) | `0.1, 0.5` | — | — | — |

**Output in SimulationOutput:**

```typescript
interface SimulationOutput {
  // ... existing fields ...
  accuracyReport?: NodeAccuracyReport[];
  overallConfidence: number;  // topology-wide confidence score
}
```

### Confidence scoring

Overall confidence is the geometric mean of per-node confidences. Per-node confidence weights each parameter by its impact on metrics:

| Parameter | Weight | Rationale |
| --- | --- | --- |
| `processing.distribution` | 3 | Drives service time, throughput, latency — most impactful |
| `queue.workers` | 2 | Drives concurrency and utilization |
| `queue.capacity` | 2 | Drives rejection rate |
| `edge.latency.distribution` | 2 | Drives end-to-end latency |
| `processing.timeout` | 1 | Affects timeout rate |
| `queue.discipline` | 1 | Affects queue wait variance |

A node with all `user-parameter` values gets confidence 1.0. All `default-override` gets ~0.5. Mixing user and default parameters produces an intermediate score. `not-simulated` parameters don't affect confidence because they don't affect metrics.

---

## Feature 4: Reproducibility & Determinism

### Current implementation

**Seeded PRNG:** `createRandom` at `src/engine/stochastic/random.ts:37-74`

The RNG is initialized from a string seed via:
1. `xmur3(seedString)` — converts arbitrary string to a hash function that produces 32-bit integers
2. `sfc32(seed(), seed(), seed(), seed())` — initializes the sfc32 PRNG with four seeded values

sfc32 (Small, Fast, Chaotic) is a 128-bit state PRNG with:
- Period: 2^128 (practically infinite for simulation purposes)
- Statistical quality: passes PractRand and TestU01 SmallCrush
- Speed: very fast (single function, integer-only arithmetic)
- Determinism: identical seed → identical sequence, always

**Seed propagation:** The seed is set in `GlobalConfig.seed` (default `'default-seed'` from `DEFAULT_SCENARIO_STATE`). The engine creates a single RNG at construction (`engine.ts:59`) and passes it to all subsystems:
- `Distributions` (service time sampling)
- `RoutingTable` (weighted random, uniform random selection)
- `WorkloadGenerator` (inter-arrival times, request type selection, priority)
- `enqueueEdgeTransfer` (packet loss, error rate)
- `shouldFailAtNode` (node error rate)
- `applySecurityPolicy` (block rate, dropped packets)

Because all random decisions flow through a single sequential RNG, the sequence of random calls is deterministic for a given topology + seed.

**Output guarantees:** `SimulationOutput.reproducible` is hardcoded to `true` (`output.ts:117`). `SimulationOutput.seed` records the seed used (`output.ts:162`).

### Determinism constraints

For reproducibility to hold, the following invariants must be maintained:

1. **Single-threaded execution.** The event loop is sequential — `processEvents` extracts one event at a time from the MinHeap. If execution were parallelized, the order of RNG calls would be non-deterministic.

2. **Deterministic event ordering.** The MinHeap breaks ties by insertion order (FIFO within same timestamp). Combined with deterministic event creation order, this ensures the same events are processed in the same order.

3. **No floating-point non-determinism.** All time calculations use `bigint` microseconds. Distribution sampling uses `number` (IEEE 754 double), which is deterministic for the same inputs on the same platform. Cross-platform reproducibility requires identical floating-point behaviour (generally true for V8/SpiderMonkey/JavaScriptCore).

4. **No external state.** The engine reads only from `TopologyJSON` and the RNG. No system clock, no network, no filesystem.

### Proposed reproducibility verification

Currently, `reproducible: true` is a declaration, not a verification. A runtime check could:

1. Run the simulation twice with the same seed (expensive but thorough)
2. Hash the event sequence and compare (requires storing the hash from a prior run)
3. Verify that key metrics match a prior run with the same seed (lightweight regression)

A practical approach is to store a fingerprint in the output:

```typescript
interface SimulationOutput {
  // ... existing fields ...
  fingerprint: string;  // hash of (seed + eventsProcessed + summary.throughput + summary.errorRate)
}
```

Two runs with the same topology and seed should produce identical fingerprints. A mismatch indicates a determinism bug.

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | Relationship |
| --- | --- |
| **Default-Driven Simplification Layer** | Validation applies defaults that duplicate engine defaults; default layer should be the single source |
| **Queue Depth Calculation** | Little's Law uses queue metrics (L); conservation check uses rejection/timeout counts |
| **Throughput Calculation** | Little's Law uses λ (arrival rate) and throughput for λW verification |
| **Request Rejection Behaviour** | Conservation check depends on accurate rejection counting; `fail()` bug affects balance |
| **Arrival, Departure & Request Lifecycle Semantics** | Event ordering drives determinism; lifecycle completeness drives conservation |
| **Edge Properties & Defaults** | Validator checks edge source/target existence; accuracy classification flags not-simulated edge properties |
| **Request Pattern Configuration** | Workload patterns affect Little's Law validity (non-stationary patterns violate steady-state) |
| **Cost Calculation & Budgeting** | Error budget checking is a post-run validation; extends SLO breach detection |
| **Request Type Model** | Condition-based edge filtering uses regex that isn't validated for correctness |

---

## Integration Requirements

### Across features

| Integration point | Producer | Consumer | Contract |
| --- | --- | --- | --- |
| `TopologyJSON` | Canvas serializer | `validateTopology` | Must conform to `TopologyJSONSchema` |
| `ValidationResult` | `validateTopology` | UI / Engine gate | `valid: true` required before simulation starts |
| `PerNodeMetrics` | `MetricsCollector` | All post-run checks | Consistent post-warmup counters |
| `GlobalConfig` | `TopologyJSON.global` | `calculateLittlesLaw`, `assessWarmupAdequacy` | Duration and warmup values |
| `SLOConfig` | `ComponentNode.slo` | `detectSLOBreaches` | Per-node latency and availability targets |
| `InvariantCheck[]` | `TopologyJSON.invariants` | `evaluateInvariants` (proposed) | User-defined post-run assertions |
| `GlobalConfig.seed` | User / default | `createRandom` | String seed for PRNG initialization |
| `SimulationOutput` | `generateSimulationOutput` | UI / API consumer | Contains all validation results |

### Within this feature

| Component | Responsibility | Key invariant |
| --- | --- | --- |
| `validateTopology` | Pre-run structural and semantic validation | No simulation starts without `valid: true` |
| `calculateLittlesLaw` | Post-run L=λW verification | Dual tolerance guard (10% relative OR 0.5 absolute) |
| `buildConservationCheck` | Post-run request accounting | `arrived = processed + rejected + timedOut + inFlight` |
| `assessWarmupAdequacy` | Post-run warmup heuristic | 10× max p99 multiplier |
| `detectSLOBreaches` | Post-run SLO comparison | Checks latency P99 and availability |
| `createRandom` | Deterministic PRNG | Same seed → same output, always |
| `ParameterAccuracyClass` | Per-parameter fidelity classification | Every parameter has exactly one class |

---

## Source-to-Feature Map

| Source file | Lines | Feature |
| --- | --- | --- |
| `src/engine/validation/validator.ts` | 570-847 | F1: `validateTopology` — full pre-run validation |
| `src/engine/validation/validator.ts` | 506-525 | F1: `TopologyJSONSchema` — Zod structural schema |
| `src/engine/validation/validator.ts` | 545-568 | F1: `collectReachableNodeIds` — BFS reachability |
| `src/engine/validation/validator.ts` | 616-631 | F1/F3: Default application with warnings |
| `src/engine/validation/validator.ts` | 498-502 | F2: `InvariantCheckSchema` — Zod schema for invariants |
| `src/engine/analysis/output.ts` | 223-250 | F2: `calculateLittlesLaw` — L=λW verification |
| `src/engine/analysis/output.ts` | 256-299 | F2: `assessWarmupAdequacy` — warmup heuristic |
| `src/engine/analysis/output.ts` | 308-326 | F2: `buildConservationCheck` — request accounting |
| `src/engine/analysis/output.ts` | 172-213 | F2: `detectSLOBreaches` — SLO breach detection |
| `src/engine/analysis/output.ts` | 37-44 | F2: `InvariantViolation` interface (output type) |
| `src/engine/analysis/output.ts` | 105-127 | F2: `SimulationOutput` containing all checks |
| `src/engine/core/types.ts` | 11-15 | F3: `ParameterAccuracyClass` type definition |
| `src/engine/core/types.ts` | 423-427 | F2: `InvariantCheck` type definition |
| `src/engine/stochastic/random.ts` | 1-74 | F4: `xmur3`, `sfc32`, `createRandom` — seeded PRNG |
| `src/engine/engine.ts` | 59 | F4: Single RNG creation from seed |
| `src/engine/engine.ts` | 604 | F2: `invariantViolations: []` — stub |
| `src/engine/engine.ts` | 603 | F2: `causalGraph: null` — stub |

---

## Assumptions and Unresolved Questions

### Assumptions

1. **Validation is a gate, not a filter.** If `validateTopology` returns `valid: false`, the simulation does not run. There is no "best-effort" mode that skips invalid nodes.

2. **Post-run checks are informational.** Little's Law failure, conservation imbalance, or warmup inadequacy do not invalidate the output — they flag potential issues. The UI should display these as warnings, not errors.

3. **Single RNG is sufficient for reproducibility.** All random decisions go through one `RandomGenerator` instance. If per-subsystem RNGs were needed (e.g., for isolation), they would need to be seeded from the parent RNG deterministically.

4. **Floating-point determinism holds within-platform.** Two runs of the same seed on the same JS engine version produce identical results. Cross-platform determinism (e.g., Node.js vs. browser, V8 vs. SpiderMonkey) is not guaranteed but is generally reliable for IEEE 754 operations.

5. **Little's Law is approximate for finite simulations.** The law holds exactly only for stationary, ergodic systems observed over infinite time. For finite simulations with warmup, the dual tolerance guard accounts for sampling variance.

### Unresolved questions

| # | Question | Why it matters |
| - | --- | --- |
| 1 | Should cycle detection be an error or a warning? | Some topologies intentionally model retry loops; others create infinite event storms |
| 2 | Should invariant evaluation use a safe expression language or a predicate DSL? | `eval` is a security risk; a custom DSL is safe but limited |
| 3 | Should the accuracy report be opt-in or always computed? | Adds output size; may not be relevant for quick iterations |
| 4 | Should reproducibility be verified by running twice? | Expensive but thorough; a hash-based fingerprint is cheaper |
| 5 | Should post-run checks support user-defined thresholds? | e.g., "Little's Law tolerance of 5% instead of 10%"; default works for most cases |
| 6 | Should validator warn when arrival rate × mean service time > workers? | This detects obvious capacity mismatches before simulation runs |
| 7 | How should non-stationary patterns (spike, diurnal) interact with Little's Law? | Little's Law assumes stationarity; spike/diurnal patterns systematically violate it |
| 8 | Should `ParameterAccuracyClass` be attached to each parameter at serialization time? | The serializer knows what the user set vs. what was defaulted; this information is lost by the time the engine sees it |

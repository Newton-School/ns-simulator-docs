# Cost Calculation & Budgeting

Technical feature specification defining how the simulator should compute infrastructure cost estimates from resource configurations, service times, and throughput data, and how error budgets should gate SLO compliance decisions. This spec bridges the gap between the existing type definitions (`ResourceConfig`, `SLOConfig.errorBudget`) and the missing runtime logic that would make cost and budget data actionable.

This spec exists because `ResourceConfig` (cpu, memory, replicas) and `SLOConfig.errorBudget` are defined in the type system, validated on input, and present on mock topologies — but never consumed by the engine, metrics collector, or analysis output. Cost and budgeting are the features these types were designed to support.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Resource Cost Model](#feature-1-resource-cost-model)
4. [Feature 2: Per-Request Cost Attribution](#feature-2-per-request-cost-attribution)
5. [Feature 3: Error Budget Accounting](#feature-3-error-budget-accounting)
6. [Feature 4: Cost-Aware Analysis Output](#feature-4-cost-aware-analysis-output)
7. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
8. [Integration Requirements](#integration-requirements)
9. [Source-to-Feature Map](#source-to-feature-map)
10. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Cost Calculation & Budgeting introduces two related capabilities: (1) estimating the infrastructure cost of running a topology based on resource allocations, utilization, and throughput, and (2) tracking error budget consumption against SLO targets to answer "how much of our error budget did this simulation burn?" Both capabilities derive from data that already exists in the simulation output — they are analysis-layer features that add no new events or engine logic.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Cost estimation and error budget are core capacity planning outputs |
| Architectural change      |       No | Analysis-layer only; no engine event loop changes |
| Domain model addition     |      Yes | New types: `CostConfig`, `CostEstimate`, `ErrorBudgetResult` |
| Validation layer          |  Partial | `ResourceConfig` and `errorBudget` are already validated |
| Refactor of existing code |       No | New code; existing types consumed for the first time |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Resource cost model (per-node cost from cpu/memory/replicas) | Yes | Maps `ResourceConfig` to dollar estimates |
| Per-request cost attribution | Yes | Cost per successful/failed request from resource usage |
| Error budget accounting | Yes | Consumes `SLOConfig.errorBudget`, computes burn rate |
| Error budget in SLO breach detection | Yes | Extends `detectSLOBreaches` with budget-based breaches |
| Cost in simulation output | Yes | New `CostEstimate` section in `SimulationOutput` |
| `ResourceConfig` type definition | No | Belongs to the type system; this spec consumes it |
| `SLOConfig.errorBudget` definition | No | Belongs to the type system; this spec consumes it |
| Throughput calculation | No | Belongs to Throughput Calculation; this spec uses the result |
| Rejection metrics | No | Belongs to Request Rejection Behaviour; this spec reads rejection counts |

---

## Problem Context

### What exists today

**ResourceConfig** at `src/engine/core/types.ts:214-219`:
```typescript
export interface ResourceConfig {
  cpu: number      // vCPUs
  memory: number   // in MB
  replicas: number
  maxReplicas?: number
}
```
This type is defined on `ComponentNode.resources` (optional) and validated by the validator's Zod schema. It is populated by the canvas serializer when the user configures node resources. However, the engine never reads `resources` — it only uses `queue`, `processing`, and `config`.

**SLOConfig.errorBudget** at `src/engine/core/types.ts:264`:
```typescript
export interface SLOConfig {
  latencyP99: number        // ms
  availabilityTarget: number // fraction 0–1
  errorBudget: number       // fraction 0–1
}
```
`errorBudget` is validated (Zod: `z.number().min(0).max(1)` at `validator.ts:279`) and present on all mock topology nodes (e.g., `orderProcessingTopology.ts` uses values like `0.001`, `0.005`, `0.0001`). But `detectSLOBreaches` at `output.ts:172-213` only checks `latencyP99` and `availabilityTarget` — `errorBudget` is never read.

**LegacySeedMetrics** at `src/engine/catalog/nodeSpecTypes.ts:79-98`:
Contains `vCPU` and `ram` fields used by `buildSeededSimulationConfig` to derive worker counts and capacity — but these values influence the simulation config, not cost output.

**buildSeededSimulationConfig** at `src/engine/catalog/componentSpecs.ts:95-140`:
Uses `vCPU` and `ram` to derive `workers` and `capacity`. The `memoryCapacityBoost` formula (`clamp(memoryGb / 8, 0.5, 8)`) scales capacity by memory. This is the closest the system gets to resource-aware computation, but it's config derivation, not cost calculation.

### What's missing

| Gap | Impact |
| --- | --- |
| `ResourceConfig` is never consumed at runtime | Users configure cpu/memory/replicas but get no cost output |
| `errorBudget` is validated but never checked | Error budget violations go undetected; SLO breaches only cover latency and availability |
| No cost model or pricing configuration | Cannot estimate hourly/monthly infrastructure cost |
| No per-request cost attribution | Cannot answer "what does a single request cost?" |
| No cost-vs-throughput analysis | Cannot find the optimal capacity point (cost per request at target throughput) |
| No error budget burn rate | Cannot answer "at this error rate, how fast are we consuming our budget?" |
| No cost section in `SimulationOutput` | All cost analysis would need to be done externally |

---

## Feature 1: Resource Cost Model

### Design

The resource cost model computes a per-node infrastructure cost estimate from the node's `ResourceConfig`, a pricing table, and the simulation duration. The model is intentionally simple — it calculates the cost of *provisioned* resources, not consumed resources, because cloud infrastructure bills for allocation, not utilization.

### Proposed types

```typescript
interface CostConfig {
  currency: string;           // e.g., 'USD'
  cpuCostPerHour: number;     // cost per vCPU per hour
  memoryCostPerGbHour: number; // cost per GB-hour
  networkCostPerGb: number;    // cost per GB transferred
  storageCostPerGbMonth: number; // cost per GB stored per month (future)
}

interface NodeCostEstimate {
  nodeId: string;
  nodeLabel: string;
  provisioned: {
    cpuCost: number;          // cpuCostPerHour × cpu × replicas × durationHours
    memoryCost: number;       // memoryCostPerGbHour × (memory/1024) × replicas × durationHours
    totalCost: number;        // cpuCost + memoryCost
  };
  perRequest: {
    costPerSuccessful: number;  // totalCost / postWarmupProcessed
    costPerRequest: number;     // totalCost / postWarmupArrived (includes failures)
  };
  networkCost: number;         // networkCostPerGb × totalBytesTransferred
}
```

### Calculation algorithm

For each node with `resources` defined:

```
durationHours = (simulationDuration - warmupDuration) / 3_600_000

cpuCost = costConfig.cpuCostPerHour × resources.cpu × resources.replicas × durationHours
memoryCost = costConfig.memoryCostPerGbHour × (resources.memory / 1024) × resources.replicas × durationHours
totalProvisionedCost = cpuCost + memoryCost

costPerSuccessful = totalProvisionedCost / max(1, postWarmupProcessed)
costPerRequest = totalProvisionedCost / max(1, postWarmupArrived)
```

**Replicas vs. workers:** `resources.replicas` represents infrastructure instances (VMs, containers). `queue.workers` represents concurrency within a single logical node. In the current model, `replicas` is metadata only — the engine doesn't simulate multiple replicas. The cost model treats `replicas` as a multiplier on provisioned resources. A future `ScalingConfig`-aware cost model would use `maxReplicas` to compute peak cost.

**Network cost:** Requires tracking total bytes transferred through each node. Currently, `Request.sizeBytes` exists on the request object but is never accumulated per-node. A per-node `totalBytesIn` and `totalBytesOut` accumulator would need to be added to `MetricsCollector`.

### Default pricing

```typescript
const DEFAULT_COST_CONFIG: CostConfig = {
  currency: 'USD',
  cpuCostPerHour: 0.048,        // ~AWS on-demand m5.xlarge equivalent
  memoryCostPerGbHour: 0.006,   // ~AWS on-demand memory pricing
  networkCostPerGb: 0.09,       // AWS cross-AZ / internet egress
  storageCostPerGbMonth: 0.023  // AWS S3 standard
};
```

These defaults are rough approximations. The spec deliberately avoids cloud-provider-specific pricing because the simulator is provider-agnostic. Users should be able to override `CostConfig` in `GlobalConfig`.

### Where it integrates

`CostConfig` should be an optional field on `GlobalConfig` at `types.ts:446-455`. If absent, cost analysis is skipped. If present, `generateSimulationOutput` computes `NodeCostEstimate` for each node that has `resources` defined.

---

## Feature 2: Per-Request Cost Attribution

### Design

Per-request cost attribution answers the question: "What does it cost to serve one successful request through this topology?" This requires tracing the *path* of a request through nodes and accumulating the cost of each node's resources proportional to the time the request spent there.

### Cost attribution model

Two attribution strategies are proposed:

**Strategy 1: Proportional allocation (recommended)**

Each node's total cost is divided equally among all requests that passed through it:

```
nodeContribution(request) = nodeTotalCost / postWarmupArrived
requestCost = Σ nodeContribution for each node in request.path
```

This is simple, requires no per-request tracking beyond the existing `request.path`, and produces stable estimates. It attributes cost by *presence*, not by *time spent*.

**Strategy 2: Time-weighted allocation**

Each node's cost is allocated proportional to the request's time in that node:

```
nodeContribution(request) = nodeTotalCost × (requestTimeInNode / totalNodeBusyTime)
requestCost = Σ nodeContribution for each node in request.path
```

This requires per-request span data (already captured in `request.spans`). It attributes more cost to requests with longer service times, which is more accurate but also more variable.

### Integration with request path

The `request.path` array (built by `appendNodeToPath` at `engine.ts:567-569`) records every node the request visited. Combined with `request.spans` (which record `arrivalTime`, `queueWait`, `serviceTime`, `departureTime` per node), there is sufficient data for both attribution strategies.

**Fan-out complication:** Async fan-out creates branch clones with independent paths. The cost of a fan-out request should be the sum of all branch costs, but currently branches are independent requests with no parent-child cost aggregation. A future `parentRequestId` field would enable fan-out cost roll-up.

### Proposed output

```typescript
interface TopologyCostSummary {
  totalProvisionedCost: number;
  totalNetworkCost: number;
  avgCostPerSuccessfulRequest: number;
  avgCostPerRequest: number;
  costByNode: Record<string, NodeCostEstimate>;
  costEfficiency: number;  // successful requests per dollar
}
```

---

## Feature 3: Error Budget Accounting

### Design

Error budget accounting consumes `SLOConfig.errorBudget` to answer: "Given a budget of N% errors over a time window, how much of that budget did this simulation consume?" The error budget is a reliability engineering concept — it defines the acceptable failure rate over a period (typically 30 days), and the simulation's error rate is extrapolated to see how fast it would burn the budget.

### Calculation

```
simulatedErrorRate = (postWarmupRejected + postWarmupTimedOut) / postWarmupArrived
budgetBurnRate = simulatedErrorRate / errorBudget
budgetBurnDuration = errorBudget / simulatedErrorRate  // how many simulation-durations until budget exhausted

// Extrapolation to 30-day window
effectiveDurationHours = (simulationDuration - warmupDuration) / 3_600_000
monthlyBurnFraction = simulatedErrorRate / errorBudget
budgetExhaustionDays = if simulatedErrorRate > 0 then errorBudget / simulatedErrorRate × effectiveDurationHours / 24 else Infinity
```

**Example:** A node with `errorBudget = 0.001` (0.1%) and simulated error rate of `0.005` (0.5%) has a burn rate of `5.0×`. At this rate, the 30-day budget would be exhausted in 6 days.

### Proposed types

```typescript
interface ErrorBudgetResult {
  nodeId: string;
  nodeLabel: string;
  errorBudget: number;          // from SLOConfig
  simulatedErrorRate: number;   // actual rate from simulation
  burnRate: number;             // simulatedErrorRate / errorBudget
  budgetExhausted: boolean;     // simulatedErrorRate > errorBudget
  burnSeverity: 'safe' | 'warning' | 'critical';
}
```

**Severity thresholds:**
- `safe`: burnRate ≤ 1.0 (within budget)
- `warning`: 1.0 < burnRate ≤ 3.0 (burning fast but recoverable)
- `critical`: burnRate > 3.0 (budget will be exhausted rapidly)

### Integration with SLO breaches

`detectSLOBreaches` at `output.ts:172-213` should be extended to check error budget:

```typescript
if (nodeMetrics.errorRate > slo.errorBudget) {
  breaches.push({
    nodeId,
    nodeLabel,
    metric: 'errorBudget',
    target: slo.errorBudget,
    actual: nodeMetrics.errorRate,
    severity: burnRate > 3.0 ? 'critical' : 'warning'
  });
}
```

This adds a third SLO dimension alongside latencyP99 and availability. The `SLOBreach.metric` field is already a string, so `'errorBudget'` fits without type changes.

### Relationship to availability

Error budget and availability are related but not redundant:
- **Availability** = 1 − errorRate. It measures *current* reliability.
- **Error budget** measures *budget consumption rate*. A node with 99.5% availability and 99.9% budget (0.1%) is burning budget at 5× — it's "available enough right now" but unsustainable over 30 days.

The error budget check catches sustainability problems that availability alone misses.

---

## Feature 4: Cost-Aware Analysis Output

### Design

Cost-aware analysis output adds a `cost` section to `SimulationOutput` that aggregates all cost and budget data into a single, queryable structure.

### Proposed SimulationOutput extension

```typescript
interface SimulationOutput {
  // ... existing fields ...
  cost: CostAnalysis | null;  // null when no CostConfig or no ResourceConfig on any node
}

interface CostAnalysis {
  config: CostConfig;
  topology: TopologyCostSummary;
  perNode: Record<string, NodeCostEstimate>;
  errorBudgets: ErrorBudgetResult[];
  recommendations: CostRecommendation[];
}

interface CostRecommendation {
  nodeId: string;
  nodeLabel: string;
  type: 'over-provisioned' | 'under-provisioned' | 'budget-critical';
  message: string;
  metric: string;
  currentValue: number;
  suggestedValue?: number;
}
```

### Recommendation engine

Simple heuristic-based recommendations:

**Over-provisioned:** `utilization < 0.3` and `errorRate < 0.01`. The node has spare capacity and low errors — it could run with fewer resources.

```
suggestedReplicas = max(1, ceil(resources.replicas × utilization / 0.7))
```

**Under-provisioned:** `postWarmupRejected / postWarmupArrived > 0.05` (more than 5% capacity rejections). The node is rejecting work due to capacity limits.

```
suggestedCapacity = ceil(capacity × 1.5)
// or: suggestedReplicas = ceil(replicas × 1.5)
```

**Budget-critical:** `burnRate > 3.0`. Error budget will be exhausted before the SLO window ends.

```
message = "Error budget burning at {burnRate}×; budget exhausted in ~{days} days"
```

### Where it integrates

`generateSimulationOutput` at `output.ts:130-170` constructs the full output object. The `cost` field is computed after `perNode` metrics are available, since cost calculations depend on throughput, rejection counts, and utilization data.

The computation is pure analysis — it reads from `MetricsCollector` and `TopologyJSON` config, produces a `CostAnalysis` object, and has no side effects on the simulation.

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | Relationship |
| --- | --- |
| **Throughput Calculation** | Cost per request depends on throughput; cost efficiency is requests per dollar |
| **Request Rejection Behaviour** | Capacity rejections signal under-provisioning; error rate rejections burn error budget |
| **Queue Depth Calculation** | Utilization data drives over/under-provisioning recommendations |
| **Edge Properties & Defaults** | Network cost requires tracking bytes transferred per edge |
| **Arrival, Departure & Request Lifecycle Semantics** | Request spans provide time-weighted cost attribution data |
| **Simulation Validation & Pattern Accuracy** | Conservation check must balance before cost attribution is meaningful |
| **Default-Driven Simplification Layer** | `CostConfig` defaults define the pricing model when none is specified |
| **Request Type Model** | Per-type cost attribution (e.g., "type A costs 3× type B") is a future extension |

---

## Integration Requirements

### Across features

| Integration point | Producer | Consumer | Contract |
| --- | --- | --- | --- |
| `ResourceConfig` | `ComponentNode.resources` | Cost model | `{ cpu, memory, replicas }` — may be absent |
| `SLOConfig.errorBudget` | `ComponentNode.slo` | Error budget accounting | Fraction 0–1; may be absent if no SLO |
| `postWarmupProcessed` | `MetricsCollector` | Cost per successful request | Denominator for per-request cost |
| `postWarmupRejected + postWarmupTimedOut` | `MetricsCollector` | Error budget burn rate | Numerator for error rate |
| `utilization` | `PerNodeMetrics` | Over-provisioning detection | Average utilization over post-warmup window |
| `request.path` | Engine | Per-request cost attribution | Ordered node sequence per request |
| `request.spans` | Engine | Time-weighted cost attribution | Per-node timing data |
| `CostConfig` | `GlobalConfig` (proposed) | All cost calculations | Pricing parameters; optional |

### Within this feature

| Component | Responsibility | Key invariant |
| --- | --- | --- |
| Cost model | Computes per-node provisioned cost | Cost is based on allocation, not utilization |
| Per-request attribution | Distributes node costs across requests | Sum of per-request costs ≈ total topology cost |
| Error budget accounting | Computes burn rate from error rate and budget | `burnRate = errorRate / errorBudget` |
| Recommendation engine | Generates actionable suggestions | Only recommends when signal is strong (not borderline) |

---

## Source-to-Feature Map

| Source file | Lines | Feature |
| --- | --- | --- |
| `src/engine/core/types.ts` | 214-219 | F1: `ResourceConfig` type (cpu, memory, replicas) |
| `src/engine/core/types.ts` | 261-265 | F3: `SLOConfig` with `errorBudget` |
| `src/engine/core/types.ts` | 291-307 | F1: `ComponentNode.resources` (optional) |
| `src/engine/core/types.ts` | 446-455 | F1: `GlobalConfig` (proposed `CostConfig` home) |
| `src/engine/validation/validator.ts` | 279 | F3: `errorBudget` Zod validation (min 0, max 1) |
| `src/engine/catalog/componentSpecs.ts` | 95-140 | F1: `buildSeededSimulationConfig` uses vCPU/ram for config derivation |
| `src/engine/catalog/nodeSpecTypes.ts` | 79-98 | F1: `LegacySeedMetrics.vCPU` and `.ram` |
| `src/engine/metrics.ts` | 311-395 | F2/F3: `getPerNodeMetrics` — throughput, errorRate, availability |
| `src/engine/analysis/output.ts` | 172-213 | F3/F4: `detectSLOBreaches` — extends with errorBudget |
| `src/engine/analysis/output.ts` | 130-170 | F4: `generateSimulationOutput` — adds `cost` section |
| `src/engine/__mocks__/orderProcessingTopology.ts` | various | F3: `errorBudget` values on mock nodes (0.001, 0.005, 0.0001) |

---

## Assumptions and Unresolved Questions

### Assumptions

1. **Cost is based on provisioned resources, not consumed.** Cloud providers bill for allocated CPU and memory, not for actual utilization. A node at 10% utilization costs the same as one at 90% if they have the same `ResourceConfig`. The recommendation engine identifies the mismatch, but the cost model reflects reality.

2. **Error budget is a rate comparison, not a cumulative counter.** The spec compares the simulation's error rate against the budget fraction, rather than tracking a running count of "errors remaining." This is appropriate for a single simulation run; cumulative tracking across simulation runs is out of scope.

3. **`ResourceConfig` is optional.** Many nodes won't have resources defined. Cost analysis is per-node where data exists; the topology summary only includes nodes with `ResourceConfig`. Nodes without resources don't appear in cost output.

4. **Network cost requires new per-node byte tracking.** Currently `request.sizeBytes` exists but is not accumulated anywhere. Adding `totalBytesIn` / `totalBytesOut` to `NodeInternalMetrics` is a prerequisite for network cost.

5. **Default pricing is illustrative.** The `DEFAULT_COST_CONFIG` values are order-of-magnitude correct for a major cloud provider but should not be treated as accurate pricing. Users in production should supply their own `CostConfig`.

### Unresolved questions

| # | Question | Why it matters |
| - | --- | --- |
| 1 | Should `CostConfig` be per-node or global? | Different nodes may use different instance types at different prices |
| 2 | Should `replicas` multiply cost linearly? | Spot instances, reserved pricing, and tiered discounts make linear scaling unrealistic |
| 3 | Should the cost model account for `ScalingConfig.maxReplicas`? | Auto-scaling means cost varies over time; peak vs. average cost is a meaningful distinction |
| 4 | Should error budget tracking be cumulative across simulation runs? | For release validation, a single run's burn rate is sufficient; for ongoing monitoring, cumulative tracking matters |
| 5 | Should per-request cost include edge/network cost? | Adds accuracy but requires byte-level tracking through every edge |
| 6 | Should the recommendation engine consider the relationship between capacity and rejection rate? | A node rejecting 10% of requests might cost less than one provisioned to handle all traffic — the optimizer should model this tradeoff |
| 7 | Where should `CostConfig` live in the UI? | Global settings panel vs. per-scenario configuration vs. environment-level default |

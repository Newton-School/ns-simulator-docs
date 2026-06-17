# Request Pattern Configuration

Technical feature specification defining how workload arrival patterns are configured, parameterized, and consumed by the simulation engine.

This spec consolidates the existing `WorkloadProfile` type, the `WorkloadGenerator` class, the 7 implemented arrival patterns, the request distribution model, and the canvas-level `SourceConfig` into a unified description of what request pattern configuration is, how it works internally, and what gaps remain. It exists because the arrival pattern is the single most influential input to any simulation run — it determines the rate, shape, and composition of traffic entering the topology — and downstream specs (throughput calculation, queue depth, rejection behaviour, lifecycle semantics) all assume a well-defined pattern contract. The Environment Definition & Configuration Model spec reserves a `requestPatternId` slot and a pattern override mechanism; this spec defines what those slots point to.

---

## Table of Contents

1. [Feature/Architecture Ideation](#featurearchitecture-ideation)
2. [Problem Context](#problem-context)
3. [Feature 1: Workload Pattern Selection and Parameterization](#feature-1-workload-pattern-selection-and-parameterization)
4. [Feature 2: Request Distribution and Type Composition](#feature-2-request-distribution-and-type-composition)
5. [Feature 3: Inter-Arrival Time Algorithms](#feature-3-inter-arrival-time-algorithms)
6. [Feature 4: Pattern Presets and Named Configurations](#feature-4-pattern-presets-and-named-configurations)
7. [Feature 5: Pattern Validation](#feature-5-pattern-validation)
8. [Relationship to Adjacent Feature Domains](#relationship-to-adjacent-feature-domains)
9. [Integration Requirements](#integration-requirements)
10. [Source-to-Feature Map](#source-to-feature-map)
11. [Assumptions and Unresolved Questions](#assumptions-and-unresolved-questions)

---

## Feature/Architecture Ideation

### Capability definition

Request Pattern Configuration is the subsystem that converts a declarative workload description (pattern shape, base rate, pattern-specific parameters, request type mix) into a stream of timed `request-generated` events that the simulation engine processes. It is the only traffic source in the simulator — no requests exist unless a pattern configuration produces them.

The capability covers three concerns: (1) selecting and parameterizing one of 7 arrival patterns, (2) composing the request type mix via a weighted distribution, and (3) translating the parameterized pattern into concrete inter-arrival times at runtime. It also covers the proposed extension of named pattern presets that the Environment Model can reference by id.

### Classification

| Classification            | Applies? | Why |
| ------------------------- | -------: | --- |
| Product feature           |      Yes | Users configure workload shape, rate, and request mix before running a simulation |
| Architectural change      |       No | The current `WorkloadProfile` → `WorkloadGenerator` pipeline is sound; this spec formalizes it, not replaces it |
| Domain model addition     |  Partial | Proposes `RequestPatternPreset` and `RequestPatternId` types for the preset system; existing types are already implemented |
| Validation layer          |      Yes | Proposes pattern-specific validation rules beyond what the current Zod schema checks |
| Refactor of existing code |  Partial | Proposes extracting hardcoded defaults (`DEFAULT_BURST_MULTIPLIER`, etc.) into the environment defaults model |

### Current pain without this model

| Pain | Who is affected | Technical cause | Consequence |
| ---- | --------------- | --------------- | ----------- |
| Pattern defaults are hardcoded constants | Engine developers | `src/engine/workload.ts:7-10` defines `DEFAULT_BURST_MULTIPLIER = 5`, `DEFAULT_BURST_DURATION_MS = 5_000`, `DEFAULT_NORMAL_DURATION_MS = 10_000`, `DEFAULT_RAMP_DURATION_MS = 10_000` as module-level constants. These are not configurable from the environment or UI. | Users cannot tune burst/sawtooth cycle timing without modifying source code; changing a default requires a code change in the workload module |
| No pattern presets | Users, product team | There is no concept of a named pattern configuration. Every workload must be specified from scratch with explicit `pattern`, `baseRps`, and pattern-specific sub-objects. | Users building common scenarios (e.g., "moderate web traffic", "flash sale spike") must manually configure every parameter each time |
| Pattern validation is schema-only | Engine developers | `validator.ts` validates `WorkloadProfile` via Zod schema (field types, required fields) but does not validate pattern-specific semantics: e.g., `spikeTime + spikeDuration > simulationDuration`, `hourlyMultipliers` containing negative values, `baseRps <= 0` with no spike override | Invalid pattern configurations pass validation and produce silent failures at runtime (infinite inter-arrival times, zero-traffic windows) |
| Request priority is hardcoded | Users | `workload.ts:164` assigns priority via `this.rng.boolean(0.1) ? 0 : 1` — 10% high priority, 90% normal. This ratio is not configurable. | Priority-sensitive simulations (priority queue disciplines, SLO tiers) cannot model different priority distributions |
| Canvas source config is disconnected from pattern model | Frontend developers | `SourceConfig` in `src/engine/catalog/nodeSpecTypes.ts:54-57` stores a `defaultWorkload: Omit<WorkloadProfile, 'sourceNodeId' | 'requestDistribution'>` per source node, but this is a canvas concern that the engine never sees directly — it is serialized into `TopologyJSON.workload` by `useTopologySerializer`. | No round-trip: if the engine normalizes or adjusts the pattern, there is no path to reflect that back to the canvas config |
| Single workload per topology | Users | `TopologyJSON.workload` is a single optional `WorkloadProfile`. There is no support for multiple concurrent workload sources. | Multi-source topologies (e.g., internal traffic + external traffic at different rates) require workarounds |

### Proposed responsibility boundary

| Responsibility | Owned by this spec? | Reason |
| --- | ---: | --- |
| Pattern shape enumeration (constant, poisson, bursty, diurnal, spike, sawtooth, replay) | Yes | These are the 7 implemented patterns; this spec defines their semantics |
| Pattern-specific parameters (burstRps, hourlyMultipliers, spikeTime, etc.) | Yes | These are the configuration knobs for each pattern |
| Inter-arrival time algorithm per pattern | Yes | The `nextInterArrivalMs` method is the core of the workload generator |
| Request type distribution and weighted selection | Yes | `requestDistribution` and `pickRequestDistributionEntry` are pattern concerns |
| Named pattern presets | Yes | This spec proposes the preset model referenced by the Environment Model's `requestPatternId` |
| Pattern preset assignment to nodes | No | Belongs to Environment Definition & Configuration Model (stores the `requestPatternId` slot) |
| Request priority model | Partial | This spec documents the current hardcoded priority and proposes making it configurable; the full priority queue semantics belong to Queue Depth Calculation |
| How arrival events enter the queue | No | Belongs to Arrival, Departure & Request Lifecycle Semantics |
| How throughput is calculated from arrival rate | No | Belongs to Throughput Calculation |
| Pattern accuracy regression testing | No | Belongs to Simulation Validation & Pattern Accuracy |

### Smallest useful v1

| v1 capability | Required? | Why |
| --- | ---: | --- |
| Formal documentation of 7 existing patterns | Yes | The patterns are implemented but undocumented; this spec is the single reference |
| Inter-arrival time algorithm specification | Yes | Downstream specs (throughput, queue depth) need to reference the exact algorithm |
| Request distribution semantics | Yes | Request type composition affects routing (conditional edges) and rejection (type-based SLOs) |
| Pattern validation rules | Yes | Prevents silent runtime failures from invalid pattern configurations |
| Named presets | Maybe | Useful for UX but not required for engine correctness; can be deferred if Environment Model v1 ships without preset references |
| Multi-workload support | Deferred | Requires `TopologyJSON` schema change; valuable but not blocking |
| Configurable priority distribution | Deferred | Current 10/90 split works for most scenarios; configurability can follow |

### Deferred capabilities

| Deferred capability | Later spec | Why deferred |
| --- | --- | --- |
| Multi-source concurrent workloads | Request Flow Direction & Topology Rules | Requires topology-level support for multiple entry points with independent workload configs |
| Pattern accuracy regression fixtures | Simulation Validation & Pattern Accuracy | This spec defines what patterns do; accuracy spec defines how to verify they match theory |
| Priority-aware queue interaction | Queue Depth Calculation | Priority affects dequeue order, not arrival pattern |
| Request type lifecycle effects | Request Type Model | Request types are composed here but their semantic effects (routing conditions, SLO tiers) belong to the type model |
| Environment-level pattern defaults | Environment Definition & Configuration Model | The environment model stores the default pattern assignment; this spec defines what patterns are available to assign |
| Progressive disclosure of pattern parameters | Default-Driven Simplification Layer | Hiding advanced parameters (hourlyMultipliers, burstDuration) is a UX concern |

---

## Problem Context

### What exists today

**WorkloadProfile type (`src/engine/core/types.ts:369-413`)**

The `WorkloadProfile` interface is the declarative pattern configuration:

```typescript
export interface WorkloadProfile {
  sourceNodeId: string
  pattern: 'constant' | 'poisson' | 'bursty' | 'diurnal' | 'spike' | 'sawtooth' | 'replay'
  baseRps: number
  diurnal?: {
    peakMultiplier: number
    hourlyMultipliers: DiurnalHourlyMultipliers  // 24-element tuple
  }
  spike?: {
    spikeTime: number       // ms from simulation start
    spikeRps: number
    spikeDuration: number   // ms
  }
  bursty?: {
    burstRps: number
    burstDuration: number   // ms
    normalDuration: number  // ms
  }
  sawtooth?: {
    peakRps: number
    rampDuration: number    // ms
  }
  requestDistribution: Array<{
    type: string
    weight: number
    sizeBytes: number
  }>
}
```

Key observations:
- `pattern` is a discriminated union literal, but the sub-objects (`diurnal`, `spike`, `bursty`, `sawtooth`) are all optional regardless of which pattern is selected. The type system does not enforce that `spike` is present when `pattern === 'spike'`.
- `requestDistribution` is required and non-empty. Weights are documented as summing to 1.0, but the runtime (`pickRequestDistributionEntry`) normalizes by total weight, so any positive weights work.
- `replay` pattern exists in the union but is treated identically to `constant` in the generator (`workload.ts:83-84`). No replay-specific data source is implemented.

**WorkloadGenerator class (`src/engine/workload.ts`)**

The generator is constructed with a `WorkloadProfile`, a seeded `RandomGenerator`, and an `EventScheduler`. It:
1. Receives `initialize(startTime)` call from the engine constructor (`engine.ts:103`).
2. Schedules a `request-generated` event at `startTime`.
3. On each `generateNext(currentTime)` call, creates a `Request` object and schedules the next `request-generated` event based on the inter-arrival time for the current pattern.
4. Stops scheduling when `timestamp >= startTime + simulationDurationUs`.

The generator owns 5 hardcoded defaults:
- `DEFAULT_TIMEOUT_MS = 30_000` (used as request deadline if no global timeout)
- `DEFAULT_BURST_MULTIPLIER = 5` (burstRps fallback = baseRps * 5)
- `DEFAULT_BURST_DURATION_MS = 5_000`
- `DEFAULT_NORMAL_DURATION_MS = 10_000`
- `DEFAULT_RAMP_DURATION_MS = 10_000`

**Canvas-level source configuration (`src/engine/catalog/nodeSpecTypes.ts:54-57`)**

```typescript
export interface SourceConfig {
  requestDistribution: WorkloadProfile['requestDistribution']
  defaultWorkload: Omit<WorkloadProfile, 'sourceNodeId' | 'requestDistribution'>
}
```

This is stored on `CanvasNodeDataV2.source` for nodes with `structuralRole === 'source'`. It provides the per-source-node default pattern and request mix that `useTopologySerializer` combines with `ScenarioState.workloadOverride` to produce the final `TopologyJSON.workload`.

**Scenario-level workload override (`src/renderer/src/types/ui.ts:61`)**

```typescript
workloadOverride?: Partial<Omit<WorkloadProfile, 'sourceNodeId' | 'requestDistribution'>>
```

This lets the scenario panel override pattern-level fields (e.g., change `baseRps` or `pattern` at run time) without modifying the canvas source node's default workload. The merge happens during topology serialization.

**Engine consumption (`src/engine/engine.ts:98-104`)**

```typescript
if (topology.workload) {
  this.workload = new WorkloadGenerator(topology.workload, rng, scheduler, {
    defaultTimeoutMs: topology.global.defaultTimeout,
    simulationDurationMs: topology.global.simulationDuration
  })
  this.workload.initialize(0n)
}
```

The engine creates exactly one `WorkloadGenerator` from `topology.workload`. If `workload` is undefined, no traffic is generated — the simulation runs with zero requests.

**Stochastic foundation (`src/engine/stochastic/distribution.ts`)**

The `Distributions` class provides 14 distribution samplers. The workload generator uses one directly: `exponential(lambda)` for the Poisson pattern's inter-arrival times (`workload.ts:213-214`). All other patterns use deterministic interval calculation via `intervalForRps(rps)` = `1000 / rps`.

### What's missing

| Gap | Impact | Technical cause |
| --- | --- | --- |
| No discriminated union enforcement for pattern sub-objects | Pattern-specific fields can be absent when they should be required (e.g., `pattern: 'spike'` with no `spike` object) | `WorkloadProfile` uses optional fields instead of a tagged discriminated union |
| No pattern-level validation beyond Zod schema | Invalid configurations (negative multipliers, spike that exceeds simulation duration, zero baseRps with no spike) pass validation | `validator.ts` treats `WorkloadProfile` as a flat schema; no pattern-specific semantic checks |
| No named pattern presets | Users must configure every pattern from scratch; environment model cannot reference patterns by id | No preset registry or pattern id concept exists |
| No multi-workload support | Single traffic source per simulation run | `TopologyJSON.workload` is singular |
| Hardcoded priority distribution | Cannot model priority-sensitive scenarios | 10/90 split in `createRequest` is not configurable |
| `replay` pattern is a no-op | Pattern union includes `replay` but it behaves identically to `constant` | No replay data source or trace-replay mechanism is implemented |
| Pattern defaults are module constants, not environment config | Burst/sawtooth cycle parameters cannot be tuned without code changes | Constants in `workload.ts:7-10` are not exposed through any configuration path |

### What the source material explores

The product discussions and the Environment Definition & Configuration Model spec identify request pattern configuration as one of the twelve foundational feature domains. The environment spec reserves a `requestPatternId` slot on `EnvironmentDefaults` and `EnvironmentNodeConfig` for referencing named patterns, and proposes that pattern-specific parameters be the responsibility of this spec. The system mind map positions workload generation as the leftmost entry point in the simulation flow: `WorkloadGenerator` → `request-generated` event → arrival at source node → queue processing → routing → completion/rejection/timeout.

---

## Feature 1: Workload Pattern Selection and Parameterization

### What it does

Provides 7 distinct arrival patterns that control the rate at which `request-generated` events are scheduled into the simulation event queue. Each pattern maps a base request rate (`baseRps`) plus pattern-specific parameters to a time-varying function that produces inter-arrival intervals.

### Why it exists

The arrival pattern is the fundamental input to every queuing calculation. A constant-rate arrival produces steady-state behaviour where Little's Law applies directly. A Poisson arrival introduces stochastic variation that tests queue absorption. A bursty or spike arrival stresses capacity limits and triggers rejection/timeout cascades. Without configurable patterns, the simulator can only model constant load — useless for capacity planning, failure analysis, or SLO validation.

### How it works internally

**Data source**: `WorkloadProfile.pattern` (discriminant) + `WorkloadProfile.baseRps` + pattern-specific sub-objects. Defined in `src/engine/core/types.ts:369-413`.

**Pattern semantics**:

| Pattern | Inter-arrival behaviour | Parameters | Stochastic? |
| --- | --- | --- | --- |
| `constant` | Fixed interval: `1000 / baseRps` ms | `baseRps` only | No — deterministic |
| `poisson` | Exponentially distributed: `-ln(1-U) / (baseRps/1000)` where U ~ Uniform(0,1) | `baseRps` only | Yes — memoryless |
| `bursty` | Alternates between burst and normal phases on a fixed cycle | `baseRps`, `burstRps`, `burstDuration`, `normalDuration` | No — deterministic phase switching |
| `diurnal` | Scales baseRps by an hourly multiplier array over a 24-hour cycle mapped to simulation duration | `baseRps`, `hourlyMultipliers[24]`, `peakMultiplier` | No — deterministic |
| `spike` | Fixed interval at `baseRps` except during a defined window where rate jumps to `spikeRps` | `baseRps`, `spikeTime`, `spikeRps`, `spikeDuration` | No — deterministic |
| `sawtooth` | Linear ramp from `baseRps` to `peakRps` over `rampDuration`, then reset | `baseRps`, `peakRps`, `rampDuration` | No — deterministic |
| `replay` | Currently identical to `constant` — reserved for future trace replay | `baseRps` only | No — placeholder |

**Processing logic — `nextInterArrivalMs(currentTime)` in `src/engine/workload.ts:78-153`**:

The method switches on `this.config.pattern` and returns a millisecond interval:

1. **`constant` / `replay`**: Returns `1000 / baseRps`. Same request every `1/baseRps` seconds.

2. **`poisson`**: Calls `this.distributions.exponential(baseRps / 1000)` which returns `-ln(1-U) / lambda` where `lambda = baseRps / 1000` (rate per ms). This produces memoryless inter-arrival times with mean `1000 / baseRps` ms.

3. **`bursty`**: Computes `elapsedMs % cycleDuration` where `cycleDuration = burstDuration + normalDuration`. If in burst phase (`< burstDuration`), uses `burstRps`; otherwise uses `baseRps`. Falls back to `baseRps * DEFAULT_BURST_MULTIPLIER` if `burstRps` not provided, and `DEFAULT_BURST_DURATION_MS`/`DEFAULT_NORMAL_DURATION_MS` for missing durations.

4. **`diurnal`**: Maps simulation progress to a 24-hour cycle. If `simulationDurationUs` is known, computes `progress = (elapsedMs % durationMs) / durationMs`, then `hour = floor(progress * 24)`. Looks up `hourlyMultipliers[hour]` (default 1) and returns `1000 / (baseRps * multiplier)`.

5. **`spike`**: Checks if `elapsedMs` falls within `[spikeTime, spikeTime + spikeDuration)`. If yes, uses `spikeRps`; otherwise uses `baseRps`.

6. **`sawtooth`**: Computes `t = (elapsedMs % rampDuration) / rampDuration` (linear phase 0→1), then `currentRps = baseRps + (peakRps - baseRps) * t`. Returns `1000 / currentRps`.

**Scheduling flow**:

```
WorkloadGenerator.initialize(0n)
  └─ scheduleRequestGeneratedAt(0n)
       └─ scheduler.schedule(createEvent('request-generated', sourceNodeId, '', {}, 0n))

Engine.handleRequestGenerated(event)
  └─ workload.generateNext(currentTime)
       ├─ createRequest(currentTime) → Request object
       └─ scheduleNext(currentTime)
            └─ nextInterArrivalMs(currentTime) → interval
                 └─ scheduleRequestGeneratedAt(currentTime + interval)
```

Each `request-generated` event triggers the engine to call `generateNext`, which both creates the current request and schedules the next `request-generated` event. The chain terminates when the next timestamp would exceed `startTime + simulationDurationUs`.

**Default fallbacks in the current code**:

| Default | Value | Used when | Defined at |
| --- | --- | --- | --- |
| `DEFAULT_TIMEOUT_MS` | 30,000 ms | `options.defaultTimeoutMs` not provided | `workload.ts:7` |
| `DEFAULT_BURST_MULTIPLIER` | 5 | `bursty.burstRps` not specified | `workload.ts:8` |
| `DEFAULT_BURST_DURATION_MS` | 5,000 ms | `bursty.burstDuration` not specified | `workload.ts:9` |
| `DEFAULT_NORMAL_DURATION_MS` | 10,000 ms | `bursty.normalDuration` not specified | `workload.ts:10` |
| `DEFAULT_RAMP_DURATION_MS` | 10,000 ms | `sawtooth.rampDuration` is 0 or missing | `workload.ts:10` |
| Priority split | 10% high (0), 90% normal (1) | Always — not configurable | `workload.ts:164` |

### What components it requires

- **Engine-side**: No changes needed for existing patterns. For the proposed discriminated union and environment integration, `WorkloadProfile` type needs restructuring (see Feature 4).
- **Shared layer**: Pattern-specific default constants should migrate from `workload.ts` module scope to the Environment Model's `EnvironmentDefaults.requestPattern` when the environment spec is implemented.
- **Renderer/frontend-side**: `SourceConfig.defaultWorkload` and `ScenarioState.workloadOverride` already provide the pattern configuration UI contract. No renderer changes needed for existing patterns.

### Explored in

Environment Definition & Configuration Model spec (responsibility boundary table, deferred capabilities), system mind map (workload generation subgraph), `src/engine/workload.ts` (full implementation), `src/engine/core/types.ts:369-413` (type definition).

---

## Feature 2: Request Distribution and Type Composition

### What it does

Defines the mix of request types that the workload generator produces. Each generated request receives a `type` string, a `sizeBytes` value, and a `priority` level selected from a weighted distribution. This composition determines the request diversity entering the topology and affects downstream routing (conditional edges match on `request.type`) and metrics (per-type throughput, per-type rejection).

### Why it exists

Real systems serve heterogeneous traffic. An API gateway handles GET reads (small, fast), POST writes (medium, slower), and file uploads (large, slowest). A messaging system processes standard messages and priority alerts. Without type composition, the simulator treats all requests identically, which masks the most common capacity planning failure mode: a minority traffic type consuming disproportionate resources.

### How it works internally

**Data source**: `WorkloadProfile.requestDistribution` — a required, non-empty array of `{ type: string; weight: number; sizeBytes: number }` entries. Defined in `src/engine/core/types.ts:404-412`.

**Selection algorithm — `pickRequestDistributionEntry()` in `src/engine/workload.ts:173-195`**:

```
1. Sum all entry weights → totalWeight
2. Generate uniform random: target = rng.next() * totalWeight
3. Walk entries, accumulating weight:
   for each entry:
     cumulative += entry.weight
     if target < cumulative → return this entry
4. Fallback: return last entry (guards floating-point edge case)
```

This is a standard weighted random selection. It does not require weights to sum to 1.0 — the algorithm normalizes by `totalWeight`. However, the JSDoc on `WorkloadProfile.requestDistribution[].weight` states weights are "expected to sum to 1.0", creating a documentation/implementation mismatch.

**Request creation — `createRequest(currentTime)` in `src/engine/workload.ts:155-171`**:

```typescript
const requestType = this.pickRequestDistributionEntry()
const requestId = `req-${String(++this.requestCounter).padStart(6, '0')}`

return {
  id: requestId,
  type: requestType.type,
  sizeBytes: requestType.sizeBytes,
  priority: this.rng.boolean(0.1) ? 0 : 1,
  createdAt: currentTime,
  deadline: currentTime + msToMicro(this.defaultTimeoutMs),
  path: [],
  spans: [],
  retryCount: 0,
  metadata: {}
}
```

Key properties assigned:
- `id`: Sequential counter with zero-padding (`req-000001`, `req-000002`, ...).
- `type`: From the selected distribution entry.
- `sizeBytes`: From the selected distribution entry. Used by edge transfer logic for bandwidth calculations.
- `priority`: Hardcoded 10% probability of high priority (0), 90% normal (1). Lower numeric value = higher priority.
- `deadline`: `currentTime + defaultTimeoutMs` converted to microseconds. The `defaultTimeoutMs` comes from `topology.global.defaultTimeout` passed via `WorkloadGeneratorOptions`.
- `retryCount`: Always 0 at creation. Incremented by the engine's retry logic (if resilience config is present).

**Integration with conditional routing**:

`request.type` is the key field consumed by conditional edges. In `src/engine/routing.ts`, `matchesCondition()` evaluates expressions like `request.type === "api-read"` against the request object. The type string assigned here is the one matched there. This makes `requestDistribution` entries the authoritative source for what type strings exist in a simulation run.

**Canvas-level source of truth**:

`SourceConfig.requestDistribution` (in `CanvasNodeDataV2.source`) stores the per-source-node request mix. This is the value the user configures on the canvas. During serialization, `useTopologySerializer` copies it into `TopologyJSON.workload.requestDistribution`. The scenario panel does not currently override `requestDistribution` — `ScenarioState.workloadOverride` excludes it via `Omit<WorkloadProfile, 'sourceNodeId' | 'requestDistribution'>`.

### What components it requires

- **Engine-side**: The distribution selection algorithm in `workload.ts:173-195` is complete and correct. No changes needed for current functionality.
- **Shared layer**: The proposed `RequestPatternPreset` (Feature 4) should include `requestDistribution` so that presets capture the full workload shape including type mix.
- **Renderer/frontend-side**: Source node configuration panels already expose `requestDistribution` editing. No changes needed.

### Explored in

`src/engine/workload.ts:155-195` (request creation and type selection), `src/engine/core/events.ts` (Request interface), `src/engine/routing.ts` (conditional routing consumes `request.type`), `src/engine/catalog/nodeSpecTypes.ts:54-57` (SourceConfig).

---

## Feature 3: Inter-Arrival Time Algorithms

### What it does

Specifies the exact mathematical algorithm each pattern uses to compute the time gap between consecutive `request-generated` events. This is the translation layer between the declarative pattern description ("bursty at 500 rps with 2-second bursts") and the event-level scheduling ("next request in 2.0 ms" or "next request in 6.67 ms").

### Why it exists

Downstream specs need to reason about arrival rates as mathematical functions. The Throughput Calculation spec needs to know the effective arrival rate λ(t) to predict steady-state throughput. The Queue Depth Calculation spec needs to know whether arrivals are deterministic (D/G/c/K) or stochastic (M/G/c/K) to select the right queuing formula. The Simulation Validation & Pattern Accuracy spec needs to verify that the generator's empirical arrival rate matches the declared pattern within statistical tolerance. Without formal algorithm definitions, these specs cannot ground their calculations.

### How it works internally

**Algorithm per pattern**:

#### Constant / Replay

```
interArrivalMs = 1000 / baseRps
```

Deterministic. Produces exactly `baseRps` requests per second, uniformly spaced. In queuing notation, this is a **D** (deterministic) arrival process. The interval is constant across the entire simulation.

#### Poisson

```
lambda = baseRps / 1000          // rate per millisecond
U ~ Uniform(0, 1)                // from seeded RNG
interArrivalMs = -ln(1 - U) / lambda
```

Stochastic. Produces an exponentially distributed inter-arrival time with mean `1000 / baseRps` ms. This is the standard **M** (Markovian/memoryless) arrival process. The `1 - U` form (instead of `ln(U)`) avoids the undefined `ln(0)` when `U = 0`. Implementation: `this.distributions.exponential(lambdaPerMs)` which calls `-Math.log(1 - this.rng.next()) / lambda` in `src/engine/stochastic/distribution.ts:31`.

#### Bursty

```
burstRps = config.bursty.burstRps  ?? baseRps * 5      // DEFAULT_BURST_MULTIPLIER
burstDur = config.bursty.burstDuration ?? 5000          // DEFAULT_BURST_DURATION_MS
normDur  = config.bursty.normalDuration ?? 10000         // DEFAULT_NORMAL_DURATION_MS
cycleDur = burstDur + normDur

elapsed  = currentTime - startTime                       // in ms
phase    = elapsed % cycleDur

if phase < burstDur:
    interArrivalMs = 1000 / burstRps                     // burst phase
else:
    interArrivalMs = 1000 / baseRps                      // normal phase
```

Deterministic within each phase. Produces a square wave pattern alternating between high and low rates. Cycle repeats indefinitely. The transition is instantaneous — no ramp-up or ramp-down between phases.

#### Diurnal

```
if simulationDuration is known:
    progress = (elapsedMs % simulationDurationMs) / simulationDurationMs
    hour = floor(progress * 24)                          // maps full sim to 24 hours
else:
    hour = floor((elapsedMs % 86_400_000) / 3_600_000)   // real-time hours

multiplier = hourlyMultipliers[hour] ?? 1
interArrivalMs = 1000 / (baseRps * multiplier)
```

Deterministic, step-function. Each "hour" (1/24th of the simulation duration) uses a different multiplier. The pattern maps the simulation duration to a 24-hour day, regardless of actual duration — a 60-second simulation has 2.5-second "hours". If `hourlyMultipliers` is not provided, falls back to constant rate.

The `peakMultiplier` field on `diurnal` is declared in the type but not used by the generator — only `hourlyMultipliers` is consumed. This is a dead field.

#### Spike

```
if elapsedMs >= spikeTime AND elapsedMs < spikeTime + spikeDuration:
    interArrivalMs = 1000 / spikeRps                     // in spike window
else:
    interArrivalMs = 1000 / baseRps                      // normal rate
```

Deterministic. A single rectangular pulse. Unlike bursty, the spike does not repeat — it fires once at the specified offset. If `spike` config is missing, falls back to constant rate.

#### Sawtooth

```
rampDur = config.sawtooth.rampDuration > 0
            ? config.sawtooth.rampDuration
            : 10000                                       // DEFAULT_RAMP_DURATION_MS

t = (elapsedMs % rampDur) / rampDur                      // linear phase [0, 1)
currentRps = baseRps + (peakRps - baseRps) * t
interArrivalMs = 1000 / currentRps
```

Deterministic, linearly ramping. Rate increases from `baseRps` to `peakRps` over `rampDuration`, then resets instantly to `baseRps` and ramps again. The ramp is strictly linear — `t` maps directly to the interpolation factor.

**Scheduling guard — `scheduleNext()` in `src/engine/workload.ts:55-63`**:

```typescript
const interArrivalMs = this.nextInterArrivalMs(currentTime)
if (!Number.isFinite(interArrivalMs) || interArrivalMs < 0) {
  return  // stops the chain — no more requests
}
const interArrivalUs = BigInt(Math.max(1, Math.round(interArrivalMs * 1000)))
```

Safety bounds: if the interval is `Infinity` (from `baseRps <= 0`), `NaN`, or negative, the generator stops producing events. The minimum inter-arrival is 1 microsecond (`Math.max(1, ...)`), preventing zero-interval infinite loops.

**Duration guard — `scheduleRequestGeneratedAt()` in `src/engine/workload.ts:65-76`**:

```typescript
if (this.simulationDurationUs !== null) {
  const endExclusive = this.startTime + this.simulationDurationUs
  if (timestamp >= endExclusive) {
    return  // don't schedule past simulation end
  }
}
```

Ensures no `request-generated` events are scheduled beyond the simulation duration.

### What components it requires

- **Engine-side**: All algorithms are implemented. No changes for current functionality.
- **Shared layer**: Algorithm constants should be documented in the Environment Model as defaults that can be overridden.
- **Renderer/frontend-side**: No impact — algorithms are engine-internal.

### Explored in

`src/engine/workload.ts:78-153` (all pattern algorithms), `src/engine/stochastic/distribution.ts:26-31` (exponential sampler for Poisson), `src/engine/core/types.ts:369-413` (parameter types).

---

## Feature 4: Pattern Presets and Named Configurations

### What it does

Proposes a named preset system where common workload configurations can be defined once and referenced by id. The Environment Model's `requestPatternId` slot (defined in the Environment Definition & Configuration Model spec) would resolve to one of these presets. Users could select "flash-sale-spike" or "steady-web-traffic" instead of manually configuring pattern parameters.

### Why it exists

The current configuration surface requires users to understand all 7 patterns and their parameters to set up a workload. For common scenarios — moderate web traffic, periodic batch processing, flash sale events — the parameters are well-known and should be available as one-click presets. This also enables the Default-Driven Simplification Layer to offer progressive disclosure: show preset names first, reveal parameters only when users want to customize.

### How it works internally

**Proposed types**:

```typescript
/** Unique identifier for a pattern preset. */
export type RequestPatternId = string

/**
 * A named, reusable workload configuration.
 * Stored in the pattern preset registry and referenced by id
 * from EnvironmentDefaults.requestPatternId or
 * EnvironmentNodeConfig.requestPatternId.
 */
export interface RequestPatternPreset {
  /** Unique identifier, e.g., 'steady-web-traffic', 'flash-sale-spike'. */
  id: RequestPatternId

  /** Human-readable name shown in the UI preset picker. */
  name: string

  /** One-line description of the scenario this preset models. */
  description: string

  /** The full workload profile minus sourceNodeId (assigned at topology level). */
  workload: Omit<WorkloadProfile, 'sourceNodeId'>

  /** Whether this is a built-in preset (not user-deletable). */
  builtIn: boolean
}
```

These types would live in a new file `src/engine/core/patternPresets.ts` or alongside `WorkloadProfile` in `src/engine/core/types.ts`.

**Proposed built-in presets**:

| Preset id | Pattern | baseRps | Key parameters | Scenario |
| --- | --- | --- | --- | --- |
| `steady-web-traffic` | `constant` | 100 | — | Baseline web application under normal load |
| `api-moderate` | `poisson` | 200 | — | API with natural arrival variation |
| `flash-sale-spike` | `spike` | 50 | spikeTime: 10000, spikeRps: 2000, spikeDuration: 5000 | E-commerce flash sale at 10s mark |
| `business-hours` | `diurnal` | 100 | hourlyMultipliers: low overnight, peak at hours 9-17 | Office-hours traffic pattern |
| `microservice-bursty` | `bursty` | 150 | burstRps: 750, burstDuration: 3000, normalDuration: 7000 | Bursty inter-service communication |
| `load-test-ramp` | `sawtooth` | 10 | peakRps: 500, rampDuration: 30000 | Gradual load test ramp-up |

Each preset includes a `requestDistribution` with sensible defaults (e.g., `steady-web-traffic` might use `[{ type: 'GET', weight: 0.7, sizeBytes: 256 }, { type: 'POST', weight: 0.3, sizeBytes: 1024 }]`).

**Resolution flow**:

```
Environment config declares: requestPatternId = 'flash-sale-spike'
                                    │
                                    ▼
           PresetRegistry.resolve(id) → RequestPatternPreset
                                    │
                                    ▼
         Merge preset.workload with node-level overrides
                                    │
                                    ▼
              Final WorkloadProfile → WorkloadGenerator
```

The preset registry would be a simple `Map<RequestPatternId, RequestPatternPreset>` initialized with built-in presets at startup. Custom presets could be added via the UI (stored alongside topology persistence) or via the environment config.

**Integration with Environment Model**:

The Environment Definition & Configuration Model spec defines `EnvironmentDefaults.requestPatternId` as the global default pattern and `EnvironmentNodeConfig.requestPatternId` as a per-node override. The resolution order:

1. Per-node `requestPatternId` → specific preset
2. Global `requestPatternId` → default preset
3. Fallback → `constant` at `baseRps: 100` with single `{ type: 'default', weight: 1, sizeBytes: 512 }` distribution

### What components it requires

- **Engine-side**: New `RequestPatternPreset` type, preset registry, resolution function. ~100 lines of new code.
- **Shared layer**: Preset definitions shared between engine and renderer.
- **Renderer/frontend-side**: Preset picker UI in source node configuration panel and scenario panel. Depends on preset data being importable.

### Explored in

Environment Definition & Configuration Model spec (requestPatternId slots, deferred capabilities table), system mind map (environment model subgraph, workload generation node).

---

## Feature 5: Pattern Validation

### What it does

Defines semantic validation rules for workload pattern configurations that go beyond schema-level type checking. These rules catch configurations that are structurally valid (pass Zod parsing) but semantically broken (will produce degenerate simulation behaviour).

### Why it exists

The current validator (`src/engine/validation/validator.ts`) validates `WorkloadProfile` at the schema level: field types, required fields, enum values. It does not validate pattern-specific constraints. This means configurations like `pattern: 'spike'` with no `spike` object, or `baseRps: 0` with no spike to compensate, or `hourlyMultipliers` with all-zero values, pass validation and produce simulations with zero traffic, infinite inter-arrival times, or misleading results.

### How it works internally

**Proposed validation rules**:

| Rule | Condition | Severity | Diagnostic code |
| --- | --- | --- | --- |
| Base rate positive | `baseRps > 0` | Error | `PATTERN_BASE_RPS_ZERO` |
| Pattern params present | When `pattern === 'spike'`, `spike` object must exist (and similarly for `bursty`, `diurnal`, `sawtooth`) | Error | `PATTERN_PARAMS_MISSING` |
| Spike within simulation window | `spikeTime + spikeDuration <= simulationDuration` | Warning | `PATTERN_SPIKE_EXCEEDS_DURATION` |
| Spike rate positive | `spike.spikeRps > 0` | Error | `PATTERN_SPIKE_RPS_ZERO` |
| Burst rate exceeds base | `bursty.burstRps >= baseRps` | Warning | `PATTERN_BURST_BELOW_BASE` |
| Burst durations positive | `burstDuration > 0 && normalDuration > 0` | Error | `PATTERN_BURST_DURATION_ZERO` |
| Diurnal multipliers non-negative | All 24 `hourlyMultipliers` values >= 0 | Error | `PATTERN_DIURNAL_NEGATIVE_MULTIPLIER` |
| Diurnal not all-zero | At least one `hourlyMultipliers` value > 0 | Error | `PATTERN_DIURNAL_ALL_ZERO` |
| Sawtooth peak exceeds base | `sawtooth.peakRps >= baseRps` | Warning | `PATTERN_SAWTOOTH_PEAK_BELOW_BASE` |
| Sawtooth ramp positive | `sawtooth.rampDuration > 0` | Warning | `PATTERN_SAWTOOTH_RAMP_ZERO` |
| Distribution non-empty | `requestDistribution.length > 0` | Error | `PATTERN_DISTRIBUTION_EMPTY` |
| Distribution weights positive | All weights > 0 | Error | `PATTERN_DISTRIBUTION_ZERO_WEIGHT` |
| Distribution total weight positive | Sum of all weights > 0 | Error | `PATTERN_DISTRIBUTION_TOTAL_ZERO` |
| Replay pattern unsupported | `pattern === 'replay'` should produce a warning until replay is implemented | Warning | `PATTERN_REPLAY_NOT_IMPLEMENTED` |

**Proposed type for pattern diagnostics**:

```typescript
export interface PatternDiagnostic {
  code: string
  severity: 'error' | 'warning'
  message: string
  path: string  // JSON path within WorkloadProfile, e.g., 'spike.spikeRps'
}

export interface PatternValidationResult {
  valid: boolean
  diagnostics: PatternDiagnostic[]
}
```

**Where it would live**: A new `validateWorkloadPattern(profile: WorkloadProfile, simulationDuration: number): PatternValidationResult` function, either in `src/engine/validation/validator.ts` (alongside existing validation) or in a dedicated `src/engine/validation/patternValidator.ts`. It would be called from `validateTopology` after schema parsing succeeds, using the parsed `WorkloadProfile` and `GlobalConfig.simulationDuration`.

**Proposed discriminated union for stricter typing**:

To enforce pattern-param presence at the type level, `WorkloadProfile` could be restructured as:

```typescript
interface WorkloadProfileBase {
  sourceNodeId: string
  baseRps: number
  requestDistribution: Array<{ type: string; weight: number; sizeBytes: number }>
}

export type WorkloadProfile =
  | (WorkloadProfileBase & { pattern: 'constant' })
  | (WorkloadProfileBase & { pattern: 'poisson' })
  | (WorkloadProfileBase & { pattern: 'replay' })
  | (WorkloadProfileBase & {
      pattern: 'bursty'
      bursty?: { burstRps: number; burstDuration: number; normalDuration: number }
    })
  | (WorkloadProfileBase & {
      pattern: 'diurnal'
      diurnal?: { peakMultiplier: number; hourlyMultipliers: DiurnalHourlyMultipliers }
    })
  | (WorkloadProfileBase & {
      pattern: 'spike'
      spike: { spikeTime: number; spikeRps: number; spikeDuration: number }
    })
  | (WorkloadProfileBase & {
      pattern: 'sawtooth'
      sawtooth: { peakRps: number; rampDuration: number }
    })
```

This makes `spike` required when `pattern === 'spike'` and `sawtooth` required when `pattern === 'sawtooth'`, while keeping `bursty` and `diurnal` optional (since the generator has fallback defaults for those).

### What components it requires

- **Engine-side**: New validation function (~80 lines), diagnostic types (~20 lines). Optional: `WorkloadProfile` discriminated union refactor (~40 lines type change, ~20 lines Zod schema update).
- **Shared layer**: `PatternDiagnostic` and `PatternValidationResult` types shared between engine validation and renderer error display.
- **Renderer/frontend-side**: Display pattern validation diagnostics in the scenario panel or source node config panel, alongside existing validation errors.

### Explored in

`src/engine/validation/validator.ts` (current validation), Environment Definition & Configuration Model spec (validation and constraints section), system mind map (validation layer node).

---

## Relationship to Adjacent Feature Domains

| Adjacent spec | What this spec provides | What this spec consumes | Shared data |
| --- | --- | --- | --- |
| **Environment Definition & Configuration Model** | Pattern preset definitions, pattern validation rules | `requestPatternId` slot, pattern defaults from environment | `WorkloadProfile`, `RequestPatternId` |
| **Request Flow Direction & Topology Rules** | Request type strings (from `requestDistribution`) that conditional edges match on | Edge mode and routing strategy that determine how generated requests traverse the topology | `request.type`, `EdgeDefinition.condition` |
| **Request Type Model** | Request type strings and `sizeBytes` values as the creation point for typed requests | Type-level properties (SLO tiers, processing weight) that are not yet part of the distribution model | `requestDistribution[].type` |
| **Edge Properties & Defaults** | Request `sizeBytes` that edge bandwidth calculations consume | Edge latency distribution that affects end-to-end timing | `Request.sizeBytes`, `EdgeDefinition.bandwidth` |
| **Throughput Calculation** | Effective arrival rate λ(t) derived from pattern parameters | — (throughput is a derived metric, not an input to patterns) | `baseRps`, pattern shape → λ(t) |
| **Queue Depth Calculation** | Arrival process classification (deterministic D vs stochastic M) per pattern | Queue capacity and discipline that determine whether arrivals queue or reject | Arrival process type, `QueueConfig.capacity` |
| **Arrival, Departure & Request Lifecycle Semantics** | The `request-generated` event that starts each request's lifecycle | Event type definitions and the lifecycle state machine | `request-generated` event, `Request` interface |
| **Request Rejection Behaviour** | Arrival rate that drives queue saturation and triggers rejection | Rejection reasons and metrics fed back to analysis | `baseRps` → arrival pressure, `request-rejected` events |
| **Cost Calculation & Budgeting** | Total request volume derived from pattern parameters and simulation duration | — (cost is a derived metric) | `baseRps * simulationDuration` → total expected requests |
| **Simulation Validation & Pattern Accuracy** | Declared arrival rate and pattern shape as the "expected" baseline | Empirical arrival rate measurements as the "actual" for comparison | `baseRps`, pattern params vs measured inter-arrival stats |
| **Default-Driven Simplification Layer** | Pattern presets as the highest-level simplification ("pick a preset, not parameters") | Progressive disclosure rules that hide advanced pattern parameters | `RequestPatternPreset`, parameter visibility rules |

---

## Integration Requirements

| File / Module | Change | Why | Scope |
| --- | --- | --- | --- |
| `src/engine/core/types.ts` | Optionally restructure `WorkloadProfile` as discriminated union | Enforce pattern-param presence at type level | ~40 lines type change |
| `src/engine/core/types.ts` (or new `patternPresets.ts`) | Add `RequestPatternPreset`, `RequestPatternId` types | Support named presets referenced by environment model | ~30 lines new types |
| `src/engine/validation/validator.ts` | Add `validateWorkloadPattern()` call inside `validateTopology` | Catch semantically invalid pattern configurations | ~80 lines new validation logic |
| `src/engine/workload.ts` | Extract `DEFAULT_BURST_MULTIPLIER` etc. to accept them as constructor options | Allow environment model to provide pattern defaults | ~15 lines, change constructor signature |
| `src/engine/workload.ts` | Expose `intervalForRps` and `poissonIntervalForRps` for testing | Enable pattern accuracy validation spec to verify algorithms | ~5 lines, change private → package-visible |
| `src/engine/engine.ts` | When environment model lands, resolve `requestPatternId` → `WorkloadProfile` before constructing `WorkloadGenerator` | Connect preset system to engine initialization | ~20 lines in constructor |
| `src/renderer/src/types/ui.ts` | Extend `ScenarioState.workloadOverride` or add `requestPatternId` field | Allow scenario panel to select presets | ~5 lines |

---

## Source-to-Feature Map

| Feature | Source files | Types | Key functions |
| --- | --- | --- | --- |
| Workload Pattern Selection | `workload.ts`, `types.ts:369-413` | `WorkloadProfile` | `nextInterArrivalMs()` |
| Request Distribution | `workload.ts:155-195`, `events.ts` (Request) | `WorkloadProfile.requestDistribution`, `Request` | `pickRequestDistributionEntry()`, `createRequest()` |
| Inter-Arrival Algorithms | `workload.ts:78-153`, `distribution.ts:26-31` | — | `intervalForRps()`, `poissonIntervalForRps()`, `Distributions.exponential()` |
| Pattern Presets | Proposed: `patternPresets.ts` | `RequestPatternPreset`, `RequestPatternId` | Proposed: `resolvePatternPreset()` |
| Pattern Validation | `validator.ts` (existing schema), proposed extension | `PatternDiagnostic`, `PatternValidationResult` | Proposed: `validateWorkloadPattern()` |

---

## Assumptions and Unresolved Questions

| # | Assumption / Question | Status | Impact if wrong |
| --- | --- | --- | --- |
| 1 | `replay` pattern will eventually support trace-driven replay from recorded traffic | Assumption | If dropped, the pattern literal should be removed from the union to avoid confusion |
| 2 | The single-workload limitation (`TopologyJSON.workload` is singular) will be addressed in a later spec | Assumption | Multi-source topologies remain blocked on workarounds |
| 3 | The 10/90 priority split is acceptable for v1 | Assumption | Priority-queue discipline tests may produce unrealistic results |
| 4 | `diurnal.peakMultiplier` is a dead field — the generator only reads `hourlyMultipliers` | Observation | If it was intended to scale the multipliers, the implementation has a silent bug |
| 5 | Pattern presets are built-in only for v1, with user-defined presets deferred | Assumption | Users who need custom presets must configure `WorkloadProfile` manually |
| 6 | `requestDistribution` weights do not need to sum to 1.0 despite JSDoc stating otherwise | Observation — the algorithm normalizes by total weight | If validation enforces sum-to-1.0, some existing configurations may break |
| 7 | `bursty` and `diurnal` sub-objects remain optional (generator has fallbacks) while `spike` and `sawtooth` should be required when their pattern is selected | Design decision | Affects whether the discriminated union refactor makes `bursty`/`diurnal` required or optional |

# Canvas Indicator Grammar, Tooltips, and Roll-Up Legend

Technical UI specification expanding the July 21, 2026 review notes on tooltip coverage and the persistent corner legend into an implementation-ready document. This spec consolidates the attached critique with the current renderer code so later work can ship from one source of truth instead of ad hoc copy, one-off thresholds, and duplicated status logic.

The two requested deliverables are:

1. A complete tooltip and microcopy checklist for dense simulator surfaces.
2. A bottom-left corner legend that doubles as a live topology roll-up.

Both depend on the same prerequisite: one shared indicator grammar.

## Table of Contents

1. Problem Context
2. Goals and Non-Goals
3. Feature 1: Shared Indicator Grammar
4. Feature 2: Tooltip and Microcopy System
5. Feature 3: Corner Roll-Up Legend
6. Relationship to Existing Specs and Renderer Modules
7. Integration Requirements
8. Acceptance Criteria
9. Source-to-Feature Map

---

## Problem Context

### What exists today

The renderer already has most of the raw data and some of the primitives this work needs:

- `src/renderer/src/utils/nodeHealthThresholds.ts` defines the current status vocabulary and thresholds for reliability and capacity via `deriveReliabilityStatus()`, `deriveCapacityStatus()`, and `deriveCombinedRuntimeTone()`.
- `src/renderer/src/types/ui.ts` defines `MetricLens`, `RuntimeMetricLens`, and `NodeSimulationMetrics`, which are the contract every tooltip and roll-up summary will read from.
- `src/renderer/src/hooks/useNodeMetrics.ts` projects per-node runtime metrics from `useStore().simulationMetricsByNode`.
- `src/renderer/src/components/nodes/nodePresentation.ts` derives card-level status, capacity bands, and lens cards from the runtime metrics.
- `src/renderer/src/components/nodes/BaseNode.tsx` applies the visible selection ring and currently lets selection styling collide with health styling.
- `src/renderer/src/components/properties/PropertiesHeader.tsx` still exposes a single-word health badge derived from `nodeErrorRate`, which can contradict the richer runtime model already used elsewhere.
- `src/renderer/src/components/simulation/ResultsTray.tsx` already contains three local tooltip catalogs:
  - `E2E_PERCENTILE_TOOLTIPS`
  - `HEALTH_CHECK_TOOLTIPS`
  - `PER_NODE_COLUMN_TOOLTIPS`
- `src/renderer/src/components/ui/Tooltip.tsx` provides a hover tooltip primitive that can be reused, but it is hover-first and does not yet define a shared catalog or a keyboard/focus contract.

The data problem is not missing metrics. The problem is semantic drift across surfaces.

### What is missing

The current UI still lacks the system-wide rules that make dense instrumentation readable:

- No shared grammar separates reliability, capacity, activity, confidence, and selection into distinct visual channels.
- Tooltips exist in isolated pockets, but there is no repo-wide inventory of what must be explained, what should stay inline, and what copy should be reused across components.
- The results tray, node cards, properties header, and canvas do not read from one shared status presentation layer, which makes contradiction possible.
- There is no persistent legend that explains the active lens and summarizes topology health at a glance.
- Data caveats such as in-flight counts and percentile-summation limits are not consistently treated as confidence information; they can read like faults.
- The current tooltip primitive does not yet guarantee keyboard discoverability, which matters because many of the ambiguous labels are short abbreviations.

### What the source material explores

The attached notes make one core argument: the tooltip checklist and the corner legend are not separate polish items. They are both remedies for the same problem, namely a high-density interface with too many signals and no shared grammar for what those signals mean. This spec turns that argument into concrete scope, copy, data contracts, and file-level integration points.

---

## Goals and Non-Goals

### Goals

- Define one semantic indicator system for runtime status and UI state.
- Inventory every ambiguous metric label, badge, and caveat that needs tooltip or inline explanatory copy.
- Specify a persistent corner legend that is both a legend key and a live run summary.
- Keep thresholds, labels, and copy in one place so the canvas, tray, and properties panel cannot drift.
- Make the resulting work implementable within the existing renderer architecture.

### Non-Goals

- This spec does not redesign the entire canvas layout.
- This spec does not change engine-side metric computation.
- This spec does not define CSS tokens or pixel-level layout values.
- This spec does not introduce new simulation metrics beyond what `NodeSimulationMetrics` and `SimulationOutput` already expose.

### Anti-overload constraint

This spec adds a grammar, a tooltip catalog, and a live legend to an interface whose stated problem is too many signals. Left unchecked, the remedy reproduces the disease. The following constraint is binding, not advisory:

**One explanation per concept, and the cheapest channel wins.** For any given concept, the hierarchy is inline text, then tooltip, then legend. A concept gets exactly one of these, never two.

- If a label already carries an inline description, it does not also get a tooltip.
- If a concept is already explained in the legend key, individual instances do not repeat that explanation in tooltips unless the instance adds new, local information.
- A tooltip is justified only when the label is abbreviated or dense and there is no room for inline copy.

**Encoding budget per surface.** No single node, card, or table row may carry more than one indicator per channel. If two elements on the same object encode the same channel, remove one.

**Silence is a valid state.** Confidence strips, legend callouts, and warning treatments appear only when they are non-empty. An all-healthy run should be quieter than a degraded one.

The test for any new indicator is simple: if removing it does not change what the operator would conclude or do, it fails the budget and does not ship.

---

## Feature 1: Shared Indicator Grammar

### What it does

This feature defines the semantic channels the UI is allowed to use and assigns exactly one primary visual mechanism to each. The goal is to stop collisions such as red meaning both failure and saturation, or green meaning both healthy and selected.

### Why it exists

The current renderer already computes multiple kinds of state, but those states are not consistently separated in presentation. Without a shared grammar, each component locally decides what color or badge means, which makes the whole app harder to scan and easier to misread.

### How it works internally

#### Data source

The relevant existing data contracts are already present:

```ts
export type RuntimeMetricLens = 'traffic' | 'saturation' | 'latency' | 'errors' | 'throughput'

export interface NodeSimulationMetrics {
  throughput?: number
  postWarmupArrived?: number
  postWarmupProcessed?: number
  postWarmupRejected?: number
  postWarmupTimedOut?: number
  postWarmupConnectionReset?: number
  postWarmupInFlight?: number
  queueDepth?: number
  utilization?: number
  errorRate?: number
  active?: boolean
  successLatencySamples?: number
  timeToErrorSamples?: number
  latencyWindowErrorRate?: number
}
```

```ts
export type NodeCapacityLevel = 'headroom' | 'tight' | 'saturated'
export type NodeReliabilityLevel = 'idle' | 'healthy' | 'degraded' | 'failing' | 'silent' | 'down'
```

#### New types

These types should live in a shared renderer module such as `src/renderer/src/features/indicators/indicatorTypes.ts`.

```ts
export type IndicatorChannel =
  | 'reliability'
  | 'capacity'
  | 'activity'
  | 'confidence'
  | 'selection'

export interface IndicatorDescriptor {
  channel: IndicatorChannel
  label: string
  detail: string
  source: 'runtime' | 'ui-state'
}
```

These types exist so the legend, tooltip catalog, node cards, and properties header can all describe state using the same vocabulary.

#### Channel rules

| Channel | Question answered | Existing data source | Primary encoding | Must never encode |
| --- | --- | --- | --- | --- |
| Reliability | Are requests succeeding here | `deriveReliabilityStatus()` in `nodeHealthThresholds.ts` | Discrete status dot/badge with labels like `Healthy`, `Degraded`, `Failing`, `Silent`, `Down` | Capacity or selection |
| Capacity | How much headroom is left | `deriveCapacityStatus()` in `nodeHealthThresholds.ts` | Meter/ramp or capacity glyph, never terminal-failure red while still serving | Reliability or selection |
| Activity | Is traffic moving right now | `useStore().edgeFlowById`, `EdgeFlowState.recent`, per-edge rate fields from `useStore.ts`, and the projections consumed by `PacketEdge.tsx` | Motion density and speed | Health severity |
| Confidence | Can I trust or qualify this number | In-flight counts, percentile scope limits, replay caps, warmup notes in `ResultsTray.tsx` and `NodeMetricsDetail.tsx` | Info/caveat glyph and muted informational treatment | Errors or faults |
| Selection | What the operator is focused on | Selection state in canvas and inspector | Neutral outline or bracket | Health or capacity |

#### Canonical thresholds

Every threshold the derivations depend on is stated here. `deriveReliabilityStatus()`, `deriveCapacityStatus()`, and legend aggregation must read these values from one canonical source. If a number changes, it changes in the shared threshold module and nowhere else.

**Reliability** is evaluated per node, in precedence order.

| Status | Condition | Notes |
| --- | --- | --- |
| `Idle` | `postWarmupArrived === 0` and there are no success or error window samples | No traffic reached the node; blank runtime status is intentional |
| `Down` | no successful passes and `latencyWindowErrorRate > 50%`, dominant cause is not timeout | Node is effectively not serving |
| `Silent` | no successful passes and `latencyWindowErrorRate > 50%`, dominant cause is timeout | Requests are timing out rather than being actively rejected |
| `Failing` | `latencyWindowErrorRate > 5%` | Dominant-cause detail may specialize the copy, but the bucket is still failing |
| `Degraded` | `latencyWindowErrorRate > 1%` | Elevated but still serving |
| `Healthy` | none of the above | Errors at or below 1% |

Reliability does not read `utilization` or `queueDepth`. Those belong to capacity. This also means `nodeHealthThresholds.ts` should consume its own `failureWarnPercent` and `failureCritPercent` thresholds directly rather than letting the derived labels drift from the shared constants.

**Capacity** is evaluated per participating node, in precedence order.

| Band | Condition | Notes |
| --- | --- | --- |
| `Saturated` | `utilization >= 90%` | Warning tone, but never terminal-failure red while reliability is still healthy |
| `Tight` | `utilization >= 75%` or `queueDepth >= 1` | Limited headroom |
| `Headroom` | none of the above | Comfortable slack remains |

`deriveCapacityStatus()` is the semantic contract for the legend and roll-up counts. `nodePresentation.ts` currently introduces an extra renderer-only visual sub-band via `getRuntimeCapacityVisualBand()` with `steady` at `utilization >= 40%`. That visual accent is allowed for node-card styling, but it is not a separate semantic legend bucket and must not fork the roll-up logic.

**Node-type participation** is explicit because not every node participates in every channel.

| Node role | Reliability | Capacity | Basis |
| --- | --- | --- | --- |
| Source / client | Yes | No | Source nodes have no worker or connection saturation model; exclude them from capacity roll-up counts |
| Compute / service | Yes | Yes | Full participation |
| Datastore / cache | Yes | Yes, when a concurrency limit exists | Capacity derives from worker, pool, or connection saturation |
| Passive or synthetic nodes without a concurrency limit | Yes, when requests can fail there | No | Omit from capacity counts rather than treating them as headroom |

A node that does not participate in a channel is omitted from that channel's bucket totals, not counted as zero-utilization headroom. The legend header may still count all topology nodes, but each channel's buckets sum only to the participating subset.

**Confidence callout thresholds** define when the legend surfaces a run-level caveat.

| Callout | Trigger | Source |
| --- | --- | --- |
| In-flight at cutoff | `sum(postWarmupInFlight) >= 1` across the topology | `NodeSimulationMetrics.postWarmupInFlight` |
| Replay cap | recorded edge-flow events exceed the renderer retention cap | `EDGE_FLOW_MAX_EVENTS` in `useStore.ts` |
| Saturated present | any participating node is in `Saturated` | `deriveCapacityStatus()` |
| Failing present | any participating node is in `Failing`, `Down`, or `Silent` | `deriveReliabilityStatus()` |

`In flight >= 1` is deliberately low. Even a single in-flight request at cutoff is worth a one-line note because it explains why arrival and completion counts differ. This remains a confidence treatment, never an error treatment.

#### Required visual invariants

- Reliability remains discrete.
- Capacity remains a gradient or bounded-limit indicator.
- Activity is motion, not status color.
- Confidence is informational, not alarm-colored.
- Selection uses a neutral accent not present in any health palette.

#### Current collisions this feature must eliminate

- `BaseNode.tsx` can currently let a selected node read as a status-colored node.
- `PropertiesHeader.tsx` still compresses runtime health into a single status badge.
- `ResultsTray.tsx` and node cards can show capacity and reliability with different severity semantics.
- Informational caveats can visually resemble warnings or failures.

### What components it requires

- Engine-side: none.
- Shared layer: a renderer-only indicator type module and a shared copy catalog.
- Renderer/frontend-side:
  - `BaseNode.tsx`
  - `nodePresentation.ts`
  - `PropertiesHeader.tsx`
  - `ResultsTray.tsx`
  - new legend component and aggregation helper

---

## Feature 2: Tooltip and Microcopy System

### What it does

This feature defines what must be explained, where the explanation lives, and which copy should be shared across surfaces. It centralizes tooltip text, caveat copy, and small inline hints so dense simulator vocabulary does not rely on guesswork.

### Why it exists

The simulator uses real systems and queueing language: `Arr CV`, `λ`, `W`, `L`, `In Flight`, warmup, headroom, and per-hop percentiles. These are valid terms, but they are not self-explanatory for every user. The current UI already has good explanatory copy in a few places, but coverage is uneven and the copy is trapped inside local components.

### How it works internally

#### Data source

The tooltip system does not need new engine data. It reads existing labels and runtime values from:

- `MetricLensSwitcher.tsx`
- `ResultsTray.tsx`
- `NodeMetricContent.tsx`
- `RuntimeNodeMetrics.tsx`
- `NodeMetricsDetail.tsx`
- `PropertiesHeader.tsx`
- `nodePresentation.ts`

#### New types

These types should live in `src/renderer/src/config/tooltipCatalog.ts`.

```ts
export type TooltipIntent = 'metric' | 'status' | 'caveat' | 'legend' | 'empty-state'

export interface TooltipSpec {
  key: string
  intent: TooltipIntent
  shortLabel?: string
  description: string
  placementHint?: 'right' | 'bottom'
}
```

The catalog exists for two reasons:

1. Copy reuse: the same concept should not be explained three different ways in three different files.
2. Drift prevention: if threshold or wording changes, the app should update from one place.

#### Global writing rules

- Anything a newcomer cannot decode in two seconds gets a tooltip or inline help.
- Primary instructions belong inline; secondary or dense explanations belong in tooltips.
- Confidence caveats are not phrased as faults.
- Tooltip content must be available on hover and focus.
- Existing good copy in `ResultsTray.tsx` should be preserved and moved, not rewritten for novelty.

#### Tooltip interaction model

Hover and focus parity is a requirement, but it does not mean every dense label becomes a stop in the tab order.

- Reuse focusable controls when a surface already has them, such as buttons, tabs, or sortable headers.
- For non-interactive dense labels, attach the tooltip to a dedicated compact info affordance rather than making every static text node tabbable.
- Material caveats that change how a number should be interpreted must also appear somewhere inline in the surface, not tooltip-only.

This spec is desktop-first. Touch-specific reinterpretation is out of scope for the first pass, but anything essential to numeric correctness must remain readable without hover.

#### Tooltip inventory

##### A. Canvas lens switcher

| Element | Current file | Action | Copy |
| --- | --- | --- | --- |
| `Traffic` | `MetricLensSwitcher.tsx` | Add tooltip | `Colors nodes and edges by request flow and fail rate.` |
| `Saturation` | `MetricLensSwitcher.tsx` | Add tooltip | `Colors nodes by utilization headroom so you can see what is near capacity.` |
| `Latency` | `MetricLensSwitcher.tsx` | Add tooltip | `Colors by response time so slow hops stand out.` |
| `Errors` | `MetricLensSwitcher.tsx` | Add tooltip | `Colors by failure rate and dominant failure cause.` |
| `Throughput` | `MetricLensSwitcher.tsx` | Add tooltip | `Colors by requests per second moving through each node.` |

##### B. Results tray: end-to-end metrics and health checks

| Surface | Current state | Action |
| --- | --- | --- |
| End-to-end percentile chips | Already documented by `E2E_PERCENTILE_TOOLTIPS` in `ResultsTray.tsx` | Keep the copy, move it into the shared catalog |
| Health check rows | Already documented by `HEALTH_CHECK_TOOLTIPS` in `ResultsTray.tsx` | Keep the copy, move it into the shared catalog, and use the same phrasing anywhere those checks reappear |

##### C. Results tray: per-node table headers

This is the highest-value tooltip cluster in the product and should be treated as required scope.

| Header | Copy |
| --- | --- |
| `Arrived` | `Requests that reached this node in the post-warmup window.` |
| `Done` | `Requests this node finished before the cutoff in the post-warmup window.` |
| `Reject` | `Requests turned away because the queue was full.` |
| `T.O.` | `Requests that exceeded this node's timeout.` |
| `Reset` | `Requests explicitly terminated with connection_reset while queued or in service.` |
| `In Flight` | `Requests that had arrived here but were still queued or processing when the run ended.` |
| `Avg Q` | `Time-averaged queue depth for requests waiting, not yet being processed.` |
| `Util` | `Fraction of workers busy on average. Near 100% means the node is saturated.` |
| `Err %` | `Rejected + timed out + reset requests divided by arrivals at this node.` |
| `Arr CV` | `Arrival burstiness. 0 is perfectly even, about 1 is Poisson, higher means spikier arrivals.` |
| `p50 / p95 / p99` | `Per-hop latency percentiles at this node only. Per-hop percentiles do not sum to end-to-end percentiles.` |
| `λ` | `Arrival rate in requests per second during the post-warmup window.` |
| `W` | `Mean time a request spends at this node, including queue and service time.` |
| `L` | `Average number of requests at this node at once. By Little's Law, L = λ × W.` |

##### D. Node cards and runtime cardlets

| Element | Current file | Action | Copy |
| --- | --- | --- | --- |
| `Completed / Received` | `RuntimeNodeMetrics.tsx` | Add tooltip to label | `Requests this node completed out of requests that reached it in the post-warmup window.` |
| `Rejected / Timed Out` | `RuntimeNodeMetrics.tsx` | Add tooltip to label | `Requests dropped because the queue filled, or requests that waited longer than the timeout.` |
| Pre-run metric labels like `Workers`, `Connections`, `Operations`, `Consumers` | `nodePresentation.ts` and node components | Add tooltip or inline explanation per label family | `Concurrent work this node can process at once.` |
| Idle text `No post-warmup traffic` | `NodeMetricContent.tsx` | Add tooltip on the text | `This node received no requests after the warmup period, so runtime metrics are intentionally blank.` |
| Lens card `click for detail` explanations | `nodePresentation.ts` | Keep inline, not tooltip-only | Inline text already carries the first-level explanation; do not hide that behind hover |

##### E. Properties panel and detail view

| Element | Current file | Action | Copy |
| --- | --- | --- | --- |
| Header health badge | `PropertiesHeader.tsx` | Replace one-word badge and add tooltip | `Reliability shows whether requests are succeeding. Capacity shows how much headroom is left.` |
| Mean service time | form config surfaces | Add tooltip only if no inline description is present | `Fixed processing time per request when latency is not modeled dynamically.` |
| Chaos `Blackhole` mode | form config surfaces | Add tooltip | `The node accepts requests but never responds. They fail only when the caller timeout fires.` |
| Latency note in detail view | `NodeMetricsDetail.tsx` | Keep inline, style as a caveat not a failure unless success count is zero | Existing note already explains when percentiles are success-only |

##### F. Confidence and caveat copy

These are not faults and must use the confidence channel.

| Message | Current file(s) | Copy |
| --- | --- | --- |
| In-flight at cutoff | `ResultsTray.tsx`, `NodeMetricsDetail.tsx` | `Counted as neither completed nor failed. Normal at the cutoff because the requests had not finished yet.` |
| Per-hop percentiles do not sum | results surfaces | `Each hop's percentile is measured independently, so you cannot add per-hop p95 or p99 values to get end-to-end p95 or p99.` |
| Replay/event cap reached | traffic/event surfaces | `Capped for rendering speed. Aggregate metrics still use the full dataset.` |
| Warmup exclusions | run summary and idle states | `Warmup traffic is excluded from reported steady-state metrics.` |

##### G. Empty and first-run states

| Surface | Action | Copy |
| --- | --- | --- |
| Empty canvas | Add inline empty-state text | `Load a scenario from the left, or drag a component onto the canvas to start.` |
| No selected run detail | Add small instructional copy where needed | `Run a simulation, then select a node to inspect runtime detail.` |

### What components it requires

- Engine-side: none.
- Shared layer:
  - new shared tooltip catalog module
  - shared confidence/caveat copy entries
- Renderer/frontend-side:
  - `Tooltip.tsx` for hover + focus behavior
  - `MetricLensSwitcher.tsx`
  - `ResultsTray.tsx`
  - `RuntimeNodeMetrics.tsx`
  - `NodeMetricContent.tsx`
  - `NodeMetricsDetail.tsx`
  - `PropertiesHeader.tsx`

---

## Feature 3: Corner Roll-Up Legend

### What it does

This feature adds a persistent bottom-left legend that explains the active encoding and summarizes topology status in one glance. It is both a legend key and a live roll-up of how many nodes are healthy, degraded, saturated, failing, or idle.

### Why it exists

A static legend is usually ignored after the first day. A live roll-up is operationally useful on every run. The feature solves two problems at once: it explains the visual language without forcing memory, and it gives the operator a compact topology verdict without opening the results tray.

### How it works internally

#### Data source

The roll-up should be derived from existing renderer state only:

- `useStore().simulationMetricsByNode`
- `useStore().metricLens`
- `deriveReliabilityStatus()` from `nodeHealthThresholds.ts`
- `deriveCapacityStatus()` from `nodeHealthThresholds.ts`
- node metadata already available to node components for labels and workers

No engine changes are required.

#### New types

These should live in a helper such as `src/renderer/src/components/canvas/topologyLegend.ts`.

```ts
export interface LegendCount {
  key: string
  label: string
  count: number
  tone: 'neutral' | 'ok' | 'warn' | 'crit'
  shape: 'circle' | 'rounded-square'
}

export interface LegendCallout {
  severity: 'info' | 'warn' | 'crit'
  label: string
  detail: string
}

export interface TopologyLegendRollup {
  lens: RuntimeMetricLens | null
  reliability: LegendCount[]
  capacity: LegendCount[]
  confidence: LegendCallout[]
}
```

The legend needs these types because it is not a raw metric dump. It is a derived summary with presentation semantics attached.

#### Aggregation logic

For each node with runtime metrics:

1. Derive reliability via `deriveReliabilityStatus()`.
2. Derive capacity via `deriveCapacityStatus()`.
3. Increment the appropriate reliability bucket.
4. Increment the appropriate capacity bucket.
5. Add a confidence callout when the topology has notable in-flight requests, a replay cap, or another run-level caveat already exposed elsewhere.

Suggested buckets:

- Reliability:
  - `Healthy`
  - `Degraded`
  - `Failing`
  - `Silent`
  - `Down`
  - `Idle`
- Capacity:
  - `Headroom`
  - `Tight`
  - `Saturated`

#### Behavior rules

| State | Condition | Behavior |
| --- | --- | --- |
| Pre-run | No runtime metrics in store | Show a compact legend key for the active lens and selection semantics, but no roll-up counts |
| Running | Runtime metrics present and still updating | Show live counts that update as store data changes |
| Post-run | Stable final output | Keep counts visible and show confidence callouts if present |
| Incomplete or errored run | Results are partial, or the simulation terminates with an error after some metrics were emitted | Freeze the last coherent counts if available and add a neutral confidence callout such as `Run incomplete — counts reflect partial output`; otherwise fall back to the compact key only |
| Reduced motion | Motion reduced or disabled | Legend remains fully informative; it must not depend on animation |

#### Visual rules

- Reliability uses circles.
- Capacity uses rounded squares.
- Confidence uses an info/caret glyph and muted informational styling.
- Selection is represented in the key with a neutral outline, not a health color.
- Zero counts are shown in muted text so non-zero buckets dominate attention.
- The bottom action strip appears only when there is something worth surfacing, such as one or more saturated or failing nodes.

#### Copy examples

- `1 saturated — no headroom for spikes`
- `2 failing — errors dominate this run`
- `3 requests still in flight at cutoff`

#### Placement

Bottom-left is the correct default because:

- top-left already contains the lens switcher
- top-right is contested by inspector and contextual detail
- bottom-right already carries the minimap and related affordances

On narrow canvas widths, the legend should collapse to a single summary chip that expands on hover or focus. The legend remains bottom-left by default; collapse is the first response, not relocation.

### What components it requires

- Engine-side: none.
- Shared layer:
  - legend aggregation helper reusing `nodeHealthThresholds.ts`
  - shared indicator and tooltip vocabulary
- Renderer/frontend-side:
  - new `TopologyLegend` component
  - new aggregation helper or selector
  - `FlowCanvas.tsx` to mount the legend

---

## Relationship to Existing Specs and Renderer Modules

This spec is a focused follow-on to `ns-simulator-docs/specs/canvas-visualization-and-ux-simplification.md`. That earlier document defines what the canvas should prioritize. This document defines how the indicators on that canvas are explained and summarized.

It also aligns with the following governing principles already documented in `ns-simulator-docs/design-decisions/governing-principles.md`:

- Principle 26: one meaning per channel, everywhere
- Principle 32: warmup and windows are visually honest
- Principle 35: every encoding is inspectable

### Shared data source table

| Source | Consumed by tooltips | Consumed by legend | Notes |
| --- | --- | --- | --- |
| `NodeSimulationMetrics` | Yes | Yes | Primary runtime metric contract |
| `RuntimeMetricLens` | Yes | Yes | Explains active encoding |
| `deriveReliabilityStatus()` | Yes | Yes | Must remain the canonical reliability derivation |
| `deriveCapacityStatus()` | Yes | Yes | Must remain the canonical capacity derivation |
| `ResultsTray.tsx` local tooltip constants | Yes | Indirectly | Should be moved into a shared catalog |

### Implementation order implications

1. Shared vocabulary first.
2. Shared tooltip catalog second.
3. Status surface alignment third.
4. Legend component after the above, so it reuses the same semantics instead of inventing its own.

---

## Integration Requirements

| File or module | Change | Why | Size |
| --- | --- | --- | --- |
| `src/renderer/src/components/ui/Tooltip.tsx` | Add focus/blur support and standardize trigger behavior | Dense labels must be keyboard-discoverable, not hover-only | Small |
| `src/renderer/src/config/tooltipCatalog.ts` | New shared catalog for tooltip and caveat copy | Prevent copy drift and duplication | Medium |
| `src/renderer/src/features/indicators/indicatorTypes.ts` | New shared indicator vocabulary | Makes legend, tooltips, and status surfaces speak one language | Small |
| `src/renderer/src/utils/nodeHealthThresholds.ts` | Align the runtime derivations with the stated canonical thresholds and keep all cutoffs in one module | Prevent legend, tray, and card logic from drifting or hard-coding competing numbers | Small |
| `src/renderer/src/components/canvas/MetricLensSwitcher.tsx` | Wrap lens buttons with tooltips from the shared catalog | Explains what each lens changes | Small |
| `src/renderer/src/components/simulation/ResultsTray.tsx` | Replace local tooltip constants with catalog references and normalize caveat styling | Keeps existing good copy while making it reusable | Medium |
| `src/renderer/src/components/nodes/RuntimeNodeMetrics.tsx` | Add label-level tooltips | Explains compact node card metrics | Small |
| `src/renderer/src/components/nodes/NodeMetricContent.tsx` | Add idle-state explanation | Clarifies warmup and no-traffic cases | Small |
| `src/renderer/src/components/properties/NodeMetricsDetail.tsx` | Reuse caveat copy and confidence styling | Keeps latency and in-flight notes consistent | Small |
| `src/renderer/src/components/properties/PropertiesHeader.tsx` | Replace single health badge with combined reliability/capacity summary | Avoids contradiction with runtime detail below | Medium |
| `src/renderer/src/components/nodes/BaseNode.tsx` | Decouple selection styling from health styling | Removes one of the highest-risk channel collisions | Small |
| `src/renderer/src/components/canvas/TopologyLegend.tsx` | New legend component | Adds the persistent key and live roll-up | Medium |
| `src/renderer/src/components/canvas/FlowCanvas.tsx` | Mount the legend and pass required state | Integrates the new component into the canvas | Small |

---

## Acceptance Criteria

- No visible status surface uses the same encoding for both reliability and selection.
- The five runtime lens buttons each explain what changing the lens will recolor or emphasize.
- Every abbreviated per-node results-table header has tooltip coverage.
- Existing results-tray percentile and health-check explanations are preserved and centralized.
- Data caveats are presented as confidence information, not error alarms.
- The properties header no longer shows a single-word status that can contradict the runtime tray beneath it.
- The legend is persistent in the bottom-left corner and remains useful before, during, and after a run.
- The legend uses different shapes for reliability and capacity.
- The legend roll-up reads from the same threshold logic as node cards and tray badges.
- Tooltip content is available on both hover and focus.
- Reliability and capacity remain distinguishable without relying on hue alone in the legend and its key.

---

## Source-to-Feature Map

| Source material | Covered here |
| --- | --- |
| Attached note: indicator design language and collision audit | Problem Context, Feature 1, Integration Requirements |
| Attached note: tooltip checklist | Feature 2 |
| Attached note: corner roll-up legend | Feature 3 |
| Existing spec: `canvas-visualization-and-ux-simplification.md` | Relationship section |
| Existing renderer modules | Problem Context and Integration Requirements |

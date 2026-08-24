# Budget V3 - Implementation Spec (code-level)

> **What this is.** The engineering translation of `budget-feature-consolidated-design-v3.md`
> onto the actual ns-simulator codebase: the exact files, symbols, signatures, and
> ordering to build it - plus the two places where the design meets a code reality it
> didn't account for (edge traffic cost and the "foil" topology), and how to resolve them.
>
> **Status.** Plan only. V1 ships with no graded budget (already removed). Nothing below
> is built yet. Phases 1-2 deliver a meaningful budget; 3-5 deepen it.

---

## 0. Where budget lives today (the surface to change)

| Concern | File | Key symbols |
|--------|------|-------------|
| Cost math | `src/engine/analysis/budget.ts` | `estimateNodeCost(node)`, `evaluateBudget(topo, budget)`, `budgetBreakdown(topo, budget)`, `EDGE_COST`, `BudgetEvaluation`, `BudgetBreakdown`, `BudgetLineItem` |
| Budget type/schema | `src/engine/analysis/gradingCriteria.ts` | `Budget = { unit: 'cost'\|'nodes'\|'edges'; cap }`, `BudgetSchema`, `parseBudget` |
| Grading integration | `src/engine/analysis/question.ts` | `gradeAttemptWithArtifacts` (calls `evaluateBudget`), `flattenBudgetRows`, `toHostContract`, `AttemptGrade.budget` |
| Authoring checks | `src/engine/analysis/authoringValidator.ts` | `validateAuthoredQuestion(pkg)`, `AuthoringDiagnostic` |
| Trio harness | `scripts/validate-question-dir.ts` | grades reference + gamed topologies (has both topologies in hand) |
| UI meter | `src/renderer/src/components/question/BudgetMeter.tsx` | renders when `activeQuestion.budget` exists |
| Question authoring | `scripts/gen-question-fixtures.ts` | generates each question's `question.json` + topologies |

**Invariant to preserve:** `evaluateBudget` / `budgetBreakdown` are **pure functions of
the topology** - no simulation run. That is why `BudgetMeter` updates live as the student
edits. Phases 1-2 keep this. Phase 3 (traffic cost) is the only part that needs run-time
data, and §3 shows how to add it without breaking the live meter.

---

## 1. Two architectural decisions the design forces

### 1a. Traffic-weighted edges are NOT pure - split the model

The design's `edgeCost = EDGE_BASE + ceil(throughputMBps / NETWORK_UNIT)` needs per-edge
throughput. Reality in the code:

- `SimulationOutput.perEdge: Record<string, PerEdgeMetrics>` exists, but `PerEdgeMetrics`
  carries `totalSuccessfulTransits` - a **request count**, not bytes. There is **no**
  `throughputMBps` field, and `perEdge` is **not** projected into `SimulationVerdict`.
- So `throughputMBps` must be **derived**:
  `MBps ≈ (totalSuccessfulTransits × avgPayloadBytes) / (durationSec × 1e6)`, where
  `avgPayloadBytes` is the weighted mean of the injected `requestDistribution.sizeBytes`.

> ⚠️ **This is a deliberately coarse proxy, not a measurement.** It applies one
> workload-wide mean payload to *every* edge, so it ignores per-edge byte differences
> (a fan-out to a cache vs a hit on the DB), request-vs-response asymmetry, and cache
> hit-rate effects - which are largest on exactly the edges the `chatty-services`
> lesson turns on. Treat the network number the way V3 treats base costs: **relative
> order is the lesson, the absolute value is approximate.** Per-edge payload
> differentiation is a later refinement (would require tagging transit bytes per edge
> in `PerEdgeMetrics`).

**Decision - a two-tier budget:**

| Term | Purity | Where computed | Meter behavior |
|------|--------|----------------|----------------|
| base (`BASE[type]×replicas`) + capacity | **pure** (topology only) | `budget.ts` as today | live |
| traffic (edge) | needs `SimulationOutput` | `gradeAttemptWithArtifacts` at grade time, via a `BudgetContext` | live meter shows base+capacity; network cost appears **after Run** (or as a static estimate - see §3) |

This keeps the live meter working and adds the network term where the data actually
exists (grade time, per case).

### 1b. The "foil" is a new topology, distinct from the gamed one

The design's guardrail needs a **foil**: *correct on every other axis but expensive*.
The existing `gamed-topology.json` is the opposite - *wrong on the intended axis*
(fails p99/structural). They are different designs. So a budget question needs a
**third topology**, `budget-foil-topology.json`, and the harness grades it too:

- reference → within budget + passes all axes;
- gamed → fails the intended axis (unchanged);
- **budget-foil** → passes all axes **except** budget (over cap).

The discrimination guardrail (§5) runs `budgetBreakdown` on reference vs foil.

### 1c. Which cost each consumer reads (resolve the meter ↔ guardrail divergence)

`base + capacity` is available live; `traffic` needs a run. **Three consumers read a
cost, and if they read different totals the cap is miscalibrated** - worst on
`chatty-services`, where traffic *is* the cost. Pin them down:

| Consumer | Cost it uses | Why |
|----------|--------------|-----|
| **Live meter** (pre-run) | base + capacity **only** | no `SimulationOutput` yet; shows `+ network (run to measure)` |
| **Cap-last calibration** (author) | **full** cost incl. traffic, from a grade run | the cap must include the term the lesson is about |
| **Guardrail** (`non_binding`, …) | **full** grade-time cost | the harness has `SimulationOutput`; reference vs foil compared on the same basis |

**Rule:** the cap and every guardrail ratio operate on the **full grade-time cost**
(base + capacity + traffic). The live meter is a deliberately-degraded *preview* and is
**never** the calibration source. Consequently the author-mode calibration hint (§7)
must display the **full `C_ref` from a grade run**, not the meter's partial total - or a
`chatty-services` cap will be set against a number that omits its own lesson.

---

## 2. Phase 1 - `nodes` anti-kitchen-sink cap (already works)

**No engine change.** `evaluateBudget` already handles `unit: 'nodes'`
(`actual = topology.nodes.length`), `budgetBreakdown` already emits per-node items, and
`BudgetMeter`'s `UNIT_LABEL` already has `nodes: 'node count'`.

**To ship:** author a question with `budget: { unit: 'nodes', cap: 8 }`. Done.

Optional polish: the `BudgetMeter` cost-heuristic footnote is gated on
`budget.unit === 'cost'`, so it correctly hides for `nodes`. Nothing else.

> Use `budget:{unit:'nodes'}` (graded) rather than `constraints.maxNodeCount` (a
> constraint) when you want the cap to be a graded, student-visible test row.

---

## 3. Phase 2 - per-type cost model (`budget.ts`)

### 3a. New tables (top of `budget.ts`)

```ts
// Base cost by componentType; unlisted → DEFAULT_BASE (backward compatible).
const DEFAULT_BASE = 1
const BASE: Partial<Record<ComponentType, number>> = {
  'api-endpoint': 0,
  microservice: 2, 'batch-worker': 2, queue: 2, 'load-balancer': 2,
  'in-memory-cache': 2, 'object-storage': 2,
  cdn: 3, 'kv-store': 3,
  'message-broker': 4, 'nosql-db': 4, 'time-series-db': 4,
  'search-index': 4, 'distributed-lock': 4,
  'event-sourcing-store': 5,
  'relational-db': 6
}

// Stateful nodes charge more per capacity unit (DB connections > worker threads).
const CAPACITY_UNIT_STATELESS = 100
const CAPACITY_UNIT_STATEFUL = 25
```

Stateful classification reuses the catalog - no new metadata:

```ts
import { getComponentSpec } from '../catalog/componentSpecs'
const STATEFUL_CATEGORIES = new Set<ComponentCategory>([
  'storage-and-data', 'messaging-and-streaming', 'consensus-and-coordination'
])
function capacityUnit(node: ComponentNode): number {
  // Fallback chain: catalog spec → the node's own category → stateless.
  const cat = getComponentSpec(node.type)?.category ?? node.category
  if (cat === undefined) return CAPACITY_UNIT_STATELESS // never misclassify silently
  return STATEFUL_CATEGORIES.has(cat) ? CAPACITY_UNIT_STATEFUL : CAPACITY_UNIT_STATELESS
}
```

> ⚠️ **Guard the "unknown type" path.** `getComponentSpec` can return `undefined` for an
> unrecognized type, and `node.category` may be missing on a student-built node - so the
> explicit `?? CAPACITY_UNIT_STATELESS` is deliberate. But note the failure mode it
> creates: a **stateful** node that slips through (bad/unknown type) is charged the
> cheaper stateless unit, i.e. it *undercharges the exact over-provisioning the model is
> meant to punish*. Add a `budget.test.ts` case for an unknown-type node and for a
> stateful node with a missing `category`, asserting they don't silently price as cheap
> stateless when the type is actually known-stateful.

### 3b. Rewrite `estimateNodeCost`

```ts
export function estimateNodeCost(node: ComponentNode): number {
  const base = BASE[node.type] ?? DEFAULT_BASE
  const replicas = node.resources?.replicas ?? 1
  const workers = node.queue?.workers ?? 0
  return base * replicas + Math.floor(workers / capacityUnit(node)) // floor, not ceil (see note)
}
```

> **`Math.floor`, not `ceil`.** The capacity term must be **0 below one full unit** so a
> default-sized node costs only `base × replicas` and the initial state stays clean. With
> `ceil`, any node with ≥1 worker gains a spurious +1, and the §3e live-feedback / §8
> worked numbers break. (The V3 design draft's `ceil` is a typo vs its own constant
> descriptions; use `floor`. Same applies to the edge traffic term in §4a.)

`replicas` multiplying `base` is what makes `relational-db ×3 = 18` blow a cap that a
`in-memory-cache = 2` fits under - the core lesson.

### 3c. Update `budgetBreakdown` line-item formula

The `cost`-unit branch already builds per-node items; change the `formula` string to
`` `${base}×${replicas} + ⌊${workers}/${unit}⌋` `` so the breakdown shows *why* a node
is expensive.

### 3d. Ripple

- **`BudgetMeter.tsx`** hard-codes the footnote `"1 + replicas + ⌈workers/50⌉"`. Replace
  with model-aware copy, e.g. `"cost = base(type) × replicas + capacity + network"`.
- **`budget.test.ts`** asserts the old numbers (`lean = 2`, `heavy = 21`, etc.). Update to
  the new formula and add per-type cases (a `relational-db` costs 3× an `in-memory-cache`).
- **Back-compat:** unlisted types fall to `DEFAULT_BASE = 1`, so no existing topology
  errors; only the *numbers* change, and no live V1 question has a budget.

### 3e. Where `replicas` / `workers` come from (the live-feedback loop)

`estimateNodeCost` reads `node.resources?.replicas` and `node.queue?.workers`. On the
**student topology** these come from the serialized canvas node, and both are optional:
`replicas ?? 1`, `workers ?? 0`. So a student who drops a `relational-db` and never
touches its config is priced at `base × 1 = 6` (one replica) with no worker charge - and
the moment they bump the replica count in the PropertiesPanel, `serialize()` re-runs, the
`BudgetMeter` `useMemo` recomputes, and the cost rises **live**. That live tie between the
replica knob and the meter *is* the "add a cache, not 3 replicas" lesson, so verify two
things when building: (a) the replica/worker fields are actually editable on the relevant
node types in the config panel (they render from the capability modules - confirm
`relational-db` exposes a replicas field), and (b) the meter reflects a replica change
without a Run. If replicas aren't user-editable for a type, the core budget lesson can't
be felt on it.

> **Phase 5 e2e assertion (foil replicas actually serialize).** The whole "cache vs 3
> replicas" fork depends on the foil's replica count landing at `node.resources.replicas`
> - the exact path `estimateNodeCost` reads. If the generator writes the replica count to
> a different path (or the serializer drops it), the foil silently costs `6×1` instead of
> `6×3`, `C_foil` falls under the cap, and the guardrail passes a broken question. Add an
> explicit assertion to the `validate-question-dir.ts` run for budget questions:
> `budgetBreakdown(foil).items.find(i => i.id === '<db-node>').cost === BASE['relational-db'] × 3`.

---

## 4. Phase 3 - traffic-weighted edges

### 4a. Context-threaded budget

```ts
export interface BudgetContext {
  /** MB/s on an edge, derived at grade time from SimulationOutput. Absent ⇒ 0. */
  edgeThroughputMBps?: (edgeId: string) => number
}
const EDGE_BASE = 1
const NETWORK_UNIT = 50 // MB/s per network cost unit
function edgeCost(edge: EdgeDefinition, ctx?: BudgetContext): number {
  const mbps = ctx?.edgeThroughputMBps?.(edge.id) ?? 0
  return EDGE_BASE + Math.floor(mbps / NETWORK_UNIT) // floor: sub-unit traffic adds 0
}
```

`evaluateBudget(topo, budget, ctx?)` and `budgetBreakdown(topo, budget, ctx?)` gain the
optional `ctx` (default = no traffic → today's `EDGE_BASE`-only behavior, fully back-compat).

### 4b. Deriving throughput at grade time (`question.ts`)

`gradeAttemptWithArtifacts` already holds each case's `SimulationOutput`
(`outputByTopology`). Build the context there:

```ts
const avgPayload = weightedMeanSizeBytes(caseWorkload.requestDistribution)
const durationSec = topology.global.simulationDuration / 1000
const ctx: BudgetContext = {
  edgeThroughputMBps: (id) => {
    const e = output.perEdge[id]
    return e ? (e.totalSuccessfulTransits * avgPayload) / (durationSec * 1e6) : 0
  }
}
const budget = pkg.budget ? evaluateBudget(studentTopology, pkg.budget, ctx) : undefined
```

### 4c. Live meter limitation (call it out in UI)

The pre-run meter can't know real per-edge throughput. Options, cheapest first:
1. **Show base+capacity live; add network after Run** - the graded contract has the full
   cost; the meter shows a `+ network (run to measure)` line.
2. **Static estimate** - propagate `baseRps × avgPayload` along routed edges (approximate;
   ignores cache hit-rates / conditional routing). More work, less accurate.

Recommend option 1 for correctness; the network lesson lands at grade time anyway.

### 4d. De-risk the traffic math *before* the UI/re-author work

`chatty-services` (§6) is the only question that validates the whole traffic model, and
it's scheduled last - so if the coarse `avgPayload` proxy (§1a) can't actually separate a
thin-edge reference from a fat-edge foil, you wouldn't find out until after building the
UI and re-authoring. **Front-load the risk:** during Phase 3, build a throwaway
`chatty-services` fixture (reference + fat-link foil) and run it through
`gradeAttemptWithArtifacts` purely to confirm `foilCost > referenceCost` by a comfortable
margin *on the traffic term alone*. Only once the traffic math demonstrably discriminates
do you commit to §7 (UI) and §6 (re-author). If it doesn't discriminate, that's the
signal to invest in per-edge payload tagging before shipping traffic-weighted edges.

---

## 5. Phase 4 - the non-binding-budget guardrail

Because `authoringValidator.validateAuthoredQuestion(pkg)` only sees the **package**
(not topologies), the discrimination checks live in the **harness**, fed by a pure helper
in `budget.ts`:

```ts
export interface BudgetDiscriminationInput {
  budget: Budget
  referenceCost: number   // budgetBreakdown(reference).actual
  foilCost?: number       // budgetBreakdown(foil).actual
}
export function validateBudgetDiscrimination(i: BudgetDiscriminationInput): AuthoringDiagnostic[]
```

| Code | Condition | Severity |
|------|-----------|----------|
| `budget.non_binding` | `referenceCost / cap < 0.6` | error |
| `budget.misaligned` | `foilCost !== undefined && foilCost <= referenceCost` | error |
| `budget.no_foil` | `unit==='cost'` and no `budget-foil-topology.json` | error |
| `budget.wrong_unit` | `unit==='cost'` but the reference's nodes span **< 2 distinct base values** | warning (advisory) |

Wire into `scripts/validate-question-dir.ts`: if `pkg.budget`, load
`budget-foil-topology.json` (if present), compute both costs via `budgetBreakdown`
(using the **full grade-time cost** incl. traffic - see §1c), run
`validateBudgetDiscrimination`, and fail the run on any error. Add a regression test that
feeds the old `async-sla` 36/600 config and asserts `budget.non_binding` fires.

The first three checks are load-bearing and would have flagged both V1 questions on day
one. **`budget.wrong_unit` is advisory and on probation** - "< 2 distinct base values" is
a weak proxy (a legit `client(0)→svc(2)→db(6)` reference has three distinct bases yet may
still be a node-count lesson), so it can miss real cases and add noise. Ship it as a
warning; **drop it if it doesn't earn its place.**

> **Property test - cap-last must never trip its own guardrail.** The cap-last rule
> (`cap = round(C_ref × 1.15)`, §6) and the `non_binding` threshold (`C_ref/cap < 0.6`)
> were written independently. They're consistent today (`C_ref/round(C_ref×1.15) ≈ 0.87`;
> at small costs the `round` drops the cap, which pushes the ratio **up** toward 1.0, not
> down - the dangerous direction, a ratio < 0.6, needs the cap to round *up* substantially,
> which `1.15×` can't do). But don't hard-code a bound (the true min across 1..100 is well
> above 0.6): assert the relationship, not a number. Add a property test:
> `for C_ref in 1..100: validateBudgetDiscrimination({ referenceCost: C_ref, cap: round(C_ref*1.15), … })` must **not** emit `budget.non_binding`.
> This locks the two constants together so a future tweak that breaks the relationship
> fails CI instead of shipping a self-contradicting authoring rule.

---

## 6. Phase 5 - re-author the questions (`gen-question-fixtures.ts`)

Budget questions become a **quad** (question + reference + gamed + budget-foil). In the
generator's builder for each budget question:

- add `budget: { unit: 'cost', cap: <cap-last> }` to the package (via `patchQuestion` or
  the builder), with `cap = round(referenceCost × 1.15)`;
- emit a `budget-foil-topology.json` (correct on other axes, expensive route);
- keep `gamed-topology.json` as the intended-axis foil (unchanged).

Concrete targets (numbers from the design §7, re-measured with the model in §3):

| Question | Reference | Foil | Cap | Depends on |
|----------|-----------|------|----:|-----------|
| `async-sla` | client→svc→queue→worker→relational-db (`C_ref≈16`) | sync client→svc→relational-db ×3 (`C_foil≈22`) | 18 | Phase 2 |
| `sensor-store` | client→svc→time-series-db (`C_ref≈8`) | client→svc→relational-db ×3 (`C_foil≈20`) | 10 | Phase 2 **+ `storageProfile` trait** |
| `chatty-services` *(new)* | client→svc-a→cache→svc-b (`C_ref≈9`) | client→svc-a→svc-b fat ≈300 MB/s link (`C_foil≈12`) | **10** | Phase 3 (traffic edges) |

> `sensor-store` only becomes a *strong* budget question once `storageProfile` (see
> `node-capability-matrix.md`) makes the relational write path physically slower - until
> then the foil is only *pricier*, not *slower*. Ship `async-sla` (Phase 2) first.

Then run `validate-question-dir.ts` over each: reference within budget + passing; gamed
fails intended axis; budget-foil over budget.

---

## 7. UI changes (`BudgetMeter.tsx`, `QuestionPanel.tsx`)

- **Model-aware footnote** - replace the hard-coded `1 + replicas + ⌈workers/50⌉` string
  (§3d).
- **Per-type / per-edge breakdown** - the breakdown table already renders `item.formula`
  + `item.cost`; Phase 2/3 formulas make it show `relational-db ×3 = 18` and
  `svc-a→svc-b link = 6`. No structural change, just richer data.
- **Ungraded footprint mode (optional)** - today `BudgetMeter` requires `budget.cap`.
  To show a no-cap footprint on any question, make `cap` optional in the component and
  render the total without the pass/fail band. Small, separable.
- **Author-mode calibration hint** - show `C_ref`, `C_foil`, `C_ref/cap` when
  `environmentProfile.mode === 'AUTHOR'`, so the cap can be seen to bite before shipping.

---

## 8. File-touch summary

| Phase | budget.ts | question.ts | authoringValidator.ts | validate-question-dir.ts | gen-question-fixtures.ts | BudgetMeter.tsx | tests |
|------:|:--------:|:-----------:|:---------------------:|:------------------------:|:------------------------:|:---------------:|:-----:|
| 1 nodes | - | - | - | - | ✎ author | - | - |
| 2 cost model | ✎ tables+`estimateNodeCost`+breakdown | - | - | - | - | ✎ copy | ✎ `budget.test` |
| 3 traffic | ✎ `BudgetContext`+`edgeCost` | ✎ ctx from `perEdge` | - | - | - | ✎ meter note | ✎ |
| 4 guardrail | ✎ `validateBudgetDiscrimination` | - | ✎ diagnostic codes | ✎ wire + fail-on-error | - | - | ✎ authoring+regression |
| 5 re-author | - | - | - | ✎ load `budget-foil` | ✎ budget + foil topo | - | ✎ e2e |

---

## 9. Backward compatibility & determinism

- **No schema change** to `Budget` (`{ unit, cap }`) - the cost model is internal to
  `budget.ts`. Existing question JSON stays valid.
- **Unlisted types → `DEFAULT_BASE = 1`**, absent edge traffic → `EDGE_BASE` only - so
  the model runs on any topology without re-authoring.
- **Determinism:** the traffic term reads `SimulationOutput.perEdge`, which is already a
  product of the seeded run - no new randomness, fully reproducible. Budget stays a
  deterministic function of (topology, [seeded sim output]).
- **Purity boundary:** keep `evaluateBudget(topo, budget)` (no ctx) pure for the live
  meter; the 3-arg form is only called at grade time.

---

## 10. Definition of done (mapped to code)

1. `estimateNodeCost` uses `BASE[type] × replicas + ⌊workers / capacityUnit⌋`; `budget.test.ts` green.
2. `evaluateBudget`/`budgetBreakdown` accept optional `BudgetContext`; `gradeAttemptWithArtifacts` supplies per-edge throughput from `SimulationOutput.perEdge`.
3. `validateBudgetDiscrimination` exists + wired into `validate-question-dir.ts`; the old
   `async-sla` 36/600 config **fails authoring** (regression test).
4. `async-sla` re-authored as a real budget question (reference within cap, `budget-foil`
   over cap) - proven by the harness.
5. `BudgetMeter` footnote + breakdown reflect the per-type/per-edge model.
6. `budget:{unit:'nodes'}` documented as the anti-kitchen-sink tool.

---

## 11. Review resolutions (incorporated)

| # | Reviewer point | Resolved in |
|---|----------------|-------------|
| 1 | `avgPayload` presented as truth, not proxy | §1a coarse-proxy warning (relative order is the lesson) |
| 2 | Meter/cap-last/guardrail may read divergent costs | §1c "which cost each consumer reads" - **cap + guardrail use full grade-time cost; meter is a degraded preview**; author hint shows full `C_ref` |
| 3 | `capacityUnit` fallback can misclassify stateful as cheap | §3a explicit `?? CAPACITY_UNIT_STATELESS` + guard + required unknown-type / missing-category tests |
| 4 | `wrong_unit` underspecified / may be noise | §5 tightened to "< 2 distinct base values" **and marked advisory / on probation** |
| 5 | Traffic math validated last (Phase 3) - risk | §4d front-load a throwaway `chatty-services` fixture to prove `foilCost > refCost` on the traffic term before UI/re-author |
| + | How `replicas`/`workers` reach `estimateNodeCost` | §3e live-feedback loop - defaults, edit path, and the two build-time checks |

**Gating order per the review:** land §1c (point 2) and §3a (point 3) *before* authoring
any cap; the rest can ride along.

### Second review round (numbers stress-test)

| Reviewer point | Resolved in |
|----------------|-------------|
| §8 computed `C_ref` with thin edges (the number §1c forbids) | §8 rewritten to show the **full grade-time cost** with capacity + per-edge traffic terms explicit; `C_ref=16` now holds because async traffic (~1.5 MB/s) genuinely floors to 0 |
| Root cause: `⌈⌉` makes thin-edge=1 / capacity=0 impossible | **Operator changed to `⌊⌋` (floor)** in `estimateNodeCost` (§3b) and `edgeCost` (§4a) + math doc §0 - reconciles the formula with the design's own "1 KB/s link adds 0" |
| `chatty-services` had no cap / no cost (highest model risk, least specified) | Worked cost table added (math doc §8b) + §6 cap set (`C_ref≈9`, `cap=10`, `C_foil≈12`) with an explicit **integer-gap** check |
| §4d validates discrimination, not calibration | §8b adds the integer-gap check the throwaway fixture must also satisfy |
| cap-last vs `non_binding` interaction safe but untested | §5 **property test** - cap-last output never trips `non_binding` for `C_ref ∈ 1..100` |
| foil replicas may not serialize to `resources.replicas` | §3e Phase-5 e2e assertion - `budgetBreakdown(foil)` db item must equal `BASE × 3` |
| `object-storage` base 2 = cache 2 undersells the tier story | flagged as a known compression in the math doc `BASE` table (split later if a question needs it) |

### Third review round (numbers foot end-to-end)

| Reviewer point | Resolved in |
|----------------|-------------|
| §8 table didn't sum to its stated total (worker@100, db@60 charged capacity; total 19 vs claimed 16) | math §8 **rewritten with sub-unit sizing** (worker 80, queue/db 20) so capacity = 0 on every row and the table **foots to 16**; adds a "to scale past the unit, add the term" note with worked 8/14 examples |
| `queue` row used the stateless unit - it's stateful (25), so "or 5" was really "or 14" | math §8 row now labels `queue` **stateful (unit 25)** and both stateful rows show the 25 unit |
| `chatty-services` foil assumed to pass other axes | math §8b **precondition** - the fat link must be *fast enough to pass perf but too expensive to afford*, else it collapses into the gamed topology |
| `non_binding` property-test bound stated as ≥ 0.75 (wrong bound) | impl §5 reworded - "assert the relationship, not a number; let the test surface the true min" |
| `durationSec` window ambiguity (25 s vs `simulationDuration`) | math §6/§8 - **duration cancels** on a constant source (`MBps ≈ baseRps × avgPayload / 1e6`); §6 names the window-match requirement |

# NS-Simulator - Curriculum, Documentation Index & "Why This Works"

> **What this is.** The single navigational + teaching spec for the whole system: a
> bottom-up lecture curriculum, an annotated map of every doc in this repo, and the
> intellectual case for *why a "LeetCode for system design" is even possible* - the
> math, the creative solutions, the determinism strategy, and the answer to every
> "this can't be simulated/graded" objection.
>
> **How to use it.** Engineers/authors onboarding → read Part I in order. Navigating
> the docs → Part II. Defending the approach to a skeptical instructor / teaching the
> keynote → Part III. Each part cross-links to the deep specs.
>
> **Running examples** throughout: `cache-placement` (read-heavy, cache-shields-DB)
> and `url-shortener` (point-lookup store-fit + read cache).

---

# Part I - The Lecture Curriculum

**Course:** *How the System Design Simulator Works - from event loop to authored question.*
**Audience:** engineers + content authors. **Prereqs:** basic queueing intuition, TypeScript, React basics.
**Spine:** one request's journey → one node's physics → one topology's cost/metrics → one graded question → the product around it.
**Per-lecture format:** Objectives → Concepts → Source of truth (files) → Live demo → Exercise.
**Shape:** ~12 lectures (75 min) or a 3-day workshop.

### Module 0 - Orientation & Mental Model *(0.5 lec)*
- The product: design an *architecture* (nodes/edges/sizing), not code; the sim runs load and grades it.
- The three honesty claims: (1) every number is physically derived + shows provenance; (2) concurrency/cost are hardware consequences, not free dials; (3) a question is "authored" only when a good design passes and a gamed one fails.
- Repo map: `src/engine/*` (headless sim + grading), `src/renderer/*` (React app), `ns-simulator-docs/*` (specs), `system-design-simulator-questions/*` (bank).
- Two runtimes: headless engine (Node - tests + grading) vs browser app (Web Worker runs the *same* engine).

### Module 1 - Discrete-Event Simulation Core *(1 lec)*
- DES: an event queue ordered by *simulated* time; the clock jumps event→event.
- Determinism: seeded RNG (`global.seed`), why fixing the seed kills seed-farming.
- Time model: `timeResolution`, `simulationDuration`, `warmupDuration` and why warmup is excluded (transient vs steady state).
- Run boundary: `SimulationEngine(topology).run()` → `SimulationOutput`.
- **Source:** `engine.ts`, `core/*`. **Demo:** run cache-placement reference headless. **Exercise:** reseed → identical stats.

### Module 2 - Request Lifecycle & Terminal Taxonomy *(1 lec)*
- The journey: source → edge transit → arrival → admission → queue wait → service → departure → next hop → terminal.
- Closed terminal taxonomy: `success`, `timeout`, `capacity_exceeded`/`queue_full`, `oom`, `connection_reset`, edge failures - why *closed* = honest error accounting.
- Deadlines, request identity (`type`, `sizeBytes`).
- **Source:** `core/events.ts`, `arrival-departure-and-request-lifecycle-semantics.md`. **Demo:** timeout vs OOM.

### Module 3 - The Queueing Model (G/G/c/K) *(1 lec)*
- Node = queue: `c` servers, `K` capacity, FIFO. Why G/G/c/K (general arrival/service, finite servers/buffer).
- **Utilization as a time-weighted integral** `∫busy dt / (c·T)` - not a snapshot (the honesty rule).
- Little's Law as an invariant check.
- **Source:** `GGcKNode.ts`, `queue-depth-calculation.md`, `throughput-calculation.md`.
- **⚠️ Teach the live bug:** a saturated node can currently *report* low utilization while queueing heavily (util denominator vs scheduler's derived `c`) - why url-shortener's API Server fails p99 while showing "HEALTHY".

### Module 4 - Nodes, Component Types & Service Time *(1 lec)*
- Palette types + categories (compute / storage-and-data / network-and-edge / …).
- `processing.distribution`: constant vs exponential; heavy-tail intuition (exp p99 ≈ 4.6× mean); `TYPE_MEAN_SERVICE_MS`, category floors.
- Palette seeding (`buildSeededSimulationConfig`, `paletteTemplates.ts`).
- **Source:** `componentSpecs.ts`, `node-capability-matrix.md`. **Exercise:** predict a path's p99 from per-hop means.

### Module 5 - Instance Model & Derived Concurrency *(1 lec - crown jewel)*
- Derive-and-lock: pick `instanceType` + `instanceCount`, everything follows.
- Catalog (t3/m5/c5/r5/x1e): vCPU/RAM/$/perfFactor, curated, frozen, price-proportional.
- `effectiveC = vCPU × count × workersPerVcpu`; `effectiveK = max(c, memCeiling)`, `memCeiling = totalRAM ÷ perRequestMemMb`.
- `perfFactor → serviceTimeMultiplier = 1/effectivePerf`. Legacy nodes fall back to raw `queue.workers`.
- **Source:** `instanceCatalog.ts`, `resourceDefaults.ts`, `resourceDerivation.ts`, `resource-allocation-and-derived-concurrency.md`. **Demo:** scale url-shortener API Server c5.large ×1→×4 → p99 156ms→21ms.

### Module 6 - Execution Profiles: CPU-bound vs IO-bound *(0.5 lec)*
- cpu-bound = 1 worker/vCPU (occupies core); io-bound = 32/vCPU (waits on I/O, multiplexes).
- Per-tier defaults: compute processors → cpu-bound; sources/stores/caches/network/messaging → io-bound.
- "One number, many labels": workers/connections/consumers/ops = same derived `c`.
- Bottleneck lever: flip a store to cpu-bound on a small instance (cache-placement's t3.small DB). The lock: `canEditExecutionProfile`.
- **Source:** `execution-profile-and-node-concurrency.md`.

### Module 7 - Edges: Network Physics vs Dumb Connectors *(1 lec)*
- Edge properties: latency (path-type constant vs log-normal), `pathType` (same-rack…internet), bandwidth, `maxConcurrentRequests`, packet loss, error rate.
- Path-type inference from Region/AZ/Subnet composite placement.
- Conditional routing (`condition: request.type === "read"`) - mix only matters when the topology routes on type.
- `edgeModel`: network vs connector (connector = zero physics/cost).
- **Source:** `edge-properties-and-defaults.md`, `edgeLensPresentation.ts`, `request-flow-direction-and-topology-rules.md`.

### Module 8 - Traits: Pluggable Node Behaviors *(1 lec)*
- Trait system: `NodeBehaviourTrait` hooks (`beforeArrival`…) + capability modules (config panels).
- Cache trait (deep): inline pass-through - hit served locally (`handled`), miss `continue`s downstream; no conditional edges needed.
- Other traits: cold-start, health-aware routing, content routing, service-time overrides.
- **Source:** `traits/*`, `trait-integration-guide.md`, `node-behaviour/*`. **Exercise:** vary `cacheHitRate` 0.5→0.9 → DB load moves.

### Module 9 - Cost Model & Budgets *(0.5 lec)*
- Provisioned: `pricePerHour × count × pricingMultiplier` (on-demand/reserved/spot).
- Per-type `costModel`: provisioned / consumption (serverless per-request) / volume (CDN/object-storage per-GB) / none (sources).
- Egress per-edge by pathType (estimate pre-run, measured post-run).
- Budgets: `resourceBudget` (vCPU/RAM) vs `costBudget` ($/hr), independent; graded `budget.unit:"cost"` v1 heuristic vs live chip.
- **Source:** `cost.ts`, `cost-calculation-and-budgeting.md`, `budget/*`.

### Module 10 - Metrics, Aggregation & the Honesty Doctrine *(1 lec)*
- Per-node/per-edge/summary/invariant metrics; windowed post-warmup, time-weighted integrals, percentiles that don't sum across hops.
- Honesty roadmap: failure-mode taxonomy, cause splits, provenance-on-every-number; the point-sampled-scalar anti-pattern.
- **Source:** `metrics.ts`, `analysis/output.ts`, `simulation-validation-and-pattern-accuracy.md`.

### Module 11 - Workload & Scale *(0.5 lec)*
- Where load lives: `suite.cases[].workload` (question-owned, injected) vs the student's dry-run scenario.
- `requestDistribution` (typed classes, weights, `sizeBytes`); patterns (constant/poisson/bursty…).
- Tractable vs display scale: `baseRps` ~2-5k vs `prompt.scale.peakRps`. **The trap:** dry-run at 100 rps looks fine; graded peak at 2k saturates.
- **Source:** `request-type-model.md`, `request-pattern-configuration.md`.

### Module 12 - The Grading DSL & Anti-Gaming *(1 lec)*
- Five orthogonal axes: Topology (structural), Scale-fit (semantic/storageFit), Simulation (rubric), Justification, Budget.
- Structural rules, semantic criteria (placement/guardedPath/fanout/storageFit/forbidUnjustified), `hardFail` + short-circuit order.
- Rubric verdict keys (`summary.latency.p99`, invariants); performance-vs-correctness boundary.
- The Dual-Topology Rule: reference PASSES, gamed FAILS on the intended axis; `validate-question-dir`.
- **Source:** `structural.ts`, `semanticCriteria.ts`, `rubric.ts`, `authoringValidator.ts`, **`evaluation-authoring-reference-manual.md`** (master DSL).

### Module 13 - Environment Profiles & Capabilities *(0.5 lec)*
- Modes AUTHOR/ASSIGNMENT/PRACTICE; deployed default (PRACTICE + connector).
- Capabilities: editPaletteList, canEditScaffoldNodes, canEditEdges, canEditResources, canEditExecutionProfile, edgeModel, maxTestRuns, budgets, visibility.
- Domain overrides: `network`→editable edges, `cost`→editable resources.
- **Source:** `environmentProfile.ts`, `environment-definition-and-configuration-model.md`, `system-design-leetcode-environment-model.md`, authoring manual §10.

### Module 14 - Frontend Architecture *(1 lec)*
- App shell: React + Zustand (`useStore`), canvas (ReactFlow), Web Worker (`useSimulation`), serialization (`useTopologySerializer`).
- Metric lenses: pre-run (Instance/Concurrency/QueueCapacity/Timeout/Cost) vs runtime (Traffic/Saturation/Latency/Errors/Throughput).
- Panels & chrome: properties panel, simulation tray, header (cost chip, mode badge, settings modal), theming.
- **Source:** `src/renderer/src/{store,hooks,components}`, `canvas-visualization-and-ux-simplification.md`, `settings-modal-feature-spec.md`.

### Module 15 - Newton Integration & Authoring Workflow *(1 lec - authors)*
- Two authoring shapes: standalone `question.json` vs Newton Django rows (SIMULATOR_CONFIG + STRUCTURAL_RULE/SEMANTIC_CRITERION/RUBRIC_CHECK) + host contract.
- Bridge: `newtonGamePlayground.ts` (`parseNewtonSeed`, `buildQuestionPackageFromRows`), host messaging, `environmentProfile` passthrough.
- Loop: author terse → validate (`parseQuestionPackage` + `validateAuthoredQuestion`) → dual-topology grade → ship rows.
- **Source:** authoring manual §11, `newton-api-backend-integration.md`, `authoring-a-simulator-game-question-runbook.md`.

### Capstone - Author a question end-to-end *(1 lec / lab)*
Fresh problem (e.g. write-heavy sensor store): prompt + FR/NFR/scale → choose discriminating axes → author reference + gamed → tune the bottleneck via the instance model → validate dual-topology → convert to Django rows.

### Tracks
- **Engineers (full):** Modules 0-15 + capstone (~2.5 days).
- **Content authors (fast):** 0, 4-6, 8, 9, 11, 12, 13, 15, capstone (~1 day).
- **Product/PM overview:** 0, 5-6, 10, 12, 13 (~half day).

### Recurring threads (call out every lecture)
1. **Honesty** - every number derived + provenance (M3, M5, M10).
2. **You can't fake it** - concurrency & cost cost money (M5, M6, M9).
3. **Discrimination** - good passes, gamed fails (M12).
4. **Known gaps** - the utilization-display bug + the dry-run-vs-graded-load trap; teach them openly.

---

# Part II - Annotated Documentation Index

Legend: **[canonical]** current source of truth · **[primer]** teaching/first-principles · **[design]** spec/ADR · **[history]** planning/roadmap (context, may be stale).

## Backing reading per module

**M0 Orientation:** `README.md` [canonical] docs index · `docs/SYSTEM_OVERVIEW.md` [primer] plain-English how-it-works · `system-mind-map.md` [primer] whole system on one page · `docs/theoretical-foundations.md` [primer] concept vocabulary · `guides/v1-scope-and-roadmap.md` [history] V1 vs future · `design-decisions/governing-principles.md` [design] north-star principles.

**M1 DES core:** `docs/README.md` [primer] first-principles guide index · `docs/01-system-diagrams.md` [primer] system design→DES · `docs/02-simulation-fundamentals.md` [primer] the event loop/clock/RNG · `docs/05-devs-chaos-and-analysis.md` [primer] DEVS formalism + output analysis.

**M2 Lifecycle:** `specs/arrival-departure-and-request-lifecycle-semantics.md` [canonical] arrival→terminal semantics · `specs/request-rejection-behaviour.md` [canonical] rejection rules · `docs/03-data-structures-and-mechanics.md` [primer] event/request data structures.

**M3 Queueing:** `specs/queue-depth-calculation.md` [canonical] · `specs/throughput-calculation.md` [canonical] · `specs/simulation-validation-and-pattern-accuracy.md` [canonical] validation vs expected behavior.

**M4 Nodes:** `specs/node-capability-matrix.md` [canonical] which behaviors each type has · `specs/node-behaviour/node-behaviour-specification.md` [canonical] node behavior architecture · `specs/default-driven-simplification-layer.md` [canonical] default derivation · `canonical-catalogue/README.md` [canonical] the component catalogue · `schema/README.md` [canonical] schema entry point.

**M5 Instances:** `specs/resource-allocation-and-derived-concurrency.md` [canonical] the crown-jewel spec.

**M6 Execution profiles:** `specs/execution-profile-and-node-concurrency.md` [canonical] cpu/io-bound explainer.

**M7 Edges:** `specs/edge-properties-and-defaults.md` [canonical] · `specs/request-flow-direction-and-topology-rules.md` [canonical] directionality + routing.

**M8 Traits:** `specs/trait-integration-guide.md` [canonical] trait system + cohesion · `docs/04-distributed-systems-and-failures.md` [primer] advanced behaviors/failures.

**M9 Cost:** `specs/cost-calculation-and-budgeting.md` [canonical] · `specs/budget/budget-cost-model-math.md` [canonical] all the cost math · `specs/budget/budget-feature-consolidated-design-v3.md` [design] · `specs/budget/budget-feature-implementation-v3.md` [design] code-level · `specs/real-world-fidelity/real-world-fidelity-and-iac-export.md` [design] telemetry map + IaC · `planning/budget-feature-review.md`, `planning/budget-v2-design.md` [history].

**M10 Metrics:** `docs/05-devs-chaos-and-analysis.md` [primer] output analysis · `specs/event-debugger-schema.md` [canonical] per-event telemetry model · `specs/event-debugger-prototypes.md` [design] debugger/log UI · `generated/notionlite-multiregion-simulation.md` [primer] worked output example · `stitch_simulation_output_analysis/` [history] analysis artifacts.

**M11 Workload:** `specs/request-type-model.md` [canonical] · `specs/request-pattern-configuration.md` [canonical] arrival patterns · `specs/question-simulation-alignment.md` [canonical] scale/mix alignment (the 99:1 display-only gap).

**M12 Grading DSL:** `specs/evaluation-authoring-reference-manual.md` [canonical] ⭐ master DSL · `specs/question-grading-model-and-anti-gaming.md` [canonical] grading + gaming defenses · `specs/rubric-engine-and-question-platform-architecture.md` [canonical] rubric internals · `specs/question-creation-feature-spec.md` [design] · `specs/question-families-and-bottlenecks.md` [canonical] archetype→bottleneck map · `specs/question-bank-initial-game-states.md` [canonical] 12 archetypes + validation status · `specs/worked-example-order-processing-question.md` [primer] end-to-end example · `design-decisions/adr-generalized-simulator-question-evaluation-framework.md` [design] · `docs/question-platform-hardening/{01-05,README}.md` [history/primer] PR-by-PR hardening guide.

**M13 Environment:** `specs/environment-definition-and-configuration-model.md` [canonical] · `specs/system-design-leetcode-environment-model.md` [canonical] mode/lens model · `docs/question-platform-hardening/08-environment-profile-presentation-layer.md` [canonical].

**M14 Frontend:** `specs/canvas-visualization-and-ux-simplification.md` [canonical] · `specs/settings-modal-feature-spec.md` [canonical] · `specs/terminal-feature-spec.md` [design] in-app terminal · `design-decisions/adr-state-management.md` [design] Zustand+XState · `design-decisions/adr-no-custom-change-detection.md` [design] engine↔UI reactivity · `design-decisions/adr-ui-architecture-review.md`, `adr-critical-problems.md`, `ISSUES.md` [design/history] UI review + issues · `design-decisions/adr-canonical-node-architecture-refactor.md` [design] engine-first discriminated-union node model.

**M15 Newton/authoring:** `specs/newton-api-backend-integration.md` [canonical] · `specs/authoring-a-simulator-game-question-runbook.md` [canonical] · `specs/PROMPT_TEMPLATE.md` [canonical] feature-spec template · `docs/question-platform-hardening/06-...persistence...envelope.md` [canonical] grading-safe persistence · `docs/question-platform-hardening/07-production-embed-runtime-and-origin-security.md` [canonical] embed + origin security · `examples/url-shortener/README.md` [primer] runnable example.

**Capstone/teaching:** `guides/teacher-manual.md` [canonical] · `guides/student-guide.md` [canonical] · `planning/course-integration-plan.md` [history].

## Cross-cutting sets

**Authoring "skills" (agent/Claude accelerators - author track, ties to M4/M12/M15).** Each is `skills/<name>/SKILL.md` + a `references/` cheatsheet: `topology-json-author` (valid topology JSON), `scenario-composer` (workload scenarios), `component-taxonomy-selector` (pick node type), `cost-and-provider-mapper` (real cloud pricing), `invariant-policy-checker` (grading invariants), `failure-propagation-analyzer` (fault spread), `resilience-pattern-tuner` (retries/breakers), `chaos-experiment-designer` (fault cases), `simulation-output-analyst` (read run output), `schema-catalog-sync-guard` (schema↔catalog drift), `dsds-ui-spec-to-component` + `ticket-implementation-copilot` (dev helpers). Index: `skills/README.md`.

**Architecture ADRs (instructor deep-prep, M0/M14):** `design-decisions/adr-internal-modularity-over-plugin-system.md` [design] engine generalization; plus the UI/state/node ADRs under M14.

**Planning / history (context only, likely partly stale):** `planning/IMPLEMENTATION_PLAN.md`, `TICKETS.md`, `execution-roadmap-tasks.md`, `question-platform-evaluation-framework-backlog.md`, `v1-launch-checklist.md`, `analysis/meeting-feedback-analysis.md`.

> **Freshness caveat:** `specs/*` are the live source of truth; `planning/*` and the older `docs/question-platform-hardening/*` are historical context. When a spec and a plan disagree, the spec wins.

---

# Part III - Why This Works: Math, Creative Solutions & the Skeptic's FAQ

*(This part also stands alone as the argument in `why-this-works-math-tricks-and-skeptics-faq.md`.)*

There is no standard "LeetCode for system design" - no compile/run, no single right answer, an unbounded design space, and the interesting skill (scaling tradeoffs) looks un-gradeable. Here is how we made it work.

## A. The math we actually run

1. **Discrete-event simulation (DES).** A priority queue of events in *simulated* time; the clock jumps event→event. The DEVS formalism used in real capacity planning - not an animation.
2. **Queueing theory - every node is a G/G/c/K station.** `c` servers, `K` capacity, FIFO. **Little's Law** `L = λ·W` as an invariant check. **Utilization = time-weighted integral** `ρ = ∫busy dt / (c·T)`, not a point sample.
3. **Derived concurrency.** `effectiveC = vCPU × instanceCount × workersPerVcpu` (1 cpu-bound / 32 io-bound); `effectiveK = max(c, ⌊totalRAM/perRequestMemMb⌋)` (RAM sets admission → `oom`).
4. **Service-time tails.** For exponential service, `p99 ≈ mean × ln(100) ≈ 4.6× mean` - why a chain of small means still yields a big p99. `serviceTimeMultiplier = 1/effectivePerf`, io-bound damped `effectivePerf = 1 + (perfFactor−1)×0.25`.
5. **Cache-aside as Bernoulli thinning.** A hit is served locally with probability `hitRate`; a miss `continue`s downstream. We never model the cache's *contents* - only which backend the request routes to (all the metric cares about).
6. **Cost & egress.** `cost = pricePerHour × count × pricingMultiplier`; egress `= bytes/duration × 3600 × $/GB` - upper-bound estimate pre-run, measured exactly post-run.
7. **Scale-invariance of discrimination.** We run ~2k rps not 200k because what matters is the **offered/capacity ratio**, preserved when rps and capacity downscale together.

## B. The creative mechanisms

1. **Grade the consequences, not the diagram.** Run load, measure whether it meets the SLO. **Physics is the impartial grader.**
2. **Five orthogonal axes (T/S/Σ/J/$).** Gaming one is caught by another; no single number to farm.
3. **The Dual-Topology Rule** - an *executable definition of a good question*: reference PASSES, a known gamed shortcut FAILS on the intended axis. The architecture-world equivalent of hidden test cases; if the gamed design passes, the question is rejected as under-constrained.
4. **Derive-and-lock** - the killer move. If workers were free, every bottleneck vanishes for free and nothing discriminates. Deriving capacity from a *priced, capped* catalog makes "more capacity" cost money and hit quotas. **Scaling becomes a real physical tradeoff** (the "company scale up/down exploration" answer).
5. **The performance/correctness boundary.** Simulate what queueing physics can decide; *refuse* to fake what it can't (exactly-once, ordering) - those go to topology + justification. Honesty about the boundary is a feature.
6. **Topology-as-proxy.** "Generate a unique code" isn't simulatable, but "a durable store on the write path" is - a structural proxy + justification prompt carries the nuance.
7. **Deterministic justification grading (no LLM).** Name a component actually in the graph (anti-BS) + cite a real scale number + state a tradeoff. Reproducible.
8. **Question-owned injected workload.** The student can't lower load, reseed, or change the mix - the suite is injected over *their* topology at grade time.

## C. Determinism & continuous distributions in JS - no floating-point drift

**The question.** How do you sample continuous PDFs (arrival/service times) in a deterministic JS environment without accumulating floating-point drift over millions of events?

**The answer - three layers keep it exact:**

**1. An integer-only PRNG (no float state).** Seeded via `xmur3(seedString)` → `sfc32(a,b,c,d)`. The generator's *state* is four 32-bit unsigned integers evolved with `Math.imul`, shifts, XOR, and `>>> 0`. **No float ever enters the recurrence**, so the random stream is bit-identical on every V8/JSC platform and cannot drift no matter how long it runs. Only the *final* step divides to `[0,1)`: `t / 4294967296` - a single deterministic IEEE-754 op.
*Lives in `src/engine/stochastic/random.ts`.*

**2. Standard inverse-transform / transform sampling, built from that one uniform.** Continuous distributions are drawn from `rng.next()`:
- **Exponential** (arrival & service): inverse-CDF `−ln(1−U)/λ`.
- **Normal:** Box-Muller `√(−2 ln U₁)·cos(2πU₂)`; **log-normal** = `exp(normal(μ,σ))`.
- **Weibull:** inverse-CDF `scale·(−ln(1−U))^{1/shape}`; **Gamma:** Marsaglia-Tsang acceptance-rejection.
- Config-dispatched by `distribution.type` (`constant | exponential | log-normal | …`).
*Lives in `src/engine/stochastic/distribution.ts`.*

**3. The simulation clock is BigInt microseconds - floats never accumulate.** This is the crux. The *accumulating* quantity - the event-loop clock and every scheduled time - is **`bigint` integer microseconds** (`this.clock`, `simulationDurationUs`, `interArrivalUs`, `latencyUs`, `totalQueueTime`, `totalServiceTime`, …). A sampled float duration is **quantized to whole microseconds the instant it enters the timeline**:
```ts
const interArrivalUs = BigInt(Math.max(1, Math.round(interArrivalMs * 1000)))
this.scheduleRequestGeneratedAt(currentTime + interArrivalUs)   // BigInt + BigInt - exact
```
So floating-point math is confined to a **single, non-accumulating leaf step** (drawing one duration). The moment that value joins the event queue it is an exact integer, and all subsequent arithmetic (ordering events, summing millions of durations, computing the busy-area integral) is **exact BigInt integer math**. There is no growing epsilon because nothing floating-point is ever summed.

**Why this fully answers the drift worry:**
- **Ordering** of events is exact (integer comparison) → the event sequence is reproducible.
- **Accumulation** (clock, busy-time integrals, totals) is exact (BigInt) → no epsilon growth over long runs.
- **Sampling** floats affect only the *value* of one duration, by at most sub-microsecond, and are **erased by µs quantization** (`Math.round(ms*1000)`, floored at 1µs).
- **Honest caveat:** the transcendental funcs (`Math.log/sqrt/pow/cos`) *can* differ in the last ULP across JS engines. Because every result is rounded to a whole microsecond before use, those sub-ULP differences vanish - reproducibility is guaranteed within an engine and effectively across engines. If we ever needed *bit-identical cross-engine* transcendentals we'd swap in a fixed-point/polynomial `log` (not currently necessary).

**Where it lives today:** `src/engine/stochastic/{random,distribution}.ts` (+ their `__tests__`), the BigInt clock in `engine.ts` and `core/types.ts`, and the quantization in `workload.ts`.
**The gap:** there is **no spec** that states this determinism contract (integer PRNG + BigInt clock + µs-quantized sampling) as a first-class invariant. It's correct in code and covered by unit tests, but a reviewer or new engineer has to reverse-engineer it. → Worth a short spec `simulation-determinism-and-numerics.md` (or a section in `simulation-validation-and-pattern-accuracy.md`) so "reproducible given a seed" is a documented guarantee, not folklore.

## D. The skeptic's FAQ - "this can't be simulated/graded" → the answer

> **"System design has no single right answer - you can't grade it."**
> We don't grade *the* answer; we grade whether the design **satisfies the requirements under load**. Constraint-satisfaction, not answer-matching - *any* topology that meets the SLO with the store shielded passes. Multiple valid solutions is a feature.

> **"You can't simulate a real distributed system in a browser."**
> We don't. We simulate the **queueing physics that decide whether it meets its SLO** - arrival, service, contention, saturation - on a tractable, proportionally-faithful slice. Well-founded DES/queueing theory; a calibrated instrument, not a cloud oracle.

> **"Correctness (exactly-once, no double-book) can't be simulated."**
> Correct - and we **don't fake it.** Hard boundary: performance → simulation; correctness → the required guard on the topology + a justification prompt. Never a correctness claim behind a latency number.

> **"Students will just game it / get lucky."**
> Multi-axis grading + Dual-Topology validation. Each question is authored so a known gamed shortcut fails on a specific axis; if it passes, the question is rejected. **Gaming is a bug we test for** before ship.

> **"Anyone can crank the servers up to pass."**
> Not anymore. Concurrency is derived from a priced, capped catalog - cranking "workers" does nothing, buying capacity costs money and can breach a budget/quota, and over-provisioning fails the **$** axis.

> **"Latency from a toy sim is meaningless."**
> It's **relative and physically consistent**, not an absolute prediction. The threshold is co-authored *with* the sim's numbers (reference passes with margin, gamed fails clearly), and every question is validated both ways.

> **"The real skill is the reasoning/tradeoffs - you can't grade that."**
> Deterministic justification grading does exactly that: name-a-real-node + cite-a-number + state-a-tradeoff. No LLM, fully reproducible.

> **"Scaling up vs out, cost tradeoffs - you can't explore those in a toy."**
> That's precisely what the instance model exposes: scale up (bigger SKU) vs out (more instances), cpu- vs io-bound, on-demand/reserved/spot, RAM ceilings → OOM, per-region egress. The learner watches **cost and SLO move together** - the real capacity-planning loop.

---

# Part IV - Where it lives today & the gaps (consolidated)

| Topic | Documented in | Gap |
|-------|---------------|-----|
| Queueing math (c/K, Little, utilization integral) | `queue-depth-calculation.md`, `throughput-calculation.md` | - |
| Derive-and-lock + instance model | `resource-allocation-and-derived-concurrency.md` | - |
| CPU/IO execution profiles | `execution-profile-and-node-concurrency.md` | - |
| Anti-gaming + Dual-Topology | `question-grading-model-and-anti-gaming.md`, authoring manual | - |
| Correctness boundary + scale trick | `question-simulation-alignment.md` | - |
| Honesty / no point-samples | honesty roadmap + memory notes | scattered |
| **Determinism & numerics (integer PRNG + BigInt clock + µs quantization)** | code + `stochastic/__tests__` | **no spec** → propose `simulation-determinism-and-numerics.md` |
| **Sim-core internals (M1-M3), Frontend wiring (M14)** | primers only | **no dedicated spec** |
| **The "why this works" argument (Part III)** | scattered across specs | **consolidated here**; can also live as `why-this-works-math-tricks-and-skeptics-faq.md` |
| **Known bugs** - utilization-display, dry-run-vs-graded-load | (this doc) | needs an issue + fix |

**Highest-leverage doc follow-ups:** (1) a determinism/numerics spec; (2) a sim-core spec for M1-M3; (3) split Part III into the standalone `why-this-works-math-tricks-and-skeptics-faq.md` for sales/skeptic-facing use.

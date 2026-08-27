# Trait Integration & Cohesion Guide

> Companion to `node-capability-matrix.md`. That doc says **what** to build; this
> one says **where it plugs in** so the whole simulator stays cohesive and nothing
> breaks - engine, config schema, UI, grading, and telemetry - when you add a new
> `🔧` trait or extend an existing one (`➕`).

## TL;DR - the good news

The trait system was designed as a plug-in layer, so **most of a new trait is
self-contained** and the **config UI is generated for free**:

- **Behavior** lives in one module under `src/engine/traits/`, registered in
  `capabilityModules.ts`, attached to component types via `appliesTo`.
- **Config UI renders automatically** - `src/renderer/src/config/fieldConfig.ts`
  reads each module's `config.sections` and builds the PropertiesPanel. Adding a
  `ConfigField` = a new labelled input appears. **No PropertiesPanel edits.**
- **Validation never breaks** - `node.config` is `z.record(z.string(), z.unknown())`
  in `validator.ts`, so new `sim.*` keys are accepted and every existing topology
  keeps loading.

The work that is **not** automatic - and where cohesion actually lives - is
**making the effect visible and gradable**: metrics, the verdict projection, the
event timeline, the on-canvas node lens, and determinism.

### Recently shipped on this surface

- `storageProfile` now makes store-fit decisions visible at runtime instead of
  leaving them only in rubric text.
- `broadcastFanout` now delivers one broker publish to every downstream subscriber.
- `idempotencyDedup` now models a keyed duplicate short-circuit on the write path.
- `retryBackoff` now models caller-owned retries with exponential backoff/jitter.
- `lockLease` now models per-key lease acquisition/contention/TTL for `distributed-lock`.
- `rate-limiter`, `circuit-breaker-controller`, and `distributed-lock` are now first-class palette/catalog nodes rather than generic placeholders.
- `Blueprints` in the library now reuse the question-brief workflow for
  requirements-first scaffolds.

---

## The trait pipeline today

A trait is a `NodeCapabilityModule` (`src/engine/traits/types.ts`) with two halves:

1. **`hooks`** - the physics. Three hook points fire during simulation:
   - `beforeArrival(ctx)` → delay / reject / mutate a request as it reaches the node
     (where you'd add a GC pause, a connection-pool wait, a cache-hit short-circuit).
   - `beforeRouting(ctx)` → change the routing decision.
   - `filterRoutes(ctx)` → drop candidate routes (fires in `src/engine/routing.ts`).
2. **`config`** - declarative `sections: ConfigField[]` (`path`, `type`, `label`,
   `why`, `altitude`), consumed by the UI.

Registration + resolution:

```
src/engine/traits/<trait>.ts          # the module (hooks + config + appliesTo)
        │
src/engine/traits/capabilityModules.ts  # TRAIT_CAPABILITY_MODULES (behavior)
        │                                # NODE_CONFIG_MODULES     (config UI)
src/engine/traits/resolveTraits.ts      # componentType → hooks (via appliesTo)
        │
engine.ts / routing.ts                  # calls the hooks per request
```

---

## Add-a-trait checklist (what to touch, and what's automatic)

| # | Layer | File(s) | Change | Automatic? |
|---|-------|---------|--------|:---------:|
| 1 | **Trait module** | `src/engine/traits/<trait>.ts` | Implement `hooks` + `config.sections` + `appliesTo` | - |
| 2 | **Register** | `src/engine/traits/capabilityModules.ts` | Add to `TRAIT_CAPABILITY_MODULES` (+ `NODE_CONFIG_MODULES` if it has config) | - |
| 3 | **Config validation** | `src/engine/validation/validator.ts` | *Nothing* - `node.config` is free-form `z.record` | ✅ auto |
| 4 | **Config UI** | `src/renderer/src/config/fieldConfig.ts` | *Nothing* - sections render from the module | ✅ auto |
| 5 | **Palette defaults** | `src/engine/catalog/paletteTemplates.ts` | Add sensible `seed`/default `sim.*` so a freshly-dragged node behaves | - |
| 6 | **Metrics** | `src/engine/analysis/output.ts` | Surface any new counter (e.g. pool timeouts, GC pauses) on `SimulationSummary` / per-node | needed if graded |
| 7 | **Verdict projection** | `src/engine/analysis/verdict.ts` | Add the metric to `projectToVerdict` so rubric `metric:` paths resolve | needed if graded |
| 8 | **Events / timeline** | `src/engine/core/events.ts`, `event-stream.ts`, `debugTypes.ts` | New event kind (e.g. `gc-pause`, `cache-stampede`) so the debugger renders it | optional but high-value |
| 9 | **On-canvas metric** | `RuntimeNodeMetrics.tsx`, `MetricLensSwitcher.tsx`, `LensMetricCard.tsx` | A lens/cell so students *see* the new metric on the node | needed to "feel" it |
| 10 | **ResultsTray** | `components/simulation/ResultsTray.tsx` | Overview/Bottlenecks row for the new effect | optional |
| 11 | **Tests** | `src/engine/traits/<trait>.test.ts` | Deterministic unit test of the hook | - |
| 12 | **Docs** | `node-capability-matrix.md` | Flip the node row to ✅, move the trait from 🔧 to shipped | - |

Steps **3 and 4 are free** - that's the cohesion win. Steps **6-9** are the ones
that make the trait *land* pedagogically; skipping them yields a trait that changes
numbers invisibly.

---

## Cohesion guardrails - what will break if you're not careful

1. **Determinism (the big one).** The engine is seeded and reproducible - grading
   depends on it. Any stochastic behavior (GC jitter, stampede, zipfian skew,
   packet loss) **must** draw from the engine's seeded source
   (`this.distributions.random()` in `engine.ts`), never `Math.random()`. A single
   unseeded call makes runs non-reproducible and flakes every rubric check.

2. **Metric-key drift.** A rubric check references `summary.<path>`. If a trait
   emits a metric that isn't added to *both* `output.ts` and `verdict.ts`, the check
   silently resolves to `undefined` and fails/errs. Always add the metric to the
   projection **in the same change** as the check. (This class of bug already bit us
   once - `summary.latencyP99Ms` vs `summary.latency.p99`.)

3. **Backward-compatible defaults.** All existing topologies and the 9 V1 questions
   must grade **identically** after the change. A new trait must be a **no-op at its
   default config** (e.g. `sim.gcPauseMs: 0`, `sim.maxConnections: ∞`). Traits added
   to already-used types (`relational-db`, `in-memory-cache`) especially must default
   to neutral. Re-run `validate-question-dir.ts` across all 9 to prove no drift.

4. **Warmup contamination.** Bursty traits (GC pauses, stampede spikes) inflate p99
   during the transient. The warmup advisor in `output.ts` already flags this; keep
   the injected suite warmup ≥ 10× the new max per-node p99.

5. **Budget interaction.** The cost heuristic (`budget.ts`) reads `replicas` +
   `workers` only. If a trait adds capacity via new config (e.g.
   `sim.replicationBandwidthMbps`), decide whether it should feed the cost model -
   otherwise students can buy durability "for free."

6. **Palette scope.** A trait that finally makes a hidden node meaningful (e.g.
   `dataSkew` on `shard-node`, or wiring `throttler`) is the trigger to add that
   type to `V1_PALETTE_NODE_TYPES` in `LibrarySidebar.tsx` **and** un-defer any
   question that needs it. Keep them out of the palette until the trait ships, or the
   node is a generic pass-through again.

7. **Grading axis alignment.** Correctness-style traits (`idempotencyDedup`,
   `lockLease`) now create real runtime behavior, but they are still graded mainly by
   **topology + justification**, not a single `summary.*` scalar. Performance traits
   (`storageProfile`, `connectionPool`, `gcJitter`) *are* graded by simulation metrics.

---

## UI changes, specifically

| UI surface | Auto or manual | What's needed |
|------------|:--------------:|---------------|
| **PropertiesPanel config** | ✅ auto | Fields render from `config.sections`. Use `altitude: 'advanced'` so deep knobs collapse; fill `why:` for the pedagogical tooltip. |
| **Node card metric (canvas)** | manual | Add a metric to `RuntimeNodeMetrics` + a `MetricLensSwitcher` lens (e.g. a "Connections" or "GC" lens) so the saturating node lights up. This is what turns a number into an "aha." |
| **ResultsTray** | manual | Optional Overview/Bottlenecks rows (e.g. "312 connection timeouts", "GC stole 8% of p99"). |
| **Event debugger timeline** | manual | Register the new event kind in `debugTypes.ts` so a `gc-pause` / `cache-stampede` glyph appears on the request timeline - the clearest "watch it happen" view. |
| **Question brief** | ✅ auto | New `sim.*` metrics referenced by NFRs/rubric already flow through the existing test-row rendering. |

**Rule of thumb:** the config panel is free; budget one UI task per trait to make the
effect *visible on the node* (lens) and one to make it *visible in time* (timeline
glyph). Without those two, the physics change is real but invisible.

---

## Worked example - `connectionPool` end to end

1. **Module** `src/engine/traits/connectionPool.ts`: `appliesTo:
   ['relational-db','api-gateway','microservice']`; `hooks.beforeArrival`: if
   in-flight ≥ `sim.maxConnections`, enqueue behind the pool (or emit
   `connection-timeout` past `processing.timeout`); `config.sections`:
   `sim.maxConnections` (input, `why: "Requests beyond the pool queue before app
   logic - head-of-line blocking"`), `sim.tcpHandshakeMs` (advanced).
2. **Register** in `capabilityModules.ts` (behavior + config).
3. **Defaults**: `paletteTemplates.ts` seeds `relational-db` with e.g.
   `sim.maxConnections: 100`; **default keeps existing behavior** if set high enough
   to be a no-op for current questions.
4. **Metric**: add `connectionPoolWaitP99` / `connectionTimeouts` to `output.ts`
   summary + per-node, and to `verdict.ts` (`perNode.<id>.connectionTimeouts`).
5. **Event**: add `connection-timeout` to `events.ts`/`debugTypes.ts` → timeline glyph.
6. **Lens**: a "Connections" lens in `MetricLensSwitcher` showing pool utilization.
7. **Determinism**: no randomness needed - pure counting, so trivially reproducible.
8. **Test** + flip `relational-db`/`api-gateway`/`microservice` rows to ✅ in the matrix.

A new question ("your service is CPU-idle but p99 is 2s - why?") now has a real,
feelable answer, and the fix (raise the pool / add a replica) is visible on the node.

---

## Recommended rollout order (keeps V1 green)

1. **`➕` extensions first** - extend `cache`/`keyBasedRouting`/`coldStart`/
   `contentRouting` `appliesTo`. No new engine code, no new metrics, low risk.
2. **Shipped foundation slice** - `storageProfile`, `broadcastFanout`,
   `idempotencyDedup`, `retryBackoff`, `lockLease`, plus the requirements-first
   `Blueprints` workflow.
3. **Delivery lifecycle expansion** - the queue path now ships producer
   ack/release plus delivery mode, visibility-timeout redelivery, and DLQ
   handoff plus caller-owned `retryBackoff`. Remaining work in this bucket is
   delete-ack boundaries and richer broker guarantees / consumer-group semantics.
4. **Coordination + correctness set** - `lockLease`, `idempotencyDedup`, and the
   dedicated `rate-limiter` / `circuit-breaker-controller` / `distributed-lock`
   nodes are now wired. Remaining work is higher-order correctness semantics such
   as reconciliation, ledgers, and exactly-once approximations.
5. **Failure-mode set** (`gcJitter`, `connectionPool`, `cacheStampede`, `dataSkew`,
   `replicationCost`) - each is a self-contained "aha" and a whole new question class.

After **every** step: re-run `scripts/validate-question-dir.ts` over all 9 shipped
questions to prove references still pass and gamed still fails on the intended axis.

_Source of truth for the hook/config/registration surface: `src/engine/traits/`
(`types.ts`, `capabilityModules.ts`, `resolveTraits.ts`), `src/engine/routing.ts`;
UI config generation in `src/renderer/src/config/fieldConfig.ts`; metrics in
`src/engine/analysis/{output,verdict}.ts`._

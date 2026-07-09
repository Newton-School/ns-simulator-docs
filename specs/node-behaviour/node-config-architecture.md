# Node Config Architecture - Capability Modules

> **Purpose:** The delivery mechanism for [`node-config-mapping.md`](./node-config-mapping.md). The mapping defines *what* each of the 72 nodes should show; this document defines *how that is produced* - a modular, structural config system in which the panel is **derived by composition, never authored per node**.
>
> **Date:** July 2026
>
> **The design in one sentence:** the trait system is already the per-type modularity system for *behaviour*; grow the trait into a **capability module** that also owns its config, defaults, metrics contract, constraints, presentation, and honesty notes - so config modularity and behaviour modularity become the same system, keyed by the same registry.
>
> **Companions:** [`node-behaviour-specification.md`](./node-behaviour-specification.md) (trait behaviours, §6–8) · [`node-config-mapping.md`](./node-config-mapping.md) (per-node apt config) · `design-decisions/governing-principles.md` (P-references below) · `design-decisions/adr-internal-modularity-over-plugin-system.md` (this design is internal modularity, not a plugin surface) · `planning/execution-roadmap-tasks.md` (B1/B2, C5, E2).

---

## 1. The problem, stated structurally

### 1.1 One capability is currently a diaspora

Shipping **one** trait today touches six files across three layers. Traced on the `node-trait-system-edge-behaviour` branch for CacheTrait:

| Concern | Where it lives today | Layer |
|---|---|---|
| Behaviour hooks | `src/engine/traits/cache.ts` ✅ | engine |
| Which nodes get it | `cache.ts` (`CACHE_COMPONENT_TYPES`) ✅ | engine |
| Config fields + visibility predicates | `src/renderer/src/config/fieldConfig.ts` | **renderer** |
| Defaults + seeded values | `src/engine/catalog/componentSpecs.ts` | catalog |
| Validation (canvas + JSON) | `componentSpecs.ts` **and** `validation/validator.ts` | catalog + engine |
| Metrics wiring | `metrics.ts` + `engine.ts` | engine |
| Identity chip / presentation | `renderer/.../nodePresentation.ts` | renderer |

The trait is a module in the engine and a diaspora everywhere else. Every new trait re-scatters, and every scatter point is a place where two copies of "which nodes have caching?" can diverge (P22 violation waiting to happen).

### 1.2 The base is stamped, not designed

`PROFILE_FIELD_GROUPS` keys the form off *profile* (`router`, `datastore`, `control-plane`…), and every profile's groups are near-identical copies of the same Queueing/Processing/Reliability base. Result: a Discovery Service and an API Server show the same form, in the engine's vocabulary (`Lambda: 2.5`), because the form generator mirrors the engine's data model instead of the domain. This is the root cause diagnosed in the mapping doc - a schema dump wearing a UI.

### 1.3 The migration has already half-started

`fieldConfig.ts` already imports `CACHE_COMPONENT_TYPES`, `RATE_LIMITER_COMPONENT_TYPES`, `CONTENT_ROUTING_COMPONENT_TYPES`, `HEALTH_AWARE_COMPONENT_TYPES`, `READ_WRITE_SPLIT_COMPONENT_TYPES` from the engine's trait files - the renderer already treats the trait as the source of truth for *where* a field appears. This document formalizes the direction: the trait becomes the source of truth for *everything about* the field.

---

## 2. The design: traits grow into capability modules

### 2.1 The module interface

Evolves from `NodeBehaviourTrait` in `src/engine/traits/types.ts`. One object owns everything about one capability:

```ts
interface NodeCapabilityModule {
  name: string                                  // 'cache', 'rate-limiter', …

  /** WHERE - the single source of truth resolveTraits and the panel both read */
  appliesTo: readonly ComponentType[]
  forbiddenOn?: {                               // teaching-by-denial (P17)
    types: readonly ComponentType[]
    lockedNote: string                          // "L4 operates at the transport layer…"
  }

  /** BEHAVIOUR - the existing trait, unchanged (P5: hooks on the queue lifecycle) */
  hooks?: NodeBehaviourTrait                    // beforeArrival / beforeRouting / filterRoutes

  /** CONFIG - the fields this capability contributes to the panel (§3) */
  config: ConfigFragment

  /** DEFAULTS - with rationale; consumed by the B1 resolver when it lands */
  defaults: ReadonlyArray<{ path: FieldPath; value: unknown; rationale: string }>

  /** METRICS CONTRACT - what this capability emits, declared not implied */
  metrics?: {
    counters?: readonly string[]                // 'cacheHits', 'cacheMisses'
    rejectionReasons?: readonly string[]        // 'rate_limited', 'no_healthy_targets'
  }

  /** PRESENTATION - canvas identity chip + visual signature (P26, P31) */
  presentation?: {
    identityChip?: (config: NodeSimConfig) => IdentityChip | null
    signature?: VisualSignatureSpec             // violet absorb, red shed, dashed breaker…
  }

  /** HONESTY - P3; feeds info cards (E2) AND the untraited-node notes (§5.3) */
  honesty: {
    simulates: readonly string[]
    notModeled: readonly string[]
  }
}
```

Design intent per section:

- **`appliesTo` is defined once.** Today it already lives in the trait file; the module makes it the *only* copy - `resolveTraits`, the panel composer, the validator, and the grader all read the same list. Divergence stops being a bug class (P22).
- **`hooks` is optional** because not every module is behavioural (§2.3) - but see §4.2: a module with `config` and no `hooks` must justify itself, or it's a fake knob.
- **`defaults` carry their rationale string** - the same text renders in the B2 provenance badge and the E2 info card. Written once.
- **`honesty` is mandatory, not optional.** Every module states what it does and doesn't model. This is what makes the definition of done enforceable (§4.2).

### 2.2 Composition: the panel is derived

```
panelSchema(node) =
    BASE_QUEUE_MODULE.config.withOverrides(node.componentType)   // §2.3-a
  + modulesFor(node.componentType).map(m => m.config)            // same registry as resolveTraits
  + lockedNotesFor(node.componentType)                           // every module's forbiddenOn
  + CROSS_CUTTING_MODULES.map(m => m.config)                     // §2.3-c: SLO, chaos
```

No node has a hand-authored form. `PROFILE_FIELD_GROUPS` is deleted at the end of the migration (§6); `fieldConfig.ts` becomes the **composer** - it assembles fragments, owns none.

### 2.3 Three kinds of module (the boundaries, stated honestly)

Not everything is a trait, and pretending otherwise would be dishonest the other way. Three kinds:

**(a) The base queue module - the one module that isn't a trait.**
G/G/c/K is the substrate (P5), not a capability: it has no hooks, applies to every non-source node, and cannot be removed. It gets module *packaging* - a `ConfigFragment` with **per-type vocabulary overrides** (the mapping doc's rule 3):

```ts
const BASE_VOCABULARY: Partial<Record<ComponentType, { workers: string; capacity: string }>> = {
  'load-balancer-l4':  { workers: 'Max concurrent connections', capacity: 'Connection queue limit' },
  'relational-db':     { workers: 'Connection pool size',       capacity: 'Query queue limit' },
  'serverless-fn':     { workers: 'Concurrency limit',          capacity: /* hidden: throttles, no queue */ },
  'job-worker':        { workers: 'Worker count',               capacity: 'Backlog limit' },
  // default: 'Workers' / 'Request queue limit'
}
```

Same engine value, correct physical name per node - the structural answer to "why does an LB have 8 workers?"

**(b) Behavioural modules - the traits.** Cache, RateLimiter, ContentRouting, HealthAwareRouting, ReadWriteSplit, ReadOnly, AckAndRelease, HealthProber, and everything in #180. Hooks + config + defaults + metrics + honesty, shipped together.

**(c) Cross-cutting modules - config without behaviour hooks.** Opt-in SLO targets, chaos injection ("Inject failure" - the relabeled Node Health knob), and workload config on sources. These have `config` and `honesty` but no `hooks`; they exist because their consumer is the *engine core or analysis layer*, not a trait. Naming them as a third kind keeps the P20 rule sharp instead of eroded.

---

## 3. The `ConfigFragment` field contract

Every field a module contributes declares its full contract - this is where the mapping doc's five design rules become types:

```ts
interface ConfigField {
  path: FieldPath                        // 'sim.queue.workers'
  label: string                          // domain vocabulary (rule 1) - or per-type via BASE_VOCABULARY
  unit?: string
  why: string                            // one-liner: why this field exists - the senior's question,
                                         //   answered on hover (P6)
  altitude: 'primary' | 'advanced'       // Advanced ▸ disclosure (rule 4, P12);
                                         //   per-type overridable (queueing is PRIMARY on job-worker)
  displayAs?: Transform                  // engine parameterization ⇄ human meaning (rule 1):
                                         //   lambda ⇄ mean ms · (mu,sigma) ⇄ typical+spread · ratio ⇄ %
  optional?: boolean                     // unset renders "+ Add …", serializes as ABSENT,
                                         //   never a fake 0 (rule 2, P2/P6)
  input: FieldInput                      // number | select | toggle | list-editor (RoutingRulesEditor)
  validate?: FieldValidation             // shape checks - consumed by canvas AND JSON validator
  accuracy: AccuracyClass                // existing scaffold: user-parameter | default-override |
                                         //   invariant | not-simulated  → provenance badge (rule 5)
}
```

**Transforms are display-layer only.** The engine keeps `lambda` internally and stays byte-identical (P8); `displayAs` converts on render and inverts on write. `Lambda: 6.666666666667` becomes `Mean service time: 0.15 ms` with zero engine change.

---

## 4. Where the trait system fits - precisely

### 4.1 The registry is the spine

`resolveTraits(node)` currently answers *"which behaviours run?"* Under this design the **same lookup** answers five questions:

| Consumer | Question it asks the registry |
|---|---|
| Engine (`resolveTraits`) | which hooks run on this node? |
| Panel composer (`fieldConfig.ts`) | which config sections render? |
| Default resolver (B1) | which defaults + rationales apply? |
| Validator (canvas + JSON) + C5 `isValidConnection` | which shapes/constraints to enforce, which wires to block? |
| Metrics / cards / info cards | which counters exist, which chips show, which honesty notes print? |

One mapping, five consumers - P22 enforced by construction instead of by review discipline.

### 4.2 P20 becomes a type-system guarantee

"Config never ships ahead of behaviour" is currently a review rule someone must remember. In the module shape it's structural, in both directions:

- A config field can only exist inside a module - and a behavioural module without `hooks` won't compile past review. You *cannot* add `heartbeatIntervalMs` to Discovery Service without shipping the heartbeat behaviour that consumes it.
- A trait PR that omits `config`, `defaults`, or `honesty` fails the interface. **The module type is the definition of done** - the same PR carries behaviour, knobs, rationale, metrics contract, and honesty note, or it doesn't merge.

### 4.3 What traits are *not* asked to do

Identity (label/icon/category), workload generation, chaos injection, SLOs. Forcing these into traits would blur the P5 boundary. They are modules (kind a/c), not traits (kind b) - the distinction is what keeps "trait" meaning something.

---

## 5. The structural payoff

### 5.1 The panel mirrors the architecture

Once config is composed from modules, **the sections a user sees map 1:1 to the modules the node is made of**:

> **API Gateway panel** = *Rate limiting · Content routing · Health · Forwarding (base, relabeled) · Advanced ▸*
> - because the node literally **is** RateLimiter + ContentRouting + HealthAware + queue.

The config UI stops being a form and becomes an honest exploded-view diagram of the node. That is itself teaching: *"what is an API gateway? - these four capabilities composed."* Structure on screen = structure in code = structure in the domain.

### 5.2 The L4/L7 lesson becomes module data

L7 = L4 + ContentRouting module. The panel *shows* that equation: identical sections except one - and on L4, the ContentRouting module's `forbiddenOn.lockedNote` renders in its place. The denial is data in the module, consumed identically by the panel (🔒 note), the canvas (C5 wire-block), and the validator (import rejection).

### 5.3 Untraited nodes become honest instead of fake

For the ~39 nodes with no behavioural modules yet, composition yields: relabeled base + cross-cutting + **an honesty note** derived from the absence itself:

> ⓘ *This node currently simulates as a generic request queue. Modeled: concurrency, queueing, latency. Not yet modeled: service registration, heartbeats, critical-dependency failure.*

Content comes from the mapping doc's 📋 rows. Thirty-nine silent fakes become thirty-nine declared simplifications (P3) - and the note doubles as the visible roadmap for #180+. When Discovery Service's trait lands, its module replaces the note automatically.

---

## 6. Migration path (each step independently shippable)

| # | Step | Files | Risk |
|---|---|---|---|
| 0 | **Display pass first** (no architecture needed): `displayAs` transforms, opt-in SLO, chaos-knob relabel, Advanced ▸ | `fieldConfig.ts`, `PropertiesForm.tsx` | S - fixes all 72 panels at once |
| 1 | Define `ConfigFragment` / `NodeCapabilityModule` types; wrap the 9 existing traits - **move their fields from `fieldConfig.ts` into their trait files**; `fieldConfig` becomes the composer | `src/engine/traits/*`, `fieldConfig.ts` | M - mechanical, behaviour-neutral |
| 2 | Base queue module + `BASE_VOCABULARY` per-type relabels; delete `PROFILE_FIELD_GROUPS` | `traits/baseQueue.ts`, `fieldConfig.ts` | M |
| 3 | Move defaults + rationale from `componentSpecs.ts` into modules; resolver reads modules (this **is** part of B1) | `componentSpecs.ts`, traits | M |
| 4 | Move identity chips, L4 locked-note, honesty notes into modules; wire C5 `isValidConnection` off `forbiddenOn` | `nodePresentation.ts`, `FlowCanvas.tsx` | M |
| 5 | New traits (#180) ship **module-complete from day one** | per trait | - |

**Prerequisite:** commit the in-flight branch work first (`RoutingRulesEditor.tsx`, `NodeMetricsDetail.tsx`, `fieldConfig.ts` edits) - step 1 rewrites the exact region it touches.

---

## 7. Testing strategy

1. **The mapping doc becomes executable.** One snapshot test: *for every `ComponentType`, the composed `panelSchema` section/field list must match the "Proposed" column of `node-config-mapping.md`.* The mapping doc and the code can never drift silently.
2. **Interface completeness** - a test iterates all registered modules asserting `honesty`, `defaults[].rationale`, and `config[].why` are non-empty (P20's definition of done, mechanized).
3. **Transform round-trips** - `write(display(x)) === x` for every `displayAs` (guards P8: transforms must never touch stored values).
4. **Determinism regression** - golden-file run before/after each migration step; steps 1–4 are display/structure only and must be byte-identical in engine output.

---

## 8. What this is NOT

- **Not a plugin system.** Per `adr-internal-modularity-over-plugin-system.md`: modules are internal, statically registered, type-checked - composability for *us*, not an extension API for third parties.
- **Not an engine rewrite.** `GGcKNode` is untouched (P5); hooks are the existing three; transforms are render-layer.
- **Not a blocker for #180.** New traits can adopt the module shape immediately (step 5) even while steps 1–4 are in flight.
- **Not 72 bespoke forms.** The entire point: per-node aptness falls out of composition + a small vocabulary table, not per-node design work.

## 9. Principles enforced by construction

| Principle | How the architecture enforces it |
|---|---|
| P5 queue stays, traits overlay | Base is the one hook-less module; everything else composes onto it |
| P6/P11 no number without a why | `why` + `accuracy` + `defaults[].rationale` are required fields |
| P12 altitude | `altitude` is a field property, per-type overridable |
| P17 constraint is the lesson | `forbiddenOn.lockedNote` - one datum, three enforcement points |
| P20 behaviour ships with demonstration | Module interface = definition of done (§4.2) |
| P22 one truth per rule | `appliesTo` defined once, five consumers (§4.1) |
| P2/P14 failure injected, config ≠ result | Chaos is its own cross-cutting module, labeled as injection |
| P3 model honestly | `honesty` is mandatory; untraited nodes auto-note (§5.3) |

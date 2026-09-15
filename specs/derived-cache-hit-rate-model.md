# Derived Cache Hit-Rate Model — Gap Analysis + Build Spec

> **Goal.** Stop treating cache hit rate as a free dial. Today `cacheHitRate` is
> an author-supplied probability the engine consumes verbatim; a design that
> "adds a cache" gets whatever hit rate the author typed, regardless of working
> set, cache size, or access pattern. This spec makes hit rate **derivable** from
> `f(working-set, capacity, access-skew)` while keeping an explicit override, so
> the disclosure flips from *"hit rate is an input you dialed"* to *"hit rate is
> derived, and overridable."*
>
> **Status.** Phases 1–4 **SHIPPED (2026-09-11)** — see §4. Hit rate is now a
> measured consequence of a real bounded LRU (`cacheModel: 'derived-lru'`, opt-in)
> fed by Zipf-drawn keys; `declared-rate` remains the default. Remaining: flip the
> default after a dual-topology grading validation (§6).
>
> **Provenance.** Distilled from a session tracing how the engine actually models
> traffic distribution across Load Balancer / API Gateway / Distributed Cache /
> Pub/Sub / API Server. The cache was the one component whose "distribution"
> reduces to a single declared scalar — see §1.

---

## 1. What the engine models today (evidence)

Traffic-distribution audit across the five front-of-house components:

| Component | Distribution mechanism | Modeled? | Source |
|---|---|---|---|
| Load Balancer / router | round-robin, least-conn, weighted, random, passthrough | ✅ executed per request | `routing.ts` `pickSyncRoute` (~L220) |
| API Gateway | edge conditions on `request.type` (generic) **plus** `type/method/path/host` rule routing (l7-lb / api-gateway / ingress) | ✅ / ⚠️ | `routing.ts` `matchesCondition`; `traits/contentRouting.ts` + `core/requestSemantics.ts` |
| Distributed Cache | **single hit/miss probability** | ⚠️ **declared input** | `traits/cache.ts` |
| Pub/Sub | keyed partition (`hash(key) % partitions`), consumer groups, offsets | ✅ Kafka-shaped | `semantics/v2StateMachines.ts` `ReplicatedLog` |
| API Server | queue + worker concurrency | ✅ consumer, not distributor | engine queue model |

The cache is the outlier. `traits/cache.ts` is literally:

```
normalized < hitRate  →  hit (skip downstream)
else                  →  miss (fall through)
```

and it declares its own limits ([cache.ts:106], [cache.ts:221]):

> "Both use the same hit/miss model here. TTL is topology intent only; expiry and
> eviction are not simulated." `notModeled: ['eviction pressure, origin shield
> behavior, stale reads']`

So none of consistent hashing, sharding, LRU/LFU, or eviction is modeled. Hit
rate is an input, not a consequence. This is *honest* (it says so) but *inert*:
the design lever "size the cache to the working set" has no effect.

> **Scope note.** The cache is the *only* front-of-house component whose
> "distribution" reduces to a declared scalar — it absorbs traffic, it does not
> route it. The catalogue-wide audit of every node that *does* distribute traffic
> (the five tiers, what's not modeled, whether the input exists, and the fixes)
> now lives in its own spec:
> [`traffic-distribution-gap-register.md`](./traffic-distribution-gap-register.md).
> This spec stays focused on deriving the cache hit rate; its priority-#1 fix (the
> `keyspace.skew` Zipf draw, §4) is shared with that register's Tier-4 work.

## 2. What inputs already exist

Deriving hit rate needs three quantities. Two are already in the schema:

| Ingredient | Symbol | Where it lives today | Status |
|---|---|---|---|
| Working-set size (distinct keys) | `N` | `requestType.keyspace.size` — [workload.ts:217] | ✅ exists |
| Cache capacity (RAM → items) | `C` | `memoryGb` already boosts derived capacity — [componentSpecs.ts:210] | ✅ exists (needs value-size to become item count) |
| Access skew (popularity concentration) | `s` | — keys drawn **uniformly** at [workload.ts:219] | ❌ **missing** |

The `memoryPressure` trait already carries a `workingSetRatio` (working-set ÷
capacity) concept — [memoryPressure.ts] — so the ratio pattern is not foreign to
the engine.

## 3. The math — why skew is load-bearing

Let `C` = items the cache holds, `N` = distinct keys in the working set.

**Uniform access (today's key draw).** Steady-state LRU hit rate is
```
hitRate ≈ min(1, C / N)
```
Derivable with zero new inputs — but a **bad** model. It claims a cache holding
10% of keys yields a 10% hit rate. Real caches work *because* access is skewed.
Shipping this uniform derivation would replace an honest input with a
dishonest-looking derivation, violating the no-point-sampled-scalars / honesty
doctrine. **Do not ship the uniform form alone.**

**Skewed access (Zipf), the realistic case.** With skew `s`, hit rate is the
cumulative popularity mass of the top-`C` keys:
```
hitRate ≈ ( Σ_{r=1..C} r^(-s) ) / ( Σ_{r=1..N} r^(-s) )
```
At `s ≈ 1` (typical web), the top 10–20% of keys carry 80%+ of requests, so a
small cache earns a high hit rate — the curve that makes caching worthwhile.
One parameter separates a toy from a credible model.

## 4. Build plan (phased)

### Phase 1 — Zipf keyspace draw ✅ **SHIPPED (2026-09-11)**
- Added `keyspace.skew` (Zipf `s`, `0`/omitted = uniform for back-compat) to the
  keyspace type (`core/types.ts`) and schema (`validation/validator.ts`).
- `workload.ts` `buildRequestMetadata` now draws Zipf when `skew > 0` via a cached
  normalized cumulative table + binary search (`drawZipfIndex`/`getZipfTable`,
  O(log size) per request, `MAX_ZIPF_TABLE = 100_000` guard with a folded-uniform
  tail). Index `0` is the hottest key. Uniform path unchanged when `skew` absent.
- Coverage in `workload.test.ts` ("keyspace key selection"): uniform spread,
  Zipf concentration (top decile ≈ H₁₀/H₁₀₀ ≈ 0.565 at s=1), bounds, determinism.
  Full engine suite green (671 tests).
- **Free side-benefit (available, not yet applied):** the `flash-sale-booking`
  keyspace can set `skew` to make hot keys collide more; left unset there for now
  to avoid changing an existing question's grading without review.

### Phase 2 — Capacity in items ✅ **SHIPPED (2026-09-11)**
- `deriveCapacityItems` in `traits/cache.ts` computes `C = cacheRamMb·1e6 ÷
  valueSizeBytes` (min 1). Both inputs added as first-class config
  (`sim.cacheRamMb`, `sim.valueSizeBytes`) and wired through the sim→engine
  allowlist (`componentSpecs.ts`), the `sim` type (`nodeSpecTypes.ts`), and the
  round-trip adapter (`topologyCanvasAdapter.ts`).

### Phase 3 — Derived hit rate ✅ **SHIPPED (2026-09-11) — as a real LRU, not an analytic scalar**
- **Design change from the original draft.** Instead of computing an analytic
  Zipf-CDF scalar (which would need the workload's `N`/`s` plumbed to the cache
  node and breaks when one cache serves multiple request types), the cache now
  simulates a **real bounded LRU** of `C` items in per-node `TraitContext.state`,
  keyed on the request's canonical `__key` (stamped by `workload.ts` whenever a
  keyspace is declared). Hit rate becomes a **measured consequence** of capacity
  + the Zipf-drawn key stream — strictly more honest, and it directly consumes
  phase 1. Cold-start warming and eviction are now modeled (previously deferred).
- **Opt-in, back-compat.** New `sim.cacheModel` select: `declared-rate` (default,
  unchanged behaviour) vs `derived-lru`. Existing topologies keep the declared
  model, so no graded question shifts. In `derived-lru`, `cacheHitRate` is hidden/
  ignored; if the capacity inputs or the request key are missing, the node falls
  back to the declared path.
- **Validation.** `cache.test.ts` "derived-lru model": warming (miss→hit),
  LRU eviction past capacity, full-coverage all-hit, and both fallbacks.
  End-to-end (Zipf keys → LRU): uniform C/N≈0.1, Zipf(s=1) C=100/N=1000 ≈ 0.4+,
  hit rate rises with both capacity and skew. Full suite green (683 tests).

### Phase 4 — Disclosure ✅ **SHIPPED (2026-09-11)**
- The capability-module `note` now describes both models; the `honesty` block
  splits `simulates` / `notModeled` per model (derived: measured hit rate + warming
  + eviction; still-out: TTL expiry, sharding/consistent-hashing, per-key value
  size). The `cacheHitRate` field's `why` says "declared model only."
- **Remaining default flip deferred:** `declared-rate` stays the default until a
  dual-topology question validates grading on the derived model (see §6).

## 5. Explicitly deferred / not modeled

- ~~**Time dynamics of eviction**~~ — **now modeled** in the derived-LRU model
  (cold-start warming + LRU eviction emerge from the key stream).
- **Consistent hashing / sharding across cache nodes** — orthogonal; this spec is
  about *hit rate*, not *which node holds the key*.
- **Stale reads / TTL expiry / origin shield** — remain declared-intent only.
- **Per-key value-size variation** — one mean `valueSizeBytes` sets capacity.
- **Per-endpoint working sets** — the key stream is per request-type keyspace;
  multi-tier or per-route working sets are a later refinement.
- **Default-model flip** — `declared-rate` remains the default pending a
  dual-topology grading validation (§6).

## 6. Open questions

1. Default `s`? Web ≈ 0.8–1.0; proposal: `0.9`, with `0` meaning uniform.
2. Where does value size live — cache trait field, or storage-profile reuse?
3. Should an author-declared `cacheHitRate` **warn** when it diverges sharply from
   the derived value (teachable "your cache is mis-sized" signal), or stay silent?
4. Does derived hit rate feed grading, or display-only first? (Recommend
   display-first, then graded once validated on a dual-topology question.)

---

## Appendix — files touched (anticipated)

- `src/engine/workload.ts` — Zipf draw, `keyspace.skew`
- `src/engine/validation/validator.ts` — schema for `skew`, `valueSizeBytes`
- `src/engine/traits/cache.ts` — derivation, override, disclosure
- `src/engine/catalog/componentSpecs.ts` — RAM → item capacity
- `src/engine/traits/cache.test.ts` / `workload.test.ts` — coverage
- A dual-topology question (well-sized vs. under-sized cache) to validate grading

The catalogue-wide distributor fixes moved to
[`traffic-distribution-gap-register.md`](./traffic-distribution-gap-register.md);
the shared `keyspace.skew` Zipf draw (phase 1 here) is that register's priority #1.

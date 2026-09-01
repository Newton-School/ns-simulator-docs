# Contended-Inventory & Oversell Model — Gap Analysis + Build Spec

> **Goal.** Make the simulator able to author and *honestly grade* a true
> "Design Ticketmaster" question whose lesson is **"never sell the same seat
> twice under a concurrent burst."** This document (a) enumerates every gap
> blocking that today, each grounded in a specific file, with nothing assumed,
> and (b) specifies the build.
>
> **Status.** Gap audit complete (2026-08-27). **Model B built and validated
> (2026-08-27)** — see §6. GAP 4 (question-owned invariants) was deliberately
> **deferred**: oversell is graded via a question-owned `rubric` simulation check
> on `reservations.oversells`, so no invariant-injection channel was needed.

---

## 6. What shipped (Model B)

Built end-to-end, all 635 tests green, dual-topology validation passing.

- **Run-scoped shared trait state.** `TraitContext.sharedState` (a run-lifetime
  `TraitStateStore`) added alongside per-node `state`; engine plumbs it into the
  `beforeArrival` / `beforeRouting` hook sites (`traits/types.ts`, `engine.ts`).
- **Reservation capability** (`traits/reservationStore.ts`, new component type
  `reservation-store`). Atomic per-key reserve: first request for a key commits
  (`reservationCommits`), later requests at the same authority get a fast
  "sold out" success (`reservationConflicts`, modeled as `handled` — **not** an
  error), and a commit for a key already committed by a *different* node is an
  **oversell** (`reservationOversells`). Registered across all 10 catalogue/
  renderer sites; honesty block declares what it does and does not model.
- **Keyspace workload (GAP 2).** `requestDistribution[].keyspace = { field, size }`
  stamps each request a key drawn uniformly from `size` keys (`workload.ts`,
  schema in `validation/validator.ts`). Small size + high RPS = contention.
- **Metric surface (GAP 3).** `verdict.perNode.<id>.traitCounters` and a run-wide
  `verdict.reservations = { commits, conflicts, oversells }` (`verdict.ts`).
  `resolveMetric` reaches both via its `getByPath` fallback — a rubric grades
  `reservations.oversells == 0` with no new switch case.
- **Authored question** at
  `examples/question-bank/flash-sale-booking/`
  (`question.json` + `reference-topology.json` + `gamed-topology.json`).

**Dual-topology result** (injected 1200 rps of `book` over a 40-seat keyspace):

| Topology | oversells | structural | semantic | rubric | verdict |
|----------|-----------|-----------|----------|--------|---------|
| Reference (1 authority) | **0** | ✓ | ✓ | 7/7 | **PASS** |
| Gamed (2 uncoordinated authorities) | **40** | ✓ | ✓ | 2/7 (0.29 < 0.71) | **FAIL** |

The gamed design is structurally valid and passes store-fit — it fails **only**
on the simulated oversell, which is the correctness signal that did not exist
before. Reference sells all 40 seats exactly once; the two-authority design
double-books every seat.

---

## (historical) original build plan

---

## 1. Why the current engine cannot grade it (evidence)

Everything below was verified by reading source, not inferred.

### GAP 1 — There is no contended finite-inventory / reservation model
- No inventory / seat / reservation / oversell mechanism exists in `traits/` or
  `nodes/`.
- `traits/storageProfile.ts:254` explicitly lists `notModeled: ['quorums,
  freshness/staleness windows, lock contention, compaction internals']`. Lock
  contention — the exact physics of double-booking — is declared out of scope.
- `traits/idempotencyDedup.ts` (honesty block, lines 200-207) models **retry
  dedup by key** and explicitly *not* `['commit outcome tracking', 'cross-node
  consensus', 'partial-failure recovery']`. Dedup catches the *same* request
  submitted twice; it does **not** catch two *different* buyers racing for one
  seat.
- Consequence: a plain single store node in a DES serializes events, so it can
  never be *made* to double-book. Oversell only exists if we deliberately model
  the read-modify-write race.

### GAP 2 — The workload cannot generate a contended keyspace
- `workload.ts:176-179` copies a **static** `requestType.metadata` onto every
  request of that type. Every `book` request therefore carries identical
  metadata.
- There is no per-request key sampling (no hot-key / uniform-over-N-seats
  distribution). Without a varying `seatId`, there is no contention to grade.

### GAP 3 — Trait counters are dropped before grading; no metric surface exists
- Traits emit `payload.metricCounters`; the engine aggregates them per node via
  `recordNodeTraitCounters` (`metrics.ts:630`), stored as `NodeMetrics.traitCounters`.
- **But `projectToVerdict` (`verdict.ts:128-150`) does not copy `traitCounters`
  into the verdict `perNode`**, and `resolveMetric` (`rubric.ts:160-215`) has no
  case for them.
- Consequence: even today's `idempotencyDuplicateHits` cannot be asserted by a
  rubric or invariant. Any oversell counter we add is invisible to grading until
  this boundary is bridged.

### GAP 4 — Invariants are not question-owned, and are threshold-only
- `InvariantCheck = { id, description, condition }` (`core/types.ts:479`) lives on
  `TopologyJSON.invariants` (`core/types.ts:509`) and is evaluated from
  `this.topology.invariants` (`engine.ts:1810`).
- `mergeTopologyWithOverrides` (`evaluate.ts:67-91`) merges `global`, `workload`,
  and `faults` — **not `invariants`**. So a question suite has no channel to
  inject its own invariants; the graded topology's invariants come from the
  *student's* base topology, which the student can delete. The url-shortener
  `no-invariants` rubric row is effectively a no-op today.
- `invariants.ts` only supports `<metric> <op> <number>` over resolvable verdict
  metrics. A "no double-book" invariant is meaningless until a resolvable oversell
  metric exists (GAP 3) **and** the question can own the invariant.

### GAP 5 — (authoring correction, not a blocker) guard is semantic, not structural
- There is **no** `requires_guarded_path` structural kind. `structural.ts` kinds:
  single_source, component, category, edge, path, redundancy, connected_graph,
  counts, composite, forbids_component.
- The guard check is `SEMANTIC_CRITERION` **`guardedPath`** with fields
  `from` / `guard` / `to` (`semanticCriteria.ts:127-168`) and it already enforces
  "a path exists **and no path bypasses the guard**." Usable as-is.

### GAP 6 — (authoring correction) `storageFit.accessPattern` is cosmetic
- `evalStorageFit` uses `accessPattern` only inside the human-readable `detail`
  string (`semanticCriteria.ts:297-311`). Grading is purely the `accept` /
  `partial` / `antiPattern` **component-type lists**. "Use an atomic/consistent
  store" must be encoded as component lists, not as an `accessPattern` value —
  which is why GAP 7 (a distinct reservation component type) matters.

### GAP 7 — No reservation/inventory component type or catalog surface
- `ComponentType` (`core/types.ts:176`) has no reservation/inventory member.
- Adding one touches: the union; capability registration in
  `traits/capabilityModules.ts`; catalog `componentSpecs.ts`,
  `paletteTemplates.ts`, `resourceDefaults.ts`; and renderer `nodeRegistry.ts` /
  `libraryInfo.ts`.

---

## 2. What already exists and is reusable
- **Guard placement:** `guardedPath` semantic criterion (GAP 5) — reuse directly.
- **Store-fit discrimination:** `storageFit` accept/anti/hardFail — reuse to force
  the right store and reject cache-as-source-of-truth.
- **Stateful trait pattern:** `TraitStateStore` + `payload.metricCounters` +
  `NodeCapabilityModule.honesty` (`traits/idempotencyDedup.ts` is the reference
  implementation to copy).
- **Per-key routing/hashing:** `traits/keyBasedRouting.ts` + `stableHash` show how
  a `resourceKey` is read from `request.metadata` and hashed.
- **Rubric/invariant plumbing:** metric → op → value → points, and
  `invariantViolations.count`, all work once a metric is surfaced (GAP 3).

---

## 3. THE ONE DECISION — how should an oversell *emerge*?

An oversell must be a **consequence of the design**, not a dial. Two viable models:

### Model A — Emergent from topology (purest, hardest)
Booking is modeled as an explicit **check-then-commit** two-step. Oversell is
counted at runtime when a commit for a `seatId` lands after a *stale* availability
read — i.e., when the design reads availability from a **non-authoritative**
component (cache / read-replica) ahead of the write, or splits writes across
**multiple uncoordinated authorities**. A single atomic reservation store on a
guarded path yields zero. Most physically honest; requires modeling stale reads
and multi-authority state. Highest build cost/risk.

### Model B — Atomic reservation node + topology-derived authority (recommended)
Add a **`reservation-store` capability**: a single stateful authority that holds
per-`seatId` remaining capacity and performs an **atomic conditional reserve**
(first request for a seat commits; later ones are cleanly *rejected* as
"sold out" — a correct rejection, not an error). Oversell is counted **only** when
the graded topology routes writes for the same key through **more than one
independent reservation authority** (e.g. two replicas each holding inventory) or
lets an unguarded path reach the seat store without the reservation node. A
correct single-authority, guarded design yields zero; the classic gamed designs
(no guard, cache-as-truth, uncoordinated replicas) yield >0. Emergent enough to
discriminate, bounded enough to build deterministically in one pass.

### Model C — Explicit `concurrencyControl` toggle (rejected)
The student flips the store to "safe." Violates the no-free-dial honesty
principle (correctness must not be a dial). Not building this.

**Recommendation: Model B.** It grades honestly, reuses the idempotency trait
pattern, and its "atomicity comes from using one authoritative reservation node on
a guarded path" story is exactly the real-world lesson.

---

## 4. Build plan (once Model is confirmed)

Phased so each phase is independently testable.

1. **Metric surface (GAP 3).** Add `traitCounters` (or a scoped
   `capabilityCounters`) to verdict `perNode` in `verdict.ts`; add
   `perNode.<id>.<counter>` and a top-level aggregate (e.g.
   `reservations.oversells`) to `resolveMetric` in `rubric.ts`. Unit tests.
2. **Question-owned invariants (GAP 4).** Extend `ScenarioOverrides` +
   `mergeTopologyWithOverrides` to carry `invariants`, and let a suite case /
   package supply them so the student cannot delete them. Schema + tests.
3. **Keyspace workload (GAP 2).** Allow a `requestDistribution` entry to declare a
   `keyspace` (field name + size + hot-key skew) so each request draws a
   `seatId`. `workload.ts` + schema + tests.
4. **Reservation capability (GAP 1 + 7).** New `reservation-store` component type +
   capability module (copy `idempotencyDedup.ts` shape): per-key atomic reserve,
   emits `reservationCommits`, `reservationConflicts` (correct rejects), and
   `reservationOversells` per the Model-B authority rule. Catalog + palette +
   renderer registry. Honesty block. Unit tests including a two-authority
   oversell case.
5. **Author the question + dual-topology validation.** Reference topology → 0
   oversell, PASS; gamed topologies (no guard / cache-as-truth / split replicas)
   → oversell > 0, FAIL on the intended axis. Ship as Django rows.
6. **Docs.** Update `evaluation-authoring-reference-manual.md` (new component,
   new metrics, keyspace workload) and rewrite video-script 3 against the real
   schema.

---

## 5. Open sub-questions to settle inside the chosen model
- Capacity default per key (1 seat) and how a seat "inventory" of N is declared.
- The exact deterministic runtime rule for counting an oversell under Model B
  (single-authority serialization vs. multi-authority race) — pinned in Phase 4.
- Whether oversell surfaces as a first-class `invariantViolations` entry (so the
  existing `invariantViolations.count` rubric works) or as a dedicated
  `reservations.oversells` metric (or both).

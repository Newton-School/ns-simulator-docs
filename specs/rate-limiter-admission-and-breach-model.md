# Rate-Limiter Admission & Breach Model

Date: 2026-09-01

## 1. Why this exists

The rate-limiter chapter (Alex Xu, System Design vol. 1 ch. 4) teaches five
admission algorithms, a distributed synchronization bug, and a read-check-
increment race. Most of that lived in the ungradeable `J` (justification) and
`N` (narrative) axes. This model moves two of those lessons into the
**simulation (Σ)** axis, without an engine-architecture change:

1. the **synchronization lesson** — an uncoordinated (per-instance local)
   counter lets a client exceed the global limit, and
2. the **algorithm-consequence lesson** — a fixed-window counter admits up to
   2× the limit across a window boundary (the edge-doubling bug), a sliding
   window does not.

Both are graded by one run-wide metric: `rateLimit.breaches`.

## 2. The key idea: admission vs. a truth oracle

The trait separates two concerns that are usually conflated:

- **Admission** (the mechanism the student chose) runs against **per-node**
  `state`. This faithfully models *independent local counters*: one limiter node
  = one counter; two parallel limiter nodes = two independent counters. This is
  the honest default — nodes do not magically share state.
- **The breach oracle** (physics truth) runs against **run-scoped
  `sharedState`**. It records every admit across *every* rate-limiter node into a
  per-key rolling log, and flags a breach whenever the true rolling-window admit
  count for a key exceeds the question's contracted `limit`.

Crucially, **admission never reads the shared oracle**. If it did, two nodes
would automatically behave as one shared Redis counter and there would be
nothing to grade. Correctness therefore still has to come from **topology** —
the student must funnel all traffic for a key through a single authority. The
oracle only *observes* and *reports*; it never *coordinates*.

This mirrors the reservation-store pattern (`reservationStore.ts`: per-node
committed set + run-scoped shared ledger detecting a second committer) and the
lock-lease clock model (`lockLease.ts`: state held across simulated time,
compared against `clock`). It is a `beforeArrival` + `clock` computation — no
completion/departure hook is required.

## 3. What it does *not* model (the honest boundary)

Admission is **atomic per event** — read and write happen inside one
`beforeArrival` call, so the *literal* read-modify-write interleaving (the
chapter's counter 3→4→4-instead-of-5 figure) is **not** simulated. That is a
deliberate scope choice: the teachable *insight* of that race — "an
uncoordinated counter lets a client exceed the limit" — is exactly what the
breach oracle surfaces, via topology (two authorities) and via algorithm (edge
doubling). Modelling the byte-level interleaving would need a two-phase
read-at-arrival / write-at-completion hook (an engine change) and would teach
nothing extra. Also unmodelled: HTTP 429 semantics, `X-RateLimit-*` headers,
and rule-config formats (all stay narrative/justify).

## 4. Configuration

The `rate-limiter` capability (`src/engine/traits/rateLimiter.ts`) applies to
`api-gateway`, `third-party-api-connector`, `rate-limiter`, `throttler`.

| Field (`sim.*`) | Meaning | Default |
| --- | --- | --- |
| `algorithm` | `token-bucket` \| `fixed-window` \| `sliding-window` | `token-bucket` |
| `limit` | contracted admits per key per window (window algorithms; also the breach ceiling) | — |
| `windowMs` | rolling window the limit applies over (window algorithms) | — |
| `rateLimitKeyField` | `request.metadata.<field>` to bucket on (per client/user); empty ⇒ one global bucket | empty |
| `maxTokens` | token-bucket burst size (legacy path) | — |
| `refillRatePerSecond` | token-bucket steady-state refill (legacy path) | — |

Backward compatibility: a node configured only with `maxTokens` +
`refillRatePerSecond` behaves exactly as the pre-existing token-bucket limiter,
now additionally keyable. Window algorithms require both `limit` and `windowMs`;
without them the node is a pass-through (never silently blocks).

## 5. Algorithms

- **token-bucket** — burst up to `maxTokens`, refill at `refillRatePerSecond`
  against the simulation `clock`. Burst-tolerant by design.
- **fixed-window** — window origin aligned to `floor(clock / windowUs)`. Admits
  up to `limit` per aligned window; a burst straddling a boundary can admit
  `limit` in each of two adjacent windows ⇒ up to 2× in a rolling window ⇒ the
  oracle flags breaches.
- **sliding-window** — exact log of admit timestamps in the trailing window;
  never admits more than `limit` in any rolling window ⇒ 0 breaches.

## 6. Metrics

Per-node counters land in `perNode.<nodeId>.traitCounters.*`:
`rateAdmitted`, `rateRejected`, `rateLimitBreaches`, `rateKeyless`. Rejected
requests carry rejection reason `rate_limited`.

Run-wide aggregate (`projectToVerdict`, `SimulationVerdict.rateLimit`):

| Field | Meaning |
| --- | --- |
| `admitted` | total admits across all rate-limiter nodes |
| `rejected` | total admission rejections |
| `breaches` | admits that pushed the true rolling-window count for a key above `limit` — **the correctness signal** |
| `keyless` | requests that reached a per-key limiter with no key field (usually a wiring mistake) |

**Grade the correctness lesson with `rateLimit.breaches == 0`.**

## 7. How the two bugs surface (discrimination)

| Topology / config | Admits (one key, window) | `rateLimit.breaches` |
| --- | --- | --- |
| one sliding-window authority | ≤ limit | 0 → **PASS** |
| one fixed-window authority, edge-straddling burst | up to 2× limit | > 0 → **FAIL** |
| two parallel limiters (local state), same key | up to 2× limit | > 0 → **FAIL** |

The reference passes; each gamed shortcut fails on the intended signal — the
Dual-Topology Rule holds.

## 8. Authoring the workload

The contended key must vary per request. Use the workload `keyspace` on the
request distribution (`requestDistribution[].keyspace = { field, size }`, the
same primitive contended-inventory uses), with `field` matching
`rateLimitKeyField` and a small `size` so many requests share a key. Inject a
burst rate above `limit / windowMs` so the limiter is actually exercised.

## 9. Code map

- Trait + capability module: `src/engine/traits/rateLimiter.ts`
- Registration: `src/engine/traits/capabilityModules.ts`
- Run-wide aggregate: `src/engine/analysis/verdict.ts` (`SimulationVerdict.rateLimit`, `sumRateLimitCounters`)
- Tests: `src/engine/traits/rateLimiter.test.ts`
- Contended-key workload primitive: `specs/contended-inventory-and-oversell-model.md`
- Runtime-evidence grading surface: `specs/runtime-semantic-criteria.md`
- Lesson design: `specs/rate-limiter-lab-lesson.md`

# Support Ledger And Runtime Semantics

Date: 2026-09-01

## 1. Why this exists

The simulator had two related problems:

1. support truth was fragmented across docs, validator warnings, sample questions, and trait honesty notes
2. request outcomes told us how a request ended, but not enough about the semantic state it went through

This document defines the first foundation layer that fixes both.

## 2. Support ledger

The source of truth now lives in:

- `src/engine/analysis/supportLedger.ts`

It classifies:

- question domains
- component categories
- major trait modules
- known teaching concepts

using these tiers:

- `first-class`
- `guided`
- `structural-only`
- `presentational-only`
- `deferred`

### 2.1 Tier meaning

- `first-class`: runtime, grading, authoring, and tests are all strong enough to rely on directly
- `guided`: something real exists, but the simulator still has declared boundaries the author must respect
- `structural-only`: topology or semantic checks can teach it, but runtime does not prove it
- `presentational-only`: catalog or docs may expose it, but it is not a trustworthy teaching/grading surface yet
- `deferred`: not ready for author use

### 2.2 What changed

The authoring validator now reads this ledger instead of relying on the old blanket idea that entire domains like `network`, `resilience`, or `cost` are simply "not built yet."

That means author feedback is now more honest:

- `network` warns as `guided`, not as nonexistent
- `resilience` warns as `guided`, not as nonexistent
- `cost` warns as `guided`, with expectation of a budget-aware question shape
- concepts like `exactly-once`, `consumer-groups`, or `l4-vs-l7` can now warn independently of the broad domain tag

## 3. Runtime semantics foundation

The first runtime semantics contract now lives in:

- `src/engine/core/simulationSemantics.ts`

It does **not** claim full distributed-systems semantics. It is the first honest layer above raw request outcomes.

### 3.1 Lifecycle state

Each request outcome now carries a normalized lifecycle state such as:

- `completed`
- `timed-out`
- `rejected`
- `in-flight`

This remains intentionally small. It gives the simulator a stable top-line vocabulary for summaries, grading, and filtering.

### 3.2 Per-request state timeline

Each request outcome now also carries a first-class `stateTimeline` ledger.

Current scopes:

- `request`
- `delivery`
- `idempotency`
- `lock`
- `reservation`

Current request states include:

- `generated`
- `admitted`
- `queued`
- `processing`
- `forwarded`
- `retry-scheduled`
- `completed`
- `timed-out`
- `rejected`
- `in-flight`

Current delivery states include:

- `producer-acked`
- `released-to-consumer`
- `redelivery-scheduled`
- `dlq-routed`

Current coordination states include:

- idempotency:
  - `recorded`
  - `deduped`
  - `key-missing`
- lock:
  - `attempting`
  - `acquired`
  - `contended`
  - `held`
  - `released`
  - `key-missing`
- reservation:
  - `committed`
  - `sold-out`
  - `oversold`
  - `key-missing`

This timeline is now retained on the request-outcome ledger and surfaced in the results tray, so authors and students can inspect how a request moved through queue delivery and correctness-related traits without reading raw canonical events.

### 3.3 Delivery semantics

Queue-backed outcomes now carry an assessed delivery snapshot:

- configured delivery mode
- actual runtime guarantee
- whether duplicate delivery is possible
- whether replay is possible
- whether silent loss is still possible
- whether the configured mode had to be downgraded

The most important honesty rule today:

- configured `exactly-once` is currently downgraded to runtime `at-least-once`

because commit-outcome coordination is still not modeled yet.

### 3.4 Coordination state markers

Certain traits now stamp explicit semantic markers into the request metadata so the final outcome can preserve the last meaningful state.

Current markers:

- idempotency:
  - `recorded`
  - `duplicate`
  - `no-key`
- lock lease:
  - `attempting`
  - `acquired`
  - `contended`
  - `held-by-request`
  - `no-key`
- reservation:
  - `committed`
  - `sold-out`
  - `oversold`
  - `no-key`

Those markers are folded into the final `requestOutcomes[*].semantics` snapshot.

## 4. What the outcome ledger now contains

Each `RequestOutcomeRecord` now includes:

- lifecycle state
- ordered state timeline transitions across request, delivery, and coordination scopes
- direct vs queued flow kind
- delivery semantics assessment when a queue is involved
- coordination decisions for idempotency, lock, and reservation behavior
- derived state tags such as:
  - `queued-delivery`
  - `retried`
  - `idempotency:duplicate`
  - `lock:contended`
  - `reservation:oversold`
- human-readable notes summarizing the semantic meaning

This is enough to support:

- results-tray semantic drill-downs
- searchable delivery and coordination transitions in retained outcome rows
- future grading helpers for "duplicate possible", "lock contended", or "oversold detected"

without changing the core queueing engine shape.

## 5. What this still does not do

This foundation is intentionally narrow.

It still does **not** provide:

- consumer-group offsets
- partition ordering truth
- commit-outcome ledger semantics
- quorum or replica acknowledgment semantics
- linearizability
- full L4 versus L7 behavioral divergence
- full protocol-specific delivery semantics

So authors must still treat these carefully:

- `exactly-once` is not first-class
- `consumer-groups` are not first-class
- `message-ordering` is not first-class
- `quorum` and `consensus` are deferred

## 6. What to build next

The next dependency-safe order remains:

1. consume support-ledger truth in more authoring and UI surfaces
2. extend delivery semantics into broker-specific behavior
3. add commit-outcome semantics for correctness-heavy questions
4. add replication and quorum behavior after that
5. add protocol-specific semantics only after the above support truth is explicit

## 7. Code map

- support ledger:
  - `src/engine/analysis/supportLedger.ts`
- validator integration:
  - `src/engine/analysis/authoringValidator.ts`
- runtime semantics contract:
  - `src/engine/core/simulationSemantics.ts`
- outcome record integration:
  - `src/engine/core/event-stream.ts`
  - `src/engine/engine.ts`
- coordination markers:
  - `src/engine/traits/idempotencyDedup.ts`
  - `src/engine/traits/lockLease.ts`
  - `src/engine/traits/reservationStore.ts`

This is the current foundation, not the final semantics architecture.

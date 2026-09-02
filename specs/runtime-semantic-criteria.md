# Runtime Semantic Criteria

Date: 2026-09-01

## 1. Why this exists

The runtime-semantics foundation (see
`support-ledger-and-runtime-semantics.md`) records a per-request
`stateTimeline` — the ordered transitions a request moves through across the
`request`, `delivery`, `broker`, `replication`, `protocol`, `idempotency`, `commit-outcome`, `lock`, and `reservation` scopes. That
foundation *records* semantic evidence but does not *grade* it.

This document defines the **authoring surface** that lets question authors grade
against that evidence: two new semantic criterion kinds, `stateTransition` and
`stateSequence`. Where the older semantic criteria (`placement`, `guardedPath`,
`fanout`, `storageFit`, `forbidUnjustified`) reason only about the **static
topology graph**, these two reason about **what actually happened at runtime**.

Example questions they unlock:

- "an oversell transition must **never** occur" (absence check)
- "at least one request must be **deduped** by the idempotency store"
- "a contended lock must resolve as `acquired → held → released` in order"
- "duplicate delivery must appear at least N times for a `retried` outcome"

## 2. Where runtime evidence comes from

`gradeAttemptWithArtifacts` builds a `SemanticContext.runtimeCases` array — one
entry per prepared suite case, each carrying that case's `SimulationOutput` (or
`null` when the case ran without a topology). The evaluator reads
`requestOutcomes[].stateTimeline` from those outputs. No new simulation is run;
these criteria consume the ledger the engine already produced.

## 3. Criterion syntax

Both kinds extend the common `CriterionBase` (`id`, `description?`, `points`,
`hardFail?`).

### 3.1 `stateTransition`

Counts matching transitions across all eligible request outcomes.

```jsonc
{
  "kind": "stateTransition",
  "match": { /* RuntimeStateTransitionMatcher, see §4 */ },
  "where": { /* RuntimeOutcomeFilter, optional, see §5 */ },
  "minCount": 1,   // default 1; how many matching transitions are required
  "maxCount": 0    // optional upper bound — key for absence checks
}
```

Outcome:

- **failed** if `maxCount` is set and the count exceeds it (absence violated).
- **passed** if `count >= minCount`.
- **partial** if `0 < count < minCount` and `minCount > 1`.
- **failed** otherwise.

Absence check pattern (e.g. "oversell must never happen"): set
`minCount: 0, maxCount: 0`.

### 3.2 `stateSequence`

Asserts that an **ordered** subsequence of transitions appears within a single
request's timeline, counted across eligible outcomes.

```jsonc
{
  "kind": "stateSequence",
  "sequence": [ /* ≥2 RuntimeStateTransitionMatcher entries, in order */ ],
  "where": { /* RuntimeOutcomeFilter, optional */ },
  "minMatches": 1  // minimum eligible outcomes whose timeline contains the sequence
}
```

The sequence matches as an ordered (not necessarily contiguous) subsequence of a
single outcome's timeline. Outcome:

- **passed** if `matches >= minMatches`.
- **partial** if `0 < matches < minMatches` and `minMatches > 1`.
- **failed** otherwise.

## 4. `RuntimeStateTransitionMatcher`

A matcher is discriminated by `scope`; the valid `state` values depend on the
scope. Optional narrowing fields apply to every scope.

| Field | Applies to | Meaning |
| --- | --- | --- |
| `scope` | all | one of `request`, `delivery`, `broker`, `replication`, `protocol`, `idempotency`, `commit-outcome`, `lock`, `reservation` |
| `state` | all | a timeline state valid for that scope (below) |
| `source` | all (optional) | which layer emitted the transition: `event`, `trait`, or `engine` |
| `nodeId` | all (optional) | restrict to a specific node id |
| `nodeType` | all (optional) | restrict to a component type |
| `reasonCode` | all (optional) | restrict to a specific reason code |

Valid `state` per scope (from `simulationSemantics.ts`):

- `request`: `generated`, `admitted`, `queued`, `processing`, `forwarded`,
  `retry-scheduled`, `completed`, `timed-out`, `rejected`, `in-flight`
- `delivery`: `producer-acked`, `released-to-consumer`,
  `redelivery-scheduled`, `dlq-routed`
- `broker`: `partition-assigned`, `group-delivered`, `offset-committed`,
  `retention-expired`, `broker-unavailable`, `broker-recovered`
- `replication`: `quorum-committed`, `quorum-unavailable`, `replica-read`,
  `stale-read-possible`, `leader-promoted`, `failover-in-progress`
- `protocol`: `session-open`, `session-closed`, `http-acknowledged`,
  `l7-rejected`, `flow-controlled`
- `idempotency`: `recorded`, `deduped`, `key-missing`
- `commit-outcome`: `intent-recorded`, `commit-confirmed`, `outcome-unknown`,
  `replay-blocked`
- `lock`: `attempting`, `acquired`, `contended`, `held`, `released`,
  `key-missing`
- `reservation`: `committed`, `sold-out`, `oversold`, `key-missing`

## 5. `RuntimeOutcomeFilter` (`where`)

Restricts which request outcomes are eligible before matching:

| Field | Meaning |
| --- | --- |
| `caseId` | only outcomes from this suite case |
| `outcomeStatus` | only outcomes with this terminal status |
| `terminalNodeId` | only outcomes whose terminal node has this id |
| `terminalNodeType` | only outcomes whose terminal node has this type |

If a `caseId` filter references a case not defined in `suite.cases[]`, the
authoring validator rejects the package (see §7).

## 6. Scoring

Consistent with the rest of the semantic layer:

- `passed` → full `points`
- `partial` → `floor(points / 2)`
- `failed` → `0`
- a `hardFail` criterion that does not pass **zeroes the whole question**

Results appear in `SemanticEvaluation.results[]` with `outcome`,
`pointsEarned`, `pointsPossible`, `hardFailed`, and a human-readable `detail`
explaining the count/expectation mismatch.

## 7. Authoring validation

`validateAuthoredQuestion` now checks, for any `stateTransition` /
`stateSequence` criterion, that a `where.caseId` (if present) matches a real
`suite.cases[].id`. A dangling case id fails as
`semantic.caseIdUnknown`, pointing at `semanticCriteria[i].where.caseId`.

## 8. Newton / Django authoring

Runtime semantic criteria are authored as `SEMANTIC_CRITERION` rows like any
other semantic criterion. `describeSemanticCriterion` provides default
human-readable summaries:

- `stateTransition` → "Required runtime transition must appear in the request
  timeline"
- `stateSequence` → "Runtime transition sequence must appear in request
  timelines"

## 9. What this does not do

- It does not add new runtime states — it grades the states the foundation
  already records. Broker entries show deterministic partition assignment and
  one delivery per configured consumer group, while commit outcomes show the
  local intent/confirmation/unknown/replay-blocked journal. Offset progression,
  retention enforcement, partition ordering, quorum, and reconciliation are
  not yet modeled as end-to-end runtime truth.
- `stateSequence` matches order, not adjacency or timing — it does not assert
  that two transitions were contiguous or within a time bound.
- It does not run additional simulation; it is a read over the retained request
  ledger.

## 10. Code map

- Criterion schema + types:
  - `src/engine/analysis/gradingCriteria.ts`
    (`StateTransitionCriterion`, `StateSequenceCriterion`,
    `RuntimeStateTransitionMatcher`, `RuntimeOutcomeFilter`)
- Evaluation:
  - `src/engine/analysis/semanticCriteria.ts`
    (`evalStateTransition`, `evalStateSequence`, `evaluateSemanticCriteria`)
- Runtime evidence wiring into grading:
  - `src/engine/analysis/question.ts` (`SemanticContext.runtimeCases`)
- Underlying state timeline:
  - `src/engine/core/simulationSemantics.ts`
- Authoring validation:
  - `src/engine/analysis/authoringValidator.ts` (`semantic.caseIdUnknown`)
- Newton authoring summaries:
  - `src/engine/analysis/newtonGamePlayground.ts` (`describeSemanticCriterion`)

# Design an event-notification backbone

`messaging-fanout` · type: `open-build` · workload: `connection-heavy` · difficulty: `beginner`

> You are designing the notification backbone that delivers every domain event to several independent downstream services (analytics, search indexer, email). You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

One producer publishes each event once. Each of the three downstream consumers must receive every event independently.

Traffic: 5,000 events/sec from a single producer.

At submission you will explain your choice of messaging primitive and its delivery guarantee trade-off.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | A broadcast broker is present (requires_component) |
|  | Broker fans out to ≥3 independent consumers; a work-queue to 3 is wrong (fanout, hardFail) |
| **[J]** justification | Broadcast vs work-queue delivery semantics (justify: why-broker) |
| **[N]** narrative | analytics/search/email backbone; 5,000 events/sec |

## Intended discrimination
fanout: a work-queue delivering to 3 consumers is not pub/sub fan-out.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/messaging-fanout
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/messaging-fanout/question.json \
  ns-simulator-docs/examples/question-bank/messaging-fanout/reference-topology.json
```

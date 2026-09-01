# Job-processing backend for a 15s SLA

`async-sla` · type: `open-build` · workload: `write-heavy` · difficulty: `advanced`

> You are decoupling a synchronous request path that fails under spikes. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Accept jobs quickly at ingest, hand them to an asynchronous queue, and process them with a pool of scalable workers within the SLA. Ingest must not block on processing.

Target: p99 job completion under 15 s during spike load.

Traffic: 50,000 jobs/min with bursty spikes (mostly writes).

At submission you will explain why using a queue meets the SLA better than a synchronous path, and what consistency trade-off you accept.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Async queue + scalable workers present (structural) |
|  | Ingest guarded through the queue to workers, no bypass (guardedPath) |
|  | p99 completion < 15 s (rubric); spike write load injected |
| **[J]** justification | Queue-decoupling rationale + consistency trade-off (justify: why-async) |
| **[N]** narrative | monolith spike decoupling; 50,000 jobs/min |

## Intended discrimination
structural + guardedPath: the gamed design is synchronous — no queue and no workers to decouple ingest.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/async-sla
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/async-sla/question.json \
  ns-simulator-docs/examples/question-bank/async-sla/reference-topology.json
```

# Ingest a large IoT sensor fleet

`sensor-store` · type: `open-build` · workload: `write-heavy` · difficulty: `intermediate`

> You are designing the ingestion backend for a large IoT fleet that keeps sending time-stamped readings. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Design an ingest path that sustains a very high write rate where new readings are only added, and supports range queries over recent time windows per sensor. Choose a storage engine whose access pattern matches time-series data.

Target: sustain the injected write throughput without dropping events.

Traffic: 200,000 writes/sec, with about 5% reads for recent-window range queries.

At submission you will explain your storage-engine choice for time-series data at this write rate.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Store fits time-series, not relational (storageFit, hardFail) |
|  | Sustains write throughput (rubric throughput); 200K write-dominant load injected |
| **[J]** justification | Time-series engine choice + join trade-off (justify: why-db) |
| **[N]** narrative | IoT fleet ingest; 200,000 writes/sec |

## Intended discrimination
storageFit + throughput: a relational DB cannot sustain 200K-scale time-series writes and saturates.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/sensor-store
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/sensor-store/question.json \
  ns-simulator-docs/examples/question-bank/sensor-store/reference-topology.json
```

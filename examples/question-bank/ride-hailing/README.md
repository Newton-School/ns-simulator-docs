# Design a ride-hailing match & payment backend

`ride-hailing` · type: `open-build` · workload: `read-heavy` · difficulty: `advanced`

> You are the lead infrastructure architect at a ride-hailing company preparing for a national-holiday surge. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Design a matching path that keeps nearby-driver lookups on a fast in-memory layer positioned between the service and the payment database, and a separate payment path that commits to a strongly consistent transactional database. Keep the hot matching path off the payment database.

Target: rider-to-driver match p99 latency under 3 s.

Traffic: 40,000 peak RPS at an 80:20 read-to-write ratio.

At submission you will explain why the nearby-driver hot path is separated from the payment store and how payments stay ACID-consistent.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Transactional DB present for payments (structural) |
|  | Payment store fits transactional-relational, not KV (storageFit) |
|  | Geospatial cache between service and payment DB (placement) |
|  | Match p99 < 3 s (rubric); 80:20 read/write injected |
| **[J]** justification | Hot/cold split + ACID payments (justify: why-hot-cold) |
| **[N]** narrative | ride-hailing holiday surge; 40,000 peak RPS |

## Intended discrimination
storageFit + placement: the gamed design puts payments on a KV store and drops the geospatial cache.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/ride-hailing
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/ride-hailing/question.json \
  ns-simulator-docs/examples/question-bank/ride-hailing/reference-topology.json
```

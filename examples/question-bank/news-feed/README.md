# Design a social news feed

`news-feed` · type: `open-build` · workload: `read-heavy` · difficulty: `intermediate`

> You are the architect for a social app's home feed. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Design a write path where posting an item fans it out to followers' timelines via a broadcast component to independent timeline builders, and a read path where a user loads their prebuilt timeline by direct lookup.

Target: feed-load (read-path) p99 latency under 200 ms.

Traffic: 50,000 peak RPS at a 98:2 read-to-write ratio. Timeline reads that hit the backing store directly will saturate it.

At submission you will explain your fan-out-on-write versus fan-out-on-read decision for this read ratio.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Broadcast fan-out to ≥2 independent timeline builders (fanout) |
|  | Timeline store fits point-lookup (storageFit) |
|  | Feed p99 < 200 ms (rubric); 98:2 read/write injected |
| **[J]** justification | Fan-out-on-write vs -on-read, cites the 50k scale (justify: why-fanout) |
| **[N]** narrative | social home feed; 50,000 peak RPS / 10M DAU |

## Intended discrimination
simulation p99 (< 200ms): removing the read cache saturates the timeline KV store.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/news-feed
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/news-feed/question.json \
  ns-simulator-docs/examples/question-bank/news-feed/reference-topology.json
```

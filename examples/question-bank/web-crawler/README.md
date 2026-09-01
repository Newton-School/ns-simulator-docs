# Design a distributed web crawler

`web-crawler` · type: `open-build` · workload: `batch-heavy` · difficulty: `expert`

> You are building a distributed crawler that must fetch billions of pages without crawling the same URL again. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Design a pipeline: URLs are checked against a dedup index before entering the frontier (crawl) queue, the frontier fans work out to many fetchers, and fetched pages flow through processors in order into object storage.

Target: sustain the injected aggregate crawl throughput.

Traffic: about 23,000 URLs/sec steady, mostly writes.

At submission you will explain your dedup mechanism (for example, Bloom filter vs exact index) before enqueue.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Frontier queue + dedup index present (structural) |
|  | URLs guarded through dedup before the frontier (guardedPath) |
|  | Ordered pipeline frontier→fetchers→processors (placement) |
|  | Aggregate throughput sustained (rubric) |
| **[J]** justification | Dedup mechanism + false-positive trade-off (justify: why-dedup) |
| **[N]** narrative | billions-of-pages crawler; ~23,000 URLs/sec |

## Intended discrimination
guardedPath: the gamed crawler enqueues URLs to the frontier without passing the dedup index.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/web-crawler
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/web-crawler/question.json \
  ns-simulator-docs/examples/question-bank/web-crawler/reference-topology.json
```

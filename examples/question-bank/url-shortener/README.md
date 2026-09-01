# Design a URL shortener

`url-shortener` · type: `open-build` · workload: `read-heavy` · difficulty: `intermediate`

> You are the lead infrastructure architect for a new URL-shortening service (like bit.ly). You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Design a write path that accepts a long URL and stores a short-code -> long-URL mapping in a durable store, and a read path that resolves a short code and issues an HTTP redirect.

Target: redirect (read-path) p99 latency under 100 ms at peak.

Traffic: 200,000 peak RPS at a 99:1 read-to-write ratio. Reads that fall through to the primary store will saturate it.

At submission you will explain your storage-engine choice for short-code lookups at this scale, your short-code generation and collision-handling strategy (for example, base62), and your redirect status code (301 vs 302).

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Durable store on the write path + fits point-lookup (structural + storageFit) |
|  | Redirect read-path p99 < 100 ms (rubric simulation) |
|  | 99:1 read/write injected as requestDistribution — uncached reads saturate the store (reinforcing loop) |
| **[J]** justification | Store fit, base62 code generation/collision handling, 301 vs 302 (justify: why-store) |
| **[N]** narrative | bit.ly-style scenario; 200,000 peak RPS / 50M DAU display scale |

## Intended discrimination
simulation p99 (< 100ms): removing the cache saturates the KV store.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/url-shortener
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/url-shortener/question.json \
  ns-simulator-docs/examples/question-bank/url-shortener/reference-topology.json
```

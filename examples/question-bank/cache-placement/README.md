# Scale a read-hot product API

`cache-placement` · type: `open-build` · workload: `read-heavy` · difficulty: `beginner`

> You are an SRE hardening a product-catalog API that has started to struggle under read traffic. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

All traffic must enter through a load balancer, reach the application service, and read from the primary database. Introduce and place a cache layer so reads are shielded from the database - it must sit on the path between the service and the database, never in front of the load balancer.

Target: read p99 latency under 120 ms at peak.

Traffic: 20,000 peak RPS at a 95:5 read-to-write ratio. Without the cache, reads will overwhelm the database.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Load balancer fronts the system (requires_component) |
|  | Accelerating layer between service and DB, not before the LB (placement) |
|  | Read p99 < 120 ms (rubric); 95:5 read/write injected |
| **[J]** justification | — none authored |
| **[N]** narrative | Product-catalog API under read pressure; 20,000 peak RPS |

## Intended discrimination
placement + p99 (< 120ms): with no cache between service and DB, reads saturate the relational DB.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/cache-placement
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/cache-placement/question.json \
  ns-simulator-docs/examples/question-bank/cache-placement/reference-topology.json
```

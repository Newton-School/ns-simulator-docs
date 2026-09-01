# Design a dynamic per-user API

`cargo-cult-cdn` · type: `open-build` · workload: `read-heavy` · difficulty: `intermediate`

> You are reviewing an architecture for an API that serves dynamic, per-user responses (personalized and not cacheable). You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.

Design the request path from the edge to the service and its data store. Add only components that earn their place - a CDN in front of content that cannot be cached is unnecessary.

Traffic: 8,000 peak RPS of personalized responses.

If you include a CDN, you will need to explain at submission what it actually speeds up here. Otherwise, leave it out.

## Files
- `question.json` - the QuestionPackage (prompt, structural rules, semantic criteria, suite, rubric). Traffic is driven by a Client (api-endpoint) source node feeding the topology.
- `reference-topology.json` - a **correct** design. Grades **PASS** on every checkable axis.
- `gamed-topology.json` - a plausible-but-wrong design. Grades **FAIL** on the intended axis.

> **V1 note:** the justification feature is hidden for launch, so `justify` is stored under `_justify` (ignored by the grader) and any `[J]` rows below are deferred to V2.

## Requirement buckets ([G]radeable / [J]ustification / [N]arrative)
Every requirement is backed by a check - no orphan requirements.

| Bucket | Requirement |
|--------|-------------|
| **[G]** gradeable | Single source of traffic (structural) |
|  | A CDN, if present, must be defended or it fails (forbidUnjustified) |
| **[J]** justification | Whether a CDN is warranted for non-cacheable traffic (justify: why-cdn) |
| **[N]** narrative | Personalized-API review; 8,000 peak RPS |

## Intended discrimination
forbidUnjustified: the gamed design adds a CDN with no benefit for dynamic traffic.

## Validate (from the ns-simulator-prod repo)
The harness grades the whole trio (structural, semantic, simulation):
```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/cargo-cult-cdn
```
Expect: reference PASSES all tests; gamed FAILS on the intended axis.

You can also grade a single topology headlessly (structural + semantic + simulation only — justifications show as unanswered):
```bash
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/question-bank/cargo-cult-cdn/question.json \
  ns-simulator-docs/examples/question-bank/cargo-cult-cdn/reference-topology.json
```

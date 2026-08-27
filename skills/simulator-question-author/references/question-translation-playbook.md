# Question Translation Playbook

Use this guide when turning a normal system design prompt into one or more simulator-ready assignment parts.

## 1. Required inputs

Collect these before authoring:

- raw prompt text
- source URL, source course, or author name
- explicit scale numbers
- interviewer hints or expected discussion topics
- any product context that must survive translation
- any missing assumptions you need to add

## 2. Requirement buckets

Every source statement must land in one bucket.

| Bucket | Use it for | Typical output |
| --- | --- | --- |
| `Structural` | The topology must contain a component, edge, path, redundancy shape, or count limit. | `STRUCTURAL_RULE` |
| `Semantic` | The chosen component or placement must mean the right thing for the workload. | `SEMANTIC_CRITERION` |
| `Simulation` | The design must hit a measurable runtime target under injected load. | `RUBRIC_CHECK` |
| `Justification` | The student should explain a decision that the engine cannot grade honestly today. | prompt prose or future justification surface |
| `Narrative` | Realism, framing, role-play, or context that is useful but not graded. | `question_text` only |
| `Split Trigger` | Evidence that this idea belongs in a different assignment part. | new part |

## 3. Split heuristics

Keep one part when most of these are true:

- one dominant path
- one dominant bottleneck domain
- one clear workload character
- one to three concepts
- one main reason the wrong design should fail

Split the question when any of these are true:

- the prompt mixes hot-path serving with async analytics or background processing
- the prompt mixes serving performance with policy, moderation, or abuse prevention
- two valid answers require contradictory grading logic
- the prompt needs different workload categories for different lessons
- the assignment would otherwise need too many unrelated grading rows

## 4. Assignment shape fields

Choose these fields before writing rows. Always choose both a grading archetype
and a learner-entry format.

### Question types

| `questionType` | Use when |
| --- | --- |
| `open-build` | The student builds the architecture from an empty scaffold. |
| `fix` | The student repairs a flawed starter topology. |
| `optimize` | The student improves a working but suboptimal baseline. |
| `build-budget` | The student must meet the goal under strict budget limits. |
| `scaling` | The lesson is about saturation, replicas, or capacity growth. |
| `ha-chaos` | The lesson is about redundancy and failure behavior. |
| `tradeoff` | Several defensible designs exist and the comparison itself is the lesson. |

### Entry formats

| `entryFormat` | Use when | Typical companion `questionType` |
| --- | --- | --- |
| `blank-canvas` | The student should start from an empty canvas. | `open-build`, `tradeoff` |
| `requirements-first` | The lesson should begin with explicit FR/NFR/scale decomposition, a wizard, or blueprint scaffolding before free editing. | `open-build`, `build-budget`, `tradeoff` |
| `partial-scaffold` | The student should complete a bounded starter topology. | `open-build`, `scaling`, `ha-chaos` |
| `broken-scaffold` | The student must repair a flawed starter topology. | `fix` |
| `baseline-optimize` | The student must improve a weak baseline and compare against what exists. | `optimize` |
| `locked-lab` | The student should mostly vary parameters on a fixed topology. | lab-style exercises |

Rule of thumb:

- `questionType` says how the package grades
- `entryFormat` says how the learner enters
- do not overload `questionType` to imply the shell

### Domains

Use the dominant lesson axis, not every technology named in the prompt.

| Domain | Use when the lesson is mainly about |
| --- | --- |
| `compute` | service tiers, workers, concurrency, CPU saturation |
| `storage` | primary store choice, cache/store interaction, read/write fit |
| `network` | routing, transport, latency, network physics, edge behavior |
| `resilience` | retries, failover, redundancy, failure containment |
| `correctness` | guarding invariants, safe write paths, consistency-oriented architecture |
| `cost` | budget pressure, anti-kitchen-sink scoring, resource tradeoffs |

### Workload categories

| `workloadCategory` | Use when |
| --- | --- |
| `read-heavy` | hot read path dominates and caching or lookup-fit matters |
| `write-heavy` | write throughput or write amplification is the main lesson |
| `connection-heavy` | fan-out, brokers, shared state, or session traffic dominates |
| `correctness-heavy` | correctness architecture matters more than runtime performance |
| `batch-heavy` | ordered pipelines and sustained throughput matter more than request latency |

## 5. Display scale vs tractable scale

Keep both of these true at once:

- the prompt should look like the real interview problem
- the suite should remain runnable and discriminative in the browser

Use this rule:

- keep real `DAU`, peak `RPS`, and read/write ratio in `question_text`
- inject a compressed `baseRps`, usually in the low-thousands
- preserve the same traffic mix and dominant bottleneck
- preserve the same reason the wrong design fails

Bad compression:

- shrinking load until both good and bad designs pass
- changing the read/write ratio enough to remove the intended bottleneck
- using random failure or jitter as a substitute for missing architectural pressure

## 6. Prompt rewrite pattern

For each part, write `question_text` in this order:

1. scenario paragraph
2. required path or system behavior paragraph
3. target paragraph
4. modeling disclaimer when needed
5. traffic and scale paragraph
6. submission explanation paragraph
7. `Functional Requirements` section
8. `Non-Functional Targets` section
9. `Scale` section

Use raw HTML. Keep the prose concrete and bounded.

## 7. Row emission contract

The final Newton-facing file should contain:

1. `question_type: GAME`
2. `question_title`
3. `question_text` as raw HTML
4. `initial_game_state: {}`
5. ordered Django test-case rows

Row order:

1. `SIMULATOR_CONFIG`
2. zero or more `STRUCTURAL_RULE`
3. zero or more `SEMANTIC_CRITERION`
4. one or more `RUBRIC_CHECK`

Use this mapping discipline:

- if the graph must contain a thing, use a structural rule
- if the thing exists but the type or placement must be appropriate, use a semantic criterion
- if the engine already reports the metric, use a rubric check
- if the engine cannot grade it honestly, keep it in explanation or narrative form
- make `SIMULATOR_CONFIG.entryFormat` explicit when the learner shell matters

## 8. Multiple valid solutions

The simulator should grade an authored solution space, not one frozen reference topology.

Use these patterns:

### Same family, several valid component variants

Use broad structural rules and semantic `accept` lists.

Example:

- `kv-store` and `nosql-db` can both satisfy point lookup
- `relational-db` can remain an anti-pattern

### Different families with one common lesson

Use:

- common structural gates that every valid family must satisfy
- common runtime checks that every valid family must satisfy
- family-specific semantic acceptance logic

Example:

- a news-feed question might allow `fanout-on-write` or a hybrid celebrity path
- both still need durable writes and acceptable feed latency

### Different families that require contradictory lessons

Split into separate assignment parts. Do not force one question to grade two different pedagogical goals.

## 9. Author validation loop

Before shipping, verify all of these:

- one intended good topology passes
- one plausible gamed topology fails
- the failure happens on the intended axis
- unsupported concerns stay narrative-only
- the prompt, suite, and row logic all teach the same lesson

## 10. Mini example

Source prompt:

> Design a URL shortener like bit.ly. Reads are much higher than writes, and redirect latency must stay low at peak.

Translation summary:

- dominant lesson: read-heavy hot path
- domains: `compute`, `storage`
- concepts: `read-cache`, `store-fit`
- workload category: `read-heavy`
- semantic expectation: point-lookup store on the read path
- runtime expectation: redirect-path p99 under target
- deferred concerns: code generation strategy and redirect-code choice stay explanation-only

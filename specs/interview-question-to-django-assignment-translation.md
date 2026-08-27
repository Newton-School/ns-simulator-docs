# Translating Interview-Style System Design Questions into Simulator Newton Assignments

> **Purpose.** Define the manual authoring workflow for converting a normal
> interview-style or prep-style system design prompt into one or more
> simulator-ready Newton assignments authored in the
> `django-admin-assignment.md` shape.
>
> **Primary outputs.** For each translated assignment part:
> 1. rewritten `question_text` HTML
> 2. ordered Django test-case rows (`SIMULATOR_CONFIG`, `STRUCTURAL_RULE`,
>    `SEMANTIC_CRITERION`, `RUBRIC_CHECK`)
> 3. explicit reasoning for what was kept, split, downgraded to justification,
>    or dropped
>
> **Grounding examples.** Existing exemplars live in:
> - [url-shortener/django-admin-assignment.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/system-design-simulator-questions/questions/url-shortener/django-admin-assignment.md)
> - [messaging-fanout/django-admin-assignment.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/system-design-simulator-questions/questions/messaging-fanout/django-admin-assignment.md)
> - [news-feed/django-admin-assignment.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/system-design-simulator-questions/questions/news-feed/django-admin-assignment.md)
> - [evaluation-authoring-reference-manual.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/ns-simulator-prod/ns-simulator-docs/specs/evaluation-authoring-reference-manual.md:843)

## 1. Problem Statement

Most system design questions found online are written for a live conversation:

- broad product framing
- many simultaneous concerns
- open-ended tradeoff discussion
- vague or unstated workloads
- no deterministic notion of "correct enough"

The simulator cannot grade that raw form directly.

The simulator needs a question that is:

- bounded
- teachable
- discriminative
- expressible as topology + workload + checks
- authorable in Newton's Django row format

The job of translation is therefore **not** to transcribe the original prompt.
The job is to **extract the lesson** and turn it into a simulator assignment that
still feels like the original question, but is precise enough to grade.

## 2. Governing Principles

### 2.1 Translate the lesson, not the wording

An interview prompt is a conversation starter. A simulator question is a
teaching and grading contract.

Keep:

- the real product scenario
- the dominant bottleneck
- the important workload character
- the key design decision the student must demonstrate

Do not keep by default:

- every sub-problem mentioned in the source
- vague "discuss tradeoffs" language with no grading path
- unsupported concerns presented as if the engine simulates them

### 2.2 One assignment should usually have one dominant lesson

A good simulator assignment usually has:

- 1 dominant bottleneck domain
- 1 primary path or paired read/write paths that serve one lesson
- 1-3 concepts
- 2-6 meaningful grading rows beyond `SIMULATOR_CONFIG`

If the source question meaningfully spans several independent lessons, split it.

### 2.3 Gradeable facts must map to explicit checks

Every requirement in the final assignment must fall into one of these buckets:

- `Structural`
- `Semantic`
- `Simulation`
- `Justification`
- `Narrative`

Nothing should remain as "important but untracked."

### 2.4 The final authoring target is Django rows, but the thinking layer is richer

Authors should not begin with JSON rows.

The correct order is:

1. source prompt
2. translation worksheet
3. per-part simulator design
4. `question_text` HTML
5. Django row emission

Rows are the **deployment format**, not the thinking format.

### 2.5 Preserve real-world scale in the prompt, but compress runtime load in the suite

The prompt should show the real-world numbers.

The injected simulator workload should be a **tractable representative load** that
preserves the same character:

- same dominant ratio
- same stressed path
- same intended failure mode

See [evaluation-authoring-reference-manual.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/ns-simulator-prod/ns-simulator-docs/specs/evaluation-authoring-reference-manual.md:106) for the display-scale vs tractable-scale rule.

## 3. What the Final Deliverable Must Contain

For each translated assignment part, the author must be able to produce a
complete `django-admin-assignment.md` containing:

### 3.1 Django question fields

- `question_type: GAME`
- `question_title`
- `question_text` as raw HTML
- `initial_game_state: {}`

### 3.2 Ordered test-case rows

At minimum:

1. `SIMULATOR_CONFIG`
2. zero or more `STRUCTURAL_RULE`
3. zero or more `SEMANTIC_CRITERION`
4. one or more `RUBRIC_CHECK`

### 3.3 Translation reasoning

The author must also be able to explain:

- why the source question was kept as one part or split into several
- why each requirement became structural, semantic, simulation, justification, or narrative
- why the suite workload is scaled the way it is
- why the selected grading rows discriminate the intended solution from a gamed one

## 4. Requirement Classification Model

Before writing `question_text` or rows, convert the source prompt into a
classification table.

| Bucket | Meaning | Typical output |
|--------|---------|----------------|
| `Structural` | The graph must contain a component, path, edge, count, or redundancy shape. | `STRUCTURAL_RULE` |
| `Semantic` | The graph must express the right *meaning* for the workload. | `SEMANTIC_CRITERION` |
| `Simulation` | The design must satisfy latency / throughput / error / invariant targets under injected load. | `RUBRIC_CHECK` |
| `Justification` | The student should explain a decision, but the engine should not decide correctness from runtime metrics alone. | prompt prose today; future `justify` |
| `Narrative` | Framing, product realism, context, or discussion prompts that are not graded. | `question_text` only |
| `Split Trigger` | A sign that this statement belongs in a separate assignment part. | new part |

### 4.1 Structural examples

- "Exactly one traffic source"
- "A durable store must be present"
- "The write path must reach the ledger"
- "There must be at least two replicas"

### 4.2 Semantic examples

- "Use a store suited for point lookup"
- "A broker must fan out to independent consumers"
- "A payment write must pass through an idempotency guard"
- "A cache is only valid if it sits between the app and the store"

### 4.3 Simulation examples

- "Read-path p99 under 100 ms"
- "Error rate under 5%"
- "No invariant violations"
- "Throughput at least 150 req/s"

### 4.4 Justification examples

- "Explain 301 vs 302"
- "Defend your store choice"
- "Explain code generation and collision handling"
- "Defend fan-out-on-write versus fan-out-on-read"

### 4.5 Narrative examples

- "Like bit.ly"
- "You are the lead architect"
- "The product is growing quickly"
- "This is a core user-facing experience"

## 5. Mandatory Translation Worksheet

The author must fill this worksheet before authoring rows.

A fill-in template version lives at
[interview-question-translation-worksheet-template.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/ns-simulator-prod/ns-simulator-docs/specs/interview-question-translation-worksheet-template.md).

That worksheet template now includes a worked example based on a
URL-shortener prompt. Authors should treat the filled sample rows as a pattern
reference, then duplicate, replace, or delete them while translating their own
question.

The worksheet set also has a companion reference pack at
[interview-question-translation-reference-pack.md](/Users/hritvikmohan/Desktop/HM25/ns-simulator-prod/ns-simulator-prod/ns-simulator-docs/specs/interview-question-translation-reference-pack.md),
which collects a glossary plus the reusable authoring tables imported from
`evaluation-authoring-reference-manual.md`.

### 5.1 Source capture

- original prompt text
- source URL or author
- any interviewer hints or expected discussion topics
- any scale numbers explicitly given
- any unstated but necessary assumptions

### 5.2 Statement extraction

Break the source into atomic statements:

| ID | Source statement | Inferred meaning | Bucket | Keep / Split / Drop | Reason |
|----|------------------|------------------|--------|---------------------|--------|

The author should be able to point to every line in the final assignment and say
which source statement it came from.

### 5.3 Part definition

For each resulting assignment part:

| Field | Definition |
|-------|------------|
| `partTitle` | The specific slice name |
| `studentAction` | What the student is being asked to build or fix |
| `domains` | 1-2 dominant bottleneck domains |
| `concepts` | 1-3 specific concepts |
| `workloadCategory` | dominant traffic character |
| `questionType` | usually `open-build`, sometimes `fix` or `tradeoff` |
| `entryFormat` | the learner-entry shell: `blank-canvas`, `requirements-first`, `partial-scaffold`, `broken-scaffold`, `baseline-optimize`, or `locked-lab` |
| `intendedBadDesign` | the most plausible wrong answer |
| `proofOfDiscrimination` | why the wrong answer should fail |

### 5.3.1 Choose `questionType` and `entryFormat` separately

`questionType` and `entryFormat` answer different questions:

- `questionType`: what grading archetype is this?
- `entryFormat`: what surface does the learner start from?

Use this matrix:

| `entryFormat` | Use when | Typical companion `questionType` |
|---------------|----------|----------------------------------|
| `blank-canvas` | The student should design from scratch with no starter topology. | `open-build`, sometimes `tradeoff` |
| `requirements-first` | The student should start from explicit FR/NFR/scale decomposition, wizard steps, or blueprint scaffolding before touching the canvas. | `open-build`, `build-budget`, `tradeoff` |
| `partial-scaffold` | The topology should start half-built so the student completes a bounded design. | `open-build`, `scaling`, `ha-chaos` |
| `broken-scaffold` | The student must repair a flawed starter topology. | `fix` |
| `baseline-optimize` | The student must improve a working but weak baseline and usually compare against a prior verdict. | `optimize` |
| `locked-lab` | The student should manipulate parameters on a fixed topology rather than edit architecture shape. | lab-style lessons; the stored `questionType` may still be `open-build` |

Authoring rule:

- choose `questionType` first for grading semantics
- choose `entryFormat` second for the learner shell
- rely on inference only for legacy questions you are not rewriting

### 5.4 Output traceability

For each part, create a final traceability table:

| Final item | Source statement(s) | Bucket | Output location |
|------------|---------------------|--------|-----------------|
| prompt paragraph | S1, S2 | Narrative | `question_text` |
| "exactly one source" | S3 | Structural | row `STRUCTURAL_RULE: single-source` |
| "point lookup store" | S4 | Semantic | row `SEMANTIC_CRITERION: store-fit` |
| "p99 < 100 ms" | S5 | Simulation | row `RUBRIC_CHECK: p99` |

This table is the best defense against drift and accidental cargo-cult authoring.

## 6. When One Interview Question Must Become Multiple Simulator Questions

### 6.1 Split when the prompt contains independent lessons

Split the source into 2 or more simulator assignments when any of the following
is true:

1. The question has **more than one dominant bottleneck domain** that would need
   different grading logic or edit policies.
2. The question has **several unrelated critical paths** whose correct answers do
   not depend on the same central design choice.
3. A single assignment would require the student to pass **too many orthogonal
   semantic checks** to be legible.
4. The source prompt is really a whole product ("design Twitter", "design Uber")
   rather than one simulator-sized lesson.
5. The engine cannot honestly simulate some major part of the source prompt, but
   another part *is* simulatable and worth preserving.

### 6.2 Do not split when one lesson can still dominate

Do not split just because the problem mentions both read and write paths.

Keep it as one assignment when:

- both paths support the same main lesson
- the read/write pairing is necessary to make the bottleneck obvious
- the semantic checks remain legible
- the intended gamed design is still clear

The existing `news-feed` example keeps fan-out-on-write and prebuilt read-path
lookup in one assignment because both serve one read-heavy lesson.

### 6.3 Recommended split heuristic

If a prompt has more than:

- 2 dominant paths
- 2 dominant domains
- 3 core concepts
- 6 meaningful grading rows

then it should normally split.

### 6.4 Typical split patterns

| Source prompt shape | Better simulator split |
|---------------------|------------------------|
| `Design Twitter` | feed write fanout, feed read path, maybe notifications |
| `Design Uber` | trip-match hot path, durable payment/correctness path |
| `Design Dropbox` | metadata/write path, read/download path |
| `Design YouTube` | upload pipeline, read delivery path |
| `Design WhatsApp` | delivery fanout, presence/state synchronization |

### 6.5 Example: "Design Twitter"

A conversational interview prompt might mix:

- post creation
- follower fanout
- timeline reads
- ranking
- notifications
- caching
- analytics
- ads

That is not one simulator question.

Reasonable simulator parts:

1. **Feed write fanout**
   - lesson: broadcast to independent consumers
   - concepts: `fan-out-on-write`, broker choice
2. **Feed read path**
   - lesson: direct lookup / cache / store-fit for prebuilt timelines
   - concepts: `read-cache`, `store-fit`
3. **Optional later part**
   - if the engine supports it, maybe ranking or multi-region distribution

Anything about ads ranking, ML ranking, abuse prevention, or search indexing
should be separate or narrative-only unless the lesson is specifically about it.

## 7. Manual Translation Workflow

### Step 1. Normalize the source prompt into simulator language

Rewrite the source into plain internal notes:

- who the user is
- what paths matter
- what the traffic character is
- what failure mode or bottleneck the good design must avoid
- what decision the student is really being tested on

Do not write HTML yet.

### Step 2. Choose the assignment slice

Write one sentence:

`The student must build/fix <specific path> so that <specific bottleneck lesson> is resolved under <specific workload>.`

If you cannot say this in one sentence, the prompt probably needs a split.

### Step 3. Choose metadata

For each part, author:

- `questionId`
- `questionType`
- `entryFormat`
- `domains`
- `concepts`
- `difficulty`
- `workloadCategory`

Guidelines:

- `questionType` is usually `open-build`
- `entryFormat` is often `requirements-first` for translated interview prompts
- use `fix` when the exercise is scaffold-first debugging
- use `broken-scaffold` when the learner must repair a flawed starter topology
- keep `domains` to 1-2 unless there is a strong reason
- keep `concepts` to 1-3

### 7.3 Domain selection guidance

| If the lesson is mainly about... | Use domain(s) |
|----------------------------------|---------------|
| overloaded services, sync blocking, saturation | `compute` |
| point lookup vs scan, write throughput, fanout storage shape | `storage` |
| geo latency, bandwidth, explicit edge tuning | `network` |
| retries, failover, resilience controls | `resilience` |
| exactly-once, idempotency, no-double-book | `correctness` |
| fixing within a money cap | `cost` |

### 7.4 Workload category guidance

| Prompt shape | `workloadCategory` |
|--------------|--------------------|
| mostly reads | `read-heavy` |
| mostly writes | `write-heavy` |
| broker / shared-state / fanout lesson | `connection-heavy` |
| correctness / duplicate suppression / double-booking | `correctness-heavy` |
| pipelines / crawler / async jobs | `batch-heavy` |

### Step 4. Convert the source into explicit FR / NFR / Scale

The source prompt must be rewritten into:

- 1-3 functional requirements
- 0-3 non-functional targets
- explicit scale bullets

The simulator should not rely on vague terms like:

- "high scale"
- "fast"
- "very available"
- "lots of traffic"

If the source lacks numbers, the author must supply reasonable teaching numbers.

### Step 5. Decide what belongs in `question_text`

`question_text` must carry:

- scenario framing
- architecture-not-code framing
- explicit path description
- target latency / throughput / error wording
- traffic shape
- submission explanation prompts

### 7.5 `question_text` writing rules

Use this structure:

1. scenario paragraph
2. path paragraph
3. target paragraph
4. connector disclaimer paragraph if edges are in connector mode
5. traffic / scale paragraph
6. optional "At submission you will explain..." paragraph
7. `Functional Requirements`
8. `Non-Functional Targets`
9. `Scale`

### 7.6 Connector-mode disclaimer rule

If the assignment uses connector edges, explicitly say so in the prompt.

Recommended wording:

```html
<p>In this assignment, links are simple connectors. Focus on which components should connect, not on tuning per-link network properties.</p>
```

Do not ask the student to tune edge latency, bandwidth, or edge concurrency in a
connector assignment.

### Step 6. Convert real-world scale into a tractable suite

The prompt can show:

- `Peak RPS: 200,000`
- `Read / Write: 99:1`
- `DAU: 50,000,000`

But the graded workload should be a tractable representative load, often in the
`2,000-5,000` range, preserving:

- the same read/write mix
- the same relative bottleneck
- the same expected failure of the wrong design

### 7.7 Compression rule

Never compress blindly.

Good:

- display `200,000` peak RPS in the prompt
- inject `2,000` or `3,000` in the suite
- preserve `99:1`
- size the reference/gamed designs so the right answer still passes and the wrong answer still fails

Bad:

- shrinking the load until both correct and incorrect designs pass
- keeping the raw source ratio in prose but using a different ratio in the suite

### Step 7. Author the grading rows

The row order is mandatory:

1. `SIMULATOR_CONFIG`
2. `STRUCTURAL_RULE`
3. `SEMANTIC_CRITERION`
4. `RUBRIC_CHECK`

For every row:

- `hidden = false`
- `output = ""`
- `output_file = empty`

### 7.8 Row 1: `SIMULATOR_CONFIG`

This is the master row.

It must carry:

- question identity
- question type and entry format
- domains and concepts
- difficulty and workload category
- prompt source contract
- scaffold
- constraints
- suite
- rubric header
- environment profile

#### Recommended defaults

- `presentationMode: "raw-html"`
- `promptSource: "question_text"`
- `environmentProfile.mode: "ASSIGNMENT"`
- `chromeDensity: "minimal"`
- `rubricChecks: "LIVE_DURING_BUILD"`
- connector edges unless the lesson is explicitly network-driven
- choose `entryFormat` deliberately instead of leaving the runtime to infer it

#### Constraint guidance

Use constraints to keep the problem crisp:

- `maxNodeCount`
- `canModifyScaffold`
- `canRemoveScaffoldNodes`

Do not let the topology sprawl if the lesson is small.

### 7.9 `STRUCTURAL_RULE` guidance

Use structural rules for graph shape, not meaning.

Supported structural kinds include:

- `requires_component`
- `requires_category`
- `requires_edge`
- `requires_path`
- `requires_redundancy`
- `requires_connected_graph`
- `requires_single_source`
- `forbids_component`
- `max_component_count`
- `min_node_count`
- `max_node_count`

Use them for:

- "exactly one source"
- "must include a broker"
- "must reach durable storage"
- "must not include a CDN"
- "must have redundancy"

Do not use structural rules to encode store-fit or semantic correctness.

### 7.10 `SEMANTIC_CRITERION` guidance

Use semantic criteria for "the graph means the right thing."

Supported semantic kinds include:

- `placement`
- `guardedPath`
- `fanout`
- `storageFit`
- `forbidUnjustified`

Use them for:

- a cache must sit between app and store
- a payment write must pass through idempotency guard
- a broker must fan out to several independent consumers
- a store must fit point lookup / append-only / search / blob semantics
- a cargo-cult component must be absent unless justified

### 7.11 `RUBRIC_CHECK` guidance

Use rubric checks for measurable outputs:

- latency
- throughput
- error rate
- invariants
- utilization ceilings

Every assignment should normally include:

- at least one main outcome check
- `no invariant violations`

## 8. The Dual-Topology Validation Rule

An assignment is not finished when the rows look plausible.

It is only authored when:

1. a **reference topology** passes
2. a **gamed topology** fails on the intended axis

This is the same discrimination rule established in the authoring manual.

The author must be able to say:

- what the correct design is
- what the most plausible wrong design is
- which row catches the wrong design

If the wrong design passes, the assignment is under-constrained.

## 9. Recommended Question-Bank File Set

Even when Django rows are the final deployment artifact, the author should
maintain a local question folder like:

- `question.json`
- `django-admin-assignment.md`
- `reference-topology.json`
- `gamed-topology.json`
- `README.md`

Why:

- `question.json` is easier to validate locally
- the two topology files prove discrimination
- the Django file is then a projection of the same package

This avoids thinking only in host rows.

## 10. Naming Conventions for Split Variants

If a source question yields one assignment, use:

- `django-admin-assignment.md`

If it yields a domain-specific or combined variant, use suffixes:

- `django-admin-assignment-compute.md`
- `django-admin-assignment-storage.md`
- `django-admin-assignment-compute-storage.md`

The suffix should describe the lesson slice, not the original interview site.

## 11. Anti-Patterns

Avoid these:

### 11.1 Transcribing the internet prompt verbatim

This preserves ambiguity instead of authoring a lesson.

### 11.2 Forcing the whole product into one simulator question

"Design Twitter", "Design Uber", "Design YouTube" are usually not single
assignments.

### 11.3 Making everything a simulation check

Some ideas are semantic or justification-only. Do not fake runtime metrics for them.

### 11.4 Using connector edges but asking network questions

If the lesson is edge tuning, the assignment must move into a `network` domain
and upgrade edges accordingly.

### 11.5 Keeping vague NFRs

"Fast", "scalable", and "available" are not grading criteria.

### 11.6 Overly permissive topology size

If the student can add everything, the assignment becomes kitchen-sink design
instead of a discriminative question.

### 11.7 Missing the intended bad design

If the author cannot name the likely wrong answer, the question is not yet sharp enough.

## 12. Author Quality Checklist

Before shipping a translated assignment, verify:

- the question has one dominant lesson or has been split cleanly
- every important requirement is classified
- every gradeable requirement maps to rows
- `question_text` mentions only simulated or explicitly-justified concerns
- scale is explicit in the prompt
- suite load is compressed but faithful
- connector/network mode matches the prompt wording
- the assignment has a plausible gamed design
- the reference passes
- the gamed design fails for the intended reason

## Appendix A. Canonical `django-admin-assignment.md` Skeleton

~~~~md
# Django Admin Setup: <Question Title>

This authoring shape is for Newton assignment mode only.
Use it when the simulator is embedded through the generic GAME iframe with `?host=newton`.
Do not use this shape for standalone/local authoring at `https://systems-simulator.newtonschool.co/`; standalone/local must keep topology open/save available.

Justification prompts are currently hidden in the Newton assignment UI and are not graded, so do not include `justify` in the test-case rows for this flow.

## Frontend contract

- GAME iframe URL: `https://systems-simulator.newtonschool.co/?host=newton`
- Newton-hosted assignment mode must render `question_text` as raw Django HTML.
- The frontend translator must rebuild immutable simulator config from the test-case rows below, not from `initial_game_state`.
- `initial_game_state` stays mutable-only learner state. Do not paste the full `question.json` there.
- Newton-hosted assignment mode must hide topology `Open` / `Save` actions and disable `Ctrl/Cmd+O` and `Ctrl/Cmd+S`.
- Newton-hosted assignment mode must hide the header settings entry point.
- The authored assignment environment should stay explicit in `SIMULATOR_CONFIG`.
- Scaffold nodes stay locked.
- <connector/network note>
- <resource-edit note if needed>

## Django fields

- `question_type`: `GAME`
- `question_title`: `<Question Title>`
- `question_text`:

```html
<p>You are ... You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design ... explicit path(s) ...</p>
<p>Target: ...</p>
<p>In this assignment, links are simple connectors. Focus on which components should connect, not on tuning per-link network properties.</p>
<p>Traffic: ...</p>
<p>At submission you will explain ...</p>
<h3>Functional Requirements</h3>
<ul>
  <li>...</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>...</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>DAU:</strong> ...</li>
  <li><strong>Peak RPS:</strong> ...</li>
  <li><strong>Read / Write:</strong> ...</li>
</ul>
```

- `initial_game_state`:

```json
{}
```

- `initial_game_state` must stay mutable-only. Do not paste the full `question.json` here.

## Test-case mapping rules

- Create the rows in the exact order shown below.
- For every row: `hidden = false`, `output = ""`, `output_file = empty`.
- Paste each JSON block into the Django `input` field exactly as shown.

## Row 1

- `title`: `SIMULATOR_CONFIG: <question-id>`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "configVersion": "1.0",
  "questionId": "<question-id>",
  "questionVersion": "1.0",
  "questionType": "open-build",
  "entryFormat": "requirements-first",
  "domains": ["compute"],
  "concepts": ["some-concept"],
  "difficulty": "intermediate",
  "workloadCategory": "read-heavy",
  "presentationMode": "raw-html",
  "promptSource": "question_text",
  "scaffold": { "type": "empty" },
  "constraints": {
    "canModifyScaffold": true,
    "canRemoveScaffoldNodes": true,
    "maxNodeCount": 12
  },
  "suite": {
    "name": "<suite-name>",
    "visibleToStudent": false,
    "cases": [
      {
        "id": "baseline",
        "description": "Representative peak",
        "workload": {
          "baseRps": 2000
        }
      }
    ]
  },
  "rubric": {
    "id": "<rubric-id>",
    "passThreshold": 1
  },
  "environmentProfile": {
    "mode": "ASSIGNMENT",
    "visibility": {
      "prompt": true,
      "scaffoldSourceNodes": true,
      "gradingSuiteDetails": false,
      "liveMetrics": true,
      "rubricChecks": "LIVE_DURING_BUILD"
    },
    "capabilities": {
      "editPaletteList": null,
      "canEditScaffoldNodes": false,
      "canTriggerTestRuns": true,
      "edgeModel": "connector",
      "canEditEdges": false,
      "canEditResources": false,
      "canEditExecutionProfile": false
    },
    "graded": true,
    "chromeDensity": "minimal"
  }
}
```

## Row 2

- `title`: `STRUCTURAL_RULE: <id>`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "<id>",
  "kind": "requires_single_source",
  "description": "Exactly one source"
}
```

## Row 3

- `title`: `SEMANTIC_CRITERION: <id>`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "<id>",
  "kind": "storageFit",
  "description": "...",
  "accessPattern": "point-lookup",
  "accept": ["kv-store", "nosql-db"],
  "antiPattern": ["relational-db"],
  "points": 3
}
```

## Row 4

- `title`: `RUBRIC_CHECK: <id>`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "id": "<id>",
  "kind": "simulation",
  "description": "...",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 100,
  "points": 3
}
```
~~~~

## Appendix B. Prompt Contract for the Future Skill

The eventual skill should not merely "rewrite text." It should perform the same
translation workflow above and emit a full authoring artifact.

### B.1 Skill objective

Input:

- one interview-style source prompt
- optional source URL
- optional author notes
- optional preferred lesson focus

Output:

1. split recommendation
2. translation worksheet
3. one or more simulator assignment parts
4. complete `django-admin-assignment.md` content for each part

### B.2 Required reasoning steps

The skill must explicitly do all of the following:

1. extract atomic source statements
2. classify each statement into structural / semantic / simulation / justification / narrative / split trigger
3. recommend whether to keep as one part or split
4. define the dominant lesson for each part
5. choose `domains`, `concepts`, `workloadCategory`, `questionType`, and `entryFormat`
6. rewrite the prompt into raw HTML `question_text`
7. create the ordered Django rows
8. explain why the chosen rows discriminate the intended good and bad designs
9. mark anything unsupported by the simulator as narrative-only or justification-only rather than inventing fake simulation behavior

### B.3 Required output format

The skill should return:

1. `Translation Summary`
2. `Split Decision`
3. `Per-Part Reasoning`
4. `django-admin-assignment.md` block(s)
5. `Open Questions / Unsupported Areas`

### B.4 Prompt template for the future skill

```md
You are translating a system design interview-style question into one or more
ns-simulator Newton assignments.

Your task is not to paraphrase the source. Your task is to extract the lesson,
decide whether the problem must split into multiple simulator parts, and emit
full `django-admin-assignment.md` content for each part.

Follow these rules:

1. Classify every important source statement as structural, semantic,
   simulation, justification, narrative, or split trigger.
2. Prefer one dominant lesson per assignment part.
3. Split the prompt if one part would otherwise contain multiple independent
   bottlenecks or unrelated critical paths.
4. Keep real-world scale in the prompt, but compress suite load to a tractable
   representative load while preserving ratios and the intended bottleneck.
5. If the assignment uses connector edges, explicitly say so in `question_text`
   and do not author grading logic that depends on edge tuning.
6. Output complete Django rows in the exact order:
   `SIMULATOR_CONFIG`, `STRUCTURAL_RULE`, `SEMANTIC_CRITERION`, `RUBRIC_CHECK`.
7. Do not invent unsupported simulator features. Downgrade unsupported source
   ideas to justification-only or narrative-only.
8. Explain the intended good design and the most plausible gamed design for each part.

Return:

## Translation Summary
## Split Decision
## Part 1 Reasoning
## Part 1 django-admin-assignment.md
## Part 2 Reasoning (if needed)
## Part 2 django-admin-assignment.md (if needed)
## Unsupported / Deferred Concerns
```

This prompt should later be turned into a dedicated skill once the manual
workflow in this document is stable in real author usage.

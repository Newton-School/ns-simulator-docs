# Interview Question Translation Worksheet Template

Use this as the fill-in worksheet before writing `question_text`, `question.json`,
or `django-admin-assignment.md`.

One source question may produce one or more simulator assignment parts. Duplicate
the part-level tables as needed.

Worked example convention:

- The first filled row in each table is an illustrative example using a
  URL-shortener prompt.
- Delete, duplicate, or overwrite the example rows when authoring a real
  question.

## 1. Source Intake

| Source question title | Source URL / origin | Author / interviewer | Raw source prompt | Explicit scale numbers in source | Missing assumptions to supply | Initial fit judgement |
|-----------------------|---------------------|----------------------|-------------------|----------------------------------|-------------------------------|----------------------|
| Design a URL shortener | Existing Newton example adapted from an interview-style prompt | Example author | Design a URL-shortening service like bit.ly. Support short-link creation and redirect reads at very high read volume. | 50M DAU; 200k peak RPS; 99:1 read/write | Read path is the dominant lesson; connectors only; target redirect p99 under 100 ms | Keep as one simulator part focused on read-heavy storage fit and cache placement |
|                       |                     |                      |                   |                                  |                               |                      |

## 2. Atomic Statement Extraction

| Statement ID | Source statement | Interpreted meaning | Bucket (`Structural` / `Semantic` / `Simulation` / `Justification` / `Narrative` / `Split Trigger`) | Keep / Split / Drop | Why | Candidate simulator expression |
|--------------|------------------|---------------------|-------------------------------------------------------------------------------------------------------------------------------|---------------------|-----|-------------------------------|
| S1 | Design a URL-shortening service like bit.ly | Product framing for the lesson | `Narrative` | Keep | Preserves realism without forcing grading logic | `question_text` intro paragraph |
| S2 | Accept a long URL and store a short-code mapping durably | Write path needs a durable sink | `Structural` | Keep | The graph must include a durable write destination | Durable store on the write path |
| S3 | Resolve a short code and issue a redirect fast | Read path is the performance-critical path | `Simulation` | Keep | The assignment needs an explicit latency target | p99 latency rubric check |
| S4 | Reads massively outweigh writes | This is a read-heavy lesson | `Semantic` | Keep | Motivates cache placement and store choice | `workloadCategory: read-heavy` |
| S5 | 200k peak RPS with a 99:1 read/write split | Scale must shape the suite and prompt | `Simulation` | Keep | Determines suite ratios and stressed path | Display scale plus compressed suite load |
| S6 | Choose a store suited for short-code lookup | Store fit matters more than relational modeling | `Semantic` | Keep | Discriminates the intended good and bad designs | `SEMANTIC_CRITERION: storageFit` |
| S7 | Explain 301 vs 302 and short-code generation | The student should justify choices in prose | `Justification` | Keep | Important for learning, but not runtime-gradable today | Submission explanation paragraph |
| S8 | Add analytics, abuse prevention, and custom aliases | These are separate lessons that would clutter this part | `Split Trigger` | Split | They dilute the dominant redirect-path lesson | Defer to future assignment parts |
| S9 | | | | | | |

## 3. Split Decision

| Candidate part ID | Part title | Why this is a separate lesson | Dominant path | Dominant bottleneck domain(s) | Keep as part? (`Yes` / `No`) | Merge with / split from |
|-------------------|------------|-------------------------------|---------------|-------------------------------|-------------------------------|-------------------------|
| P1 | URL shortener core redirect path | One dominant lesson: point lookup store plus cache under read-heavy traffic | Redirect read path, with supporting write path | `compute`, `storage` | `Yes` | — |
| P2 | Click analytics pipeline | Separate async ingestion and reporting lesson | Click event ingest to downstream analytics | `streaming`, `storage` | `No` | Split from source; defer |
| P3 | Abuse prevention and custom aliases | Policy and product controls are not the same lesson as redirect performance | Moderation and policy enforcement | `policy`, `application` | `No` | Split from source; defer |

## 4. Part Definition

| Part ID | Student task sentence | Question type | Entry format | Difficulty | Domains | Concepts | Workload category | Connector or network edges | Intended good design | Intended gamed design | Why the gamed design should fail |
|---------|-----------------------|---------------|--------------|------------|---------|----------|-------------------|----------------------------|----------------------|----------------------|----------------------------------|
| P1 | Build a URL-shortener topology that keeps redirect reads fast while storing mappings durably. | `open-build` | `requirements-first` | `intermediate` | `compute`, `storage` | `read-cache`, `store-fit` | `read-heavy` | Connector edges only | App tier reads through cache and falls back to a point-lookup store; writes persist mappings durably | App tier reads and writes directly to a relational DB with no cache | Primary store saturates on the hot read path and breaches the latency target |
| P2 | | | | | | | | | | | |
| P3 | | | | | | | | | | | |

## 5. Prompt Rewrite Worksheet

Fill one row per part.

| Part ID | Question title | Scenario paragraph | Path paragraph | Target paragraph | Connector / network disclaimer | Traffic paragraph | Submission explanation paragraph | Functional requirement 1 | Functional requirement 2 | Functional requirement 3 | NFR 1 | NFR 2 | NFR 3 | DAU | Peak RPS | Read / Write | Other scale notes |
|---------|----------------|-------------------|----------------|------------------|--------------------------------|-------------------|----------------------------------|--------------------------|--------------------------|--------------------------|-------|-------|-------|-----|----------|--------------|------------------|
| P1 | Design a URL shortener | You are the lead architect for a URL-shortening service similar to bit.ly. | Design a write path that stores short-code mappings durably and a read path that resolves redirects quickly. | Keep redirect p99 under 100 ms at peak. | In this assignment, links are connectors. Focus on component placement and path shape, not per-edge tuning. | Traffic is read-heavy at a 99:1 read/write ratio, so store misses on the redirect path will saturate the primary store. | At submission, explain your store choice, collision-handling approach, and redirect code choice. | Accept a long URL and create a short-code mapping. | Resolve a short code to its long URL and issue a redirect. | Keep the mapping in a durable store. | Redirect p99 under 100 ms. | No invariant violations under the graded suite. | Avoid saturating the primary read path. | 50,000,000 | 200,000 | 99:1 | Compress runtime load while preserving the read-heavy bottleneck |
| P2 | | | | | | | | | | | | | | | | | |
| P3 | | | | | | | | | | | | | | | | | |

## 6. Suite Compression Worksheet

Fill one row per graded case.

| Part ID | Case ID | Real-world display scale | Tractable simulated `baseRps` | Request distribution | Why this compressed load preserves the lesson | Expected failure mode of wrong design | Expected pass condition of good design |
|---------|---------|--------------------------|-------------------------------|----------------------|----------------------------------------------|---------------------------------------|----------------------------------------|
| P1 | `peak` | 200k peak RPS at a 99:1 read/write split | 2000 | 99% reads / 1% writes | The compressed load still hammers the redirect path and reveals whether the store choice and cache placement are correct. | Relational-store-only design saturates the primary path and breaches p99. | Cache plus point-lookup store keeps redirect latency under target. |
| P1 | | | | | | | |
| P2 | | | | | | | |
| P3 | | | | | | | |

## 7. Structural Rule Planner

Use one row per intended `STRUCTURAL_RULE`.

| Part ID | Row order | Rule ID | Structural kind | Description | Required fields | Source statement IDs | Why this must be structural, not semantic |
|---------|-----------|---------|-----------------|-------------|-----------------|----------------------|-------------------------------------------|
| P1 | 1 | `single-source` | `requires_single_source` | Exactly one traffic source | none | S2, S3 | The topology shape must contain a single source node before any runtime evaluation starts. |
| P1 | | | | | | | |
| P2 | | | | | | | |
| P3 | | | | | | | |

## 8. Semantic Criterion Planner

Use one row per intended `SEMANTIC_CRITERION`.

| Part ID | Row order | Criterion ID | Semantic kind | Description | Full-credit shape | Partial-credit shape | Anti-pattern / hard fail | Points | Source statement IDs | Why this is semantic, not structural |
|---------|-----------|--------------|---------------|-------------|-------------------|----------------------|--------------------------|--------|----------------------|--------------------------------------|
| P1 | 1 | `store-fits-point-lookup` | `storageFit` | Short-code lookup should use a store suited for direct key lookup. | `kv-store` or `nosql-db` on the redirect path | in-memory cache present but backing store ambiguous | relational DB as the primary lookup store | 3 | S4, S5, S6 | The grading intent is about whether the chosen component means the right thing for the workload, not merely whether any store exists. |
| P1 | | | | | | | | | | |
| P2 | | | | | | | | | | |
| P3 | | | | | | | | | | |

## 9. Rubric Check Planner

Use one row per intended `RUBRIC_CHECK`.

| Part ID | Row order | Check ID | Check kind | Description | Metric | Operator | Value | Points | Source statement IDs | Why this is measurable in the simulator |
|---------|-----------|----------|------------|-------------|--------|----------|-------|--------|----------------------|-----------------------------------------|
| P1 | 1 | `p99` | `simulation` | Redirect p99 stays under the target. | `summary.latency.p99` | `<` | 100 | 3 | S3, S5 | The simulator already reports summary latency metrics under the injected suite. |
| P1 | 2 | `no-invariants` | `invariant` | No invariant violations occur during the graded run. | `invariantViolations.count` | `==` | 0 | 1 | S2, S3 | Invariant counters are directly measurable in the simulation output. |
| P2 | | | | | | | | | | |
| P3 | | | | | | | | | | |

## 10. Django Row Inventory

This is the pre-JSON row manifest for the final `django-admin-assignment.md`.

| Part ID | Final row order | Django row title | Row type | Purpose | Depends on which worksheet section(s) | Ready? (`Yes` / `No`) |
|---------|-----------------|------------------|----------|---------|--------------------------------------|-----------------------|
| P1 | 1 | `SIMULATOR_CONFIG: url-shortener` | `SIMULATOR_CONFIG` | Defines the prompt contract, domains, suite, and environment profile | Sections 4, 5, 6 | `Yes` |
| P1 | 2 | `STRUCTURAL_RULE: single-source` | `STRUCTURAL_RULE` | Enforces one traffic source in the topology | Sections 2, 7 | `Yes` |
| P1 | 3 | `SEMANTIC_CRITERION: store-fits-point-lookup` | `SEMANTIC_CRITERION` | Rewards a store choice suited to redirect lookups | Sections 2, 8 | `Yes` |
| P1 | 4 | `RUBRIC_CHECK: p99` | `RUBRIC_CHECK` | Verifies redirect latency under the graded suite | Sections 5, 6, 9 | `Yes` |
| P1 | 5 | `RUBRIC_CHECK: no-invariants` | `RUBRIC_CHECK` | Verifies the run does not violate invariants | Sections 5, 9, 12 | `Yes` |
| P2 | 1 | `SIMULATOR_CONFIG: ...` | `SIMULATOR_CONFIG` | | | |
| P3 | 1 | `SIMULATOR_CONFIG: ...` | `SIMULATOR_CONFIG` | | | |

## 11. Traceability Matrix

| Part ID | Final item | Output location (`question_text` / `SIMULATOR_CONFIG` / `STRUCTURAL_RULE` / `SEMANTIC_CRITERION` / `RUBRIC_CHECK`) | Source statement IDs | Why it belongs here |
|---------|------------|----------------------------------------------------------------------------------------------------------------------------------|----------------------|---------------------|
| P1 | Scenario and scale paragraphs | `question_text` | S1, S3, S5, S7 | They frame the lesson and preserve real-world realism without forcing unsupported grading. |
| P1 | Single source requirement | `STRUCTURAL_RULE` | S2, S3 | This is a topology-shape constraint the engine can check before scoring runtime behavior. |
| P1 | Point-lookup store fit | `SEMANTIC_CRITERION` | S4, S6 | The lesson is about choosing a component whose meaning matches the workload. |
| P1 | Redirect p99 under 100 ms | `RUBRIC_CHECK` | S3, S5 | This is the explicit measurable success target for the assignment. |
| P2 | | | | |
| P3 | | | | |

## 12. Validation Checklist

| Part ID | Reference topology path | Gamed topology path | Does reference pass? | Does gamed fail? | Intended failing axis of gamed design | Any unsupported concerns left narrative-only? | Final author sign-off |
|---------|-------------------------|---------------------|----------------------|------------------|---------------------------------------|-----------------------------------------------|----------------------|
| P1 | `EXAMPLE: questions/url-shortener/reference.topology.json` | `EXAMPLE: questions/url-shortener/gamed-relational-only.topology.json` | `Yes` | `Yes` | Primary-store saturation on the hot redirect path | `Yes` - redirect code choice and code-generation strategy stay explanation-only | |
| P2 | | | | | | | |
| P3 | | | | | | | |

## 13. Glossary

| Term | Plain-English meaning | Why it matters when authoring |
|------|------------------------|-------------------------------|
| `Structural rule` | A graph-shape requirement such as needing a source, a component, or a path. | Use it when the topology must contain a shape before any runtime scoring makes sense. |
| `Semantic criterion` | A meaning-level check that a component choice or placement matches the workload. | Use it when the lesson is about whether the chosen primitive is architecturally appropriate. |
| `Rubric check` | A measurable pass/fail check over simulator verdict metrics. | Use it for latency, throughput, availability, or invariant outcomes the engine already reports. |
| `Invariant` | A correctness condition that should always remain true during a run. | Authors use invariants to catch bad behavior that is not just about speed, such as broken guarantees or invalid states. |
| `Invariant violation` | A recorded break of one of those always-true correctness conditions. | If the verdict reports invariant violations, the design did something fundamentally wrong even if latency looked fine. |
| `no-invariants` | Common shorthand for a rubric check that requires `invariantViolations.count` to stay at zero. | Authors often add this as a safety check to prove the good design is not merely fast, but also behaviorally sound. |
| `Display scale` | The real-world numbers shown in the prompt, such as `200000` peak RPS. | Keep realism in the student brief even when the runtime suite is smaller. |
| `Tractable scale` | A compressed runtime load the browser can simulate, usually around low-thousands RPS. | Use it in `suite.cases[].workload.baseRps` while preserving the dominant bottleneck. |
| `Topology` | The graph of nodes and edges that the student builds in the simulator. | Many checks are about topology shape, not application-code details. |
| `Topology shape` | The arrangement of components and paths in the graph. | A question can fail because the shape is wrong even before runtime metrics are considered. |
| `Scale-fit semantics` | Whether the chosen component type makes sense for the workload and scale. | This is the reason `storageFit` and similar checks exist; a present component can still be the wrong primitive. |
| `Workload category` | The dominant traffic character, such as `read-heavy` or `write-heavy`. | It helps the author choose the right lesson and semantic checks. |
| `Entry format` | The learner-facing starting shell, such as `blank-canvas`, `requirements-first`, or `locked-lab`. | Authors choose this separately from `questionType` so the prompt wrapper and the grading archetype do not get conflated. |
| `Requirements-first` | A question that starts from explicit FR/NFR/scale breakdown, wizard steps, or blueprint scaffolding before the learner edits the canvas. | Use it when the lesson should begin with requirement decomposition rather than immediate free-play graph editing. |
| `Partial scaffold` | A starter topology with some of the architecture already placed. | Use it to bound the solution space without turning the question into a repair task. |
| `Broken scaffold` | A flawed starter topology that the learner must diagnose and repair. | Pair it with `questionType: fix` so authors and graders agree that the exercise is about repair. |
| `Baseline optimize` | A working but suboptimal starter design that the learner must improve. | Use it for optimization lessons, ideally with a visible baseline verdict for comparison. |
| `Locked lab` | A fixed topology where the learner mainly tweaks parameters and observes outputs. | Use it for guided labs and keep the scaffold locked so the lesson stays focused on the chosen concept. |
| `requestDistribution` | The typed traffic mix that says how much of the suite is read, write, `GET`, `POST`, and so on. | It is how the suite expresses ratios such as `99:1` read/write. |
| `Suite` | The set of graded simulation cases attached to a question. | This is where authors define the tractable runtime load and any fault scenarios. |
| `Case` | One simulation scenario inside the suite, such as a peak-load case. | Each case can have its own workload, faults, and global overrides. |
| `Dry run` | A student-triggered practice execution before final submission. | Authors should know whether an assignment allows dry runs and whether the visible case differs from hidden graded cases. |
| `Point lookup` | A direct get-by-key access pattern. | It usually points toward a key-value store or a NoSQL store rather than a relational store at scale. |
| `Access pattern` | The dominant way data is read or written, such as `point-lookup`, `time-series`, or `append-only-ledger`. | Authors use access patterns to justify store selection and `storageFit` criteria. |
| `storageFit` | A semantic check that asks whether the selected store type matches the access pattern. | It is how authors reward the right database primitive and reject a wrong but still technically connected store. |
| `Placement` | A semantic check about where a component sits in the path, such as between the app and the DB. | Useful when the lesson is not merely that a cache exists, but that it is placed in the right location. |
| `Guarded path` | A rule that all traffic of a certain kind must pass through a guard component. | Use it for rate limiters, dedup layers, locks, or idempotency gates. |
| `Ordered pipeline` | A path where several component types must appear in a specific order. | Useful for batch or processing pipelines where sequence is part of the lesson. |
| `Single source` | A topology with exactly one source node and no extra competing sources. | Frequently used to keep the question bounded and to stop authors from introducing ambiguous traffic origins. |
| `Path check` | A check that traffic can reach one component from another along a directed path. | This is the basic way to encode many functional requirements such as writes reaching a durable store. |
| `Redundancy` | Having enough replicas or equivalent instances to satisfy availability expectations. | Useful for structural rules when the lesson requires more than one copy of something. |
| `Fan-out` | A topology where one event or request must reach multiple downstream consumers. | Use it to distinguish queues from brokers and to grade broadcast-style lessons. |
| `Hard fail` | A criterion that should zero the question because the design is architecturally naive. | Reserve it for serious anti-patterns rather than minor imperfections. |
| `Partial credit` | A middle score for a defensible but not ideal design choice. | Authors use it when a component is not fully right, but also not bad enough to hard-fail. |
| `passThreshold` | The fraction of total rubric points required to pass the question. | This controls whether students need every point or only enough of the score to count as correct. |
| `Budget axis` | The grading dimension that penalizes wasteful overbuilding using cost, nodes, or edges. | Useful when authors want to stop kitchen-sink solutions that brute-force performance. |
| `Anti-kitchen-sink` | The idea that students should not spray unnecessary components everywhere just to pass. | Authors encode this with budget caps, `forbidUnjustified` checks, or component-count limits. |
| `Graph-consistent` | A justification answer that matches what the student actually placed in the topology. | This prevents answer stuffing, where a student writes about a component that is not really in the graph. |
| `Tradeoff` | What a design gains and what it gives up. | Authors often require tradeoffs in justification prompts so students cannot give one-sided answers. |
| `Latency p99` | The 99th-percentile latency: the value under which 99 percent of requests finish. | This is a common performance target because it captures tail latency rather than average speed. |
| `Throughput` | How much work the system completes per unit time, such as requests per second. | Use it when the lesson is about handling sustained load, not only low latency. |
| `Availability` | How often the system continues serving requests successfully. | Use it in simulation rubrics when failure handling or redundancy is part of the lesson. |
| `Error rate` | The fraction of requests that fail. | A design with acceptable latency but a high error rate is still failing the operational goal. |
| `Scaffold` | The starter topology or fixed nodes that the student begins with. | Important for partial-build and fix-style questions where authors want to bound the editing surface. |
| `Locked scaffold node` | A scaffold node the student is not allowed to modify or remove. | Use it when the assignment should preserve part of the given system while grading only the student-controlled parts. |
| `Connector edge` | A dumb wire used for placement-focused questions, without per-edge network physics. | Use it when the lesson is about component choice and path shape, not latency tuning. |
| `Network edge` | A modeled edge with network behavior and editable edge properties. | Use it only when the question genuinely teaches network tuning or transport behavior. |
| `Instance type` | The hardware SKU that controls vCPU, RAM, price, and performance defaults. | Relevant for sizing nodes when the question uses the newer `resources` block. |
| `Workload kind` | The execution profile of a node, usually `cpu-bound` or `io-bound`. | It changes derived concurrency and explains why stores and services expose different worker counts. |
| `Execution profile` | Another way of describing the node's workload kind and derived concurrency behavior. | Authors should understand it when sizing nodes through resources instead of only queue workers. |
| `Reference topology` | The intended good solution topology used in validation. | Authors should prove that it passes before shipping the assignment. |
| `Gamed design` | A plausible wrong design that looks superficially reasonable but should fail the assignment. | It proves the rubric discriminates real understanding from cargo-cult topology stuffing. |
| `Anti-pattern` | A component choice or shape the assignment should reject or hard-fail. | Use it to make the wrong answer explicit rather than hoping runtime metrics alone catch it. |
| `Authoring validator` | The validation layer that checks whether the question package is structurally sound and internally consistent. | It catches schema mistakes, missing mappings, and some authoring drift before students ever see the question. |
| `Raw HTML prompt` | Question text written as HTML instead of plain markdown. | Newton assignment mode renders this directly, so authors can structure the prompt with headings and lists. |

## 14. Imported Reference Tables

For the full imported reference tables from
[evaluation-authoring-reference-manual.md](evaluation-authoring-reference-manual.md),
use the companion pack:
[interview-question-translation-reference-pack.md](interview-question-translation-reference-pack.md).

That companion file is intended to stay in sync with the workbook reference tabs
and the glossary sheet.

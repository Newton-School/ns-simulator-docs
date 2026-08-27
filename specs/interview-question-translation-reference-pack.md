# Interview Question Translation Reference Pack

This reference pack accompanies the interview-question translation worksheet.
It pulls glossary help plus the reusable authoring tables from
`evaluation-authoring-reference-manual.md` into one place so authors can keep
the worksheet and the reference material side by side.

## Glossary

| Term | Plain-English meaning | Why it matters when authoring |
| --- | --- | --- |
| Structural rule | A graph-shape requirement such as needing a source, a component, or a path. | Use it when the topology must contain a shape before any runtime scoring makes sense. |
| Semantic criterion | A meaning-level check that a component choice or placement matches the workload. | Use it when the lesson is about whether the chosen primitive is architecturally appropriate. |
| Rubric check | A measurable pass/fail check over simulator verdict metrics. | Use it for latency, throughput, availability, or invariant outcomes the engine already reports. |
| Invariant | A correctness condition that should always remain true during a run. | Authors use invariants to catch bad behavior that is not just about speed, such as broken guarantees or invalid states. |
| Invariant violation | A recorded break of one of those always-true correctness conditions. | If the verdict reports invariant violations, the design did something fundamentally wrong even if latency looked fine. |
| no-invariants | Common shorthand for a rubric check that requires invariantViolations.count to stay at zero. | Authors often add this as a safety check to prove the good design is not merely fast, but also behaviorally sound. |
| Display scale | The real-world numbers shown in the prompt, such as 200k peak RPS. | Keep realism in the student brief even when the runtime suite is smaller. |
| Tractable scale | A compressed runtime load the browser can simulate, usually around low-thousands RPS. | Use it in suite.cases[].workload.baseRps while preserving the dominant bottleneck. |
| Workload category | The dominant traffic character, such as read-heavy or write-heavy. | It helps the author choose the right lesson and semantic checks. |
| Topology | The graph of nodes and edges that the student builds in the simulator. | Many checks are about topology shape, not application-code details. |
| Topology shape | The arrangement of components and paths in the graph. | A question can fail because the shape is wrong even before runtime metrics are considered. |
| Scale-fit semantics | Whether the chosen component type makes sense for the workload and scale. | This is the reason storageFit and similar checks exist; a present component can still be the wrong primitive. |
| requestDistribution | The typed traffic mix that says how much of the suite is read, write, GET, POST, and so on. | It is how the suite expresses ratios such as 99:1 read/write. |
| Suite | The set of graded simulation cases attached to a question. | This is where authors define the tractable runtime load and any fault scenarios. |
| Case | One simulation scenario inside the suite, such as a peak-load case. | Each case can have its own workload, faults, and global overrides. |
| Dry run | A student-triggered practice execution before final submission. | Authors should know whether an assignment allows dry runs and whether the visible case differs from hidden graded cases. |
| Point lookup | A direct get-by-key access pattern. | It usually points toward a key-value store or a NoSQL store rather than a relational store at scale. |
| Access pattern | The dominant way data is read or written, such as point lookup, time-series, or append-only ledger. | Authors use access patterns to justify store selection and storageFit criteria. |
| storageFit | A semantic check that asks whether the selected store type matches the access pattern. | It is how authors reward the right database primitive and reject a wrong but still technically connected store. |
| Placement | A semantic check about where a component sits in the path, such as between the app and the DB. | Useful when the lesson is not merely that a cache exists, but that it is placed in the right location. |
| Guarded path | A rule that all traffic of a certain kind must pass through a guard component. | Use it for rate limiters, dedup layers, locks, or idempotency gates. |
| Ordered pipeline | A path where several component types must appear in a specific order. | Useful for batch or processing pipelines where sequence is part of the lesson. |
| Single source | A topology with exactly one source node and no extra competing sources. | Frequently used to keep the question bounded and to stop authors from introducing ambiguous traffic origins. |
| Path check | A check that traffic can reach one component from another along a directed path. | This is the basic way to encode many functional requirements such as writes reaching a durable store. |
| Redundancy | Having enough replicas or equivalent instances to satisfy availability expectations. | Useful for structural rules when the lesson requires more than one copy of something. |
| Fan-out | A topology where one event or request must reach multiple downstream consumers. | Use it to distinguish queues from brokers and to grade broadcast-style lessons. |
| Hard fail | A criterion that should zero the question because the design is architecturally naive. | Reserve it for serious anti-patterns rather than minor imperfections. |
| Partial credit | A middle score for a defensible but not ideal design choice. | Authors use it when a component is not fully right, but also not bad enough to hard-fail. |
| passThreshold | The fraction of total rubric points required to pass the question. | This controls whether students need every point or only enough of the score to count as correct. |
| Budget axis | The grading dimension that penalizes wasteful overbuilding using cost, nodes, or edges. | Useful when authors want to stop kitchen-sink solutions that brute-force performance. |
| Anti-kitchen-sink | The idea that students should not spray unnecessary components everywhere just to pass. | Authors encode this with budget caps, forbidUnjustified checks, or component-count limits. |
| Justification | A prose explanation the student must give for a decision or tradeoff. | Use it for choices the simulator cannot honestly grade from runtime metrics alone. |
| Graph-consistent | A justification answer that matches what the student actually placed in the topology. | This prevents answer stuffing, where a student writes about a component that is not really in the graph. |
| Tradeoff | What a design gains and what it gives up. | Authors often require tradeoffs in justification prompts so students cannot give one-sided answers. |
| Latency p99 | The 99th-percentile latency: the value under which 99 percent of requests finish. | This is a common SLO-like performance target because it captures tail latency rather than average speed. |
| Throughput | How much work the system completes per unit time, such as requests per second. | Use it when the lesson is about handling sustained load, not only low latency. |
| Availability | How often the system continues serving requests successfully. | Use it in simulation rubrics when failure handling or redundancy is part of the lesson. |
| Error rate | The fraction of requests that fail. | A design with acceptable latency but a high error rate is still failing the operational goal. |
| Environment profile | The assignment/practice/author mode lens that controls visibility and edit capabilities. | It decides whether students can edit edges, resources, scaffold nodes, or test-run freely. |
| Scaffold | The starter topology or fixed nodes that the student begins with. | Important for partial-build and fix-style questions where authors want to bound the editing surface. |
| Locked scaffold node | A scaffold node the student is not allowed to modify or remove. | Use it when the assignment should preserve part of the given system while grading only the student-controlled parts. |
| Connector edge | A dumb wire used for placement-focused questions, without per-edge network physics. | Use it when the lesson is about component choice and path shape, not latency tuning. |
| Network edge | A modeled edge with network behavior and editable edge properties. | Use it only when the question genuinely teaches network tuning or transport behavior. |
| Instance type | The hardware SKU that controls vCPU, RAM, price, and performance defaults. | Relevant for sizing nodes when the question uses the newer resources block. |
| Workload kind | The execution profile of a node, usually cpu-bound or io-bound. | It changes derived concurrency and explains why stores and services expose different worker counts. |
| Execution profile | Another way of describing the node's workload kind and derived concurrency behavior. | Authors should understand it when sizing nodes through resources instead of only queue workers. |
| Reference topology | The intended good solution topology used in validation. | Authors should prove that it passes before shipping the assignment. |
| Gamed design | A plausible wrong design that looks superficially reasonable but should fail the assignment. | It proves the rubric discriminates real understanding from cargo-cult topology stuffing. |
| Anti-pattern | A component choice or shape the assignment should reject or hard-fail. | Use it to make the wrong answer explicit rather than hoping runtime metrics alone catch it. |
| Authoring validator | The validation layer that checks whether the question package is structurally sound and internally consistent. | It catches schema mistakes, missing mappings, and some authoring drift before students ever see the question. |
| Raw HTML prompt | Question text written as HTML instead of plain markdown. | Newton assignment mode renders this directly, so authors can structure the prompt with headings and lists. |

## Imported Reference Tables

### Table 01. 1.1 Discriminatory authoring

Source section: `Section 1 - Philosophy & The Authoring Recipe > 1.1 Discriminatory authoring`

| Axis | Symbol | Graded by | Measures |
| --- | --- | --- | --- |
| Topology | **T** | `structuralRules`, `placement`, `guardedPath`, `fanout` | shape of the graph |
| Scale-fit semantics | **S** | `storageFit`, scale-aware checks | right component for the workload |
| Simulation | **Σ** | `rubric` checks over verdict metrics | performance under injected load |
| Justification | **J** | `justify` prompts (graph-consistent) | reasoning, tradeoffs |
| Budget | **$** | `budget` | cost / anti-kitchen-sink |

### Table 02. 1.3 Workload characterization

Source section: `Section 1 - Philosophy & The Authoring Recipe > 1.3 Workload characterization`

| `workloadCategory` | Injected load | Dominant axis | Canonical hard problem |
| --- | --- | --- | --- |
| `read-heavy` | high read `requestDistribution` (e.g. 99% read) | Σ + S | caching is mandatory (store saturates without it) |
| `write-heavy` | high write mix | S + Σ | storage-fit for write throughput (right DB) |
| `connection-heavy` | fan-out / shared-state traffic | T | broker fan-out, shared counters |
| `correctness-heavy` | modest load | **T + J** (NOT Σ) | exactly-once, no-double-book, ordering |
| `batch-heavy` | sustained throughput, latency-insensitive | Σ (throughput) + T (pipeline) | ordered pipeline, dedup, aggregate throughput |

### Table 03. 2.2 Tractable vs display scale

Source section: `Section 2 - Workload & Scale Configuration > 2.2 Tractable vs display scale`

| Field | Purpose | Value guidance |
| --- | --- | --- |
| `prompt.scale.peakRps` | **display** - the real-world target shown in the brief | the real number (e.g. `200000`) |
| `prompt.scale.readWriteRatio` | **display** - shown as `99:1`; also the source the sim mix *should* mirror | the real ratio |
| `suite.cases[].workload.baseRps` | **tractable simulation load** the browser can actually run | **~2,000-5,000** rps |

### Table 04. 2.3 Traffic distributions (`requestDistribution`)

Source section: `Section 2 - Workload & Scale Configuration > 2.3 Traffic distributions (`requestDistribution`)`

| Field | Required | Rule |
| --- | --- | --- |
| `type` | ✅ | free string; used in edge `condition` (`request.type === "read"`) and GET/POST inference |
| `weight` | ✅ | fraction 0-1; weights across the array should sum to 1.0 |
| `sizeBytes` | ✅ (full topology) | payload bytes - drives bandwidth/serialization; **a full topology's entries require it** (the suite override tolerates its absence but a merged topology does not) |
| `metadata` | optional | untyped `Record<string, unknown>` escape hatch (not consumed by grading today) |

### Table 05. 2.4 Current topology-default semantics that affect authored questions

Source section: `Section 2 - Workload & Scale Configuration > 2.4 Current topology-default semantics that affect authored questions`

| Surface | Current behavior | Authoring consequence |
| --- | --- | --- |
| `suite.cases[].workload.pattern` | If you author a full workload, `pattern` must be explicit. The product's interactive defaults now favor **`constant`** traffic for predictability. | For deterministic graded cases, prefer `constant` unless arrival jitter is part of the lesson. Use `poisson` only intentionally. |
| Edge latency when no explicit edge latency is authored | The renderer/serializer now resolves a bare edge to a **path-type-derived constant median latency (no jitter)**. Log-normal latency only appears when the edge explicitly chooses the log-normal model or supplies `mu` / `sigma`. | If the question depends on latency variance or burst bunching, author explicit log-normal edge latency in the topology. Do not assume omitted latency means jitter. |
| Node capacity when `resources.instanceType` / `instanceCount` are present | The engine now treats the **instance model** as authoritative for effective concurrency on that node (derived from vCPU × count × execution profile - **§9**). Legacy nodes with no instance-model resources still run off raw `queue.workers` / `queue.capacity`. | For saturation / scaling questions, treat `resources` as part of the real topology DSL. Once you opt into instance-model resources, raw queue numbers are no longer the whole story - size via `instanceType` + `workloadKind`, not `workers`. |
| Cost in the live product vs cost in question grading | The app now has a richer instance-aware live cost model and resource displays, but **`budget.unit:"cost"` in question grading still uses the older v1 heuristic** from `budget.ts`. | Do not assume the UI cost chip and the graded `$` axis are numerically identical. Use `budget.nodes` / `budget.edges` for hard anti-kitchen-sink caps; treat `budget.cost` as a heuristic grading axis until the grading DSL is upgraded. |

### Table 06. 3.1 Mapping FRs to DSL obligations

Source section: `Section 3 - Functional Requirements (FR) Engine > 3.1 Mapping FRs to DSL obligations`

| FR intent | DSL obligation | Example |
| --- | --- | --- |
| "A component must exist" | `requires_component` | a load balancer fronts the system |
| "Traffic must reach X" | `requires_path` (directed) | payment path reaches the SQL store |
| "All traffic of a type must pass a guard" | `guardedPath` | rate-limit checks traverse the shared cache |
| "Component sits in the right position / order" | `placement` (`between`/`notBefore`/`orderedPipeline`) | cache between service & DB, not before the LB |

### Table 07. 4.1 Performance NFRs vs correctness NFRs - the hard boundary

Source section: `Section 4 - Non-Functional Requirements (NFR) & Simulation Rules > 4.1 Performance NFRs vs correctness NFRs - the hard boundary`

| NFR flavour | Simulatable? | Graded by |
| --- | --- | --- |
| **Performance** - latency, throughput, availability, utilization | ✅ | `rubric` `simulation` check |
| **Correctness** - consistency, exactly-once, ordering, immutability, no-double-book | ❌ | `storageFit` / `guardedPath` + `justify` - **NEVER** a `simulation` check |

### Table 08. 5.3 Structural rule kinds (full)

Source section: `Section 5 - Anti-Patterns, Hard Fails & Structural Checks > 5.3 Structural rule kinds (full)`

| `kind` | Extra fields | Passes when |
| --- | --- | --- |
| `requires_component` | `componentType`, `minCount?`(=1) | ≥ minCount nodes of the type |
| `requires_category` | `category`, `minCount?`(=1) | ≥ minCount nodes in the category |
| `requires_edge` | `fromType`, `toType`, `mode?` | an edge `fromType`→`toType` (of `mode`) exists |
| `requires_path` | `fromType`, `toType` | a directed path exists (BFS) |
| `requires_redundancy` | `componentType`, `minReplicas` | total replicas of the type ≥ minReplicas |
| `max_component_count` | `componentType`, `maxCount` | ≤ maxCount of the type |
| `min_node_count` / `max_node_count` | `count` | total nodes ≥ / ≤ count |
| `forbids_component` | `componentType` | zero of the type present |
| `requires_connected_graph` | - | every node reachable (undirected BFS) |
| `requires_single_source` | - | exactly one source node (no inbound edge) |

### Table 09. 6.1 Justification schema (`justify`)

Source section: `Section 6 - Justifications, Tradeoffs & Cost Constraints > 6.1 Justification schema (`justify`)`

| Field | Required | Rule |
| --- | --- | --- |
| `id` | ✅ | unique; referenced by `forbidUnjustified.justifyId` |
| `decision` | ✅ | the decision the student must defend |
| `boundTo` | optional | `{ nodeId?, componentType? }` - ties the answer to a real graph element |
| `requires.choice` | ✅ | graph-consistency gate: answer must name the component **actually placed** (anti-stuffing) |
| `requires.number` | optional | answer must cite a **scale/NFR number** this question defines |
| `requires.tradeoff` | ✅ | answer must state what is given up |
| `acceptTradeoffTokens` | optional | author-provided tradeoff keywords (else a default list) |

### Table 10. Section 7 - Master Property & DSL Reference Table

Source section: `Section 7 - Master Property & DSL Reference Table`

| Property Name / Key | Scope / Context | Data Type / Enum Values | Required / Optional | Description & Usage Rules | Gotchas & Validation Errors |
| --- | --- | --- | --- | --- | --- |
| `version` | QuestionPackage | `"1.0"` (literal) | Required | Package schema version. | Must equal `"1.0"`. |
| `id` | QuestionPackage | string | Required | Stable question id. | - |
| `title` | QuestionPackage | string | Required | Human title. | - |
| `description` | QuestionPackage | string | Optional | Long description. | - |
| `difficulty` | QuestionPackage | `beginner \| intermediate \| advanced \| expert` | Required | Difficulty tier. | - |
| `tags` | QuestionPackage | string[] | Optional | Free tags. | - |
| `estimatedTimeMinutes` | QuestionPackage | number | Optional | Est. solve time. | - |
| `type` | QuestionPackage | `fix \| build-budget \| optimize \| open-build \| scaling \| ha-chaos \| tradeoff` | Required | Question archetype. | - |
| `entryFormat` | QuestionPackage | `blank-canvas \| requirements-first \| partial-scaffold \| broken-scaffold \| baseline-optimize \| locked-lab` | Optional | Learner starting surface and wrapper style. Orthogonal to `type`: `type` says how the question grades, `entryFormat` says how the learner enters it. | Omitted fields stay backward-compatible via inference. Explicit mismatches trigger authoring-validator diagnostics such as `entryFormat.blankCanvasMismatch`, `entryFormat.baselineVerdictMissing`, or `entryFormat.lockedLabUnlocked`. |
| `workloadCategory` | QuestionPackage | `read-heavy \| write-heavy \| connection-heavy \| correctness-heavy \| batch-heavy` | Optional | Primary evaluation axis selector. | No `compute`/`equal` enum - `batch-worker` node is category `compute`; "equal" = a 0.5/0.5 `requestDistribution`. |
| `domains` | QuestionPackage | `QuestionDomain[]` (`compute \| storage \| network \| resilience \| correctness \| cost`) | Optional but strongly recommended | Declares the bottleneck domain(s) the question is teaching. Drives authoring-validator consistency checks and platform behavior such as edge/resource edit policy. | Missing ⇒ validator `domains.missing`; `network` / `resilience` / `cost` currently warn as V2 domains. |
| `concepts` | QuestionPackage | `string[]` (non-empty kebab-case slugs by convention) | Optional | Fine-grained lesson tags, narrower than `domains` (for example `read-cache`, `store-fit`, `async-decoupling`). | Free-form metadata today; schema enforces only non-empty strings. |
| `author` | QuestionPackage | string | Optional | Author id. | - |
| `createdAt` | QuestionPackage | ISO string | Optional | Timestamp. | - |
| `prompt.text` | prompt | string (markdown) | Required | Problem statement. | Frame as "design the architecture, not code". |
| `prompt.functionalRequirements` | prompt | string[] | Required | FRs (prose). | Not parsed - each must map to an obligation (§3) or be labeled context. |
| `prompt.nonFunctionalRequirements` | prompt | `NFRTarget[]` | Required | Structured NFRs. | Orphan NFR (no matching rubric check) ⇒ validator `nfr.orphan`. |
| `prompt.scale` | prompt | `ScaleParameters` | Required | Display + derivation numbers. | Feeds grade-time workload derivation when a suite case omits `workload.baseRps` / `requestDistribution`; explicit case overrides still win. |
| `prompt.additionalContext` | prompt | string | Optional | Extra context. | - |
| `NFRTarget.metric` | NFR | `latency_p99 \| latency_p50 \| availability \| error_rate \| throughput` | Required | NFR metric. | Distinct from verdict metric keys. |
| `NFRTarget.operator` | NFR | `< \| <= \| > \| >=` | Required | Comparison. | - |
| `NFRTarget.value` | NFR | number | Required | Target value. | - |
| `NFRTarget.unit` | NFR | `ms \| percent \| req_per_sec \| nines` | Required | Unit. | - |
| `NFRTarget.description` | NFR | string | Required | Student-facing label. | - |
| `scale.dau` | scale | number ≥ 0 | Optional | Daily active users (display). | - |
| `scale.peakRps` | scale | number ≥ 0 | Optional | Real-world peak (display + derivation). | Grade-time workload derivation uses this when a case omits `workload.baseRps`; keep explicit case `baseRps` only for scenario-specific overrides. |
| `scale.readWriteRatio` | scale | number 0-100 | Optional | Reads % (display + derivation). | Grade-time workload derivation synthesizes a typed `read`/`write` `requestDistribution` when a case omits one, reusing the source workload's request sizes. |
| `scale.storageGb` | scale | number ≥ 0 | Optional | Storage size (display). | - |
| `scale.retentionDays` | scale | number ≥ 0 | Optional | Retention (display). | - |
| `scale.growthRatePercent` | scale | number ≥ 0 | Optional | Growth (display). | - |
| `scaffold.type` | scaffold | `empty \| partial \| complete` | Required | Starting canvas. | `partial`/`complete` require a `topology`. |
| `scaffold.topology` | scaffold | `TopologyJSON` | Conditional | Given nodes/edges. | Required unless `type: "empty"`. |
| `scaffold.lockedNodeIds` | scaffold | string[] | Optional | Immutable nodes. | - |
| `scaffold.lockedEdgeIds` | scaffold | string[] | Optional | Immutable edges. | - |
| `scaffold.baselineVerdict` | scaffold | `SimulationVerdict` | Optional | Baseline to beat (`optimize`). | Must be a versioned verdict. |
| `constraints.canModifyScaffold` | constraints | boolean | Required | May edit scaffold nodes. | - |
| `constraints.canRemoveScaffoldNodes` | constraints | boolean | Required | May delete scaffold nodes. | - |
| `constraints.allowedNodeTypes` | constraints | string[] | Optional | Palette allowlist. | - |
| `constraints.forbiddenNodeTypes` | constraints | string[] | Optional | Palette denylist. | - |
| `constraints.maxNodeCount` | constraints | number | Optional | Hard node ceiling. | - |
| `constraints.maxBudget` | constraints | number | Optional | Hard cost ceiling. | Distinct from graded `budget`. |
| `constraints.maxTotalWorkers` | constraints | number | Optional | Hard worker ceiling. | - |
| `structuralRules[].id` | structuralRule | string | Required | Unique id. | Duplicate ids rejected. |
| `structuralRules[].description` | structuralRule | string | Required | Row label + failure text prefix. | Never parsed; only echoed. |
| `structuralRules[].kind` | structuralRule | see §5.3 | Required | Rule kind. | - |
| `…componentType` / `category` / `fromType` / `toType` / `mode` / `minCount` / `maxCount` / `minReplicas` / `count` | structuralRule | per kind (§5.3) | per kind | Kind-specific fields. | `componentType` = a valid `ComponentType` string; `category` = a `ComponentCategory`. |
| `semanticCriteria[].id` | semanticCriterion | string | Required | Unique id. | Duplicate ids rejected. |
| `semanticCriteria[].description` | semanticCriterion | string | Optional | Row label + `detail`. | - |
| `semanticCriteria[].points` | semanticCriterion | number | Required | Points (full/partial→floor(½)/0). | - |
| `semanticCriteria[].hardFail` | semanticCriterion | boolean | Optional | Failing zeroes the question. | Use for architecturally-naive mistakes only. |
| `semanticCriteria[].kind` | semanticCriterion | `placement \| guardedPath \| fanout \| storageFit \| forbidUnjustified` | Required | Check kind. | - |
| `placement.componentType` | placement | `ComponentType` | Required | The placed component. | - |
| `placement.between` | placement | `[ComponentType, ComponentType]` | Optional | On a directed A→…→B path. | - |
| `placement.notBefore` | placement | `ComponentType` | Optional | Not upstream of X. | - |
| `placement.orderedPipeline` | placement | `ComponentType[]` | Optional | Types appear in order along a path. | - |
| `guardedPath.from` | guardedPath | `ComponentType` | Required | Path origin. | - |
| `guardedPath.guard` | guardedPath | `ComponentType` | Required | Mandatory guard node. | - |
| `guardedPath.to` | guardedPath | `ComponentType` | Optional | Path destination. | With a read/write mix, a `to` guardedPath can wrongly fail correct designs (writes bypass) ⇒ validator `guardedPath.readWriteMix`. |
| `fanout.broker` | fanout | `ComponentType` | Required | Fan-out broker. | - |
| `fanout.minConsumers` | fanout | number | Required | Distinct downstream consumers required. | - |
| `fanout.forbiddenBroker` | fanout | `ComponentType` | Optional | Wrong primitive (queue) feeding N ⇒ hard-fail case. | - |
| `storageFit.accessPattern` | storageFit | `point-lookup \| time-series \| append-only-ledger \| transactional-relational \| search-index \| blob` | Required | The access pattern. | See Appendix C. |
| `storageFit.accept` | storageFit | `ComponentType[]` | Required | Full-credit store types. | - |
| `storageFit.partial` | storageFit | `ComponentType[]` | Optional | Half-credit (defensible). | - |
| `storageFit.antiPattern` | storageFit | `ComponentType[]` | Optional | Anti-pattern types (hard-fail-worthy). | Present anti-pattern ⇒ fail (hard-fail if flagged). |
| `forbidUnjustified.componentType` | forbidUnjustified | `ComponentType` | Required | Component to guard. | - |
| `forbidUnjustified.justifyId` | forbidUnjustified | string | Optional | Bound justify prompt id. | Dangling ⇒ validator `justify.dangling`; missing ⇒ present component always fails. |
| `justify[].id` | justify | string | Required | Unique id. | - |
| `justify[].decision` | justify | string | Required | Decision to defend. | - |
| `justify[].boundTo` | justify | `{ nodeId?, componentType? }` | Optional | Graph binding. | - |
| `justify[].requires.choice` | justify | boolean | Required | Graph-consistency gate. | - |
| `justify[].requires.number` | justify | boolean | Optional | Must cite a scale number. | - |
| `justify[].requires.tradeoff` | justify | boolean | Required | Must state a tradeoff. | - |
| `justify[].acceptTradeoffTokens` | justify | string[] | Optional | Tradeoff keywords. | - |
| `budget.unit` | budget | `cost \| nodes \| edges` | Required | Budget dimension. | - |
| `budget.cap` | budget | number > 0 | Required | Ceiling. | - |
| `suite.name` | suite | string | Required | Suite name. | - |
| `suite.visibleToStudent` | suite | boolean | Required | Show scenarios to student. | `false` = hidden contest suite. |
| `suite.dryRunCase` | suite | `QuestionSuiteCase` | Optional | Case the student may dry-run. | - |
| `suite.cases[].id` | suite case | string | Required | Case id. | Empty `cases` ⇒ validator `suite.empty` (error). |
| `suite.cases[].description` | suite case | string | Optional | Case label. | - |
| `suite.cases[].global` | suite case | `Partial<GlobalConfig>` | Optional | Global override (seed/duration). | Question-owned - fixes seed to kill seed-farming. |
| `suite.cases[].workload` | suite case | `Partial<WorkloadProfile>` | Optional | Injected load (RPS + mix). | The read/write mix lives here (`requestDistribution`). |
| `suite.cases[].faults` | suite case | `FaultSpec[]` | Optional | Injected chaos faults. | Question-owned HA scenario. |
| `workload.baseRps` | workload | number > 0 | Required (in a workload) | Tractable RPS (~2-5K). | Not the display scale. |
| `workload.pattern` | workload | `constant \| poisson \| bursty \| diurnal \| spike \| sawtooth \| replay` | Required (in a full workload) | Arrival pattern. | - |
| `workload.requestDistribution[].type` | requestDistribution | string | Required | Traffic class (`read`/`write`/`GET`…). | Used in edge `condition`. |
| `workload.requestDistribution[].weight` | requestDistribution | number 0-1 | Required | Fraction of traffic. | Weights should sum to 1.0. |
| `workload.requestDistribution[].sizeBytes` | requestDistribution | number | Required (full topology) | Payload size. | Missing on a full topology ⇒ validation error. |
| `workload.requestDistribution[].metadata` | requestDistribution | object | Optional | Untyped escape hatch. | Not consumed by grading. |
| `global.seed` | global | string | Required (full) | RNG seed. | Question-fixed to prevent seed-farming. |
| `global.simulationDuration` | global | number > 0 (ms) | Required (full) | Sim length. | Keep short for the browser. |
| `global.warmupDuration` | global | number ≥ 0 (ms) | Required (full) | Pre-metrics warmup. | - |
| `global.timeResolution` | global | `microsecond \| millisecond` | Required (full) | Tick resolution. | - |
| `global.defaultTimeout` | global | number > 0 (ms) | Required (full) | Request timeout. | - |
| `global.traceSampleRate` | global | number 0-1 | Optional | Trace sampling. | - |
| `resources.instanceType` | node resources | `InstanceType` (catalog key, §9.2) | Optional | Hardware SKU; resolves vCPU/RAM/price/perf. Opts the node into the instance model. | Not free-typed - must be a catalog key. |
| `resources.instanceCount` | node resources | number ≥ 1 | Optional (=1) | Horizontal scale. | Supersedes `replicas`. |
| `resources.workloadKind` | node resources | `cpu-bound \| io-bound` | Optional (per-type default) | Execution profile → workers-per-vCPU (1 vs 32, §9.3). | This is why stores show 64-128 and services show 2. |
| `resources.maxInstances` | node resources | number | Optional | Per-node `instanceCount` quota. | Build-time validation. |
| `resources.perRequestMemMb` | node resources | number (MB) | Optional | Per-request memory → admission ceiling `K`. | Small value ⇒ RAM never binds (pure queueing). |
| `resources.pricingModel` | node resources | `on-demand \| reserved \| spot` | Optional (=on-demand) | Price multiplier 1.0 / 0.6 / 0.3. | Provisioned cost only; not the graded `$` axis (§9.5). |
| `resources.workersPerInstance` / `queueSlots` | node resources | number | Optional | **Derived, read-only** once instance model is set. | Do not tune to size a node - ignored by derivation. |
| `resources.cpu` / `memory` / `replicas` | node resources | number | Optional | **@deprecated** legacy free-typed fields. | Read for back-compat only. |
| `environmentProfile` | Newton `SIMULATOR_CONFIG` / launch payload | `EnvironmentProfileInput` (§10) | Optional | Mode + visibility + capabilities lens. | Not part of `question.json`; authored in the Newton row or launch payload. |
| `rubric.id` | rubric | string | Required | Rubric id. | - |
| `rubric.passThreshold` | rubric | number 0-1 | Optional (=1) | Fraction of points to pass. | - |
| `rubric.checks[].id` | rubric check | string | Required | Check id. | - |
| `rubric.checks[].description` | rubric check | string | Required | Row label. | - |
| `rubric.checks[].kind` | rubric check | `topology \| simulation \| invariant` | Optional | Inferred from metric prefix if omitted. | Mismatch (simulation check on `topology.*`) ⇒ validator `metric.kindMismatch`. |
| `rubric.checks[].metric` | rubric check | verdict path (§4.2) | Required | Metric to compare. | `summary.latencyP99Ms` ⇒ validator `metric.badLatencyKey`. |
| `rubric.checks[].op` | rubric check | `< \| <= \| > \| >= \| == \| !=` | Required | Comparison. | - |
| `rubric.checks[].value` | rubric check | number | Required | Threshold. | - |
| `rubric.checks[].points` | rubric check | number | Optional (=1) | Points. | - |

### Table 11. 8.3 Implementation status - graded vs schema-only

Source section: `Section 8 - Schema Validation & Engine Gotchas Index > 8.3 Implementation status - graded vs schema-only`

| Feature | Schema | Graded / behavioral? |
| --- | --- | --- |
| `structuralRules` (all kinds) | ✅ | ✅ graded |
| `rubric` (`simulation`/`topology`/`invariant`) | ✅ | ✅ graded |
| `semanticCriteria` (placement/guardedPath/fanout/storageFit/forbidUnjustified) | ✅ | ✅ graded (evaluators + hardFail) |
| `justify` (graph-consistent) | ✅ | ✅ graded; feeds `forbidUnjustified` in-app |
| **`budget`** | ✅ | ✅ **graded** (`budget.ts` - nodes/edges exact, cost = v1 heuristic) |
| `suite.cases[].workload` / `global` / `faults` | ✅ | ✅ injected at grade time |
| `resources.*` (instance model - `instanceType`/`instanceCount`/`workloadKind`/`perRequestMemMb`) | ✅ | ✅ **behavioral** - drives derived concurrency `c`/`K`, service speed, and cost on that node (§9) |
| `resources.pricingModel` | ✅ | ⚠️ affects the **live** cost chip / `cost.ts` only; graded `budget.unit:"cost"` still uses the v1 heuristic (§6.2) |
| `environmentProfile` (mode / visibility / `capabilities`) | ✅ (Newton row / launch) | ⚠️ **platform-facing** - governs edit locks, `edgeModel`, visibility; not a scored axis. Overlaid by `domains` (§10.4) |
| `edgeModel` (`network` / `connector`) | ✅ | ⚠️ behavioral - `connector` edges carry no sim physics or egress cost (§10.3) |
| `constraints.*` (`maxNodeCount`, `maxBudget`, `maxTotalWorkers`, `allowed/forbiddenNodeTypes`) | ✅ | ✅ **graded + behavioral** - palette filtering still applies, and grade time now enforces node caps, spend caps, worker caps, and allowed/forbidden component types |
| `workloadCategory` | ✅ | ❌ label only (author-side axis selector; not read by grading) |
| `domains` | ✅ | ⚠️ **advisory + platform-facing** - checked by the authoring validator and consumed by environment-profile / edit-policy logic, but not scored as a rubric axis by themselves |
| `concepts` | ✅ | ❌ metadata only (taxonomy / indexing aid; not graded) |
| `type` (`fix`/`build-budget`/`optimize`/`open-build`/`scaling`/`ha-chaos`/`tradeoff`) | ✅ | ❌ **all are labels** - none drives behavior. `optimize` does **not** grade against `scaffold.baselineVerdict`; `build-budget` does not auto-enforce `budget`; `ha-chaos` "works" only via `suite.faults`. |
| `entryFormat` (`blank-canvas`/`requirements-first`/`partial-scaffold`/`broken-scaffold`/`baseline-optimize`/`locked-lab`) | ✅ | ⚠️ **platform-facing** - explicit authoring/presentation metadata. Backward-compatible inference exists for legacy questions; `locked-lab` drives the Lab wrapper, `baseline-optimize` drives the comparison shell, and the other formats now feed the live workflow tracker / question shell selection. |
| `scaffold.baselineVerdict` | ✅ | ✅ graded for baseline-comparison questions - the primary case must improve at least one comparison metric without regressing the others |
| `requestDistribution[].metadata` | ✅ | ❌ not consumed |
| `readWriteRatio → requestDistribution` auto-derivation | - | ✅ built - when a case omits `requestDistribution`, grading derives a typed `read`/`write` mix from `prompt.scale.readWriteRatio` and the source workload's request sizes |

### Table 12. 9.1 The `resources` block

Source section: `Section 9 - Resource, Instance & Execution-Profile Model (node sizing DSL) > 9.1 The `resources` block`

| Field | Type / Enum | Meaning |
| --- | --- | --- |
| `instanceType` | `InstanceType` (catalog key, §9.2) | Hardware SKU → resolves `{ vcpu, ramGb, pricePerHour, perfFactor }`. Never free-typed. |
| `instanceCount` | number ≥ 1 | Horizontal scale (replaces legacy `replicas`). |
| `maxInstances` | number | Per-node quota; `instanceCount` may not exceed it (build-time validation error). |
| `workloadKind` | `cpu-bound \| io-bound` | The **execution profile** - decides workers-per-vCPU (§9.3). |
| `perRequestMemMb` | number (MB) | Memory footprint of one in-flight request; divides RAM into the admission ceiling `K`. |
| `pricingModel` | `on-demand \| reserved \| spot` | Purchasing model → price multiplier (§9.5). Absent = `on-demand`. |
| `workersPerInstance` / `queueSlots` | number | **Derived defaults, shown read-only.** Authored values are ignored by the derivation once `instanceType`/`instanceCount` are present - do not tune these to size a node. |
| `cpu` / `memory` / `replicas` | number | **@deprecated** legacy free-typed fields, read only for back-compat (`replicas`→`instanceCount` via `getInstanceCount`). |

### Table 13. 9.2 The instance catalog (frozen SKU menu)

Source section: `Section 9 - Resource, Instance & Execution-Profile Model (node sizing DSL) > 9.2 The instance catalog (frozen SKU menu)`

| `instanceType` | Family | vCPU | RAM (GB) | `$/hr` | `perfFactor` |
| --- | --- | --- | --- | --- | --- |
| `t3.small` | burstable | 2 | 2 | 0.021 | 0.8 |
| `t3.medium` | burstable | 2 | 4 | 0.042 | 0.8 |
| `m5.large` | general | 2 | 8 | 0.096 | 1.0 |
| `m5.xlarge` | general | 4 | 16 | 0.192 | 1.0 |
| `m5.2xlarge` | general | 8 | 32 | 0.384 | 1.0 |
| `c5.large` | compute-optimized | 2 | 4 | 0.085 | 1.3 |
| `c5.xlarge` | compute-optimized | 4 | 8 | 0.170 | 1.3 |
| `c5.2xlarge` | compute-optimized | 8 | 16 | 0.340 | 1.3 |
| `r5.large` | memory-optimized | 2 | 16 | 0.126 | 1.0 |
| `r5.xlarge` | memory-optimized | 4 | 32 | 0.252 | 1.0 |
| `r5.2xlarge` | memory-optimized | 8 | 64 | 0.504 | 1.0 |
| `x1e.xlarge` | memory-extreme | 4 | 122 | 0.834 | 1.0 |

### Table 14. 9.3 Derived concurrency - why a datastore shows 64-128 "workers" and a service shows 2

Source section: `Section 9 - Resource, Instance & Execution-Profile Model (node sizing DSL) > 9.3 Derived concurrency - why a datastore shows 64-128 "workers" and a service shows 2`

| Tier | Example types | Default `workloadKind` | Derived `c` (per vCPU) |
| --- | --- | --- | --- |
| Compute processors | `microservice`, `batch-worker` | **cpu-bound** | 1 |
| Everything else | `relational-db`, `nosql-db`, `kv-store`, `in-memory-cache`, `load-balancer`, `api-endpoint`, `queue`, `message-broker`, `object-storage`, … | **io-bound** | 32 |

### Table 15. 9.5 Cost model (what the graded `$` axis and the live chip use)

Source section: `Section 9 - Resource, Instance & Execution-Profile Model (node sizing DSL) > 9.5 Cost model (what the graded `$` axis and the live chip use)`

| `costModel` | Basis | Types |
| --- | --- | --- |
| `provisioned` | instance-hours (above) | most compute + stores |
| `consumption` | `pricePerMillionRequests × throughput` | `serverless-function` (per-request) |
| `volume` | `pricePerGb × egress` | `cdn`, `object-storage` (traffic-priced; estimated pre-run, measured post-run) |
| `none` | not billable | traffic sources (`api-endpoint` client) |

### Table 16. 10.1 Modes and the deployed default

Source section: `Section 10 - Environment Profiles & Capabilities (assignment vs practice vs author) > 10.1 Modes and the deployed default`

| Mode | `graded` | Edges | Resources editable | Use |
| --- | --- | --- | --- | --- |
| `AUTHOR` | true | `network` | yes | Full authoring / dev UI |
| `ASSIGNMENT` | true | `connector` | no | Graded student attempt (locked scaffold) |
| `PRACTICE` | false | `connector` | yes | Free self-paced sandbox |

### Table 17. 10.2 Capabilities (`environmentProfile.capabilities`)

Source section: `Section 10 - Environment Profiles & Capabilities (assignment vs practice vs author) > 10.2 Capabilities (`environmentProfile.capabilities`)`

| Field | Type | Meaning |
| --- | --- | --- |
| `editPaletteList` | `string[] \| null` | Allowed palette types (`null` = all, `[]` = none). |
| `canEditScaffoldNodes` | boolean | Whether scaffold nodes can be edited. |
| `canTriggerTestRuns` | boolean | Whether the student may dry-run before submit. |
| `edgeModel` | `network \| connector` | Whether edges are a modelled layer or dumb wires (§10.3). |
| `canEditEdges` | boolean | Edit edge *properties* - only meaningful in `network` mode. |
| `canEditResources` | boolean | Change a node's instance type / count / execution profile. |
| `canEditExecutionProfile` | boolean | Change a node's `workloadKind` (cpu/io) specifically. |
| `maxTestRuns` | number? | Cap on dry runs (absent = unlimited). |
| `resourceBudget` | `{ totalVcpu, totalRamGb }`? | Hardware quota wall (absent = unbounded). |
| `costBudget` | `{ maxPerHour }`? | Money wall, independent of quota (absent = unbounded). |

### Table 18. 11.2 Django question fields

Source section: `Section 11 - Writing Test Cases: the Newton Django-Admin Authoring Format > 11.2 Django question fields`

| Django field | Value |
| --- | --- |
| `question_type` | `GAME` |
| `question_title` | the question title (e.g. `Design a URL shortener`) |
| `question_text` | **raw HTML** (see skeleton below) - rendered as-is |
| `initial_game_state` | `{}` (mutable-only learner state; never the full package) |

### Table 19. 11.3 Test-case row conventions (the Django columns)

Source section: `Section 11 - Writing Test Cases: the Newton Django-Admin Authoring Format > 11.3 Test-case row conventions (the Django columns)`

| Django column | Value |
| --- | --- |
| `title` | `"<ROW_TYPE>: <id>"` - e.g. `SIMULATOR_CONFIG: url-shortener`, `STRUCTURAL_RULE: single-source`, `RUBRIC_CHECK: p99` |
| `input` | the JSON block for that row, pasted **verbatim** |
| `hidden` | `false` |
| `output` | `""` (empty) |
| `output_file` | empty |

### Table 20. 11.4 Row 1 - `SIMULATOR_CONFIG` (the master row)

Source section: `Section 11 - Writing Test Cases: the Newton Django-Admin Authoring Format > 11.4 Row 1 - `SIMULATOR_CONFIG` (the master row)`

| Key | Value / notes |
| --- | --- |
| `type` | `"SIMULATOR_CONFIG"` |
| `configVersion` | `"1.0"` (row schema version) |
| `questionId` / `questionVersion` | question identity |
| `questionType` | the archetype (`open-build`, …) - mirrors `type` in `question.json` |
| `entryFormat` | Optional learner-entry shell (`requirements-first`, `partial-scaffold`, `locked-lab`, …) - mirrors `entryFormat` in `question.json` |
| `domains` / `concepts` | as in `question.json` §7 - **`domains` drive edit policy** (§10.4) |
| `difficulty` / `workloadCategory` | as in `question.json` |
| `presentationMode` | `"raw-html"` (renders `question_text` as HTML) |
| `promptSource` | `"question_text"` (prompt comes from the Django field, not a `prompt.text`) |
| `scaffold` | `{ "type": "empty" }` or a `partial`/`complete` topology |
| `constraints` | `canModifyScaffold` / `canRemoveScaffoldNodes` / `maxNodeCount` |
| `suite` | the injected workload (`name`, `visibleToStudent`, `cases[]`) - §2 |
| `rubric` | **header only** here: `{ id, passThreshold }`. The checks are their own rows. |
| `environmentProfile` | the mode + visibility + capabilities lens - §10 |

### Table 21. 11.5 Rows 2…N - one row per rule / criterion / check

Source section: `Section 11 - Writing Test Cases: the Newton Django-Admin Authoring Format > 11.5 Rows 2…N - one row per rule / criterion / check`

| Row `type` | Body = one element of | Kinds |
| --- | --- | --- |
| `STRUCTURAL_RULE` | `structuralRules[]` (§5.3) | `requires_component`, `requires_single_source`, … |
| `SEMANTIC_CRITERION` | `semanticCriteria[]` (§5) | `placement` / `guardedPath` / `fanout` / `storageFit` / `forbidUnjustified` |
| `RUBRIC_CHECK` | `rubric.checks[]` (§4.2) | `simulation` / `topology` / `invariant` |

### Table 22. Appendix A - The Functional-Requirement Taxonomy (all FR classes)

Source section: `Appendix A - The Functional-Requirement Taxonomy (all FR classes)`

| FR class | Example verbs / phrasings | Obligation | Gradeable? |
| --- | --- | --- | --- |
| **Create / write a record** | "create a short code", "post an item", "place an order", "ingest a reading" | `requires_path`(source→store); `storageFit` | T/S |
| **Read / look up** | "redirect a code", "load a feed", "get order status", "range-query recent" | `requires_path`(source→store); cache via Σ p99 | T/Σ |
| **Match / assign** | "match rider→driver", "assign a worker" | `requires_path` + `placement` (hot path off the txn DB) | T |
| **Track / stream** | "track live location", "stream updates" | `requires_component`(stream/websockets-gateway) | T |
| **Pay / transact (consistent)** | "process payment", "strongly-consistent" | `storageFit`(transactional-relational) + `guardedPath`(→lock/idempotency) + `justify` | S/T/J |
| **Search** | "search events/products" | `requires_component`(search-index); `storageFit`(search-index) | T/S |
| **Enqueue / decouple (async)** | "accept jobs quickly", "process within SLA" | `requires_component`(queue)+`requires_component`(worker); `guardedPath`(→queue→worker); Σ SLA | T/Σ |
| **Fan-out / broadcast** | "each of N consumers receives every event" | `fanout`(broker, N, forbiddenBroker=queue) | T |
| **Dedup / idempotency** | "enqueue only new URLs", "exactly-once" | `guardedPath`(→dedup index / idempotency store) + `justify` | T/J |
| **Rate-limit / throttle** | "limit requests", "shared counters" | `requires_component`(rate-limiter)+`requires_edge`(rl→shared cache)+`guardedPath` + `justify` | T/J |
| **Serialize / lock (contention)** | "no double-booking", "hold a seat once" | `guardedPath`(→distributed-lock) + `justify` (TTL/OCC) | T/J |
| **Aggregate / batch (throughput)** | "crawl billions", "aggregate 23K/s" | `placement` orderedPipeline + Σ throughput | T/Σ |
| **Audit / immutability** | "auditable trail", "append-only" | `storageFit`(append-only-ledger); `forbids_component`(mutable store on that path) + `justify` | S/T/J |
| **Omit / avoid waste** | "don't add a wasteful CDN" | `forbidUnjustified` + `justify` | T/J |
| **Cache / accelerate reads** | "keep redirects fast" | Σ p99 under injected read-heavy load (NOT guardedPath) | Σ |
| **Generate an id / encode** | "generate a unique code", "base62" | **narrative** - structural proxy (a store) + `justify` context | J only |
| **Return a protocol response** | "return 301/302", "HTTP status" | **narrative** - `justify` context; not modeled | J only |

### Table 23. Appendix C - Access-Pattern Catalog (`storageFit.accessPattern`)

Source section: `Appendix C - Access-Pattern Catalog (`storageFit.accessPattern`)`

| `accessPattern` | Meaning | `accept` (full credit) | `partial` | `antiPattern` (hard-fail-worthy) |
| --- | --- | --- | --- | --- |
| `point-lookup` | get-by-key (URL→long) | `kv-store`, `nosql-db` | `in-memory-cache` | `relational-db` (at scale) |
| `time-series` | append + range-by-time (sensors) | `time-series-db`, `columnar-db`, `nosql-db` | - | `relational-db` |
| `append-only-ledger` | immutable double-entry (payments) | `event-sourcing-store` | - | `in-memory-cache`, mutable stores |
| `transactional-relational` | ACID, joins, money (bookings) | `relational-db` | - | `in-memory-cache`, `kv-store` |
| `search-index` | full-text / faceted (events, products) | `search-index` | `nosql-db` | `relational-db` (for full-text) |
| `blob` | large immutable objects (media, crawl content) | `object-storage`, `block-storage` | `distributed-file-system` | `relational-db`, `kv-store` |

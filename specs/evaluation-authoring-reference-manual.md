# Evaluation Authoring — Reference Manual & DSL Guidebook (Domain-Specific Language)

> **Scope.** The complete, authoritative reference for authoring **system-design
> evaluation questions** (`QuestionPackage`) for the ns-simulator: every
> configurable property, schema constraint, structural rule, semantic check,
> simulation metric, justification field, budget, and validation requirement
> needed to author **discriminatory** questions.
>
> **Source of truth.** `src/engine/analysis/{question,gradingCriteria,rubric,structural,semanticCriteria,justification,authoringValidator}.ts`.
> Validated by `parseQuestionPackage` (schema) + `validateAuthoredQuestion`
> (authoring contract). Companion specs: `question-simulation-alignment.md`,
> `question-grading-model-and-anti-gaming.md`, `question-bank-initial-game-states.md`.

---

## Section 1 — Philosophy & The Authoring Recipe

### 1.1 Discriminatory authoring
A question is only "authored" (vs merely "written") when it **discriminates**: a
*good* design passes and a *gamed* design fails **on the intended axis**. Gaming
is any way to pass without the target competence — over-provisioning a single
node, tuning a metric, using the wrong-but-tolerated store, memorizing prose.
Discrimination comes from grading **≥3 orthogonal axes**:

| Axis | Symbol | Graded by | Measures |
|------|--------|-----------|----------|
| Topology | **T** | `structuralRules`, `placement`, `guardedPath`, `fanout` | shape of the graph |
| Scale-fit semantics | **S** | `storageFit`, scale-aware checks | right component for the workload |
| Simulation | **Σ** | `rubric` checks over verdict metrics | performance under injected load |
| Justification | **J** | `justify` prompts (graph-consistent) | reasoning, tradeoffs |
| Budget | **$** | `budget` | cost / anti-kitchen-sink |

Gaming one axis is caught by another. Correctness properties the sim cannot
measure (exactly-once, no-double-book) are carried by **T + J**.

### 1.2 The Dual-Topology Rule (mandatory validation loop)
Every question MUST be validated by grading **two** topologies through
`sim evaluate question`:

1. **Reference topology** — a correct solution → expect **PASS** (full score).
2. **Gamed topology** — a deliberately-wrong solution → expect **FAIL** on the
   *intended* check (read the failing `detail`).

```bash
sim evaluate question <package.json> <reference-topology.json>   # exit 0, full score
sim evaluate question <package.json> <gamed-topology.json>       # non-zero, fails intended axis
```

If the gamed design passes, the question is **under-constrained** — tighten the
`semanticCriteria`/`rubric`. A question that has not been graded both ways is not
authored. (Every kind in this manual was validated this way — see
`question-bank-initial-game-states.md` §Validation status.)

### 1.3 Workload characterization
`workloadCategory` selects which axis dominates and what load is injected. It is
an **author-side selector**, optionally surfaced to the student as a hint — **not**
the teaching mechanism (the student should infer the character from the FRs +
scale numbers and be forced into the right design by the simulation).

| `workloadCategory` | Injected load | Dominant axis | Canonical hard problem |
|--------------------|---------------|---------------|------------------------|
| `read-heavy` | high read `requestDistribution` (e.g. 99% read) | Σ + S | caching is mandatory (store saturates without it) |
| `write-heavy` | high write mix | S + Σ | storage-fit for write throughput (right DB) |
| `connection-heavy` | fan-out / shared-state traffic | T | broker fan-out, shared counters |
| `correctness-heavy` | modest load | **T + J** (NOT Σ) | exactly-once, no-double-book, ordering |
| `batch-heavy` | sustained throughput, latency-insensitive | Σ (throughput) + T (pipeline) | ordered pipeline, dedup, aggregate throughput |

> **"Equal"** read/write is authored as a `requestDistribution` with `read`/`write`
> weights ~0.5/0.5 and no single dominant axis; the grade then rests on structure +
> justification. There is no `equal` enum value — express it via the distribution.
>
> **CPU-bound / resource-allocation questions.** There is also **no**
> `workloadCategory: "compute"` enum in the shipped schema. Author those as an
> existing workload character (`batch-heavy` is the usual fit for sustained
> throughput work), then declare the lesson explicitly in `domains`
> (for example `["compute"]` or `["compute", "cost"]`).

---

## Section 2 — Workload & Scale Configuration

### 2.1 Where workload is authored (and where it is NOT)
- **Graded workload = question JSON** (`suite.cases[].workload`), injected over the
  student's topology at grade time via `mergeTopologyWithOverrides`. Question-owned
  (anti-gaming): the student cannot lower the load, reseed, or change the mix.
- **The request mix is JSON-only.** Neither the canvas scenario editor
  (`ScenarioState.workloadOverride`) nor a source node's `defaultWorkload` can carry
  a `requestDistribution` — both are typed `Omit<WorkloadProfile, 'sourceNodeId' | 'requestDistribution'>`.
  So read/write character is set **exclusively** in the question package.
- The student's on-canvas scenario (RPS/pattern/source/faults) affects only their
  own dry-runs and is **overridden** by the injected suite at grade time.

### 2.2 Tractable vs display scale
| Field | Purpose | Value guidance |
|-------|---------|----------------|
| `prompt.scale.peakRps` | **display** — the real-world target shown in the brief | the real number (e.g. `200000`) |
| `prompt.scale.readWriteRatio` | **display** — shown as `99:1`; also the source the sim mix *should* mirror | the real ratio |
| `suite.cases[].workload.baseRps` | **tractable simulation load** the browser can actually run | **~2,000–5,000** rps |

The browser cannot run 200K rps × 30s (6M events). Author a **representative**
`baseRps` that still stresses the design, and size nodes + thresholds together.
`prompt.scale` numbers are display/derivation inputs; they do not run.

### 2.3 Traffic distributions (`requestDistribution`)
An array of typed traffic classes on the injected workload. Types are matched by
routing conditions (`request.type === "read"`) and GET/POST is inferred from the
type token.

```json
"workload": {
  "baseRps": 2000,
  "requestDistribution": [
    { "type": "read",  "weight": 0.99, "sizeBytes": 256 },
    { "type": "write", "weight": 0.01, "sizeBytes": 512 }
  ]
}
```

| Field | Required | Rule |
|-------|----------|------|
| `type` | ✅ | free string; used in edge `condition` (`request.type === "read"`) and GET/POST inference |
| `weight` | ✅ | fraction 0–1; weights across the array should sum to 1.0 |
| `sizeBytes` | ✅ (full topology) | payload bytes — drives bandwidth/serialization; **a full topology's entries require it** (the suite override tolerates its absence but a merged topology does not) |
| `metadata` | optional | untyped `Record<string, unknown>` escape hatch (not consumed by grading today) |

> **Why declare payload sizes.** `sizeBytes` feeds edge bandwidth and transfer
> time; omitting it on a full topology fails validation
> (`workload.requestDistribution.N.sizeBytes: expected number, received undefined`).

**The read/write mix only *matters* when BOTH** (a) it is injected as typed
traffic **and** (b) the topology routes on type (`condition: request.type === "read"`).
A distribution with no type-conditional routing leaves reads and writes on the
same path, so the ratio has no effect (alignment §9).

### 2.4 Current topology-default semantics that affect authored questions
The question DSL owns the **suite workload**, but authored reference / gamed
topologies still inherit important simulator defaults. These are the ones that
matter today:

| Surface | Current behavior | Authoring consequence |
|---------|------------------|-----------------------|
| `suite.cases[].workload.pattern` | If you author a full workload, `pattern` must be explicit. The product's interactive defaults now favor **`constant`** traffic for predictability. | For deterministic graded cases, prefer `constant` unless arrival jitter is part of the lesson. Use `poisson` only intentionally. |
| Edge latency when no explicit edge latency is authored | The renderer/serializer now resolves a bare edge to a **path-type-derived constant median latency (no jitter)**. Log-normal latency only appears when the edge explicitly chooses the log-normal model or supplies `mu` / `sigma`. | If the question depends on latency variance or burst bunching, author explicit log-normal edge latency in the topology. Do not assume omitted latency means jitter. |
| Node capacity when `resources.instanceType` / `instanceCount` are present | The engine now treats the **instance model** as authoritative for effective concurrency on that node. Legacy nodes with no instance-model resources still run off raw `queue.workers` / `queue.capacity`. | For saturation / scaling questions, treat `resources` as part of the real topology DSL. Once you opt into instance-model resources, raw queue numbers are no longer the whole story. |
| Cost in the live product vs cost in question grading | The app now has a richer instance-aware live cost model and resource displays, but **`budget.unit:"cost"` in question grading still uses the older v1 heuristic** from `budget.ts`. | Do not assume the UI cost chip and the graded `$` axis are numerically identical. Use `budget.nodes` / `budget.edges` for hard anti-kitchen-sink caps; treat `budget.cost` as a heuristic grading axis until the grading DSL is upgraded. |

For authored question packages, the safest practice is:
- always set `suite.cases[].workload.pattern` explicitly,
- author edge latency explicitly whenever edge jitter is part of the discriminator,
- and be deliberate about whether a reference topology is **legacy queue-authored**
  or **instance-model-authored**.

---

## Section 3 — Functional Requirements (FR) Engine

FRs are **prose in `prompt.functionalRequirements`**; the engine does not parse
them. Each FR must be backed by a structural/semantic **obligation** or explicitly
labeled context — no orphan FRs.

### 3.1 Mapping FRs to DSL obligations
| FR intent | DSL obligation | Example |
|-----------|----------------|---------|
| "A component must exist" | `requires_component` | a load balancer fronts the system |
| "Traffic must reach X" | `requires_path` (directed) | payment path reaches the SQL store |
| "All traffic of a type must pass a guard" | `guardedPath` | rate-limit checks traverse the shared cache |
| "Component sits in the right position / order" | `placement` (`between`/`notBefore`/`orderedPipeline`) | cache between service & DB, not before the LB |

```json
"structuralRules": [
  { "id": "pay-path", "kind": "requires_path", "fromType": "microservice", "toType": "relational-db",
    "description": "A payment path reaches the transactional store" }
]
```

### 3.2 Handling application-logic FRs (the "generate a unique code" problem)
The sim models **flow and capacity**, not application logic. FRs like *"generate a
unique short code"*, *"return 301"*, *"encode base62"* are **not gradeable in the
simulation**. Convert them to:
1. a **structural proxy** — the component that *would* do it must exist (a store
   for the code→URL mapping), and
2. a **`justify` prompt** carrying the nuance as context, and
3. a **context label** in the prompt text so the student knows it is narrative.

```json
"functionalRequirements": [
  "Create a short code for a long URL (write path to a store)",
  "Redirect a short code to its long URL (read path; a permanent redirect — see Justify)"
],
"justify": [
  { "id": "redirect-semantics",
    "decision": "Which HTTP status for a permanent redirect, and how is the code generated (e.g. base62)?",
    "requires": { "choice": true, "tradeoff": true } }
]
```

> See **Appendix A** for the full FR taxonomy and **Appendix B** for the
> per-archetype solution-nuance catalog (301/302, base62, idempotency keys, TTL
> locks, OCC, bloom filters, consistent hashing, …), each classified as
> *gradeable / justification-only / narrative*.

---

## Section 4 — Non-Functional Requirements (NFR) & Simulation Rules

### 4.1 Performance NFRs vs correctness NFRs — the hard boundary
| NFR flavour | Simulatable? | Graded by |
|-------------|--------------|-----------|
| **Performance** — latency, throughput, availability, utilization | ✅ | `rubric` `simulation` check |
| **Correctness** — consistency, exactly-once, ordering, immutability, no-double-book | ❌ | `storageFit` / `guardedPath` + `justify` — **NEVER** a `simulation` check |

The engine has no notion of contention, dedup, or transactional correctness. A
`simulation` check on a correctness property never resolves and silently mis-grades.

`prompt.nonFunctionalRequirements` entries are structured (`NFRTarget`) and each
should map to a rubric/semantic check (orphan NFRs are flagged by the validator):

```json
"nonFunctionalRequirements": [
  { "metric": "latency_p99", "operator": "<", "value": 100, "unit": "ms", "description": "p99 redirect latency under 100ms" }
]
```
`metric` ∈ `latency_p99 | latency_p50 | availability | error_rate | throughput`;
`operator` ∈ `< | <= | > | >=`; `unit` ∈ `ms | percent | req_per_sec | nines`.
(These are the *NFR display* enums; the `rubric` check uses the *verdict metric
keys* below.)

### 4.2 Simulation metric keys (verdict paths)
A `rubric` check's `kind` is inferred from the metric prefix
(`topology.*` → topology; `invariantViolations.*`/`conservation.*`/`littlesLaw.*`
→ invariant; else → simulation). Valid keys:

**Simulation (verdict summary):**
`summary.latency.p50` · `summary.latency.p90` · `summary.latency.p95` ·
`summary.latency.p99` · `summary.latency.min` · `summary.latency.max` ·
`summary.latency.mean` · `summary.errorRate` · `summary.throughput` ·
`summary.totalRequests` · `summary.successfulRequests` · `summary.failedRequests` ·
`perNode.maxUtilization` · `perNode.maxErrorRate` · `perNode.maxLatencyP99`

**Invariant:** `invariantViolations.count` · `sloBreaches.count` ·
`conservation.unbalanced` · `littlesLaw.violations`

**Topology (no simulation needed):** `topology.nodeCount` · `topology.edgeCount` ·
`topology.sourceCount` · `topology.totalWorkers` · `topology.totalReplicas` ·
`topology.componentCounts.<type>` · `topology.categoryCounts.<category>`

> **Anti-example — `summary.latencyP99Ms` is INVALID.** It does not resolve
> (`getByPath(verdict, 'summary.latencyP99Ms')` → undefined → the check silently
> fails at grade time). The correct key is **`summary.latency.p99`**. The authoring
> validator raises `metric.badLatencyKey` for this exact mistake.

```json
"rubric": {
  "id": "url-rubric", "passThreshold": 1,
  "checks": [
    { "id": "p99", "kind": "simulation", "description": "p99 under 100ms", "metric": "summary.latency.p99", "op": "<", "value": 100, "points": 3 },
    { "id": "no-invariants", "kind": "invariant", "description": "No invariant violations", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
  ]
}
```
`op` ∈ `< | <= | > | >= | == | !=`. `passThreshold` = fraction (0–1) of points
required for the rubric to pass (default 1 = every point).

### 4.3 Topology vs simulation obligations (the caching nuance)
Enforce "reads must be cached" with the **p99 simulation check**, NOT
`guardedPath(service→store)`. Under a read/write mix, writes legitimately bypass
the cache and hit the store directly; a topology `guardedPath` cannot distinguish
request types and would wrongly fail a correct design. The simulation is the
enforcement: without a cache the store saturates and p99 fails (proven, alignment
§9). Reserve `guardedPath` for **all-traffic guards** (rate-limiter→shared-cache,
payment→idempotency-store) where there is no legitimate bypass.

---

## Section 5 — Anti-Patterns, Hard Fails & Structural Checks

### 5.1 Hard-fail semantic checks
`"hardFail": true` on a semantic criterion **zeroes the whole question** when that
criterion fails, regardless of other credit — for *architecturally naive* mistakes
(not merely suboptimal ones):

```json
{ "id": "store-fit", "kind": "storageFit", "accessPattern": "time-series",
  "accept": ["time-series-db", "columnar-db"], "antiPattern": ["relational-db"],
  "points": 6, "hardFail": true }
```
Canonical hard-fails: `storageFit` anti-pattern present (SQL at 200K time-series
writes); `fanout` via a `forbiddenBroker` queue (queue→N ≠ fan-out); `guardedPath`
bypass (write reaches the ledger without idempotency). A failed `hardFail` sets the
grade's `hardFailed` flag and drops the host contract's `allPassed`.

### 5.2 Short-circuit mechanics (evaluation order)
Grading runs in a strict order and **short-circuits**:

```
structuralRules  →  (if any fail, STOP: simulation + semantic skipped)
        ↓ pass
justification  →  semantic (forbidUnjustified reads justification results)  →  simulation (suite) + rubric
```

- A failing `structuralRule` **prevents** semantic/simulation from running — the
  design fails at the structural gate. If you want a *specific* semantic check to
  be the failure point, ensure the gamed design **passes structural first**
  (e.g. include the required broker but fan out with a queue, so `fanout` — not a
  `requires_component` — is the failing check).
- `structuralRules` carry **no points** in the host contract; they are pass/fail
  gates. Points live on `rubric` checks and `semanticCriteria`.

### 5.3 Structural rule kinds (full)
Base fields on every rule: `id`, `description`, `kind`.

| `kind` | Extra fields | Passes when |
|--------|--------------|-------------|
| `requires_component` | `componentType`, `minCount?`(=1) | ≥ minCount nodes of the type |
| `requires_category` | `category`, `minCount?`(=1) | ≥ minCount nodes in the category |
| `requires_edge` | `fromType`, `toType`, `mode?` | an edge `fromType`→`toType` (of `mode`) exists |
| `requires_path` | `fromType`, `toType` | a directed path exists (BFS) |
| `requires_redundancy` | `componentType`, `minReplicas` | total replicas of the type ≥ minReplicas |
| `max_component_count` | `componentType`, `maxCount` | ≤ maxCount of the type |
| `min_node_count` / `max_node_count` | `count` | total nodes ≥ / ≤ count |
| `forbids_component` | `componentType` | zero of the type present |
| `requires_connected_graph` | — | every node reachable (undirected BFS) |
| `requires_single_source` | — | exactly one source node (no inbound edge) |

---

## Section 6 — Justifications, Tradeoffs & Cost Constraints

### 6.1 Justification schema (`justify`)
```json
"justify": [
  { "id": "why-store",
    "decision": "Why this store type for lookups at this scale?",
    "boundTo": { "componentType": "kv-store" },
    "requires": { "choice": true, "number": true, "tradeoff": true },
    "acceptTradeoffTokens": ["but", "however", "at the cost", "we lose"] }
]
```
| Field | Required | Rule |
|-------|----------|------|
| `id` | ✅ | unique; referenced by `forbidUnjustified.justifyId` |
| `decision` | ✅ | the decision the student must defend |
| `boundTo` | optional | `{ nodeId?, componentType? }` — ties the answer to a real graph element |
| `requires.choice` | ✅ | graph-consistency gate: answer must name the component **actually placed** (anti-stuffing) |
| `requires.number` | optional | answer must cite a **scale/NFR number** this question defines |
| `requires.tradeoff` | ✅ | answer must state what is given up |
| `acceptTradeoffTokens` | optional | author-provided tradeoff keywords (else a default list) |

Grading is **deterministic, no LLM**: (1) graph-consistency (mentions the placed
component's alias), (2) number-citation (within 0.5%), (3) tradeoff token. Outcome
∈ `passed | partial | failed | missing`.

### 6.2 Budget (`budget`) — anti-kitchen-sink  *(graded — `budget.ts`)*
```json
"budget": { "unit": "cost", "cap": 600 }
```
`unit` ∈ `cost | nodes | edges`; `cap` = positive number. Evaluated by
`evaluateBudget(topology, budget)` after the structural gate; the result surfaces
as a **`topology.budget`** check row that **fails the contract when
`actual > cap`** (drops `allPassed`), so an over-provisioned "kitchen-sink" design
fails the **$** axis rather than being explicitly forbidden.

- **`nodes` / `edges`** — `actual` = node / edge **count**. The primary
  anti-kitchen-sink lever; exact and price-model-free.
- **`cost`** — `actual` = a **v1 capacity-cost heuristic** (no real price sheet
  yet): per node `1 + replicas + ceil(workers / 50)`, plus `1` per edge. This
  penalizes over-provisioned capacity (high replicas/workers). Swap in a real cost
  model later without changing the DSL — the heuristic is clearly labeled in the
  failure `detail` (`"… (v1 capacity-cost heuristic)"`).

The row shows as **pending** before grading and passes/fails after. Note
`constraints.maxBudget`/`maxNodeCount` are **not** enforced at grade time (see §8.3);
`budget` is the graded axis.

### 6.3 CLI vs in-app behavior (`forbidUnjustified`)
`forbidUnjustified` requires a component to be **absent, OR present and defended by
a valid justification** (`justificationPassed(justifyId) === true`).

- **CLI (`sim evaluate question`)** captures **no** justification answers → a
  present component is **always undefended → fails** (`"justification was not
  evaluated"`). Test the *absent* case for a clean CLI pass.
- **In-app** threads the student's answers into `gradeAttempt` → a **defended**
  present component **passes**. This is the graph-consistent justification linchpin.

```json
"semanticCriteria": [
  { "id": "cdn-justified", "kind": "forbidUnjustified", "componentType": "cdn",
    "justifyId": "why-cdn", "points": 4 }
]
```
`justifyId` MUST reference an existing `justify[].id` (dangling ⇒ validator error
`justify.dangling`).

---

## Section 7 — Master Property & DSL Reference Table

Every customizable property across the DSL. **Scope** names the containing object.

| Property Name / Key | Scope / Context | Data Type / Enum Values | Required / Optional | Description & Usage Rules | Gotchas & Validation Errors |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `version` | QuestionPackage | `"1.0"` (literal) | Required | Package schema version. | Must equal `"1.0"`. |
| `id` | QuestionPackage | string | Required | Stable question id. | — |
| `title` | QuestionPackage | string | Required | Human title. | — |
| `description` | QuestionPackage | string | Optional | Long description. | — |
| `difficulty` | QuestionPackage | `beginner \| intermediate \| advanced \| expert` | Required | Difficulty tier. | — |
| `tags` | QuestionPackage | string[] | Optional | Free tags. | — |
| `estimatedTimeMinutes` | QuestionPackage | number | Optional | Est. solve time. | — |
| `type` | QuestionPackage | `fix \| build-budget \| optimize \| open-build \| scaling \| ha-chaos \| tradeoff` | Required | Question archetype. | — |
| `workloadCategory` | QuestionPackage | `read-heavy \| write-heavy \| connection-heavy \| correctness-heavy \| batch-heavy` | Optional | Primary evaluation axis selector. | No `compute`/`equal` enum — `batch-worker` node is category `compute`; "equal" = a 0.5/0.5 `requestDistribution`. |
| `domains` | QuestionPackage | `QuestionDomain[]` (`compute \| storage \| network \| resilience \| correctness \| cost`) | Optional but strongly recommended | Declares the bottleneck domain(s) the question is teaching. Drives authoring-validator consistency checks and platform behavior such as edge/resource edit policy. | Missing ⇒ validator `domains.missing`; `network` / `resilience` / `cost` currently warn as V2 domains. |
| `concepts` | QuestionPackage | `string[]` (non-empty kebab-case slugs by convention) | Optional | Fine-grained lesson tags, narrower than `domains` (for example `read-cache`, `store-fit`, `async-decoupling`). | Free-form metadata today; schema enforces only non-empty strings. |
| `author` | QuestionPackage | string | Optional | Author id. | — |
| `createdAt` | QuestionPackage | ISO string | Optional | Timestamp. | — |
| `prompt.text` | prompt | string (markdown) | Required | Problem statement. | Frame as "design the architecture, not code". |
| `prompt.functionalRequirements` | prompt | string[] | Required | FRs (prose). | Not parsed — each must map to an obligation (§3) or be labeled context. |
| `prompt.nonFunctionalRequirements` | prompt | `NFRTarget[]` | Required | Structured NFRs. | Orphan NFR (no matching rubric check) ⇒ validator `nfr.orphan`. |
| `prompt.scale` | prompt | `ScaleParameters` | Required | Display + derivation numbers. | Display-only unless injected into `suite.workload`. |
| `prompt.additionalContext` | prompt | string | Optional | Extra context. | — |
| `NFRTarget.metric` | NFR | `latency_p99 \| latency_p50 \| availability \| error_rate \| throughput` | Required | NFR metric. | Distinct from verdict metric keys. |
| `NFRTarget.operator` | NFR | `< \| <= \| > \| >=` | Required | Comparison. | — |
| `NFRTarget.value` | NFR | number | Required | Target value. | — |
| `NFRTarget.unit` | NFR | `ms \| percent \| req_per_sec \| nines` | Required | Unit. | — |
| `NFRTarget.description` | NFR | string | Required | Student-facing label. | — |
| `scale.dau` | scale | number ≥ 0 | Optional | Daily active users (display). | — |
| `scale.peakRps` | scale | number ≥ 0 | Optional | Real-world peak (display). | Do NOT put in `baseRps`. Validator warns `scale.rpsNotInjected` if no case sets `baseRps`. |
| `scale.readWriteRatio` | scale | number 0–100 | Optional | Reads % (display + derivation). | Display-only unless injected as typed `requestDistribution` ⇒ validator `scale.mixNotInjected`. |
| `scale.storageGb` | scale | number ≥ 0 | Optional | Storage size (display). | — |
| `scale.retentionDays` | scale | number ≥ 0 | Optional | Retention (display). | — |
| `scale.growthRatePercent` | scale | number ≥ 0 | Optional | Growth (display). | — |
| `scaffold.type` | scaffold | `empty \| partial \| complete` | Required | Starting canvas. | `partial`/`complete` require a `topology`. |
| `scaffold.topology` | scaffold | `TopologyJSON` | Conditional | Given nodes/edges. | Required unless `type: "empty"`. |
| `scaffold.lockedNodeIds` | scaffold | string[] | Optional | Immutable nodes. | — |
| `scaffold.lockedEdgeIds` | scaffold | string[] | Optional | Immutable edges. | — |
| `scaffold.baselineVerdict` | scaffold | `SimulationVerdict` | Optional | Baseline to beat (`optimize`). | Must be a versioned verdict. |
| `constraints.canModifyScaffold` | constraints | boolean | Required | May edit scaffold nodes. | — |
| `constraints.canRemoveScaffoldNodes` | constraints | boolean | Required | May delete scaffold nodes. | — |
| `constraints.allowedNodeTypes` | constraints | string[] | Optional | Palette allowlist. | — |
| `constraints.forbiddenNodeTypes` | constraints | string[] | Optional | Palette denylist. | — |
| `constraints.maxNodeCount` | constraints | number | Optional | Hard node ceiling. | — |
| `constraints.maxBudget` | constraints | number | Optional | Hard cost ceiling. | Distinct from graded `budget`. |
| `constraints.maxTotalWorkers` | constraints | number | Optional | Hard worker ceiling. | — |
| `structuralRules[].id` | structuralRule | string | Required | Unique id. | Duplicate ids rejected. |
| `structuralRules[].description` | structuralRule | string | Required | Row label + failure text prefix. | Never parsed; only echoed. |
| `structuralRules[].kind` | structuralRule | see §5.3 | Required | Rule kind. | — |
| `…componentType` / `category` / `fromType` / `toType` / `mode` / `minCount` / `maxCount` / `minReplicas` / `count` | structuralRule | per kind (§5.3) | per kind | Kind-specific fields. | `componentType` = a valid `ComponentType` string; `category` = a `ComponentCategory`. |
| `semanticCriteria[].id` | semanticCriterion | string | Required | Unique id. | Duplicate ids rejected. |
| `semanticCriteria[].description` | semanticCriterion | string | Optional | Row label + `detail`. | — |
| `semanticCriteria[].points` | semanticCriterion | number | Required | Points (full/partial→floor(½)/0). | — |
| `semanticCriteria[].hardFail` | semanticCriterion | boolean | Optional | Failing zeroes the question. | Use for architecturally-naive mistakes only. |
| `semanticCriteria[].kind` | semanticCriterion | `placement \| guardedPath \| fanout \| storageFit \| forbidUnjustified` | Required | Check kind. | — |
| `placement.componentType` | placement | `ComponentType` | Required | The placed component. | — |
| `placement.between` | placement | `[ComponentType, ComponentType]` | Optional | On a directed A→…→B path. | — |
| `placement.notBefore` | placement | `ComponentType` | Optional | Not upstream of X. | — |
| `placement.orderedPipeline` | placement | `ComponentType[]` | Optional | Types appear in order along a path. | — |
| `guardedPath.from` | guardedPath | `ComponentType` | Required | Path origin. | — |
| `guardedPath.guard` | guardedPath | `ComponentType` | Required | Mandatory guard node. | — |
| `guardedPath.to` | guardedPath | `ComponentType` | Optional | Path destination. | With a read/write mix, a `to` guardedPath can wrongly fail correct designs (writes bypass) ⇒ validator `guardedPath.readWriteMix`. |
| `fanout.broker` | fanout | `ComponentType` | Required | Fan-out broker. | — |
| `fanout.minConsumers` | fanout | number | Required | Distinct downstream consumers required. | — |
| `fanout.forbiddenBroker` | fanout | `ComponentType` | Optional | Wrong primitive (queue) feeding N ⇒ hard-fail case. | — |
| `storageFit.accessPattern` | storageFit | `point-lookup \| time-series \| append-only-ledger \| transactional-relational \| search-index \| blob` | Required | The access pattern. | See Appendix C. |
| `storageFit.accept` | storageFit | `ComponentType[]` | Required | Full-credit store types. | — |
| `storageFit.partial` | storageFit | `ComponentType[]` | Optional | Half-credit (defensible). | — |
| `storageFit.antiPattern` | storageFit | `ComponentType[]` | Optional | Anti-pattern types (hard-fail-worthy). | Present anti-pattern ⇒ fail (hard-fail if flagged). |
| `forbidUnjustified.componentType` | forbidUnjustified | `ComponentType` | Required | Component to guard. | — |
| `forbidUnjustified.justifyId` | forbidUnjustified | string | Optional | Bound justify prompt id. | Dangling ⇒ validator `justify.dangling`; missing ⇒ present component always fails. |
| `justify[].id` | justify | string | Required | Unique id. | — |
| `justify[].decision` | justify | string | Required | Decision to defend. | — |
| `justify[].boundTo` | justify | `{ nodeId?, componentType? }` | Optional | Graph binding. | — |
| `justify[].requires.choice` | justify | boolean | Required | Graph-consistency gate. | — |
| `justify[].requires.number` | justify | boolean | Optional | Must cite a scale number. | — |
| `justify[].requires.tradeoff` | justify | boolean | Required | Must state a tradeoff. | — |
| `justify[].acceptTradeoffTokens` | justify | string[] | Optional | Tradeoff keywords. | — |
| `budget.unit` | budget | `cost \| nodes \| edges` | Required | Budget dimension. | — |
| `budget.cap` | budget | number > 0 | Required | Ceiling. | — |
| `suite.name` | suite | string | Required | Suite name. | — |
| `suite.visibleToStudent` | suite | boolean | Required | Show scenarios to student. | `false` = hidden contest suite. |
| `suite.dryRunCase` | suite | `QuestionSuiteCase` | Optional | Case the student may dry-run. | — |
| `suite.cases[].id` | suite case | string | Required | Case id. | Empty `cases` ⇒ validator `suite.empty` (error). |
| `suite.cases[].description` | suite case | string | Optional | Case label. | — |
| `suite.cases[].global` | suite case | `Partial<GlobalConfig>` | Optional | Global override (seed/duration). | Question-owned — fixes seed to kill seed-farming. |
| `suite.cases[].workload` | suite case | `Partial<WorkloadProfile>` | Optional | Injected load (RPS + mix). | The read/write mix lives here (`requestDistribution`). |
| `suite.cases[].faults` | suite case | `FaultSpec[]` | Optional | Injected chaos faults. | Question-owned HA scenario. |
| `workload.baseRps` | workload | number > 0 | Required (in a workload) | Tractable RPS (~2–5K). | Not the display scale. |
| `workload.pattern` | workload | `constant \| poisson \| bursty \| diurnal \| spike \| sawtooth \| replay` | Required (in a full workload) | Arrival pattern. | — |
| `workload.requestDistribution[].type` | requestDistribution | string | Required | Traffic class (`read`/`write`/`GET`…). | Used in edge `condition`. |
| `workload.requestDistribution[].weight` | requestDistribution | number 0–1 | Required | Fraction of traffic. | Weights should sum to 1.0. |
| `workload.requestDistribution[].sizeBytes` | requestDistribution | number | Required (full topology) | Payload size. | Missing on a full topology ⇒ validation error. |
| `workload.requestDistribution[].metadata` | requestDistribution | object | Optional | Untyped escape hatch. | Not consumed by grading. |
| `global.seed` | global | string | Required (full) | RNG seed. | Question-fixed to prevent seed-farming. |
| `global.simulationDuration` | global | number > 0 (ms) | Required (full) | Sim length. | Keep short for the browser. |
| `global.warmupDuration` | global | number ≥ 0 (ms) | Required (full) | Pre-metrics warmup. | — |
| `global.timeResolution` | global | `microsecond \| millisecond` | Required (full) | Tick resolution. | — |
| `global.defaultTimeout` | global | number > 0 (ms) | Required (full) | Request timeout. | — |
| `global.traceSampleRate` | global | number 0–1 | Optional | Trace sampling. | — |
| `rubric.id` | rubric | string | Required | Rubric id. | — |
| `rubric.passThreshold` | rubric | number 0–1 | Optional (=1) | Fraction of points to pass. | — |
| `rubric.checks[].id` | rubric check | string | Required | Check id. | — |
| `rubric.checks[].description` | rubric check | string | Required | Row label. | — |
| `rubric.checks[].kind` | rubric check | `topology \| simulation \| invariant` | Optional | Inferred from metric prefix if omitted. | Mismatch (simulation check on `topology.*`) ⇒ validator `metric.kindMismatch`. |
| `rubric.checks[].metric` | rubric check | verdict path (§4.2) | Required | Metric to compare. | `summary.latencyP99Ms` ⇒ validator `metric.badLatencyKey`. |
| `rubric.checks[].op` | rubric check | `< \| <= \| > \| >= \| == \| !=` | Required | Comparison. | — |
| `rubric.checks[].value` | rubric check | number | Required | Threshold. | — |
| `rubric.checks[].points` | rubric check | number | Optional (=1) | Points. | — |

---

## Section 8 — Schema Validation & Engine Gotchas Index

### 8.1 The two-stage validation pipeline
1. **`parseQuestionPackage(raw)`** — Zod schema validation. Enforces types, enums,
   required fields, and unique ids (`structuralRules`, `semanticCriteria`,
   `justify`). Throws on any schema violation. This is what the Django admin
   `clean()` / the Node `/validate` runs; a malformed package cannot be saved.
2. **`validateAuthoredQuestion(pkg)`** — the authoring-contract lint (semantic, not
   schema). Returns `error`/`warning` diagnostics: wrong metric keys, un-injected
   scale numbers, missing `sizeBytes`, orphan NFRs, correctness-on-simulation,
   dangling justify bindings, read/write `guardedPath` misuse. `error`s should block
   a save; `warning`s are advisory.

### 8.2 Gotcha index
- **Metric key resolution** — use the exact verdict paths (`summary.latency.p99`).
  `summary.latencyP99Ms` never resolves. Topology metrics need `kind: "topology"`.
- **String keys vs enum values** — `componentType`/`category` must be valid
  `ComponentType`/`ComponentCategory` strings. **`batch-worker` is a *type*; its
  *category* is `compute`** (a category is a fixed enum, not the type name).
- **`sizeBytes` is mandatory** on a full topology's `requestDistribution` entries
  (the suite override is a partial and tolerates its absence).
- **Read/write mix is JSON-only** — not settable on the canvas or a source node
  (both `Omit` `requestDistribution`); and it only affects the sim when the topology
  routes on `request.type`.
- **Omitted edge latency is now deterministic by default** — a bare edge resolves to
  a path-type-derived **constant** median latency, not an implicit log-normal. If a
  question needs network jitter, author it explicitly.
- **Instance-model resources change the meaning of capacity** — once a node carries
  `resources.instanceType` / `instanceCount`, effective concurrency is derived from
  the instance model. Legacy `queue.workers`-only intuition no longer applies
  unchanged to that node.
- **Short-circuit** — a failing `structuralRule` skips semantic + simulation. Design
  gamed topologies to pass structural if you want a specific semantic check to fail.
- **CLI vs in-app** — `forbidUnjustified` fails a present component in the CLI (no
  answer capture) but passes a defended one in-app.
- **hardFail zeroes the question** — reserve for architecturally-naive mistakes.
- **Correctness ≠ simulation** — never author a `simulation` check for exactly-once,
  ordering, immutability, or no-double-book.
- **Tractable RPS** — `baseRps` ~2–5K; the real number goes in `prompt.scale`.
- **Graded cost is still heuristic** — the live app may show richer instance-aware
  cost numbers, but question-package `budget.unit:"cost"` still grades via
  `estimateNodeCost` in `budget.ts`.

### 8.3 Implementation status — graded vs schema-only
Not every schema field drives grading. Author accordingly.

| Feature | Schema | Graded / behavioral? |
|---------|--------|----------------------|
| `structuralRules` (all kinds) | ✅ | ✅ graded |
| `rubric` (`simulation`/`topology`/`invariant`) | ✅ | ✅ graded |
| `semanticCriteria` (placement/guardedPath/fanout/storageFit/forbidUnjustified) | ✅ | ✅ graded (evaluators + hardFail) |
| `justify` (graph-consistent) | ✅ | ✅ graded; feeds `forbidUnjustified` in-app |
| **`budget`** | ✅ | ✅ **graded** (`budget.ts` — nodes/edges exact, cost = v1 heuristic) |
| `suite.cases[].workload` / `global` / `faults` | ✅ | ✅ injected at grade time |
| `constraints.*` (`maxNodeCount`, `maxBudget`, `maxTotalWorkers`, `allowed/forbiddenNodeTypes`) | ✅ | ❌ **not enforced at grade time** (UI/palette only) — use `budget` + `max_node_count`/`max_component_count` structural rules to enforce |
| `workloadCategory` | ✅ | ❌ label only (author-side axis selector; not read by grading) |
| `domains` | ✅ | ⚠️ **advisory + platform-facing** — checked by the authoring validator and consumed by environment-profile / edit-policy logic, but not scored as a rubric axis by themselves |
| `concepts` | ✅ | ❌ metadata only (taxonomy / indexing aid; not graded) |
| `type` (`fix`/`build-budget`/`optimize`/`open-build`/`scaling`/`ha-chaos`/`tradeoff`) | ✅ | ❌ **all are labels** — none drives behavior. `optimize` does **not** grade against `scaffold.baselineVerdict`; `build-budget` does not auto-enforce `budget`; `ha-chaos` "works" only via `suite.faults`. |
| `scaffold.baselineVerdict` | ✅ | ❌ not graded (no "beat the baseline" check) |
| `requestDistribution[].metadata` | ✅ | ❌ not consumed |
| `readWriteRatio → requestDistribution` auto-derivation | — | ❌ not built (author the mix by hand) |

> To enforce a node cap, use `budget:{unit:"nodes",cap:N}` or a
> `max_node_count`/`max_component_count` structural rule — `constraints.maxNodeCount`
> alone does nothing at grade time.

---

## Appendix A — The Functional-Requirement Taxonomy (all FR classes)

Every FR reduces to one of these classes. Each maps to a DSL obligation (T/S) or
is **narrative** (app-logic the sim can't grade → structural proxy + `justify`).

| FR class | Example verbs / phrasings | Obligation | Gradeable? |
|----------|---------------------------|------------|-----------|
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
| **Generate an id / encode** | "generate a unique code", "base62" | **narrative** — structural proxy (a store) + `justify` context | J only |
| **Return a protocol response** | "return 301/302", "HTTP status" | **narrative** — `justify` context; not modeled | J only |

---

## Appendix B — Per-Archetype Solution-Nuance Catalog (the "nitty-gritties")

Nuances an expert answer includes. Classified: **[G]** gradeable in the sim/DSL;
**[J]** justification-only (deterministic text check); **[N]** narrative/context
(surface in prompt or `justify`, not gradeable).

**URL Shortener** — base62 code encoding **[N/J]**; 301 (permanent) vs 302
(temporary) redirect **[N/J]**; key = short code, point-lookup **[G storageFit]**;
counter/ZooKeeper-range vs hash for id generation **[J]**; cache the hot reads
**[G Σ p99]**; write path persists (not cache-served) **[N/J]**.

**News Feed** — fan-out-on-write vs on-read given the read ratio **[J]**; timeline
store is point-lookup **[G]**; broker fans to timeline builders **[G fanout]**;
celebrity/hot-key handling **[J]**.

**Sensor / time-series** — wide-column/TSDB, NOT relational **[G storageFit hardFail]**;
partition key = sensor_id, clustering = timestamp **[J]**; downsampling/retention
**[N]**; write throughput **[G Σ throughput]**.

**Cache placement** — cache between service & DB, not before the LB **[G placement]**;
cache-aside vs write-through **[J]**; TTL / invalidation **[J]**.

**Messaging fan-out** — pub/sub broker not a work-queue (queue→N is wrong) **[G fanout hardFail]**;
at-least-once vs exactly-once delivery **[J]**; consumer groups **[J]**.

**Cargo-cult CDN** — CDN wasteful for dynamic per-user responses; omit or defend
**[G forbidUnjustified + J]**; static vs dynamic cacheability **[J]**.

**Ride-hailing** — geospatial hot path (geohash/quadtree) off the txn DB
**[G placement]**; payment path = SQL, strongly consistent **[G storageFit]**;
match latency < 3s **[G Σ]**; location updates high-frequency stream **[T]**;
surge pricing **[N]**.

**Rate limiter** — counters in a **shared** store, not per-instance **[G requires_edge + guardedPath hardFail]**;
token-bucket vs sliding-window algorithm **[J]**; cache not DB for counters (latency)
**[J number]**; atomic increments / Lua **[N]**.

**Async SLA** — queue + scalable workers; sync fails the SLA at load **[G Σ + structural]**;
autoscaling policy **[J + $ budget]**; back-pressure / DLQ **[J]**; idempotent workers **[J]**.

**Ticketmaster** — distributed lock (with TTL) serializes seat holds; no double-book
**[G guardedPath hardFail + J]**; virtual waiting queue absorbs surge **[G requires_component + Σ]**;
bookings transactional-relational **[G storageFit]**; search-index for events **[G]**;
OCC vs pessimistic locking **[J]**.

**Web Crawler** — frontier→fetch→process ordered pipeline **[G placement orderedPipeline]**;
URL dedup before enqueue (bloom filter / index) **[G guardedPath + J]**; per-domain
politeness / rate-limit **[J]**; content dedup (simhash) **[J]**; aggregate throughput
**[G Σ]**; DLQ for failures **[J]**; content in blob/object-storage **[G storageFit blob]**.

**Payment** — idempotency key guards every write; exactly-once **[G guardedPath hardFail + J]**;
immutable append-only double-entry ledger **[G storageFit append-only-ledger hardFail]**;
reconciliation job **[N]**; 2-phase / saga for cross-service **[J]**; durable, HA
ledger **[G Σ availability / errorRate]**.

---

## Appendix C — Access-Pattern Catalog (`storageFit.accessPattern`)

The full enum + recommended `accept` / `antiPattern` store types. Access pattern
is an **authored grading concept** (inferred by the student from the FRs); it is
NOT a canvas/node property. The student chooses a store type; `storageFit` grades
the fit.

| `accessPattern` | Meaning | `accept` (full credit) | `partial` | `antiPattern` (hard-fail-worthy) |
|-----------------|---------|------------------------|-----------|-----------------------------------|
| `point-lookup` | get-by-key (URL→long) | `kv-store`, `nosql-db` | `in-memory-cache` | `relational-db` (at scale) |
| `time-series` | append + range-by-time (sensors) | `time-series-db`, `columnar-db`, `nosql-db` | — | `relational-db` |
| `append-only-ledger` | immutable double-entry (payments) | `event-sourcing-store` | — | `in-memory-cache`, mutable stores |
| `transactional-relational` | ACID, joins, money (bookings) | `relational-db` | — | `in-memory-cache`, `kv-store` |
| `search-index` | full-text / faceted (events, products) | `search-index` | `nosql-db` | `relational-db` (for full-text) |
| `blob` | large immutable objects (media, crawl content) | `object-storage`, `block-storage` | `distributed-file-system` | `relational-db`, `kv-store` |

> **Candidate additions** (not yet in the enum — future work): `wide-column`
> (distinct from time-series), `graph-traversal` (`graph-db`), `vector-similarity`
> (`vector-db`), `geospatial` (geohash/quadtree over a KV/index), `counter`
> (atomic increment — cache), `stream` (`stream`/`event-bus`). Until added, model
> these via `accept`/`antiPattern` type lists on the nearest pattern + a `justify`.

# Question Grading Model & Anti-Gaming

> **Purpose.** Reverse-engineer a *generalized* question + grading model for the
> HLD simulator from two faculty inputs, and design it so students **cannot game
> it** - i.e. cannot exploit the grading rules to score without the understanding
> the question is meant to test.
>
> **Sources.**
>
> 1. *HLD System Design Simulator - Lab & Exam Question Bank* (faculty spec: 5
>    labs, 3 exams, grading logic, Section C dev-team notes).
> 2. *System Design Interview Prep* (the "answer key": URL Shortener, Chat, News
>    Feed, Google Docs - fully worked, plus the Cross-Cutting Patterns cheat
>    sheet).

This spec is the design authority for the grading model. The implementation
companion lives in `docs/question-platform-hardening/`.

---

## 0. The central finding: a grading-model mismatch is the root of gaming

The faculty grade a design on **three axes**; the simulator today covers mainly
one.

| Axis                     | What the docs grade                                                                                           | What the simulator does today                    |
| ------------------------ | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Topology correctness** | node & edge *presence*, *placement/ordering*, *direction*, *fan-out shape*, *storage-type-for-access-pattern* | `structuralRules` (presence + a few path checks) |
| **Reasoning**            | a **required, gradeable justification** - "choosing X because *[number]*, tradeoff is Y"                      | **nothing** - no justification field exists      |
| **Behaviour under load** | implied by the scale numbers                                                                                  | ✅ `rubric.checks` over simulation metrics        |

**Gaming is what happens when a design is graded on only one axis**, because any
single axis is exploitable:

- Grade only on **simulation metrics** → the student cranks a single node's (or
  edge's) capacity/timeout/bandwidth until the metric passes, with the wrong
  architecture. (Lab 4's "200K writes to a single SQL" *passes a lenient sim*.)
- Grade only on **node/edge presence** → the *kitchen-sink*: drop every node and
  wire everything to everything to satisfy every `requires_X`. (Exactly the
  "cargo-cult a CDN" mistake Lab 5 exists to catch.)
- Grade justification by **keyword match** → keyword-stuffing.

The faculty already encode the defense implicitly - **hard-fail vs partial
credit**, a **required justification**, and *"justify omission as much as
inclusion."* So anti-gaming is not a feature bolted on; it is the **organising
principle**: grade on **≥3 orthogonal axes + a graph-consistent justification + a
global cost budget**, so that gaming one axis is caught by another.

---

## 1. The reasoning spine (what a good answer looks like)

Both docs share one spine, which the generalized question must elicit and grade:

```
Requirements (FR + NFR) → API / Data Model → Capacity (the numbers)
        → HLD, node-by-node "why each box exists" → Bottlenecks & Tradeoffs
```

The target sentence, verbatim from the prep doc, is the reasoning unit we grade:

> **"I'm choosing X because [number], the tradeoff is Y."**

and its closing frame:

> **"The workload is [read-heavy / write-heavy / connection-heavy /
> correctness-heavy], so I optimized for [X] and accepted [Y] as the tradeoff."**

Every grading mechanism below exists to check some instance of that pattern -
against **both the graph and the numbers**, not against prose alone.

---

## 2. The generalized question schema

Every question in both docs collapses to one record (the faculty confirm this in
Section C: *"each question follows the same schema … additional questions can be
authored later using the same JSON/data shape without engine changes"*).

```
Question
├── meta        id, title, mode(lab|exam), difficulty, timeLimitSec?, totalPoints
├── prompt      text
│               FR[]      { id, text }                       // functional reqs
│               NFR[]     { id, metric, op, target, unit }   // measurable targets
│               scale     { dau?, writesPerSec?, readsPerSec?, rwRatio?,
│                           retention?, objectSize?, derived[] }
│               constraintsPanel   // display strings for the numbers
├── scaffold    given nodes/edges (Lab 1 gives Client + 3 App Servers)
├── rubric      criteria[]  { id, points, kind, hardFail?, ...kind-specific... }
│               where kind ∈ CHECK_KINDS (§4)
├── justify     prompts[]   { id, decision, boundTo, requires{choice,number,tradeoff} }
├── budget      { unit: 'cost'|'nodes'|'edges', cap }        // anti-kitchen-sink
└── instructorNotes         // hidden from student
```

Mapping to the current `QuestionPackage` (see gap analysis, §8):

| Schema part                | Current field                                                           | Status                                          |
| -------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| meta.mode (lab/exam)       | `EnvironmentProfile` PRACTICE/ASSIGNMENT                                | ✅ have                                          |
| prompt.FR / NFR / scale    | `prompt.functionalRequirements` / `nonFunctionalRequirements` / `scale` | ✅ have                                          |
| scaffold                   | `scaffold`                                                              | ✅ have                                          |
| rubric (metric checks)     | `rubric.checks`                                                         | ✅ have (simulation kind)                        |
| structural checks          | `structuralRules`                                                       | ✅ have (presence/path)                          |
| **justify**                | -                                                                       | ❌ new                                           |
| **budget**                 | -                                                                       | ❌ new (see `cost-calculation-and-budgeting.md`) |
| weighted points + hardFail | partial (`points`)                                                      | ⚠️ extend                                        |

---

## 3. How each evaluation dimension is graded

Grounded in specific questions. "Axis" = which grading axis the dimension lives
on (

1. T = topology, 

2. S = scale-fit semantics, 

3. Σ = simulation, 

4. J = justification,

5. $ = budget

).

| Dimension                           | Evidence                                                                   | Mechanism                                                        | Axis | New?     |
| ----------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------- | ---- | -------- |
| **FR**                              | Exam 1: match / track / surge / pay                                        | each FR → a required sub-path/node-set                           | T    | extend   |
| **NFR - latency/throughput**        | Exam 1 "<3s match"; Exam 2 "<5ms"                                          | simulation check vs target under load                            | Σ    | have     |
| **NFR - consistency/durability**    | Exam 1 payment strongly consistent                                         | semantic: payment path must be SQL (not Σ)                       | S    | new      |
| **Scale (numbers)**                 | prep doc pins *every* decision to a number                                 | drives 3 things: panel display, sim workload, scale-aware checks | S+Σ  | plumbing |
| **Storage-type for access pattern** | Lab 4: 200K writes + time-series → wide-column, SQL = anti-pattern         | `storageFit` check                                               | S    | **new**  |
| **READ:WRITE ratio**                | URL 100:1; Feed 50:1; Lab 2 20:1                                           | drives sim workload mix + "must cache when read-heavy" check     | S+Σ  | new      |
| **Fan-out / messaging**             | Lab 3: 1 broker + 3 consumers ✅; 1 queue→3 = hard fail; 3 queues = partial | `fanout` check (node-type-aware)                                 | T    | **new**  |
| **Placement / ordering**            | Lab 2: cache between AppServer & DB, *not* before LB                       | `placement` check (adjacency/order/forbidden position)           | T    | extend   |
| **Edge direction / data flow**      | prep flows are directional; DB→Client is wrong                             | directional path check, not adjacency                            | T    | extend   |
| **Tradeoffs / core hard problem**   | prep "choosing X because [n], tradeoff Y"                                  | `justification` check (structured, graph-consistent)             | J    | **new**  |
| **Omission (anti-cargo-cult)**      | Lab 5: CDN wasteful for Service B; justify *not* adding                    | `forbidUnjustified` check                                        | T+J  | **new**  |
| **Hot/cold path separation**        | Exam 1: geospatial cache vs SQL (20 pts)                                   | placement + latency-budget sim                                   | T+Σ  | extend   |
| **Async vs sync**                   | Exam 3: sync violates 15s SLA at 50K/min                                   | sim fails SLA + queue/worker present                             | Σ+T  | have     |
| **Autoscaling / cost**              | Exam 3: autoscale (20 pts); kitchen-sink costs more                        | `budget`/cost                                                    | $    | **new**  |

---

### 3.1 Worked encoding - one concrete example per dimension

Each snippet is a **schema-valid** `QuestionPackage` fragment (validated with
`parseQuestionPackage`). Full packages live in
`question-bank-initial-game-states.md`. Metric keys are the real verdict paths
(`summary.latency.p99`, `summary.throughput`, `invariantViolations.count`).

**FR** → each functional requirement becomes a required node/sub-path (`structural`).
Exam 1 "pay" ⇒ a payment path must exist and reach the transactional DB:

```json
{ "id": "pay-path", "kind": "requires_path", "fromType": "microservice", "toType": "relational-db",
  "description": "A payment path reaches the transactional store" }
```

**NFR - latency/throughput** → a `simulation` rubric check vs a target under the
injected load (Σ). Exam 1 "<3s match":

```json
{ "id": "match-latency", "kind": "simulation", "metric": "summary.latency.p99", "op": "<", "value": 3000, "points": 3,
  "description": "p99 match under 3s" }
```

**NFR - consistency/durability** → *semantic*, not simulation - the sim can't
measure consistency, so assert the store type (S). Exam 1 payment strongly consistent:

```json
{ "id": "pay-fits-relational", "kind": "storageFit", "accessPattern": "transactional-relational",
  "accept": ["relational-db"], "antiPattern": ["in-memory-cache"], "points": 3, "hardFail": true,
  "description": "Payment is ACID/transactional, not a cache" }
```

**Scale (numbers)** → one number drives three surfaces: the prompt panel, the
injected workload, and scale-aware checks. It is *plumbing*, not a check:

```json
"prompt": { "scale": { "peakRps": 200000, "readWriteRatio": 99 } },
"suite": { "cases": [ { "id": "peak",
  "workload": { "baseRps": 2000, "requestDistribution": [
    { "type": "read", "weight": 0.99 }, { "type": "write", "weight": 0.01 } ] } } ] }
```

**Storage-type for access pattern** → `storageFit` maps `(accessPattern) →
accept / antiPattern`. Lab 4 time-series (SQL = hard fail):

```json
{ "id": "store-fits-time-series", "kind": "storageFit", "accessPattern": "time-series",
  "accept": ["time-series-db", "columnar-db"], "antiPattern": ["relational-db"], "points": 6, "hardFail": true,
  "description": "200K writes/s time-series → wide-column, not relational" }
```

**READ:WRITE ratio** → injected as **typed** traffic in the workload (drives the
sim mix); the "must cache when read-heavy" property is enforced by the **p99
simulation** check, *not* a topology rule (writes legitimately bypass the cache -
alignment §9). So it's the §Scale workload block **plus** the §NFR-latency check
above - no separate check kind.

**Fan-out / messaging** → node-type-aware `fanout` (a *queue* to N is the hard
fail). Lab 3:

```json
{ "id": "fanout", "kind": "fanout", "broker": "message-broker", "minConsumers": 3,
  "forbiddenBroker": "queue", "points": 5, "hardFail": true,
  "description": "Broker fans out to 3 independent consumers; a queue to 3 is wrong" }
```

**Placement / ordering** → `placement` with adjacency + forbidden position. Lab 2
(cache between service & DB, not before the LB):

```json
{ "id": "cache-between", "kind": "placement", "componentType": "in-memory-cache",
  "between": ["microservice", "relational-db"], "notBefore": "load-balancer", "points": 4,
  "description": "Cache sits between service and DB, never before the LB" }
```

**Edge direction / data flow** → directional guard, not mere adjacency. Use
`guardedPath` (all `from`→`to` traffic must traverse a guard, in direction), or a
directed `requires_path`. Rate-limiter counters must reach the shared store:

```json
{ "id": "counters-in-shared-store", "kind": "guardedPath", "from": "rate-limiter",
  "guard": "in-memory-cache", "points": 4, "hardFail": true,
  "description": "All rate-limit checks traverse the shared counter store" }
```

**Tradeoffs / core hard problem** → a graph-consistent `justify` prompt (J):

```json
{ "id": "why-db", "decision": "Why this DB type for 200000 writes/sec time-series?",
  "boundTo": { "componentType": "time-series-db" },
  "requires": { "choice": true, "number": true, "tradeoff": true } }
```

**Omission (anti-cargo-cult)** → `forbidUnjustified`: absent, or present *and*
defended. Lab 5 CDN:

```json
{ "id": "cdn-justified", "kind": "forbidUnjustified", "componentType": "cdn",
  "justifyId": "why-cdn", "points": 4,
  "description": "CDN must be absent, or defended by a valid justification" }
```

(paired with a `justify` prompt whose `id` is `why-cdn`.)

**Hot/cold path separation** → `placement` (hot path off the transactional DB) +
a latency `simulation` check on the hot path (T+Σ). Exam 1 geospatial:

```json
{ "id": "geo-hot-path", "kind": "placement", "componentType": "in-memory-cache",
  "between": ["microservice", "relational-db"], "points": 2,
  "description": "Geospatial matching uses a cache/index, not the payment DB" }
```

**Async vs sync** → structural (queue + workers present) **plus** an SLA
`simulation` check that a synchronous design fails under load (Σ+T). Exam 3:

```json
"structuralRules": [
  { "id": "has-queue", "kind": "requires_component", "componentType": "queue", "description": "Async queue decouples ingest" },
  { "id": "has-workers", "kind": "requires_component", "componentType": "batch-worker", "description": "Scalable workers" } ],
"rubric": { "checks": [
  { "id": "sla", "kind": "simulation", "metric": "summary.latency.p99", "op": "<", "value": 15000, "points": 3,
    "description": "p99 completion under 15s - a sync path fails this at 50K/min" } ] }
```

**Autoscaling / cost** → the `budget` axis caps total cost so a kitchen-sink
design fails ($):

```json
"budget": { "unit": "cost", "cap": 600 }
```

---

## 4. The check-kind taxonomy

Every rubric criterion is one of these kinds. Each is a **pure function of the
graph (+ scale + justification)**, returns pass / partial / fail, and may set
`hardFail` (a hard fail zeroes the whole question regardless of other credit -
faculty are explicit that some mistakes are *architecturally naive*, not merely
*suboptimal*).

| kind                | Inputs                                                          | Passes when                                                                            | Example                                          |
| ------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `structural`        | graph, node types                                               | required nodes present (min/max counts)                                                | Lab 1: API Gateway present                       |
| `placement`         | graph, ordering/adjacency rules                                 | node sits in the required position; forbidden positions absent                         | Lab 2: cache between AppServer↔DB, not before LB |
| `direction`         | graph, directed path spec                                       | traffic path exists **in the correct direction**; no reverse/bypass edge               | redirect path Client→…→DB, no Client→DB shortcut |
| `fanout`            | graph, node-type semantics                                      | a *broker* fans out to N independent consumers (a *queue* to N ≠ fan-out)              | Lab 3                                            |
| `storageFit`        | scale, access pattern, chosen DB type                           | DB type matches the access pattern; flags anti-patterns                                | Lab 4 (wide-column), Exam 1 payment (SQL)        |
| `simulation`        | verdict metrics vs NFR targets under the scale-derived workload | metric meets target                                                                    | Exam 3 15s SLA                                   |
| `justification`     | text, bound decision, graph                                     | names choice + cites a scale number + states a tradeoff, **consistent with the graph** | every "justify" prompt                           |
| `forbidUnjustified` | graph, node/edge, bound justification                           | node/edge absent, OR present *and* defended by a valid justification                   | Lab 5 CDN-for-Service-B                          |
| `budget`            | graph, cost model                                               | total cost / node count / edge count ≤ cap                                             | anti-kitchen-sink                                |

`structural`, `placement`, `direction`, `fanout` all operate on **nodes *and*
edges** - see §6 for why edges need their own defenses.

### 4.1 Evaluation algorithms (implemented)

The semantic axis ships in `src/engine/analysis/semanticCriteria.ts` -
`evaluateSemanticCriteria(topology, criteria, ctx)`. Every evaluator is a
deterministic graph computation over the submitted topology (the same BFS /
reachability toolkit as `structural.ts`), returning `passed | partial | failed`
plus a `detail` string. Points are awarded **full** (passed), **floor(points/2)**
(partial), or **zero** (failed); a `hardFail` criterion that fails sets
`hardFailed`, which drops the host contract's `allPassed`.

| kind                                                                | Exact computation                                                                                                                                                                                                                                         | Fails when                                                                                                                                                                                                                            |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **guardedPath** (`from`,`guard`,`to?`)                              | Confirm `to` is reachable from `from` on the directed graph; then **rebuild the graph with the guard nodes removed** and re-run reachability.                                                                                                             | A `from→to` path survives guard removal (an unguarded **bypass** exists), or `from`/`guard`/`to` is missing, or `from`→`to` is unreachable even with the guard. When `to` is omitted: fails if the guard isn't reachable from `from`. |
| **placement** (`between?`,`notBefore?`,`orderedPipeline?`)          | `between[A,B]`: some component node is reachable from an `A` **and** reaches a `B`. `notBefore X`: no component node reaches an `X`. `orderedPipeline[T₁..Tₙ]`: layered reachability - the frontier of `Tᵢ` nodes must reach a `Tᵢ₊₁` node at each stage. | The component is absent, or off the A→B path, or upstream of a `notBefore` type, or the pipeline order breaks.                                                                                                                        |
| **fanout** (`broker`,`minConsumers`,`forbiddenBroker?`)             | For each `broker` node, count **distinct** out-edge targets; pass if any ≥ `minConsumers`.                                                                                                                                                                | No broker meets the count. If a `forbiddenBroker` node (queue semantics) meets the count instead, fail with the "queue ≠ fan-out" detail (the hard-fail case).                                                                        |
| **storageFit** (`accessPattern`,`accept`,`partial?`,`antiPattern?`) | Classify the store types **present** in the graph: any `antiPattern` present → fail; else any `accept` present → pass; else any `partial` present → partial; else fail.                                                                                   | An anti-pattern store is present (e.g. `relational-db` at a point-lookup), or no fitting store exists.                                                                                                                                |
| **forbidUnjustified** (`componentType`,`justifyId?`)                | Absent ⇒ pass. Present ⇒ pass only if `ctx.justificationPassed(justifyId)` is `true`.                                                                                                                                                                     | Present with no bound justification, or an undefended/unevaluated justification (conservative: undefined justification result ⇒ fail).                                                                                                |

**Ordering & dependency.** Semantic criteria run **after** the structural gate
passes (a structurally-broken topology short-circuits before simulation *and*
semantics). The `forbidUnjustified` evaluator's justification lookup is injected
via `SemanticContext`, so the module stays pure and unit-tested; until graded
justification answers are threaded in (Phase 2b), a present-but-undefended
component conservatively fails.

---

## 5. The justification model (structured, graph-consistent)

**Decision: structured, graph-consistent justification - not free-prose keyword
matching, and not an LLM judge.** Deterministic, un-stuffable, no per-grade cost.

A justification prompt is **bound to a decision** and graded on three
requirements, each checkable against the graph and the numbers:

```
justify prompt
  decision:  "Why this database type for the write path?"
  boundTo:   { node: 'primary-store' }        // ties the answer to a real node
  requires:
    choice:   the student must reference the actual chosen node/type in the graph
    number:   the student must cite a scale number from THIS question (e.g. 200K w/s)
    tradeoff: the student must state what is given up ("lose ad-hoc joins")
```

Grading:

1. **Graph-consistency (the anti-stuffing core).** The claimed choice must match
   what is *actually in the graph*. If the text says "I used Cassandra for
   throughput" but the graph has a SQL node on that path → the justification
   **fails** and the mismatch is surfaced. You cannot write a correct-sounding
   justification for a wrong graph.
2. **Number-citation.** Must reference a number the question actually defines
   (randomized per attempt - §7), so memorized prose from a reference answer
   doesn't fit.
3. **Tradeoff presence.** Must name a cost/limitation, matched against an
   authored set of acceptable tradeoff tokens *plus* a "not a non-answer" check
   (empty/echo-the-prompt rejected).

This makes the justification a **cross-check on the topology**, not a parallel
prose channel - which is exactly what defeats keyword-stuffing.

---

## 6. Edge gaming - first-class, not an afterthought

Nodes are the obvious target; **edges are the subtle one**, because edges encode
the data flow. Every graph-based check must consider edges, direction, and edge
properties - not just node sets.

| Edge gaming vector                     | Exploit                                                                                                    | Defense                                                                                                                                                                                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Complete graph / edge kitchen-sink** | wire everything→everything to satisfy any `requires_edge`/connectivity                                     | `budget` on edge count/cost; require *specific directional* paths, not mere adjacency; penalize unused edges                                                                                                                            |
| **Wrong-direction edges**              | connectivity passes but data flows backwards (DB→Client)                                                   | `direction` check on directed paths (we already model edge direction / `request-flow-direction-and-topology-rules`)                                                                                                                     |
| **Fake fan-out**                       | 3 edges off a single **Message Queue** to look like a broker                                               | `fanout` is **node-type-aware**: a queue with N out-edges is *not* fan-out; only a broker with N consumer groups is                                                                                                                     |
| **Edge-property tuning**               | set edge `errorRate=0`, `latency=0`, `bandwidth=∞`, `maxConcurrentRequests=∞` to pass the sim              | faithful edge-property **bounds + defaults** (`edge-properties-and-defaults`, `default-driven-simplification-layer`); **edge cost** (`cost-calculation-and-budgeting`); in exam mode, lock/validate edge props against realistic ranges |
| **Bypass / shortcut edges**            | add a hidden `Client→DB` edge that skips the required cache/gateway while keeping the correct path present | forbidden-edge checks; **"all traffic must traverse the required path"** (a stronger `direction` check than "a path exists")                                                                                                            |
| **Self-loops / duplicate edges**       | pad to satisfy counts                                                                                      | normalize graph before grading; reject/ignore self-loops & duplicates                                                                                                                                                                   |

**Principle:** the grading target is the **directed, typed, property-bearing
graph**, and edge-level exploits are defended by the *same* defense-in-depth -
budget (edge cost), faithful simulation (edge-property ceilings), and topology
semantics (direction + node-type-aware fan-out).

---

## 7. Anti-gaming - the full model

Grade on **≥3 orthogonal axes + justification + budget**, so gaming one fails
another.

### 7.1 Who controls what - the test/architecture split

The single most important structural rule: **the question owns the test
conditions; the student owns only the architecture.**

| Surface                                                                       | Owner                 | Anti-gaming rationale                                                                                                                                                                                                       |
| ----------------------------------------------------------------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Workload** (RPS, traffic pattern, read/write mix, request types/sizes)      | **question**          | injected at grade time, overriding any student value - else a student sets a 1-RPS, all-cache-hit workload and passes trivially. A read-heavy question **must** inject a read-heavy load so the cache is actually stressed. |
| **Global run config** (seed, simulationDuration, warmupDuration)              | **question**          | else a student shortens the run to dodge steady-state, or **cherry-picks a lucky seed** by re-running until one passes. Fixed, question-authored seed(s) + `maxTestRuns` (exam) kill seed-farming.                          |
| **Fault injection** (chaos/HA scenarios)                                      | **question**          | Exam-mode HA questions inject the failures; the student can't opt out of the scenario they're graded on.                                                                                                                    |
| **Node design config** (queue capacity, workers, processing dist/timeout)     | **student** (bounded) | the student *should* design node sizing - but each unit is **priced (cost)** and **bounded to realistic ranges/defaults**, so `workers=10000` is caught by `budget` + faithful sim, not by being forbidden.                 |
| **Edge design config** (bandwidth, latency, maxConcurrentRequests, errorRate) | **student** (bounded) | same: real ceilings + edge cost, so `bandwidth=∞`/`errorRate=0` is caught by `budget` + faithful sim (§6).                                                                                                                  |

**This split is already how our engine works** - `QuestionSuiteCase` carries
`global` / `workload` / `faults` overrides that `gradeAttempt` injects via
`mergeTopologyWithOverrides(studentTopology, …)`. So the graded scenario is
authored, not student-supplied. The work remaining is on the *bounded student
config* side: realistic ceilings + cost (§4, §6).

### 7.2 The gaming matrix

| Gaming vector            | Exploit                                                           | Caught by                                                                                                        |
| ------------------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Node kitchen-sink        | pass all `requires_X`                                             | `budget` · `forbidUnjustified` · `max_component_count` · sim ignores unwired nodes                               |
| Edge kitchen-sink        | pass all connectivity                                             | `budget` (edge cost) · `direction` (specific paths)                                                              |
| Node-config tuning       | crank capacity/workers/timeout so one box absorbs impossible load | node cost (`budget`) · realistic ceilings/defaults · `storageFit` is config-independent                          |
| Edge-config tuning       | `bandwidth=∞`, `errorRate=0`, `latency=0`                         | edge cost · faithful edge-property bounds (§6)                                                                   |
| **Workload tampering**   | set a trivial/benign source workload                              | **question injects the workload**, overriding the student's (§7.1)                                               |
| **Seed / run tampering** | shorten run or farm seeds until one passes                        | **question fixes seed + duration**; `maxTestRuns` caps attempts (§7.1)                                           |
| Keyword-stuffing         | pass keyword match                                                | graph-consistent `justification` (§5)                                                                            |
| Wrong-but-passes-sim     | under-loaded scenario                                             | sim workload **derived from the scale numbers** so load genuinely stresses the design; independent S-axis checks |
| Copy a reference diagram | memorize the 4 worked systems                                     | **randomize scale numbers per attempt** + novel prompts                                                          |
| Decorative/disconnected  | node/edge present but unwired/off-path                            | `direction`/connectivity · unwired elements cost but give no metric benefit                                      |

### 7.3 The two missing levers + load faithfulness

Two levers make all of the above robust: a **graph-consistent justification**
(§5) - now **implemented** (`justification.ts`; UI answer capture is the only
remaining piece, Phase 2b) - and a **cost/budget model** (§4, specced in
`cost-calculation-and-budgeting.md`) - **still to build** (the `budget` axis).
This analysis reframes both as **anti-gaming infrastructure**, not just features.
(The scale-fit semantic checks that back several rows above - `guardedPath`,
`storageFit`, `fanout`, `placement` - are now implemented too; see §4.1.)

**Load faithfulness.** For metric-tuning to be un-gameable, a single node/edge
must **realistically break at its limit** - a single SQL node must not absorb
200K writes/s, an edge's bandwidth must have a real ceiling and cost.
Cross-reference `no-point-sampled-scalars` (reported scalars must be
time-weighted integrals) - a lenient/averaged metric is itself a gaming surface.

---

## 8. Reverse-engineering to the simulator - gap analysis

| Capability                                                                                         | Status     | Note                                                                                                            |
| -------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------- |
| Question schema (prompt/scaffold/suite/rubric/constraints)                                         | ✅ have     | `QuestionPackage`                                                                                               |
| Lab vs Exam mode                                                                                   | ✅ have     | `EnvironmentProfile` PRACTICE/ASSIGNMENT; hints + timer are the only gaps                                       |
| Simulation-metric checks                                                                           | ✅ have     | `rubric.checks`                                                                                                 |
| Structural presence/path checks                                                                    | ✅ have     | `structuralRules`                                                                                               |
| Hard-fail vs partial + weighted points                                                             | ⚠️ extend   | need explicit `hardFail` overrides-all + point allocation                                                       |
| **Justification field (graph-consistent)**                                                         | ❌ new      | §5 - biggest gap; faculty explicitly demand it                                                                  |
| **`storageFit` (scale→DB-type)**                                                                   | ❌ new      | Lab 4, Exam 1                                                                                                   |
| **`fanout` (node-type-aware)**                                                                     | ❌ new      | Lab 3                                                                                                           |
| **`placement` / `direction`**                                                                      | ⚠️ extend   | extend `requires_path`; add forbidden-position/edge + directed-all-traffic                                      |
| **Cost / budget model**                                                                            | ⚠️ specced  | `cost-calculation-and-budgeting.md` exists; wire as `budget` check                                              |
| **Question-authored test conditions** (workload/seed/duration/faults injected, overriding student) | ✅ have     | `QuestionSuiteCase` overrides via `mergeTopologyWithOverrides` - the anti-gaming test/architecture split (§7.1) |
| **Scale numbers → sim workload**                                                                   | ⚠️ plumbing | derive the injected workload from `scale` so numbers force architecture                                         |
| **Bounded student config** (node/edge config ceilings + cost)                                      | ⚠️ extend   | realistic defaults + pricing so config-tuning is caught, not forbidden (§6, §7.1)                               |
| **Faithful node/edge ceilings**                                                                    | ⚠️ verify   | see load-faithfulness (§7.3)                                                                                    |
| Hints (cost points, exam) + timer                                                                  | ❌ new      | Lab/Exam detail                                                                                                 |
| Scale randomization per attempt                                                                    | ❌ new      | anti-memorization (§7)                                                                                          |

---

## 9. Phased plan

1. ✅ **Lock the schema** - `gradingCriteria.ts` adds the semantic-criterion
   union, `JustifyPrompt`, `Budget`, `AccessPattern`, `WorkloadCategory` as typed
   contracts + Zod; `QuestionPackage` gains optional `semanticCriteria` / `justify`
   / `budget` / `workloadCategory` (non-breaking).
2. ✅ **Graph-consistent justification** (§5) - `justification.ts` grades each
   prompt deterministically: the **graph-consistency gate** (the answer must
   reference the component actually in the student's graph, else fail - this is
   what defeats keyword-stuffing), plus number-citation and tradeoff for graded
   credit. Pure/injectable (`JustificationContext`), fully unit-tested. *Remaining
   for this axis:* store the student's answers on the attempt/submission and wire
   the text fields in the UI (Phase 2b).
3. ✅ **Scale-fit semantic checks** - `semanticCriteria.ts` implements all five
   evaluators (`guardedPath`, `placement`, `fanout`, `storageFit`,
   `forbidUnjustified`) as pure graph computations, aggregates points
   (full/partial/zero) with `hardFail` support, and is wired into `gradeAttempt`
   (surfaced as `topology.semantic.*` host-contract rows). See §4.1 for the
   algorithms. *Remaining for this axis:* thread graded justification results
   into `forbidUnjustified` (depends on Phase 2b answer capture); optionally zero
   the total rubric score on a semantic `hardFail`.
4. **Cost / budget model** - wire `cost-calculation-and-budgeting` as the
   `budget` axis (anti-kitchen-sink for nodes and edges).
5. **Scale → simulation-workload derivation + ceiling faithfulness** - make the
   numbers force the architecture; audit node/edge property bounds.
6. **Author the 8 questions** (5 labs + 3 exams) as real `QuestionPackage`s to
   validate the schema end-to-end, plus a few **fetched-from-the-web** canonical
   questions (Ticketmaster / payment / notification) to stress the generalization.
7. **Exam-mode details** - hints-cost-points, timer, scale randomization.

---

## 10. Worked encodings (proof the schema holds)

### Lab 4 - Read-heavy vs write-heavy DB (storage)

```
meta:   { mode: lab, difficulty: intermediate, totalPoints: 100 }
prompt.scale: { writesPerSec: 200000, accessPattern: 'time-series',
                joins: false, consistency: 'none-stated' }
rubric:
  - storageFit  points 60  hardFail:true
      expect: wide-column (partitionKey=sensor_id, clustering=timestamp)
      antiPattern: relational  // SQL at 200K w/s → hard fail unless justified
  - justification points 40
      decision: "Why this DB type?"  boundTo:{ node:'store' }
      requires: { choice, number:200000, tradeoff }
budget: { unit: cost, cap: <IoT-store budget> }   // KV/relational padding costs
```

Gaming caught: SQL-and-tune-the-sim → `storageFit` hard-fails independent of sim;
kitchen-sink DBs → `budget`; correct-prose-wrong-graph → `justification`
graph-consistency.

### Exam 2 - Distributed rate limiter

```
meta:   { mode: exam, difficulty: advanced, totalPoints: 70, timeLimitSec: 1800 }
rubric:
  - structural  points 30  hardFail:true
      expect: RateLimiter node connected to a SHARED Cache (Redis)
      forbid: per-instance in-memory counters (RateLimiter with no shared-store edge)
  - direction   points 0   // guard: RateLimiter → shared Cache edge must exist
  - justification points 20   decision:"Which algorithm and why?"  // token bucket / sliding window
  - justification points 20   decision:"Why cache not DB for counters?"  requires:{number:5 /*ms*/, tradeoff}
```

Gaming caught: the faculty's exact hard-fail - *"detect graphs where the Rate
Limiter has no connection to a shared Cache/DB node"* - is the `structural` +
`direction` guard; "vague we-check-a-counter" → `justification` requiring the
named algorithm.

---

## 11. Web-question validation - solving 3 novel questions

To stress-test the generalization beyond the 8 authored questions, three
canonical questions were fetched and encoded. They were chosen to hit dimensions
*absent* from URL/Chat/Feed/Docs: **correctness-under-contention**, **exactly-once**,
and **batch/throughput**.

| Question           | New dimension it stresses           | Core hard problem                                                                  |
| ------------------ | ----------------------------------- | ---------------------------------------------------------------------------------- |
| **Ticketmaster**   | correctness-under-contention        | no double-booking (distributed lock + TTL + OCC); virtual waiting queue            |
| **Web Crawler**    | batch / throughput + async pipeline | URL/content dedup; per-domain politeness; frontier→fetch→process pipeline with DLQ |
| **Payment System** | exactly-once + auditability         | idempotency keys; immutable double-entry ledger; reconciliation                    |

**Encodings held** in the §2 schema. But solving them surfaced **five concrete
refinements** that Phase 1 must fold in:

1. **The "guarded path" is one generalized check, not four.** Exam-2
   rate-limiter→shared-cache, Ticketmaster booking→lock-store, Payment
   write→idempotency-key-store, Crawler enqueue→dedup-index are **the same check**:
   *"all traffic of type T must traverse guard node G (in the correct
   direction)."* Promote §6's "all traffic must traverse the required path" into a
   first-class `guardedPath` check kind (a strengthened `direction`). This is the
   most reused anti-gaming primitive across real questions.
2. **The simulation axis grades *performance* invariants, not *correctness*
   invariants.** Latency/throughput/utilization are simulatable; *mutual
   exclusion / exactly-once / immutability / no-double-book* are **not** (our
   metrics engine doesn't model contention or dedup). Therefore correctness-heavy
   questions are graded on **topology (`guardedPath` + `structural`) + `justification`** -
   which is exactly the ≥3-axis anti-gaming model doing its job when the sim can't
   help. This boundary must be explicit so authors don't write un-gradeable
   simulation checks for correctness.
3. **`storageFit` needs an access-pattern enum, not just "SQL vs NoSQL".** The
   real spread is: point-lookup (URL→KV), time-series (Lab 4→wide-column),
   **append-only-immutable-ledger** (Payment), transactional-relational
   (Ticketmaster/payment path→SQL), search-index (Ticketmaster→Elasticsearch).
   The check maps `(scale, accessPattern) → acceptable node types + anti-patterns`.
4. **Async-pipeline / DLQ / dedup / admission-queue are structural-pattern
   checks.** Many NFRs (fault-tolerance, politeness, no-lost-progress) are graded
   by *topology shape*, not simulation - reinforcing #2. A `placement`/`direction`
   *ordered-pipeline* variant covers frontier→fetch→process→extract.
5. **A fourth workload category exists.** The prep-doc cheat sheet names
   read-/write-/connection-/correctness-heavy. The crawler is **batch /
   throughput-heavy** (10B pages / 5 days = ~23K pages/s aggregate, latency
   irrelevant). Add it to the workload taxonomy so the "the workload is [X]"
   framing and the derived sim scenario cover batch systems.

**Net:** the schema is sound; Phase 1 should add the `guardedPath` check kind, the
`storageFit` access-pattern enum, an ordered-pipeline `placement` variant, the
performance-vs-correctness axis note, and the batch workload category.

Sources:
[Ticketmaster (HelloInterview)](https://www.hellointerview.com/learn/system-design/problem-breakdowns/ticketmaster),
[Web Crawler (HelloInterview)](https://www.hellointerview.com/learn/system-design/problem-breakdowns/web-crawler),
[Payment System design (survey)](https://prachub.com/concepts/payment-systems-ledgers-idempotency-and-reconciliation).

---

## 12. Open items

- **Justification grading = structured + graph-consistent** (decided). Revisit an
  optional LLM *assist* only for author-time hint generation, never for scoring.
- **Fetch-and-solve web questions** (Ticketmaster, payment, notification) to
  validate the schema - pending (Phase 6).
- **Scale randomization** ranges per question - authoring concern; define bounds
  that keep the *correct architecture* invariant while moving thresholds.

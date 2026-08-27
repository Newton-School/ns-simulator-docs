# Multiple Valid Solutions Grading

> **Purpose.** Define how the simulator should handle problems where more than
> one architecture is correct, and make the distinction explicit between:
>
> 1. **multiple valid variants of the same solution family**, and
> 2. **multiple different architecture families** that should both pass.
>
> **Source of truth today.**
>
> - `src/engine/analysis/question.ts`
> - `src/engine/analysis/semanticCriteria.ts`
> - `src/engine/analysis/structural.ts`
> - `src/engine/analysis/rubric.ts`
> - `src/engine/analysis/evaluationContract.ts`
>
> **Related docs.**
>
> - `evaluation-authoring-reference-manual.md`
> - `question-grading-model-and-anti-gaming.md`
> - `rubric-engine-and-question-platform-architecture.md`

---

## 1. Executive Summary

The simulator already grades against an **authored solution space**, not against
one frozen reference topology.

That means:

- the live grader does **not** compare a student graph to the reference graph
- if two different student topologies satisfy the authored checks, both pass
- the reference topology is only an **author validation artifact**

But the current system only handles this well when the acceptable answers are
**small variants inside one architecture family**.

It does **not** yet handle **multiple different architecture families**
cleanly as a first-class grading feature.

Examples:

- **Already reasonably supported today**
  - URL shortener using `kv-store`
  - URL shortener using `nosql-db`
  - both can pass one `storageFit.accept` list

- **Awkward today**
  - News feed where either `fanout-on-write` or `hybrid celebrity fallback`
    should pass
  - Flash sale where either `distributed-lock` or `serialized queue + worker`
    should pass
  - notification delivery where either a generic `message-broker` or a
    provider-style fanout primitive should pass

The missing abstraction is a first-class **Solution Family** model:

- common gates that every valid answer must satisfy
- family-specific gates that only apply to one architecture family
- final pass if **any one family passes**

---

## 2. What The Simulator Does Today

### 2.1 It grades a constraint set, not a reference graph

Today the evaluator works like this:

1. run `structuralRules`
2. if structural fails, short-circuit and skip simulation
3. run `justify` if present
4. run `semanticCriteria`
5. run the suite and grade `rubric.checks`
6. collapse everything into a host-facing boolean contract

The important property is that the student is graded against:

- structural requirements
- semantic requirements
- runtime requirements

and **not** against exact graph equality.

So if two topologies both satisfy the authored rules, the engine accepts both.

### 2.2 Reference topology is author-only, not runtime grading input

The reference topology exists so the author can prove:

- one intended good topology passes
- one intended bad topology fails on the intended axis

That is the Dual-Topology Rule in `evaluation-authoring-reference-manual.md`.
It is an authoring validation loop, not an exact-match runtime scoring model.

### 2.3 Current support for "multiple answers" already exists in narrow form

The current DSL already supports some bounded alternative answers.

#### A. Broad structural families

A question can say:

- must contain a durable store
- must not connect client directly to DB
- must contain an app processing tier

without requiring one exact layout.

#### B. Semantic accept / partial / anti-pattern lists

`storageFit` already supports:

- `accept`
- `partial`
- `antiPattern`

So one question can allow multiple store types.

Example:

```json
{
  "id": "store-fits-point-lookup",
  "kind": "storageFit",
  "accessPattern": "point-lookup",
  "accept": ["kv-store", "nosql-db"],
  "partial": ["in-memory-cache"],
  "antiPattern": ["relational-db"],
  "points": 3
}
```

This already says:

- `kv-store` is valid
- `nosql-db` is valid
- `in-memory-cache` alone is only partially acceptable
- `relational-db` is wrong

#### C. Rubric scoring can be fractional

The rubric supports weighted checks plus `passThreshold`.

So authors can say:

- not every rubric point must be required to pass
- runtime behavior can be judged by score fraction

Example:

```json
{
  "rubric": {
    "id": "feed-rubric",
    "passThreshold": 0.8,
    "checks": [
      {
        "id": "p99",
        "metric": "summary.latency.p99",
        "op": "<",
        "value": 200,
        "points": 3
      },
      {
        "id": "errors",
        "metric": "summary.errorRate",
        "op": "<",
        "value": 0.01,
        "points": 2
      }
    ]
  }
}
```

---

## 3. The Current Limitation

The current system breaks down when the question should accept **two different
architecture families**, not just two component choices.

### 3.1 It can express "A or B component", but not "A-family or B-family"

Current DSL strength:

- one store may be any of several acceptable types
- one path may be shaped broadly

Current DSL weakness:

- one complete solution may be a **fanout-on-write design**
- another complete solution may be a **fanout-on-read + celebrity fallback design**
- both are valid, but they require different semantic expectations

Today the author must pick one of these bad options:

1. author the question narrowly around one family
2. over-broaden the checks until both pass, but lose discrimination
3. author one family as `accept` and treat the other as `partial`, even though
   it may actually be fully valid

### 3.2 Partial semantic credit does not behave like a real alternate pass today

Internally, semantic criteria support:

- `passed`
- `partial`
- `failed`

and partial gets half credit:

```ts
if (outcome === 'partial') return Math.floor(points / 2)
```

But the host-facing contract collapses semantic rows to:

- `passed` if outcome is exactly `passed`
- `failed` for both `partial` and `failed`

So a design can be:

- semantically defensible enough to earn points
- but still shown as a failed row in the final boolean contract

### 3.3 `passThreshold` only applies to rubric score, not the whole design

Today:

- rubric score can pass fractionally
- semantic score is separate
- structural is a hard gate
- budget is separate
- host `allPassed` requires every flattened row to be green

So the system has:

- a **rich internal score**
- a **strict final boolean**

This is fine for "one intended family, many small variants"
but awkward for "two different architecture families should both count as
correct."

---

## 4. The Design Goal

We need the simulator to support:

> **Pass if the student built any one valid architecture family that satisfies
> the common problem requirements.**

That means the simulator should be able to express:

- common requirements every valid answer must satisfy
- family-specific requirements for each accepted family
- a final grade that passes if **at least one family passes**

without:

- forcing exact graph equality
- pretending all families are the same shape
- flattening full alternatives into "partial credit"

### 4.1 Important distinction: three different "family" ideas

| Term | Meaning | Example | Does it need `solutionFamilies`? |
|------|---------|---------|----------------------------------|
| **Component variant** | Same end-to-end architecture, but one primitive changes | URL shortener on `kv-store` vs `nosql-db` | **No**. Use existing `accept` / `partial` / `antiPattern`. |
| **Solution family** | Different end-to-end architecture that should still count as fully correct | ticketing with `distributed-lock` vs serialized `queue + worker` | **Yes**. This is the new feature proposed in this doc. |
| **Problem taxonomy family** | The bottleneck domain the lesson belongs to | `compute`, `storage`, `correctness`, `resilience` | **Indirectly**. This helps authors decide which solution families are plausible. |

### 4.2 Exhaustive simulator family catalog for authoring

This table is **exhaustive for the simulator taxonomy today**. It is not a claim
that all distributed-systems architectures fit only these rows; it is the full
authoring catalog the simulator currently reasons about.

| Master family | Bottleneck / lesson family | Canonical full-credit solution families authors may accept | Usually modeled as | Current simulator support |
|---------------|----------------------------|-------------------------------------------------------------|--------------------|---------------------------|
| **Compute & Capacity** | Read-heavy saturation | cache-aside read path; read-through cache; pre-materialized read model | single family, sometimes multi-family for feed-style problems | ✅ physics-backed |
| **Compute & Capacity** | Synchronous blocking | queue + worker; broker + batch worker; async job/result pattern | single family with variants | ✅ physics-backed |
| **Compute & Capacity** | CPU / thread contention | scale-out replicas; load balancer + replicas; work partitioning | single family today | 🟡 mostly structural |
| **Storage & State** | Write-throughput saturation | time-series store; write-optimized NoSQL store; buffered ingest + durable sink | single family with store variants | 🟡 semantic + rubric |
| **Storage & State** | Broadcast / fan-out exhaustion | pub-sub fanout; fanout-on-write; hybrid celebrity fallback | **true multi-family candidate** | 🟡 structural today |
| **Storage & State** | Scan vs lookup penalty | search index; geo index; keyed lookup store | single family with store/index variants | 🟡 semantic today |
| **Storage & State** | Storage tiering & cost | object-storage + metadata DB; hot/cold tier split | true multi-family candidate later | ❌ deferred |
| **Network & Edge** | Connection-pool / port exhaustion | connection multiplexer; scale-out NAT/gateway tier | true multi-family candidate later | ❌ deferred |
| **Network & Edge** | Bandwidth / pipe saturation | CDN; edge cache; compression/transcoding edge | true multi-family candidate later | ❌ deferred |
| **Network & Edge** | Geo-latency / routing | multi-region routing; geo-sharding; read-local replicas | true multi-family candidate later | ❌ deferred |
| **Resilience & Chaos** | Cascading failure / retry storms | circuit breaker + deadlines; bulkhead + queue isolation; throttling / load-shedding | true multi-family candidate later | 🟡 partial |
| **Resilience & Chaos** | Data-center failover | active-passive failover; active-active regional routing | true multi-family candidate later | 🟡 partial |
| **Resilience & Chaos** | Shared-state rate limiting | centralized counter store; sharded shared counter store | usually single family with algorithm variants | 🟡 topology + justification today |
| **Correctness** | Contention / double-booking | distributed lock; serialized queue + worker; OCC-style guarded write path | **true multi-family candidate** | 🟡 topology + justification |
| **Correctness** | Exactly-once / idempotency | idempotency guard + immutable ledger; idempotent write gate + dedup store | single family with variants today | 🟡 topology + justification |
| **Meta-constraint** | Cost optimization | minimal-cache optimization; async decoupling instead of brute-force scale; hot/cold tier split | usually cross-family comparison, not one family | ❌ deferred |

### 4.3 Which rows are most likely to need true multi-family grading

| Bottleneck / lesson family | Why one family is often not enough | Typical accepted family set |
|----------------------------|------------------------------------|-----------------------------|
| Broadcast / fan-out exhaustion | Read/write tradeoff changes the shape of the whole architecture | `fanout-on-write` vs `hybrid-celebrity-fallback` |
| Contention / double-booking | The correctness mechanism can be either explicit locking or serialized processing | `distributed-lock` vs `queue + worker` |
| Cascading failure / retry storms | Protection can be centered on fast rejection, isolation, or smarter retries | `circuit-breaker + deadline` vs `load-shedding + bulkhead` |
| Geo-latency / routing | The global shape differs between route-to-region and replicate-read-local designs | `geo-routing` vs `read-local replica` |
| Storage tiering & cost | The accepted answer may hinge on whether the primary move is retrieval tiering or workload reshaping | `hot/cold tier split` vs `async archive pipeline` |

---

## 5. Proposal: Solution Family Evaluation

### 5.1 New concept

Add a first-class `solutionFamilies` layer to the question package.

The question becomes:

- **common gates**
- plus **N accepted solution families**
- final result = any family passes

### 5.2 Proposed additive schema

This should be additive and backwards-compatible.

Existing questions without `solutionFamilies` continue working exactly as they
do today.

```ts
interface SolutionFamily {
  id: string
  title: string
  description?: string

  structuralRules?: StructuralRule[]
  semanticCriteria?: SemanticCriterion[]
  budget?: Budget

  rubric?: {
    checks?: RubricCheck[]
    passThreshold?: number
  }

  passPolicy?: {
    semanticMode?: 'all-green' | 'score-threshold'
    semanticThreshold?: number
    requireBudget?: boolean
  }
}

interface QuestionPackage {
  // existing fields
  structuralRules?: StructuralRule[]     // common rules
  semanticCriteria?: SemanticCriterion[] // common rules
  budget?: Budget                        // common budget
  rubric: Rubric                         // common rubric

  solutionFamilies?: SolutionFamily[]
}
```

### 5.2.1 Proposed field table: question-level common layer

| Field | Scope | Required | Meaning | Authoring guidance |
|-------|-------|----------|---------|--------------------|
| `structuralRules` | common | no | Rules every valid answer must satisfy | Put only question-invariant structure here. |
| `semanticCriteria` | common | no | Semantics every valid answer must satisfy | Use for rules that should hold across all accepted families. |
| `budget` | common | no | Budget every valid answer must satisfy | Use only if the budget is truly family-agnostic. |
| `rubric.checks` | common | yes, if question already has a rubric | Shared runtime or score checks | Put FR/NFR targets here when all families share them. |
| `rubric.passThreshold` | common | no | Shared rubric threshold | Keep at question level unless one family intentionally has a different bar. |
| `solutionFamilies` | question container | no | The list of accepted alternate pass paths | Add only when two or more families are truly full-credit answers. |

### 5.2.2 Proposed field table: per-family layer

| Field | Required | Meaning | When to use it |
|-------|----------|---------|----------------|
| `id` | yes | Stable machine key for the family | Required for grading, diagnostics, and analytics. |
| `title` | yes | Human-readable name | What the student sees in pass/fail explanations. |
| `description` | no | Short explanation of the family | Helpful for authors and future UI hints. |
| `structuralRules` | no | Structure required only for that family | Use when the topology shape differs across families. |
| `semanticCriteria` | no | Semantics required only for that family | Use when each family needs different meaning checks. |
| `budget` | no | Family-specific budget override or add-on | Use only if cost expectations differ by family. |
| `rubric.checks` | no | Extra runtime checks for that family | Use when one family needs a distinct observable. |
| `rubric.passThreshold` | no | Family-specific runtime threshold | Use sparingly; only if one family is intentionally graded with a different bar. |
| `passPolicy` | no | How this family converts raw checks into pass/fail | Use when `all-green` is too strict for that family. |

### 5.2.3 Proposed field table: `passPolicy`

| Field | Allowed values | Meaning | Recommended default |
|-------|----------------|---------|---------------------|
| `semanticMode` | `all-green`, `score-threshold` | Whether semantic pass is strict-per-row or score-based | `all-green` |
| `semanticThreshold` | `0..1` or question-defined normalized score | Minimum semantic score if `score-threshold` is used | unset unless needed |
| `requireBudget` | `true`, `false` | Whether family budget must pass to count as a passing family | `true` when a budget is authored |

### 5.2.4 Proposed scope decision table

| Requirement shape | Put it at common layer | Put it inside a family | Example |
|-------------------|------------------------|------------------------|---------|
| Every correct answer must satisfy it | ✅ | no | feed p99 under 200 ms |
| Only one architecture path needs it | no | ✅ | must traverse `distributed-lock` |
| The metric target is shared, but the mechanism differs | ✅ target, family-specific mechanism | ✅ | all families must hit p99, but one uses cache and another uses fanout |
| The cost bar differs by accepted family | maybe | ✅ | one family allowed higher write cost because it buys stronger correctness |
| The rule is really just a primitive substitution | no new family | no new family | `kv-store` or `nosql-db` for point lookup |

### 5.3 Semantic meaning of the schema

Question-level fields become **common constraints**:

- common `structuralRules`
- common `semanticCriteria`
- common `rubric`
- common `budget`

Each family adds **family-specific constraints**.

Final pass rule:

- common structural must pass
- then evaluate every family
- if **any family** passes, the submission passes

### 5.3.1 What belongs in common rules vs family rules

| Question type | Common rules should contain | Family rules should contain |
|---------------|-----------------------------|-----------------------------|
| Single SLO, multiple mechanism choices | SLOs, invariants, source count, hard forbidden anti-patterns | family-specific path requirements and semantic fit checks |
| Correctness question with two valid mechanisms | shared invariant and downstream system-of-record rules | lock-path rules for lock family; serialization-path rules for queue family |
| Feed / fanout question | shared latency target, invariant count, workload model | write-materialization rules for fanout family; dynamic merge rules for hybrid family |
| Cost-sensitive question | shared budget cap only if universal | family-specific budget and extra cost checks if not universal |

### 5.4 Evaluation algorithm

#### Step 1. Common structural gate

Run question-level `structuralRules`.

- if they fail, stop immediately
- no family can pass if the base topology is structurally invalid

#### Step 2. Shared suite execution

Run the simulation suite **once** against the student topology.

This is important:

- solution families are grading interpretations of one student topology
- they do not require re-running the suite if the workload is the same

#### Step 3. Evaluate each family independently

For each family:

- run family structural rules
- run family semantic criteria
- run family budget if present
- run rubric using:
  - common rubric checks
  - plus any family-specific rubric checks

#### Step 4. Determine family status

A family passes if:

- family structural passes
- no hard-fail semantic criterion failed
- semantic pass policy is satisfied
- rubric score meets threshold
- budget passes if required

#### Step 5. Select winning family

If one or more families pass:

- choose a winning family
- default tie-break = highest normalized score

If no family passes:

- pick the closest family for diagnostics
- default tie-break = highest normalized score among failures

#### Step 6. Build host contract

The current host contract should be changed from:

- "every flattened row across everything must be green"

to:

- "all common rows must be green and at least one family must satisfy its pass
  policy"

The host result should also record:

```ts
{
  passed: true,
  selectedSolutionFamilyId: "hybrid-celebrity-fallback"
}
```

### 5.4.1 Evaluation flow as a table

| Step | Scope | Hard gate? | Runs once or per family? | Output |
|------|-------|------------|---------------------------|--------|
| 1. Common structural | question | yes | once | base structural pass/fail |
| 2. Shared suite execution | question | no | once | runtime metrics reused by all families |
| 3. Family structural | family | yes for that family | per family | family structural status |
| 4. Family semantic | family | policy-driven | per family | semantic rows and family semantic score |
| 5. Family rubric | family plus common rubric | threshold-driven | per family using shared suite output | family runtime score |
| 6. Family budget | family or common | policy-driven | per family | budget pass/fail |
| 7. Family selection | cross-family | n/a | once after all family results exist | selected passing family or closest failing family |
| 8. Host contract build | question | final | once | one pass/fail contract for the host and UI |

### 5.4.2 Family selection and tie-break policy table

| Situation | Default behavior | Why |
|-----------|------------------|-----|
| Exactly one family passes | select that family | unambiguous |
| More than one family passes | choose highest normalized score | deterministic and explainable |
| No family passes | choose closest family by normalized score for diagnostics | best failure explanation |
| Scores tie | stable sort by authored family order, then `id` | deterministic output for analytics and UI |

### 5.4.3 Host contract / UI outcome table

| Situation | `passed` | `selectedSolutionFamilyId` | `closestSolutionFamilyId` | UI implication |
|-----------|----------|----------------------------|---------------------------|----------------|
| Common structural failed | `false` | unset | unset | show base topology failure before family detail |
| Family A passed, others failed | `true` | `family-a` | optional | losing families must not poison final pass |
| Family A and B both passed | `true` | winning family by tie-break | optional | show one selected winner, optionally note other passing families |
| No family passed | `false` | unset | nearest failing family | show the most relevant failure explanation |

---

## 6. What This Solves

### 6.1 It keeps the current anti-gaming model

We still keep:

- structural gates
- semantic meaning checks
- runtime checks
- hard fails
- budget constraints

So this does **not** weaken grading.

It only adds a better way to express:

- more than one correct architectural family

### 6.2 It avoids fake partial-credit semantics

Right now authors may be tempted to use:

- `partial`

to mean:

- "this other architecture family is also okay"

That is not what `partial` should mean.

`partial` should mean:

- defensible but weaker
- incomplete optimization
- not wrong enough to hard-fail

It should **not** be the stand-in for:

- fully valid alternative architecture family

### 6.3 It makes results explainable

Instead of:

- "failed cache-placement"

the student can see:

- "passed via family `hybrid-celebrity-fallback`"
- or "closest family was `fanout-on-write`, but celebrity fallback semantic rule failed"

---

## 7. Worked Examples

## 7.1 Example A - URL Shortener

### Question

Design a URL shortener.

### Is this a true multi-family problem?

Usually **no**.

This is mostly a **single family with several acceptable component choices**.

### Good current authoring

One `storageFit` criterion can already allow both:

- `kv-store`
- `nosql-db`

Example:

```json
{
  "semanticCriteria": [
    {
      "id": "store-fits-point-lookup",
      "kind": "storageFit",
      "accessPattern": "point-lookup",
      "accept": ["kv-store", "nosql-db"],
      "partial": ["in-memory-cache"],
      "antiPattern": ["relational-db"],
      "points": 3,
      "hardFail": true
    }
  ]
}
```

### Why this does not need solution families

Because the accepted answers are still one architectural idea:

- direct point lookup
- cache in front if needed
- durable write path

The variation is only the backing primitive, not the whole family.

---

## 7.2 Example B - News Feed

### Question

Design a social feed under normal load plus celebrity spikes.

### Why this is a true multi-family problem

Two valid answers may exist:

#### Family 1 - Fanout on write

- broker or queue-based precompute path
- timeline materialization
- fast read path

#### Family 2 - Hybrid celebrity fallback

- normal users use fanout-on-write
- celebrity posts bypass the normal precompute path
- read path composes recent celebrity content dynamically

Both can be correct.
They are not just component substitutions.

### Proposed authoring

#### Common rules

- one traffic source
- feed p99 under 200 ms
- no invariant violations

#### Family 1

- must contain a broker
- must fan out to multiple consumers
- write path must reach materialized timelines

#### Family 2

- must contain a cache
- must contain a durable base store
- read path must include a dynamic merge path for celebrity content

### Example shape

```json
{
  "structuralRules": [
    {
      "id": "single-source",
      "kind": "requires_single_source",
      "description": "Exactly one traffic source"
    }
  ],
  "rubric": {
    "id": "feed-common",
    "passThreshold": 1,
    "checks": [
      {
        "id": "p99",
        "description": "Feed p99 under 200 ms",
        "metric": "summary.latency.p99",
        "op": "<",
        "value": 200,
        "points": 3
      },
      {
        "id": "no-invariants",
        "description": "No invariant violations",
        "metric": "invariantViolations.count",
        "op": "==",
        "value": 0,
        "points": 1
      }
    ]
  },
  "solutionFamilies": [
    {
      "id": "fanout-on-write",
      "title": "Fanout on write",
      "semanticCriteria": [
        {
          "id": "true-fanout",
          "kind": "fanout",
          "broker": "message-broker",
          "minConsumers": 2,
          "forbiddenBroker": "queue",
          "points": 4,
          "hardFail": true
        }
      ]
    },
    {
      "id": "hybrid-celebrity-fallback",
      "title": "Hybrid celebrity fallback",
      "semanticCriteria": [
        {
          "id": "cache-before-store",
          "kind": "placement",
          "componentType": "in-memory-cache",
          "between": ["microservice", "nosql-db"],
          "points": 2
        }
      ]
    }
  ]
}
```

### Expected grading behavior

- a correct fanout-on-write design passes family 1
- a correct hybrid design passes family 2
- a synchronous relational-only design fails both

---

## 7.3 Example C - Flash Sale / Seat Hold

### Question

Prevent double-booking under extreme contention.

### Why this is a true multi-family problem

There may be two valid approaches:

#### Family 1 - Lock-based

- distributed lock
- transactional relational store
- direct write path

#### Family 2 - Serialization-based

- queue at the write boundary
- worker processes requests one at a time
- transactional relational store downstream

Both can be valid depending on the lesson framing.

### Why today this is awkward

Current authoring tends to choose only one:

- either require `guardedPath` through a distributed lock
- or require a queue

That makes the other architecture fail even if it is a legitimate answer.

### Family-based authoring

#### Common rules

- payment or booking must hit a transactional relational store
- no invariant violations
- error rate target under load

#### Family 1

- guarded path through `distributed-lock`

#### Family 2

- requires queue + worker
- ordered pipeline: ingress -> queue -> worker -> relational-db

### Result

Both families remain strongly constrained.
The simulator allows two real solutions without opening the door to cargo-cult
answers.

---

## 8. Implementation Plan

## Phase 1 - Typed contracts

Add the schema only.

Files:

- `src/engine/analysis/question.ts`
- possibly a dedicated `src/engine/analysis/solutionFamilies.ts`

Tasks:

- add `solutionFamilies` types
- parse and validate them
- keep backwards compatibility when the field is absent

## Phase 2 - Family evaluator

Add an evaluator that:

- consumes common structural result
- consumes shared suite batch
- evaluates each family independently
- selects winning family

Suggested output type:

```ts
interface SolutionFamilyEvaluation {
  id: string
  title: string
  structuralPassed: boolean
  semantic?: SemanticEvaluation
  budget?: BudgetEvaluation
  graded: GradedEvaluationBatch
  passed: boolean
  normalizedScore: number
}
```

## Phase 3 - Attempt grade integration

Extend `AttemptGrade` with:

```ts
interface AttemptGrade {
  structural: StructuralEvaluation
  semantic?: SemanticEvaluation      // existing common semantic
  graded: GradedEvaluationBatch      // existing common rubric path
  solutionFamilies?: SolutionFamilyEvaluation[]
  selectedSolutionFamilyId?: string
  contract: HostContract
}
```

Important design decision:

- when families exist, the **selected family** drives final pass/fail
- non-winning family failures must not poison `allPassed`

## Phase 4 - Host contract and UI

Change:

- `toHostContract()`
- `buildQuestionEvaluationContract()`
- question results UI
- Newton playground result mapping

Needed product behavior:

- show selected passing family
- if failed, show nearest family and why
- do not flatten partial or losing-family rows into final hard failure if some
  other family passed

## Phase 5 - Authoring docs and fixtures

Update:

- `evaluation-authoring-reference-manual.md`
- `interview-question-to-django-assignment-translation.md`
- example question fixtures

Add at least:

- one narrow multi-variant example
- one true multi-family example

---

## 9. Design Rules For Authors

When should an author use `solutionFamilies`?

Use it when:

- two answers are genuinely different architecture families
- each family needs different semantic checks
- both families should be full-credit pass outcomes

Do **not** use it when:

- one criterion can already express the accepted alternatives
- the difference is only one store type or one cache type
- the "alternative" is really only partial credit

Use `partial` when:

- the design is defensible but weaker
- it should earn some credit
- it should not be presented as one of the canonical correct families

Use `solutionFamilies` when:

- the design should be a real pass path

### 9.1 Author decision table

| Author situation | Correct tool | Why |
|------------------|--------------|-----|
| Same architecture, different store choice | `storageFit.accept` or similar semantic accept-list | This is a variant, not a new family. |
| Same family, but one answer is weaker | `partial` | The answer deserves credit but should not become a canonical pass path. |
| Two end-to-end architectures are both fully correct | `solutionFamilies` | The simulator must expose two full-credit pass paths. |
| One mechanism is always required no matter what | common `structuralRules` or common `semanticCriteria` | Keep invariant requirements out of family branches. |
| One mechanism is unique to only one accepted answer | family-specific rule | Avoid over-broadening common rules until they become meaningless. |

### 9.2 Recommended initial family shortlist for authors

When authors need to enumerate accepted families, start from this shortlist
instead of inventing ad hoc names:

| Problem area | Recommended family labels |
|--------------|---------------------------|
| Read-heavy serving | `cache-aside`, `read-through-cache`, `materialized-read-model` |
| Async decoupling | `queue-worker`, `broker-batch-worker`, `async-job-result` |
| Feed fanout | `fanout-on-write`, `hybrid-celebrity-fallback` |
| Contention / booking | `distributed-lock`, `serialized-queue-worker`, `occ-guarded-write` |
| Idempotent writes | `idempotency-ledger`, `idempotency-dedup-store` |
| Rate limiting | `shared-counter-store`, `sharded-shared-counter-store` |
| Global routing | `geo-routing`, `read-local-replica`, `active-active-regional` |
| Failover | `active-passive`, `active-active-failover` |

---

## 10. Recommended Initial Scope

The first version should support:

- common structural rules
- family-specific semantic criteria
- family-specific rubric thresholds
- final pass if any family passes

The first version should **not** try to support:

- family-specific suite workloads
- nested AND/OR logic trees
- arbitrary boolean expressions over criteria

That would overcomplicate the first cut.

The initial model should remain:

- simple
- additive
- deterministic
- explainable

---

## 11. Bottom Line

The simulator already supports **one bounded solution family with multiple small
variants**.

It does **not yet** support **multiple different correct architecture families**
as a first-class grading model.

The right next abstraction is:

> **common gates + family-specific gates + pass if any family passes**

That keeps the grading system:

- deterministic
- anti-gameable
- explainable
- and much closer to how real system design questions are actually solved.

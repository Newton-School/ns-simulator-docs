# System Design LeetCode Environment Model

This document defines how the simulator should behave when used as a "LeetCode for system design" product. The goal is not to force one exact topology. The goal is to bound the design space around one architectural lesson at a time, expose only the right abstractions for that lesson, and evaluate a family of valid solutions through simulator behavior.

This spec complements the existing question-platform work in [question-creation-feature-spec.md](./question-creation-feature-spec.md), [rubric-engine-and-question-platform-architecture.md](./rubric-engine-and-question-platform-architecture.md), and [question-platform-ui-changes.md](./question-platform-ui-changes.md). Those documents define the grading contracts and UI seams. This document defines the product model and pedagogy for the problems themselves.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Existing Foundations](#existing-foundations)
3. [Core Design Decision](#core-design-decision)
4. [Mental Model](#mental-model)
5. [Environment Modes](#environment-modes)
6. [Environment Isolation Levers](#environment-isolation-levers)
7. [Constraint Taxonomy](#constraint-taxonomy)
8. [Evaluation Philosophy](#evaluation-philosophy)
9. [Problem Archetypes](#problem-archetypes)
10. [Example: Request-Path Design Family](#example-request-path-design-family)
11. [Authoring Workflow](#authoring-workflow)
12. [Implementation Implications](#implementation-implications)

---

## Problem Statement

The simulator can already execute topologies and grade submissions against a `QuestionPackage`, but that alone does not make a good practice platform.

The open design problem is:

- How do we isolate the learner inside a bounded environment instead of dropping them into the full simulator?
- How do we teach one architectural concept at a time without collapsing into snapshot topology comparison?
- How do we make a problem feel like LeetCode: constrained, repeatable, gradable, and pedagogically sharp?
- How do we support both learning mode and contest mode without changing the underlying question content?

The answer is to treat a problem as a combination of:

- content
- environment
- feedback policy
- evaluation policy

not just a prompt plus a grading rubric.

---

## Existing Foundations

The repo already has the core schema boundary needed for this product model.

| Concern | Current foundation |
|---|---|
| Question content | `QuestionPackage` in `src/engine/analysis/question.ts` |
| Student work state | `AttemptState` in `src/engine/analysis/question.ts` |
| Verdict-driven grading | rubric and grading pipeline in `src/engine/analysis/rubric.ts` and `src/engine/analysis/question.ts` |
| Runtime question UI | `QuestionPanel` and host seam already wired in the renderer |
| Product-level environment model | specified in `rubric-engine-and-question-platform-architecture.md`, not yet fully enforced in runtime |
| Palette allowlist / locked scaffold / curated results | specified in docs, still a follow-up implementation slice |

As of July 28, 2026, the main missing piece is not the concept model. The missing piece is runtime enforcement of the environment lens.

---

## Core Design Decision

The simulator should not treat a system design problem as:

`one prompt -> one exact topology -> one exact expected answer`

It should treat a problem as:

`one architecture lesson + one bounded solution space + one behavioral test suite`

This means:

- the learner should be constrained by the environment, not by hidden nitpicks
- the grading should prefer behavioral correctness and coarse structural validity over exact graph matching
- the question should isolate one concept family at a time
- the same question content should be deployable in `LEARN`, `INTERVIEW`, and `AUTHOR` modes

This is the product move that makes "LeetCode for system design" viable.

---

## Mental Model

The platform should use the separation already implied by the current architecture docs:

- `QuestionPackage` = what the problem is
- `EnvironmentProfile` = how much of the simulator is exposed
- `AttemptState` = the student's current work

| Layer | Responsibility |
|---|---|
| `QuestionPackage` | Prompt, scaffold, constraints, suite, rubric, metadata |
| `EnvironmentProfile` | Palette visibility, editability, feedback timing, results visibility, chrome density |
| `AttemptState` | Current topology, test-run count, autosave state, submission state, grades |

The key product rule is:

Change the environment when changing pedagogy. Do not fork the problem itself unless the content changes.

---

## Environment Modes

The environment mode is a teaching lens, not a different question type.

| Mode | Purpose | Palette | Feedback | Results | Grading |
|---|---|---|---|---|---|
| `LEARN` | Teach one concept with low pressure | tightly curated | live or near-live | curated and explanatory | optional or de-emphasized |
| `INTERVIEW` | Evaluate problem-solving under bounded constraints | curated, less guided | limited | curated, less explanatory | required on submit |
| `AUTHOR` | Preview and validate question behavior | full | full | full | used for author verification |

### `LEARN`

`LEARN` should optimize for concept acquisition.

- Narrow palette.
- Strong abstraction.
- Optional scaffold.
- Friendly curated metrics.
- Explanatory failures.
- Generous dry runs.

### `INTERVIEW`

`INTERVIEW` should optimize for evaluation signal.

- Curated palette, but less hand-holding.
- Hidden grading suite.
- Minimal chrome.
- Limited dry runs.
- Post-submit rubric visibility.

### `AUTHOR`

`AUTHOR` should optimize for question-setter verification.

- Full palette.
- Full result surfaces.
- Full rubric visibility.
- Full scaffold editability.

---

## Environment Isolation Levers

The environment isolates the learner by controlling what the simulator exposes.

| Lever | What it controls | Why it exists |
|---|---|---|
| Palette allowlist | Which component types are available | Limits the active concept space |
| Locked scaffold | Which nodes and edges are fixed | Anchors the lesson when needed |
| Editability | Whether scaffold nodes can be changed or removed | Prevents off-lesson churn |
| Curated results | Which metrics and tabs are visible | Keeps feedback relevant to the lesson |
| Feedback timing | Live checks vs post-submit checks | Tunes learning vs evaluation pressure |
| Run policy | Dry-run availability and limits | Controls trial-and-error behavior |
| Budget limits | Nodes, workers, cost, time | Creates meaningful tradeoffs |
| Structural invariants | Broad shape requirements | Prevents degenerate solutions without snapshot matching |

This is the abstraction boundary. A learner is not "isolated" by hiding the answer. A learner is isolated by seeing only the concepts the question is designed to teach or evaluate.

---

## Constraint Taxonomy

Constraints should be authored in categories, not as one undifferentiated "correctness" bucket.

### 1. Input Constraints

These control what the learner is allowed to build.

Examples:

- allowed node types
- forbidden node types
- maximum node count
- maximum worker count
- whether scaffold nodes can be modified
- whether scaffold nodes can be removed

These correspond directly to the current `QuestionConstraints` shape in `src/engine/analysis/question.ts`.

### 2. Output Constraints

These control what the submission must achieve behaviorally.

Examples:

- throughput threshold
- error-rate ceiling
- latency target
- availability target
- invariant-violation count
- saturation ceiling

These are the natural home of the current verdict-based rubric system.

### 3. Resource and Budget Constraints

These force tradeoffs.

Examples:

- maximum total cost
- maximum total workers
- maximum node count
- limited dry runs
- time-bound contest window

The important product rule is that budgets should create meaningful tension, not arbitrary starvation.

### 4. Structural Invariants

These define the broad solution family without comparing against one frozen topology.

Examples:

- must contain a durable store
- must contain an application processing tier
- must not connect client directly to database
- must not bypass the only asynchronous boundary
- must route all write traffic through a processing tier

These are coarse shape rules, not exact node-position or exact edge-count rules.

### 5. Interaction Constraints

These control how the learner is allowed to explore.

Examples:

- number of test runs
- whether advanced node properties are editable
- whether workload controls are visible
- whether the full results tray is visible

### Anti-goals

The system should explicitly avoid:

- exact snapshot topology comparison
- grading based on node positions or visual layout
- hidden "gotcha" constraints that are not part of the lesson
- exposing two abstractions when the question is not about the difference between them

---

## Evaluation Philosophy

Problems should be evaluated in layers.

### Layer 1: Behavioral correctness

The primary question is:

Does the system behave correctly under the scenarios that matter?

This includes:

- throughput
- latency
- error rate
- availability
- queue pressure
- invariant violations

### Layer 2: Coarse structural validity

The secondary question is:

Is the student solving the intended architectural problem, or routing around it?

This includes broad checks such as:

- has a durable sink
- has an application tier
- no direct client-to-database shortcut
- no forbidden component family

### Layer 3: Resource discipline

The tertiary question is:

Did the student meet the requirements within the intended budget box?

This includes:

- node count
- worker budget
- cost budget
- dry-run or submission policy

The grading engine should prefer:

`behavioral outcome + coarse structural invariants + resource discipline`

not:

`graph equality with one authored answer`

---

## Problem Archetypes

A simulator-based problem set should be built from recurring archetypes, not only from giant interview prompts.

| Archetype | Student action | Best use |
|---|---|---|
| Fix | repair a broken topology | teach diagnosis and missing components |
| Open Build | build from a bounded palette | teach first-principles design |
| Optimize | improve an existing topology | teach bottleneck reasoning |
| Budget Box | satisfy SLOs under tight limits | teach tradeoffs |
| Scaling | survive higher load without redesign | teach scale-out reasoning |
| HA / Chaos | survive faults | teach resilience patterns |
| Tradeoff | solve with one family forbidden | teach architectural substitution |

For a "LeetCode for system design" experience, most early problems should be `Fix`, `Open Build`, or `Budget Box`.

---

## Example: Request-Path Design Family

A recurring beginner/intermediate family is:

`Client -> Router -> Backend Service -> Primary DB`

The important design decision is that this is a solution family, not one exact graph.

### What the environment should teach

- requests need an entry point
- requests should flow through an application tier
- writes should end in durable storage
- the smallest architecture that satisfies the lesson is preferred

### What the environment should not do

- require both `api-gateway` and `load-balancer-l7` unless the question is about that distinction
- require caches, queues, replicas, or other scale patterns when the lesson is only request flow and durable writes
- penalize a student for choosing one valid router abstraction over another when both are acceptable

### Authoring rule for this family

If the lesson is not "gateway vs load balancer", expose one router abstraction only.

| Question focus | Good palette exposure | Bad palette exposure |
|---|---|---|
| Basic request path | one router tile, one app tier, one durable store | both gateway and balancer plus cache and queue |
| Router comparison | gateway and balancer together | every infra primitive in the simulator |
| Durable writes | app tier and durable store, optional router | full read-scaling and event-driven palette |

This is how the product stays pedagogically honest.

---

## Authoring Workflow

Every problem should be authored in this order.

### 1. Choose the lesson

Pick one architectural idea:

- durable writes
- read scaling
- async offload
- retry and timeout tuning
- failover
- budget tradeoffs

If a prompt teaches five ideas at once, it is not a good early-stage problem.

### 2. Define the accepted solution family

Write down the broad shape of acceptable solutions.

Examples:

- must include an application tier and durable store
- may use either a gateway or L7 balancer
- may not use cache in this problem

### 3. Define the environment

Choose:

- palette allowlist
- scaffold style
- editability rules
- curated results
- run policy
- feedback timing

### 4. Define the scenarios

Author:

- one visible dry-run scenario
- one or more hidden grading scenarios

The visible case should help the student reason. The hidden cases should test generalization.

### 5. Define the rubric

Prefer a compact rubric with high-signal checks.

Examples:

- `summary.errorRate < threshold`
- `summary.throughput >= threshold`
- `invariantViolations.count == 0`
- `perNode.maxUtilization < threshold`

Add structural invariants only when they meaningfully protect the lesson.

### 6. Define the editorial

The problem should ship with an explanation that states:

- what concept it was teaching
- why the accepted design family works
- which alternatives were also valid
- what common over-engineering patterns to avoid

---

## Implementation Implications

This document does not replace the existing question-platform specs. It narrows what the runtime must eventually enforce.

| Capability | Status on July 28, 2026 | Why it matters here |
|---|---|---|
| `QuestionPackage` schema | present | defines the problem content |
| `AttemptState` schema | present | defines learner work state |
| verdict-based rubric grading | present | covers outcome checks |
| launch-context / submit host seam | present | supports embedded problem runtime |
| `EnvironmentProfile` runtime enforcement | not fully implemented | needed to isolate the learner |
| palette allowlist filtering | specified, not fully implemented | needed to bound concept space |
| locked scaffold behavior | specified, not fully implemented | needed for guided problems |
| curated student result surfaces | specified, not fully implemented | needed to avoid full-simulator overload |
| structural invariant engine | deferred follow-up | needed to define solution families without snapshot matching |
| cost and budget grading | follows cost model | needed for `Budget Box` style problems |

### Immediate product implication

Before filling implementation gaps one by one, the team should treat this document as the product contract:

- Problems are authored around a concept family.
- Environments isolate the learner by abstraction, not by trickery.
- Grading prefers behavior and broad structural validity over graph equality.
- Learn mode and contest mode are environment variants over the same content model.

### Practical sequencing

The next implementation slices should follow this order:

1. environment profile injection and runtime gating
2. palette allowlist and scaffold locks
3. curated results and feedback timing
4. structural invariant checks
5. resource and budget constraints
6. editorial and progression surfaces

That order matches the product model in this document: isolate first, then evaluate more deeply.

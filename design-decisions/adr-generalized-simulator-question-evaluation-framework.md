# ADR: Generalized Simulator Question Evaluation Framework

> **Status:** Proposed
>
> **Date:** July 28, 2026
>
> **Decision summary:** Generalize the evaluation **framework**, not the exact checks. Every simulator-native question chooses from a shared evaluation vocabulary across three stable layers: behavioral correctness, coarse structural validity, and resource / budget discipline. The framework is universal; the chosen criteria are per-question.

---

## Context

The question-platform work already has the correct high-level split:

- `QuestionPackage` = what the problem is
- `EnvironmentProfile` = how much of the simulator is exposed
- `AttemptState` = the student's work in progress

That is the right runtime mental model. The missing design decision is one layer above it:

How should questions be **evaluated in general**?

There are two tempting but incorrect directions:

1. Treat each question as a one-off with a custom evaluator.
2. Force every question through one universal rubric with the same checks.

Both are wrong.

The first destroys reuse, authoring consistency, and product coherence.
The second destroys pedagogy, because different question types require different kinds of evidence.

The correct abstraction is:

- universal **evaluation framework**
- per-question **selection of criteria**

This matters because the platform goal is not "a simulator with a grading button." The goal is a deterministic practice and evaluation system for simulator-native system design questions.

---

## Decision

Adopt a generalized evaluation framework based on three stable layers:

1. `Behavioral correctness`
2. `Coarse structural validity`
3. `Resource / budget discipline`

Every simulator-native question will choose:

- which layers are active
- which criteria are chosen inside each layer
- which scenarios are run
- which environment profile is used
- what editorial or teaching guidance is attached

The framework is shared. The criteria are authored per question.

---

## Why This, Not a Universal Rubric

The right abstraction is not:

- every question uses `throughput + error rate + read replica + worker budget`

It is:

- every question chooses from a shared evaluation vocabulary

That vocabulary can be reused across question archetypes, but the final evaluation plan remains question-specific.

### Rejected alternative: one fixed rubric for every question

This fails because:

- `Optimize` questions care about improvement over baseline, not only absolute thresholds.
- `Fix` questions often care about a specific repair plus minimal collateral change.
- `HA / Chaos` questions care about behavior under fault scenarios, not only steady-state metrics.
- `Tradeoff` questions often need explicit forbidden components or budget-box checks.
- `Learn-only` exercises may need formative feedback without formal pass/fail grading.

### Rejected alternative: no common structure, only ad hoc evaluators

This fails because:

- question authoring becomes inconsistent
- the UI cannot generalize result surfaces
- the grading engine cannot reuse criterion evaluation primitives
- it becomes impossible to build coherent editorial and progression systems

---

## Scope and Caveat

This framework works for **simulator-native questions**, not for literally any system design question.

A question is simulator-native only if it can be operationalized into:

- scenarios
- constraints
- measurable outcomes
- acceptable structure families

If a question is too open-ended, purely subjective, or cannot be expressed as a bounded set of scenarios and criteria, then it is not yet a good deterministic simulator question.

This is an important product boundary. The simulator should not pretend to grade what it cannot meaningfully operationalize.

---

## The Three Layers

## 1. Behavioral correctness

Behavioral correctness asks:

Does the topology behave acceptably under the scenarios that matter?

Typical evidence:

- throughput
- error rate
- latency
- availability
- invariant violations
- saturation
- queue pressure

This is the layer closest to the simulator engine and existing rubric system.

## 2. Coarse structural validity

Coarse structural validity asks:

Is the student solving the intended architecture problem family, or routing around it?

Typical evidence:

- has required tier
- has async boundary
- forbids client-to-database shortcut
- requires durable write sink
- forbids forbidden component family
- ensures write path and read path are semantically sensible

This layer is deliberately broad. It should constrain the solution family without collapsing into exact topology matching.

## 3. Resource / budget discipline

Resource / budget discipline asks:

Did the student satisfy the question within the intended design box?

Typical evidence:

- node count
- worker count
- cost points
- run budget
- contest interaction limits

This layer is what turns unconstrained "build anything" into meaningful tradeoff problems.

---

## Common Evaluation Vocabulary

Every question should select criteria from a common vocabulary.

### Scenarios

Scenarios define the conditions under which the topology is tested.

Examples:

- normal load
- peak load
- latency spike
- dependency failure
- network partition
- budget-box scenario
- custom authored scenario

### Behavioral checks

Examples:

- throughput threshold
- error-rate ceiling
- latency target
- availability target
- zero invariant violations
- saturation ceiling

### Structural checks

Examples:

- has required tier
- forbids shortcut
- must include async boundary
- must not include forbidden component
- write traffic must pass through compute
- at least one durable primary sink must exist

### Comparative checks

Comparative checks are still part of the general framework, but they compare one result against another rather than against an absolute threshold.

Examples:

- lower p99 than baseline
- lower error rate than baseline
- lower cost than baseline
- fewer saturated nodes than baseline

These usually sit inside the behavioral or budget layers rather than forming a fourth top-level layer.

### Budget checks

Examples:

- node count limit
- worker count limit
- cost-point limit
- dry-run limit

### Environment policy

This is not itself a grading criterion, but it is part of the evaluation system because it determines how the question is exposed.

Examples:

- palette allowlist
- scaffold policy
- visibility policy
- dry-run policy
- feedback timing

### Editorial

Editorial is not grading logic, but it is part of the same authoring contract because it explains what the learner was supposed to discover.

Examples:

- learning objective
- why the accepted design family works
- common wrong turns
- what evidence in the run demonstrates the lesson

---

## Archetype Mapping

Different question archetypes activate different parts of the framework.

| Archetype | Typical active layers | Typical emphasis |
|---|---|---|
| `Open Build` | behavioral + structural + optional budget | design from bounded palette |
| `Fix` | behavioral + structural | required repair, optional minimal-edit discipline |
| `Optimize` | behavioral + budget, often comparative | beat baseline, improve one tradeoff |
| `HA / Chaos` | behavioral + structural | maintain service under fault scenarios |
| `Tradeoff` | behavioral + structural + budget | satisfy constraints with forbidden or expensive options removed |
| `Learn-only exercise` | behavioral + structural for feedback only | concept acquisition without formal grading pressure |

The important pattern is that archetypes choose from the framework; they do not redefine it.

---

## Data Model

The framework needs an authoring-time data model that is more expressive than today's runtime `QuestionPackage`, but still projectable onto the current architecture.

### Core types

```ts
export type QuestionArchetype =
  | 'open-build'
  | 'fix'
  | 'optimize'
  | 'ha-chaos'
  | 'tradeoff'
  | 'learn-only'

export type EvaluationLayer =
  | 'behavioral-correctness'
  | 'coarse-structural-validity'
  | 'resource-budget-discipline'

export type CriterionSeverity = 'gate' | 'scored'

export type CriterionStatus = 'implemented' | 'proposed'
```

### Scenario model

```ts
export type ScenarioKind =
  | 'normal-load'
  | 'peak-load'
  | 'failure-case'
  | 'latency-spike'
  | 'budget-box'
  | 'custom'

export interface EvaluationScenario {
  /** Stable scenario ID used by criteria. */
  id: string

  /** Reusable archetype label. */
  kind: ScenarioKind

  /** Human-readable explanation. */
  description?: string

  /** Whether this scenario is visible to the student. */
  visibleToStudent: boolean

  /** Optional authoring tag like "baseline" or "hidden-grade". */
  tags?: string[]

  /** Whether this scenario acts as the baseline for comparative checks. */
  baseline?: boolean

  /** Partial runtime overrides applied to the tested topology. */
  overrides: {
    global?: Record<string, unknown>
    workload?: Record<string, unknown>
    faults?: unknown[]
  }
}
```

### Criterion model

```ts
export interface CriterionBase {
  /** Stable criterion ID. */
  id: string

  /** Human-readable explanation for authors, UI, and feedback. */
  description: string

  /** Which top-level layer this belongs to. */
  layer: EvaluationLayer

  /** Whether failure blocks the whole question or contributes to a score. */
  severity: CriterionSeverity

  /** Optional score weight for scored criteria. */
  weight?: number

  /** Which scenarios this criterion runs against. */
  scenarios?: string[]

  /** Whether the engine supports this criterion today. */
  status: CriterionStatus

  /** Why this criterion exists pedagogically. */
  rationale?: string
}
```

#### Behavioral criteria

```ts
export interface AbsoluteBehavioralCheck {
  mode: 'absolute'
  metric: string
  op: '<' | '<=' | '>' | '>=' | '==' | '!='
  value: number
}

export interface ComparativeBehavioralCheck {
  mode: 'vs-baseline'
  metric: string
  baselineScenarioId: string
  comparison: '<' | '<=' | '>' | '>='
  delta: number
}

export interface BehavioralCriterion extends CriterionBase {
  kind: 'behavioral'
  check: AbsoluteBehavioralCheck | ComparativeBehavioralCheck
}
```

#### Structural criteria

```ts
export type StructuralRule =
  | {
      type: 'requires-node-type'
      nodeType: string
      minCount?: number
      maxCount?: number
    }
  | {
      type: 'forbids-node-type'
      nodeType: string
    }
  | {
      type: 'requires-path'
      fromRole?: string
      fromNodeType?: string
      toRole?: string
      toNodeType?: string
      viaNodeTypes?: string[]
      requestType?: string
    }
  | {
      type: 'forbids-shortcut'
      fromRole?: string
      toNodeType?: string
      bypassNodeTypes?: string[]
    }
  | {
      type: 'requires-conditional-route'
      requestType: string
      toNodeType: string
    }

export interface StructuralCriterion extends CriterionBase {
  kind: 'structural'
  rule: StructuralRule
}
```

#### Resource / budget criteria

```ts
export type ResourceRule =
  | {
      type: 'max-node-count'
      value: number
    }
  | {
      type: 'max-total-workers'
      value: number
      scope: 'all-nodes' | 'student-added-only'
    }
  | {
      type: 'max-cost-points'
      value: number
      costModelVersion: string
    }
  | {
      type: 'max-test-runs'
      value: number
    }

export interface ResourceCriterion extends CriterionBase {
  kind: 'resource'
  rule: ResourceRule
}
```

### Environment policy model

```ts
export interface EvaluationEnvironmentPolicy {
  mode: 'AUTHOR' | 'ASSIGNMENT' | 'PRACTICE'

  paletteAllowlist: string[] | null

  lockedNodeIds?: string[]
  lockedEdgeIds?: string[]

  canEditScaffoldNodes: boolean
  canRemoveScaffoldNodes: boolean

  canTriggerTestRuns: boolean
  maxTestRuns?: number | null

  visibility: {
    prompt: boolean
    gradingSuiteDetails: boolean
    liveMetrics: boolean
    rubricChecks: 'HIDDEN' | 'LIVE_DURING_BUILD' | 'POST_SUBMIT_ONLY'
  }
}
```

### Editorial model

```ts
export interface EditorialPlan {
  /** The concept the question is teaching or evaluating. */
  learningObjectives: string[]

  /** Why the accepted design family works. */
  keyReasoningPoints: string[]

  /** Common mistakes the learner should understand. */
  commonWrongTurns?: string[]

  /** When the editorial is unlocked. */
  unlockPolicy: 'after-pass' | 'after-submit' | 'author-only'
}
```

### Full authoring model

```ts
export type EvaluationCriterion =
  | BehavioralCriterion
  | StructuralCriterion
  | ResourceCriterion

export interface EvaluationPlan {
  /** Problem family. */
  archetype: QuestionArchetype

  /** Which top-level layers are active for this question. */
  activeLayers: EvaluationLayer[]

  /** Scenarios used for dry-run and grading. */
  scenarios: EvaluationScenario[]

  /** Chosen criteria from the shared vocabulary. */
  criteria: EvaluationCriterion[]

  /** Runtime exposure policy for this deployment. */
  environment: EvaluationEnvironmentPolicy

  /** Teaching explanation for post-run or post-pass surfaces. */
  editorial?: EditorialPlan
}
```

---

## Projection to the Current Architecture

This ADR does not require replacing the current runtime model.

Instead, `EvaluationPlan` should be treated as an authoring-time abstraction that projects into the current surfaces.

| EvaluationPlan field | Current or future runtime target |
|---|---|
| `scenarios` | `QuestionSuite` |
| absolute behavioral criteria | `Rubric` |
| scaffold-related environment fields | `QuestionScaffold` + `QuestionConstraints` |
| palette and visibility policy | `EnvironmentProfile` |
| structural criteria | future structural evaluator slice |
| comparative criteria | future comparative evaluator slice |
| resource criteria | `QuestionConstraints` today, richer budget model later |
| editorial | host or simulator editorial surface |

This preserves continuity with the existing codebase:

- `QuestionPackage` remains the runtime content contract
- `EnvironmentProfile` remains the runtime lens
- `AttemptState` remains the runtime student state

The generalized model lives one level above them as the authoring and design abstraction.

---

## Authoring Flow

Questions should be authored in this order.

1. Identify the concept being taught or evaluated.
2. Choose the question archetype.
3. Decide which of the three layers are active.
4. Define the scenarios.
5. Choose criteria from the shared vocabulary.
6. Define the environment policy.
7. Define the editorial or explanation surfaces.

The authoring question is always:

What evidence would convince us that the learner understood this architecture lesson inside this simulator?

Not:

What exact topology do we wish they had drawn?

---

## Operationalizability Gate

Before a question is accepted into the simulator-native problem set, it should pass an operationalizability review.

### Required conditions

- It can be expressed as one or more scenarios.
- It has measurable behavioral outcomes or comparable baselines.
- It has a bounded acceptable solution family.
- It can be isolated through an environment policy.
- It can be explained editorially after the run.

### Rejection conditions

Reject or redesign the question if:

- correctness depends mostly on subjective prose reasoning
- the solution space is too open to define meaningful structure families
- no measurable simulator-facing signals correspond to the intended lesson
- the environment cannot be bounded without removing the essence of the problem

This prevents the platform from pretending determinism where none exists.

---

## Authoring Template

Every authored question should be able to answer the following in one compact template.

### 1. Concept

- What architecture lesson is being taught or evaluated?

### 2. Archetype

- Is this `open-build`, `fix`, `optimize`, `ha-chaos`, `tradeoff`, or `learn-only`?

### 3. Scenario set

- What visible dry-run scenarios exist?
- What hidden grading scenarios exist?
- Is there a baseline scenario for comparative checks?

### 4. Active layers

- Which of the three layers are active for this question?

### 5. Criteria selection

- Which behavioral criteria are active?
- Which structural criteria are active?
- Which resource or budget criteria are active?
- Which criteria are `gate` vs `scored`?

### 6. Environment policy

- What palette is exposed?
- What scaffold is locked?
- What dry-run policy exists?
- What result surfaces are visible?
- When are rubric checks visible?

### 7. Editorial

- What should the learner understand after solving?
- What are the common wrong turns?
- When is the explanation unlocked?

If an author cannot answer those seven sections crisply, the question is probably not yet well-bounded enough for simulator-native grading.

---

## Consequences

### Positive

- Questions share a common evaluation language.
- Different archetypes can still be evaluated honestly.
- The grading engine can grow incrementally without changing the product model.
- Environment policy becomes first-class instead of a loose afterthought.
- Editorial and progression systems can be designed against a stable structure.

### Tradeoffs

- The authoring model is richer than today's runtime schema.
- Structural and comparative evaluators require additional implementation work.
- Some open-ended system design prompts will be rejected as not simulator-native.

### Non-goals

This ADR does not define:

- exact UI layouts for result surfaces
- the full cost model
- the full topology query language for structural checks
- the host-side assignment lifecycle

It only defines the generalized evaluation framework and its data model.

---

## Final Rule

The stable product rule is:

- universal **evaluation framework**
- per-question **selection of criteria**

Not:

- one universal rubric applied unchanged to every question

That is the level at which this system generalizes cleanly.

# Question Creation & Simulator-Based Grading — Feature Specification

This document describes the features required to turn System Design assignments into deterministic, simulator-graded questions. It is written from a feature perspective: what each capability does, why it exists, how it works internally, what data it consumes, and what components it requires to be built.

The Question Creation system was designed through a reference document (`Simulator_Question_Creation`) that covers authoring, submission, evaluation, 10 question types, and cross-team ownership. This specification consolidates that into feature-level requirements grounded in the current codebase and identifies the exact contract surface between the Django backend and the ns-simulator engine.

---

## Table of Contents

1. [Problem Context](#problem-context)
2. [Feature 1 — Simulation Verdict Contract](#feature-1--simulation-verdict-contract)
3. [Feature 2 — Headless Batch Runner](#feature-2--headless-batch-runner)
4. [Feature 3 — Scenario Specification Model](#feature-3--scenario-specification-model)
5. [Feature 4 — Rubric & Scoring Engine](#feature-4--rubric--scoring-engine)
6. [Feature 5 — Structural Validation Rules](#feature-5--structural-validation-rules)
7. [Feature 6 — Question Type Framework](#feature-6--question-type-framework)
8. [Feature 7 — Topology Diffing for Fix/Debug Questions](#feature-7--topology-diffing-for-fixdebug-questions)
9. [Feature 8 — Constraint Enforcement](#feature-8--constraint-enforcement)
10. [Feature 9 — Incremental Evolution Support](#feature-9--incremental-evolution-support)
11. [Feature 10 — Feedback Generation](#feature-10--feedback-generation)
12. [Architecture Boundary](#architecture-boundary)
13. [Relationship to Event Debugger & Terminal](#relationship-to-event-debugger--terminal)
14. [NS Simulator Integration Requirements](#ns-simulator-integration-requirements)
15. [Source-to-Feature Map](#source-to-feature-map)

---

## Problem Context

### What exists today

System Design assignments currently work as follows:

1. Students submit answers through the existing `AssignmentQuestionType.SYSTEM_DESIGN` flow, which routes through the `Subjective` / `SubjectiveSubmission` model chain in Django.
2. Grading relies on AI-based subjective evaluation — an LLM scores the submission against a reference answer and rubric text.
3. Marks roll up through the current assignment and integrated assessment pipelines.
4. The ns-simulator exists as a separate tool — students can build topologies on the canvas and run simulations, but there is no connection between the simulator and the grading system.

### What's missing

- **No deterministic grading.** AI-based evaluation produces different scores for the same submission on different runs. Two students with identical architectures can receive different grades. There is no reproducible "test suite" for system design.

- **No scenario-based testing.** An instructor cannot say "this design must survive a database failure" or "this design must handle 10x traffic" and have the system verify it automatically. Grading is holistic and opinion-based, not scenario-driven.

- **No simulator integration in the grading pipeline.** The simulator can run topologies and produce `SimulationOutput` with detailed metrics (`summary.throughput`, `perNode[x].latencyP99`, `sloBreaches[]`, `conservationCheck[]`), but this data never reaches the grading system. The simulator and the LMS are disconnected.

- **No structured question authoring.** Instructors write free-text question descriptions and rubric paragraphs. There is no structured format for defining what components are allowed, what scenarios to test, what thresholds constitute passing, or what scoring weights to apply.

- **No feedback beyond pass/fail.** Students receive a score and optional AI-generated comments. There is no breakdown showing "your design passed the normal load scenario but failed the database failure scenario because you had no read replicas."

### What the reference document explores

The reference document describes a 3-layer system (Authoring → Submission → Evaluation) with 10 question types, 4 scoring buckets, and a cross-team ownership model. This specification treats each layer's capabilities as features, focusing on the simulator's role as a grading engine.

### Where this lives

**This is primarily a Django backend system, NOT an ns-simulator extension.** The authoring models, rubric rules, evaluation records, and scoring logic all live in the Django backend. The ns-simulator's role is narrow and well-defined: it is a **black-box execution engine** that receives a `TopologyJSON`, runs it against scenario parameters, and returns a `SimulationOutput`. The backend interprets that output.

This document specifies both sides of the boundary: what the backend needs from the simulator, and what the simulator must expose.

---

## Feature 1 — Simulation Verdict Contract

### What it does

Defines a stable, versioned subset of `SimulationOutput` that the Django grading backend can depend on as a public API. The backend parses this contract to evaluate rubric rules — it never touches internal engine types directly.

### Why it exists

`SimulationOutput` (in `src/engine/analysis/output.ts`) is an internal type. Its fields evolve with the engine — new checks get added (`warmupAdequacy` was added recently), field names may change, and the structure reflects engine internals rather than grading needs. If the backend grading system parses `SimulationOutput` directly, any engine refactor could silently break grading.

The verdict contract creates an explicit API boundary: "these fields exist, they mean exactly this, and they will not change without a version bump."

### How it works internally

**Contract type:**

```typescript
// Proposed location: src/engine/analysis/verdict.ts

export interface SimulationVerdict {
  /** Contract version for backward compatibility. */
  version: '1.0';

  /** Overall simulation metadata. */
  meta: {
    seed: string;
    simulationDurationMs: number;
    warmupDurationMs: number;
    eventsProcessed: number;
    reproducible: boolean;
  };

  /** Aggregate metrics across all nodes. */
  summary: {
    totalRequests: number;
    successfulRequests: number;
    failedRequests: number;
    rejectedRequests: number;
    timedOutRequests: number;
    throughput: number;          // req/s post-warmup
    errorRate: number;           // fraction
    latency: {
      p50: number;
      p90: number;
      p95: number;
      p99: number;
      max: number;
      mean: number;
    };
  };

  /** Per-node metrics, keyed by node ID. */
  perNode: Record<string, {
    nodeLabel: string;
    totalArrived: number;
    totalProcessed: number;
    totalRejected: number;
    totalTimedOut: number;
    utilization: number;          // [0, 1]
    throughput: number;           // req/s
    errorRate: number;            // fraction
    availability: number;         // fraction
    latencyP50: number;
    latencyP95: number;
    latencyP99: number;
    avgQueueLength: number;
    avgServiceTime: number;
    peakQueueLength: number;
  }>;

  /** SLO violations detected during the run. */
  sloBreaches: Array<{
    nodeId: string;
    nodeLabel: string;
    metric: 'latencyP99' | 'availability';
    target: number;
    actual: number;
    severity: 'warning' | 'critical';
  }>;

  /** Invariant violations (custom assertions). */
  invariantViolations: Array<{
    invariantId: string;
    invariantName: string;
    violatedAt: number;
    details: string;
  }>;

  /** Conservation check — request accounting per node. */
  conservation: Array<{
    nodeId: string;
    arrived: number;
    processed: number;
    rejected: number;
    timedOut: number;
    inFlight: number;
    balanced: boolean;
  }>;

  /** Little's Law verification per node. */
  littlesLaw: Array<{
    nodeId: string;
    observedL: number;
    expectedL: number;
    error: number;
    withinTolerance: boolean;
  }>;
}
```

**Projection function:**

```typescript
export function projectToVerdict(output: SimulationOutput): SimulationVerdict
```

This function maps from the internal `SimulationOutput` (which may evolve) to the stable `SimulationVerdict` (which is versioned). The mapping is straightforward — mostly field selection and renaming — but the indirection ensures the backend never depends on internal field names.

**Why `version` exists:** When the grading contract needs to add new fields (e.g., adding `causalGraph` data for resilience scoring), the backend can check `verdict.version` and handle both old and new formats. Without versioning, adding a field the backend expects would break all older simulation results.

**Relationship to existing types:** `SimulationVerdict` is a strict subset of `SimulationOutput`. Every field in the verdict comes from an existing `SimulationOutput` field:

| Verdict field | Source in SimulationOutput |
|---|---|
| `summary.totalRequests` | `summary.totalRequests` |
| `summary.throughput` | `summary.throughput` |
| `summary.latency.*` | `summary.latency.*` |
| `perNode[id].utilization` | `perNode[id].utilization` |
| `perNode[id].latencyP99` | `perNode[id].latencyP99` |
| `sloBreaches[]` | `sloBreaches[]` |
| `invariantViolations[]` | `invariantViolations[]` |
| `conservation[]` | `conservationCheck[]` (renamed) |
| `littlesLaw[]` | `littlesLawCheck[]` (renamed) |

### What components it requires

- **NS Simulator side:** `src/engine/analysis/verdict.ts` — the `SimulationVerdict` type and `projectToVerdict()` function. Exported from the engine package.
- **CLI side:** The headless runner ([Feature 2](#feature-2--headless-batch-runner)) outputs `SimulationVerdict` JSON instead of raw `SimulationOutput` when invoked by the grading pipeline.
- **Backend side:** Django models that parse `SimulationVerdict` JSON. These live in the backend, not in ns-simulator.

### Explored in

Reference doc (Evaluation layer — "metrics/verdict response contract", "Simulator team owns: topology validation, deterministic scenario execution, metrics/verdict response contract").

---

## Feature 2 — Headless Batch Runner

### What it does

An extension of the existing CLI (`src/cli/index.ts`) that accepts multiple scenario configurations, runs the simulator once per scenario, and returns an array of `SimulationVerdict` results. This is the integration point between the Django backend and the ns-simulator engine.

### Why it exists

The current CLI runs one simulation per invocation. The grading pipeline needs to run N scenarios per submission (e.g., "normal load", "10x spike", "database failure", "network partition") and collect all results. Without a batch runner, the backend would need to spawn N separate processes, parse N separate outputs, and handle N sets of error conditions.

### How it works internally

**Invocation:**

```bash
# Single scenario (existing behavior, but outputting verdict)
nssim run topology.json --verdict --output result.json

# Batch scenarios (new)
nssim evaluate topology.json --scenarios scenarios.json --output verdicts.json
```

**Scenarios input format:**

```json
{
  "scenarios": [
    {
      "id": "normal-load",
      "name": "Normal traffic (100 RPS)",
      "overrides": {
        "global": { "simulationDuration": 30000, "seed": "eval-normal-001" },
        "workload": { "baseRps": 100 }
      }
    },
    {
      "id": "spike-10x",
      "name": "10x traffic spike",
      "overrides": {
        "global": { "simulationDuration": 30000, "seed": "eval-spike-001" },
        "workload": { "baseRps": 100, "pattern": "spike", "spike": { "spikeTime": 10000, "spikeRps": 1000, "spikeDuration": 5000 } }
      }
    },
    {
      "id": "db-failure",
      "name": "Database node failure",
      "overrides": {
        "global": { "simulationDuration": 30000, "seed": "eval-dbfail-001" },
        "faults": [{ "targetId": "orders-db", "faultType": "node-failure", "timing": "deterministic", "duration": "fixed", "params": { "triggerTimeMs": 5000, "durationMs": 10000 } }]
      }
    }
  ]
}
```

Each scenario takes the base `TopologyJSON` (the student's submission) and applies `overrides` to produce a modified topology. The overrides use a shallow merge at each level — `overrides.global` merges with `topology.global`, `overrides.workload` replaces `topology.workload`, `overrides.faults` replaces `topology.faults`.

**Batch output format:**

```json
{
  "submissionId": "sub-12345",
  "topologyId": "student-topology-001",
  "evaluatedAt": "2026-06-01T12:00:00Z",
  "verdicts": [
    {
      "scenarioId": "normal-load",
      "scenarioName": "Normal traffic (100 RPS)",
      "status": "completed",
      "verdict": { /* SimulationVerdict */ }
    },
    {
      "scenarioId": "spike-10x",
      "scenarioName": "10x traffic spike",
      "status": "completed",
      "verdict": { /* SimulationVerdict */ }
    },
    {
      "scenarioId": "db-failure",
      "scenarioName": "Database node failure",
      "status": "error",
      "error": "Topology validation failed: node 'orders-db' not found"
    }
  ]
}
```

**Execution model:**

```
For each scenario:
  1. Deep-clone base TopologyJSON
  2. Apply scenario overrides
  3. validateTopology(merged) → reject if invalid
  4. new SimulationEngine(merged) → engine.run()
  5. projectToVerdict(engine.getResults()) → collect
```

Scenarios run **sequentially** in the same process (the engine is deterministic and single-threaded). Each scenario gets its own `SimulationEngine` instance with its own seed, so results are independent and reproducible.

**Error handling:** If a scenario fails (validation error, engine crash, timeout), that scenario's entry in the output gets `status: 'error'` with the error message. Other scenarios still run. The batch runner never exits with a non-zero code unless the base topology itself is unparseable.

**Timeout guard:** Each scenario has a wall-clock timeout (configurable, default 30 seconds). If the engine doesn't complete within the timeout, the scenario is killed and marked as `status: 'timeout'`. This prevents a student's pathological topology (e.g., infinite-capacity queue with 0 workers) from hanging the grading pipeline.

### What components it requires

- **NS Simulator side:** A new `evaluate` command in `src/cli/` that accepts `--scenarios` and orchestrates batch execution. Reuses the existing `SimulationEngine` and `validateTopology`.
- **Shared layer:** A `ScenarioOverride` type and a `mergeTopologyWithOverrides(base, overrides)` utility.
- **Backend side:** A Celery task that invokes `nssim evaluate` as a subprocess, reads the JSON output, and stores results. Lives in Django, not in ns-simulator.

### Explored in

Reference doc (Evaluation layer — "backend runs simulator scenarios", "Simulator team owns: deterministic scenario execution", "May need a batch runner or scenario-list support in the CLI").

---

## Feature 3 — Scenario Specification Model

### What it does

A structured data model for defining test scenarios that an instructor attaches to a System Design question. Each scenario specifies traffic conditions, fault injections, timing, and what success looks like — everything the simulator needs to produce a meaningful verdict.

### Why it exists

Without structured scenarios, the grading pipeline has no instructions for how to test a submission. The instructor needs to say "run the student's topology under 1000 RPS for 30 seconds and check that P99 latency stays below 200ms." This requires a formal schema that can be stored in a database, serialized to JSON, and passed to the simulator.

### How it works internally

**Scenario model (Django side):**

```python
# This lives in the Django backend, NOT in ns-simulator.
# Shown here to document the contract.

class SimulatorScenario(models.Model):
    question = models.ForeignKey('SystemDesignSpec', on_delete=models.CASCADE, related_name='scenarios')
    scenario_id = models.CharField(max_length=64, unique=True)
    name = models.CharField(max_length=256)
    description = models.TextField(blank=True)
    
    # Traffic configuration
    workload_overrides = models.JSONField(default=dict)  # → TopologyJSON.workload overrides
    
    # Fault injection
    faults = models.JSONField(default=list)  # → TopologyJSON.faults overrides
    
    # Simulation parameters
    duration_ms = models.IntegerField(default=30000)
    seed = models.CharField(max_length=64)
    warmup_ms = models.IntegerField(default=5000)
    
    # Pass criteria
    pass_criteria = models.JSONField()  # → ScenarioPassCriteria
    
    # Weighting
    weight = models.FloatField(default=1.0)  # relative weight in total score
    required = models.BooleanField(default=True)  # must pass for overall pass
    
    # Scoring bucket
    bucket = models.CharField(choices=[
        ('structure', 'Structure'),
        ('behavior', 'Behavior'),
        ('resilience', 'Resilience'),
        ('efficiency', 'Efficiency'),
    ], max_length=16)
    
    order = models.IntegerField(default=0)  # execution order
```

**Pass criteria (the contract between backend and simulator):**

```typescript
// Type that the backend's pass_criteria JSONField stores.
// The backend evaluates these against SimulationVerdict fields.

interface ScenarioPassCriteria {
  /** All conditions must be true for the scenario to pass. */
  conditions: PassCondition[];
}

type PassCondition =
  | { type: 'summary'; field: 'throughput' | 'errorRate'; operator: '>=' | '<=' | '<' | '>'; value: number }
  | { type: 'summary.latency'; field: 'p50' | 'p90' | 'p95' | 'p99' | 'max'; operator: '<=' | '<'; value: number }
  | { type: 'perNode'; nodeLabel: string; field: 'utilization' | 'errorRate' | 'availability' | 'latencyP99'; operator: '>=' | '<=' | '<' | '>'; value: number }
  | { type: 'sloBreaches'; maxCount: number }
  | { type: 'invariantViolations'; maxCount: number }
  | { type: 'conservation'; allBalanced: boolean }
  | { type: 'noRejections' }  // summary.rejectedRequests === 0
  | { type: 'noTimeouts' }   // summary.timedOutRequests === 0
```

**How the backend evaluates pass criteria:**

```python
def evaluate_condition(condition, verdict):
    if condition['type'] == 'summary':
        actual = verdict['summary'][condition['field']]
        return compare(actual, condition['operator'], condition['value'])
    
    elif condition['type'] == 'summary.latency':
        actual = verdict['summary']['latency'][condition['field']]
        return compare(actual, condition['operator'], condition['value'])
    
    elif condition['type'] == 'perNode':
        # Find node by label (not ID, since student IDs are arbitrary)
        node = find_node_by_label(verdict['perNode'], condition['nodeLabel'])
        if not node:
            return False  # required node missing → fail
        actual = node[condition['field']]
        return compare(actual, condition['operator'], condition['value'])
    
    elif condition['type'] == 'sloBreaches':
        return len(verdict['sloBreaches']) <= condition['maxCount']
    
    elif condition['type'] == 'noRejections':
        return verdict['summary']['rejectedRequests'] == 0
    # ...
```

**Important: node matching by label, not by ID.** Students create their own nodes with arbitrary IDs (`node-1`, `my-db`, `postgres-main`). The instructor's pass criteria reference nodes by label or component type, not by ID. The backend's `find_node_by_label` searches `verdict.perNode` for a node whose `nodeLabel` matches the criterion. This is why `nodeLabel` is a required field in the verdict contract.

**How scenarios map to TopologyJSON overrides:**

The scenario's `workload_overrides`, `faults`, `duration_ms`, `seed`, and `warmup_ms` are merged into the student's `TopologyJSON` before running the simulator:

```python
def build_scenario_topology(base_topology, scenario):
    merged = deep_copy(base_topology)
    merged['global']['simulationDuration'] = scenario.duration_ms
    merged['global']['seed'] = scenario.seed
    merged['global']['warmupDuration'] = scenario.warmup_ms
    
    if scenario.workload_overrides:
        merged['workload'] = {**merged.get('workload', {}), **scenario.workload_overrides}
    
    if scenario.faults:
        merged['faults'] = scenario.faults
    
    return merged
```

### What components it requires

- **Backend side:** `SimulatorScenario` Django model, `ScenarioPassCriteria` schema, evaluation logic. All in Django.
- **NS Simulator side:** Nothing new — the simulator already accepts `TopologyJSON` with `workload`, `faults`, and `global` sections. The scenario model is a backend concern that maps to existing simulator inputs.

### Explored in

Reference doc (Authoring layer — "instructors create: what the system design question expects, what scenarios should be tested, how scoring works").

---

## Feature 4 — Rubric & Scoring Engine

### What it does

A configurable scoring system that converts scenario verdicts into a numeric score across four buckets: **Structure**, **Behavior**, **Resilience**, and **Efficiency**. Each bucket aggregates pass/fail results from its assigned scenarios, applies weights, and produces a 0–100 score.

### Why it exists

Individual scenario verdicts are boolean (pass/fail per condition). The rubric engine converts these into a meaningful grade. Without it, the system can only say "passed 3 of 5 scenarios" — it can't produce a nuanced score like "structure: 90/100, behavior: 75/100, resilience: 40/100, efficiency: 85/100."

### How it works internally

**The four scoring buckets:**

| Bucket | What it measures | Example scenarios |
|---|---|---|
| **Structure** | Correct components, proper connections, valid topology | "Has a load balancer upstream of API servers", "Database has read replicas", "Cache sits between API and DB" |
| **Behavior** | Meets functional requirements under normal load | "Throughput ≥ 500 req/s at 100 RPS", "P99 latency < 200ms", "No rejections under normal traffic" |
| **Resilience** | Survives failure scenarios | "System recovers from DB failure within 10s", "No cascading failures when one service dies", "Handles 10x traffic spike" |
| **Efficiency** | Optimal resource usage | "Utilization > 30% on all nodes (not over-provisioned)", "Cost estimate within budget", "No idle replicas" |

**Scoring model (Django side):**

```python
class RubricRule(models.Model):
    question = models.ForeignKey('SystemDesignSpec', on_delete=models.CASCADE, related_name='rubric_rules')
    rule_id = models.CharField(max_length=64)
    bucket = models.CharField(choices=SCORING_BUCKETS, max_length=16)
    description = models.TextField()  # human-readable explanation
    
    # What this rule evaluates
    rule_type = models.CharField(choices=[
        ('scenario_pass', 'Scenario Pass'),       # scenario must pass
        ('structural_check', 'Structural Check'),  # topology must have certain components
        ('metric_threshold', 'Metric Threshold'),  # specific metric must meet threshold
        ('comparison', 'Comparison'),              # compare two nodes/scenarios
    ], max_length=20)
    
    rule_config = models.JSONField()  # rule-type-specific configuration
    
    weight = models.FloatField(default=1.0)     # within its bucket
    max_points = models.FloatField(default=10)   # points awarded if rule passes
```

**Score computation:**

```python
def compute_score(question, verdicts):
    bucket_scores = { 'structure': 0, 'behavior': 0, 'resilience': 0, 'efficiency': 0 }
    bucket_maxes  = { 'structure': 0, 'behavior': 0, 'resilience': 0, 'efficiency': 0 }
    
    for rule in question.rubric_rules.all():
        passed = evaluate_rule(rule, verdicts)
        earned = rule.max_points * rule.weight if passed else 0
        bucket_scores[rule.bucket] += earned
        bucket_maxes[rule.bucket] += rule.max_points * rule.weight
    
    # Normalize each bucket to 0–100
    for bucket in bucket_scores:
        if bucket_maxes[bucket] > 0:
            bucket_scores[bucket] = (bucket_scores[bucket] / bucket_maxes[bucket]) * 100
    
    # Weighted average across buckets
    total_weight = sum(question.bucket_weights.values())
    final_score = sum(
        bucket_scores[b] * question.bucket_weights.get(b, 1.0)
        for b in bucket_scores
    ) / total_weight
    
    return { 'buckets': bucket_scores, 'final': final_score }
```

**Pass/fail determination:**

Two modes, configurable per question:
1. **All-required:** Every scenario marked `required=True` must pass. If any required scenario fails, the submission fails regardless of score.
2. **Threshold:** The final score must exceed a configurable pass threshold (e.g., 60%). Individual scenario failures don't automatically fail the submission.

### What components it requires

- **Backend side:** `RubricRule` Django model, `compute_score()` function, bucket weight configuration on `SystemDesignSpec`. All in Django.
- **NS Simulator side:** Nothing — scoring operates entirely on `SimulationVerdict` data that the simulator already produces.

### Explored in

Reference doc (Scoring, simplified — "four buckets: structure, behavior, resilience, efficiency").

---

## Feature 5 — Structural Validation Rules

### What it does

Pre-simulation checks that verify a student's topology has the required structural properties before running any scenarios. These catch fundamental design mistakes (missing components, disconnected graphs, wrong component types) without needing to burn simulation compute.

### Why it exists

If an instructor's question says "design a system with a load balancer, at least 2 API servers, a cache, and a database," and the student submits a topology with no load balancer, there is no point running 5 simulation scenarios — the submission is structurally invalid. Structural validation provides instant feedback and saves compute.

### How it works internally

**Structural rules (stored in Django, evaluated by the grading pipeline):**

```typescript
// Rule types that operate on TopologyJSON directly (no simulation needed)

type StructuralRule =
  | { type: 'requires_component'; componentType: ComponentType; minCount: number; label?: string }
  | { type: 'requires_category'; category: ComponentCategory; minCount: number }
  | { type: 'requires_edge'; fromType: ComponentType; toType: ComponentType; mode?: EdgeDefinition['mode'] }
  | { type: 'max_component_count'; componentType: ComponentType; maxCount: number }
  | { type: 'requires_redundancy'; componentType: ComponentType; minReplicas: number }
  | { type: 'forbids_component'; componentType: ComponentType }
  | { type: 'requires_connected_graph' }   // no orphaned nodes
  | { type: 'requires_single_source' }     // exactly one workload source
  | { type: 'min_node_count'; count: number }
  | { type: 'max_node_count'; count: number }
  | { type: 'requires_path'; from: ComponentType; to: ComponentType }  // reachability check
```

**Evaluation:**

```python
def evaluate_structural_rule(rule, topology):
    if rule['type'] == 'requires_component':
        matching = [n for n in topology['nodes'] if n['type'] == rule['componentType']]
        return len(matching) >= rule['minCount']
    
    elif rule['type'] == 'requires_edge':
        for edge in topology['edges']:
            src_node = find_node(topology, edge['source'])
            tgt_node = find_node(topology, edge['target'])
            if (src_node['type'] == rule['fromType'] and 
                tgt_node['type'] == rule['toType'] and
                (not rule.get('mode') or edge['mode'] == rule['mode'])):
                return True
        return False
    
    elif rule['type'] == 'requires_connected_graph':
        return is_connected(topology['nodes'], topology['edges'])
    
    elif rule['type'] == 'requires_path':
        return has_path_between_types(topology, rule['from'], rule['to'])
    # ...
```

**Where evaluation runs:** Structural rules are evaluated **before** scenarios, **in the backend**, on the raw `TopologyJSON`. They do NOT require the simulator engine — they're pure graph analysis on the topology's node/edge structure. This is distinct from `validateTopology()` in the simulator, which checks schema correctness (valid field types, positive integers, etc.). Structural rules check design correctness (right components, right connections).

**Relationship to `validateTopology()`:** The simulator's existing validator (`src/engine/validation/validator.ts`) uses Zod schemas to verify that the `TopologyJSON` is structurally valid JSON — correct types, valid enums, positive numbers, capacity ≥ workers, etc. Structural rules are a higher layer: they verify the topology is a *good design* for the given question, not just a valid input to the simulator.

Both run: the simulator's validator runs first (rejecting malformed JSON), then structural rules run (checking design requirements), then scenarios run (testing behavior).

### What components it requires

- **Backend side:** Structural rule definitions, evaluation functions, storage on `SystemDesignSpec`. All in Django.
- **NS Simulator side:** Topology validation (`validateTopology()`) already exists. No changes needed. The backend may import `ComponentType` and `ComponentCategory` type definitions for structural rule autocomplete — these could be exported as a shared type package.

### Explored in

Reference doc (Authoring layer — "which components are allowed in the diagram", Component-restricted Design question type).

---

## Feature 6 — Question Type Framework

### What it does

A classification system for 10 types of System Design questions, each with a predefined authoring template, default scenario patterns, and scoring emphasis. Instructors select a question type when creating a question, and the system pre-populates appropriate scenarios and rubric rules.

### Why it exists

Creating scenarios and rubric rules from scratch is complex. Question types provide templates: selecting "Resilience Testing" pre-populates fault injection scenarios; selecting "Scale the System" pre-populates load ramp scenarios. This makes authoring accessible to instructors who aren't simulation experts.

### The 10 question types

**1. Build-from-Scratch (Classic Design)**

> "Design a system that handles X."

- **Default scenarios:** Normal load, moderate load, edge case traffic
- **Scoring emphasis:** Structure (40%), Behavior (40%), Efficiency (20%)
- **Structural rules:** Requires specific component types per question (e.g., "must have a database, a cache, and an API layer")

**2. Fix / Debug a Broken System**

> "Here's a system. It's failing. Fix it."

- **Provision:** Instructor provides a *reference topology* with known problems (misconfigured capacity, missing load balancer, bottleneck node). Student receives this as a starting point and modifies it.
- **Default scenarios:** Same workload that causes the problem in the reference topology. Student's fixed version must pass where the reference fails.
- **Scoring emphasis:** Behavior (50%), Structure (30%), Efficiency (20%)
- **Special feature:** Topology diffing ([Feature 7](#feature-7--topology-diffing-for-fixdebug-questions))

**3. Scale the System**

> "Make this system handle 10x the current load."

- **Provision:** Instructor provides a working baseline topology that handles load X. Student must modify it to handle 10X.
- **Default scenarios:** Load at X (must still pass), load at 5X, load at 10X
- **Scoring emphasis:** Behavior (40%), Efficiency (30%), Structure (30%)
- **Pass criteria patterns:** Throughput ≥ target at each load level, P99 < threshold, no rejections

**4. Resilience / Fault Tolerance**

> "Make this system survive failures."

- **Default scenarios:** Node failure (each critical node), network partition, cascading failure, recovery test
- **Scoring emphasis:** Resilience (60%), Structure (25%), Behavior (15%)
- **Fault patterns:** Uses `TopologyJSON.faults[]` with `timing: 'deterministic'` for reproducible failure injection

**5. Performance Optimization**

> "Meet these strict SLOs."

- **Provision:** Instructor provides a topology that works but is slow. Student must optimize it.
- **Default scenarios:** High-load scenario with strict latency SLOs
- **Scoring emphasis:** Behavior (40%), Efficiency (40%), Structure (20%)
- **Pass criteria patterns:** P99 < target, utilization within range, no over-provisioning

**6. Constraint-based Design**

> "Design under these constraints."

- **Special feature:** Constraint enforcement ([Feature 8](#feature-8--constraint-enforcement)) — the system verifies the student's topology respects limits (e.g., max 5 nodes, no caching allowed, cost budget)
- **Default scenarios:** Normal load within constraints
- **Scoring emphasis:** Structure (50%), Behavior (30%), Efficiency (20%)

**7. Incremental Evolution**

> "Start with v1, evolve to v2."

- **Provision:** Instructor provides v1 topology. Student submits v2.
- **Special feature:** Evolution support ([Feature 9](#feature-9--incremental-evolution-support)) — v2 must still pass v1 scenarios (backward compatibility) plus new v2 scenarios
- **Default scenarios:** v1 scenarios (must still pass) + v2 scenarios (new requirements)
- **Scoring emphasis:** Structure (30%), Behavior (30%), Resilience (20%), Efficiency (20%)

**8. Component-restricted Design**

> "Design using only these building blocks."

- **Special feature:** Allowed component whitelist. The structural validation rejects any node whose `ComponentType` isn't in the allowed list.
- **Default scenarios:** Standard behavior scenarios
- **Scoring emphasis:** Structure (50%), Behavior (30%), Efficiency (20%)

**9. Scenario-driven "Test Suite"**

> "Your system must pass these hidden scenarios."

- **Key difference:** Scenarios are NOT revealed to the student. The student designs based on a problem description, and the hidden scenarios test edge cases they should anticipate.
- **Default scenarios:** Mix of normal, failure, and spike — student doesn't know which
- **Scoring emphasis:** Behavior (35%), Resilience (35%), Structure (20%), Efficiency (10%)

**10. Tradeoff Evaluation**

> "Optimize for X, but balance Y."

- **Key difference:** Scoring weighs tradeoff quality. A system optimized purely for latency at the cost of 10x over-provisioning scores lower than one that balances latency and cost.
- **Default scenarios:** Normal load with competing metrics
- **Scoring emphasis:** Efficiency (40%), Behavior (30%), Structure (20%), Resilience (10%)
- **Special rubric rules:** Comparison rules (e.g., "latencyP99 < 200ms AND utilization > 0.3 on all nodes")

### What components it requires

- **Backend side:** Question type enum, per-type scenario/rubric templates, authoring UI that pre-populates fields based on type. All in Django.
- **NS Simulator side:** Nothing — question types are an authoring abstraction. The simulator doesn't know or care about question types; it receives `TopologyJSON` + overrides and runs them.

### Explored in

Reference doc (all 10 question type sections with examples).

---

## Feature 7 — Topology Diffing for Fix/Debug Questions

### What it does

Compares a student's submitted topology against the instructor's reference topology (the "broken" version) and identifies what the student changed: added nodes, removed nodes, modified configurations, rewired edges. This diff is used for scoring (did the student fix the right things?) and feedback.

### Why it exists

For Fix/Debug questions, the scoring isn't just "does the system work now?" — it's "did the student identify and fix the actual problem?" A student who adds 100 extra nodes to brute-force through a bottleneck should score lower than one who correctly identified the misconfigured capacity on a single node.

### How it works internally

**Diff model:**

```typescript
interface TopologyDiff {
  addedNodes: ComponentNode[];
  removedNodes: ComponentNode[];
  modifiedNodes: Array<{
    nodeId: string;
    changes: Array<{
      field: string;        // e.g., 'queue.capacity', 'processing.timeout'
      oldValue: unknown;
      newValue: unknown;
    }>;
  }>;
  addedEdges: EdgeDefinition[];
  removedEdges: EdgeDefinition[];
  modifiedEdges: Array<{
    edgeId: string;
    changes: Array<{
      field: string;
      oldValue: unknown;
      newValue: unknown;
    }>;
  }>;
}
```

**How it's computed:** Deep comparison of `TopologyJSON.nodes[]` and `TopologyJSON.edges[]` between reference and submission. Nodes are matched by ID (if the student kept the reference's node IDs) or by a combination of `type + label` (fuzzy match if IDs differ).

**Scoring integration:** The diff feeds into rubric rules:

```python
# Rubric rule: "Student must modify the payment-svc capacity"
{
    "rule_type": "diff_check",
    "rule_config": {
        "expected_changes": [
            { "nodeLabel": "payment-svc", "field": "queue.capacity", "direction": "increased" }
        ],
        "max_total_changes": 5  # penalize if student changed too many things
    }
}
```

### What components it requires

- **Backend side:** `TopologyDiff` computation, diff-based rubric rules. In Django.
- **NS Simulator side:** Optionally, a `diffTopologies(a, b)` utility could live in `src/engine/` as a shared function. Alternatively, the backend handles diffing entirely. The utility is simple enough that either placement works.

### Explored in

Reference doc (Fix/Debug question type — "Can student identify bottlenecks, Can they modify architecture correctly").

---

## Feature 8 — Constraint Enforcement

### What it does

Verifies that a student's topology respects instructor-defined constraints before running scenarios. Constraints include component count limits, cost budgets, forbidden component types, and resource caps.

### Why it exists

For Constraint-based Design and Component-restricted questions, the design challenge is "build something that works *within these limits*." Without enforcement, a student could ignore constraints and still get a passing score if their over-provisioned design passes the scenarios.

### How it works internally

**Constraint types:**

```typescript
type DesignConstraint =
  | { type: 'max_nodes'; count: number }
  | { type: 'max_edges'; count: number }
  | { type: 'allowed_types'; types: ComponentType[] }           // whitelist
  | { type: 'forbidden_types'; types: ComponentType[] }         // blacklist
  | { type: 'max_total_workers'; count: number }                // sum of all queue.workers
  | { type: 'max_total_capacity'; count: number }               // sum of all queue.capacity
  | { type: 'cost_budget'; maxMonthlyCost: number }             // requires cost model
  | { type: 'max_replicas_per_node'; count: number }            // resources.replicas
  | { type: 'required_architecture_pattern'; pattern: 'event-driven' | 'request-response' | 'cqrs' }
```

**Evaluation:** Constraints are checked **before** structural rules and scenarios:

```
Student submits TopologyJSON
  → validateTopology() (schema check — ns-simulator)
  → enforceConstraints() (design constraints — backend)
  → evaluateStructuralRules() (required components — backend)
  → run scenarios (simulation — ns-simulator)
  → compute score (rubric — backend)
```

If any constraint is violated, the submission is rejected with a specific message ("Your design uses 8 nodes, but the maximum allowed is 5"). The student can resubmit.

**Cost model integration:** The `cost_budget` constraint requires a cost model that estimates monthly infrastructure cost from the topology. This maps to the existing cost calculator issue (#74 — `T-031: Implement cost calculator`). The cost model assigns per-node cost based on `ComponentType` and `ResourceConfig`:

```typescript
// From #74 — cost calculator (not yet implemented)
function estimateMonthlyCost(topology: TopologyJSON): number {
  return topology.nodes.reduce((total, node) => {
    const unitCost = BASE_COSTS[node.type] ?? 50; // $/month
    const replicas = node.resources?.replicas ?? 1;
    return total + unitCost * replicas;
  }, 0);
}
```

### What components it requires

- **Backend side:** Constraint definitions, enforcement logic, per-question constraint configuration. In Django.
- **NS Simulator side:** Cost calculator (#74) would be beneficial for cost-budget constraints. Otherwise, nothing new — constraints operate on `TopologyJSON` directly.

### Explored in

Reference doc (Constraint-based Design question type — "Limited memory, Cost constraints, No caching allowed").

---

## Feature 9 — Incremental Evolution Support

### What it does

For "Evolve v1 to v2" questions, the system runs the student's submission against two scenario sets: the original v1 scenarios (backward compatibility) and the new v2 scenarios (new requirements). Both must pass for full credit.

### Why it exists

System evolution is a critical engineering skill — adding features without breaking existing functionality. This question type tests whether a student can extend an architecture (add real-time features, add multi-region support) while maintaining backward compatibility.

### How it works internally

**Authoring:**

The instructor creates the question with:
1. A v1 reference topology (the starting point)
2. v1 scenarios (the baseline requirements)
3. v2 requirements description (what to add)
4. v2 scenarios (the new requirements)

**Evaluation:**

```
Student submits v2 topology
  → Run v1 scenarios against v2 topology → must still pass
  → Run v2 scenarios against v2 topology → must pass
  → Compute topology diff (v1 reference → v2 submission)
  → Score based on backward compatibility + new feature correctness + change efficiency
```

**Scoring:**

```python
# v1 backward compatibility: 40% weight
# v2 new feature: 40% weight  
# Change efficiency: 20% weight (penalize excessive changes, reward minimal modifications)
```

The "change efficiency" score uses the topology diff ([Feature 7](#feature-7--topology-diffing-for-fixdebug-questions)) — fewer, more targeted changes score higher than wholesale rewrites.

### What components it requires

- **Backend side:** Multi-scenario-set configuration (v1 set, v2 set), diff-based efficiency scoring. In Django.
- **NS Simulator side:** Nothing new — the simulator runs scenarios regardless of whether they're labeled "v1" or "v2."

### Explored in

Reference doc (Incremental Evolution question type — "Add real-time features to batch system, Add multi-region support").

---

## Feature 10 — Feedback Generation

### What it does

Produces structured, per-scenario feedback for students after evaluation. Instead of a single score, students see which scenarios passed, which failed, why they failed, and what part of their design caused the failure.

### Why it exists

A score of 65/100 is meaningless without context. Students need to know: "Your system handled normal traffic (pass), but failed the database failure scenario because you had no read replicas. The payment-svc node reached 100% utilization and rejected 342 requests." This feedback drives learning — the student knows exactly what to fix.

### How it works internally

**Feedback model:**

```typescript
interface SubmissionFeedback {
  overallScore: number;                    // 0–100
  overallPass: boolean;
  
  bucketScores: {
    structure: { score: number; max: number; details: string[] };
    behavior: { score: number; max: number; details: string[] };
    resilience: { score: number; max: number; details: string[] };
    efficiency: { score: number; max: number; details: string[] };
  };
  
  scenarioResults: Array<{
    scenarioId: string;
    scenarioName: string;
    passed: boolean;
    failedConditions: Array<{
      description: string;        // "P99 latency must be < 200ms"
      expected: string;           // "< 200ms"
      actual: string;             // "342ms"
    }>;
    highlights: Array<{
      type: 'bottleneck' | 'slo_breach' | 'rejection_hotspot' | 'over_provisioned';
      nodeLabel: string;
      detail: string;             // "payment-svc rejected 342 requests (capacity: 100, arrived: 980/s)"
    }>;
  }>;
  
  structuralNotes: string[];               // "Missing read replicas for orders-db"
  suggestions: string[];                   // "Consider adding a cache between API and DB"
}
```

**How highlights are derived from `SimulationVerdict`:**

| Highlight type | Derived from | Condition |
|---|---|---|
| `bottleneck` | `perNode[id].utilization` | Utilization > 90% |
| `slo_breach` | `sloBreaches[]` | Any breach present |
| `rejection_hotspot` | `perNode[id].totalRejected` | Rejections > 0 |
| `over_provisioned` | `perNode[id].utilization` | Utilization < 10% and node has > 1 worker |

**Suggestions:** Rule-based, keyed off failure patterns:

```python
SUGGESTION_RULES = [
    {
        'condition': lambda v: any(n['utilization'] > 0.9 for n in v['perNode'].values()),
        'suggestion': 'Consider adding more workers or a load balancer upstream of the saturated node.'
    },
    {
        'condition': lambda v: v['summary']['rejectedRequests'] > v['summary']['totalRequests'] * 0.05,
        'suggestion': 'More than 5% of requests are being rejected. Increase node capacity or add horizontal scaling.'
    },
    {
        'condition': lambda v: len(v['sloBreaches']) > 0 and any(b['metric'] == 'latencyP99' for b in v['sloBreaches']),
        'suggestion': 'P99 latency SLO is breached. Consider adding a cache layer to reduce database load.'
    },
]
```

**Visibility control:** For "Hidden Test Suite" questions (type 9), scenario details are hidden — the student sees "Scenario 3: Failed" but not the specific conditions or workload parameters. This prevents reverse-engineering the test cases.

### What components it requires

- **Backend side:** Feedback generation logic, suggestion rules, visibility controls, student-facing API. All in Django.
- **NS Simulator side:** Nothing — feedback is derived from `SimulationVerdict` data that the simulator already produces.

### Explored in

Reference doc (Evaluation layer — "stores detailed feedback", "gives better feedback to students").

---

## Architecture Boundary

This is the most important section of this document. It defines exactly where ns-simulator's responsibility ends and the backend's begins.

```
┌─────────────────────────────────────────────────┐
│              Django Backend                      │
│                                                  │
│  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ Authoring     │  │ Evaluation               │ │
│  │               │  │                          │ │
│  │ SystemDesign  │  │ For each scenario:       │ │
│  │   Spec        │  │   merge overrides        │ │
│  │ Scenarios     │  │   invoke simulator ──────┤─┤──┐
│  │ RubricRules   │  │   receive verdict  ◄─────┤─┤──┤
│  │ Constraints   │  │   evaluate pass criteria │ │  │
│  │               │  │                          │ │  │
│  └──────────────┘  │ Compute bucket scores     │ │  │
│                     │ Generate feedback         │ │  │
│                     │ Store results             │ │  │
│                     │ Update marks pipeline     │ │  │
│                     └──────────────────────────┘ │  │
└─────────────────────────────────────────────────┘  │
                                                      │
          ┌───────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────┐
│              NS Simulator                        │
│                                                  │
│  ┌─────────────────────────────────────────────┐│
│  │ nssim evaluate topology.json                ││
│  │   --scenarios scenarios.json                ││
│  │   --output verdicts.json                    ││
│  │                                             ││
│  │ For each scenario:                          ││
│  │   1. validateTopology(merged)               ││
│  │   2. new SimulationEngine(merged)           ││
│  │   3. engine.run()                           ││
│  │   4. projectToVerdict(engine.getResults())  ││
│  │   5. collect verdict                        ││
│  │                                             ││
│  │ Output: SimulationVerdict[]                 ││
│  └─────────────────────────────────────────────┘│
│                                                  │
│  Owns:                                           │
│  ✓ TopologyJSON validation (Zod schemas)         │
│  ✓ Deterministic simulation execution            │
│  ✓ SimulationVerdict contract                    │
│  ✓ Seeded reproducibility                        │
│  ✓ Engine versioning                             │
│                                                  │
│  Does NOT own:                                   │
│  ✗ Question authoring                            │
│  ✗ Scenario definitions                          │
│  ✗ Rubric/scoring logic                          │
│  ✗ Structural design rules                       │
│  ✗ Feedback generation                           │
│  ✗ Student submission handling                   │
│  ✗ Marks pipeline integration                    │
└─────────────────────────────────────────────────┘
```

**The contract surface has exactly two touch points:**

1. **Input:** `TopologyJSON` (already exists) + scenario overrides (shallow merge — no new types needed)
2. **Output:** `SimulationVerdict` (new type — [Feature 1](#feature-1--simulation-verdict-contract))

Everything else — authoring, scenarios, rubrics, constraints, scoring, feedback, marks — is backend logic that never touches ns-simulator code.

---

## Relationship to Event Debugger & Terminal

The Question Creation system is **adjacent** to the event debugger and terminal, not overlapping. It consumes the simulator as a black box and never uses the event-level or debug-level data that the debugger and terminal depend on.

### What it shares

| Shared element | How Question Creation uses it | How Debugger/Terminal uses it |
|---|---|---|
| `SimulationEngine` | Runs simulations headlessly | Same engine, but with debug callbacks wired |
| `SimulationOutput` | Source data for `SimulationVerdict` projection | Source data for `DebugEvent` projection |
| `validateTopology()` | Pre-simulation validation in the batch runner | Same validation before GUI-initiated runs |
| `TopologyJSON` | Student submission format | Canvas serialization format |
| CLI (`src/cli/index.ts`) | Invocation target for the `nssim evaluate` command | Invocation target for `nssim run`, `nssim show`, etc. |

### What it does NOT share

| Event Debugger / Terminal feature | Why Question Creation doesn't need it |
|---|---|
| `DebugEvent[]` (#38) | Grading cares about aggregate verdicts, not individual events |
| `RequestLifecycle`, `AdmissionDecision` | Students see feedback, not debugging tools |
| `TimeSeriesSnapshot` streaming (#33) | No real-time visualization — batch processing only |
| Canvas debug overlay (#158) | No visual canvas in the grading pipeline |
| Terminal commands, xterm.js | No interactive CLI in the grading pipeline |
| Worker protocol expansion (#68) | No pause/resume/speed — simulations run to completion |
| `useSimulation` hook (#69) | No React renderer in the grading pipeline |

### Implementation order implication

Question Creation can be built **independently** of the event debugger and terminal. The only shared prerequisite is a stable `SimulationOutput` — which already exists. The `SimulationVerdict` contract ([Feature 1](#feature-1--simulation-verdict-contract)) is a thin projection layer that can be added at any time.

If the event debugger and terminal are being built in phases (as outlined in the combined implementation order), the Question Creation features can run in parallel without blocking or being blocked.

---

## NS Simulator Integration Requirements

Only two things need to change in ns-simulator to support Question Creation:

### 1. SimulationVerdict contract (Feature 1)

**New file:** `src/engine/analysis/verdict.ts`
**Contents:** `SimulationVerdict` interface + `projectToVerdict()` function
**Size:** Small — ~100 lines of type definitions and field mapping
**Dependencies:** Only `SimulationOutput` (already exists)

### 2. Headless batch runner (Feature 2)

**New file:** `src/cli/commands/evaluate.ts` (or extend `src/cli/index.ts`)
**Contents:** `nssim evaluate` command that accepts `--scenarios`, runs multiple simulations, outputs `SimulationVerdict[]`
**Size:** Medium — ~200 lines of orchestration, override merging, timeout handling
**Dependencies:** `SimulationEngine`, `validateTopology`, `projectToVerdict`

### Optional: Topology diff utility (Feature 7)

**New file:** `src/engine/analysis/diff.ts`
**Contents:** `diffTopologies(a, b): TopologyDiff` function
**Size:** Small — ~150 lines of deep comparison
**Dependencies:** `TopologyJSON` types only

### Optional: Shared type exports

**Modified:** `package.json` exports or a dedicated `src/types/public.ts`
**Contents:** Export `ComponentType`, `ComponentCategory`, `TopologyJSON`, `SimulationVerdict` as a public type package that the Django backend can reference for type safety
**Size:** Trivial — re-exports of existing types

Everything else is backend work that does not touch ns-simulator.

---

## Source-to-Feature Map

| Feature | Reference Doc Section |
|---|---|
| 1. Simulation Verdict Contract | Evaluation layer — "metrics/verdict response contract" |
| 2. Headless Batch Runner | Evaluation layer — "backend runs simulator scenarios", "May need a batch runner" |
| 3. Scenario Specification Model | Authoring layer — "what scenarios should be tested" |
| 4. Rubric & Scoring Engine | Scoring, simplified — "four buckets: structure, behavior, resilience, efficiency" |
| 5. Structural Validation Rules | Authoring layer — "which components are allowed in the diagram" |
| 6. Question Type Framework | All 10 question type sections |
| 7. Topology Diffing | Fix/Debug question type — "Can student identify bottlenecks" |
| 8. Constraint Enforcement | Constraint-based Design question type |
| 9. Incremental Evolution Support | Incremental Evolution question type |
| 10. Feedback Generation | Evaluation layer — "stores detailed feedback", "gives better feedback" |

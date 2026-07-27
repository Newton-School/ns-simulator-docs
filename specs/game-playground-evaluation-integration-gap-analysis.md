# Game Playground Evaluation Integration Gap Analysis

This document turns the current simulator state into a concrete integration analysis for an evaluation system shaped like Newton's Game Playground. It is written as a product and engineering gap note, not as an implementation PRD for a single file or service.

The reference point is the existing Game Playground model used by `web-based-packet-tracer`: an iframe-hosted simulator with a seeded starting state, a durable attempt-state blob, a visible rubric checklist, and summary score flags that the host platform persists and reads for completion.

The important takeaway is that the packet tracer is **not** merely "a simulator in an iframe". It is a simulator plus:

- an embed-mode runtime
- an attempt-state protocol
- a rubric and scoring engine
- a visible tests UI
- a host-compatible save and completion contract

For NS Simulator, the state format should remain JSON. The packet tracer's use of XML is domain-specific to network topology serialization; it is **not** a requirement of Game Playground itself. The right equivalent here is `TopologyJSON` plus a JSON attempt-state envelope.

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Integration Principles](#integration-principles)
3. [Gap Matrix 1 — Existing Feature to Missing Piece](#gap-matrix-1--existing-feature-to-missing-piece)
4. [Gap Matrix 2 — Packet Tracer Feature Mapping](#gap-matrix-2--packet-tracer-feature-mapping)
5. [Current Repo Surface](#current-repo-surface)
6. [1. Real Evaluation Contract](#1-real-evaluation-contract)
7. [2. Headless Batch Evaluation Runner](#2-headless-batch-evaluation-runner)
8. [3. Rubric and Check Engine](#3-rubric-and-check-engine)
9. [4. Attempt-State Protocol for Game Playground](#4-attempt-state-protocol-for-game-playground)
10. [5. Real Embed Mode](#5-real-embed-mode)
11. [6. Authoring Model for Questions](#6-authoring-model-for-questions)
12. [7. Grading-Safe Persistence and Replay Lifecycle](#7-grading-safe-persistence-and-replay-lifecycle)
13. [8. Grading-Risk Engine Gaps](#8-grading-risk-engine-gaps)
14. [UI Changes Required](#ui-changes-required)
15. [Recommended Build Order](#recommended-build-order)
16. [JSON Shapes to Standardize](#json-shapes-to-standardize)
17. [Final Recommendation](#final-recommendation)

---

## Problem Statement

Today the simulator is a strong standalone system-design and distributed-systems simulator:

- it serializes the canvas to `TopologyJSON`
- it validates topology before execution
- it runs deterministic seeded simulations
- it produces rich `SimulationOutput`
- it supports local save and load
- it has a sample scenario library

What it does **not** yet have is the assignment-evaluation layer needed for a platform like Game Playground:

- a stable grading contract
- a batch evaluation runner
- a rubric and scoring engine
- a host-compatible attempt-state blob
- a real embed runtime
- authored question packages
- grading-safe lifecycle management

The existing grading-oriented spec already states this separation clearly: the simulator is currently a black-box execution engine with no connection to the grading pipeline, and the missing pieces are deterministic grading, scenario-based testing, structured authoring, and structured feedback. See `specs/question-creation-feature-spec.md`.

---

## Integration Principles

The following principles should guide the integration design.

### 1. Keep `TopologyJSON` as the canonical domain state

The packet tracer persists `topology_xml` because its simulator internally models device configuration as XML. NS Simulator already has a good JSON-native domain model. Do not add XML only to mimic packet tracer.

### 2. Separate simulator execution from grading logic

The simulator should expose:

- `TopologyJSON` as input
- `SimulationVerdict` as stable output

Everything else should live in the evaluation layer:

- scenarios
- rubric rules
- structural checks
- question authoring
- assignment lifecycle
- marks and completion logic

This matches the architecture already described in `specs/question-creation-feature-spec.md`.

### 3. Treat Game Playground as a delivery shell, not the source of grading truth

If integrating into Newton's existing Game Playground host, the iframe state contract must be honored. But long-term grading trust should come from deterministic evaluation over simulator runs, not from a purely client-trusted "I passed" flag.

### 4. Preserve JSON-native persistence

The host-facing attempt blob should be a JSON envelope around:

- the current `TopologyJSON`
- any local workspace state worth restoring
- the last evaluation results
- host summary flags such as `test_cases_passed` and `all_test_cases_passed`

### 5. Build one vertical slice first

The correct first question type is the same one already recommended in the roadmap: **Fix the bottleneck**. This is the shortest path to a real authored, solved, and deterministically graded assignment.

---

## Gap Matrix 1 — Existing Feature to Missing Piece

| Existing feature | Missing piece | Why needed for question creation | Why needed for Game Playground | Priority |
| --- | --- | --- | --- | --- |
| Canvas serialization to `TopologyJSON` | Stable public grading contract over results | Authoring and grading need a backend-safe output, not internal engine types | Host needs a stable summary of pass/fail and evidence | P0 |
| Single-run CLI (`npm run simulate -- topology.json`) | Batch evaluator with scenario overrides and per-scenario timeout guards | Real questions need multiple scenarios per submission | Host-side grading or server-side recheck needs repeatable multi-scenario evaluation | P0 |
| Rich `SimulationOutput` with metrics, SLOs, traces, checks | `SimulationVerdict` projection | Grading cannot depend directly on evolving engine internals | Host/platform should read a small, stable grading shape | P0 |
| Topology validator | Per-question structural rule engine | Questions need allowed/required/forbidden component checks | Invalid attempts must be rejected before or alongside simulation | P0 |
| Scenario controls in the app | Scenario suite authoring model | Instructors need to define scenario sets, thresholds, weights, and visibility | Host needs a known rubric/checklist for each attempt | P0 |
| Results tray and raw diagnostics | Rubric/check engine | Raw metrics are not grades; grading needs checks, points, and messages | Tests panel needs pass/fail rows, not just charts | P0 |
| Local JSON save/load | Attempt-state protocol and server sync | Students must resume drafts and submit attempts | Core Game Playground requirement: save/reload the whole attempt blob | P0 |
| Standalone simulator app | True embed mode with host boot, seed ingestion, save, reset, and read-only | Students may solve questions inside an LMS shell instead of locally | Game Playground works by iframe embedding and state exchange | P0 |
| Local question textarea preview | Persisted question and attempt model | Authoring requires structured question metadata, not ephemeral UI text | Host instructions panel must load from backend/authored package | P1 |
| Sample scenario library | Question package and template library | Useful as the base of instructor-authored questions | Useful for starter questions and course-aligned templates | P1 |
| Seeded engine and deterministic replay intent | Reproducibility certification and grading hardening | Grading must be byte-stable and explainable | Host-visible marks must be defensible when challenged | P1 |
| Invariant types in schema | Actual invariant evaluation | Some questions will need invariants as grading conditions | Improves fidelity of visible test results and failure reasons | P1 |
| Local UI/store lifecycle | Draft, lock, submit, graded, and replay states | Assignment workflows need more than an editable canvas | Mentor review and read-only replay depend on this | P1 |
| Lightweight iframe preview widget | Production embed runtime | Preview-only handshake does not support real attempts | Host needs a full save/reset/read-only compatible simulator surface | P1 |
| JSON-native output and save model | Standardized attempt-state JSON schema | Required for durable, typed integration | Direct replacement for packet tracer's domain-specific XML blob | P0 |

---

## Gap Matrix 2 — Packet Tracer Feature Mapping

| Packet-tracer feature | NS-simulator equivalent | Exists / missing | Priority |
| --- | --- | --- | --- |
| Dedicated embed route (`/embed/v1`) | Host-aware embed boot mode | Missing | P0 |
| Host handshake (`ready-event`, seed, save) | Embed message contract for ready, seed, save, reset, analytics | Partial preview only; not production-ready | P0 |
| Instruction panel with authored prompt | Real question panel bound to authored metadata | Partial; current text area is local-only | P1 |
| Tests tab with visible checklist | Rubric/check results panel | Missing | P0 |
| `initial_game_state` seed | Starting `TopologyJSON` + authored metadata | Missing as a formal attempt seed protocol | P0 |
| `topology_xml` in save blob | `topology_json` in save blob | Missing as attempt-state standard; JSON should be used instead | P0 |
| `rubric_results[]` persisted in save blob | `check_results[]` or `scenario_results[]` persisted in attempt blob | Missing | P0 |
| `test_cases_passed`, `test_cases_total`, `all_test_cases_passed` summary flags | Aggregate `points_earned`, `points_possible`, `all_checks_passed` plus host-compatible summary flags | Missing | P0 |
| "Run Tests" action | Evaluate current topology against rubric/scenario suite | Missing | P0 |
| Autosave that carries last verdict forward | Autosave of attempt blob without recomputing unless explicitly re-evaluated | Missing | P0 |
| Read-only mentor or locked-attempt mode | Locked/read-only replay mode | Missing | P1 |
| Backend-authored rubric rows | Backend-authored question package or rubric JSON | Missing | P0 |
| Per-check student-facing message | Per-check or per-scenario failure explanation | Missing | P1 |
| Standalone mode outside host | Standalone simulator fallback | Exists as an app, but not as host-compatible embed fallback | P1 |
| Attempt identity (`playgroundHash`) | Stable `attempt_id`, `question_id`, `question_version` in save blob | Missing | P0 |
| Monotonic completion state | Submission and completion lifecycle with final graded snapshot | Missing | P1 |

---

## Current Repo Surface

This section anchors the gap analysis in the current codebase.

### Already present

- **Rich simulation output** in `src/engine/analysis/output.ts`
- **Single-run CLI** in `src/cli/index.ts`
- **Canvas to topology serialization** in `src/renderer/src/hooks/useTopologySerializer.ts`
- **Local JSON file persistence** in `src/renderer/src/hooks/useFlowPersistence.ts`
- **Sample scenario library** in `src/renderer/src/config/sampleScenarios.ts`
- **A lightweight iframe preview** in `src/renderer/src/components/library/EmbeddedIframeQuestion.tsx`

### Not yet present

- `SimulationVerdict`
- `nssim evaluate`
- rubric and scoring engine
- question package model
- attempt-state protocol
- lifecycle-safe submission and replay
- production embed runtime

---

## 1. Real Evaluation Contract

### Goal

Define a stable, versioned JSON output contract that grading systems can consume safely even if `SimulationOutput` evolves internally.

### Why this is required

`SimulationOutput` is excellent for internal analysis and UI rendering, but it is the wrong boundary for grading. It contains internal engine details, optional debug artifacts, and fields that may evolve without grading concerns in mind.

Without a public verdict contract:

- backend graders become coupled to engine internals
- refactors become dangerous
- LMS integrations become brittle
- Game Playground can only trust coarse client-side summary flags

### What to build

Create a new public contract, for example:

- `src/engine/analysis/verdict.ts`

with:

- `SimulationVerdict`
- `projectToVerdict(output: SimulationOutput): SimulationVerdict`

### Recommended contract shape

```json
{
  "version": "1.0",
  "meta": {
    "seed": "abc123",
    "simulation_duration_ms": 60000,
    "warmup_duration_ms": 10000,
    "engine_version": "1.0.0",
    "catalog_version": "2026-07-23",
    "events_processed": 812391,
    "reproducible": true
  },
  "summary": {
    "total_requests": 5000,
    "successful_requests": 4891,
    "failed_requests": 109,
    "rejected_requests": 54,
    "timed_out_requests": 31,
    "throughput": 842.3,
    "error_rate": 0.0218,
    "latency": {
      "p50": 10.5,
      "p90": 52.0,
      "p95": 81.2,
      "p99": 140.6,
      "max": 412.8,
      "mean": 28.4
    }
  },
  "per_node": {},
  "slo_breaches": [],
  "invariant_violations": [],
  "conservation": [],
  "littles_law": []
}
```

### Add scenario-local results on top

`SimulationVerdict` should represent **one scenario evaluation result**. The batch evaluator should then return an array of scenario-scoped verdicts, each annotated with:

- `scenario_id`
- `scenario_name`
- `status`
- `verdict`

### Design rules

- Version the contract from day one.
- Use stable, grading-oriented field names.
- Avoid debug-only or UI-only data.
- Keep enough detail for feedback generation.
- Export the type publicly so the backend can type-check against it.

### What this unlocks

- backend scoring logic
- LMS-safe storage
- hidden/public scenario support
- appealable grading
- Game Playground summary flag derivation from stable evaluator output

---

## 2. Headless Batch Evaluation Runner

### Goal

Run one student submission against many scenarios deterministically and return ordered verdicts.

### Current state

The CLI only supports:

- load one topology
- validate it
- run it once
- print or write `SimulationOutput`

This is useful for local inspection but insufficient for real evaluation.

### What to build

Extend the CLI with:

```bash
nssim evaluate topology.json --scenarios scenarios.json --output verdicts.json
```

This can live in:

- `src/cli/commands/evaluate.ts`, or
- an extension of `src/cli/index.ts`

### Responsibilities of the evaluator

1. Read `TopologyJSON`.
2. Read `ScenarioSuite`.
3. For each scenario:
   - merge overrides into the base topology
   - validate the merged topology
   - execute the simulator
   - project output to `SimulationVerdict`
   - return deterministic scenario result ordering
4. Enforce per-scenario wall-clock timeout guards.
5. Return a top-level `EvaluationResult`.

### Example scenarios input

```json
{
  "version": "1.0",
  "scenarios": [
    {
      "id": "normal-load",
      "name": "Normal Traffic",
      "timeout_ms": 30000,
      "overrides": {
        "global": {
          "simulationDuration": 60000,
          "warmupDuration": 10000
        },
        "workload": {
          "baseRps": 400
        }
      }
    },
    {
      "id": "db-failure",
      "name": "Primary DB Failure",
      "timeout_ms": 30000,
      "overrides": {
        "faults": [
          {
            "targetId": "primary-db",
            "mode": "reject",
            "startTime": 15000,
            "duration": 20000
          }
        ]
      }
    }
  ]
}
```

### Example batch output

```json
{
  "version": "1.0",
  "evaluated_at": "2026-07-23T12:00:00Z",
  "results": [
    {
      "scenario_id": "normal-load",
      "status": "ok",
      "verdict": {}
    },
    {
      "scenario_id": "db-failure",
      "status": "ok",
      "verdict": {}
    }
  ]
}
```

### Non-negotiable requirements

- deterministic output ordering
- no host UI dependency
- timeout guard per scenario
- clear error codes for invalid topology, timeout, engine failure
- golden-file tests in CI

### Why this is the simulator-side equivalent of "Run Tests"

Packet tracer evaluates the current network state against rubric checks. For NS Simulator, the equivalent is:

- run the submission across authored scenarios
- collect structured verdicts
- score rubric checks against those verdicts

This is the engine half of the grading pipeline.

---

## 3. Rubric and Check Engine

### Goal

Turn simulator outputs into:

- pass/fail checks
- points earned
- points possible
- clear failure messages

### Current gap

The simulator can tell you what happened. It cannot yet tell you whether that outcome satisfies an authored assignment rubric.

### What to build

A structured rubric/check engine that consumes:

- structural facts about the topology
- per-scenario `SimulationVerdict`
- optional diffs against the starting topology

and produces:

- `check_results[]`
- aggregate points
- feedback

### Recommended first-slice check types

Start with structured JSON checks, not free-form expression strings.

Suggested v1 check types:

- `REQUIRED_COMPONENT`
- `FORBIDDEN_COMPONENT`
- `MIN_COMPONENT_COUNT`
- `MAX_COMPONENT_COUNT`
- `SCENARIO_THRESHOLD`
- `SCENARIO_COMPARISON`
- `INVARIANT_PASS`
- `TOPOLOGY_DIFF_LIMIT`

### Example rubric

```json
{
  "version": "1.0",
  "checks": [
    {
      "id": "must-have-cache",
      "type": "REQUIRED_COMPONENT",
      "points": 2,
      "component_type": "in-memory-cache",
      "message_on_fail": "Add a cache on the read path to reduce DB pressure."
    },
    {
      "id": "normal-load-p99",
      "type": "SCENARIO_THRESHOLD",
      "points": 3,
      "scenario_id": "normal-load",
      "metric": "summary.latency.p99",
      "operator": "<=",
      "target": 200,
      "message_on_fail": "P99 latency must stay under 200ms at normal load."
    },
    {
      "id": "db-failure-availability",
      "type": "SCENARIO_THRESHOLD",
      "points": 4,
      "scenario_id": "db-failure",
      "metric": "summary.error_rate",
      "operator": "<=",
      "target": 0.05,
      "message_on_fail": "The design becomes too error-prone when the primary DB fails."
    }
  ]
}
```

### Output shape

```json
{
  "check_results": [
    {
      "id": "must-have-cache",
      "passed": true,
      "points_earned": 2,
      "points_possible": 2,
      "message": "Redis Cache exists on the read path."
    },
    {
      "id": "normal-load-p99",
      "passed": false,
      "points_earned": 0,
      "points_possible": 3,
      "message": "Observed p99 latency was 284ms; target was <= 200ms."
    }
  ],
  "points_earned": 12,
  "points_possible": 20,
  "all_checks_passed": false
}
```

### Important design choice

Do not start with arbitrary evaluator expressions unless necessary. A structured check language is:

- safer
- easier to validate
- easier to author in UI
- easier to explain to students
- easier to keep deterministic

### Relationship to Game Playground summary flags

If you need Newton host compatibility, derive:

- `test_cases_passed`
- `test_cases_total`
- `all_test_cases_passed`

from the rubric engine output.

For example:

- `test_cases_passed = points_earned`
- `test_cases_total = points_possible`
- `all_test_cases_passed = points_earned === points_possible`

That mirrors the packet tracer pattern while keeping the simulator's actual scoring model independent.

---

## 4. Attempt-State Protocol for Game Playground

### Goal

Define the single durable JSON blob that:

- the host seeds into the iframe
- the simulator mutates locally
- the host persists on save
- the simulator can restore on reopen

### Why this matters

This is the biggest conceptual difference between "a simulator" and "a graded game". Packet tracer's submission JSON is a complete attempt-state snapshot, not merely a topology export.

For NS Simulator, the attempt blob should stay JSON-native and contain `topology_json`.

### Recommended attempt-state shape

```json
{
  "version": "1.0",
  "saved_at": "2026-07-23T12:00:00Z",
  "question_id": "fix-bottleneck-001",
  "question_version": "3",
  "attempt_id": "attempt-abc123",
  "read_only": false,
  "topology_json": {
    "id": "canvas-topology",
    "name": "Student Attempt",
    "version": "2.0.0",
    "global": {},
    "nodes": [],
    "edges": []
  },
  "workspace_state": {
    "selected_source_node_id": "client-app-1",
    "metric_lens": "concurrency"
  },
  "last_evaluation": {
    "evaluated_at": "2026-07-23T11:57:00Z",
    "check_results": [],
    "points_earned": 12,
    "points_possible": 20,
    "all_checks_passed": false
  },
  "test_cases_passed": 12,
  "test_cases_total": 20,
  "all_test_cases_passed": false
}
```

### Required semantics

- `topology_json` is the current student solution state.
- `workspace_state` is optional, UI-specific restoration data.
- `last_evaluation` stores the most recent rubric result.
- summary flags at the root exist for host compatibility.

### Save rules

- Every save should post the **entire** attempt blob.
- Autosave should preserve `last_evaluation` unless a new evaluation has actually run.
- Read-only attempts must not save edits.
- Reset should replace `topology_json` with the starting seed and clear or reset evaluation summary state.

### Why JSON is the right choice

Packet tracer needs XML because its internal topology domain is XML. NS Simulator already has a typed JSON topology schema and local JSON persistence. Converting to XML would add complexity without product value.

---

## 5. Real Embed Mode

### Goal

Support a real iframe-hosted attempt runtime instead of a preview-only embedded widget.

### Current state

The current app has a lightweight iframe preview component that:

- loads an iframe
- sends a one-off `ns-simulator:launch-context`
- waits for `ns-simulator:ready`

This is useful for previewing an embedded assignment surface, but it is not a production attempt runtime.

### What real embed mode must support

- host-aware boot mode
- seed ingestion
- attempt restoration
- save command handling
- reset command handling
- read-only mode
- standalone fallback when there is no parent

### Two integration modes

#### Mode A: Interoperate with Newton's existing Game Playground

If the simulator must plug directly into Newton's existing game host, it should implement that host's wire contract:

- `ready-event`
- host seed push
- response to raw `save`
- root-level `test_cases_passed` and `all_test_cases_passed`

#### Mode B: Use a custom host shell

If you are building your own embed shell, define a cleaner contract, for example:

- game -> host: `ns-simulator:ready`
- host -> game: `ns-simulator:seed`
- host -> game: `ns-simulator:save`
- host -> game: `ns-simulator:reset`
- game -> host: `ns-simulator:state`
- game -> host: `ns-simulator:analytics`

### Recommended simulator embed route

Expose an embed-specific route or app mode that:

- hides local file-first chrome
- boots from host seed if present
- respects read-only state
- supports host-initiated save and reset

### Why the current preview is insufficient

The existing preview component is not bound to:

- attempt lifecycle
- real save protocol
- authored question packages
- graded state restoration
- mentor read-only mode

It is a useful prototype, not a grading runtime.

---

## 6. Authoring Model for Questions

### Goal

Move from ad hoc local notes and sample scenarios to a formal assignment artifact.

### Current state

The app has:

- sample scenarios
- a freeform question text area

What it lacks is a structured authored question format.

### What to build

Introduce a `QuestionPackage` schema containing:

- metadata
- prompt/instructions
- starting topology
- structural rules
- scenario suite
- rubric
- optional reference solution
- versioning

### Recommended question package shape

```json
{
  "version": "1.0",
  "id": "fix-bottleneck-001",
  "title": "Reduce Checkout Latency",
  "prompt_html": "<p>The DB is the bottleneck. Improve the topology without adding more than one new datastore.</p>",
  "initial_topology_json": {},
  "allowed_component_types": [
    "load-balancer-l7",
    "microservice",
    "relational-db",
    "in-memory-cache"
  ],
  "forbidden_component_types": [
    "data-lake"
  ],
  "scenarios": {},
  "rubric": {},
  "reference_solution_topology_json": {}
}
```

### Why this matters

The authoring model is the bridge between:

- instructor intent
- student attempt seed
- batch evaluator
- rubric engine
- host platform

Without it, Game Playground can only embed a sandbox, not a real question.

### Reuse path from current repo

The current sample scenarios should seed the first instructor templates:

- bare metal baseline
- monolith core
- L7 scale-out
- cache-aside read path
- replica read split
- circuit breaker fail-fast

These can become starter question packages instead of being only local samples.

---

## 7. Grading-Safe Persistence and Replay Lifecycle

### Goal

Support the full lifecycle of a graded attempt safely and reproducibly.

### Current state

Current persistence is file-oriented workspace persistence:

- local save
- local open
- unsaved-change tracking

That is useful for authoring and standalone learning, but it is not enough for graded attempts.

### Required lifecycle states

- `draft`
- `autosaved`
- `submitted`
- `locked`
- `graded`
- `reopened_read_only`

### Required behaviors

#### Draft and autosave

- Every meaningful topology edit can autosave the full attempt blob.
- Autosave must not imply re-evaluation.
- The last valid verdict should be preserved until the next explicit test run.

#### Run Tests

- Evaluate current topology against the authored rubric.
- Update `last_evaluation`.
- Update host summary flags.
- Do not submit automatically unless the product explicitly wants "evaluate and submit".

#### Submit

- Freeze the evaluated attempt snapshot.
- Mark the attempt as submitted.
- Prevent accidental mutation of the graded snapshot.

#### Read-only replay

- Reopen the exact saved topology.
- Reopen the exact verdict used for grading.
- Allow inspection and results browsing.
- Disallow editing and saving.

### Why this is required

Without lifecycle-safe persistence:

- students can accidentally overwrite graded state
- mentors cannot review the exact graded attempt
- retries and appeals become ambiguous
- Game Playground summary flags can drift from the actual evaluated snapshot

---

## 8. Grading-Risk Engine Gaps

### Goal

Identify engine issues that are acceptable for exploration but dangerous for grading.

### Confirmed risks

#### 1. Invariants are modeled but not evaluated

The codebase and specs support invariant types and an `invariantViolations` field, but the evaluation is currently stubbed. This is acceptable for an incomplete analysis surface; it is not acceptable if rubric rules depend on invariants.

#### 2. Reproducibility is not the same as grading safety

A seeded engine can still grade incorrectly if:

- physics are incomplete
- a trait is half-simulated
- defaults are inconsistent
- a new node changes random draws in unrelated nodes

Deterministic wrong answers are worse than noisy exploratory results when marks are involved.

#### 3. No grading-specific golden tests yet

The evaluator needs:

- frozen scenario fixtures
- frozen expected verdicts
- CI validation that identical inputs produce identical verdicts

#### 4. No batch-run timeout guard

Pathological topologies should not hang grading infrastructure.

#### 5. No student-facing evidence layer over verdicts

Raw output fields are not pedagogical feedback. Students need messages like:

- "Normal load passed."
- "Database-failure scenario failed because the write path has no redundancy."
- "Primary DB hit 100% utilization and rejected 342 requests."

### Recommended mitigation sequence

1. Freeze `SimulationVerdict`.
2. Add `nssim evaluate`.
3. Keep invariants out of rubric v1 unless they are truly implemented.
4. Add golden tests for the first question type.
5. Add timeout guards.
6. Only then attach marks and completion semantics.

---

## UI Changes Required

The required UI work falls into three distinct surfaces:

- student runtime
- instructor authoring
- host/embed runtime

### Student Runtime UI

The student runtime needs to become a question-solving surface, not just a simulator workspace.

#### Required additions

- A real **Question** panel bound to authored content
- A **Tests** panel showing rubric rows and pass/fail status
- A distinct **Run Tests** action separate from plain **Run Simulation**
- Visible **save state**
- Visible **last evaluated at**
- Visible **read-only / locked / graded** badge
- Optional **Submit Attempt** action if explicit submission is part of the workflow

#### Why this matters

Packet tracer works because the student can:

- read the question
- build the attempt
- run visible tests
- understand what failed

Your current app has the canvas and results tray, but not the assignment-oriented shell.

### Instructor Authoring UI

The instructor needs a separate authoring mode, not just the student workspace.

#### Required panels

- question metadata editor
- instructions editor
- starting topology selector
- allowed/forbidden components editor
- scenario suite editor
- rubric editor
- reference solution loader
- preview-as-student mode

#### Suggested workflow

1. Build or load the starting topology.
2. Write prompt and constraints.
3. Define scenarios.
4. Define rubric checks.
5. Load a reference solution.
6. Verify that the reference solution passes 100%.
7. Publish a versioned question package.

### Host / Embed UI

The embed mode needs its own user-state affordances.

#### Required runtime states

- waiting for host seed
- loading saved attempt
- read-only attempt
- save in progress / save failed
- reset in progress

#### Required host affordances

- question title
- attempt status
- save status
- optional due-time or lock state

### Existing UI Pieces You Can Reuse

- The left activity rail and collapsible side panels in `WorkspaceLayout` are a good foundation for Question / Tests / Components / Scenarios.
- The sample scenarios panel can seed a question-template or authored-question picker.
- The results tray can remain the deep evidence view, even after a grading-focused tests panel is added.

### UI elements that should not remain as-is

- The current freeform `Question Text` textarea cannot remain the primary question authoring or runtime surface. It is local component state only and is not part of saved topology or attempt state.
- The embed preview widget should not be mistaken for real attempt hosting. It must be replaced or extended into a real host-aware runtime.

---

## Recommended Build Order

| Phase | Deliverable | Why it comes first |
| --- | --- | --- |
| 1 | `SimulationVerdict v1` | Establishes the public grading boundary |
| 2 | `nssim evaluate` | Enables backend-safe scenario execution |
| 3 | Rubric/check engine for one question type | Converts runs into scores and feedback |
| 4 | `QuestionPackage` and `AttemptState` schemas | Makes authoring and persistence explicit |
| 5 | Production embed mode | Makes iframe-hosted attempts real |
| 6 | Student UI: Question, Tests, Run Tests, save state | Makes the assignment flow usable |
| 7 | Instructor authoring UI | Makes content creation scalable |
| 8 | Lifecycle hardening and grading-risk fixes | Makes grading defensible and reviewable |

The first fully supported question type should be:

- **Fix the bottleneck**

This matches the current roadmap and keeps the first vertical slice coherent.

---

## JSON Shapes to Standardize

These are the JSON-native shapes that should be standardized before integration proceeds.

### 1. `SimulationVerdict`

- versioned
- one scenario result shape
- stable metric subset
- grading-safe field naming

### 2. `ScenarioSuite`

- scenario metadata
- per-scenario overrides
- timeouts
- optional visibility flags

### 3. `Rubric`

- structured check list
- points
- failure messages
- optional scenario association

### 4. `QuestionPackage`

- title
- prompt
- starting topology
- scenario suite
- rubric
- question version

### 5. `AttemptState`

- saved attempt topology
- workspace state
- last evaluation
- host summary flags

### 6. `EvaluationResult`

- batch evaluation output
- scenario verdicts
- rubric check results
- aggregate score

---

## Final Recommendation

Use packet tracer as the **integration reference**, not as the **domain model**.

### Copy from packet tracer

- seeded starting state
- durable attempt blob
- visible tests/checklist
- read-only and locked attempt behavior
- summary host flags
- embed-mode runtime

### Do not copy blindly

- XML payloads
- router/CLI-specific rubric types
- long-term dependence on client-trusted "I passed" flags as the final source of truth

### Keep NS Simulator's own architecture

- `TopologyJSON` as canonical state
- deterministic simulator as the execution engine
- `SimulationVerdict` as the grading boundary
- JSON-native attempt-state envelopes
- question packages and rubric rules tailored to architecture and distributed-systems evaluation

### Strategic recommendation

Treat Game Playground as the **delivery shell** and the deterministic evaluator as the **grading core**.

That means:

- the host embeds a simulator attempt
- the simulator exchanges a durable JSON attempt blob
- the evaluator produces stable verdicts and rubric results
- the host consumes summary flags for completion

This gives you compatibility with a Game Playground-style platform without inheriting packet tracer's domain-specific storage format or coupling grading to unversioned client state.

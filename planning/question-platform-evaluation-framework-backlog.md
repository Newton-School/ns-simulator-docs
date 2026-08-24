# Question Platform + Evaluation Framework Backlog

This document turns the current question-platform work, the environment-model docs, the worked example, and the generalized evaluation-framework ADR into an ordered implementation backlog.

The goal is not to list every possible future feature. The goal is to list the tickets we should actually pick next, in dependency order, to turn the current minimum question loop into a usable simulator-native assessment system.

---

## Planning Rules

- Ordered **chronologically by dependency**, not by topic.
- Priority is relative to the current date: **July 28, 2026**.
- The **primary** backlog below is simulator-owned work.
- Django / LMS / authoring-form work is listed separately as a **host-side companion backlog** so ownership stays explicit.

---

## What Is Already Done Enough To Build On

These are the foundations already present in the repo or already implemented in this workstream.

### Foundation A - Engine-side grading base

- `SimulationVerdict` and verdict projection exist.
- `evaluateSuite()` exists.
- `Rubric`, `gradeVerdict()`, and `gradeBatch()` exist.
- CLI `evaluate` and `grade` flows exist.

### Foundation B - Minimum question runtime loop

- `QuestionPackage` and `AttemptState` schemas exist.
- Host `launch-context` and `submit` seams exist.
- Question panel exists in the left sidebar.
- In-session grading and grade summary loop exists.
- Active question state exists in the renderer store.

### Foundation C - UX support

- Auto-layout exists and is tested.
- Question panel can remain mounted inside the left sidebar.

### Foundation D - Product-definition docs

- [system-design-leetcode-environment-model.md](../specs/system-design-leetcode-environment-model.md)
- [worked-example-order-processing-question.md](../specs/worked-example-order-processing-question.md)
- [adr-generalized-simulator-question-evaluation-framework.md](../design-decisions/adr-generalized-simulator-question-evaluation-framework.md)

These are important because the next tickets are no longer blocked by conceptual ambiguity. They are now implementation slices.

---

## Workstreams

The next tickets naturally group into six workstreams:

1. Runtime environment isolation
2. Constraint enforcement
3. Student-mode results and autosave
4. Evaluation-engine expansion
5. Question archetype unlocks
6. Editorial, exemplars, and progression

The ticket order below crosses these workstreams where dependencies require it.

---

## Ordered Ticket List

| Order | Priority | Ticket ID | Title | Depends on |
|---|---|---|---|---|
| 0 | Done | QEF-00 | Minimum question loop foundations | already built |
| 1 | P0 | QEF-01 | `EnvironmentProfile` type, launch injection, and store plumbing | QEF-00 |
| 2 | P0 | QEF-02 | Runtime gating across panels, controls, and chrome | QEF-01 |
| 3 | P0 | QEF-03 | Palette allowlist and forbidden-type enforcement | QEF-02 |
| 4 | P0 | QEF-04 | Locked scaffold nodes/edges and read-only editing rules | QEF-02 |
| 5 | P0 | QEF-05 | Constraint feedback surface and pre-submit validation | QEF-03, QEF-04 |
| 6 | P1 | QEF-06 | Attempt autosave emit / restore round-trip | QEF-01 |
| 7 | P1 | QEF-07 | Curated results surfaces and feedback-timing policy | QEF-02 |
| 8 | P1 | QEF-08 | Structural-check schema and topology-query MVP | QEF-05 |
| 9 | P1 | QEF-09 | Structural checks in grading pipeline and learner feedback | QEF-08 |
| 10 | P1 | QEF-10 | Comparative checks and baseline-verdict support | QEF-08 |
| 11 | P1 | QEF-11 | Suite fault overrides in evaluator | QEF-08 |
| 12 | P1 | QEF-12 | Resource-budget evaluator MVP (`nodeCount`, `maxTotalWorkers`) | QEF-05 |
| 13 | P2 | QEF-13 | Cost-model integration for budget questions | QEF-12, cost model spec |
| 14 | P2 | QEF-14 | Suite auto-seeder from FR/NFR/scale | QEF-09, QEF-12 |
| 15 | P2 | QEF-15 | End-to-end exemplar: guided open-build order-processing question | QEF-07, QEF-09, QEF-12 |
| 16 | P2 | QEF-16 | End-to-end exemplar: fix/debug question type | QEF-09, QEF-12 |
| 17 | P2 | QEF-17 | End-to-end exemplar: optimize question type | QEF-10 |
| 18 | P2 | QEF-18 | End-to-end exemplar: HA / Chaos question type | QEF-11 |
| 19 | P2 | QEF-19 | End-to-end exemplar: tradeoff / budget-box question type | QEF-13 |
| 20 | P2 | QEF-20 | Editorial unlocks and progression surfaces | QEF-15 |
| 21 | P3 | QEF-21 | Simulator-side author preview harness polish | QEF-15 |
| 22 | P3 | QEF-22 | Django / LMS contract hardening and submission lifecycle alignment | QEF-06, QEF-15 |

---

## Detailed Tickets

## QEF-00 - Minimum question loop foundations

**Status:** Done enough to build on

**What exists**

- Question runtime panel
- In-session grading
- Host question injection seam
- Attempt state in store
- Sample question path

**Why this matters**

It means the next tickets are not about inventing the platform from zero. They are about isolating the environment and deepening evaluation.

---

## QEF-01 - `EnvironmentProfile` type, launch injection, and store plumbing

**Priority:** P0

**Why now**

The rest of the student-mode product depends on a first-class environment lens. Without this, `PRACTICE`, `ASSIGNMENT`, and `AUTHOR` remain only document concepts.

**Scope**

- Define or finalize the runtime `EnvironmentProfile` type.
- Extend launch-context parsing to include it.
- Store the active profile in the renderer state.
- Provide a selector or hook for consuming it across panels.

**Acceptance criteria**

- A question can be launched with `AUTHOR`, `ASSIGNMENT`, or `PRACTICE`.
- The active profile is available to all gating surfaces without prop-drilling.
- If the host omits the profile, the runtime falls back safely to a deterministic default.

**Likely files**

- `src/renderer/src/utils/questionHostMessaging.ts`
- `src/renderer/src/store/useStore.ts`
- `src/renderer/src/components/layout/WorkspaceLayout.tsx`
- shared question-platform type location if introduced

---

## QEF-02 - Runtime gating across panels, controls, and chrome

**Priority:** P0

**Depends on:** QEF-01

**Why now**

Environment profile data is useless until it actually changes what the learner can see and do.

**Scope**

- Gate prompt, rubric timing, and live metrics.
- Gate run controls by mode.
- Gate author-only panels and full diagnostics.
- Gate chrome density and any author-preview-only affordances.

**Acceptance criteria**

- `PRACTICE`, `ASSIGNMENT`, and `AUTHOR` render meaningfully different surfaces from the same `QuestionPackage`.
- `ASSIGNMENT` hides grading-suite details.
- `AUTHOR` retains full visibility.

**Likely files**

- `src/renderer/src/components/question/QuestionPanel.tsx`
- `src/renderer/src/components/layout/WorkspaceLayout.tsx`
- `src/renderer/src/components/simulation/ResultsTray.tsx`
- `src/renderer/src/components/properties/PropertiesPanel.tsx`

---

## QEF-03 - Palette allowlist and forbidden-type enforcement

**Priority:** P0

**Depends on:** QEF-02

**Why now**

Bounding the design space is the first real product move from "freeform simulator" toward "LeetCode for system design."

**Scope**

- Filter the left palette to allowed types.
- Hide forbidden types.
- Block forbidden drag-and-drop or creation paths.
- Enforce the same rules when loading or mutating topology in question mode.

**Acceptance criteria**

- Student modes only expose the allowed component family.
- Forbidden node types cannot be placed.
- The runtime surfaces an explanation instead of failing silently.

**Likely files**

- `src/renderer/src/components/library/LibrarySidebar.tsx`
- `src/renderer/src/components/canvas/hooks/useFlowDnD.ts`
- serializer or validation seam if needed

---

## QEF-04 - Locked scaffold nodes/edges and read-only editing rules

**Priority:** P0

**Depends on:** QEF-02

**Why now**

Palette isolation alone is not enough for guided questions. Scaffold-owned structure needs first-class behavior.

**Scope**

- Mark scaffold-owned nodes and edges.
- Prevent dragging, deleting, or rewiring locked scaffold elements in student modes.
- Make locked scaffold properties read-only.
- Surface a visible lock affordance.

**Acceptance criteria**

- Locked scaffold elements are visibly identifiable.
- Student attempts to delete or modify them are blocked cleanly.
- `AUTHOR` can still edit everything.

**Likely files**

- `src/renderer/src/components/canvas/FlowCanvas.tsx`
- `src/renderer/src/components/properties/PropertiesPanel.tsx`
- `src/renderer/src/store/useStore.ts`

---

## QEF-05 - Constraint feedback surface and pre-submit validation

**Priority:** P0

**Depends on:** QEF-03, QEF-04

**Why now**

Once constraints exist, they need visible feedback. Otherwise students hit unexplained submission failures.

**Scope**

- Add a question-constraint validation pass before submit.
- Surface violations in a small, student-readable summary.
- Distinguish hard blockers from advisories.

**Acceptance criteria**

- Students can see why a submission is blocked.
- Constraint errors name the violated rule in plain English.
- Constraint feedback is consistent with eventual grading behavior.

**Likely files**

- `src/renderer/src/components/question/QuestionPanel.tsx`
- new constraint-validation utility
- `src/engine/analysis/question.ts` if shared constraint helpers are added

---

## QEF-06 - Attempt autosave emit / restore round-trip

**Priority:** P1

**Depends on:** QEF-01

**Why now**

The runtime already knows what an `AttemptState` is. The next missing piece is durable round-trip with the host.

**Scope**

- Emit autosave payloads to host.
- Restore prior attempt from launch-context.
- Keep test-run counts and timestamps coherent.

**Acceptance criteria**

- Reloading the same task restores student topology and attempt metadata.
- Autosave does not corrupt grading state.
- The host owns persistence; the simulator owns emission and restoration only.

**Likely files**

- `src/renderer/src/components/layout/WorkspaceLayout.tsx`
- `src/renderer/src/store/useStore.ts`
- `src/renderer/src/utils/questionHostMessaging.ts`

---

## QEF-07 - Curated results surfaces and feedback-timing policy

**Priority:** P1

**Depends on:** QEF-02

**Why now**

Without curated results, student modes still feel like the full simulator and dilute the lesson.

**Scope**

- Define student-mode result cards.
- Hide or de-emphasize raw author diagnostics.
- Respect `liveMetrics` and `rubricChecks` timing policy.

**Acceptance criteria**

- `PRACTICE` can show live high-signal feedback.
- `ASSIGNMENT` can show only the intended dry-run or post-submit signals.
- `AUTHOR` retains full trays and drilldowns.

**Likely files**

- `src/renderer/src/components/simulation/ResultsTray.tsx`
- `src/renderer/src/components/question/QuestionPanel.tsx`

---

## QEF-08 - Structural-check schema and topology-query MVP

**Priority:** P1

**Depends on:** QEF-05

**Why now**

The generalized evaluation framework depends on coarse structural validity. This is the first real evaluator slice beyond verdict metrics.

**Scope**

- Define the structural-check schema.
- Implement a small topology-query engine for required node types, forbidden node types, required paths, and forbidden shortcuts.
- Keep it deliberately narrow and deterministic.

**Acceptance criteria**

- The engine can evaluate a small set of broad structure rules.
- Checks are independent of layout or visual positions.
- JSON-authored and runtime-authored topologies are evaluated identically.

**Likely files**

- `src/engine/analysis/` new structural evaluator module(s)
- `src/engine/analysis/question.ts` or a sibling contract module

---

## QEF-09 - Structural checks in grading pipeline and learner feedback

**Priority:** P1

**Depends on:** QEF-08

**Why now**

Schema without integration does not change product behavior.

**Scope**

- Add structural rows to the grading output.
- Project them into the host contract cleanly.
- Show failing structural checks in student feedback.

**Acceptance criteria**

- Structural checks appear alongside behavioral checks.
- A failing structural gate can block passing the question even if metrics look healthy.
- Feedback names the architectural reason for failure.

**Likely files**

- `src/engine/analysis/question.ts`
- `src/engine/analysis/rubric.ts` or sibling grade aggregation path
- `src/renderer/src/components/question/QuestionPanel.tsx`

---

## QEF-10 - Comparative checks and baseline-verdict support

**Priority:** P1

**Depends on:** QEF-08

**Why now**

This unlocks `Optimize` questions and baseline-improvement grading without inventing a separate system later.

**Scope**

- Define comparative criterion types.
- Support baseline verdict storage and comparison.
- Add comparison rows to grading.

**Acceptance criteria**

- A question can ask "beat the baseline" on throughput, latency, or cost-like metrics.
- Baseline comparisons are deterministic and scenario-aware.

**Likely files**

- `src/engine/analysis/question.ts`
- new comparison evaluator module(s)

---

## QEF-11 - Suite fault overrides in evaluator

**Priority:** P1

**Depends on:** QEF-08

**Why now**

Without per-case fault injection, `HA / Chaos` questions remain only conceptual.

**Scope**

- Ensure suite case `faults` overrides are applied in grading prep.
- Validate them consistently.
- Surface scenario-failure explanations.

**Acceptance criteria**

- A question case can inject a node failure or similar fault.
- The topology is evaluated under that injected condition without modifying the student's authored topology permanently.

**Likely files**

- `src/engine/analysis/question.ts`
- evaluator preparation path
- CLI grading coverage

---

## QEF-12 - Resource-budget evaluator MVP (`nodeCount`, `maxTotalWorkers`)

**Priority:** P1

**Depends on:** QEF-05

**Why now**

This is the smallest budget slice that provides real tradeoff discipline without waiting for a full cost model.

**Scope**

- Enforce `maxNodeCount`.
- Enforce `maxTotalWorkers`.
- Decide whether the worker budget counts all nodes or only student-added nodes.

**Acceptance criteria**

- Budget rules can block pass/fail cleanly.
- The budget definition is explicit and documented.
- The student sees when the topology is over budget before or at submit.

**Likely files**

- question constraint evaluator
- grading aggregation
- student feedback UI

---

## QEF-13 - Cost-model integration for budget questions

**Priority:** P2

**Depends on:** QEF-12 and the cost model spec

**Why later**

Node-count and worker-count budgets deliver earlier value. Full cost-based questions need the separate cost model to be credible.

**Scope**

- Integrate the cost estimator output into question evaluation.
- Add `cost_within_budget` style checks.
- Support cost-aware feedback.

**Acceptance criteria**

- Cost budget can be evaluated deterministically from topology + resource config.
- Cost questions can fail on budget even if behavioral checks pass.

**Dependency note**

This depends on the broader cost-model work already specified elsewhere in the docs.

---

## QEF-14 - Suite auto-seeder from FR/NFR/scale

**Priority:** P2

**Depends on:** QEF-09, QEF-12

**Why later**

It improves authoring efficiency but is not required for the first real question runtime.

**Scope**

- Seed default scenarios from prompt scale.
- Seed default behavioral checks from NFRs.
- Allow author overrides.

**Acceptance criteria**

- A setter can author a usable first-pass question from structured prompt fields.
- Auto-seeded scenarios are transparent and editable.

---

## QEF-15 - End-to-end exemplar: guided open-build order-processing question

**Priority:** P2

**Depends on:** QEF-07, QEF-09, QEF-12

**Why now**

The worked example should become a real runnable exemplar before expanding the framework further.

**Scope**

- Turn the worked order-processing example into a full runtime question package and environment profile.
- Validate student-mode experience end-to-end.

**Acceptance criteria**

- The question can run in `PRACTICE` and `ASSIGNMENT`.
- It uses partial scaffold, curated palette, curated results, and layered evaluation.
- Good and bad student attempts produce meaningfully different outcomes.

---

## QEF-16 - End-to-end exemplar: fix/debug question type

**Priority:** P2

**Depends on:** QEF-09, QEF-12

**Why now**

The roadmap already emphasizes shipping one real question type completely before generalizing too far.

**Scope**

- Build one "fix the bottleneck" style question completely.
- Use it to validate structural and behavioral feedback.

**Acceptance criteria**

- Identical submissions score identically.
- Feedback identifies the failing scenario and repair logic.

---

## QEF-17 - End-to-end exemplar: optimize question type

**Priority:** P2

**Depends on:** QEF-10

**Why later**

This question type only becomes credible once baseline comparison exists.

**Scope**

- Author one "beat the baseline" question.
- Validate comparison feedback.

---

## QEF-18 - End-to-end exemplar: HA / Chaos question type

**Priority:** P2

**Depends on:** QEF-11

**Why later**

Needs faulted scenarios in the evaluator first.

**Scope**

- Author one failure-resilience question.
- Validate that the runtime and grading explain fault handling meaningfully.

---

## QEF-19 - End-to-end exemplar: tradeoff / budget-box question type

**Priority:** P2

**Depends on:** QEF-13

**Why later**

This needs credible budget constraints, ideally cost-aware ones.

**Scope**

- Author one question where behavior and budget compete.
- Validate that learners can pass behaviorally while failing budget, and vice versa.

---

## QEF-20 - Editorial unlocks and progression surfaces

**Priority:** P2

**Depends on:** QEF-15

**Why later**

Editorial is most useful once at least one high-quality exemplar question exists.

**Scope**

- Add post-pass or post-submit explanation surfaces.
- Add "what this question teaches" and "next recommended question" scaffolding.

**Acceptance criteria**

- Learners can see the intended lesson after finishing.
- Question progression can be staged by concept or difficulty.

---

## QEF-21 - Simulator-side author preview harness polish

**Priority:** P3

**Depends on:** QEF-15

**Why later**

Author preview matters, but the learner-facing runtime should be correct first.

**Scope**

- Improve author preview flow.
- Make profile swapping and sample package injection easier for setters.

---

## QEF-22 - Django / LMS contract hardening and submission lifecycle alignment

**Priority:** P3

**Depends on:** QEF-06, QEF-15

**Why later**

This is necessary for production integration, but it should not block the simulator-side product slices from becoming coherent first.

**Scope**

- Harden host event names and payload contracts.
- Align autosave, submit, grade, and restore lifecycle across systems.
- Confirm clear ownership boundaries.

**Out-of-scope note**

Authoring forms, marks, assignment lifecycle, and summative feedback remain Django-owned.

---

## Recommended Picking Order

If the team wants the shortest path to a real, defensible simulator-native question product, the next picks should be:

1. QEF-01
2. QEF-02
3. QEF-03
4. QEF-04
5. QEF-05
6. QEF-07
7. QEF-08
8. QEF-09
9. QEF-12
10. QEF-15

That sequence gets us from "minimum question loop" to "one real bounded question with environment isolation and layered evaluation."

---

## Django / Host Companion Backlog

These tickets are not simulator implementation tickets. They belong to the Django host side. They are listed here because the question platform only becomes fully testable locally once both sides of the seam exist.

### Ownership reminder

NS Simulator owns:

- `TopologyJSON` validation
- deterministic simulation execution
- `SimulationVerdict`
- rubric and check engine
- `QuestionPackage` and `AttemptState` schemas
- seeded reproducibility

Django backend owns:

- question authoring UI
- scenario storage
- student submission handling
- marks pipeline integration
- feedback generation
- assignment lifecycle

### Ordered Django ticket list

| Order | Priority | Ticket ID | Title | Depends on |
|---|---|---|---|---|
| D0 | P0 | DJQ-01 | Question package persistence and retrieval model | content contracts agreed |
| D1 | P0 | DJQ-02 | Dev host harness page for iframe launch / submit flow | DJQ-01 |
| D2 | P0 | DJQ-03 | Launch-context assembly service | DJQ-01, DJQ-02 |
| D3 | P0 | DJQ-04 | Submit ingestion endpoint and raw payload persistence | DJQ-02 |
| D4 | P1 | DJQ-05 | Attempt autosave persistence and restore pipeline | DJQ-03, DJQ-04 |
| D5 | P1 | DJQ-06 | Marks adapter from simulator contract / grade payload | DJQ-04 |
| D6 | P1 | DJQ-07 | Feedback generation from simulator-owned results | DJQ-04, DJQ-06 |
| D7 | P1 | DJQ-08 | Scenario storage and environment-profile selection in authoring UI | DJQ-01 |
| D8 | P2 | DJQ-09 | Assignment lifecycle integration for simulator questions | DJQ-05, DJQ-06, DJQ-07 |
| D9 | P2 | DJQ-10 | Contract-fixture test suite and local end-to-end smoke harness | DJQ-02, DJQ-04, DJQ-05 |

### DJQ-01 - Question package persistence and retrieval model

**Priority:** P0

**Why now**

Django cannot host the simulator runtime meaningfully until it can store and retrieve authored `QuestionPackage` payloads and related metadata.

**Scope**

- Store authored `QuestionPackage` JSON.
- Store environment-profile selection metadata.
- Store scenario references or inline scenario payloads, depending on host design.
- Expose a retrieval path for launch-context assembly.

**Acceptance criteria**

- Django can persist and retrieve a question package losslessly.
- Versioned payloads remain inspectable for debugging.
- The host can assemble a launchable question package without touching simulator internals.

### DJQ-02 - Dev host harness page for iframe launch / submit flow

**Priority:** P0

**Depends on:** DJQ-01

**Why now**

This is the fastest local integration loop for backend developers. It proves the message seam before full assignment plumbing exists.

**Scope**

- Add a Django dev-only page that embeds the simulator iframe.
- Listen for `ns-simulator:ready`.
- Post `ns-simulator:launch-context`.
- Listen for `ns-simulator:submit` and `ns-simulator:error`.
- Render received payloads on the page for inspection.

**Acceptance criteria**

- A developer can launch the simulator from Django locally.
- The page can inject a sample or stored question package.
- The page visibly shows returned submit payloads.

### DJQ-03 - Launch-context assembly service

**Priority:** P0

**Depends on:** DJQ-01, DJQ-02

**Why now**

Django owns the student-facing launch decision: which question, which prior attempt, which environment profile.

**Scope**

- Resolve the active question package.
- Resolve the appropriate environment profile (`PRACTICE`, `ASSIGNMENT`, `AUTHOR` preview).
- Attach prior attempt if one exists.
- Normalize the payload sent to the iframe.

**Acceptance criteria**

- Django can produce a valid `launch-context` payload for all supported modes.
- Prior attempts restore correctly through the same path.
- The payload contract is logged and inspectable in development.

### DJQ-04 - Submit ingestion endpoint and raw payload persistence

**Priority:** P0

**Depends on:** DJQ-02

**Why now**

The backend must store the simulator's result as the source-of-truth payload before deriving marks or feedback.

**Scope**

- Receive `ns-simulator:submit` payloads.
- Store raw `AttemptState`.
- Store raw host `contract`.
- Attach the submission to the correct student / assignment context.

**Acceptance criteria**

- Django persists the raw simulator-owned payloads without reinterpretation loss.
- Repeated identical submissions can be compared and audited.
- Submission failures are visible and recoverable in development.

### DJQ-05 - Attempt autosave persistence and restore pipeline

**Priority:** P1

**Depends on:** DJQ-03, DJQ-04

**Why now**

Once the simulator emits `AttemptState`, Django should own restoration so student work survives refresh and resume flows.

**Scope**

- Persist autosaved attempt blobs.
- Restore the latest attempt on relaunch.
- Track timestamps and test-run counters correctly.

**Acceptance criteria**

- A student can refresh and resume the same task with prior work intact.
- Autosave never overwrites a newer submitted attempt incorrectly.
- Restore uses the same `launch-context` contract as first launch.

### DJQ-06 - Marks adapter from simulator contract / grade payload

**Priority:** P1

**Depends on:** DJQ-04

**Why now**

Django owns the marks pipeline, but it should compute marks from simulator-returned evidence rather than re-implement simulator grading.

**Scope**

- Map the simulator `contract` and, where needed, stored grade payloads into backend marks.
- Define pass / fail and points logic at the backend policy layer.
- Keep raw simulator evidence attached for auditability.

**Acceptance criteria**

- Backend marks are reproducible from stored simulator payloads.
- Marks logic can evolve without changing simulator internals.
- Raw simulator outputs remain available for debugging and regrading.

### DJQ-07 - Feedback generation from simulator-owned results

**Priority:** P1

**Depends on:** DJQ-04, DJQ-06

**Why now**

The backend owns final learner-facing feedback generation, but it should derive it from simulator-returned evidence.

**Scope**

- Build feedback templates from failing checks, scenarios, and summary signals.
- Preserve simulator wording where appropriate for consistency.
- Support both concise marks feedback and richer post-task explanations.

**Acceptance criteria**

- Feedback references the failing scenario or rule, not generic failure text.
- Feedback can be reproduced from stored simulator results.
- Backend feedback does not require re-running the simulator.

### DJQ-08 - Scenario storage and environment-profile selection in authoring UI

**Priority:** P1

**Depends on:** DJQ-01

**Why now**

Django owns question authoring and needs explicit storage for which scenarios and environment modes are attached to a question.

**Scope**

- Store scenario definitions or references.
- Let authors choose deployment profile defaults.
- Preserve authored environment constraints separately from simulator runtime state.

**Acceptance criteria**

- A setter can choose whether a question launches in `PRACTICE`, `ASSIGNMENT`, or author preview.
- Scenario metadata is durable and editable in backend-owned UI.

### DJQ-09 - Assignment lifecycle integration for simulator questions

**Priority:** P2

**Depends on:** DJQ-05, DJQ-06, DJQ-07

**Why later**

The launch / submit seam and raw persistence should be correct before full assignment-state integration is attempted.

**Scope**

- Attach simulator questions to real assignments.
- Respect due dates, submission state, and attempt policy.
- Integrate marks and feedback into the assignment lifecycle.

**Acceptance criteria**

- Simulator-backed questions behave like first-class assignment items in Django.
- Submission and reopen rules are consistent with the rest of the platform.

### DJQ-10 - Contract-fixture test suite and local end-to-end smoke harness

**Priority:** P2

**Depends on:** DJQ-02, DJQ-04, DJQ-05

**Why later**

This is the right long-term local testing loop once the basics exist.

**Scope**

- Store stable simulator-generated grade fixtures for backend tests.
- Add backend tests for marks mapping, attempt persistence, and feedback generation.
- Add one end-to-end local smoke flow using the dev host harness page.

**Acceptance criteria**

- Django tests can run against fixed simulator fixtures without launching the engine every time.
- A developer can manually verify launch, submit, persist, restore, and grade locally through the iframe harness.

### Relationship to simulator ticket QEF-22

`QEF-22` remains the simulator-side contract-hardening ticket.

The Django-side companion set is:

- DJQ-02 for local host harness
- DJQ-03 / DJQ-04 / DJQ-05 for launch, submit, and restore
- DJQ-06 / DJQ-07 / DJQ-09 for marks, feedback, and assignment lifecycle
- DJQ-10 for repeatable local testing

This keeps the seam owned on both sides without mixing the responsibilities.

---

## Non-simulator Dependencies To Track

These are important, but not simulator implementation tickets:

- host-side editorial presentation if not rendered in simulator
- any broader LMS workflow outside simulator question delivery
- any institutional grading-policy rules not expressible in simulator payloads

These should be tracked in the host system backlog, not buried inside the simulator implementation tickets.

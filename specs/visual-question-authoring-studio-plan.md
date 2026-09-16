# Visual Question Authoring Studio — Product and Implementation Plan

**Status:** Proposed  
**Date:** 2026-09-16  
**Scope:** Planning only; no implementation is implied by this document.

## 1. Executive decision

Build a dedicated **Question Studio** inside the simulator's `AUTHOR` experience.
Authors should construct the teaching brief, learner starting state, scenarios,
grading obligations, reference solution, and intended bad solutions through guided
UI. The studio compiles that author intent into the existing canonical artifacts:

1. a validated `QuestionPackage`
2. learner-facing `question_text` HTML
3. ordered Newton/Django test-case rows
4. `initial_game_state`
5. reference and gamed topology fixtures

Django remains the deployment and lifecycle system of record. The simulator owns
the authoring surface because it already owns the canvas, component catalogue,
schema, validator, simulation engine, and deterministic grader. The first release
exports artifacts for Django. A later release can let Django launch the studio and
save or publish through a host API.

The important product distinction is:

> Authors create a **teaching and grading contract**. JSON rows are compiled
> deployment output, not the primary authoring interface.

## 2. Why the current workflow needs a rethink

The repository already has the difficult engine foundations:

- a versioned `QuestionPackage`
- structured, semantic, and runtime grading contracts
- a Newton row-to-package adapter
- schema and cross-field authoring validation
- reference-versus-gamed validation tooling
- a full topology canvas and simulation controls

The remaining problem is author experience. A setter currently has to keep several
representations aligned manually:

- source/interview prompt and translation worksheet
- `question.json`
- learner-facing `question_text` HTML
- one `SIMULATOR_CONFIG` row
- multiple `STRUCTURAL_RULE`, `SEMANTIC_CRITERION`, and `RUBRIC_CHECK` rows
- scaffold, reference, and gamed topologies

This creates four predictable failures:

1. **Schema-first thinking.** Authors start from field names instead of the lesson,
   intended bad design, and evidence needed to reject it.
2. **Representation drift.** The validated `question.json` can differ from the rows
   that actually ship to the learner.
3. **Weak discrimination.** It is easy to write plausible checks without proving
   that the reference passes and a realistic wrong answer fails.
4. **Expert-only error recovery.** A bad metric path, component type, workload
   override, or runtime-state token is currently corrected by reading manuals or
   TypeScript schemas.

### Evidence from the current canonical bank

The 14 canonical questions are all `open-build` and currently use 14 suite cases in
total. Their most common authoring primitives are:

- `requires_component`: 12 uses
- `requires_single_source`: 10 uses
- `requires_path`: 1 use
- `stateTransition`: 8 uses
- `storageFit`: 5 uses
- `guardedPath` and `placement`: 3 uses each
- invariant checks: 13 uses
- p99 checks: 5 uses

This suggests an MVP can cover the real bank with a small set of well-designed
composers, while uncommon schema options remain behind progressive disclosure.

## 3. Product principles

### 3.1 Intent before syntax

The primary controls should read like architecture statements:

- `Require at least [1] [message broker]`
- `Traffic from [API service] must pass through [cache] before [key-value store]`
- `Under every grading scenario, [p99 latency] must be [below] [100 ms]`
- `The runtime trace must contain [reservation → committed] at least [1] time`

The compiler maps those statements to typed rules. Authors should never need to
remember `guardedPath`, `summary.latency.p99`, or other wire-level tokens.

### 3.2 One source of truth, several generated artifacts

The studio stores a versioned `QuestionAuthoringProject`. It never stores Django
rows as an independently editable copy. A pure compiler generates the package and
all deployment artifacts from the project.

### 3.3 Progressive disclosure

Common choices appear first. Advanced runtime-state matching, custom environment
capabilities, topology metric selectors, and low-level fault parameters appear only
when the author chooses an advanced path.

### 3.4 Traceability is part of authoring

Every learner-facing requirement must be marked as one of:

- structural
- semantic
- simulation
- justification
- narrative only
- explicitly deferred

Gradeable requirements must link to one or more actual checks. The studio should
warn about ungraded NFRs and checks that have no learner-facing requirement.

### 3.5 Proof, not plausibility

A question is only **publish ready** when a reference topology passes and at least
one plausible gamed topology fails on its intended obligation. The studio turns the
existing dual-topology rule into a first-class visual workflow.

### 3.6 Honest simulation boundaries

Domain, concept, component, and trait choices should surface the existing support
ledger. Guided or presentational-only behavior must show an explanation before an
author promises it in the prompt or grades it as simulated evidence.

### 3.7 Safe defaults and deterministic output

IDs, descriptions, points, suite names, seeds, request weights, and payload sizes
may be derived where the current Newton adapter already derives them. The generated
result must be deterministic and visible before export.

## 4. Product boundary

### Recommended ownership split

| Concern                                                                             | Owner                                                                           |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Visual authoring, canvas editing, schema validation, simulation, grading proof      | NS Simulator Question Studio                                                    |
| Draft/published record, permissions, peer review, assignment mapping, freeze policy | Django                                                                          |
| Canonical question and row contracts                                                | Shared through versioned JSON contracts and golden fixtures                     |
| Initial V1 transfer                                                                 | Download/copy export                                                            |
| Later transfer                                                                      | Django launches the studio with a draft and receives a compiled publish payload |

This deliberately revises the older assumption that Django must render every
authoring form itself. Django still owns authoring lifecycle, but the simulator is
the right place to render the domain-specific editor.

### Non-goals for the first release

- free-form collaborative editing
- assignment scheduling, peer-review workflow, or question freezing
- automatic generation of a good grading contract from a raw prompt
- server-side re-grading or anti-tamper work
- a general-purpose JSON/schema form builder
- editing every possible advanced engine field in the first screen
- publishing directly into production Django

## 5. Author journey

The studio uses seven stages. Authors may move backward freely; readiness is shown
continuously rather than enforced as a brittle linear wizard.

### Stage 1 — Frame the lesson

The author enters or imports the source prompt, then defines one sentence:

`The student must build/fix <specific path> so that <specific lesson> holds under <specific workload>.`

Controls:

- question title and derived ID
- difficulty and estimated time
- question type and learner entry format as separate choices
- one or two dominant domains
- one to three concepts
- workload category
- intended bad design
- split-question advisory when several independent lessons are detected manually

The studio does not need an LLM to make this useful. It can provide templates,
examples, and deterministic warnings first. Assisted classification can be a later,
optional feature.

### Stage 2 — Write the learner brief

Use structured fields rather than raw HTML:

- scenario framing paragraphs
- functional requirements as reorderable cards
- NFR targets with metric, operator, value, and unit controls
- real-world scale fields
- additional context and justification prompts

A learner preview renders the final content. The compiler HTML-escapes authored
text and generates consistent `question_text` HTML. Raw HTML is not the main editing
surface.

Each FR and NFR becomes a requirement card with a stable internal ID used by the
traceability view. The stable ID is authoring metadata and is not required in the
runtime `QuestionPackage`.

### Stage 3 — Choose the learner starting state

The author selects:

- blank canvas
- partial scaffold
- broken scaffold
- complete/locked lab
- baseline to optimize

The current topology canvas is embedded as the scaffold editor. Authors can:

- place and configure components visually
- lock specific nodes and edges
- choose allowed or forbidden palette components
- set node, worker, resource, and budget constraints
- preview effective learner edit permissions under `ASSIGNMENT`

Entry formats whose learner workflow is still disabled in the runtime must be
labelled **contract available, learner shell not yet released**. The authoring UI
must not make schema availability look like shipped learner behavior.

### Stage 4 — Build grading scenarios

Scenarios are displayed as cards and edited through a visual workload and fault
composer.

Each card contains:

- scenario name, stable ID, and description
- deterministic seed
- duration and warmup
- workload pattern and base RPS
- request mix table with percentage bars and size controls
- optional keyspace and skew settings
- optional fault timeline with target, mode, start, and duration
- student visibility

The UI shows real-world display scale beside injected simulation scale so authors
must acknowledge any compression. A small workload preview graph makes constant,
bursty, spike, sawtooth, and diurnal patterns understandable without reading the
underlying JSON.

Current rubric checks apply to every suite case. The MVP must say **applies to all
scenarios** rather than exposing a per-scenario selector the contract cannot honor.
Runtime semantic criteria may expose `where.caseId` in the advanced section because
that scope exists in the current contract.

### Stage 5 — Compose the grading contract

The default view is a traceability board, not a list of JSON rows.

Each requirement card shows:

- learner-facing statement
- classification
- linked check cards
- points and hard-fail behavior
- whether the check is supported, valid, and proven

Authors add checks from three galleries:

#### Topology shape

- require or forbid a component
- require one traffic source
- require an edge or path
- require a connected graph or redundancy
- minimum/maximum node or component count

#### Design meaning

- placement
- guarded path
- fanout
- storage fit
- forbid unless justified
- advanced runtime transition
- advanced runtime sequence

#### Measurable outcome

- latency percentile
- throughput
- error rate
- maximum utilization
- invariant violation count
- conservation and Little's Law checks
- supported reservation, lock, retry, and rate-limit counters
- topology totals where a rubric check is more appropriate than a structural rule

The UI uses controlled metric and operator choices, formats percent values in human
units, and shows the exact compiled meaning below each card. Authors can reorder
checks visually, but output ordering remains config → structural → semantic → rubric.

### Stage 6 — Prove discrimination

The verification lab has canvas snapshots for:

- reference design
- gamed design A
- optional gamed designs B…N

For each gamed design, the author names the misconception, such as “cache is beside
the app instead of on the read path.” They also choose the check expected to catch
it.

Running verification produces a matrix:

| Design    | Structural | Semantic  | Scenario outcomes | Expected discriminator | Ready  |
| --------- | ---------- | --------- | ----------------- | ---------------------- | ------ |
| Reference | pass       | pass      | pass              | —                      | yes/no |
| Gamed A   | pass/fail  | pass/fail | pass/fail         | caught/missed          | yes/no |

The studio highlights accidental failures separately from the intended failure. A
gamed design failing only because its topology is invalid is not proof of a good
grading contract.

### Stage 7 — Review and export

The final screen contains:

- learner preview
- requirements-to-check traceability summary
- support-ledger warnings
- validation and verification status
- generated artifact tabs
- export actions

Artifact tabs:

1. `question.json`
2. `question_text` HTML
3. Django fields
4. ordered Django rows
5. reference topology
6. gamed topologies
7. complete authoring bundle

Authors may download the authoring project at any time. **Publish-ready Django
export** is blocked by errors and missing proof; warnings require acknowledgement.
Generated JSON is viewable and copyable, but read-only in V1.

## 6. Proposed layout

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Question Studio   URL Shortener v1   Saved     Preview learner   Export      │
├──────────────┬───────────────────────────────────────────┬───────────────────┤
│ 1 Frame      │                                           │ Readiness  8/10    │
│ 2 Brief      │          Active-stage workspace           │ ✓ schema           │
│ 3 Start      │     form / traceability / canvas / lab     │ ! unlinked NFR     │
│ 4 Scenarios  │                                           │ ✕ gamed design     │
│ 5 Grade      │                                           │   still passes      │
│ 6 Prove      │                                           │                   │
│ 7 Export     │                                           │ Problems by stage  │
├──────────────┴───────────────────────────────────────────┴───────────────────┤
│ Back                                  Save draft                 Continue    │
└──────────────────────────────────────────────────────────────────────────────┘
```

The right rail is always actionable: selecting a diagnostic navigates to and
focuses the exact field or card. It should never be a passive wall of validator
text.

## 7. State and data contract mapping

### 7.1 Authoring project

The strict runtime package cannot represent incomplete forms or design rationale.
Introduce a separate, versioned draft contract:

```ts
interface QuestionAuthoringProject {
  artifactVersion: '1.0'
  projectId: string
  updatedAt: string
  source: {
    originalPrompt?: string
    sourceReference?: string
    assumptions: string[]
    lessonStatement: string
    intendedBadDesign: string
  }
  question: QuestionDraft
  requirements: AuthorRequirement[]
  assets: {
    scaffoldTopology?: TopologyJSON
    referenceTopology?: TopologyJSON
    gamedTopologies: Array<{
      id: string
      label: string
      misconception: string
      expectedCheckId: string
      topology: TopologyJSON
    }>
  }
  verification?: VerificationSnapshot
  ui?: {
    activeStage?: AuthoringStage
    advancedSections?: string[]
  }
}
```

`QuestionDraft` is a deliberately tolerant, explicit draft schema. Do not use an
unbounded `DeepPartial<QuestionPackage>`; that would weaken field-level typing and
make migrations opaque.

### 7.2 Requirement traceability

```ts
interface AuthorRequirement {
  id: string
  text: string
  sourceStatementIds?: string[]
  classification:
    | 'structural'
    | 'semantic'
    | 'simulation'
    | 'justification'
    | 'narrative'
    | 'deferred'
  linkedObligationIds: string[]
  deferReason?: string
}
```

This metadata is valuable during authoring and review but should not be silently
added to the runtime package until that contract explicitly adopts it.

### 7.3 Pure compiler pipeline

```text
QuestionAuthoringProject
          │
          ▼
 compileAuthoringProject()
          │
          ├── QuestionPackage
          ├── questionTextHtml
          ├── NewtonQuestionFields
          ├── NewtonTestCaseRow[]
          ├── fixture topologies
          └── AuthoringDiagnostic[]
```

The compiler must call the existing `QuestionPackageSchema` and
`validateAuthoredQuestion`; it must not duplicate their rules.

### 7.4 Shared Newton row codec

Before building the UI, consolidate the currently separate import/export logic
into a shared pure module:

```ts
type NewtonTestCaseRowSpec =
  | SimulatorConfigRow
  | StructuralRuleRow
  | SemanticCriterionRow
  | RubricCheckRow

compileQuestionPackageToNewtonRows(package, options): NewtonTestCaseRow[]
parseNewtonRowsToQuestionPackage(seed): QuestionPackage
```

The Newton runtime adapter, guide generator, and Question Studio must all consume
this codec. A golden round-trip test must prove:

```text
package → rows → normalized package = normalized original package
```

This is the main architectural prerequisite. Without it, the visual studio becomes
a third source of truth.

### 7.5 State ownership

| State                              | Owner                          | Notes                                                     |
| ---------------------------------- | ------------------------------ | --------------------------------------------------------- |
| Authoring draft and history        | `useQuestionAuthoringStore`    | Separate from learner/runtime topology state              |
| Active canvas nodes/edges          | existing topology store        | One authoring topology loaded at a time in V1             |
| Scaffold/reference/gamed snapshots | authoring store                | Snapshot canvas before switching tabs                     |
| Compilation result                 | derived selector/service       | Never hand-edited or persisted as canonical state         |
| Field validation                   | local/derived                  | Immediate feedback                                        |
| Package diagnostics                | compiler                       | Schema + authoring validator + support ledger             |
| Verification runs                  | authoring worker orchestration | Persist only digest/signatures needed to detect staleness |
| Exported files                     | file service                   | Web and Electron targets                                  |

For V1, reusing the global topology store is acceptable if the editor explicitly
snapshots the active topology before changing scaffold/reference/gamed tabs. If the
product later needs side-by-side editable canvases, move React Flow state behind a
scoped store provider rather than creating parallel globals.

## 8. Screen-to-component mapping

The studio should be a sibling of `WorkspaceLayout`, selected by a small app shell,
rather than adding more conditional branches to the already large runtime layout.

| Screen/area          | Proposed component         | Responsibility                                                                  | Reuse                                      |
| -------------------- | -------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------ |
| App surface selector | `AppShell`                 | Choose simulator workspace or Question Studio in AUTHOR mode; deep-link support | new, mounts existing `WorkspaceLayout`     |
| Studio frame         | `QuestionStudioShell`      | header, stage rail, workspace, diagnostics rail, navigation guards              | new                                        |
| Project header       | `AuthoringHeader`          | project name, save state, import, learner preview, export                       | file service, branding/theme controls      |
| Stage rail           | `AuthoringStageRail`       | progress and error counts by stage                                              | new                                        |
| Diagnostics          | `AuthoringReadinessPanel`  | actionable errors, warnings, proof status                                       | existing diagnostics + new compiler output |
| Frame                | `LessonFrameEditor`        | metadata, lesson statement, domains, concepts, intended bad design              | support ledger, catalogue metadata         |
| Brief                | `QuestionBriefEditor`      | structured prompt, FR/NFR/scale cards, learner preview                          | question prompt types                      |
| Starting state       | `LearnerStartEditor`       | entry format, scaffold canvas, locks, constraints, assignment preview           | `FlowCanvas`, library, properties panel    |
| Scenarios            | `ScenarioSuiteEditor`      | scenario list and visibility                                                    | new container                              |
| Scenario card        | `ScenarioComposer`         | workload, request mix, global config, fault timeline                            | simulation controls model/defaults         |
| Workload visual      | `WorkloadShapePreview`     | small deterministic pattern chart                                               | new pure visualization                     |
| Grading              | `TraceabilityBoard`        | requirements and linked obligations                                             | new                                        |
| Rule gallery         | `ObligationGallery`        | choose structural, semantic, runtime, or metric template                        | schema-backed templates                    |
| Rule card            | `ObligationSentenceEditor` | kind-specific controlled inputs and compiled sentence                           | new per-kind editors                       |
| Proof                | `DiscriminationLab`        | reference/gamed tabs, run orchestration, result matrix                          | canvas, worker, grader                     |
| Export               | `PublishReview`            | readiness summary and generated artifacts                                       | compiler/row codec                         |
| JSON display         | `GeneratedArtifactViewer`  | read-only formatted copy/download                                               | new                                        |

## 9. Validation and readiness model

Use four layers, all visible in the right rail:

### Layer 1 — Field validity

Examples: required title, positive RPS, request weights total 100%, valid threshold
units, fault start before simulation end.

### Layer 2 — Contract validity

Run the existing Zod schemas and cross-field authoring validator. Errors point back
to source controls through stable field paths.

### Layer 3 — Teaching alignment

Examples:

- unlinked gradeable requirement
- NFR without a supporting metric check
- check with no requirement
- domain/support-tier mismatch
- real-to-sim scale ratio changed without preserving traffic character
- learner prompt promises edge physics while the environment uses connector edges
- hidden suite has no representative dry-run case when the author intends practice

### Layer 4 — Empirical proof

- reference topology is valid
- reference passes all hard requirements and threshold
- each gamed topology is valid
- at least one gamed topology fails
- expected discriminator actually catches each named misconception
- results use deterministic seeds
- proof becomes stale when the project, topology, suite, or grading contract changes

### Readiness states

- **Draft:** incomplete is allowed and saveable
- **Valid:** compiles into a `QuestionPackage`
- **Verified:** dual-topology proof is current
- **Publish ready:** valid, verified, traceable, and free of blocking diagnostics

## 10. Import, persistence, and export

### Project persistence

Use a distinct extension such as `.dsds-question-project.json` with an artifact
discriminator. Autosave may use local browser storage initially; explicit file save
is the portable source of truth for V1.

### Import paths

V1 should support:

- new blank project
- start from a curated question template
- import a full `question.json`
- import a complete authoring project

Importing Django rows is desirable once the shared row codec is extracted. It
should be included before asking existing authors to migrate.

An import must never silently discard a valid field the editor cannot display.
Unsupported-but-preserved data should appear in an **Advanced imported fields**
panel and block lossy re-export until handled.

### Export behavior

- deterministic key and row ordering
- JSON output formatted consistently
- derived IDs previewed before export
- one-click copy per Django row
- complete Markdown admin guide export for the current manual workflow
- bundle download containing package, topologies, guide, and verification report
- re-import of that bundle produces an equivalent project

## 11. Implementation phases and tickets

### Phase 0 — Contract foundation

This phase is mandatory before UI work.

#### QAS-001 — Extract and type the Newton row codec

**Targets:** new engine-side authoring module, `newtonGamePlayground.ts`, Django
guide generator.

**Acceptance:** import and export use one implementation; all existing Newton row
tests remain green.

#### QAS-002 — Add golden package/row round-trip fixtures

Use all 14 canonical question-bank packages plus focused minimal rows.

**Acceptance:** normalized package equality, deterministic output, preserved stable
IDs, and friendly error paths.

#### QAS-003 — Define `QuestionAuthoringProject` and compiler

Include schema versioning, migrations, requirement traceability, topology assets,
and pure generated outputs.

**Acceptance:** incomplete drafts parse as drafts; complete drafts compile through
the existing strict package and authoring validators.

### Phase 1 — Thin vertical slice

Deliver one end-to-end path before implementing every rule kind.

#### QAS-004 — App shell and project persistence

Add the AUTHOR-only studio surface, open/save project, unsaved-change guard, and
stage/readiness navigation.

#### QAS-005 — Lesson frame and structured brief

Support core metadata, FR/NFR/scale cards, learner preview, derived IDs, and safe
HTML generation.

#### QAS-006 — Starting-state canvas

Support blank and scaffolded starts, node/edge locks, constraints, snapshot
switching, and learner-permission preview.

#### QAS-007 — Scenario composer

Support multiple cases, deterministic seeds, constant/bursty/spike/sawtooth
patterns, request mix, and the current single-fault controls. Reuse existing
simulation-control normalization.

#### QAS-008 — Core obligation composers

First support the current bank's common set:

- structural: `requires_component`, `requires_single_source`, `requires_path`
- semantic: `placement`, `guardedPath`, `fanout`, `storageFit`,
  `forbidUnjustified`, `stateTransition`
- rubric: current catalogue of simulation/invariant metric selectors

Other supported structural kinds can follow as small sentence-editor additions.

#### QAS-009 — Live compilation and diagnostics

Compile on change with debouncing, map diagnostic paths to controls, show support
ledger notes, and implement readiness states.

#### QAS-010 — Discrimination lab

Build reference/gamed topology tabs, deterministic batch verification, expected
discriminator matching, stale-proof detection, and the results matrix.

#### QAS-011 — Review and export

Generate `question.json`, safe prompt HTML, Django fields, ordered rows, fixture
files, Markdown guide, and full bundle. Enforce publish-ready gates.

### Phase 2 — Full contract coverage and migration

#### QAS-012 — Complete kind coverage

Add uncommon structural kinds, `stateSequence`, justification editors, budget
controls, advanced environment capability overrides, baseline verdict capture, and
all fault forms supported by the schema.

#### QAS-013 — Lossless legacy import

Import full packages and Django row sets, surface unsupported extensions, and prove
lossless re-export with the canonical bank.

#### QAS-014 — Templates and cloning

Add curated templates such as read-heavy cache, async decoupling, fanout, storage
fit, scaffold repair, and correctness under contention. Templates should contain
instructional placeholders, not hidden magical checks.

#### QAS-015 — Learner-experience previews

Preview `AUTHOR`, `ASSIGNMENT`, and `PRACTICE`, including prompt visibility,
scaffold locks, editable component palette, edges, resources, and rubric timing.

### Phase 3 — Django lifecycle integration

#### QAS-016 — Host launch/save contract for drafts

Django launches the studio with a versioned draft or published package and receives
save payloads without needing to understand simulator internals.

#### QAS-017 — Publish handoff

Send compiled fields and rows to a Django staging record, show a diff against the
currently published version, and require normal backend permissions and peer review.

#### QAS-018 — Versioning and audit

Record compiler version, package version, verification digest, author/reviewer, and
published artifact hashes. A post-freeze edit creates a new version rather than
mutating the reviewed question.

## 12. Acceptance criteria

### Product-level MVP

- A content author can create a gradeable question without typing JSON.
- The author can visually create or import a scaffold, reference design, and gamed
  design.
- Every gradeable requirement is visibly linked to a compiled obligation.
- The UI prevents invalid enum, component, metric, operator, and unit combinations.
- A complete draft compiles into the existing `QuestionPackage` without modifying
  engine grading semantics.
- The reference passes and the intended bad design fails before the project becomes
  publish ready.
- Generated rows load through the Newton adapter into a package equivalent to the
  compiled package.
- Exported artifacts can be pasted into the current Django workflow with no manual
  JSON editing.

### Accessibility

- All stages and cards are keyboard navigable.
- Drag/reorder has button and keyboard alternatives.
- Visual check status is not communicated by color alone.
- Inputs have persistent labels and errors are associated through ARIA attributes.
- Canvas-only bindings have searchable select/list alternatives.
- Focus moves to the selected diagnostic and returns predictably from dialogs.

### Performance

- Field editing remains immediate; strict compilation is debounced or moved off the
  interaction-critical path.
- Verification runs in the worker and can be cancelled.
- Large topology snapshots are stored structurally, not duplicated in undo history
  on every keystroke.

## 13. Integration and QA checklist

### Contract tests

- package → rows → package golden round trips
- authoring project schema and migration tests
- deterministic compiler output snapshots
- every sentence-editor option compiles to a valid typed rule
- diagnostic paths map to stable UI targets
- question-text generator escapes user content

### Fixture tests

- import and re-export all 14 canonical question-bank packages
- reference passes and gamed fails remain unchanged after round-trip
- row order is always config → structural → semantic → rubric
- stable authored IDs are preserved
- derived IDs are collision-safe and deterministic

### Component tests

- add, duplicate, reorder, and remove requirement/check/scenario cards
- percentage and unit conversions
- scenario pattern conditional fields
- support-ledger advisories
- stale-verification state after relevant edits
- unsaved project guard
- export gate and warning acknowledgement

### End-to-end flows

1. Blank project → one scenario → one structural rule → one invariant check →
   reference/gamed proof → export.
2. Import canonical `question.json` → edit a threshold → reverify → export rows.
3. Import Django rows → reconstruct package → preview learner experience.
4. Partial scaffold → lock nodes/edges → confirm ASSIGNMENT preview cannot edit them.
5. Invalid metric/support promise → navigate from diagnostic to corrective control.
6. Save project in web and Electron → reopen with identical compiled output.

### Manual author review

- A setter unfamiliar with the JSON DSL can finish the vertical-slice flow using
  labels and examples only.
- An experienced author can inspect the exact compiled meaning without leaving the
  studio.
- A reviewer can understand the dominant lesson, traceability, and discrimination
  proof without opening raw JSON.

## 14. Risks and mitigations

| Risk                                                  | Mitigation                                                                                              |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| UI, package, and Django rows drift                    | One shared compiler/row codec and golden round-trip fixtures                                            |
| Incomplete drafts do not fit strict runtime schemas   | Separate versioned draft schema; strict compile only at validation/export boundaries                    |
| A generic form exposes engine jargon                  | Intent-based sentence editors and curated galleries                                                     |
| Authors overfit checks to one reference design        | Multiple gamed designs, intended-misconception labels, and accidental-failure reporting                 |
| Unsupported concepts are presented as simulated       | Support-ledger badges and blocking alignment diagnostics for false promises                             |
| Existing imported fields are lost                     | Preserve unsupported fields and block lossy re-export                                                   |
| Multiple topology variants corrupt the canvas state   | Explicit snapshot/load controller in V1; scoped canvas stores if side-by-side editing is later required |
| Question Studio bloats `WorkspaceLayout`              | Sibling application surface with dedicated authoring store and components                               |
| Raw HTML creates preview/security issues              | Structured prompt authoring, escaped HTML generation, sandboxed advanced preview                        |
| Client-side grading is mistaken for secure assessment | Keep a visible deployment warning; server re-grade is a separate platform milestone                     |

## 15. Recommended delivery cut

The first useful release should not be “all forms implemented.” It should be a
thin, trustworthy loop:

```text
Frame lesson
  → write brief
  → create one scenario
  → add common check cards
  → build reference and one gamed design
  → prove discrimination
  → export valid Django rows
```

Complete the shared compiler and row codec first, then ship this loop using the
rule kinds already dominant in the question bank. That gives authors an immediate
no-JSON workflow and establishes the architecture needed for advanced rule kinds,
templates, and direct Django publishing without rework.

## 16. Success measures

Capture a baseline from the current manual workflow, then track:

- median time from blank project to first valid package
- percentage of questions authored without raw JSON edits
- schema/metric errors caught before Django preview
- percentage of gradeable requirements linked to checks
- percentage of questions with current dual-topology proof
- row/package drift incidents
- number of review cycles before publish readiness
- successful import/export rate for existing canonical questions

The strongest initial success criterion is binary: a non-engineering content author
can produce a Newton-ready, validated, discriminatory question and its JSON rows
without learning the JSON DSL.

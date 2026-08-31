# Repo Hardening And Feasibility Review

Date: 2026-08-31

Scope: codebase robustness, simulator fidelity, UI/UX, authoring workflow, and question-family feasibility.

This document converts the current repo review into an actionable hardening plan. It intentionally holds a few product choices constant for now so the next steps stay focused.

## 1. Decisions Held Constant

- Keep `SHOW_BLUEPRINTS_AND_LABS = false` for now. Labs and blueprints exist as concepts and sample assets, but they are not part of the immediate product surface.
- Keep `SHOW_JUSTIFICATION = false` for now. Correctness-heavy questions must therefore be treated as partial capability, not as fully productized flows.
- Do not depend on `system-design-simulator-questions/questions/...` or any absolute `/Users/...` path for fresh-author workflows. That path is personal working context, not a portable authoring contract.

These are not bugs in this document. They are deliberate scope boundaries.

## 2. Immediate Repair Completed

The repo had one failing test:

- `src/renderer/src/utils/experienceEnvelope.test.ts`

The failure came from the test expecting LAB experiences to expose `['question', 'labs']` even though `SHOW_BLUEPRINTS_AND_LABS = false` intentionally filters the `labs` tab out. The test has been aligned with the current product decision.

Current health after the fix:

- `npm test`: `98` files passed, `677` tests passed, `2` skipped
- `npm run typecheck`: passed
- `npm run build`: passed
- the main renderer entry chunk is about `563.64 kB` after feature-boundary lazy loading for question, library, scenario, settings, and results-adjacent surfaces

## 3. Fresh-Author Portability Problem

### 3.1 The problem

Today, multiple docs point to:

- `system-design-simulator-questions/questions/...`
- absolute machine-local paths such as `/Users/hritvikmohan/...`

That works for personal notes and local authoring, but it does not work for a fresh author who only has this repo. A new author should not need your personal sidecar directory to learn:

- what a good translated question looks like
- what files need to exist
- what the reference and gamed topologies are
- how to validate a question locally

### 3.2 The solution

Create a self-contained authoring pack inside this repo.

Recommended structure:

- `ns-simulator-docs/examples/question-bank/`
- `ns-simulator-docs/examples/question-bank/<question-id>/question.json`
- `ns-simulator-docs/examples/question-bank/<question-id>/reference-topology.json`
- `ns-simulator-docs/examples/question-bank/<question-id>/gamed-topology.json`
- `ns-simulator-docs/examples/question-bank/<question-id>/django-admin-assignment.md`
- `ns-simulator-docs/examples/question-bank/<question-id>/README.md`

Rules:

- All docs must link only to repo-relative assets.
- The authoring runbook must assume only this repo.
- Any external or personal bank can still exist, but it must be treated as optional source material, not required infrastructure.

### 3.3 Exact tasks

1. Create one canonical repo-local example for each first-class question family.
2. Replace personal-path links in docs with repo-relative links.
3. Add one validation command that works from this checkout alone.
4. Add a short "fresh author start here" doc that points only to repo-local assets.
5. Keep the personal notes directory out of the contract entirely.

## 4. Canvas History Will Get Slower As Question Topologies Grow

This is not a vague future concern. The problem is mechanical and easy to explain.

### 4.1 What the code does today

In `src/renderer/src/store/useStore.ts`, graph history currently works by:

- cloning the full node and edge graph
- comparing snapshots with `JSON.stringify`
- storing full graph snapshots in history

Relevant functions:

- `cloneGraphSnapshot`
- `snapshotGraph`
- `areGraphSnapshotsEqual`
- `pushGraphHistory`
- `resolveGraphHistory`

### 4.2 Why this becomes slow

Every meaningful graph edit pays a whole-graph cost, even when the actual change is tiny.

Examples:

1. Small graph, small cost:
   - `8` nodes, `10` edges
   - editing one label is still fine

2. Medium authored question:
   - `120` nodes, `180` edges
   - changing one queue field on one node still:
     - clones all nodes
     - clones all edges
     - serializes the old snapshot
     - serializes the new snapshot
     - compares the resulting strings

3. Guided repair or optimize session:
   - a student makes `30-40` meaningful edits
   - history accumulates `30-40` full graph copies
   - undo/redo becomes a memory problem, not only a CPU problem

4. Rich node configs make it worse:
   - each node now carries more than position and label
   - queue config, resource config, traits, routing config, SLOs, and authoring metadata all enlarge snapshot size

### 4.3 User-visible symptoms

As graph size grows, this will show up as:

- lag after editing a node field
- slower undo and redo
- GC churn in the renderer
- drag-end hitching
- worse mobile responsiveness
- a ceiling on how large authored scaffolds can comfortably become

### 4.4 The right solution

The fix is to stop treating every history event as "clone and compare the whole graph."

What now exists:

- `graphRevision` tracks committed graph mutations
- common graph edits now record targeted history entries instead of whole-graph snapshot comparisons
- drag interactions now capture start state once and commit one final move-history entry at drag stop
- broad graph replacements still fall back to full snapshot history only where a targeted op is not yet derived cleanly

Recommended design:

#### Short-term

- Add a monotonic `graphRevision`.
- Increment it only on committed graph mutations.
- Stop using `JSON.stringify` equality to decide whether a meaningful mutation occurred.
- Record history only at commit boundaries:
  - add node
  - remove node
  - connect edge
  - remove edge
  - update node data
  - update edge data
  - drag end

This removes repeated deep serialization from the hot path without changing user-facing undo semantics.

#### Medium-term

Replace snapshot history with operation-based history.

Store entries like:

- `addNode`
- `removeNode`
- `moveNodes`
- `updateNodeData`
- `updateEdgeData`
- `connectEdge`
- `removeEdge`

Each entry should carry its inverse operation so undo does not require a full prior snapshot.

#### Long-term

Keep sparse checkpoints only for recovery speed.

For example:

- every `25` history operations, store one checkpoint
- between checkpoints, replay inverse ops for undo/redo

That gives good performance without sacrificing restore reliability.

### 4.5 Exact implementation tasks

1. Extend the new `graphRevision` and operation-history foundation to every broad graph mutation path.
2. Remove the remaining full-snapshot fallbacks where targeted operations are derivable safely.
3. Keep drag interactions as one committed `moveNodes` history event.
4. Add checkpoint snapshots only as a recovery optimization.
5. Add performance tests with large synthetic topologies:
   - `50` nodes
   - `150` nodes
   - `300` nodes
6. Measure:
   - node edit latency
   - undo latency
   - memory footprint after `50` edits

## 5. The UI Shell Is Over-Dense And Not Responsive Enough

This section starts with the solution first, because the target shape matters more than a list of complaints.

### 5.1 The right solution

Refactor the app shell into a canvas-first layout where only one region is visually primary at a time.

The simulator's primary job is:

1. understand the question or scenario
2. edit the topology
3. run the simulation
4. inspect the result
5. iterate

The UI should reflect that sequence directly.

Recommended shell:

#### Desktop

- The canvas is the primary region.
- The left side is one contextual drawer, not a permanent pile of navigation plus content.
- The right inspector is contextual and collapses by default when nothing is selected.
- The bottom results tray stays the single place for operational deep-dives.
- The header keeps only high-priority controls visible.

#### Mobile and narrow widths

- The canvas must take the screen center.
- The question brief opens as a drawer or sheet.
- The component library opens as a drawer or sheet.
- The inspector becomes a bottom sheet.
- Secondary actions move into overflow.

### 5.2 What is wrong in the current shell

Today the shell has too many simultaneously visible control surfaces:

- branding
- file controls
- auto-layout
- run controls
- settings
- theme toggle
- left activity rail
- left content panel
- floating canvas toolbar
- right panel
- bottom results tray

On desktop, this creates visual competition.

On mobile, it becomes a real usability failure. At a narrow viewport, the canvas is squeezed into a thin residual strip while control chrome stays persistent.

### 5.3 Recommended layout refactor

#### Header

Keep only:

- mode badge
- run state and run action
- one utility overflow
- one layout toggle if needed

Move these out of the always-visible header:

- open
- save
- auto-layout
- theme toggle
- less-used settings actions

Those belong in:

- command palette
- overflow menu
- contextual menus

#### Left side

Replace the current rail-plus-panel pairing with one adaptive drawer:

- question drawer when a question is active
- component library drawer in sandbox mode
- scenario drawer when the user explicitly opens scenarios

Do not keep multiple navigation concepts alive at once if only one is in use.

#### Right side

The inspector should be invisible until:

- a node is selected
- an edge is selected
- the user explicitly pins the panel

If nothing is selected, the shell should not spend permanent width on "No Selection."

#### Bottom tray

The bottom tray should become the default home for:

- metrics
- traces
- comparison
- timeline views

That preserves the clean spatial model:

- canvas = architecture
- bottom tray = temporal and analytical detail

### 5.4 Exact implementation tasks

1. Define shell roles explicitly:
   - primary
   - secondary
   - tertiary
2. Reduce the header to one-row essential controls.
3. Move file and utility actions into overflow or command palette.
4. Collapse the left rail and left panel into one contextual drawer model.
5. Auto-hide the right inspector when nothing is selected.
6. Add mobile-specific drawer and bottom-sheet behavior.
7. Add responsive breakpoints based on task flow, not only width.
8. Cap line lengths and widths inside the question brief.
9. Add visual hierarchy tokens so one surface is dominant, not five.
10. Run manual UX checks for:
    - sandbox empty state
    - active question
    - post-run results
    - small laptop
    - tablet
    - mobile portrait

## 6. Mixed Signals About What Is Truly Supported

This section also starts with the solution first.

### 6.1 The right solution

Create one explicit support ledger for simulator capabilities and make docs, validator warnings, sample questions, and UI badges all derive from it.

That foundation now exists in `src/engine/analysis/supportLedger.ts` and already feeds `authoringValidator.ts`. The remaining work is broad adoption, not invention from scratch.

Recommended support tiers:

- `first-class`
- `guided`
- `structural-only`
- `presentational-only`
- `deferred`

Meaning:

- `first-class`: runtime, grading, authoring guidance, and tests all exist
- `guided`: partially simulated, but bounded and honest
- `structural-only`: topology and semantic grading exist, runtime does not prove the concept
- `presentational-only`: visible in catalog or docs, but not reliable for teaching or grading
- `deferred`: not ready for author use

### 6.2 Why the mixed-signal problem exists

Right now the repo sends conflicting messages:

- the validator now has a support ledger, but some docs and older language still speak in coarse V1 versus V2 terms
- Sample content already uses resilience and correctness-flavored concepts.
- Many component types exist in the catalog.
- Some traits now have honest support-tier entries.
- Some protocol or system semantics are only partially modeled.

That creates author confusion:

- "Can I write this question?"
- "Is this concept really simulated?"
- "Is it structural-only?"
- "Is the warning stale or the sample over-claiming?"

### 6.3 What must be clarified

Examples of honest partial support:

- broadcast fanout: supported as one-to-many delivery
- idempotency guard: supported as time-window duplicate suppression
- protocol fields: supported for latency overhead, packet loss, and some connection behavior

Examples of not-yet-first-class support:

- exactly-once commit semantics
- quorum and consensus behavior
- deep delivery guarantees
- full L4 vs L7 behavioral teaching surface
- full protocol-specific semantics

### 6.4 Exact implementation tasks

1. Keep the single `supportTier` source-of-truth file as the only capability ledger for:
   - question domains
   - question concepts
   - component families
   - major traits
2. Extend the existing validator integration so more diagnostics cite the ledger directly, not legacy wording.
3. Add support-tier notes to authoring docs.
4. Keep the in-product question brief aligned with the support ledger so authors and learners see support truth directly in the simulator UI.
5. Require every question family example to state:
   - what is truly simulated
   - what is structurally inferred
   - what is deferred
6. Reject or warn on authored questions that claim unsupported guarantees as runtime facts.
7. Keep honesty metadata in traits aligned with the same support ledger.

## 7. Frontend Delivery Is Getting Heavy

### 7.1 Current signal

`npm run build` passes, but the renderer still emits a large main bundle:

- `dist/assets/index-*.js`: about `559 kB` minified

That is not a correctness failure, but it is a delivery problem:

- slower startup
- heavier embed load
- worse perceived polish
- more work parsed before the user does anything

### 7.2 Likely causes

- too much shell code is eager
- question mode code is eager
- sample content is imported eagerly
- hidden features still participate in the bundle graph
- results functionality is large and only partly split

What has already improved:

- question, component-library, scenario, lab, blueprint, and settings surfaces now lazy-load behind the left sidebar tabs or modal open state
- hidden sample payloads for labs and blueprints no longer inflate the default shell path
- the issue is no longer "everything is eager"; it is now concentrated in the still-heavy always-on canvas shell and core editor path

### 7.3 The right solution

Make the renderer load by feature boundary, not only by vendor boundary.

Important constraint for current scope:

- labs and blueprints remain false, so their code and sample payloads should not inflate the default bundle
- justification remains false, so its UI code should not stay on the hot path

### 7.4 Exact implementation tasks

1. Keep the current lazy-loaded question, scenario, lab, blueprint, settings, and component-library boundaries in place.
2. Split results views by tab:
   - summary
   - per-node
   - traces
   - cost
   - comparison
3. Add manual chunking by feature area, not only by React vendor packages.
4. Audit the renderer for engine-side sample imports that can move behind `import()`.
5. Keep the always-on shell path focused on canvas plus minimum controls.
6. Add and maintain a bundle budget check in CI.
7. Track:
   - initial JS size
   - time to first interactive render
   - lazy-chunk sizes

## 8. Question-Family Feasibility: What Exactly Needs To Be Done

## 8.1 Performance-and-shape questions are already strong

These families are already good candidates for first-class simulator questions:

- cache placement
- read/write routing
- store-fit
- async decoupling
- fanout
- baseline optimization
- scaffold repair

### Why they are strong

They work well because the simulator can already combine:

- structural rules
- semantic criteria
- injected workload
- runtime rubric checks

In these families, the bottleneck is visible in either topology shape or measured system behavior.

### What exactly still needs to be done

1. Create one canonical family pack for each of the seven families:
   - one question
   - one passing topology
   - one gamed topology
   - one author README explaining the discriminator
2. Mark these families as `first-class` in the support ledger.
3. Add one regression test per family proving:
   - reference passes
   - gamed design fails
4. Standardize failure strings so students learn from the failed check.
5. Build one "author recipe" per family:
   - prompt shape
   - structural checks
   - semantic checks
   - rubric checks
   - common traps

## 8.2 Correctness-heavy interview questions are only partially feasible today

### What is feasible now

Correctness-heavy questions can already grade some architecture-visible facts:

- a payment write path passes through an idempotency guard
- a booking path passes through a lock-like guard
- a durable ledger-facing store exists
- retries are filtered before a harmful downstream side effect

### What is not yet product-complete

With justification kept false, the product cannot yet finish the evaluation loop for questions that need a human-readable defense of a semantic choice.

That means the repo can support these questions structurally, but the student experience is incomplete if the prompt over-promises correctness guarantees.

### What exactly needs to be done now

1. Split correctness-heavy questions into two buckets:
   - architecture-visible and usable now
   - justification-dependent and deferred
2. Rewrite prompts so they do not claim the simulator proves guarantees it does not prove.
3. Grade only the supported pieces today:
   - guarded paths
   - required components
   - invariant-friendly topology shape
4. Add author warnings for correctness claims that currently require justification.
5. Keep the justification feature off until its UX is redesigned.

### What needs to be done later

When justification is revisited:

1. re-enable the feature deliberately
2. redesign the UX so it feels deterministic and fair
3. integrate it into submit-time feedback, not as a detached text box

## 8.3 Pure application-logic and protocol-semantics questions are not first-class yet

### What this means

The simulator is not yet the right primary grader for questions whose real lesson is:

- exactly-once semantics
- consensus or quorum
- linearizability
- consumer-group guarantees
- rich delivery guarantees
- deep protocol differences

### What exactly needs to be done now

1. Add explicit downgrade rules to authoring guidance:
   - application logic becomes narrative plus structural proxy
   - unsupported guarantees cannot be framed as measured runtime truth
2. Add validator warnings for unsupported guarantee claims.
3. Restrict first-class authoring examples to concepts with honest runtime or structural support.
4. Add a future trait backlog for:
   - quorum and replication acknowledgment semantics
   - exactly-once or commit outcome modeling
   - consumer-group and partition behavior
   - richer websocket and streaming behavior
   - deeper L4 vs L7 behavioral divergence

## 8.4 Missing traits and simulator functionality still to be built

This is the direct gap list behind the "not first-class yet" diagnosis above.

The important distinction is:

- some gaps are missing engine semantics
- some gaps are missing productization around semantics that are partly present
- some gaps should stay hidden for now, but their contracts should still be finished honestly

### Missing engine semantics

#### 1. State semantics have a foundation now, but not a full timeline model yet

What already exists:

- normalized request lifecycle state in `src/engine/core/simulationSemantics.ts`
- per-outcome semantics snapshots in `RequestOutcomeRecord`
- trait-written coordination markers for idempotency, lock, and reservation decisions
- results-tray surfacing for lifecycle, flow kind, delivery assessment, tags, and notes

What is still missing:

- explicit lifecycle state for requests, jobs, retries, locks, leases, and acknowledgements
- state transitions that can be inspected and graded
- a shared vocabulary for "reserved", "in-flight", "acked", "released", "expired", "deduped", and "committed"

What problem this causes:

- authors can ask stateful correctness questions, but the runtime cannot always prove which state transition happened
- multiple traits may affect the same request, but there is no first-class state timeline tying them together

The solution:

1. Build a runtime state-machine layer on top of the existing lifecycle snapshot.
2. Define canonical transition enums for:
   - request lifecycle
   - queue message lifecycle
   - lock or lease lifecycle
   - idempotency decision lifecycle
3. Emit deterministic state-transition events from traits.
4. Grade against those transitions instead of inferring semantics only from final metrics.
5. Surface the same transitions in replay and bottom-tray inspection later, without changing the current canvas.

#### 2. Delivery semantics have a foundation now, but broker truth is still partial

What already exists:

- queue delivery contracts normalized in `simulationSemantics.ts`
- configured versus runtime guarantee assessment on each queued outcome
- explicit duplicate, replay, loss, and downgrade flags
- shared validator parsing for queue delivery semantics

What is still missing:

- explicit delivery mode modeling such as:
  - `best-effort`
  - `at-most-once`
  - `at-least-once`
  - `effectively-once`
- simulator-visible consequences when acknowledgements, retries, timeouts, or redelivery differ

What problem this causes:

- queue and broker questions can only partially teach reliability guarantees
- authors cannot honestly claim a specific delivery guarantee unless it is only a structural proxy

The solution:

1. Keep the current delivery-semantics contract as the base layer for queued outcomes.
2. Make acknowledgement timing, retry timing, visibility timeout, and redelivery policy derive more consistently from that contract.
3. Add validator rules that reject unsupported guarantee claims in prompts and rubrics.
4. Add grading helpers that can say:
   - duplicate possible
   - duplicate suppressed
   - loss possible
   - replay possible
5. Keep "exactly once" unavailable until commit-outcome modeling exists.

#### 3. Exactly-once and commit-outcome semantics are still missing

What is missing:

- commit outcome tracking
- coordination between dedup state and side-effect completion
- partial-failure handling between "work executed" and "acknowledgement recorded"

What problem this causes:

- `idempotencyDedup` can teach duplicate suppression
- it cannot yet prove true exactly-once side effects

The solution:

1. Introduce a commit ledger or outcome journal abstraction in the engine.
2. Model these states explicitly:
   - seen
   - executing
   - side-effect committed
   - acked
   - unknown outcome
3. Let failures occur between those boundaries.
4. Grade correctness-heavy questions against the ledger state, not only topology shape.
5. Until then, classify exactly-once questions as `guided` or `structural-only`, never `first-class`.

#### 4. Consumer-group, partition, and retention semantics are still partial

What is missing:

- true consumer-group modeling
- per-group lag truth
- partition-affinity ordering
- retention behavior independent of single-consumer removal

What problem this causes:

- Kafka-like questions are teachable only in a reduced way
- authors may overstate what broker simulations actually prove

The solution:

1. Split broker traits into:
   - fanout semantics
   - partition semantics
   - retention semantics
   - consumer-group offset semantics
2. Track offsets per consumer group.
3. Route same-key requests to the same partition deterministically.
4. Distinguish "consumed by group" from "removed from broker."
5. Add first-class lag and replay metrics to grading output.

#### 5. Quorum, replication, and leadership semantics are still missing

What is missing:

- read quorum and write quorum behavior
- leader or follower role semantics
- replication delay and acknowledgement boundaries
- failover state transitions

What problem this causes:

- many distributed-database and consensus questions cannot be graded honestly beyond topology shape

The solution:

1. Add a small replication semantics module instead of jumping straight to full consensus.
2. Start with:
   - primary-replica acknowledgement policy
   - replication lag
   - stale-read possibility
   - failover delay
3. Later, add quorum read or write thresholds and split-brain or stale-leader scenarios.
4. Keep full Raft or Paxos teaching out of first-class scope until those semantics are real.

#### 6. Protocol semantics and L4 versus L7 divergence are still shallow

What is missing:

- protocol-specific acknowledgement semantics
- deeper request inspection semantics
- streaming-session behavior
- a strong simulator-level difference between L4 and L7 routing

What problem this causes:

- protocol questions become naming exercises
- load balancer questions risk feeling cosmetic instead of causal

The solution:

1. Separate edge semantics from node semantics more aggressively.
2. Add protocol contracts for:
   - connection setup cost
   - message framing or session persistence
   - acknowledgement mode
   - redelivery capability
3. Restrict content-aware routing to L7-capable components only.
4. Keep L4 routing limited to transport-visible keys and connection distribution.
5. Add validator checks that prevent authors from attaching L7-only logic to L4 paths.

### Missing product and authoring functionality

#### 7. Requirements-first scaffolds are the right abstraction, but not a finished product surface yet

What is missing:

- a stable authored entry flow for requirements-first questions
- a pinned target budget surface
- a consistent way to convert a long interview prompt into staged simulator input

What problem this causes:

- authors can describe requirements-first questions in docs
- learners do not yet enter those questions through a dedicated simulator experience

The solution:

1. Keep the current UI surface off for now, but finish the authoring contract first.
2. Treat `requirements-first` as a first-class entry format in:
   - schema
   - validator
   - sample question packs
   - grading expectations
3. Define a minimal staged payload:
   - requirements
   - scale assumptions
   - target NFRs
   - expected architecture checkpoints
4. Add the stepper UI only after the contract is stable.

#### 8. Locked-lab mode is conceptually right, but should remain hidden until the contract is tighter

What is missing:

- hard constraints on editability
- a stable authored lab package contract
- lab-specific result framing

What problem this causes:

- labs exist as an abstraction, but can still feel like ordinary free-play unless restrictions are fully enforced

The solution:

1. Keep labs hidden in the product surface for now.
2. Finish the underlying contract for:
   - fixed topology
   - permitted knobs
   - expected observations
   - lab-specific pass or fail checks
3. Make edit restrictions data-driven, not hard-coded per screen.
4. Re-enable the visible lab surface only after one or two canonical labs are fully honest.

#### 9. Support truth now has one shared ledger, but adoption is incomplete

What already exists:

- one source of truth for support tiers in `src/engine/analysis/supportLedger.ts`
- validator integration that already uses that ledger for author warnings
- question brief surfacing that exposes domain and concept support tiers in the simulator UI

What is missing:

- full adoption across docs, samples, and UI badges

What problem this causes:

- authors still see a mix of updated ledger-backed warnings, older doc language, ambitious samples, and partially implemented traits at the same time

The solution:

1. Keep the support ledger described in Section 6 as the only source of truth.
2. Make every question family, trait, and concept declare:
   - support tier
   - what is simulated
   - what is inferred
   - what is deferred
3. Derive validator messaging and author badges from that ledger.

#### 10. Justification is correctly disabled, but the correctness loop remains incomplete without it

What is missing:

- a fair and deterministic path for questions whose lesson cannot be fully measured by topology plus simulation

What problem this causes:

- correctness-heavy questions are structurally possible, but not yet fully complete as a product experience

The solution:

1. Keep `SHOW_JUSTIFICATION = false` for now.
2. Classify any question that needs freeform defense as deferred or guided.
3. Only reintroduce justification after:
   - semantic support is clearer
   - prompt expectations are narrower
   - review feedback can be attached to concrete rubric claims

### Recommended build order inside this missing-gap set

1. Extend support-ledger truth into all authoring and UI surfaces first.
2. Build full state-transition semantics on top of the existing lifecycle snapshot.
3. Extend delivery semantics into broker-specific behavior.
4. Extend brokers with consumer-group, partition, and retention truth.
5. Add commit-outcome modeling for correctness-heavy flows.
6. Add replication and quorum semantics after that.
7. Productize requirements-first entry only after the underlying authoring contract is stable.
8. Productize locked-lab mode only after restrictions and observations are data-driven and honest.

## 9. Strong Points Worth Keeping

These are real strengths in the repo and should be protected during refactors.

## 9.1 Deterministic simulation core

Why it is strong:

- same seed, same run shape
- deterministic event-driven engine
- good fit for grading and replay

How it works:

- the engine advances simulated time through events, not wall-clock time
- core runtime pieces are structured for reproducibility
- metrics and replay data come from the same run contract

Why this matters:

- grading is defendable
- regression testing is meaningful
- question authors can tune discriminators reliably

Example:

- a cache-placement question can be re-run with the same seed after changing only one topology property and the difference is attributable to the topology, not random drift

## 9.2 Prompt scale now reaches the runtime more honestly

Why it is strong:

- question-scale numbers are not just decorative text anymore

How it works:

- `src/engine/analysis/question.ts` derives `baseRps` and a typed read/write `requestDistribution` from `prompt.scale` when the suite case omits them
- `src/engine/analysis/question.test.ts` covers that derivation

Why this matters:

- a read-heavy question can actually run read-heavy
- a peak-RPS number can actually stress the topology

Example:

- a prompt with `peakRps: 2400` and `readWriteRatio: 90` can inject `2400 rps` and a `90/10` read/write mix into grading

## 9.3 The grading pipeline is testable and mostly pure

Why it is strong:

- evaluation logic is not welded to the live UI or to the live engine instance

How it works:

- `evaluateSuite` and `gradeAttempt` take an injected `runTopology` function
- that lets tests grade scenarios without spinning the whole application shell

Why this matters:

- easier CI
- easier regression tests
- safer refactors

Example:

- a question package can be validated against fake outputs or deterministic fixtures before authoring goes anywhere near Django

## 9.4 The authoring validator is already high-value

Why it is strong:

- it catches authoring mistakes before they become bad student experiences

How it works:

- it checks for orphan NFRs
- bad metric keys
- invalid entry-format combinations
- dangling justification bindings
- missing `sizeBytes`
- grading-domain mismatches

Why this matters:

- question quality becomes enforceable, not aspirational

Example:

- if an author writes a fake metric like `summary.latencyP99Ms`, the validator catches it before the question ships

## 9.5 Traits are getting more honest

Why it is strong:

- traits describe both what they simulate and what they do not simulate

How it works:

- `broadcastFanout` honestly claims one-to-many delivery, not full broker semantics
- `idempotencyDedup` honestly claims time-window duplicate suppression, not full exactly-once

Why this matters:

- the simulator can grow concept by concept without pretending every component is fully real-world complete

Example:

- an idempotency lab can teach "duplicate retries are intercepted before downstream writes" without falsely claiming ledger commit correctness is solved

## 9.6 Outcome semantics now reach the UI in a usable way

Why it is strong:

- semantic engine work is no longer trapped in backend-only data structures

How it works:

- request outcomes now carry lifecycle, flow, delivery, coordination, tags, and notes
- the results tray can surface those details directly in expanded request rows

Why this matters:

- authors and learners can inspect why a request was retried, deduped, contended, or oversold without reverse-engineering raw events

Example:

- a booking question can now show that a failed attempt was `queued`, `retried`, `lock:contended`, or `reservation:oversold`, instead of only showing a terminal success or failure count

## 9.7 The entry-format model is a good product abstraction

Why it is strong:

- `QuestionType` and `QuestionEntryFormat` are separated cleanly

How it works:

- the question can say what is being graded
- the entry format can say how the learner enters the problem

Why this matters:

- blank canvas
- requirements-first
- scaffold repair
- baseline optimize
- locked lab

all become product surfaces built over one engine rather than separate mini-apps.

Even with labs and workflow strips hidden for now, the underlying abstraction is correct.

## 9.8 Engineering hygiene is materially good

Evidence:

- `npm test` is green after the small expectation fix
- typecheck is green
- production build is green
- CI can be tightened to run tests and enforce the web bundle budget, rather than only linting and building
- there is broad Vitest coverage already

Why this matters:

- the repo is not a speculative prototype anymore
- it is a real system that can be hardened incrementally

## 10. Shortest Path

This is the minimum path to make the repo much more robust without reopening deferred product surfaces.

1. Keep labs, blueprints, and justification off and make that explicit in docs and validator messaging.
2. Create a repo-local fresh-author pack and remove personal-path dependencies from the authoring contract.
3. Add the capability support ledger so authors know what is first-class versus partial.
4. Refactor the shell into a canvas-first responsive layout.
5. Replace whole-graph snapshot history with revision-aware, operation-based history.
6. Split the renderer by feature boundary and enforce a bundle budget.
7. Promote the already-strong question families into canonical first-class examples.
8. Start the semantic backlog with support-ledger truth, state semantics, and delivery semantics before attempting deeper correctness claims.

## 11. Critical Path

This is the dependency-sensitive order.

1. **Support ledger first.**
   - Without this, docs, validator warnings, and sample questions will keep disagreeing.
2. **Fresh-author pack second.**
   - Without this, new authors still depend on personal context and cannot reliably use the repo.
3. **Canvas-first shell refactor third.**
   - This defines the real product surface before more features pile on.
4. **History model refactor fourth.**
   - This protects performance as authoring and question size grow.
5. **Bundle splitting fifth.**
   - This is safer after the shell boundaries are clearer.
6. **Semantic backlog sixth.**
   - Build support-ledger truth, then state semantics, then delivery semantics, then broker and correctness semantics.
7. **Question-family promotion seventh.**
   - Once support tiers and authoring assets are honest, the first-class bank can be declared with confidence.

If only one chain is pursued, pursue this one.

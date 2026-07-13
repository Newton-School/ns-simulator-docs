# Issue #176 - Simplification / Declutter Proposal

This note captures the written deliverable for the declutter portion of issue `#176` (the work tracked as `#182` in the implementation breakdown). It is intentionally a product proposal, not an engine design.

## Problem

The simulator currently mixes three kinds of information in the same visual surface:

1. User-entered configuration.
2. Engine-derived results.
3. Product guidance and warnings.

That makes the interface harder to read than it needs to be. The main failure modes are:

- Pre-run cards look result-like even when no simulation has happened yet.
- Run context consumes primary space before any verdict or finding.
- Dense metric tables appear before the user knows what matters.
- Validation messages teach the user too little about what is structurally wrong.

## Design Goal

The UI should answer these questions in order:

1. `Can I run this?`
2. `What happened?`
3. `Why did it happen?`
4. `What should I inspect next?`

Configuration belongs in the inspector. Results belong on the canvas cards and in the results tray. Guidance belongs in inline warnings and targeted toasts.

## Proposal

### 1. Hide result-only affordances until a run exists

- Metric lenses should only be visible when the simulation has an active or completed run.
- Node cards should stay visually quiet before the first run.
- Closing the results tray should also clear result-only canvas state.

### 2. Make the tray verdict-first

The first screen in the results tray should not be a config echo. It should start with:

- the first bottleneck,
- the dominant failure mode,
- the most important routing or queueing clue,
- a short next-step recommendation.

Run context should remain available, but collapsed by default as reference metadata.

### 3. Keep cards lens-driven, not config-driven

Node cards should show one metric family at a time:

- `Saturation`: workers, queue, utilization, or backlog.
- `Latency`: p95/p99 with SLO context when present.
- `Errors`: dominant rejection reason or error rate.
- `Throughput`: post-warmup throughput or a trait-specific throughput-side metric like consumer lag.

They should not restyle user-entered config as if it were a measured result.

### 4. Teach invalid wiring directly

Validation should convert structural mistakes into readable messages that explain:

- what is wrong,
- where it is wrong,
- what kind of fix is expected.

Examples:

- self-loops are hard errors,
- conditional edges without conditions are hard errors,
- purely synchronous cycles without an exit are hard errors,
- unrealistic protocol/mode combinations are warnings with realism guidance.

### 5. Let scenarios carry the teaching burden

Complex behaviors should be introduced through curated scenarios rather than a blank-canvas-first flow. Each advanced behavior ships with:

- one scenario,
- one short “what to look at” note,
- one clear expected signal in the results.

## Scope Split

### In scope for this proposal

- Information hierarchy.
- Visibility rules for result-only UI.
- Tray ordering.
- Teaching-oriented validation language.
- Scenario-first onboarding for advanced behaviors.

### Out of scope for this proposal

- Grading/verdict contract design.
- Batch evaluation CLI.
- Rubric authoring.
- Backend assignment orchestration.

Those are separate workstreams even though they depend on a cleaner result presentation layer.

## Current Status Against The Proposal

The following have already landed in code:

- metric lenses are tied to run visibility rather than always showing pre-run,
- curated scenario loading exists,
- embedded iframe question previews exist,
- validation now hard-fails self-loops, empty conditional edges, and pure sync cycles,
- edge validation uses a shared rule table with realism warnings.

The following are still product/UI follow-up work:

- a true verdict-first results tray,
- collapsing run context behind a disclosure,
- reducing pre-run config echo on node cards beyond the existing lens gating,
- synthesizing “what is wrong” findings at the top of the tray.

## Recommended Next UI Slice

If the declutter proposal is implemented beyond this document, the next slice should be:

1. Add a `Findings` block at the top of the results tray.
2. Collapse `Run Context` by default.
3. Ensure every node card shows only lens-specific output after a run, and no faux-result footer before one.
4. Add direct links from findings to the relevant node, edge, or table row.

That slice would turn the proposal into a user-visible improvement without requiring the full grading system.

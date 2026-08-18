# Settings Modal Feature Spec

## Summary

The Settings modal is the operator-facing control surface for simulator behavior that does not belong in the node inspector or the per-run popover.

The shipped modal exposes three tabs:

- `Environments`
- `Simulation`
- `Display`

`Pedagogy` is intentionally **not shipped in the live student-facing modal**. The same deployed simulator is used by both instructors and learners, so pedagogy controls need a different delivery path than the general-purpose settings surface.

This spec documents both:

- the shipped `Simulation` and `Display` settings,
- the deferred `Pedagogy` model that should exist later behind an instructor-only or host-supplied surface.

## Goals

- Give authors and advanced users a stable place to control simulator-wide behavior without opening the run tray every time.
- Separate concerns cleanly:
  - `Environments` = capability and visibility policy
  - `Simulation` = run defaults and scenario-level behavior
  - `Display` = local presentation preferences
- Persist settings at the correct layer:
  - topology-scoped simulation defaults travel with the saved canvas,
  - local display preferences persist per device/browser,
  - environment policy stays runtime-scoped.

## Non-goals

- Do not turn the student-facing modal into an instructor-only admin panel.
- Do not expose grading policy, scaffold policy, or reveal policy in the deployed shared modal.
- Do not duplicate deep node/edge authoring controls that already belong in the inspector.

## Tab Model

### Environments

Already live. Owns:

- mode preset
- edge model
- edge editability
- resource editability
- execution-profile editability
- cost/vCPU/RAM budgets
- test-run limit
- rubric-check visibility

This tab is the policy layer.

### Simulation

Owns scenario-level run defaults for the current topology.

These settings are serialized in the canvas file under `scenario`.

#### Controls

- `Run duration`
  - Maps to `scenario.global.simulationDuration`
- `Warmup duration`
  - Maps to `scenario.global.warmupDuration`
- `Seed`
  - Maps to `scenario.global.seed`
- `Randomize seed each run`
  - Maps to `scenario.randomizeSeedEachRun`
  - Before each run, the app generates a fresh seed and writes the actual value back into `scenario.global.seed` so results remain reproducible.
- `Source node`
  - Maps to `scenario.selectedSourceNodeId`
  - `Auto` means `undefined`, resolved to the first workload-configured source at run time.
- `Workload pattern`
  - Maps to `scenario.workloadOverride.pattern`
- `Base RPS`
  - Maps to `scenario.workloadOverride.baseRps`
- `Inject a fault by default`
  - Presence or absence of `scenario.faults[0]`
- `Fault target`
  - Maps to `scenario.faults[0].targetId`
- `Fault mode`
  - Maps to `scenario.faults[0].params.mode`
- `Fail at`
  - Maps to `scenario.faults[0].params.atMs`
- `Recover after`
  - Maps to `scenario.faults[0].params.durationMs`

#### Behavior notes

- Pattern-specific fine-tuning for bursty/spike/sawtooth still exists in the Run popover.
- The Settings modal owns the stable defaults; the Run popover remains the quick-access surface.
- Loading a raw TopologyJSON with authored `faults` should hydrate the scenario fault preset.

### Display

Owns local presentation preferences for the current user and device.

These settings persist in local storage and do **not** travel with the topology file.

#### Controls

- `Theme`
  - `light` / `dark`
- `Chrome density`
  - `full` / `minimal`
  - Maps to `environmentProfile.chromeDensity`
- `Default build lens`
  - The pre-run canvas lens restored after clearing a run
- `Latency lens percentile`
  - Which percentile the node cards show as the headline when the runtime `Latency` lens is active
- `Auto-open simulation tray`
  - Whether the bottom tray opens automatically on run
- `Default results tab`
  - Which completed-results section opens first

#### Behavior notes

- `Theme` must stay synchronized with the header theme toggle.
- `Default build lens` affects initial load and pre-run reset behavior.
- `Latency lens percentile` is a display choice only; it does not change the simulation or grading.
- `Default results tab` applies when a completed run first opens the tray.

### Pedagogy

Deferred from the shipped modal.

The live deployed simulator is shared by students and instructors, so pedagogy controls need an instructor-only delivery mechanism such as:

- host-supplied launch context,
- instructor-only authoring surface,
- assignment wrapper UI outside the student modal,
- or a dedicated protected modal mode.

## Deferred Pedagogy Model

These settings are still worth specifying now even though they are not shipped in the modal.

### Candidate controls

- `Show prompt`
- `Show grading suite details`
- `Show scaffold-source markers`
- `Allow editing scaffold nodes`
- `Allow test runs`
- `Max test runs`
- `Show live metrics while building`
- `Allowed component palette`
- `Rubric check visibility`
- `Hint verbosity`
- `Show metric provenance`

### Why deferred

- These controls materially change the teaching contract, not just the simulator UX.
- A student-facing shared modal should not expose grading/reveal policies directly.
- Several of these already exist in `EnvironmentProfile`; the missing piece is the right instructor-only control surface, not the underlying capability.

## State Ownership

### Environment policy

Lives in `EnvironmentProfile`.

Examples:

- edge model
- edit locks
- rubric visibility
- budgets
- chrome density

### Topology-scoped simulation defaults

Lives in `scenario`.

Examples:

- duration
- warmup
- seed
- selected source
- workload override
- default injected fault
- randomize-seed flag

These should round-trip through:

- canvas save/load
- sample scenario load
- topology-to-canvas adaptation when possible

### Local display preferences

Lives in persisted UI settings.

Examples:

- theme
- default build lens
- latency lens percentile
- auto-open tray
- default results tab

These should **not** affect serialized topology files.

## Persistence Rules

### Simulation tab

Persist in saved canvas JSON as part of `scenario`.

### Display tab

Persist in local storage only.

Recommended storage key:

- `nssimulator.display-settings`

Legacy compatibility:

- continue mirroring `theme` to the existing `theme` key until all theme consumers have moved fully to shared display settings.

## UX Rules

- The modal should only show tabs that are actually live for general users.
- Do not ship a disabled `Pedagogy` tab to students.
- Use concise labels and explanatory hints, not instructor/student-specific wording.
- Avoid duplicating deep authoring surfaces from the node inspector.
- Prefer segmented controls for small enums and compact selects for larger enumerations.

## Acceptance Criteria

### Simulation

- Changing run duration, warmup, seed, selected source, workload pattern, and base RPS updates the live scenario state immediately.
- Enabling `Randomize seed each run` produces a fresh seed before each run and stores the actual generated seed back into the scenario.
- Fault defaults are editable from Settings and used by the next run without opening the Run popover.

### Display

- Theme changes in the Display tab immediately affect the app and remain in sync with the header toggle.
- Clearing a run returns the canvas to the preferred pre-run lens instead of a hardcoded lens.
- The latency lens percentile changes the runtime node-card headline value.
- The results tray opens and defaults according to the stored display preferences.

### Pedagogy

- No pedagogy policy controls are exposed in the shipped student-facing modal.
- The deferred pedagogy surface remains documented here for future instructor-only implementation.

## Implementation Notes

- `Simulation` tab UI can reuse the same scenario data model as the header run controls.
- `Display` tab should use a shared persisted preference model rather than component-local state.
- `ThemeToggle` and the Display tab must read/write the same theme source.
- `ResultsTray` should consume a shared default-tab preference instead of hardcoding `overview`.
- `clearSimulationMetrics` should restore the preferred pre-run lens instead of hardcoding `concurrency`.

## Follow-up Work

- Build the instructor-only pedagogy surface.
- Decide whether `chromeDensity` should remain under `EnvironmentProfile` or move to display preferences in standalone mode.
- Decide whether deeper pattern-specific workload fields should move into the Simulation tab or remain in the Run popover only.
- Add UI tests for the modal tabs and the display-preference persistence path.

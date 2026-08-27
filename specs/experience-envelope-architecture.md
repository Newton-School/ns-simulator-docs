# Experience Envelope Architecture

## Core Principle

Do not bolt assignment UX, interview UX, labs, and timeline tooling directly onto
the React Flow canvas.

Keep the simulator split into two layers:

1. **Physics Engine**
   - Zustand graph state
   - topology serializer / validator
   - worker-driven simulation
   - grading and budget analysis
   - results tray data

2. **Experience Envelope**
   - shell mode badge
   - left-rail tab set
   - question/lab brief surface
   - structural edit locks
   - mode-specific run language
   - bottom-tray entry points

The engine stays shared. The envelope decides how much of the workbench is exposed.

## Envelope Modes

The renderer now resolves a shell-level `ExperienceEnvelope` from the loaded
question plus the existing `EnvironmentProfile`.

Current user-facing modes:

- `Sandbox`
  - no active question
  - full workbench: question loader, blueprints, labs, library, scenarios
- `Assignment`
  - graded question wrapper
  - palette/library remains, scenarios disappear
  - question tab becomes **Assignment Brief**
- `Interview`
  - ungraded guided question wrapper
  - question tab becomes **Interview Brief**
- `Lab`
  - locked-topology guided lab
  - question tab becomes **Lab Guide**
  - only `question` and `labs` stay on the left rail

Implementation entrypoint:

- `src/renderer/src/utils/experienceEnvelope.ts`

## What Changed

### 1. Shell-level mode is now separate from environment preset

The top header badge is no longer a thin echo of `AUTHOR/ASSIGNMENT/PRACTICE`.
It now shows the learner-facing shell mode:

- `Sandbox`
- `Assignment`
- `Interview`
- `Lab`

This is the product-facing layer on top of the older environment capability model.

### 2. Labs are first-class wrappers, not separate mini-apps

Sample locked labs now live in:

- `src/renderer/src/config/sampleLabs.ts`

Each lab is still just a `QuestionPackage` plus a complete scaffold topology:

- `tags: ['lab']`
- `scaffold.type: 'complete'`
- `constraints.canModifyScaffold: false`
- `constraints.canRemoveScaffoldNodes: false`
- `constraints.allowedNodeTypes: []`

This means labs reuse:

- the same canvas
- the same worker
- the same grading path
- the same results tray

No second simulator was introduced.

### 3. Canvas structure can be locked without freezing property tuning

Lab mode now locks **structural** editing:

- no drag-in from the palette
- no new connections
- no node dragging
- no edge updates
- no paste-driven topology edits
- no reset/delete actions from the canvas toolbar

But node and edge properties remain available through the existing inspector.

This matches the intended lab model:

- topology fixed
- parameters editable
- results explorable

### 4. Palette gating now respects question constraints

The component library now filters by both:

- `EnvironmentProfile.capabilities.editPaletteList`
- `QuestionPackage.constraints.allowedNodeTypes / forbiddenNodeTypes`

This gives the assignment shell and future interview shells a real mechanism for
restricting the left panel to only the components a prompt allows.

### 5. The bottom tray is treated as the contextual deep-dive surface

The implementation does not add a second analysis UI. Instead it leans harder on
the existing results tray by relabeling the entry CTA in wrapped experiences to:

- `Open Timeline & Results`

This keeps the canvas spatial and keeps temporal detail in the tray.

## Sample Labs Added

Three locked labs were added to exercise the current V-next traits:

1. `Fanout Delivery Lab`
   - delivery semantics
   - async fanout
   - consumer saturation

2. `Store-Fit Routing Lab`
   - state semantics
   - request-class routing
   - storage-profile tradeoffs

3. `Idempotency Guard Lab`
   - correctness-first write paths
   - duplicate suppression
   - guarded side effects

## Next Steps

The envelope abstraction is now in place. The next clean additions are:

1. **Timeline-specialized tray views**
   - DNS resolution sequence
   - probe timeline
   - incident replay

2. **Wizard overlay**
   - requirements
   - estimation
   - HLD handoff to canvas
   - persistent budget tracker

3. **Interview shell controls**
   - timer
   - restricted palette presets
   - rubric visibility policy

4. **Host-supplied envelope config**
   - let Newton/assignment hosts launch directly into `Assignment`, `Interview`, or `Lab`
   - keep renderer behavior deterministic across entrypoints

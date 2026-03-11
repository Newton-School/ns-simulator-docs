# NS-Simulator — UI Layer Issues

> Synthesized from `adr-critical-problems.md` and `adr-state-management.md`. Each issue is self-contained with context, the exact problem, and acceptance criteria. Issues are ordered by dependency — fix earlier ones first.

---

## Issue 1: Connect engine domain types to the renderer

**Labels:** `architecture` `engine` `types` `blocked-by: none`
**Size:** L

### Context

`src/engine/types.ts` defines `ComponentNode`, `EdgeDefinition`, `TopologyDocument`, and ~30 domain types. The renderer never imports them. Instead it maintains informal parallel types in `types/ui.ts` (`ComputeNodeData`, `ServiceNodeData`) that are structurally incompatible with the engine. There is no code path from what the user draws on the canvas to a document the simulation engine can consume.

### What to do

- Add `@engine` path alias in `electron.vite.config.ts` pointing to `src/engine`
- Add `_uiPosition: { x: number; y: number }` to `ComponentNode` in `engine/types.ts` — the only UI-specific field allowed in the domain type
- Write `src/renderer/src/canvas/adapters.ts`:
  - `topologyToRFNodes(doc: TopologyDocument): Node[]`
  - `topologyToRFEdges(doc: TopologyDocument): Edge[]`
  - `rfChangesToTopologyMutation(changes: NodeChange[]): TopologyMutation[]`
- Delete `src/renderer/src/types/ui.ts` once adapters are in place

### Acceptance criteria

- [ ] `@engine` alias resolves in all renderer files
- [ ] `canvas/adapters.ts` exports typed conversion functions
- [ ] A `TopologyDocument` can round-trip through `topologyToRFNodes` → `rfChangesToTopologyMutation` → back to `TopologyDocument` without data loss
- [ ] `types/ui.ts` is deleted
- [ ] `tsc --noEmit` passes with no `any` introduced

---

## Issue 2: Split the single Zustand store into three stores by concern

**Labels:** `architecture` `state-management` `performance` `blocked-by: #1`
**Size:** L

### Context

`useStore.ts` holds React Flow plumbing (`onNodesChange`, `onEdgesChange`, `onConnect`), canvas data (`nodes[]`, `edges[]`), and file metadata (`fileName`, `isUnsaved`) in one slice. Any component reading `nodes` re-renders on every canvas event, including components that only care about `fileName`. `useFlowStore.ts` is a thin wrapper around the same store that provides no real abstraction.

### What to do

Create three stores:

**`useTopologyStore`** — the canonical domain model

```ts
interface TopologyStore {
  topology: TopologyDocument | null
  validationResult: ValidationResult | null   // derived, recomputed on every mutation

  addNode(def: NodeTypeDefinition, position: XYPosition): void
  removeNode(id: NodeId): void
  updateNode(id: NodeId, patch: Partial<ComponentNode>): void
  addEdge(edge: EdgeDefinition): void
  removeEdge(id: string): void
  loadTopology(doc: TopologyDocument): void
  reset(): void
}
```

**`useCanvasStore`** — React Flow UI state only

```ts
interface CanvasStore {
  rfNodes: Node[]
  rfEdges: Edge[]
  onNodesChange: OnNodesChange
  onEdgesChange: OnEdgesChange
  onConnect: OnConnect
  selectedNodeId: string | null
  setSelectedNode(id: string | null): void
}
```

`rfNodes` and `rfEdges` are derived from `useTopologyStore` via a subscription — they are never the authoritative source.

**`useAppStore`** — session and UI state

```ts
interface AppStore {
  filePath: string | null
  isDirty: boolean
  theme: 'light' | 'dark'
  leftPanelOpen: boolean
  rightPanelOpen: boolean
  activeTab: 'specs' | 'state' | 'logs'

  setFilePath(path: string | null): void
  markDirty(): void
  markClean(): void
  setTheme(theme: 'light' | 'dark'): void
  toggleLeftPanel(): void
  toggleRightPanel(): void
}
```

Delete `useFlowStore.ts` wrapper.

### Acceptance criteria

- [ ] Three stores exist with no cross-concern overlap
- [ ] `rfNodes`/`rfEdges` in canvas store are always derived from topology store, never set independently
- [ ] `useFlowStore.ts` deleted
- [ ] `useStore.ts` deleted
- [ ] Dragging a node on the canvas does not trigger a re-render in `FileStatus` component (verify with React DevTools Profiler)

---

## Issue 3: Run topology validation after every mutation and surface errors in the UI

**Labels:** `ux` `validation` `blocked-by: #1 #2`
**Size:** M

### Context

`engine/validator.ts` has a complete `validateTopology()` that returns structured `{ errors[], warnings[] }` with path-specific messages. It is never called from the renderer. Users can build invalid topologies (orphan edges, invalid distribution params, disconnected subgraphs) with no feedback until the simulation crashes.

### What to do

- Call `validateTopology(topology)` inside every mutating action in `useTopologyStore` and store the result as `validationResult`
- For large topologies, debounce validation with a `setTimeout(0)` so it does not block the mutation synchronously
- Add `ValidationPanel` organism that renders `validationResult.errors` and `validationResult.warnings`
- Surface validation state in the header (a count badge on the Run button: "3 errors")
- File save: if `validationResult.errors.length > 0`, show a confirmation dialog ("Topology has errors — save anyway?") rather than silently saving or blocking

### Acceptance criteria

- [ ] Adding an edge with a non-existent target node ID shows an error message in the UI within 100ms
- [ ] `validationResult` in `useTopologyStore` updates after every mutation
- [ ] `ValidationPanel` renders error path + message for each error
- [ ] File save with errors shows a confirmation dialog, not a silent save or silent block
- [ ] Warning messages (disconnected nodes) are visually distinct from errors

---

## Issue 4: Validate all external data boundaries with Zod

**Labels:** `type-safety` `security` `blocked-by: #1`
**Size:** M

### Context

Five entry points accept unvalidated external data, three of which are active security/stability risks:

1. **Drag-drop** — `JSON.parse(event.dataTransfer.getData(...))` with no schema check in `useFlowDnD.ts`
2. **File load** — loaded JSON content is parsed without schema validation; a corrupt or malicious file can partially load into the store
3. **IPC `runSimulation`** — `config: any` crosses the Electron IPC boundary to the main process
4. **`updateNodeData`** — `data: any` accepts any shape
5. **Properties panel** — selected node `data` cast without narrowing

### What to do

- Define `DragPayloadSchema = z.object({ nodeTypeId: z.string(), ... })` and use `.safeParse()` in `useFlowDnD`; silently ignore malformed payloads
- Route all file load operations through `engine/serialization.ts`'s `deserializeTopology()` which calls `TopologyDocumentSchema.safeParse()` and throws a typed `DeserializationError` on failure
- Narrow `runSimulation` IPC argument: define a schema in `src/shared/ipcChannels.ts` and validate in the preload before invoking
- Replace `updateNodeData(nodeId, data: any)` with `updateNode<T extends ComponentNode>(id: NodeId, patch: Partial<T>): void`
- Narrow selected node data in the properties panel using the node's `rfType` discriminant

### Acceptance criteria

- [ ] A drag event with `{}` as payload is silently ignored — no crash, no console error
- [ ] Loading a file with invalid JSON shows a UI error toast, not a partial load
- [ ] Loading a file that passes JSON.parse but fails Zod schema shows a UI error toast
- [ ] No `any` types remain at IPC, file I/O, or drag-drop boundaries
- [ ] `tsc --noEmit` with `"noImplicitAny": true` passes

---

## Issue 5: Decompose `useFlowPersistence` into single-responsibility units

**Labels:** `refactor` `hooks` `blocked-by: #2 #4`
**Size:** M

### Context

`useFlowPersistence.ts` does four unrelated things: keyboard shortcut registration, serialization, deserialization, and file dialog orchestration. These change for different reasons and cannot be tested independently.

### What to do

Delete `useFlowPersistence.ts` and replace with:

**`engine/serialization.ts`** — pure functions, no React

```ts
export function serializeTopology(doc: TopologyDocument): string
export function deserializeTopology(raw: string): TopologyDocument  // throws DeserializationError
```

**`src/renderer/src/hooks/useKeyboardShortcuts.ts`** — registers global shortcuts

```ts
export function useKeyboardShortcuts(handlers: {
  onSave: () => void
  onOpen: () => void
  onDelete: () => void
})
```

**`src/renderer/src/hooks/useFilePersistence.ts`** — orchestrates file I/O

```ts
export function useFilePersistence(): {
  handleSave: () => Promise<void>
  handleOpen: () => Promise<void>
}
// On save: gets topology from useTopologyStore, serializes, calls FileService, updates useAppStore
// On open: calls FileService, deserializes (throws on failure), loads into useTopologyStore, updates useAppStore
// Both: show error toast on failure, never silently swallow errors
```

### Acceptance criteria

- [ ] `useFlowPersistence.ts` deleted
- [ ] `engine/serialization.ts` exports two pure functions with no React imports
- [ ] `useKeyboardShortcuts.ts` has a single responsibility: registering `keydown` listeners
- [ ] `useFilePersistence.ts` surfaces errors to the UI (toast or dialog) rather than logging to console
- [ ] `serializeTopology` + `deserializeTopology` round-trip test passes (in `engine/serialization.test.ts`)

---

## Issue 6: Add XState simulation runner state machine

**Labels:** `architecture` `state-management` `simulation` `blocked-by: #2`
**Size:** L

### Context

The simulation runner has five states (idle, validating, running, paused, complete/error) and eight transitions. Modelling this in Zustand requires manual guards on every action (`if (status !== 'running') return`) that can be forgotten or bypassed. The Web Worker is a resource that must be created on entering `running` and terminated on leaving it — in Zustand, this cleanup must be manually replicated in every exit path (stop, error, complete).

Full rationale in `adr-state-management.md`.

### What to do

Install `xstate` and `@xstate/react`:

```bash
npm install xstate @xstate/react
```

Create `src/renderer/src/machines/simulationMachine.ts`:

- States: `idle | validating | running | paused | complete | error`
- `entry: 'spawnWorker'` and `exit: 'terminateWorker'` on the `running` state — Worker lifecycle tied structurally to the state
- `invoke` with `fromPromise` for the async validation step in `validating`
- Worker messages (`PROGRESS`, `SNAPSHOT`, `COMPLETE`, `ERROR`) handled as XState events in the `running` state
- `SNAPSHOT` events forwarded to `useSimulationResultsStore` (Zustand) — the machine owns the process, Zustand owns the data

Create `src/renderer/src/stores/useSimulationResultsStore.ts`:

```ts
interface SimulationResultsStore {
  snapshots: TimeSeriesSnapshot[]
  result: SimulationOutput | null
  addSnapshot(snapshot: TimeSeriesSnapshot): void
  setResult(result: SimulationOutput): void
  reset(): void
}
```

Create `src/renderer/src/hooks/useSimulation.ts`:

```ts
export function useSimulation(): {
  status: 'idle' | 'validating' | 'running' | 'paused' | 'complete' | 'error'
  progress: number
  error: string | null
  run(topology: TopologyDocument): void
  pause(): void
  resume(): void
  stop(): void
}
```

Define Worker message protocol in `src/worker/protocol.ts` (shared types, no runtime code).

### Acceptance criteria

- [ ] Calling `pause()` when status is `validating` is a no-op — no crash, no state corruption
- [ ] Worker is always terminated when leaving `running` state (stop, error, complete paths all covered)
- [ ] A second `run()` call during `validating` is ignored — no second Worker spawned
- [ ] `SimulationControls` buttons are enabled/disabled purely from machine state (`status`)
- [ ] `useSimulationResultsStore` accumulates snapshots during `running`; `reset()` is called on each new `run()`

---

## Issue 7: Make `PropertiesForm` data-driven from the node registry

**Labels:** `refactor` `dx` `blocked-by: #1`
**Size:** M

### Context

`PropertiesForm.tsx` has a hardcoded branch for `computeType` that special-cases ComputeNode rendering. Adding any node type with custom form fields requires editing the form component directly — an Open/Closed violation.

### What to do

Define `FieldDefinition` and extend `NodeTypeDefinition` in `nodes/registry.ts`:

```ts
interface FieldDefinition {
  key: string
  label: string
  type: 'slider' | 'select' | 'input' | 'boolean'
  options?: string[]             // for select
  min?: number; max?: number     // for slider
  unit?: string                  // for input/slider display
}

interface NodeTypeDefinition {
  // ... existing fields ...
  fields: FieldDefinition[]
  fieldGroups: Record<string, string[]>  // group label → field keys
}
```

Rewrite `PropertiesForm`:

```tsx
function PropertiesForm({ nodeTypeId, data, onChange }) {
  const def = NODE_REGISTRY[nodeTypeId]
  if (!def) return null

  return Object.entries(def.fieldGroups).map(([groupLabel, fieldKeys]) => (
    <FieldGroup key={groupLabel} label={groupLabel}>
      {fieldKeys.map(key => (
        <FormField key={key} definition={def.fields.find(f => f.key === key)!} value={data[key]} onChange={onChange} />
      ))}
    </FieldGroup>
  ))
}
```

Merge `fieldConfig.ts` field and group definitions into the registry entries. Delete `fieldConfig.ts`.

### Acceptance criteria

- [ ] `PropertiesForm` has no `if (data.computeType)` or any node-type-specific branch
- [ ] Adding a new node type with custom fields requires editing only its registry entry
- [ ] `fieldConfig.ts` deleted
- [ ] All existing node type fields render correctly after the migration

---

## Issue 8: Consolidate node type knowledge into a single registry

**Labels:** `refactor` `dx` `blocked-by: #7`
**Size:** M

### Context

Adding one new node type requires editing five files: `nodeRegistry.ts`, `catalogConfig.ts`, `fieldConfig.tsx`, `themeConfig.ts`, and `PropertiesForm.tsx`. These are five independent sources of truth for the same concept.

### What to do

Define a unified `NodeTypeDefinition` in `src/renderer/src/nodes/registry.ts`:

```ts
interface NodeTypeDefinition {
  id: string
  label: string
  subLabel: string
  category: ComponentCategory
  icon: LucideIcon
  theme: { bg: string; border: string; text: string }
  rfType: 'computeNode' | 'serviceNode' | 'vpcNode'
  defaultSize?: { width: number; height: number }
  defaultNodeData: () => Partial<ComponentNode>
  fields: FieldDefinition[]
  fieldGroups: Record<string, string[]>
}

export const NODE_REGISTRY: Record<string, NodeTypeDefinition> = { ... }
```

Merge:
- `themeConfig.ts` theme entries → inline in each registry entry, delete `themeConfig.ts`
- `fieldConfig.ts` field/group definitions → inline in each registry entry (done in Issue 7)
- `catalogConfig.ts` → keep as a thin ordering file that references registry IDs only, no duplicated metadata
- `nodeRegistry.ts` → becomes the new `nodes/registry.ts`

### Acceptance criteria

- [ ] `themeConfig.ts` deleted
- [ ] `nodeRegistry.ts` (old location) deleted, replaced by `nodes/registry.ts`
- [ ] `catalogConfig.ts` contains only `{ id: string; title: string; items: string[] }[]` — no icon, theme, or field data
- [ ] Adding a new node type (e.g., `redis-cluster`) requires editing exactly one file
- [ ] All 31 existing node types are present in the new registry with correct icons, themes, fields, and default data

---

## Issue 9: Move theme state into `useAppStore` and sync to DOM via effect

**Labels:** `refactor` `state-management` `blocked-by: #2`
**Size:** S

### Context

`ThemeToggle.tsx` directly mutates `document.documentElement` and `localStorage`. The current theme is not observable from React — no component can subscribe to it.

### What to do

- `useAppStore` already has `theme` and `setTheme` per Issue 2 — this just connects the toggle to it
- Initialize `theme` from `localStorage.getItem('nss-theme') ?? 'dark'` during store creation
- Add `ThemeSync` component in `main.tsx`:

```tsx
function ThemeSync() {
  const theme = useAppStore(s => s.theme)
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem('nss-theme', theme)
  }, [theme])
  return null
}
```

- Rewrite `ThemeToggle.tsx` to call `useAppStore(s => s.setTheme)` only — no direct DOM access

### Acceptance criteria

- [ ] `ThemeToggle` contains zero `document.*` or `localStorage.*` calls
- [ ] Theme is correctly initialized from `localStorage` on cold boot
- [ ] Any component can read the current theme from `useAppStore(s => s.theme)` without parsing the DOM

---

## Issue 10: Extract `VpcNode` container bounds calculation to a canvas hook

**Labels:** `performance` `refactor` `blocked-by: #2`
**Size:** S

### Context

`VpcNode.tsx` subscribes to the global `nodes` array from `useStore` to compute its own minimum size and find its children. This means every node drag in the canvas re-renders all VPC components simultaneously.

### What to do

Create `src/renderer/src/canvas/hooks/useContainerNodeBounds.ts`:

```ts
export function useContainerNodeBounds(containerId: string): { minWidth: number; minHeight: number } {
  const children = useTopologyStore(s =>
    s.topology?.nodes.filter(n => n.parentId === containerId) ?? []
  )
  return useMemo(() => computeMinBounds(children), [children])
}
```

`VpcNode` receives `minWidth` and `minHeight` as data props from the canvas adapter, not by subscribing to the store internally.

### Acceptance criteria

- [ ] `VpcNode.tsx` has no direct `useStore` or `useTopologyStore` calls
- [ ] `useContainerNodeBounds` is the only subscriber to child node positions for a given container
- [ ] React DevTools Profiler shows VPC nodes no longer re-render on sibling node drags

---

## Issue 11: Delete dead code and empty files

**Labels:** `cleanup` `good-first-issue` `blocked-by: none`
**Size:** S

### Context

Five files are inert and should be removed before the rebuild to prevent confusion about what is canonical.

### What to do

| File | Action |
|---|---|
| `src/renderer/src/App.tsx` | Delete — never imported |
| `src/renderer/src/config/node.ts` | Delete — empty |
| `src/renderer/src/assets/base.css` | Delete — superseded by `main.css`; remove its `@import` from any entry point |
| `src/renderer/src/components/features/canvas/hooks/useFlowStore.ts` | Delete — three-line wrapper with no abstraction value |

Rename:
| File | Rename to |
|---|---|
| `src/renderer/src/config/fieldConfig.tsx` | `fieldConfig.ts` — contains no JSX |

### Acceptance criteria

- [ ] All four files deleted
- [ ] `fieldConfig.ts` renamed (`.tsx` → `.ts`)
- [ ] `tsc --noEmit` and `eslint` pass after deletions
- [ ] No broken imports introduced

---

## Issue 12: Add unit tests for engine and store layer

**Labels:** `testing` `blocked-by: #1 #2 #5`
**Size:** L

### Context

Zero test files exist. The engine and store layers are the highest-value targets — they contain pure logic that can be tested without Electron, React Flow, or a DOM.

### What to do

Install `vitest`:

```bash
npm install -D vitest @vitest/ui
```

Add to `package.json`:

```json
"scripts": {
  "test": "vitest run",
  "test:watch": "vitest",
  "test:ui": "vitest --ui"
}
```

Priority test files:

| File | Min cases |
|---|---|
| `engine/validator.test.ts` | Valid topology passes; edge with unknown node ID fails; unreachable node warns; sigma < 0 fails; duplicate node IDs fail — minimum 8 cases |
| `engine/serialization.test.ts` | Round-trip: serialize → deserialize returns identical object; corrupt JSON throws `DeserializationError` |
| `canvas/adapters.test.ts` | `topologyToRFNodes` produces correct RF format; `rfChangesToTopologyMutation` round-trips |
| `stores/useTopologyStore.test.ts` | `addNode`, `removeNode`, `updateNode`, `loadTopology` produce correct state; `validationResult` updates after each mutation |
| `engine/time.test.ts` | `msToMicro(1)` → `1000n`; `formatTime` picks correct unit |

### Acceptance criteria

- [ ] `npm test` runs and exits 0
- [ ] `engine/validator.test.ts` covers ≥ 8 cases (valid, structural errors, semantic errors, warnings)
- [ ] `engine/serialization.test.ts` covers round-trip and failure cases
- [ ] `stores/useTopologyStore.test.ts` covers all four mutation types
- [ ] CI can run `npm test` without Electron or a display server

---

## Dependency Order

```
#11 (dead code)        — no deps, do first
#1  (engine types)     — no deps, do in parallel with #11
#2  (split stores)     ← needs #1
#3  (validation UI)    ← needs #1, #2
#4  (boundary safety)  ← needs #1
#5  (hook decompose)   ← needs #2, #4
#6  (XState machine)   ← needs #2
#7  (data-driven form) ← needs #1
#8  (unified registry) ← needs #7
#9  (theme store)      ← needs #2
#10 (VPC bounds hook)  ← needs #2
#12 (tests)            ← needs #1, #2, #5
```

Issues 11, 1, and 4 can all start immediately with no blockers.
Issues 2 and 5 are the critical path — most downstream issues unblock once they land.

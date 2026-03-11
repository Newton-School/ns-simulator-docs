# Critical Problems — NS-Simulator UI Layer

> A precise catalogue of the structural defects in the current renderer codebase. Each problem is stated, its consequence explained, and the fix described.

---

## Overview

The codebase has the right component hierarchy and the right libraries. The problems are in the connections between layers — specifically how the domain model, the state, and the components are wired together. None of these require rewriting the UI; they require reconnecting it correctly.

---

## Problem 1: The Engine and Renderer Are Two Disconnected Programs

**Severity: Critical**

`src/engine/` defines a complete domain model:

```
types.ts      — ComponentNode, EdgeDefinition, TopologyDocument, DistributionConfig, ...
validator.ts  — Zod schemas + validateTopology()
events.ts     — SimulationEvent, Request, RequestSpan
time.ts       — BigInt microsecond utilities
```

None of this is imported by the renderer. The renderer maintains its own parallel, informal type system in `src/renderer/src/types/ui.ts`:

```ts
interface ComputeNodeData { cpu_usage: number; queue_depth: number; is_overloaded: boolean }
interface ServiceNodeData { iconKey: string; status?: 'healthy' | 'degraded' | 'critical' }
```

These are view types, not domain types. There is no code that:
1. Maps `ServiceNodeData` → `ComponentNode` before saving to disk
2. Validates the canvas topology against `TopologyJSONSchema` at edit time
3. Prepares a `TopologyDocument` for the simulation engine

**Consequence:** The file saved to disk is a React Flow snapshot, not a valid topology document. The simulation engine cannot consume what the UI produces.

**Fix:**
- Add `@engine` path alias in `electron.vite.config.ts`
- Store a `TopologyDocument | null` as the canonical model in `useTopologyStore`
- Write `canvas/adapters.ts` with typed conversions between `TopologyDocument` and React Flow `Node[]`/`Edge[]`
- Add `_uiPosition: { x: number; y: number }` to `ComponentNode` — the only UI field allowed in the domain model
- Delete `types/ui.ts` informal types once the adapter is in place

---

## Problem 2: One Store Does Everything

**Severity: High**

`useStore.ts` is a single Zustand store holding:

```ts
// React Flow plumbing
onNodesChange, onEdgesChange, onConnect

// Canvas data
nodes: Node[], edges: Edge[]

// App/file metadata
fileName: string | null, isUnsaved: boolean
```

Any component that reads `nodes` for any reason re-renders on every canvas change, including components that only care about `fileName`.

Additionally, `useFlowStore.ts` (in `canvas/hooks/`) is a thin wrapper around the same store that provides the illusion of abstraction while changing nothing.

**Consequence:** As topology size grows, every drag operation re-renders unrelated panels (file status bar, properties panel header). This will become a visible performance problem.

**Fix:** Three stores, separated by concern. Full detail in `adr-state-management.md`.

---

## Problem 3: `useFlowPersistence` Violates Single Responsibility

**Severity: High**

`useFlowPersistence.ts` is a single hook that does four independent things:

```
1. Registers keyboard shortcuts (Ctrl+S, Ctrl+O)
2. Serializes flat RF nodes → nested JSON string
3. Deserializes nested JSON → flat nodes + store mutations
4. Orchestrates file dialog calls via FileService
```

Each of these changes for different reasons. The keyboard shortcut logic should change when keybindings are configurable. The serialization logic should change when the file format version changes. The dialog logic should change when cloud sync is added.

**Consequence:** Every format change requires touching a hook that also owns UI keyboard bindings. Every keyboard change touches serialization logic.

**Fix:**
- `useKeyboardShortcuts.ts` — registers shortcuts globally
- `useFilePersistence.ts` — save/load with validation and UI error feedback
- `engine/serialization.ts` — `serializeTopology()` and `deserializeTopology()` as pure functions

---

## Problem 4: No Validation Feedback in the UI

**Severity: High**

`engine/validator.ts` has a complete `validateTopology()` function that:
- Parses through Zod schemas
- Checks cross-references (node IDs in edges)
- Runs BFS connectivity analysis
- Returns structured `{ errors[], warnings[] }` with path-specific messages

It is never called from the renderer. The user can create an edge to a non-existent node, configure an impossible distribution (sigma: -1), or build a completely disconnected topology — and receive no feedback.

**Consequence:** Users discover topology errors only when the simulation crashes, not during design.

**Fix:** Call `validateTopology()` inside every topology store mutation. Store the `ValidationResult` in `useTopologyStore`. Render errors in a `ValidationPanel` organism. File save should warn (not block) if validation has errors.

---

## Problem 5: Type Safety Holes at Every External Boundary

**Severity: High**

These are the `any` escapes at the exact boundaries where validation matters most:

| Location | Code | Risk |
|---|---|---|
| `useStore.ts` | `updateNodeData(nodeId, data: any)` | Silently corrupts node data |
| `preload/index.ts` | `runSimulation(config: any)` | Unvalidated data crosses IPC to main process |
| `useFlowDnD.ts` | `JSON.parse(event.dataTransfer.getData(...))` | Malformed drag payload crashes state |
| `FileService.ts` | Return type re-parsed without schema | Corrupt file partially loads into store |
| `PropertiesPanel.tsx` | Selected node `data` cast without narrowing | Wrong field renders for wrong node type |

The Zod schemas in `engine/validator.ts` already exist. They need to be used at these five locations.

**Fix:**
- Define `DragPayloadSchema` and use `.safeParse()` in `useFlowDnD`
- Route all file load operations through `deserializeTopology()` which throws on failure
- Narrow `config: any` in `runSimulation` to a typed IPC argument
- Replace `data: any` in `updateNodeData` with a generic: `updateNodeData<T extends ComponentNode>(id: string, patch: Partial<T>): void`

---

## Problem 6: `PropertiesForm` Has Hardcoded Type Branches

**Severity: Medium**

```tsx
// PropertiesForm.tsx
if (data.computeType) {
  // Special render path: execution model dropdown, overload checkbox
}
// Then falls through to generic field loop
```

The form knows about specific node types. Adding any node with custom form behavior requires editing `PropertiesForm`.

**Consequence:** Open/Closed violation. The form is open for modification, not extension.

**Fix:** Each `NodeTypeDefinition` in the registry declares its own `fields: FieldDefinition[]` and `fieldGroups`. `PropertiesForm` becomes:

```tsx
function PropertiesForm({ nodeTypeId, data }) {
  const def = NODE_REGISTRY[nodeTypeId]
  return def.fieldGroups.map(group => renderGroup(group, def.fields, data))
}
```

Zero type-specific branches. New node types need zero form changes.

---

## Problem 7: Theme State Lives Outside React

**Severity: Medium**

`ThemeToggle.tsx` directly mutates the DOM and `localStorage`:

```tsx
document.documentElement.setAttribute('data-theme', newTheme)
localStorage.setItem('theme', newTheme)
```

The current theme value is not observable from React. No other component can subscribe to it.

**Consequence:** If any component needs to conditionally render based on theme (e.g., a chart that uses different colors), it must re-read `localStorage` or parse the DOM attribute manually.

**Fix:** `theme: 'light' | 'dark'` lives in `useAppStore`. Initialize from `localStorage` during store creation. A `ThemeSync` component at the root syncs the store value to the DOM via `useEffect`. `ThemeToggle` calls `setTheme()` from the store only.

---

## Problem 8: Node Type Knowledge Is Scattered Across Five Files

**Severity: Medium**

Adding one new node type requires editing:

| File | What it needs |
|---|---|
| `nodeRegistry.ts` | Icon, lookupKey, default data |
| `catalogConfig.ts` | Which sidebar category |
| `fieldConfig.tsx` | Which form fields |
| `themeConfig.ts` | Color theme |
| `PropertiesForm.tsx` | Any special form rendering |

**Consequence:** Open/Closed violated. Adding `redis-cluster` as a node type is a five-file change with no single authoritative location.

**Fix:** One `NodeTypeDefinition` interface in `nodes/registry.ts`. All five files become consumers of the registry, not independent sources of truth.

---

## Problem 9: VPC Container Node Reads Global Store Internally

**Severity: Medium**

`VpcNode.tsx` subscribes to the global `nodes` array to compute its own minimum size and find its children:

```tsx
// Inside VpcNode component
const nodes = useStore(s => s.nodes)
const children = nodes.filter(n => n.parentNode === id)
const minSize = computeMinBounds(children)
```

A render component is doing structural layout queries against the full node list.

**Consequence:** Every node drag in the canvas re-renders all VPC node components simultaneously, because they all watch `nodes`.

**Fix:** Extract to `useContainerNodeBounds(containerId)` in `canvas/hooks/`. The hook runs in the canvas adapter layer, not inside the component. The component receives `minWidth` and `minHeight` as props.

---

## Problem 10: Dead Code and Empty Files

**Severity: Low**

| File | Status |
|---|---|
| `src/renderer/src/App.tsx` | Never imported. `main.tsx` renders `WorkspaceLayout` directly. |
| `src/renderer/src/config/node.ts` | Empty. Has been empty since creation. |
| `src/renderer/src/assets/base.css` | Superseded by `main.css`. Contains conflicting `--color-background` and `--color-text` variables that shadow nothing. |
| `src/renderer/src/config/fieldConfig.tsx` | `.tsx` extension with zero JSX. |
| `src/renderer/src/components/features/canvas/hooks/useFlowStore.ts` | A three-line wrapper that adds no abstraction. |

**Fix:** Delete all five. Rename `fieldConfig.tsx` → `fieldConfig.ts` when merging into the node registry.

---

## Priority Order

Fixing in this order maximizes unblocking:

1. **Problem 1** (engine-renderer connection) — everything else depends on having a real domain model in the store
2. **Problem 2** (store split) — needed before fixing validation and type safety
3. **Problem 4** (validation feedback) — immediately visible user value, unlocks safe file I/O
4. **Problem 5** (type safety at boundaries) — prevents silent data corruption
5. **Problem 3** (hook decomposition) — refactor, unblocks testability
6. **Problems 6–8** (registry, form, theme) — architectural improvements, parallel workstreams
7. **Problem 9** (VPC store subscription) — performance, noticeable only at scale
8. **Problem 10** (dead code) — housekeeping, do any time

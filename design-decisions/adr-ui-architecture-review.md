# UI Architecture Review — NS-Simulator

> A comprehensive review of the current renderer codebase: what's working, what the component hierarchy looks like, and the design decisions that should be locked in before the rebuild.

---

## Context

The NS-Simulator renderer is an Electron + React + TypeScript application built with:

- **React 19** + TypeScript 5.9
- **React Flow 11** for the canvas
- **Zustand 5** for state
- **Zod 4** for validation
- **Tailwind CSS 3** with CSS custom properties
- **react-resizable-panels** for layout
- **electron-vite** as the build system

This review covers the UI layer only (`src/renderer/`). The engine layer (`src/engine/`) is covered separately.

---

## What Is Good — Lock These In

These patterns are correct and should be preserved in the rebuild without modification.

### 1. Atomic Design Component Hierarchy

The component tree follows atomic design correctly:

```
atoms/          — no state, pure display (Button, Input, Select, Slider, Badge)
molecules/      — compose atoms, internal interaction state only (FormField, NodeHeader)
organisms/      — feature-level, connect to stores (Header, LibrarySidebar, FlowCanvas)
templates/      — layout only (WorkspaceLayout)
features/       — canvas-specific nodes and canvas hooks
```

This is the right vocabulary. Every contributor immediately knows where a new component goes and what it's allowed to do.

### 2. CSS Custom Properties + Tailwind Integration

The theming approach is correct:

```css
/* main.css */
:root { --nss-primary: 37 99 235; /* rgb triplet for opacity support */ }
[data-theme='dark'] { --nss-primary: 59 130 246; }
```

```js
// tailwind.config.js
colors: { nss: { primary: 'rgb(var(--nss-primary) / <alpha-value>)' } }
```

Two themes, one variable namespace, Tailwind opacity modifiers work (`bg-nss-primary/20`). This is the right pattern — no runtime cost, no JS theme injection.

### 3. `nodeTransformers.ts` as a Pure Utility

The flat ↔ nested conversion for file I/O is correctly isolated:

```
convertNestedToFlat(nestedNodes): Node[]
convertFlatToNested(flatNodes): NestedNode[]
```

No React imports, no store access — pure functions. This is exactly where this logic belongs.

### 4. IPC Security in the Preload

The preload validates before invoking IPC:

```ts
saveScenario: (jsonString: string) => {
  if (!jsonString || jsonString.length > 1_000_000) return null
  return ipcRenderer.invoke('dialog:save', jsonString)
}
```

Size limits and type checks at the boundary. Correct. Keep this pattern; extend it when new IPC channels are added.

### 5. CSS Handle-State Trick

The source/target handle swap during connection dragging is elegant:

```css
body.rel-flow-connecting .custom-source-handle { opacity: 0; pointer-events: none; }
body.rel-flow-connecting .custom-target-handle { z-index: 20; pointer-events: all; }
```

A class on `body` flips which handles are interactive during a drag. No JavaScript overhead, no React state.

### 6. `PacketEdge` + `TrafficParticle`

Animated edges using SVG `animateMotion` are performant and self-contained:

```tsx
<animateMotion dur={speed} repeatCount="indefinite" path={svgPath} />
```

The animation runs in the browser's compositor thread — no JavaScript animation loop.

### 7. `useFlowDnD` + `canvasUtils`

Drag-drop and VPC re-parenting are extracted from the canvas component into dedicated hooks and utilities. The `findTargetVpc` function (BFS by smallest bounding area) is correctly isolated in `canvasUtils.ts`.

---

## Component Responsibility Model

This is the contract each layer must respect in the rebuild.

### Atoms

- No store access
- No hooks except `useMemo` for derived styles
- All props explicitly typed — no `data: any`, no spreading unknown objects
- Export a `Props` type from every atom file

### Molecules

- Can hold `useState` for internal interaction (hover, menu open/closed)
- Receive all data via props — no direct store reads
- No business logic — transform and display only

### Organisms

- Read from stores via selectors
- Dispatch store actions
- Own async operations (file save, validation trigger)
- One organism per major panel region

### Features (canvas nodes)

- Receive only display data through the `data` prop from React Flow
- The canvas adapter populates `data` — the component renders it
- No store subscriptions inside node components

---

## The Node Registry Contract

Every node type must define its shape in one place. The unified `NodeTypeDefinition` interface:

```ts
interface NodeTypeDefinition {
  id: string
  label: string
  subLabel: string
  category: ComponentCategory

  // Visual
  icon: LucideIcon
  theme: { bg: string; border: string; text: string }

  // Canvas
  rfType: 'computeNode' | 'serviceNode' | 'vpcNode'
  defaultSize?: { width: number; height: number }

  // Domain
  defaultNodeData: () => Partial<ComponentNode>

  // Form — drives PropertiesForm, no hardcoded type checks in the form
  fields: FieldDefinition[]
  fieldGroups: Record<string, string[]>
}
```

Adding a new node type = one new entry in `NODE_REGISTRY`. No other file changes.

---

## File Structure — Renderer

```
src/renderer/src/
├── main.tsx                       # React root + ThemeSync + StoreInit
│
├── stores/
│   ├── useTopologyStore.ts        # Domain state (ComponentNode[], EdgeDefinition[])
│   ├── useCanvasStore.ts          # React Flow UI state (rfNodes, rfEdges, selectedNodeId)
│   └── useAppStore.ts             # UI/session state (theme, filePath, isDirty, panels)
│
├── services/
│   └── FileService.ts             # IPC bridge (save/load topology JSON)
│
├── canvas/
│   ├── adapters.ts                # TopologyDocument ↔ RF Node/Edge conversion
│   ├── hooks/
│   │   ├── useFlowDnD.ts
│   │   ├── useContainerNodeBounds.ts
│   │   └── useKeyboardShortcuts.ts
│   └── utils/canvasUtils.ts
│
├── nodes/
│   ├── registry.ts                # NodeTypeDefinition records (single source of truth)
│   ├── catalogConfig.ts           # Sidebar categories (references registry IDs only)
│   └── types/
│       ├── ComputeNode.tsx
│       ├── ServiceNode.tsx
│       └── VpcNode.tsx
│
├── components/
│   ├── atoms/
│   ├── molecules/
│   ├── organisms/
│   └── templates/WorkspaceLayout.tsx
│
├── hooks/
│   ├── useFilePersistence.ts      # Save/load with validation + error feedback
│   └── useTheme.ts                # Reads/writes theme to appStore
│
└── assets/main.css                # Tailwind + CSS custom properties (one file only)
```

---

## Decision

The current atomic design hierarchy, theming approach, IPC security model, and utility isolation patterns are correct and should be preserved in the rebuild.

The renderer's component structure does not need to be redesigned — it needs to be reconnected to the domain model (see `adr-critical-problems.md`) and have its state management properly separated (see `adr-state-management.md`).

The node registry must be unified into a single `NodeTypeDefinition` interface. All per-type knowledge (icon, theme, fields, default data) lives in one record. This is the highest-leverage structural change available.

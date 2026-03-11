# State Management — Zustand + XState

> Decision: use Zustand for data stores, XState v5 for the simulation runner state machine. No other state libraries.

---

## Context

The application has two fundamentally different state problems that require different tools.

The first is covered in `adr-no-custom-change-detection.md`: the BUILD phase (topology editing) and the SIMULATE phase (engine → UI via Web Worker). That document resolves the reactivity question correctly.

This document resolves a more specific question: within the SIMULATE phase, what manages the lifecycle of the simulation runner itself — the state machine that governs idle → validating → running → paused → complete/error?

---

## The Two State Problems

### Problem A — Data State (stores)

Topology nodes, edges, workload config, file metadata, panel visibility, theme. This is CRUD data with derived values. The shape is stable, the mutations are explicit, and components subscribe selectively.

**Zustand is the right tool for this.**

### Problem B — Process State (simulation runner lifecycle)

The simulation runner has a finite set of states and a finite set of valid transitions between them:

```
idle
  ├── RUN ──────────────────► validating
  └── (no other transitions)

validating
  ├── VALID ─────────────────► running
  ├── INVALID ───────────────► error
  └── (can't PAUSE, can't STOP — not started yet)

running
  ├── PAUSE ─────────────────► paused
  ├── STOP ──────────────────► idle
  ├── COMPLETE ──────────────► complete
  └── ERROR ─────────────────► error

paused
  ├── RESUME ────────────────► running
  ├── STOP ──────────────────► idle
  └── (can't RUN — already ran)

complete
  ├── RUN ──────────────────► validating   (run again)
  └── (can't PAUSE — nothing running)

error
  ├── RUN ──────────────────► validating   (retry)
  └── (can't PAUSE — nothing running)
```

The Web Worker is created when entering `running`, and terminated when entering `idle`, `complete`, or `error`. This is a resource that is owned by a specific state.

**XState is the right tool for this.**

---

## Why Not Zustand for the Simulation Runner

The simulation runner modeled in Zustand requires manually guarded actions everywhere:

```ts
const useSimulationStore = create((set, get) => ({
  status: 'idle',
  worker: null,

  run: (topology) => {
    const { status } = get()
    // Manual guard — nothing enforces this structurally
    if (status !== 'idle' && status !== 'complete' && status !== 'error') return
    set({ status: 'validating' })
    // Async validation...
    // Spin up worker...
    // Wire worker.onmessage...
    // What if run() is called again before validation completes?
  },

  pause: () => {
    if (get().status !== 'running') return  // Manual guard
    get().worker?.postMessage({ type: 'PAUSE' })
    set({ status: 'paused' })
  },

  stop: () => {
    const { worker } = get()
    if (worker) {
      worker.terminate()  // Must remember to clean up
      set({ worker: null })
    }
    set({ status: 'idle' })
  }
}))
```

The problems with this approach:

1. **Guards are invisible.** Nothing in the type system prevents calling `pause()` when `status` is `validating`. The guard exists only as a runtime `if` check that can be forgotten or broken.

2. **Race conditions are possible.** If `run()` is called twice before the async validation resolves, both calls pass the `status !== 'idle'` check simultaneously and both spin up workers.

3. **Resource cleanup is manual.** The Worker must be terminated in multiple places (stop, error, complete). Missing one leaks a Worker.

4. **The async validation transition has no natural place.** Where does the `validating → running` transition live? In an effect? In the async callback? There's no clean answer in Zustand.

---

## Why XState for the Simulation Runner

XState models the simulation runner as an explicit state machine. Impossible transitions are structurally impossible — not guards you write, but transitions that don't exist in the config.

```ts
import { createMachine, assign, fromPromise } from 'xstate'

const simulationMachine = createMachine({
  id: 'simulation',
  initial: 'idle',

  context: {
    topology: null,
    progress: 0,
    result: null,
    error: null,
    worker: null,
  },

  states: {
    idle: {
      on: { RUN: { target: 'validating', actions: assign({ topology: ({ event }) => event.topology }) } }
    },

    validating: {
      invoke: {
        src: fromPromise(({ input }) => validateAsync(input.topology)),
        onDone:   { target: 'running' },
        onError:  { target: 'error', actions: assign({ error: ({ event }) => event.error.message }) }
      }
      // No PAUSE, no STOP — these transitions don't exist here
    },

    running: {
      entry: 'spawnWorker',   // Worker created on entry
      exit:  'terminateWorker', // Worker terminated on exit — always, automatically

      on: {
        PAUSE:    'paused',
        STOP:     'idle',
        COMPLETE: { target: 'complete', actions: assign({ result: ({ event }) => event.result }) },
        ERROR:    { target: 'error',    actions: assign({ error: ({ event }) => event.message }) },
        SNAPSHOT: { actions: 'forwardSnapshotToResultsStore' },
        PROGRESS: { actions: assign({ progress: ({ event }) => event.percent }) }
      }
    },

    paused: {
      entry: ({ context }) => context.worker?.postMessage({ type: 'PAUSE' }),
      on: {
        RESUME: { target: 'running', actions: ({ context }) => context.worker?.postMessage({ type: 'RESUME' }) },
        STOP:   'idle'
        // No RUN — can't start a new run while paused
      }
    },

    complete: {
      on: { RUN: { target: 'validating', actions: assign({ result: null }) } }
    },

    error: {
      on: { RUN: { target: 'validating', actions: assign({ error: null }) } }
    }
  }
})
```

Key properties:

- **Impossible transitions are structurally absent.** `PAUSE` has no handler in `validating`. Sending it does nothing. No `if` check needed.
- **Worker lifecycle is tied to the `running` state.** `entry: 'spawnWorker'` and `exit: 'terminateWorker'` guarantee cleanup. No Worker leak is possible.
- **Async validation is a first-class concept.** `invoke` with `fromPromise` handles the async transition naturally.
- **Race conditions are prevented.** XState processes one transition at a time. A second `RUN` event during `validating` has nowhere to go.

---

## The Boundary

This is the only place XState is used. The three data stores remain Zustand:

| Store | Tool | Reason |
|---|---|---|
| `useTopologyStore` | Zustand | CRUD data, stable shape, selective subscriptions |
| `useCanvasStore` | Zustand | Derived data (RF nodes/edges), frequent updates |
| `useAppStore` | Zustand | Simple key-value (theme, filePath, panels) |
| `useSimulationResultsStore` | Zustand | Time-series snapshots, final output — data, not process |
| Simulation runner lifecycle | **XState v5** | Genuine state machine with guarded transitions and resource ownership |

The machine interacts with Zustand:
- It reads `useTopologyStore.getState().topology` when `RUN` is sent
- It calls `useSimulationResultsStore.getState().addSnapshot(snapshot)` when a `SNAPSHOT` message arrives from the Worker
- It calls `useSimulationResultsStore.getState().setResult(result)` on `COMPLETE`

The Zustand stores never know about the machine. The machine knows about the stores.

---

## Worker Message Protocol

Defined in `src/worker/protocol.ts` and shared between the machine and the Worker:

```ts
// UI → Worker (machine sends these)
export type WorkerCommand =
  | { type: 'RUN';    payload: TopologyDocument }
  | { type: 'PAUSE'  }
  | { type: 'RESUME' }
  | { type: 'STOP'   }
  | { type: 'STEP';   count: number }

// Worker → UI (machine receives these)
export type WorkerMessage =
  | { type: 'PROGRESS'; percent: number; eventsProcessed: number }
  | { type: 'SNAPSHOT'; data: TimeSeriesSnapshot }
  | { type: 'COMPLETE'; result: SimulationOutput }
  | { type: 'ERROR';    message: string }
```

The machine's `running` state handles incoming Worker messages as XState events. The Worker's `postMessage` calls map directly to events the machine dispatches via `worker.onmessage`.

---

## Integration in React

```tsx
// hooks/useSimulation.ts
import { useMachine } from '@xstate/react'
import { simulationMachine } from '../machines/simulationMachine'

export function useSimulation() {
  const [state, send] = useMachine(simulationMachine)

  return {
    status:   state.value,           // 'idle' | 'validating' | 'running' | 'paused' | 'complete' | 'error'
    progress: state.context.progress,
    error:    state.context.error,

    run:    (topology: TopologyDocument) => send({ type: 'RUN', topology }),
    pause:  () => send({ type: 'PAUSE' }),
    resume: () => send({ type: 'RESUME' }),
    stop:   () => send({ type: 'STOP' }),
  }
}
```

The `SimulationControls` organism consumes this hook. The machine state drives which buttons are enabled:

```tsx
function SimulationControls() {
  const { status, run, pause, resume, stop } = useSimulation()
  const topology = useTopologyStore(s => s.topology)

  return (
    <>
      <Button onClick={() => run(topology!)} disabled={status !== 'idle' && status !== 'complete' && status !== 'error'}>
        Run
      </Button>
      <Button onClick={pause}  disabled={status !== 'running'}>Pause</Button>
      <Button onClick={resume} disabled={status !== 'paused'}>Resume</Button>
      <Button onClick={stop}   disabled={status === 'idle'}>Stop</Button>
    </>
  )
}
```

---

## What to Install

```bash
npm install xstate @xstate/react
```

Zustand is already installed. No other state libraries are needed or appropriate. The combined bundle cost of XState v5 + `@xstate/react` is ~15kB gzipped — acceptable for the value it provides.

---

## Decision

- **Zustand** for all data stores (`useTopologyStore`, `useCanvasStore`, `useAppStore`, `useSimulationResultsStore`)
- **XState v5** for the simulation runner lifecycle machine only
- **No Redux, Valtio, Jotai, or React Context** for application state — each adds complexity without solving problems this project actually has

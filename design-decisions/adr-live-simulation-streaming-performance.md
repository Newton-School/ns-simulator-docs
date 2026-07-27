# ADR: Live-Simulation Event Streaming Performance

**Status:** Proposed
**Date:** 2026-07-22
**Deciders:** Simulator engine + renderer owners
**Area:** Runtime / engine ⇄ UI data plane
**Related:** [adr-state-management.md](adr-state-management.md), [adr-no-custom-change-detection.md](adr-no-custom-change-detection.md), [adr-ui-architecture-review.md](adr-ui-architecture-review.md)

---

## TL;DR

During a live simulation the main thread is starved because the engine streams **one message per simulated edge traversal** to the UI, and the store does **O(history-size) work on every one of them**. The result is a jumpy "Elapsed" timer, a frozen histogram / Busiest-Nodes / Event-Log, and — on heavy runs — a fully wedged tab.

The physics of the simulation are **not** the problem. The **data plumbing** is. We will fix it by doing **less work, less often, in bigger chunks**: batch events on the worker, collapse each batch into a **single** store write and a **single** render, and stop copying large arrays per event. Decimation of the live visual stream and a ring buffer are held as contingent follow-ups, gated on measurement.

This is a **performance-only** change. It does not alter any simulation result, metric, or number.

---

## Context

### Two clocks, not one

The product has two independent notions of time, and conflating them is the source of most confusion here:

1. **Compute time** — how long the engine takes to *calculate* a run (wall-clock).
2. **Reveal / playback time** — how long you *watch* the run unfold.

Playback is already decoupled: the post-run paced transport (play / pause / step / scrub / 0.5×–4×) replays buffered snapshots at whatever speed the user chooses, independent of how long compute took. **That half is solved.** This ADR is exclusively about the **compute + live-view** half.

### The symptom that surfaced it

While a run is in progress, the Live Monitor's **Elapsed** timer (real wall-clock) does not tick like a stopwatch — it **freezes and jumps**. The heavier the scenario (higher RPS, more nodes, longer duration, saturating pattern), the worse it gets, culminating in the whole tab freezing on a ~600 rps multi-hop run.

The timer value is never *wrong* — `Date.now()` is exact. Its **updates** are starved: it is driven by a `setInterval(…, 100)` on the main thread (in `LiveMonitorPanel`, `src/renderer/src/components/simulation/ResultsTray.tsx`), and a `setInterval` callback cannot preempt a busy call stack. If the thread is mid–array-copy or mid-render, the tick just waits in the task queue, then snaps forward when the thread frees up.

So "the timer feels slow" is a **proxy metric for main-thread saturation**. Everything else that should update live during a run (histogram, Busiest Nodes, Event Log) suffers the same starvation.

### The algorithmic floor is fine

A discrete-event simulation is not a closed-form calculation; it must process every event in causal order. Work is **Θ(events)**, where `events ≈ requests × events-per-request` and `requests = RPS × duration`. A clean single hop is ~6–7 canonical events; a saturating hop adds queue/reject/timeout events, so the multiplier is not constant. This floor is **inherent** — a million-request run is genuinely millions of state transitions, and no engine makes that constant-time.

But the intrinsic cost of a few million events is **order-seconds**. When runs take **minutes** or wedge the tab, the cause is not the arithmetic — it is the per-event data plumbing described below.

---

## Root-cause analysis: the per-event firehose

For **every** edge traversal, the following chain executes:

```
engine.emitEdgeFlowEvent()                       // src/engine/engine.ts  (once per hop)
  → worker: post({ type: 'edge-flow', … })       // src/engine/worker/simulation.worker.ts:100
    → main thread onmessage                        // src/renderer/src/hooks/useSimulation.ts:80
      → useStore.recordEdgeFlowEvent(event)        // src/renderer/src/store/useStore.ts:320
        → [...edgeFlowHistory, e].slice(-100_000)  //   O(history size) array copy   ← hot
        → [...previous.recent, e].filter(window)   //   O(window) spread + filter
        → set({ edgeFlowById: {…spread…}, … })     //   O(edges) object spread
          → zustand notifies subscribers            //   React re-render               ← hot
```

Per-event costs, in order of severity:

| Cost | Where | Complexity per event | Why it hurts |
|------|-------|----------------------|--------------|
| **History array copy** | `[...edgeFlowHistory, e].slice(-100_000)` (`useStore.ts:339`) | **O(100k)** once the buffer fills | Copies up to 100,000 elements on *every* event. Over a run: **O(events × 100k)** — linear in events with a punishing constant. |
| **Cross-thread message** | `post({ type:'edge-flow' })` per hop (`worker:100`) | O(1) each, but **N/sec** | Structured-clone serialize on the worker + a main-thread task per event. Thousands/sec. Also slows the *worker* (engine) itself. |
| **Per-render reconciliation** | one store `set` → one React render per event | O(rendered) | Thousands of renders/sec of the live panels. |
| **Per-edge window + object spread** | `recent` spread+filter and `{...edgeFlowById}` (`useStore.ts:336,370`) | O(window), O(edges) | Additional per-event allocations and copies beyond the one big array. |

### Correcting two common mis-diagnoses

- **"It's a Garbage-Collection stop-the-world freeze."** Overstated. Modern V8 (Orinoco) does most GC incrementally/concurrently; a single long stop-the-world pause is a dated mental model. Allocation churn from throwing away 100k-element arrays *contributes*, but the **dominant** cost is the **direct synchronous work** — the copy itself and the sheer volume of store updates + renders. Fix the allocation, yes — but for the right reason.
- **"It's O(n²)."** Loose. It is **O(events × 100k)** — linear in events with a large constant, not literally quadratic. Same fix; just don't misstate the complexity.

### Why batching the messages is necessary but **not sufficient**

If we batch `postMessage` but the receiver still loops over the batch calling the existing per-event `recordEdgeFlowEvent` (each doing the O(100k) copy), we have **relocated the flood, not removed it**. The main-thread CPU cost is unchanged and the timer stays blocked.

Batching only pays off when the receiver **collapses each batch into a single store write and a single render**. And once the store write is batched, a plain `[...history, ...batch].slice(-100_000)` runs ~60×/sec instead of thousands — roughly 6M element-copies/sec, which is trivial. **That observation is what makes the ring buffer *contingent* rather than mandatory.**

### Worker is also single-threaded

The worker drives the engine in synchronous chunks (`CHUNK_SIZE = 20_000`, `simulation.worker.ts:7`). A `setInterval(…, 16)` **on the worker will not fire mid-chunk** — it would buffer 20k events and flush once. So the worker-side flush must be triggered by a **size threshold checked inside the step loop and/or at the chunk boundary**, not by a timer alone. `CHUNK_SIZE` likely needs lowering for responsiveness.

---

## Forces / constraints

- **No change to results.** Metrics, outcomes, latencies, and reproducibility must be byte-identical. This is plumbing only.
- **Preserve the two-clocks model.** Engine computes flat-out; playback reveals at chosen speed. Nothing here should re-pace the engine.
- **Keep the honest-metrics contract.** Live views are projections; the authoritative data (`timeSeries`, `requestOutcomes`, aggregated metrics) already exists post-run and must remain the source of truth.
- **Incremental + measurable.** Land the cheap, safe wins first; re-measure before investing in invasive structures.
- **Small topologies must not regress.** The common case (2–4 nodes, modest RPS) already works; do not add overhead that hurts it.

---

## Options considered

### Option A — Do nothing

| Dimension | Assessment |
|-----------|------------|
| Complexity | None |
| Cost | Zero build, high ongoing |
| Scalability | Fails on the *interesting* (heavy, saturating) scenarios |

**Pros:** No work.
**Cons:** The tool falls over on exactly the high-load / bursty / many-node runs that are the most pedagogically valuable. Live view unusable under load. Not viable.

### Option B — Worker-side batching **+ collapsed store write** (chosen core)

Accumulate edge-flow events on the worker; flush a batch (size threshold and/or chunk boundary) as **one** `postMessage`. On the main thread, a new `recordEdgeFlowEventBatch(events)` performs **one** array append and **one** `set` for the whole batch.

| Dimension | Assessment |
|-----------|------------|
| Complexity | Low–Medium |
| Cost | Small, isolated |
| Scalability | Removes the per-event flood at the source; renders drop to ~1/frame |

**Pros:** Attacks all three top costs at once (messages, copies, renders). Safe, local, no data-model change. Alone should unblock the Elapsed timer.
**Cons:** Requires the receiver to be genuinely batched (single write/render). Worker flush must respect the synchronous chunk (size threshold, not timer).

### Option C — Live-stream decimation ("do less")

If the only live consumer of the per-event stream is the canvas packet animation, emit/forward only a **sampled fraction** (e.g. every Nth event) for the live visual. Authoritative data is unaffected (metrics/outcomes derive from the full dataset).

| Dimension | Assessment |
|-----------|------------|
| Complexity | Low |
| Cost | Minimal |
| Scalability | Cuts volume by the sampling factor before it hits the store |

**Pros:** The highest-leverage move — stops sending data nobody needs at full fidelity. Can make Option D unnecessary.
**Cons:** Live packet animation becomes representative, not 1:1 (acceptable — it is decoration, not data). Needs a decision on sampling policy.

### Option D — Ring buffer for history (contingent)

Replace the flat `edgeFlowHistory` array + `slice()` with a pre-allocated fixed-size circular buffer (`head` pointer, O(1) write, re-render via a version counter).

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium–High |
| Cost | Buffer write is trivial; **read-side rewrite is the real cost** |
| Scalability | O(1) amortized writes, near-zero allocation |

**Pros:** Eliminates the large-array allocation entirely; O(1) writes regardless of volume.
**Cons:** Every consumer that reads history — the Event Log's "events up to `currentSimMs`", time-window filtering, per-edge aggregation — must become **wraparound-aware**. Real, invasive work. **Likely unnecessary** if B (batched write) + C (decimation) already reduce volume enough — a single `slice` at 60fps is cheap.

### Option E — Eliminate the live stream; reconstruct from snapshots

Do not stream per-event edge flow at all during compute. Drive the live view (and the canvas) from the periodic `timeSeries` snapshots we already collect, and reconstruct fine-grained detail post-run from `requestOutcomes` / `eventStream`.

| Dimension | Assessment |
|-----------|------------|
| Complexity | Medium (re-wires the live view's data source) |
| Cost | Removes an entire data path |
| Scalability | Best possible — the firehose ceases to exist |

**Pros:** The purest "do less." Fully aligned with the two-clocks model (we already replay from snapshots).
**Cons:** Loses live per-packet animation fidelity unless partially reintroduced via C. Larger behavioral change; defer until B/C are measured.

---

## Decision

Adopt a **phased plan that runs the cheap "do less" moves first and gates the invasive ones on measurement.** The key correction over the naive plan: **do not commit to the ring buffer before proving it is still needed.**

### Phase 1 — Batch at the source + collapse the sink *(Option B, do first)*

1. Worker accumulates edge-flow events into a local array; flush as one `postMessage` on a **size threshold** (checked in the step loop) and/or at each **chunk boundary**. Lower `CHUNK_SIZE` as needed for cadence.
2. Add `recordEdgeFlowEventBatch(events)` that does **one** array operation and **one** `set` per batch — never per event.
3. Drop the per-event `{...edgeFlowById}` object spread in favor of a mutable-with-version-bump update (consistent with [adr-no-custom-change-detection.md](adr-no-custom-change-detection.md) / [adr-state-management.md](adr-state-management.md)).

**Re-measure here.** Phase 1 alone is expected to unblock the Elapsed timer and the live panels.

### Phase 2 — Decide the live data contract *(Option C / E, a decision, not just code)*

Determine whether the live view needs every event or a **decimated** sample. If a sampled stream produces the same visual, implement decimation at the emission/forward boundary. This step **gates** whether Phase 3 is needed at all.

### Phase 3 — Ring buffer *(Option D, contingent)*

Implement the ring buffer **only if** Phases 1–2 show the store is still a bottleneck at full volume. Includes the wraparound-aware read-side rewrite. Treated as contingent, not committed.

> Rationale for the ordering: Phases 1–2 are cheap, safe, and reversible, and either can make Phase 3 unnecessary. Building the ring buffer (and rewriting every history consumer) before proving it is required would be over-engineering.

---

## Trade-off analysis

- **Batching latency vs. smoothness.** Flushing at ~60fps adds up to ~16ms of latency between an event occurring in the engine and appearing live. Imperceptible, and vastly outweighed by not freezing.
- **Decimation fidelity vs. cost.** A sampled live animation is "representative, not exact." Acceptable because the animation is decorative; all *data* (metrics, outcomes, event log counts) still derives from the full dataset. This must be stated in the UI's confidence language so it is never mistaken for data loss.
- **Ring buffer O(1) writes vs. read-side complexity.** The write win is real but the read-side rewrite is the actual cost. Deferring it avoids paying that cost unless volume genuinely demands it.
- **Mutable store updates vs. immutability.** Dropping the per-event object spread trades strict immutability for a version-counter change-detection pattern — already the sanctioned approach for the simulate-phase data flow in prior ADRs.

---

## Consequences

**What becomes easier / better**
- The **Elapsed timer ticks smoothly**; histogram, Busiest Nodes, and Event Log update live instead of freezing.
- The **tab no longer freezes** on heavy runs; mid-run interaction stays responsive.
- **Total compute wall-time drops** — the worker makes far fewer cross-thread calls and the main thread stops doing O(100k) copies per event. This is the "seconds, not minutes" outcome.
- **High-RPS / long / many-node / saturating scenarios become runnable** — precisely the ones that best teach queueing and bottlenecks, and precisely the ones that jam today. Directly serves the "usable + teachable" product goal.
- The **two-clocks model is fully realized**: compute runs flat-out; playback reveals at any chosen speed.

**What becomes harder / to watch**
- The store's data flow becomes **batched and (partially) mutable** — subscribers and selectors must be reviewed for change-detection correctness.
- If decimation ships, the live animation is **sampled**; this must be surfaced honestly in UI copy so it is not read as a fault.
- A ring buffer (if it lands) introduces **wraparound-aware reads** across every history consumer — a permanent complexity tax to maintain.

**What we will need to revisit**
- The `CHUNK_SIZE` / flush-threshold constants (tune against real profiles).
- Whether Phase 3 is needed at all (decided by Phase 1–2 measurement).
- The GC-pressure claim for phase records / metrics — only pursue typed-array reworks if profiling proves they are a top cost (they are structured objects today, so this is speculative).

---

## Non-goals / what this does **not** achieve

- **Not constant-time compute.** A genuinely massive run remains real work (seconds to tens of seconds, proportionate to size). The Θ(events) floor is physics, not plumbing.
- **No change to any result.** Metrics, outcomes, latencies, reproducibility are identical.
- **Decimation, if used, thins only the live packet animation** — never the Event Log, outcomes, or computed metrics, which continue to use the full dataset.

---

## Action items

**Phase 1 (do first)**
1. [ ] Add a worker-side edge-flow accumulator; flush on size threshold and/or chunk boundary; lower `CHUNK_SIZE` for cadence. (`src/engine/worker/simulation.worker.ts`)
2. [ ] Change the outbound message type to carry an **array** of events per flush; update `WorkerOutboundMessage`.
3. [ ] Add `recordEdgeFlowEventBatch(events)` — one array append + one `set` per batch. (`src/renderer/src/store/useStore.ts`)
4. [ ] Replace the per-event `{...edgeFlowById}` spread with a version-bump/mutable update.
5. [ ] Update the receiver to call the batch API. (`src/renderer/src/hooks/useSimulation.ts`)
6. [ ] **Measure**: Elapsed timer smoothness, live-panel update cadence, total wall-time, tab responsiveness at high RPS.

**Phase 2**
7. [ ] Decide the live data contract; if decimation, implement sampling at the emission/forward boundary and add honest UI copy.

**Phase 3 (contingent)**
8. [ ] If still bottlenecked: implement the ring buffer + wraparound-aware read-side selectors.

---

## Rollout & verification

- **Correctness gate:** a fixed seed + topology must produce identical `summary`, `perNode`, `requestOutcomes`, and `eventStream` before/after (golden-output test). Performance work that changes a number is a bug.
- **Performance gate (empirical):** on the scenario that currently wedges the tab (~600 rps, multi-hop, ≥20s), verify: (a) Elapsed advances within ~100ms of real time throughout, (b) no frame-time spike long enough to freeze input, (c) total wall-time reduced by a large factor vs. baseline.
- **Regression gate:** the small-topology common case (2–4 nodes, ≤200 rps) shows no measurable slowdown.
- Land Phase 1 behind normal review; re-measure before opening Phase 2/3.

---

## Appendix — rough magnitudes (illustrative)

For a run of ~E edge events with a 100k-slot history:

| Path | Before | After Phase 1 |
|------|--------|----------------|
| History copy work | ~E × 100k element-copies | ~(E/batch) × 100k, batch≈events-per-frame → ~100k × 60/sec |
| `postMessage` calls | ~E (thousands/sec) | ~60/sec (one per flush) |
| React renders of live panels | ~E | ~60/sec |

Numbers are order-of-magnitude, pre-profiling. The point is the shape: **per-event → per-frame**, which is what unblocks the main thread.

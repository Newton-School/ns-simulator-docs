# Canvas Visualization & UX Simplification

Technical product specification for improving the NS Simulator canvas experience without turning the app into a dense observability dashboard. This spec scans the current renderer and engine surface, identifies which simulator concepts are worth representing visually, and proposes a smaller canvas-first interaction model.

The goal is simple: the canvas should answer three questions quickly:

1. Where is traffic going?
2. What is unhealthy?
3. What changed because of the selected workload?

---

## Problem Context

The simulator already has the right data model for meaningful visual feedback:

| Data                                                      | Source                                            | Visual use                                           |
| --------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------- |
| Workload pattern and base RPS                             | `WorkloadGenerator`, `ScenarioState`, run context | Edge flow density and phase                          |
| Edge transfer success/error/loss/timeout                  | `enqueueEdgeTransfer`, edge-flow events           | Traffic dots, failed pulses, inactive edges          |
| Per-node throughput, utilization, queue depth, error rate | `SimulationOutput.perNode`, `useNodeMetrics`      | Node health and compact runtime metrics              |
| Time series snapshots                                     | `TimeSeriesSnapshot`                              | Future replay/scrubber                               |
| Event log and debug events                                | `eventLog`, canonical event stream                | Request trace replay and selected-event highlighting |
| SLO breaches and conservation checks                      | analysis output                                   | Bottleneck/health overlays                           |

The issue is not missing data. The issue is presentation density. The app currently exposes many surfaces at once: component library, question panel, canvas, node cards, edge labels, right properties panel, run controls, and bottom results tray. This makes the product feel more complex than canvas-first tools like Pinpole, where the diagram stays dominant and controls are contextual.

Note: the shared Pinpole URL appears to require an authenticated app session, so this spec uses Pinpole only as a canvas-first UX reference, not as a source for exact private UI details.

---

## What Should Be Visualized

### 1. Edge Traffic

This is the highest-value simulator visual.

Represent:

- Direction of request flow.
- Relative traffic volume.
- Workload pattern behavior.
- Edge failures/loss/timeouts.
- Inactive edges after a run.

Implementation guidance:

- Do not render one dot per request.
- Use compressed dots and small edge thickness changes.
- Keep the edge itself solid; dots carry motion.
- Keep labels compact: `42 rps`, `42 rps / 1.2% fail`, `inactive`.

### 2. Node Health

This should be visible directly on the canvas.

Represent:

- `healthy`: green dot/border.
- `degraded`: amber dot/border.
- `critical`: red dot/border.
- `inactive`: muted/grayscale.

Suggested thresholds:

| Status   | Trigger                                                 |
| -------- | ------------------------------------------------------- |
| Critical | error rate >= 5% or utilization >= 90%                  |
| Degraded | error rate > 0, utilization >= 75%, or queue depth >= 1 |
| Healthy  | active with no warning signals                          |

Use border/dot/shadow only. Avoid filling whole nodes with status colors.

### 3. Queue And Utilization

Show only when useful:

- During a run.
- After a run.
- When the node is selected or hovered.

Keep it compact:

- utilization bar
- queue chip
- throughput number

Do not show all simulation config on the canvas.

### 4. Workload Pattern Behavior

The selected pattern should change edge movement visibly:

| Pattern  | Visual behavior                                      |
| -------- | ---------------------------------------------------- |
| Constant | stable spacing and stable packet count               |
| Poisson  | irregular spacing and speed jitter                   |
| Bursty   | obvious low/high phases                              |
| Spike    | temporary surge during `spikeTime` + `spikeDuration` |
| Sawtooth | gradual ramp based on `rampDuration` and `peakRps`   |
| Diurnal  | slow low/normal/peak wave using hourly multipliers   |

Important: visual modulation should not change simulation output. It should read the run config and edge-flow stats, then compress them for human readability.

### 5. Bottlenecks

Useful, but should be an optional overlay.

Represent:

- most saturated node
- highest queue node
- SLO breach node
- critical path or edge

Recommended control:

`Traffic | Health | Bottlenecks`

Only one overlay should be visually dominant at a time.

### 6. Request Trace Replay

Useful for debugging, not as a default view.

Represent:

- one selected request path
- failed hop
- per-hop latency
- timeout/rejection reason

Entry point should be from results/event log: click a request or event, then replay that request on the canvas.

---

## What Not To Visualize Yet

Avoid:

- Full heatmaps for every metric.
- All event-level packets.
- Charts inside every node.
- Large animated backgrounds.
- Multiple simultaneous overlays.
- Strong full-card status fills.
- Always-visible labels for every metric.

The canvas should remain a system diagram first and a simulation display second.

---

## Why The App Feels Less User-Friendly

### 1. Too Many Persistent Panels

The left library, right properties panel, and bottom results tray can all compete with the canvas.

Recommendation:

- Auto-collapse the library after dragging a component.
- Open the inspector only when something is selected.
- Make results start as a compact summary, then expand into detailed tabs.

### 2. Node Cards Carry Too Much Responsibility

Nodes mix identity, configuration, runtime metrics, health, and controls.

Recommendation:

- Pre-run: icon, label, minimal config.
- During/post-run: health, throughput, queue, utilization.
- Deep config remains in the inspector.

### 3. Results Are Too Detached From The Canvas

The results tray contains useful tables, but users must mentally map rows back to the diagram.

Recommendation:

- Clicking a result row should select the related node/edge.
- Bottlenecks and failed edges should be projected back onto the canvas.
- Keep tables for detail, canvas for first-level diagnosis.

### 4. Component Library Is Broad

The catalog is powerful but heavy for first-time use.

Recommendation:

- Default to `Common`.
- Keep `All` searchable.
- Later: suggest components from the question text.

---

## Recommended Minimal UX Direction

### Canvas Modes

Add one simple segmented control:

| Mode        | Shows                                          |
| ----------- | ---------------------------------------------- |
| Traffic     | packet flow, active/inactive edges, RPS labels |
| Health      | node health status, queue/utilization emphasis |
| Bottlenecks | top problem nodes/edges only                   |

Default mode: `Traffic`.

### Label Rules

Show labels only when:

- simulation is running
- simulation is complete
- element is selected
- element is hovered

This prevents the canvas from becoming label soup.

### Visual Scale Rules

Use compressed scales:

- packet count: capped and proportional, not literal
- edge thickness: small range only
- node health: border/dot only
- failures: short pulses, not permanent noisy effects

---

## Source-To-Feature Map

| Feature                   | Current source                                             |
| ------------------------- | ---------------------------------------------------------- |
| Edge packet flow          | `PacketEdge.tsx`, `edgeFlowById`, `EdgeFlowEvent`          |
| Workload pattern behavior | `workload.ts`, `SimulationControls.tsx`, run context       |
| Node health               | `useNodeMetrics.ts`, `nodePresentation.ts`, `BaseNode.tsx` |
| Edge properties           | `EdgePropertiesPanel.tsx`, `useTopologySerializer.ts`      |
| Canvas layout             | `FlowCanvas.tsx`, React Flow                               |
| Library complexity        | `LibrarySidebar.tsx`, `catalogConfig.ts`                   |
| Inspector complexity      | `PropertiesPanel.tsx`, `PropertiesForm.tsx`                |
| Result details            | `ResultsTray.tsx`, `SimulationOutput`                      |
| Request debugging         | `eventLog`, `eventStream`, `traces`, `projectToDebugEvent` |

---

## Non-Goals

- Do not redesign the whole app.
- Do not add a charting dashboard.
- Do not add 3D or decorative animation.
- Do not make every engine event visible.
- Do not replace exact metrics with visuals; keep exact values in results/labels.

---

## Recommendation

Prioritize a cleaner canvas-first simulator:

1. Keep edge traffic flow as the primary visual.
2. Keep node health as a secondary visual.
3. Add a bottleneck overlay mode.
4. Make results click back into the canvas.
5. Hide unnecessary labels and panels until context demands them.

This keeps the app technically honest while making it feel closer to a simple architecture canvas instead of a dense simulation console.

---

## Appendix: Edge Packet Flow Rendering Model

This appendix maps the three inputs that must be handled for packet flow on an edge:

1. packets coming from the previous node
2. edge error/loss behaviour
3. selected workload pattern

The important design rule is ordering. The renderer should not start with `baseRps` and paint every edge. It should start with upstream traffic that was actually routed onto that edge, reduce it by edge outcome status, then use the selected workload pattern only to shape the readable animation.

### Why Edges Need This Model

`docs/01-system-diagrams.md` defines nodes as places where things exist, wait, or transform, and edges as paths where things travel. For the simulator UI, that means an animated dot on an edge should mean:

> a request left the source node, routing selected this edge, and the edge transfer produced a known outcome.

This keeps edge visuals faithful to the simulation. A downstream edge should not show packets if an upstream node rejected traffic, if routing sent traffic elsewhere, or if a previous edge lost the packet.

### Input 1: Packets Coming From Previous Node

**Meaning:** the number of requests that actually attempt this edge after upstream node processing and routing.

This is not the same as `baseRps`. `baseRps` only describes how fast the source workload creates new requests. By the time traffic reaches edge `e`, the count has already been shaped by:

- source generation pattern
- node queue capacity, service time, and rejection
- previous edge loss/error/timeout
- routing strategy: round-robin, weighted, uniform, conditional, async fan-out
- branch cloning for async routes

In code, the edge renderer receives this through `EdgeFlowEvent`. For non-source nodes, those events are emitted only after the node has completed processing and the routing table selected an outgoing edge. For the source node, they are emitted after workload generation and source routing. Therefore the edge event stream is the correct source for "how many packets came from the previous node."

Current implementation source:

| Concern                          | Code path                                                  |
| -------------------------------- | ---------------------------------------------------------- |
| Workload creates requests        | `src/engine/workload.ts`                                   |
| Node completes work and forwards | `src/engine/engine.ts`                                     |
| Edge selection                   | `src/engine/routing.ts`                                    |
| Async branch cloning             | `prepareRequestsForRoutes()` and `cloneRequestForBranch()` |
| Edge attempt event               | `EdgeFlowEvent` in `src/engine/core/events.ts`             |

Calculation for edge `e` over window `W = [t0, t1]`:

```text
attempted_e(W) = count(event.edgeId == e.id)
success_e(W)   = count(event.edgeId == e.id && event.status == "success")
failed_e(W)    = attempted_e(W) - success_e(W)

seconds(W) = max(1, (t1 - t0) / 1000)

attemptedRps_e(W) = attempted_e(W) / seconds(W)
successRps_e(W)   = success_e(W) / seconds(W)
failedRps_e(W)    = failed_e(W) / seconds(W)
failureRatio_e(W) = failed_e(W) / max(1, attempted_e(W))
```

Implementation implication:

- Use actual edge-flow events as the source of truth.
- Do not estimate rendered packets as `baseRps * edge.weight`.
- Use `attemptedRps` as routed upstream traffic for the edge.
- Do not show dots on inactive edges after a run. Show `inactive`.
- For async fan-out, each branch is a real edge attempt, so multiple edges can show packets for one original request.

Routing strategy affects the edge event stream as follows:

| Routing case           | Expected edge attempts before edge failure                                  |
| ---------------------- | --------------------------------------------------------------------------- |
| One eligible sync edge | Every processed upstream request attempts that edge                         |
| Round-robin sync edges | Attempts are distributed approximately evenly across eligible sync edges    |
| Weighted sync edges    | Attempts follow `edge.weight / sum(weights)` in expectation                 |
| Uniform sync edges     | One eligible sync edge is selected randomly per request                     |
| Conditional edge       | Attempts exist only for requests that match the condition                   |
| Async fan-out          | Every eligible async edge gets a branch for each processed upstream request |
| Mixed async + sync     | All async edges get branches, and one sync edge is also selected            |

The UI can show these expectations in docs/tooltips, but the renderer should use the actual `EdgeFlowEvent` counts because those already include random choices, conditions, and branch cloning.

### Input 2: Edge Error Rate And Loss

**Meaning:** the edge's transfer reliability after routing has already selected it.

The edge transfer pipeline is:

```text
route selected
  -> packet loss check
  -> edge error check
  -> latency sample
  -> deadline check
  -> request arrival
```

Current implementation source:

| Outcome                      | Engine status | UI meaning                                  |
| ---------------------------- | ------------- | ------------------------------------------- |
| Arrived                      | `success`     | render moving packet dots                   |
| Packet lost                  | `packet-loss` | count as failed; render short warning pulse |
| Edge error                   | `edge-error`  | count as failed; render short danger pulse  |
| Deadline exceeded in transit | `timeout`     | count as failed; render short warning pulse |

Expected success approximation:

```text
expectedSuccess_e
  ~= attempted_e
   * (1 - packetLossRate_e)
   * (1 - errorRate_e)
   * P(edgeLatency_e < remainingDeadline)
```

This formula is useful for reasoning, but the UI should use actual sampled events from the engine because the simulation already made the random decisions. That matters for seeded reproducibility: the renderer should replay the result, not re-simulate loss/error.

Implementation implication:

- Error rate reduces successful packets, not attempted packets.
- Packet loss and edge error should not create successful moving dots.
- Packet count should be based on successful edge throughput: `attemptedRps * observedSuccessRatio`.
- Failure should be visible as compact pulses and labels like `3.2% fail`, not as permanent glow or noisy edge styling.
- Edge `bandwidth` and `maxConcurrentRequests` are currently not enforced by the engine, so they should not yet affect packet count unless those features are implemented later.

### Input 3: Workload Profile

**Meaning:** the shape and configured rate of request arrivals over time.

The workload profile controls when source requests are generated. It should affect edge animation only after the edge's actual routed traffic baseline is known.

Correct rendering order:

```text
workload profile -> node/routing/edge runtime -> edge-flow events -> compressed visual replay
```

Pattern functions for visual replay:

| Pattern               | Engine behaviour                                          | Visual behaviour                                          |
| --------------------- | --------------------------------------------------------- | --------------------------------------------------------- |
| `constant` / `replay` | fixed interval `1000 / baseRps`                           | stable packet spacing and count                           |
| `poisson`             | exponential inter-arrival time                            | irregular spacing and speed jitter, average near baseline |
| `bursty`              | alternates `burstRps` and `baseRps`                       | visible low/high phases                                   |
| `spike`               | one surge during `[spikeTime, spikeTime + spikeDuration)` | temporary surge, then baseline                            |
| `sawtooth`            | linear ramp from `baseRps` to `peakRps`                   | gradually increasing density/speed, then reset            |
| `diurnal`             | hourly multipliers mapped over simulation duration        | slow low/normal/peak wave                                 |

Pattern multiplier formulas:

```text
base = max(1, workload.baseRps)
elapsed = current replay time in simulation ms

constant/replay:
  m(t) = 1

poisson:
  m(t) ~= jitterBucket(edgeId, floor(elapsed / bucketMs))
  average(m) should remain near 1

bursty:
  cycle = burstDuration + normalDuration
  inBurst = elapsed % cycle < burstDuration
  m(t) = inBurst ? burstRps / base : 1

spike:
  inSpike = elapsed >= spikeTime && elapsed < spikeTime + spikeDuration
  m(t) = inSpike ? spikeRps / base : 1

sawtooth:
  phase = (elapsed % rampDuration) / rampDuration
  currentRps = base + (peakRps - base) * phase
  m(t) = currentRps / base

diurnal:
  hourPosition = (elapsed / simulationDurationMs) * 24
  m(t) = interpolate(hourlyMultipliers[floor(hourPosition)], nextHour)
```

Implementation implication:

- Use pattern as a visual multiplier for density, speed, and phase label.
- Keep exact labels based on observed successful edge throughput, not inflated visual throughput.
- For `spike` and `sawtooth`, read the pattern-specific run params, otherwise these patterns will look identical to constant traffic.
- If the engine later emits enough timestamped events for a full replay, prefer event timing over synthetic multipliers.

### Current Implementation Map

| Layer           | Current implementation                            | What it contributes                                 |
| --------------- | ------------------------------------------------- | --------------------------------------------------- |
| Engine events   | `enqueueEdgeTransfer()` emits `EdgeFlowEvent`     | per-edge attempt status and latency                 |
| Worker bridge   | `simulation.worker.ts` sends `edge-flow` messages | streams edge outcomes to renderer                   |
| Store           | `edgeFlowById` in `useStore.ts`                   | rolling and average edge counters                   |
| Canvas edge     | `PacketEdge.tsx`                                  | solid edge, compressed dots, failure pulses, labels |
| Workload replay | `patternMultiplier()` in `PacketEdge.tsx`         | visible pattern differences during/post run         |

### Rendering Calculation

Use a compressed visual scale. The goal is human readability, not literal packet rendering.

```text
displaySuccessRps =
  if run complete:
    avgSuccessPerSecond
  else:
    max(recentSuccessPerSecond, avgSuccessPerSecond)

displayAttemptedRps =
  if run complete:
    avgAttemptedPerSecond
  else:
    max(recentAttemptedPerSecond, avgAttemptedPerSecond)

displayFailedRps =
  if run complete:
    avgFailedPerSecond
  else:
    max(recentFailedPerSecond, avgFailedPerSecond)

failureRatio = displayFailedRps / max(1, displayAttemptedRps)
observedSuccessRatio = displayAttemptedRps > 0
  ? displaySuccessRps / displayAttemptedRps
  : (1 - configuredPacketLossRate) * (1 - configuredEdgeErrorRate)

routedAttemptRps = displayAttemptedRps
renderedSuccessRps = routedAttemptRps * clamp(observedSuccessRatio, 0, 1)

visualMultiplier = patternMultiplier(runConfig, replayClock, edgeId)
visualSuccessRps = renderedSuccessRps * visualMultiplier

basePacketCount =
  renderedSuccessRps <= 0
    ? 0
    : clamp(ceil(log2(renderedSuccessRps + 1) * 0.8), 2, 7)

streamPacketCount =
  basePacketCount <= 0
    ? 0
    : clamp(round(basePacketCount * clamp(visualMultiplier, 0.35, 4)), 1, 14)

edgeStrokeWidth =
  clamp(3 + log2(visualSuccessRps + 1) * 0.55, 3, 5)

streamDurationMs =
  clamp(5200 - log2(visualSuccessRps + 1) * 420, 2200, 5200)
```

Label rule:

```text
if no flow and run complete:
  label = "inactive"
else:
  label = "{displaySuccessRps} rps"
  if phaseLabel: label += " · {phaseLabel}"
  if failureRatio > 0: label += " / {failureRatio%} fail"
```

### Pseudocode

Engine side:

```typescript
function enqueueEdgeTransfer(request, edge, targetNodeId) {
  const startedAt = clock

  if (random() < edge.packetLossRate) {
    emitEdgeFlowEvent(edge.id, request.id, startedAt, request.deadline, 'packet-loss')
    scheduleRequestTimeout()
    return
  }

  if (random() < edge.errorRate) {
    emitEdgeFlowEvent(edge.id, request.id, startedAt, startedAt, 'edge-error')
    scheduleRequestRejected('edge_error_rate')
    return
  }

  const latency = sampleEdgeLatency(edge)
  const arrivalTime = startedAt + latency

  if (request.deadline <= arrivalTime) {
    emitEdgeFlowEvent(edge.id, request.id, startedAt, request.deadline, 'timeout')
    scheduleRequestTimeout()
    return
  }

  emitEdgeFlowEvent(edge.id, request.id, startedAt, arrivalTime, 'success')
  scheduleRequestArrival(targetNodeId, arrivalTime)
}
```

Store side:

```typescript
function recordEdgeFlowEvent(event) {
  const flow = edgeFlowById[event.edgeId] ?? emptyFlowState()
  const displayAtMs = wallStartMs + (event.startedAtMs - simStartMs) / playbackSpeed

  flow.recent.push({ ...event, displayAtMs })
  flow.recent = keepRecentWindow(flow.recent)

  flow.totalAttempted += 1
  if (event.status === 'success') {
    flow.totalSuccess += 1
  }
  flow.totalFailed = flow.totalAttempted - flow.totalSuccess

  flow.recentRates = summarizeWindow(flow.recent)
  flow.averageRates = summarizeSinceFirstEvent(flow)
}
```

Renderer side:

```typescript
function renderPacketEdge(edgeId) {
  const flow = edgeFlowById[edgeId]

  if (!flow && runStatus === 'complete') {
    drawSolidEdge({ opacity: 0.28 })
    drawLabel('inactive')
    return
  }

  const rates = chooseRecentOrAverageRates(flow, runStatus)
  const multiplier = patternMultiplier(runConfig, playbackClock, edgeId)
  const successRatio =
    rates.attemptedRps > 0
      ? rates.successRps / rates.attemptedRps
      : (1 - configuredPacketLossRate) * (1 - configuredEdgeErrorRate)
  const renderedSuccessRps = rates.attemptedRps * clamp(successRatio, 0, 1)
  const basePacketCount = compressedPacketCount(renderedSuccessRps)
  const packetCount = patternPacketCount(basePacketCount, multiplier)
  const width = compressedStrokeWidth(renderedSuccessRps * multiplier)

  drawSolidEdge({ width, failureTint: rates.failureRatio })
  drawMovingDots({ count: packetCount, jitter: runConfig.pattern === 'poisson' })
  drawFailurePulses(flow.recentFailedEvents)
  drawLabel(formatObservedRpsAndFailure(rates, phaseLabel))
}
```

### Correctness Rules

- Start from actual edge attempts, not global `baseRps`.
- Treat edge attempts as upstream processed-and-routed traffic for that specific edge.
- Treat edge error/loss as outcomes of an already-selected edge.
- Pattern changes timing and visual density, not the edge's simulated truth.
- Use observed success rate for labels and pattern-adjusted success rate for animation feel.
- Routing strategy must be reflected through actual routed events, not through renderer-side guessing.
- Keep inactive edges visible but muted after simulation.
- Keep edge geometry solid and single-path. Dots carry motion; the line should not become dashed or duplicated.
- Use palette tokens for packet/status colours so the edge stays visually consistent with node health.

### Future Improvement: First-Class Edge Metrics

The current renderer reconstructs edge metrics from `EdgeFlowEvent`. That is good enough for the canvas, but a later engine-level `EdgeMetricsCollector` would make results more exact and easier to query.

Suggested engine metrics per edge:

```typescript
interface EdgeMetrics {
  edgeId: string
  attempted: number
  arrived: number
  packetLost: number
  edgeErrors: number
  timedOut: number
  avgLatencyMs: number
  p95LatencyMs: number
  successRps: number
  attemptedRps: number
  failureRatio: number
}
```

These metrics should be generated by the engine, while `PacketEdge.tsx` should remain a renderer that compresses the numbers into motion.

### References Consulted

- `ns-simulator-docs/docs/01-system-diagrams.md`: edges as paths, with direction, capacity, latency, and reliability.
- `ns-simulator-docs/specs/edge-properties-and-defaults.md`: current edge transfer pipeline and unsupported edge capacity fields.
- `ns-simulator-docs/specs/request-flow-direction-and-topology-rules.md`: routing, fan-out, weights, and conditional edge selection.
- `ns-simulator-docs/specs/request-pattern-configuration.md`: implemented workload pattern algorithms.
- SimPy time and scheduling notes: event queues process scheduled events sequentially and deterministically, which matches the simulator's event replay model.
- Poisson process references: Poisson arrivals are useful for random events in time and should appear as irregular spacing, not merely higher/lower constant density.

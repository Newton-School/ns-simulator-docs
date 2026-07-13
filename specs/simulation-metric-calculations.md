# Simulation Metric Calculations

This document explains how the simulator calculates the values shown in the screen you shared:

- the canvas metric lenses:
  - pre-run: `Concurrency / Queue Capacity / Timeout`
  - post-run: `Traffic / Saturation / Latency / Errors / Throughput`
- node-card values such as `Completed / Received`, `Rejected / Timed Out`, and `0.0 / 8 workers`
- the selected node **Results** panel on the right
- the **Nodes** table at the bottom (`Arrived`, `Done`, `Reject`, `T.O.`, `Avg Q`, `Util`, `p50`, `p95`, `p99`, `λ`, `W`, `L`)

The formulas below are taken from the current implementation in:

- `src/engine/metrics.ts`
- `src/engine/analysis/output.ts`
- `src/renderer/src/components/layout/WorkspaceLayout.tsx`
- `src/renderer/src/components/canvas/MetricLensSwitcher.tsx`
- `src/renderer/src/components/nodes/RuntimeNodeMetrics.tsx`
- `src/renderer/src/components/nodes/nodePresentation.ts`
- `src/renderer/src/components/canvas/PacketEdge.tsx`
- `src/renderer/src/store/useStore.ts`

## 1. Time Window Basics

Many displayed metrics are measured over the **post-warmup** window.

Formula:

```text
effectiveDurationMs = max(0, simulationDuration - warmupDuration)
effectiveDurationSec = effectiveDurationMs / 1000
```

Important detail:

- Global summary metrics gate on `request.createdAt >= warmup`
- Per-node post-warmup counts gate on `span.arrivalTime >= warmup`

That means a request created before warmup ends but arriving at a node after warmup can still count for that node's post-warmup metrics.

## 2. Which Screen Uses Which Metrics

### Canvas metric lenses

`MetricLensSwitcher.tsx` selects one metric family for all node cards on the canvas.

- **Pre-run** lenses show configured values directly from node config.
- **Post-run** lenses show observed runtime metrics collected during the simulation.

The important UI rule is:

```text
Lens name = operational category
Node content = native metric for that node type
```

So the lens stays generic (`Concurrency`), while the node shows the concrete thing it actually has (`Workers 8`, `Connections 16`, `Consumers 4`).

### Pre-run lens terms and calculations

These are not derived from runtime samples. They are direct reads from the node's serialized config.

| Lens | Meaning | Raw source | Calculation / display rule |
| --- | --- | --- | --- |
| Concurrency | How many units of work the node can handle simultaneously. | `data.sim.queue.workers` | Direct config read. Displayed with a node-specific label and unit. |
| Queue Capacity | How much work can wait before the node starts rejecting, dropping, or blocking arrivals. | `data.sim.queue.capacity` | Direct config read. Displayed with a node-specific label and unit. |
| Timeout | The configured deadline or failure threshold for work at the node. | `data.sim.processing.timeout` | Direct config read. Displayed as whole milliseconds: `{timeout} ms`. |

The current renderer maps the same raw fields to different native labels depending on node type:

| Node type family | Concurrency label | Queue Capacity label | Display example |
| --- | --- | --- | --- |
| `load-balancer`, `load-balancer-l4`, `load-balancer-l7` | `Connections` | `Connection Queue` | `16 connections`, `14 connections` |
| `api-gateway`, `ingress-controller`, `reverse-proxy` | `Request Slots` | `Request Queue` | `8 req`, `20 req` |
| `relational-db`, `primary-db`, `read-replica` | `Connections` | `Query Queue` | `32 connections`, `100 queries` |
| `in-memory-cache`, `redis-cache` | `Operations` | `Operation Queue` | `64 ops`, `200 ops` |
| `queue`, `message-queue` | `Consumers` | `Backlog` | `4 consumers`, `500 msg` |
| `service-registry`, `dns-server` | `Lookups` | `Lookup Queue` | `8 lookups`, `40 lookups` |
| default fallback | `Workers` | `Queue` | `8 workers`, `20 req` |

Dynamic singular/plural is applied when the unit is a count noun:

```text
formatCount(value, noun) =
  "{roundedValue} {singular if value = 1 else plural}"
```

Examples:

- `1 worker`
- `8 workers`
- `1 connection`
- `16 connections`

### Post-run lens terms and calculations

These lenses show observed metrics after the run has populated `simulationMetricsByNode`.

| Lens | Meaning | Raw source | Calculation / display rule |
| --- | --- | --- | --- |
| Traffic | Absolute request-flow counts through the node. | `postWarmupProcessed`, `postWarmupArrived`, `postWarmupRejected`, `postWarmupTimedOut` | Primary row: `Completed / Received = postWarmupProcessed / postWarmupArrived`. Secondary row: `Rejected / Timed Out = postWarmupRejected / postWarmupTimedOut`. |
| Saturation | How close the node got to exhausting its processing capacity. | `utilization`, `data.sim.queue.workers` | `displayedActiveWorkers = min(workers, (uiUtilizationPercent / 100) * workers)` and the card renders `{displayedActiveWorkers.toFixed(1)} / {workers} workers`. |
| Latency | Node-local processing latency percentiles, with optional SLO context. | `latencyP95`, `latencyP50`, `latencyP99`, `data.sim.slo.latencyP99` | Primary value: `{latencyP95.toFixed(1)}ms p95`. Secondary text includes `p50` and whether `latencyP99` is within or above the configured p99 SLO. |
| Errors | Failure rate plus the most important rejection reason. | `errorRate`, `totalRejected`, `rejectionsByReason` | Primary value: `{errorRate.toFixed(1)}%`. Limit text: `{totalRejected} rejected`. Secondary text: highest-count rejection reason, if any. |
| Throughput | Successful work rate after warmup. | `throughput` | Primary value: `{throughput.toFixed(1)}` with limit `req/s`. Secondary text may show stream lag or cache-hit context. |

Two important distinctions:

- **Traffic is counts**, not a rate.
- **Throughput is a rate**, not a count.

Important caveat on the current `Errors` lens:

- The primary percentage includes both post-warmup rejections and post-warmup timeouts.
- The small limit text currently uses `totalRejected` only, so it does **not** separately surface timed-out counts on that card.

### Selected node Results panel

The right-side panel uses per-node runtime metrics that are prepared in `WorkspaceLayout.tsx` from `sim.results.perNode`.

These fields map like this:

| UI label | Raw metric | Formula |
| --- | --- | --- |
| Throughput | `throughput` | `postWarmupProcessed / effectiveDurationSec` |
| Utilization | `utilization` | `utilizationSum / utilizationSamples` |
| Arrived | `postWarmupArrived` | count of requests that reached the node after warmup |
| Completed | `postWarmupProcessed` | count of completed node spans after warmup |
| Rejected | `postWarmupRejected` | count of rejections at the node after warmup |
| Timed Out | `postWarmupTimedOut` | count of node timeouts after warmup |
| p50 / p95 / p99 | `latencyP50 / latencyP95 / latencyP99` | percentiles of the node's latency samples |
| Availability | `availability` | `1 - errorRate` |
| Error Rate | `errorRate` | `(postWarmupRejected + postWarmupTimedOut) / postWarmupArrived` |

### Nodes table

The bottom **Nodes** tab uses the same per-node metrics, plus Little's Law outputs (`λ`, `W`, `L`).

### Edge label

The edge label is not taken from the per-node metrics. It is driven by edge-flow events in the React store.

### Saturation card

The node card in the **Saturation** lens uses the selected node's utilization and configured worker count.

## 3. Throughput, Counts, Availability, Error Rate

The core formulas live in `src/engine/metrics.ts`.

### Per-node counts

In the new canvas **Traffic** lens, these same counts are shown as:

```text
Completed / Received
Rejected / Timed Out
```

Older table/panel copy may still say `Done` / `Arrived`, but the underlying metrics are the same.

```text
Received  = postWarmupArrived
Completed = postWarmupProcessed
Rejected  = postWarmupRejected
Timed Out = postWarmupTimedOut
```

### Per-node throughput

```text
throughput = postWarmupProcessed / effectiveDurationSec
```

### Per-node error rate

```text
postWarmupFailed = postWarmupRejected + postWarmupTimedOut
errorRate = postWarmupFailed / postWarmupArrived
```

If `postWarmupArrived = 0`, the simulator returns `0`.

### Per-node availability

```text
availability = 1 - errorRate
```

### Global summary error rate

The global summary uses:

```text
summaryErrorRate =
  (postWarmupTotalRequests - postWarmupSuccessfulRequests) / postWarmupTotalRequests
```

This is similar to per-node error rate, but the numerator and denominator are global request totals rather than per-node arrivals.

## 4. Latency: p50, p95, p99

Per-node latency samples are collected from:

```text
nodeLatencySample = queueWait + serviceTime
```

This is **node-local latency only**. It does not include edge/network latency.

The simulator sorts the latency samples and chooses percentiles with this rule:

```text
sorted = sort(latencySamplesMs ascending)
index(p) = floor(p * (n - 1))
percentile(p) = sorted[index(p)]
```

So:

```text
p50 = sorted[floor(0.50 * (n - 1))]
p95 = sorted[floor(0.95 * (n - 1))]
p99 = sorted[floor(0.99 * (n - 1))]
```

Important caveat:

- Per-node `p50 / p95 / p99` currently use all collected node latency samples
- They are not post-warmup filtered in `getPerNodeMetrics()`

## 5. Avg Q and Util

These come from periodic node snapshots recorded during the run.

### Average queue length

```text
Avg Q = queueLengthSum / queueSamples
```

This is a time-average of queued requests waiting at the node.

### Utilization

Each snapshot contributes:

```text
snapshotUtilization = activeWorkers / maxWorkers
```

Then:

```text
utilization = utilizationSum / utilizationSamples
```

Important caveat:

- `Avg Q` and `Util` are currently averaged across all snapshots, including warmup

## 6. Saturation Card: `0.0 / 8 workers`

The saturation card is rendered from the utilization percent and configured worker count.

Raw engine utilization is a ratio from `0` to `1`.

Before it reaches the UI store, it is converted to percent:

```text
uiUtilizationPercent = round(rawUtilization * 1000) / 10
```

Then the card calculates:

```text
displayedActiveWorkers = min(workers, (uiUtilizationPercent / 100) * workers)
```

Displayed card text:

```text
{displayedActiveWorkers.toFixed(1)} / {workers} workers
```

So a very low utilization can honestly display as:

```text
0.0 / 8 workers
```

even though the underlying utilization is non-zero but tiny.

## 7. Rejections by Reason

The simulator records rejection reasons every time `recordRejection()` is called.

Examples of reasons include:

- `edge_error_rate`
- `node_error_rate`
- `capacity_exceeded`
- `security_blocked`
- `node_failed`

Displayed formula:

```text
Rejections by reason[reason] = count of rejections recorded with that reason
```

Important caveat:

- `rejectionsByReason` is returned as the node's total reason-count map
- It is not separately post-warmup filtered

## 8. Edge Label: `10.0 rps / 0.2% fail`

The edge label is computed from edge-flow render events, not from node throughput.

After the run completes, each edge stores:

```text
totalAttempted
totalSuccess
totalFailed = totalAttempted - totalSuccess
durationSeconds = max(1, (lastStartedAtMs - firstStartedAtMs) / 1000)

avgAttemptedPerSecond = totalAttempted / durationSeconds
avgSuccessPerSecond   = totalSuccess / durationSeconds
avgFailedPerSecond    = totalFailed / durationSeconds
```

The label then uses:

```text
failureRatio = avgFailedPerSecond / avgAttemptedPerSecond
```

Because both rates use the same denominator, this is equivalent to:

```text
failureRatio = totalFailed / totalAttempted
```

Displayed text:

```text
{successRps} / {failureRatio * 100}% fail
```

Formatting:

- success RPS is formatted with `fmtRps()`
- fail percentage is formatted with one decimal place

So if an edge saw:

```text
totalAttempted = 600
totalFailed = 1
```

then:

```text
failureRatio = 1 / 600 = 0.0016667 = 0.16667%
```

and the label displays:

```text
0.2% fail
```

## 9. Little's Law Columns: `λ`, `W`, `L`

These are computed in `src/engine/analysis/output.ts`.

### Lambda (`λ`)

Arrival rate during the post-warmup window:

```text
lambda = postWarmupArrived / effectiveDurationSec
```

### W

Mean time spent at the node, using post-warmup spans only:

```text
postWarmupAvgTimeInSystemMs =
  (postWarmupQueueWaitSumMs + postWarmupServiceTimeSumMs) / postWarmupProcessed

W = postWarmupAvgTimeInSystemMs / 1000
```

`W` is shown in seconds conceptually, but formatted as milliseconds or seconds in the UI.

### L

Observed average concurrent items in the node, from post-warmup snapshots:

```text
L = postWarmupInSystemSum / postWarmupInSystemSamples
```

### Expected Little's Law check

The simulator also computes:

```text
expectedL = lambda * W
```

and compares observed `L` vs expected `L`.

## 10. Worked Example From the Screenshot

Using the numbers visible in your screenshot:

```text
Received  = 600
Completed = 599
Rejected  = 1
Timed Out = 0
Error Rate = 0.17%
Availability = 99.8%
Edge fail label = 0.2%
lambda = 10.00
W = 3.5ms
```

If the run used a 60-second effective window, then:

### Throughput

```text
throughput = 599 / 60 = 9.9833 req/s
```

After UI rounding, this displays as approximately:

```text
10 req/s
```

### Error rate

```text
errorRate = (1 + 0) / 600 = 0.0016667
errorRatePercent = 0.16667%
```

Displayed as:

```text
0.17%
```

### Availability

```text
availability = 1 - 0.0016667 = 0.9983333
availabilityPercent = 99.83333%
```

Displayed as:

```text
99.8%
```

### Edge fail percentage

If the edge saw `1` failed transfer out of `600` attempts:

```text
failureRatio = 1 / 600 = 0.16667%
```

Displayed with one decimal place:

```text
0.2% fail
```

### Little's Law

```text
lambda = 600 / 60 = 10.00 req/s
W = 3.5ms = 0.0035s
expectedL = lambda * W = 10.00 * 0.0035 = 0.035
```

So on average, the node is expected to hold about `0.035` requests in the system at any instant.

## 11. UI Rounding Notes

A few displayed values are rounded after calculation:

- Throughput in `WorkspaceLayout.tsx`: 1 decimal place
- Queue depth in `WorkspaceLayout.tsx`: 1 decimal place
- Utilization in `WorkspaceLayout.tsx`: raw ratio converted to percent, then rounded to 0.1
- Error rate in `WorkspaceLayout.tsx`: raw ratio converted to percent, then rounded to 0.01
- Availability in `WorkspaceLayout.tsx`: raw ratio converted to percent, then rounded to 0.1
- Latencies in `WorkspaceLayout.tsx`: rounded to 0.01 ms before being passed into the selected-node panel
- Nodes table formatting in `ResultsTray.tsx`: usually 1 decimal place for ms and 2 decimals for `λ`
- Edge fail percentage in `PacketEdge.tsx`: 1 decimal place

## 12. Practical Summary

If you want to reproduce the numbers by hand, use this checklist:

```text
effectiveDurationSec = (simulationDuration - warmupDuration) / 1000

preRunConcurrency = sim.queue.workers
preRunQueueCapacity = sim.queue.capacity
preRunTimeoutMs = sim.processing.timeout

trafficCompleted = postWarmupProcessed
trafficReceived = postWarmupArrived
trafficRejected = postWarmupRejected
trafficTimedOut = postWarmupTimedOut

throughput = trafficCompleted / effectiveDurationSec
errorRate = (trafficRejected + trafficTimedOut) / trafficReceived
availability = 1 - errorRate

p50/p95/p99 = sorted latency sample at floor(p * (n - 1))

AvgQ = queueLengthSum / queueSamples
Util = utilizationSum / utilizationSamples

lambda = arrived / effectiveDurationSec
W = average time in node after warmup
L = average in-system count after warmup

edgeFailRatio = edgeFailed / edgeAttempted
```

If you want a second doc after this one, the next useful companion would be:

- `simulation-failure-models.md`

covering:

- edge error rate
- node error rate
- packet loss
- block rate
- dropped packets
- timeout

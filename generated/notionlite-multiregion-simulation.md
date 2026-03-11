# Notion Lite Multi-Region Simulation (Topology-Driven)

Source topology: `generated/notionlite-multiregion.topology.json`  
Topology ID: `arch-notion-lite-multiregion-v1`  
Version: `1.0.0`

This document defines the simulation calculations, expected result structure, and topology-specific run context for the Notion-lite multi-region architecture (`ap-south-1` primary, `us-east-1` DR).

## What gets calculated during a run

### Traffic generation from workload pattern
- Pattern: `spike`
- Base traffic: `baseRps = 800`
- Spike traffic: `spikeRps = 4000` from `t=60000ms` for `45000ms`
- Inter-arrival:
```text
constant: interArrivalMs = 1000 / rps
poisson: interArrivalMs ~ exponential(lambda = rps)
spike: rps = baseRps except in [spikeTime, spikeTime + spikeDuration], where rps = spikeRps
```

Derived for this run:
- Simulation duration: `240000ms` (`240s`)
- Warmup: `20000ms` (`20s`)
- Base window seconds: `195s`
- Spike window seconds: `45s`
- Estimated generated requests (pre-filter): `336000`
- Estimated warmup requests (excluded from summary): `16000`
- Estimated requests after warmup: `320000`

### Queueing/service per node using a G/G/c/K model
- Each node uses queue parameters:
```text
workers = c
capacity = K (0 means unlimited)
```
- Arrival handling:
```text
if activeWorkers < workers: start processing
else if queueLength < capacity or capacity == 0: enqueue
else: reject
```
- Service time sampled from node processing distribution.
- Key per-node calculations:
```text
utilization = busyTime / totalTime
queueSaturation = timeAtCapacity / totalTime
avgQueueLength = mean(queueLength samples)
```

### Routing and network latency per edge
- Routing modes used: `synchronous`, `asynchronous`, `streaming`, `conditional`
- Total edge latency:
```text
L = propagation + transmission + processing + queuing + jitter
transmissionMs = request.sizeBytes / (bandwidthMbps * 125)
queuingMultiplier = 1 / (1 - utilization)
effectiveProcessing = processing * queuingMultiplier
```

### Loss/fault/resilience effects
- Packet loss:
```text
effectiveLossRate = basePacketLossRate + max(0, (utilization - 0.8) * 0.1)
drop when rng() < effectiveLossRate
```
- Fault activation model:
```text
timing: deterministic | probabilistic | conditional
duration: fixed | until | permanent
```
- Retry/backoff:
```text
delay = min(baseDelay * multiplier^attempt, maxDelay)
with jitter: delay ~ uniform(0, delay)
```
- Token bucket rate limit:
```text
tokens = min(tokens + refillRate * elapsed, maxTokens)
```

### Metrics aggregation
- Percentiles from sorted successful latencies (warmup-filtered):
```text
p50 = floor(0.50 * N)
p90 = floor(0.90 * N)
p95 = floor(0.95 * N)
p99 = floor(0.99 * N)
```
- Summary metrics:
```text
throughputRps = successfulRequests / ((durationMs - warmupMs) / 1000)
errorRate = failedRequests / totalRequests
availability = 1 - errorRate
```

### Post-run checks
- SLO checks:
```text
latency breach if latencyP99 > slo.latencyP99
availability breach if (1 - errorRate) < slo.availabilityTarget
```
- Little's Law verification per node:
```text
L_observed = average queue length
lambda = totalArrived / durationSeconds
W_observed = average time in system
L_expected = lambda * W_observed
error = |L_observed - L_expected| / max(L_expected, 0.001)
```

## What you receive in results

### Core run output
- `summary`
- `perNode`
- `timeSeries`
- `traces`
- `causalGraph`
- `sloBreaches`
- `invariantViolations`
- `littlesLawCheck`
- `seed`
- `reproducible`

### Expanded schema variant (optional)
- `eventTraces`
- `metrics.global`
- `metrics.perComponent`
- `metrics.perEdge`
- `heatmaps`
- `verification`
- `reproducibilitySpec`

## Run_Context

| field | value |
|---|---|
| run_id | `arch-notion-lite-multiregion-v1` |
| name | `Notion-lite Real-time Collaboration (ap-south-1 primary, us-east-1 DR)` |
| seed | `notion-lite-collab-seed-2026-02-25` |
| simulation_duration_ms | `240000` |
| warmup_ms | `20000` |
| time_resolution | `millisecond` |
| default_timeout_ms | `30000` |
| workload_pattern | `spike` |
| source_node | `node-users` |
| base_rps | `800` |
| spike_rps | `4000` |
| spike_start_ms | `60000` |
| spike_duration_ms | `45000` |
| node_count | `22` |
| edge_count | `31` |
| fault_count | `3` |
| invariant_count | `7` |

## Reference assumptions for example stats

These assumptions are used only to produce concrete reference numbers in this document:
- CloudFront regional split follows weights exactly: `55%` to `ap-south-1`, `45%` to `us-east-1`.
- Request-type routing:
- `CRDT_EDIT` + `CURSOR_MOVE` (`80%`) go through CRDT -> Dynamo.
- `PRESENCE_HEARTBEAT` (`15%`) goes through Presence -> Redis.
- `ASSET_UPLOAD` (`5%`) goes through Blob -> S3.
- JWT validation path (`ws -> auth -> rds`) is applied to all requests.
- No autoscaling changes are applied during this reference run.
- Fault-window reliability assumptions for example output:
- Dynamo failover write success in `us-east-1`: `99.3%`.
- Redis crash reconnect storm rate: `4.1%`.
- CRDT lag window timeout impact on affected CRDT ops: `3.4%`.

## Summary

### Exact workload math from topology

| metric | value | formula |
|---|---:|---|
| total_requests_generated | 336000 | `(195s * 800) + (45s * 4000)` |
| warmup_requests | 16000 | `20s * 800` |
| measured_requests | 320000 | `336000 - 16000` |
| measured_window_seconds | 220 | `(240000-20000)/1000` |

### Example run stats (calculated reference)

| metric | value | calculation |
|---|---:|---|
| successful_requests | 318880 | `320000 - 1120` |
| failed_requests | 1120 | `590 + 41 + 479 + 10` |
| error_requests | 590 | Dynamo write failures during read-only window |
| rejected_requests | 41 | reconnect storm rejects during Redis crash |
| timed_out_requests | 489 | CRDT lag timeouts + residual network timeouts |
| throughput_rps | 1449.45 | `318880 / 220` |
| error_rate | 0.0035 | `1120 / 320000` |
| availability | 0.9965 | `1 - 0.0035` |
| latency_p50_ms | 34 | percentile (reference) |
| latency_p90_ms | 102 | percentile (reference) |
| latency_p95_ms | 210 | percentile (reference) |
| latency_p99_ms | 10420 | tail dominated by `fault-crdt-ap-10s-lag` |

## Per_Node

Node load/utilization reference calculations use:
```text
mean_service_ms = exp(mu + sigma^2 / 2)
utilization_pct = (rps * mean_service_ms / 1000) / workers * 100
```

| node_id | avg_rps_calc | peak_rps_calc | mean_service_ms_calc | workers | utilization_avg_pct | utilization_peak_pct |
|---|---:|---:|---:|---:|---:|---:|
| node-ws-ap | 800.00 | 2200.00 | 4.60 | 12000 | 0.0307 | 0.0843 |
| node-ws-us | 654.55 | 1800.00 | 4.60 | 12000 | 0.0251 | 0.0690 |
| node-auth-ap | 800.00 | 2200.00 | 3.98 | 4000 | 0.0796 | 0.2189 |
| node-auth-us | 654.55 | 1800.00 | 3.98 | 4000 | 0.0651 | 0.1791 |
| node-crdt-ap | 640.00 | 1760.00 | 5.76 | 6000 | 0.0614 | 0.1690 |
| node-crdt-us | 523.64 | 1440.00 | 5.76 | 6000 | 0.0503 | 0.1382 |
| node-presence-ap | 120.00 | 330.00 | 3.67 | 3000 | 0.0147 | 0.0404 |
| node-presence-us | 98.18 | 270.00 | 3.67 | 3000 | 0.0120 | 0.0330 |
| node-blob-ap | 40.00 | 110.00 | 11.53 | 2000 | 0.0231 | 0.0634 |
| node-blob-us | 32.73 | 90.00 | 11.53 | 2000 | 0.0189 | 0.0519 |
| node-search-ap | 560.00 | 1540.00 | 21.00 | 4000 | 0.2940 | 0.8085 |
| node-search-us | 458.18 | 1260.00 | 21.00 | 4000 | 0.2405 | 0.6615 |

Observation:
- With current worker counts, modeled steady-state utilization is low across all critical components; this topology is heavily over-provisioned for the configured workload.

## Per_Edge

Edge throughput/utilization reference calculations use:
```text
throughput_mbps = rps * avg_size_bytes * 8 / 1_000_000
bandwidth_util_pct = throughput_mbps / bandwidth_mbps * 100
tx_latency_ms = avg_size_bytes / (bandwidth_mbps * 125)
```

| edge_id | avg_rps | peak_rps | avg_size_bytes | bandwidth_mbps | throughput_avg_mbps | throughput_peak_mbps | bw_util_avg_pct | bw_util_peak_pct | tx_latency_ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| edge-users-to-cloudfront | 1454.55 | 4000.00 | 13773.2 | 2000 | 160.27 | 440.74 | 8.01 | 22.04 | 0.0551 |
| edge-cloudfront-to-ws-ap | 800.00 | 2200.00 | 13773.2 | 5000 | 88.15 | 242.41 | 1.76 | 4.85 | 0.0220 |
| edge-cloudfront-to-ws-us | 654.55 | 1800.00 | 13773.2 | 5000 | 72.12 | 198.33 | 1.44 | 3.97 | 0.0220 |
| edge-ws-ap-to-crdt-ap | 640.00 | 1760.00 | 810 | 2500 | 4.15 | 11.40 | 0.17 | 0.46 | 0.0026 |
| edge-crdt-ap-to-dynamo-ap | 640.00 | 1760.00 | 810 | 1500 | 4.15 | 11.40 | 0.28 | 0.76 | 0.0043 |
| edge-dynamo-ap-to-dynamo-us | 640.00 | 1760.00 | 810 | 1200 | 4.15 | 11.40 | 0.35 | 0.95 | 0.0054 |
| edge-ws-ap-to-blob-ap | 40.00 | 110.00 | 262144 | 2500 | 83.89 | 230.69 | 3.36 | 9.23 | 0.8389 |
| edge-s3-ap-to-s3-us | 40.00 | 110.00 | 262144 | 1500 | 83.89 | 230.69 | 5.59 | 15.38 | 1.3981 |

## TimeSeries_Global

Reference snapshots around injected faults (1-second buckets):

| ts_ms | throughput_rps | latency_p50_ms | latency_p99_ms | error_rate | active_requests | notes |
|---:|---:|---:|---:|---:|---:|---|
| 30000 | 799 | 34 | 220 | 0.0008 | 950 | steady base load |
| 70000 | 3968 | 52 | 640 | 0.0080 | 6200 | spike + Dynamo read-only window |
| 125000 | 797 | 40 | 780 | 0.0034 | 1400 | Redis crash window |
| 180000 | 788 | 90 | 10800 | 0.0150 | 16500 | CRDT lag window |
| 210000 | 790 | 48 | 1400 | 0.0060 | 4200 | lag drain/recovery |
| 230000 | 799 | 35 | 260 | 0.0010 | 1100 | post-fault steady state |

## TimeSeries_Component

Reference component snapshots (selected high-signal rows):

| ts_ms | component_id | queue_length | active_workers_or_requests | replicas | throughput_rps | latency_p99_ms | error_rate | status |
|---:|---|---:|---:|---:|---:|---:|---:|---|
| 30000 | node-crdt-ap | 24 | 5 | 4 | 352 | 240 | 0.001 | healthy |
| 70000 | node-dynamo-ap | 380 | 14 | 3 | 1760 | 680 | 0.021 | degraded (read-only fault active) |
| 70000 | node-dynamo-us | 410 | 18 | 3 | 3200 | 720 | 0.007 | failover-write hot path |
| 125000 | node-redis-ap | 5100 | 0 | 1 | 0 | 0 | 1.000 | failed (process-crash active) |
| 125000 | node-presence-ap | 880 | 3 | 3 | 66 | 940 | 0.041 | degraded (reconnect storm) |
| 180000 | node-crdt-ap | 16200 | 6 | 4 | 352 | 11100 | 0.034 | severe lag (latency-spike active) |
| 180000 | node-ws-ap | 9800 | 11 | 3 | 440 | 1320 | 0.012 | upstream backpressure visible |
| 210000 | node-crdt-ap | 4100 | 6 | 4 | 352 | 1600 | 0.007 | recovering |
| 230000 | node-crdt-ap | 70 | 4 | 4 | 352 | 250 | 0.001 | recovered |

## Traces

Reference traces (calculated examples):

| request_id | status | total_latency_ms | span_index | component_id | queue_ms | processing_ms | network_ms | start_ms | end_ms |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|
| req-00029184 | success | 42 | 1 | node-ws-ap | 1 | 4 | 12 | 0 | 17 |
| req-00029184 | success | 42 | 2 | node-auth-ap | 0 | 3 | 2 | 17 | 22 |
| req-00029184 | success | 42 | 3 | node-crdt-ap | 2 | 6 | 3 | 22 | 33 |
| req-00029184 | success | 42 | 4 | node-dynamo-ap | 1 | 5 | 3 | 33 | 42 |
| req-00148302 | success | 318 | 1 | node-ws-ap | 4 | 6 | 18 | 0 | 28 |
| req-00148302 | success | 318 | 2 | node-crdt-ap | 8 | 9 | 4 | 36 | 57 |
| req-00148302 | success | 318 | 3 | node-dynamo-ap | 6 | 7 | 5 | 57 | 75 |
| req-00148302 | success | 318 | 4 | node-dynamo-us | 120 | 90 | 33 | 75 | 318 |
| req-00222491 | timeout | 10035 | 1 | node-ws-ap | 3 | 5 | 15 | 0 | 23 |
| req-00222491 | timeout | 10035 | 2 | node-auth-ap | 1 | 4 | 3 | 23 | 31 |
| req-00222491 | timeout | 10035 | 3 | node-crdt-ap | 6200 | 3800 | 4 | 31 | 10035 |

## SLO_Breaches

| breach_start_ms | breach_end_ms | node_id_or_scope | metric | threshold | actual | duration_ms | severity | affected_requests |
|---:|---:|---|---|---:|---:|---:|---|---:|
| 60000 | 240000 | global | availability | 0.9999 | 0.9965 | 180000 | critical | 1120 |
| 170000 | 210000 | node-crdt-ap | latency-p99-ms | 200 | 10420 | 40000 | critical | 14080 |
| 170000 | 212000 | node-ws-ap | latency-p99-ms | 250 | 1320 | 42000 | warning | 17600 |

## Invariant_Violations

| violated_at_ms | invariant_id | severity | condition | message | root_cause | affected_components |
|---:|---|---|---|---|---|---|
| 120000 | inv-global-availability-slo | critical | `global.availability >= 0.9999` | Overall availability must meet 99.99% SLO. | compound fault impact across 3 windows | node-dynamo-ap\|node-redis-ap\|node-crdt-ap |
| 180000 | inv-crdt-divergence-window | critical | `crdt.userVisibleDivergenceWindowMs <= 10000` | CRDT lag fault should keep divergence bounded. | `fault-crdt-ap-10s-lag` | node-crdt-ap\|node-ws-ap |

## Little_Law

| node_id | L_observed | lambda_rps | W_observed_s | L_expected | error_pct | status |
|---|---:|---:|---:|---:|---:|---|
| node-ws-ap | 5.30 | 800.00 | 0.0064 | 5.12 | 0.035 | PASS |
| node-crdt-ap | 98.40 | 640.00 | 0.1350 | 86.40 | 0.139 | WARN |
| node-crdt-us | 4.20 | 523.64 | 0.0078 | 4.08 | 0.029 | PASS |
| node-redis-ap | 0.30 | 120.00 | 0.0024 | 0.29 | 0.042 | PASS |

## Hypothesis_Scorecard

| hypothesis | injection | observed_metric_1 | observed_metric_2 | pass_rule | result |
|---|---|---:|---:|---|---|
| ap-south-1 DynamoDB read-only takeover | `fault-dynamo-ap-readonly` | `us-east-1 writeSuccessRate = 0.993` | `failoverRtoMs = 7800` | `writeSuccessRate >= 0.99` and `RTO <= 30000` | PASS |
| Presence Redis crash behavior | `fault-redis-ap-crash` | `reconnectStormRate = 0.041` | `recoveryTimeMs = 15000` | `reconnectStormRate <= 0.05` | PASS |
| CRDT lag divergence window | `fault-crdt-ap-10s-lag` | `userVisibleDivergenceWindowMs = 10180` | `crdt-p99-ms = 10420` | `divergenceWindowMs <= 10000` | FAIL |

## Fault timeline

| fault_id | target | type | start_ms | duration_ms | end_ms | estimated_requests_in_window |
|---|---|---|---:|---:|---:|---:|
| fault-dynamo-ap-readonly | node-dynamo-ap | error-rate (`writes-only`, rate=1) | 60000 | 60000 | 120000 | 105600 total region-ap requests |
| fault-redis-ap-crash | node-redis-ap | process-crash | 120000 | 15000 | 135000 | 990 presence events at risk |
| fault-crdt-ap-10s-lag | node-crdt-ap | latency-spike (`addedMs=10000`, `multiplier=8`) | 170000 | 40000 | 210000 | 14080 CRDT ops affected |

## Notes

- Numbers in `Run_Context` and workload totals are exact from topology.
- `Summary`, `TimeSeries`, `SLO_Breaches`, `Invariant_Violations`, `Little_Law`, and `Hypothesis_Scorecard` are concrete reference stats calculated from topology plus the explicit assumptions listed above.
- Replace the reference values with actual simulator output JSON values when engine run artifacts are available.

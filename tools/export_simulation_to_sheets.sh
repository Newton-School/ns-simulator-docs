#!/usr/bin/env bash
set -euo pipefail

if [[ ${1-} == "" ]]; then
  echo "Usage: $0 <simulation-output.json> [output-dir]" >&2
  exit 1
fi

INPUT_JSON="$1"
OUTPUT_DIR="${2:-generated/sheets_export_$(date +%Y%m%d_%H%M%S)}"

if [[ ! -f "$INPUT_JSON" ]]; then
  echo "Input JSON not found: $INPUT_JSON" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

jq -r '
[
  ["run_id","seed","topology_id","duration_ms","warmup_ms","workload_pattern","base_rps","spike_rps","spike_start_ms","spike_duration_ms"],
  [
    (.runId // .id // ""),
    (.seed // .reproducibilitySpec.seed // .global.seed // ""),
    (.topologyId // .architecture.id // ""),
    (.simulatedDurationMs // .summary.duration // .duration // .global.simulationDuration // ""),
    (.warmupDuration // .global.warmupDuration // ""),
    (.workload.pattern // .workload.type // ""),
    (.workload.baseRps // .workload.requestsPerSecond // ""),
    (.workload.spike.spikeRps // .workload.spikeRps // ""),
    (.workload.spike.spikeTime // .workload.spikeStartMs // ""),
    (.workload.spike.spikeDuration // .workload.spikeDurationMs // "")
  ]
] | .[] | @csv
' "$INPUT_JSON" > "$OUTPUT_DIR/Run_Context.csv"

jq -r '
def total: (.summary.totalRequests // .requestTraces.totalRequests // .metrics.global.availability.totalRequests);
def success: (.summary.successfulRequests // .metrics.global.availability.successfulRequests);
def failed_calc: if (total|type) == "number" and (success|type) == "number" then (total - success) else null end;
def err: (.summary.errorRate // .metrics.global.errors.errorRate);
def avail_calc: if (err|type) == "number" then (1 - err) else null end;
[
  ["metric","value","formula"],
  ["total_requests", (total // ""), ""],
  ["successful_requests", (success // ""), ""],
  ["failed_requests", (.summary.failedRequests // failed_calc // ""), ""],
  ["rejected_requests", (.summary.rejectedRequests // ""), ""],
  ["timed_out_requests", (.summary.timedOutRequests // .summary.timeoutRequests // ""), ""],
  ["error_rate", (err // ""), "=B4/B2"],
  ["availability", (.summary.availability // .metrics.global.availability.availabilityPercent // avail_calc // ""), "=1-B7"],
  ["throughput_rps", (.summary.throughput // .metrics.global.throughput.requestsPerSecond // ""), "=B3/((Run_Context!D2-Run_Context!E2)/1000)"],
  ["latency_p50_ms", (.summary.latency.p50 // .metrics.global.latency.p50 // ""), ""],
  ["latency_p90_ms", (.summary.latency.p90 // .metrics.global.latency.p90 // ""), ""],
  ["latency_p95_ms", (.summary.latency.p95 // .metrics.global.latency.p95 // ""), ""],
  ["latency_p99_ms", (.summary.latency.p99 // .metrics.global.latency.p99 // ""), ""]
] | .[] | @csv
' "$INPUT_JSON" > "$OUTPUT_DIR/Summary.csv"

jq -r '
. as $root |
def rows:
  if ($root.perNode | type) == "object" then
    $root.perNode | to_entries[] |
    {
      node_id: .key,
      arrived: (.value.totalArrived // .value.totalRequests // .value.arrived),
      processed: (.value.totalProcessed // .value.totalSucceeded // .value.successfulRequests // .value.processed),
      rejected: (.value.totalRejected // .value.rejected),
      timed_out: (.value.totalTimedOut // .value.timedOutRequests // .value.timeouts),
      avg_queue_len: (.value.avgQueueLength // .value.queueLength // .value.saturation.queueLength),
      peak_queue_len: (.value.peakQueueLength // .value.maxQueueLength),
      avg_service_ms: (.value.avgServiceTime // .value.avgServiceMs // .value.latency.mean),
      p99_ms: (.value.p99 // .value.latencyP99 // .value.latency.p99),
      busy_time_ms: (.value.busyTimeMs),
      total_time_ms: ($root.summary.duration // $root.simulatedDurationMs // $root.duration),
      utilization: (.value.utilization // .value.saturation.cpuUtilization)
    }
  elif ($root.metrics.perComponent | type) == "object" then
    $root.metrics.perComponent | to_entries[] |
    {
      node_id: .key,
      arrived: (.value.availability.totalRequests),
      processed: (.value.availability.successfulRequests),
      rejected: null,
      timed_out: null,
      avg_queue_len: (.value.saturation.queueLength),
      peak_queue_len: null,
      avg_service_ms: (.value.latency.mean),
      p99_ms: (.value.latency.p99),
      busy_time_ms: null,
      total_time_ms: ($root.simulatedDurationMs // $root.summary.duration // $root.duration),
      utilization: (.value.saturation.cpuUtilization)
    }
  elif ($root.timeSeries | type) == "array" and (($root.timeSeries | length) > 0) then
    ($root.timeSeries[-1].nodes // {}) | to_entries[] |
    {
      node_id: .key,
      arrived: null,
      processed: null,
      rejected: null,
      timed_out: null,
      avg_queue_len: (.value.queueLength),
      peak_queue_len: (.value.queueLength),
      avg_service_ms: null,
      p99_ms: (.value.latencyP99 // .value.p99),
      busy_time_ms: null,
      total_time_ms: ($root.summary.duration // $root.simulatedDurationMs // $root.duration),
      utilization: (.value.utilization)
    }
  else empty end;
(["node_id","arrived","processed","rejected","timed_out","avg_queue_len","peak_queue_len","avg_service_ms","p99_ms","busy_time_ms","total_time_ms","utilization"] | @csv),
(rows | [
  .node_id,
  (.arrived // ""),
  (.processed // ""),
  (.rejected // ""),
  (.timed_out // ""),
  (.avg_queue_len // ""),
  (.peak_queue_len // ""),
  (.avg_service_ms // ""),
  (.p99_ms // ""),
  (.busy_time_ms // ""),
  (.total_time_ms // ""),
  (.utilization // "")
] | @csv)
' "$INPUT_JSON" > "$OUTPUT_DIR/Per_Node.csv"

jq -r '
. as $root |
(($root.architecture.edges // $root.edges // [])
 | map({ key: .id, value: { src: (.source // ""), dst: (.target // "") } })
 | from_entries) as $emap |
def rows:
  if ($root.metrics.perEdge | type) == "object" then
    $root.metrics.perEdge | to_entries[] |
    {
      edge_id: .key,
      src: ($emap[.key].src // ""),
      dst: ($emap[.key].dst // ""),
      throughput_rps: (.value.throughput.requestsPerSecond // .value.throughputRps // .value.throughput),
      p50_latency_ms: (.value.latency.p50 // .value.latencyP50 // .value.p50),
      packet_loss_rate: (.value.packetLoss // .value.packetLossRate),
      current_load: (.value.currentLoad),
      utilization: (.value.utilization)
    }
  elif ($root.timeSeries | type) == "array" and (($root.timeSeries | length) > 0) then
    ($root.timeSeries[-1].edges // {}) | to_entries[] |
    {
      edge_id: .key,
      src: ($emap[.key].src // ""),
      dst: ($emap[.key].dst // ""),
      throughput_rps: (.value.throughput // .value.throughputRps),
      p50_latency_ms: (.value.latencyP50 // .value.p50),
      packet_loss_rate: (.value.packetLoss // .value.packetLossRate),
      current_load: (.value.currentLoad),
      utilization: (.value.utilization)
    }
  else empty end;
(["edge_id","src","dst","throughput_rps","p50_latency_ms","packet_loss_rate","current_load","utilization"] | @csv),
(rows | [
  .edge_id,
  .src,
  .dst,
  (.throughput_rps // ""),
  (.p50_latency_ms // ""),
  (.packet_loss_rate // ""),
  (.current_load // ""),
  (.utilization // "")
] | @csv)
' "$INPUT_JSON" > "$OUTPUT_DIR/Per_Edge.csv"

jq -r '
. as $root |
def rows:
  if ($root.timeSeries | type) == "array" then
    $root.timeSeries[] |
    [
      (.timestamp // ""),
      (.global.totalRps // .global.throughputRps // ""),
      (.global.latencyP50 // .global.avgLatency // ""),
      (.global.latencyP99 // ""),
      (.global.errorRate // ""),
      (.global.activeRequests // "")
    ]
  elif ($root.timeSeries | type) == "object" and (($root.timeSeries.timestamps | type) == "array") then
    range(0; ($root.timeSeries.timestamps | length)) as $i |
    [
      ($root.timeSeries.timestamps[$i] // ""),
      ($root.timeSeries.global.throughputRps[$i] // ""),
      ($root.timeSeries.global.latencyP50[$i] // ""),
      ($root.timeSeries.global.latencyP99[$i] // ""),
      ($root.timeSeries.global.errorRate[$i] // ""),
      ($root.timeSeries.global.activeRequests[$i] // "")
    ]
  else empty end;
(["ts_ms","throughput_rps","latency_p50_ms","latency_p99_ms","error_rate","active_requests"] | @csv),
(rows | @csv)
' "$INPUT_JSON" > "$OUTPUT_DIR/TimeSeries_Global.csv"

jq -r '
. as $root |
def rows:
  if ($root.timeSeries | type) == "array" then
    $root.timeSeries[] as $snap |
    ($snap.nodes // {}) | to_entries[] |
    [
      ($snap.timestamp // ""),
      .key,
      (.value.queueLength // ""),
      (.value.activeWorkers // .value.activeRequests // ""),
      (.value.replicas // ""),
      (.value.rps // .value.throughputRps // ""),
      (.value.latencyP99 // .value.p99 // ""),
      (.value.cpuUtilization // ""),
      (.value.memoryUtilization // ""),
      (.value.errorRate // "")
    ]
  elif ($root.timeSeries | type) == "object" and (($root.timeSeries.timestamps | type) == "array") then
    ($root.timeSeries.components // {}) | to_entries[] as $comp |
    range(0; ($root.timeSeries.timestamps | length)) as $i |
    [
      ($root.timeSeries.timestamps[$i] // ""),
      $comp.key,
      ($comp.value.queueLength[$i] // ""),
      ($comp.value.activeRequests[$i] // ""),
      ($comp.value.replicas[$i] // ""),
      ($comp.value.throughputRps[$i] // ""),
      ($comp.value.latencyP99[$i] // ""),
      ($comp.value.cpuUtilization[$i] // ""),
      ($comp.value.memoryUtilization[$i] // ""),
      ($comp.value.errorRate[$i] // "")
    ]
  else empty end;
(["ts_ms","component_id","queue_len","active_requests","replicas","throughput_rps","latency_p99_ms","cpu_util","mem_util","error_rate"] | @csv),
(rows | @csv)
' "$INPUT_JSON" > "$OUTPUT_DIR/TimeSeries_Component.csv"

jq -r '
def traces: (.traces // .requestTraces.traces // []);
(["request_id","status","total_latency_ms","span_index","component_id","queue_ms","processing_ms","network_ms","start_ms","end_ms"] | @csv),
(
  traces[]? as $t |
  ($t.spans // []) as $spans |
  if ($spans | length) == 0 then
    [
      ($t.requestId // $t.id // ""),
      ($t.status // ""),
      ($t.totalLatency // $t.totalDurationMs // ""),
      "", "", "", "", "", "", ""
    ]
  else
    range(0; ($spans | length)) as $i |
    ($spans[$i]) as $s |
    [
      ($t.requestId // $t.id // ""),
      ($t.status // ""),
      ($t.totalLatency // $t.totalDurationMs // ""),
      ($i + 1),
      ($s.nodeId // $s.componentId // ""),
      ($s.queueWait // $s.queueTimeMs // ""),
      ($s.serviceTime // $s.processingTimeMs // ""),
      ($s.edgeLatency // $s.networkTimeMs // ""),
      ($s.start // $s.startTime // ""),
      ($s.end // $s.endTime // "")
    ]
  end
  | @csv
)
' "$INPUT_JSON" > "$OUTPUT_DIR/Traces.csv"

jq -r '
(["breach_start_ms","breach_end_ms","node_id","metric","threshold","actual","duration_ms","severity","affected_requests"] | @csv),
(
  (.sloBreaches // [])[]? |
  [
    (.breachStartMs // .time // .timestamp // ""),
    (.breachEndMs // ""),
    (.nodeId // .componentId // .scope // ""),
    (.metric // .sloType // ""),
    (.target // .threshold // ""),
    (.actual // .actualValue // ""),
    (.durationMs // ""),
    (.severity // ""),
    (.affectedRequests // "")
  ]
  | @csv
)
' "$INPUT_JSON" > "$OUTPUT_DIR/SLO_Breaches.csv"

jq -r '
(["violated_at_ms","invariant_id","invariant_name","details","root_cause","affected_components"] | @csv),
(
  (.invariantViolations // [])[]? |
  [
    (.violatedAt // .time // ""),
    (.invariantId // .id // ""),
    (.invariantName // .name // ""),
    (.details // .description // ""),
    (.rootCause // ""),
    ((.affectedComponents // []) | join("|"))
  ]
  | @csv
)
' "$INPUT_JSON" > "$OUTPUT_DIR/Invariant_Violations.csv"

jq -r '
. as $root |
def ll_rows:
  if ($root.littlesLawCheck | type) == "array" then
    $root.littlesLawCheck[]
  elif ($root.verification | type) == "object" and (($root.verification.littlesLaw | type) == "array") then
    $root.verification.littlesLaw[]
  elif ($root.verification | type) == "object" and (($root.verification.littlesLawCheck | type) == "array") then
    $root.verification.littlesLawCheck[]
  else empty end;
(["node_id","L_observed","lambda","W_observed","L_expected","error_pct","status"] | @csv),
(
  ll_rows |
  (
    if (.error | type) == "number" then .error
    elif (.errorPct | type) == "number" then .errorPct
    elif ((.actual // .L_observed) | type) == "number" and ((.expected // .L_expected) | type) == "number" then
      (((.actual // .L_observed) - (.expected // .L_expected)) | if . < 0 then - . else . end)
      / (((.expected // .L_expected) | if . < 0.001 then 0.001 else . end))
    else "" end
  ) as $err |
  [
    (.nodeId // .componentId // ""),
    (.actual // .L_observed // .lObserved // ""),
    (.lambda // ""),
    (.wObserved // .W_observed // ""),
    (.expected // .L_expected // ""),
    $err,
    (if ($err | type) == "number" then (if $err <= 0.10 then "PASS" else "WARN" end) else "" end)
  ]
  | @csv
)
' "$INPUT_JSON" > "$OUTPUT_DIR/Little_Law.csv"

jq -r '
. as $root |
def is_violated($id): any(($root.invariantViolations // [])[]?; ((.invariantId // .id // "") == $id));
def dyn_us_rate:
  if (($root.perNode | type) == "object") and (($root.perNode["node-dynamo-us"] // null) != null) then
    ($root.perNode["node-dynamo-us"]) as $n |
    if (($n.totalArrived // 0) | type) == "number" and (($n.totalProcessed // 0) | type) == "number" and ($n.totalArrived > 0) then
      ($n.totalProcessed / $n.totalArrived)
    else "" end
  elif (($root.metrics.perComponent | type) == "object") and (($root.metrics.perComponent["node-dynamo-us"] // null) != null) then
    ($root.metrics.perComponent["node-dynamo-us"].availability) as $a |
    if (($a.totalRequests // 0) | type) == "number" and (($a.successfulRequests // 0) | type) == "number" and ($a.totalRequests > 0) then
      ($a.successfulRequests / $a.totalRequests)
    else "" end
  else "" end;
def pass_fail($invId):
  if (($root.invariantViolations | type) == "array") then
    (if is_violated($invId) then "FAIL" else "PASS" end)
  else "UNKNOWN" end;
[
  ["hypothesis","observed_metric_1","observed_metric_2","pass_rule","result"],
  [
    "Dynamo read-only takeover",
    dyn_us_rate,
    "",
    "write_success_rate>=0.99 AND failover_rto_ms<=30000",
    pass_fail("inv-dynamo-write-takeover")
  ],
  [
    "Redis crash graceful degradation",
    "",
    "",
    "reconnect_storm_rate<=0.05",
    pass_fail("inv-presence-graceful-degradation")
  ],
  [
    "CRDT lag divergence window",
    "",
    "",
    "divergence_window_ms<=10000",
    pass_fail("inv-crdt-divergence-window")
  ]
]
| .[] | @csv
' "$INPUT_JSON" > "$OUTPUT_DIR/Hypothesis_Scorecard.csv"

ls -1 "$OUTPUT_DIR" | sed 's#^#Wrote: #' 

# Output Analysis Playbook

## Analysis order
1. Confirm run metadata (`seed`, duration, workload, faults).
2. Check global KPIs (`throughput`, `error rate`, `p95/p99 latency`).
3. Identify top bottleneck nodes and edges.
4. Inspect trace samples around onset of degradation.
5. Reconstruct causal failure path.
6. Validate invariant and SLO breaches.
7. Recommend mitigations with priority.

## Evidence checklist
- Summary metrics snapshot
- Per-node utilization and queue depth
- Time-series inflection point timestamps
- Request traces before and after failure onset
- Causal graph edges that connect trigger to impact
- Breach records (invariants/SLOs)

## Bottleneck heuristics
- High queue depth + high utilization + rising latency usually indicates service saturation.
- Rising retries with stable traffic often indicate downstream instability.
- High p99 with stable p50 often indicates tail latency from queueing or contention.
- Error spikes after retry policy changes can indicate retry amplification.

## Causality guardrails
- Use timestamp ordering to support causal claims.
- Separate root trigger from propagated symptoms.
- Mark conclusions as inference when telemetry is incomplete.

## Report template
- `Run context`
- `Top findings` (ordered by severity)
- `Evidence` (metric/artifact -> conclusion)
- `Root cause and propagation path`
- `Recommended actions` (`Now`, `Next`, `Later`)
- `Confidence and unknowns`
- `Follow-up experiments`

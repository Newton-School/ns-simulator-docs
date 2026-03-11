# Chaos Experiment Template

## Experiment skeleton
- `name`
- `hypothesis`
- `steady_state_metrics`
- `workload_configuration`
- `faults`
- `abort_conditions`
- `success_criteria`
- `rollback_or_containment`

## Example metrics
- `p99 latency`
- `error rate`
- `throughput`
- `queue depth`
- `recovery time`

## Safety checklist
- Define blast radius limit.
- Define auto-abort triggers.
- Define observer metrics and polling interval.
- Define rollback path before execution.

## Good experiment properties
- Single primary hypothesis.
- Deterministic seed and timing when possible.
- Clear criteria for both failure and success.

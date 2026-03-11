# Topology JSON Rules

## Required top-level keys
- `id`, `name`, `version`
- `global`
- `nodes[]`
- `edges[]`
- `workload`
- `faults[]`
- `invariants[]`
- `scenarios[]` (can be empty)

## Global constraints
- `global.simulationDuration > global.warmupDuration`
- `global.warmupDuration >= 0`
- `global.defaultTimeout > 0`
- `global.seed` must be set for reproducibility.
- Use `timeResolution` from `microsecond | millisecond`.

## Node checklist
- `node.id` is unique and stable.
- `node.type` exists in DSDS component taxonomy.
- `queue.workers > 0`
- `queue.capacity >= 0`
- `processing.timeout > 0`
- Dependencies reference existing node ids.
- Resource values are non-negative.

## Edge checklist
- `edge.id` is unique.
- `edge.source` and `edge.target` exist in `nodes[]`.
- `mode` and `protocol` match DSDS enums.
- Latency distribution parameters are valid.
- `packetLossRate` and `errorRate` are in `[0, 1]`.
- `weight > 0` when weighted routing is used.

## Workload checklist
- `sourceNodeId` exists and is a traffic source.
- Pattern-specific sub-config exists for selected pattern.
- Request type weights sum to `1.0` (or normalize before output).

## Fault checklist
- Each `targetId` exists.
- Fault timing mode is explicit (`deterministic`, `probabilistic`, or `conditional`).
- Duration policy is explicit (`fixed`, `until`, `permanent`).

## Invariant checklist
- Every invariant has an id, condition, severity, and message.
- Every invariant maps to an observable metric or state transition.

## Distribution parameter checks
- `log-normal`: `sigma > 0`
- `normal`: `stddev > 0`
- `exponential`: `lambda > 0`
- `poisson`: `lambda > 0`
- `weibull`: `shape > 0`, `scale > 0`
- `gamma`: `shape > 0`, `rate > 0`
- `beta`: `alpha > 0`, `beta > 0`
- `pareto`: `alpha > 0`, `xMin > 0`

## Minimal starter topology
```json
{
  "id": "arch-ecommerce-v1",
  "name": "Ecommerce Starter",
  "version": "1.0.0",
  "global": {
    "simulationDuration": 60000,
    "seed": "demo-seed",
    "warmupDuration": 5000,
    "timeResolution": "microsecond",
    "defaultTimeout": 30000
  },
  "nodes": [],
  "edges": [],
  "workload": {},
  "faults": [],
  "invariants": [],
  "scenarios": []
}
```

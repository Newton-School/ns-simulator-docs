# Scenario Patterns

## Scenario template
Use this structure for every scenario:
- `name`
- `intent` (single hypothesis)
- `seed`
- `duration` and `warmup`
- `workload` (pattern + request mix)
- `faults` (target + timing + duration + params)
- `invariants`
- `expected_outcomes`
- `pass_fail_rules`

## High-value scenario families
- Latency degradation under normal traffic
- Traffic spike saturation and recovery
- Dependency outage and cascade containment
- Region partition and consistency behavior
- Cost surge under autoscaling behavior

## Mapping to DSDS built-ins
- Cache stampede: spike traffic + synchronized cache expiry + origin overload checks
- DB primary crash: write-heavy workload + failover fault + durability/integrity checks
- Network partition: cross-region writes + partition fault + split-brain checks
- Auth outage: dependency crash + login path assertions + graceful degradation checks
- 10x traffic spike: burst workload + cold-start penalties + collapse-point tracking

## Fault timing guidance
- Deterministic: use for regression and comparison runs.
- Probabilistic: use for robustness sweeps after deterministic baseline is stable.
- Conditional: use for trigger-based experiments (for example, `cpu > 0.9`).

## Anti-pattern guardrails
- Avoid combining many unrelated faults in one scenario.
- Avoid changing seed between baseline and variant runs.
- Avoid mixing policy changes and topology changes in one experiment.
- Avoid pass/fail rules that are not tied to metrics.

## Pass/fail examples
- `p99 latency < 300ms during steady-state window`
- `error rate < 1% after minute 2`
- `MTTR < 45s after injected db crash`
- `No causal chain reaches checkout service in auth outage scenario`

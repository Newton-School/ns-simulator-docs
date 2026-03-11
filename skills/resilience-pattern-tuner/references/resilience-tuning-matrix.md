# Resilience Tuning Matrix

## Core controls and intent
- Retry: increase success under transient faults.
- Timeout: bound waiting time and protect upstream capacity.
- Circuit breaker: stop sending traffic to unhealthy dependencies.
- Bulkhead: isolate resource pools by path.
- Rate limit/load shed: preserve critical traffic under overload.

## Guardrail heuristics
- Retry count stays low for latency-sensitive paths.
- Retry backoff includes jitter to avoid synchronization.
- Breaker recovery probes are limited and controlled.
- Bulkhead limits align with downstream concurrency.
- Shedding policy is explicit about priority classes.

## Verification signals
- Lower tail latency under stress
- Reduced retry amplification
- Faster recovery after dependency failure
- Stable throughput on critical endpoints

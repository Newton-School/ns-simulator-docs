# Invariant Catalog

## Core invariant families
- Idempotency: same key does not produce duplicate side effects.
- Causal ordering: dependent events preserve required order.
- Consistency: domain constraints always hold (for example non-negative balance).
- Security: unauthorized access is never successful.
- SLO: latency and availability objectives stay within thresholds.

## Severity guidance
- Critical: correctness or security violation.
- High: major reliability breach with user impact.
- Medium: degraded behavior that risks future incidents.
- Low: drift or warning without direct impact.

## Violation record fields
- `invariant_id`
- `severity`
- `first_seen_time`
- `impacted_components`
- `evidence`
- `likely_cause`

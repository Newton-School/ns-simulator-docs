# Propagation Modeling Checklist

## Trigger setup
- What failed first?
- Is the failure partial, total, intermittent, or delayed?
- What is the expected duration?

## First-order effects
- Immediate timeout or rejection behavior
- Queue and retry behavior at adjacent services
- Dependency health transitions

## Second-order effects
- Retry amplification
- Resource starvation
- Circuit breaker state changes
- Cross-region consistency issues

## User impact lens
- Which journeys fail first?
- Which journeys degrade but succeed?
- Which controls preserve partial service?

## Mitigation checklist
- Timeout hierarchy is bounded.
- Retry policy has jitter and caps.
- Backpressure signals propagate upstream.
- Load shedding protects critical paths.

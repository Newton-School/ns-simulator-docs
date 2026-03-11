# Taxonomy Selection Guide

## Selection principles
- Prefer explicit capability fit over familiar tooling names.
- Distinguish control plane components from data plane components.
- Select the smallest set of components that captures behavior under test.

## Common requirement to category mapping
- Request handling and business logic -> `compute`
- Traffic routing and API ingress -> `network`
- Durable state and indexing -> `storage`
- Async delivery and fan-out -> `messaging`
- Runtime management and deployment -> `orchestration`
- AuthN/AuthZ and protection boundaries -> `security`
- Logging, metrics, traces, and alerting -> `observability`

## Tie-break examples
- `api-gateway` vs `reverse-proxy`: choose `api-gateway` when policy/rate/auth concerns are first-class.
- `queue` vs `stream`: choose `stream` for ordered replay and event history; choose `queue` for work distribution.
- `cache` vs `nosql-keyvalue`: choose `cache` for ephemeral acceleration; choose `nosql-keyvalue` for persistent serving state.

## Output checklist
- Every selected component type exists in taxonomy.
- Every required behavior has an owning component.
- Every component has a stated reason to exist.
- Unknowns are tracked as assumptions, not omitted.

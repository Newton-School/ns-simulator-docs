# External Reconciliation V2

Canonical pack for modeled authoritative side-effect reconciliation.

- `reference-topology.json` records idempotency intent, lets the first payment attempt time out after the side effect is marked committed in the modeled registry, then reconciles the retry.
- `gamed-topology.json` records the same unknown outcome but disables reconciliation, so retries are blocked rather than confirmed from the authoritative status lookup.
- The simulator does not call live payment-provider APIs; this pack validates the deterministic adapter contract and shared modeled registry.

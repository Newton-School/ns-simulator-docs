---
title: "M08 - Traits: Pluggable Node Behaviors"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Explain the trait system and the inline cache model; know when a basic cache fails.
Then the coordination / V2 traits that turn distributed behavior into gradeable runtime
state.

## Concepts (atomic notes)
- [[concepts/caching/cache-aside-is-bernoulli-thinning|Cache-aside is Bernoulli thinning]]
- [[concepts/caching/cache-stampede-is-a-thundering-herd|A cache stampede is a thundering herd]]
- [[concepts/caching/request-collapsing-dedups-inflight-misses|Request collapsing dedups in-flight misses]]
- [[concepts/simulation/state-machines-make-behavior-gradeable|State machines make behavior gradeable]]
- [[concepts/storage/quorum-writes-trade-latency-for-durability|Quorum writes trade latency for durability]]
- [[concepts/workloads/consumer-groups-deliver-once-per-group|A stream delivers each message once per consumer group]]

## Teaching vehicle
[[p03-global-leaderboard|P03 - Leaderboard]] (basic cache) → [[p11-celebrity-upload|P11 - Celebrity Upload]]
(stampede forces request collapsing).

## Source of truth (specs)
- [[trait-integration-guide|trait-integration-guide.md]] · [[node-capability-matrix|node-capability-matrix.md]] · [[replication-quorum-state-machine-walkthrough|replication-quorum walkthrough]] · Code: `src/engine/traits/*`

## Demo
Place a cache inline (svc→cache→db); watch the hit/miss split offload the DB.
## Exercise: vary cacheHitRate 0.5→0.9 → DB load and p99 move.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m07-edges|M07]] · Next [[m09-cost-model|M09]]

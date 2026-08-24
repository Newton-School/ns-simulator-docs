---
title: "M08 - Traits: Pluggable Node Behaviors"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Explain the trait system and the inline cache model; know when a basic cache fails.

## Concepts (atomic notes)
- [[concepts/caching/cache-aside-is-bernoulli-thinning|Cache-aside is Bernoulli thinning]]
- [[concepts/caching/cache-stampede-is-a-thundering-herd|A cache stampede is a thundering herd]]
- [[concepts/caching/request-collapsing-dedups-inflight-misses|Request collapsing dedups in-flight misses]]

## Teaching vehicle
[[p03-global-leaderboard|P03 - Leaderboard]] (basic cache) → [[p11-celebrity-upload|P11 - Celebrity Upload]]
(stampede forces request collapsing).

## Source of truth (specs)
- [[trait-integration-guide|trait-integration-guide.md]] · Code: `src/engine/traits/*`

## Demo
Place a cache inline (svc→cache→db); watch the hit/miss split offload the DB.
## Exercise: vary cacheHitRate 0.5→0.9 → DB load and p99 move.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m07-edges|M07]] · Next [[m09-cost-model|M09]]

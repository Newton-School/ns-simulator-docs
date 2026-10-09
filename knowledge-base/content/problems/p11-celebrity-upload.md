---
title: "Problem 11 - Viral Celebrity Upload"
type: problem
cluster: Cache stampede + request collapsing
tags: [problem]
---
**Purpose:** a cold hot-key triggers a cache stampede; the basic cache trait must be
swapped for request collapsing to survive.

**In the simulator (October 2026):** both halves are measured. With one hot key at 1,500
req/s and a cold cache, every miss reaches the store and every request times out. Turning on
Request collapsing on the cache (with a keyspace on the source so requests carry the key)
drops store calls to about one per in-flight fetch (about 98/s in the reference run), with no
errors and a p99 of about 15 ms. The cache-stampede chaos experiment flushes the cache
mid-run and checks the origin survives.

## Teaches (concepts)
- [[concepts/caching/cache-stampede-is-a-thundering-herd|A cache stampede is a thundering herd]]
- [[concepts/caching/request-collapsing-dedups-inflight-misses|Request collapsing dedups in-flight misses]]
- [[concepts/simulation/chaos-experiments-need-a-steady-state-first|A chaos experiment means nothing without a steady state first]]

## Related modules
- [[m08-traits|M08 - Traits]]

## Related problems
- [[p03-global-leaderboard|P03 - Leaderboard]]

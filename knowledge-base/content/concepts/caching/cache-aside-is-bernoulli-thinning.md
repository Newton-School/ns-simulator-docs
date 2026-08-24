---
title: "Cache-aside is Bernoulli thinning"
cluster: caching
tags: [concept, caching]
---
A cache hit is served locally with probability hitRate; a miss continues downstream.
The engine never models the cache's contents - only which backend the request routes
to. That thinning is exactly what the metric depends on: how much load reaches the
store.

**Seen in:** [[p03-global-leaderboard|Problem 3 - Leaderboard]] · [[p11-celebrity-upload|Problem 11 - Celebrity Upload]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Spec:** [[trait-integration-guide|trait-integration-guide.md]]

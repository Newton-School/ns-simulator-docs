---
title: "Cache-aside is Bernoulli thinning"
cluster: caching
tags: [concept, caching]
---
A cache hit is served locally with probability hitRate; a miss continues downstream.
With the default declared hit rate, the engine doesn't model the cache's contents - only
which backend the request routes to. The opt-in derived-LRU model does track keys (a
size-limited LRU on each request's key), so the hit rate is measured from the traffic.
Either way the cache thins the stream, and that is what the metric depends on: how much
load reaches the store.

**Seen in:** [[p03-global-leaderboard|Problem 3 - Leaderboard]] · [[p11-celebrity-upload|Problem 11 - Celebrity Upload]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Spec:** [[derived-cache-hit-rate-model|derived-cache-hit-rate-model.md]]
**Map:** [[maps/architecture-patterns|Architecture Patterns]] · [[maps/distributed-systems|Distributed Systems]]

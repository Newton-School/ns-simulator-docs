---
title: "A cache stampede is a thundering herd on a cold key"
cluster: caching
tags: [concept, caching]
---
When a hot key expires (or a cold start), every concurrent miss forwards to the store
at once - a thundering herd that can overwhelm the DB the cache was meant to protect.
The simulator reproduces it two ways: a key that stays cold (declared hit rate 0, or the
chaos `cache-flush` fault), and the derived LRU cache, which fills a key only when its fetch
returns, so every miss that arrives before then also goes to the store.

**Because:** [[caching/cache-aside-is-bernoulli-thinning|Cache-aside is Bernoulli thinning]]
**Leads to:** [[caching/request-collapsing-dedups-inflight-misses|Request collapsing dedups in-flight misses]]
**Seen in:** [[p11-celebrity-upload|Problem 11 - Celebrity Upload]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Map:** [[maps/distributed-systems|Distributed Systems]]

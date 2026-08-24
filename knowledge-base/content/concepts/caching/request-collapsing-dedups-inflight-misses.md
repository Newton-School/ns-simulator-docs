---
title: "Request collapsing dedups in-flight misses"
cluster: caching
tags: [concept, caching, pattern]
---
Request collapsing (single-flight) lets only the first miss for a key hit the store;
concurrent misses wait for that one result. It converts a stampede of N misses into 1
downstream call - the survival trait for a viral cold key.

**Because:** [[caching/cache-stampede-is-a-thundering-herd|A cache stampede is a thundering herd]]
**Seen in:** [[p11-celebrity-upload|Problem 11 - Celebrity Upload]]
**Taught in:** [[m08-traits|M08 - Traits]]

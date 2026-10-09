---
title: "Request collapsing dedups in-flight misses"
cluster: caching
tags: [concept, caching, pattern]
---
Request collapsing (single-flight) lets only the first miss for a key hit the store;
concurrent misses wait for that one result. It converts a stampede of N misses into 1
downstream call - the survival trait for a viral cold key. It does not raise the hit rate; it
removes duplicate miss traffic.

**In the simulator:** opt-in per cache node (Request collapsing in the Caching section, on
cdn, in-memory-cache and reverse-proxy). Followers park at the cache without a worker or
queue slot, complete when the leader's fetch returns (their latency includes the wait), and
fail with the leader's cause if it fails. It groups only requests that carry a key (a keyspace
on the source) and applies in discrete-event runs only. Not modelled: a cap on waiters per
key, lock timeouts that let waiters fall through, stale-while-revalidate.

**Because:** [[caching/cache-stampede-is-a-thundering-herd|A cache stampede is a thundering herd]]
**Seen in:** [[p11-celebrity-upload|Problem 11 - Celebrity Upload]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Spec:** [[derived-cache-hit-rate-model|derived-cache-hit-rate-model.md]]
**Map:** [[maps/distributed-systems|Distributed Systems]]

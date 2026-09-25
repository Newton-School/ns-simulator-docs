---
title: "Distributed Systems"
type: moc
tags: [moc]
---
> Caching, replication, locks, consistency, CQRS, queues, fanout.

## Caching
- [[concepts/caching/cache-aside-is-bernoulli-thinning|Cache-aside is Bernoulli thinning]]
- cache stampede → request collapsing - see [[p11-celebrity-upload|P11]]
## Storage & consistency
- row locks · contention · replication · CQRS - see [[p10-geospatial|P10]], [[p12-ps5-restock|P12]]
- [[concepts/storage/quorum-writes-trade-latency-for-durability|Quorum writes trade latency for durability]]
## Messaging & fanout
- queues · brokers · fanout - see [[p13-taylor-swift-news-feed|P13]]
- [[concepts/workloads/consumer-groups-deliver-once-per-group|A stream delivers each message once per consumer group]]
## State machines & runtime evidence (V2)
- [[concepts/simulation/state-machines-make-behavior-gradeable|State machines make behavior gradeable]]
- [[concepts/grading/runtime-state-transitions-grade-modeled-correctness|Runtime state-transition criteria grade modelled correctness]]
- walkthrough: [[replication-quorum-state-machine-walkthrough|Replication quorum state-machine trace]]
## Problems
- [[p03-global-leaderboard|P03]] · [[p08-flash-sale|P08]] · [[p11-celebrity-upload|P11]] · [[p12-ps5-restock|P12]] · [[p13-taylor-swift-news-feed|P13]]

## More notes in this map

- [[concepts/caching/cache-stampede-is-a-thundering-herd|A cache stampede is a thundering herd on a cold key]]
- [[concepts/caching/request-collapsing-dedups-inflight-misses|Request collapsing dedups in-flight misses]]
- [[concepts/storage/cqrs-splits-read-and-write-paths|CQRS splits read and write paths]]
- [[concepts/storage/replication-scales-reads-not-writes|Replication scales reads, not writes]]
- [[concepts/storage/row-locks-serialize-writes|A row lock serializes writes and pins effective concurrency to 1]]
- [[concepts/workloads/celebrity-workload-breaks-fanout-on-write|A celebrity workload breaks pure fanout-on-write]]
- [[concepts/workloads/fanout-on-write-vs-on-read|Fanout-on-write trades write cost for read speed]]

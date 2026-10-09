---
title: "Per-entity order survives only with keyed, ordered consumers"
cluster: workloads
tags: [concept, workloads]
---
A change stream keeps order per partition, not globally. Two changes to the same entity
can still be applied out of order if consumers process them in parallel, or if the partition
key is not the entity key. Partitioning by the entity and consuming per key (or per
partition) fixes it, at a throughput cost: a later change waits until the earlier one is done.
The simulator counts out-of-order applies (`changeOrderViolations`) and measures the wait.

**Because:** [[workloads/consumer-groups-deliver-once-per-group|A stream delivers each message once per consumer group]]
**Spec:** [[node-capability-matrix|node-capability-matrix.md]]
**Map:** [[maps/distributed-systems|Distributed Systems]]

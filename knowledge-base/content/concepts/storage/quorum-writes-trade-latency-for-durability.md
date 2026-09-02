---
title: "Quorum writes trade latency for durability"
cluster: storage
tags: [concept, storage]
---
A replicated store can acknowledge a write after just the primary (fast, but a single
failure loses it) or after a quorum of replicas (slower, but survives a node loss). The
replication capability models this: a quorum write waits for `floor(n/2)+1` healthy
replicas, deterministic leader promotion covers a failed leader, and a design with too few
replicas records `quorum-unavailable` under an injected failure. So "add replication"
stops being cosmetic - under-replicating fails a runtime check, and stronger durability
visibly costs write latency.

**Because:** [[concepts/storage/replication-scales-reads-not-writes]]
**Leads to:** [[concepts/grading/runtime-state-transitions-grade-modeled-correctness]]
**Seen in:** [[p12-ps5-restock|Problem 12 - PS5 Restock]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Spec:** [[replication-quorum-state-machine-walkthrough|replication-quorum-state-machine-walkthrough.md]]

---
title: "Read-your-writes costs a catch-up wait on replica reads"
cluster: storage
tags: [concept, storage]
---
A follower applies each write some time after the leader commits it (the replication
lag). Under eventual consistency a follower read answers at once with whatever it has, which
may be older than the client's own write. Read-your-writes makes the read wait until the
follower has applied that client's latest write; strong waits for the newest committed
write. The wait is the price of the guarantee: it adds read latency and holds a worker while
it waits. The simulator measures it (`consistency.catchUpWaitMs`) instead of declaring it.

**Because:** [[storage/replication-scales-reads-not-writes|Replication scales reads, not writes]]
**Contrast:** [[storage/eventual-consistency-makes-stale-reads-countable|Eventual consistency makes stale reads countable]]
**Leads to:** [[storage/quorum-writes-trade-latency-for-durability|Quorum writes trade latency for durability]]
**Spec:** [[support-ledger-and-runtime-semantics|support-ledger-and-runtime-semantics.md]]
**Map:** [[maps/distributed-systems|Distributed Systems]]

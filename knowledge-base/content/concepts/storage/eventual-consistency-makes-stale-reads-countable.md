---
title: "Eventual consistency makes stale reads countable"
cluster: storage
tags: [concept, storage]
---
With per-key data versions recorded, a stale read is a fact, not a guess: the read
returned an older version than the newest committed one. So the cost of choosing eventual
consistency can be counted (`consistency.staleReads`), as can broken session guarantees
(`consistency.readYourWritesViolations`, `consistency.monotonicReadViolations`). A bounded
single-key linearizability check runs over the same history, and whatever falls outside its
bound is reported as not checked, never as passed. Stale reads under eventual are the
expected trade-off; the health check warns only when a node breaks the guarantee its own
model promises.

**Because:** [[storage/read-your-writes-costs-a-catch-up-wait-on-replica-reads|Read-your-writes costs a catch-up wait on replica reads]]
**Leads to:** [[grading/runtime-state-transitions-grade-modeled-correctness|Runtime state-transition criteria grade modelled correctness]]
**Spec:** [[system-design-coverage-gaps|system-design-coverage-gaps.md]]
**Map:** [[maps/distributed-systems|Distributed Systems]]

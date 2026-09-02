---
title: "A stream delivers each message once per consumer group"
cluster: workloads
tags: [concept, workloads]
---
A partitioned stream broker is not a queue and not a broadcast: every consumer group gets
its own copy of each message, but within a group exactly one consumer handles it. The
stream capability models this - deterministic partition assignment, one delivery per
configured group, per-group offset commits, retention expiry, replay from a committed
offset, and rebalancing. That makes the classic mistakes gradeable: using a queue (one
consumer total) where fan-out to N independent groups was needed, or losing messages past
the retention window.

**Because:** [[concepts/workloads/fanout-on-write-vs-on-read]]
**Leads to:** [[concepts/grading/runtime-state-transitions-grade-modeled-correctness]]
**Seen in:** [[p13-taylor-swift-news-feed|Problem 13 - News Feed]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Spec:** [[support-ledger-and-runtime-semantics|support-ledger-and-runtime-semantics.md]]

---
title: "Producer batching trades latency for throughput"
cluster: network
tags: [concept, network]
---
A Kafka producer holds records until the batch reaches `batch.size` bytes or `linger.ms`
has passed since the first record, then sends the batch as one request. One request means one
in-flight slot, one protocol overhead and one trip for many records, so under the same
in-flight cap a batched edge carries records an unbatched one refuses. The price is that
every record waits for its batch. In the simulator this is opt-in on Kafka edges
(`edge.batching`) and the wait is measured as **batch wait**.

**Because:** [[network/edge-concurrency-caps-inflight-requests|Edge maxConcurrentRequests caps in-flight requests]]
**Taught in:** [[m07-edges|M07 - Edges]]
**Spec:** [[edge-properties-and-defaults|edge-properties-and-defaults.md]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

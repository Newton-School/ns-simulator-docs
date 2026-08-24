---
title: "A row lock serializes writes and pins effective concurrency to 1"
cluster: storage
tags: [concept, storage]
---
A contended row lock forces writes to the same key to run one-at-a-time. Effective
concurrency on that hot key becomes 1, so adding hardware does nothing - the fix is
architectural (queue/serialize, shard the key, or reserve).

**Related:** [[compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]
**Seen in:** [[p12-ps5-restock|Problem 12 - PS5 Restock]] · [[p08-flash-sale|Problem 8 - Flash Sale]]
**Taught in:** [[m05-instance-model|M05 - Instance Model]]

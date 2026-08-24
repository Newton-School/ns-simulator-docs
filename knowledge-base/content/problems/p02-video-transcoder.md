---
title: "Problem 2 - Video Transcoder"
type: problem
cluster: CPU + concurrency + scaling
tags: [problem]
---
**Purpose:** vertical scaling multiplies effectiveC and crushes latency; toggling a
worker to cpu-bound proves multiplexing can't help heavy compute.

## Teaches (concepts)
- [[concepts/compute/derive-and-lock-prices-concurrency|Derive-and-lock prices concurrency]]
- [[concepts/compute/cpu-bound-is-one-worker-per-vcpu|CPU-bound gets one worker per vCPU]]
- [[concepts/compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]

## Related modules
- [[m05-instance-model|M05 - Instance Model]] · [[m06-execution-profiles|M06 - Execution Profiles]]

## Related problems
- [[p12-ps5-restock|P12 - PS5 Restock]] (where scaling stops working)

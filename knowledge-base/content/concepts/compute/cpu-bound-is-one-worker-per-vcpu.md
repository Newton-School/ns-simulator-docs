---
title: "CPU-bound work gets one worker per vCPU"
cluster: compute
tags: [concept, compute]
---
A cpu-bound node occupies the core while computing, so real parallelism is ~1 worker
per vCPU. Claiming more workers just time-slices the cores (contention), it does not
add throughput. A c5.large (2 vCPU) cpu-bound node has 2 servers.

**Contrast:** [[compute/io-bound-multiplexes-many-per-vcpu|IO-bound multiplexes many per vCPU]]
**Because:** [[compute/derive-and-lock-prices-concurrency|Derive-and-lock prices concurrency]]
**Seen in:** [[p02-video-transcoder|Problem 2 - Video Transcoder]]
**Taught in:** [[m06-execution-profiles|M06 - Execution Profiles]]
**Spec:** [[execution-profile-and-node-concurrency|execution-profile-and-node-concurrency.md]]

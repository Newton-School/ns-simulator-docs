---
title: "IO-bound work multiplexes many requests per vCPU"
cluster: compute
tags: [concept, compute]
---
An io-bound node (DB, cache, LB, broker) mostly waits on disk/network, so one core
juggles many concurrent in-flight requests - 32 per vCPU here. That is why a datastore
shows 64-128 "workers/connections" while a compute service shows 2.

**Contrast:** [[compute/cpu-bound-is-one-worker-per-vcpu|CPU-bound gets one worker per vCPU]]
**Taught in:** [[m06-execution-profiles|M06 - Execution Profiles]]
**Spec:** [[execution-profile-and-node-concurrency|execution-profile-and-node-concurrency.md]]

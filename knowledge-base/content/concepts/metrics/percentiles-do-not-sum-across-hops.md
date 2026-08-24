---
title: "Latency percentiles do not sum across hops"
cluster: metrics
tags: [concept, metrics]
---
You cannot add per-node p99s to get end-to-end p99 - the tail of a sum is not the sum
of tails. End-to-end percentiles are measured over whole-request latencies, per
post-warmup window.

**Because:** [[metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]
**Taught in:** [[m10-metrics-honesty|M10 - Metrics & Honesty]]

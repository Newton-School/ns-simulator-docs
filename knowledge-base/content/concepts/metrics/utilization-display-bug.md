---
title: "The utilization-display bug (fixed)"
cluster: metrics
tags: [concept, metrics, fixed-bug]
---
Fixed bug, kept as a lesson: a saturated node used to *report* low utilization while
queueing heavily, because the util denominator used a different worker count than the
scheduler's derived c. Each node now integrates busy worker time and available worker
time over the same worker count (CPU-heavy nodes also track core usage and report the
higher of the two), and the node badge combines utilization, queue depth and error rate.
What stays true: utilization is an average over the run, so a node at moderate
utilization can still fail p99 during bursts. Read it together with queue depth and p99.

**Because:** [[metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]
**Taught in:** [[m03-queueing-model|M03]] · [[m10-metrics-honesty|M10]]
**Map:** [[maps/performance|Performance Engineering]]

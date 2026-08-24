---
title: "Queue depth is a leading indicator of latency"
cluster: queueing
tags: [concept, queueing]
---
Rising queue depth predicts a p99 spike before it shows in average latency. It is the
earliest honest signal that a node is becoming the bottleneck.

**Because:** [[queueing/queue-saturation-precedes-cpu-saturation|Queue saturation precedes CPU saturation]]
**Related:** [[metrics/utilization-display-bug|The utilization-display bug]]
**Taught in:** [[m03-queueing-model|M03 - Queueing Model]]

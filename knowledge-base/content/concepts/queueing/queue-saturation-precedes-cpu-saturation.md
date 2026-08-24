---
title: "Queue saturation precedes CPU saturation"
cluster: queueing
tags: [concept, queueing, latency]
---
A finite-server queue saturates - latency explodes - while CPU utilization can still
look low, because requests pile in the buffer, not on the cores. Watch queue depth,
not CPU, to see trouble first.

**Because:** [[queueing/ggck-models-finite-capacity-queues|G/G/c/K models finite-capacity queues]]
**Leads to:** [[queueing/queue-depth-is-a-leading-indicator-of-latency|Queue depth is a leading indicator of latency]]
**Seen in:** [[p05-live-voting|Problem 5 - Live Voting]]
**Taught in:** [[m03-queueing-model|M03 - Queueing Model]]

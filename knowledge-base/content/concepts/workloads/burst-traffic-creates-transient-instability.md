---
title: "Burst traffic creates transient queue instability"
cluster: workloads
tags: [concept, workloads, queueing]
---
A short, intense burst pushes arrival rate far above service rate, so the queue grows
faster than it drains and latency spikes - even if the long-run average is well within
capacity. Steady-state math alone misses it.

**Leads to:** [[concepts/queueing/queue-depth-is-a-leading-indicator-of-latency|Queue depth is a leading indicator of latency]]
**Seen in:** [[p05-live-voting|Problem 5 - Live Voting]]
**Taught in:** [[m11-workload-scale|M11 - Workload & Scale]] · [[m03-queueing-model|M03 - Queueing]]

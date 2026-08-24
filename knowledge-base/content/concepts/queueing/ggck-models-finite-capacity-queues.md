---
title: "G/G/c/K models finite-capacity queues"
cluster: queueing
tags: [concept, queueing]
---
Each node is a G/G/c/K station: general arrivals, general service, c parallel
servers, and a finite system capacity K (in-service + waiting) beyond which requests
are rejected. This is why capacity is a hard wall, not a soft slowdown.

**Leads to:** [[queueing/queue-saturation-precedes-cpu-saturation|Queue saturation precedes CPU saturation]]
**Seen in:** [[p05-live-voting|Problem 5 - Live Voting]]
**Taught in:** [[m03-queueing-model|M03 - Queueing Model]]
**Spec:** [[queue-depth-calculation|queue-depth-calculation.md]]

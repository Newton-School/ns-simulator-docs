---
title: "M03 - The Queueing Model (G/G/c/K)"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
After this module you can explain why a node with spare CPU can still collapse under
load, read queue depth as the first sign of trouble, and compute utilization the
honest way.

## Concepts (atomic notes)
- [[concepts/queueing/ggck-models-finite-capacity-queues|G/G/c/K models finite-capacity queues]]
- [[concepts/queueing/queue-saturation-precedes-cpu-saturation|Queue saturation precedes CPU saturation]]
- [[concepts/queueing/queue-depth-is-a-leading-indicator-of-latency|Queue depth is a leading indicator of latency]]
- [[concepts/metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]

## Teaching vehicle
[[p05-live-voting|Problem 5 - Reality TV Live Voting]] - inject a 60s burst of votes,
watch queue depth explode while CPU stays low.

## Source of truth (specs)
- [[queue-depth-calculation|queue-depth-calculation.md]] · [[throughput-calculation|throughput-calculation.md]]
- Code: `src/engine/nodes/GGcKNode.ts`

## Demo
Push a single node past its server count; watch queue depth, wait time, and
rejections rise together while the p50 stays flat and the p99 explodes.

## Exercise
Given `c = 2` servers and 3.6 ms service, find the RPS at which p99 crosses 100 ms.
Verify against a headless run.

## ⚠️ Known gaps
- [[concepts/metrics/utilization-display-bug|The utilization-display bug]] - a
  saturated node can read "HEALTHY". Trust p99 + queue depth.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m02-request-lifecycle|M02]] · Next [[m04-nodes-service-time|M04]]

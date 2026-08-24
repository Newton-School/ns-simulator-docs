---
title: "Effective concurrency determines service capacity"
cluster: compute
tags: [concept, compute]
---
A node's throughput ceiling is effectiveC / service-time. effectiveC is derived from
the instance (vCPU x count x workers-per-vCPU), not typed by hand - so buying
capacity costs money and is capped.

**Leads to:** [[queueing/queue-saturation-precedes-cpu-saturation|Queue saturation precedes CPU saturation]]
**Seen in:** [[p02-video-transcoder|Problem 2 - Video Transcoder]]
**Taught in:** [[m05-instance-model|M05 - Instance Model]]
**Spec:** [[resource-allocation-and-derived-concurrency|resource-allocation-and-derived-concurrency.md]]

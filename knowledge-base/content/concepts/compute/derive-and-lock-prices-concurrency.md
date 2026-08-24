---
title: "Derive-and-lock makes concurrency cost money"
cluster: compute
tags: [concept, compute, anti-gaming]
---
You cannot type a free worker count. Concurrency is derived from a priced, capped
instance catalog (vCPU x count x workers-per-vCPU). So "more capacity" costs money and
hits quotas - which turns scaling into a real, un-gameable tradeoff.

**Leads to:** [[compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]
**Seen in:** [[p02-video-transcoder|Problem 2 - Video Transcoder]] · [[p12-ps5-restock|Problem 12 - PS5 Restock]]
**Taught in:** [[m05-instance-model|M05 - Instance Model]]

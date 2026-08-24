---
title: "M05 - Instance Model & Derived Concurrency"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Explain derive-and-lock: you pick an instance + count, and concurrency, admission,
speed, and cost all follow - you cannot type a free worker number.

## Concepts (atomic notes)
- [[concepts/compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]

## Teaching vehicle
[[p02-video-transcoder|Problem 2 - Video Transcoder]] - vertical scaling multiplies
effectiveC and crushes latency; [[p12-ps5-restock|Problem 12 - PS5 Restock]] shows a
row-lock pinning effectiveC to 1 so hardware scaling stops helping.

## Source of truth (specs)
- [[resource-allocation-and-derived-concurrency|resource-allocation-and-derived-concurrency.md]]
- Code: `instanceCatalog.ts`, `resourceDefaults.ts`, `resourceDerivation.ts`

## Demo
Scale url-shortener's API Server c5.large x1 → x4 → p99 156 ms → 21 ms.

## Exercise
Pick the smallest/cheapest instance+count that keeps p99 under 100 ms at the graded peak.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m04-nodes-service-time|M04]] · Next [[m06-execution-profiles|M06]]

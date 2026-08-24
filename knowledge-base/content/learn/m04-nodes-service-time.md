---
title: "M04 - Nodes, Component Types & Service Time"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Explain component types/categories and how a node's service-time distribution sets its
latency floor before any load.

## Concepts (atomic notes)
- [[concepts/storage/replication-scales-reads-not-writes|Replication scales reads, not writes]]

## Key ideas
- `processing.distribution`: constant vs exponential; exp p99 ~= 4.6x mean.
- Per-type default means (`TYPE_MEAN_SERVICE_MS`), category floors.
- Palette seeding (`buildSeededSimulationConfig`, `paletteTemplates.ts`).

## Teaching vehicle
[[p09-search-autocomplete|Problem 9 - Search Autocomplete]] - contrast a relational DB
vs an in-memory trie for micro-latency lookups.

## Source of truth (specs)
- [[node-capability-matrix|node-capability-matrix.md]] · Code: `src/engine/catalog/componentSpecs.ts`

## Demo
Constant vs exponential latency → the p99 gap at zero load. ## Exercise: predict a path's p99 from per-hop means.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m03-queueing-model|M03]] · Next [[m05-instance-model|M05]]

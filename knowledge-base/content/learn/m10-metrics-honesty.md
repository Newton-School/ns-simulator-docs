---
title: "M10 - Metrics, Aggregation & the Honesty Doctrine"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Read the metric surfaces and explain why every number is a time-weighted, provenance-
bearing figure - not a snapshot.

## Concepts (atomic notes)
- [[concepts/metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]
- [[concepts/metrics/percentiles-do-not-sum-across-hops|Percentiles do not sum across hops]]
- [[concepts/metrics/utilization-display-bug|The utilization-display bug]]
- [[concepts/storage/cqrs-splits-read-and-write-paths|CQRS splits read and write paths]]

## Teaching vehicle
[[p10-geospatial|P10 - Uber/Swiggy Geospatial]] - a snapshot average hides write-window
p99 spikes that the time-weighted integral exposes → CQRS.

## Source of truth (specs)
- [[simulation-validation-and-pattern-accuracy|simulation-validation-and-pattern-accuracy.md]] · Code: `metrics.ts`, `analysis/output.ts`

## Demo
Read the simulation tray (Overview / Bottlenecks / Node Metrics / Traffic) for url-shortener.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m09-cost-model|M09]] · Next [[m11-workload-scale|M11]]

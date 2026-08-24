---
title: "CQRS splits read and write paths"
cluster: storage
tags: [concept, storage, pattern]
---
When one store serves mixed read/write load, write-heavy windows spike p99 for reads.
CQRS (Command Query Responsibility Segregation) separates the write model from a
read-optimized view so each scales independently.

**Because:** [[metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]
**Seen in:** [[p10-geospatial|Problem 10 - Geospatial]]
**Taught in:** [[m10-metrics-honesty|M10 - Metrics & Honesty]]

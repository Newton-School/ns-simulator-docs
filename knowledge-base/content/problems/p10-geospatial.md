---
title: "Problem 10 - Uber/Swiggy Geospatial"
type: problem
cluster: Metrics + aggregation + CQRS
tags: [problem]
---
**Purpose:** a mixed read/write load on one DB - a snapshot average hides the problem
while the time-weighted integral exposes write-window p99 spikes, motivating CQRS.

## Teaches (concepts)
- [[concepts/metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]
- [[concepts/storage/cqrs-splits-read-and-write-paths|CQRS splits read and write paths]]

## Related modules
- [[m10-metrics-honesty|M10 - Metrics & Honesty]]

## Related problems
- [[p13-taylor-swift-news-feed|P13 - News Feed]]

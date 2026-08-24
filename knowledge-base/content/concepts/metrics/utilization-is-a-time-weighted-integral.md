---
title: "Utilization is a time-weighted integral"
cluster: metrics
tags: [concept, metrics, honesty]
---
Utilization is the busy-area integral over the run divided by (c x duration), not a
point sample. A snapshot can read a lucky 20% during a saturated window; the integral
cannot lie about how busy the node truly was.

**Leads to:** [[metrics/utilization-display-bug|The utilization-display bug]]
**Seen in:** [[p10-geospatial|Problem 10 - Geospatial]]
**Taught in:** [[m10-metrics-honesty|M10 - Metrics & Honesty]]

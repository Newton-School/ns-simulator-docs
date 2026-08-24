---
title: "The utilization-display bug"
cluster: metrics
tags: [concept, metrics, known-gap]
---
Known gap: a saturated node can currently *report* low utilization while queueing
heavily, because the util denominator uses a different worker count than the
scheduler's derived c. Trust p99 and queue depth over the "HEALTHY" badge. This is
why the url-shortener API Server fails p99 while looking healthy.

**Because:** [[metrics/utilization-is-a-time-weighted-integral|Utilization is a time-weighted integral]]
**Taught in:** [[m03-queueing-model|M03]] · [[m10-metrics-honesty|M10]]

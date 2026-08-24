---
title: "Warmup removes transient behavior"
cluster: simulation
tags: [concept, simulation]
---
A fresh run starts with empty queues (the transient). Metrics gathered then are not
representative, so the warmup window is excluded from the graded window - only the
steady state is measured.

**Because:** [[simulation/discrete-event-simulation-advances-time-through-events|DES advances time through events]]
**Leads to:** [[simulation/steady-state-differs-from-transient|Steady-state differs from transient]]
**Seen in:** [[p04-iot-ingestion|Problem 4 - IoT Ingestion]]
**Taught in:** [[m01-discrete-event-simulation|M01 - DES Core]]

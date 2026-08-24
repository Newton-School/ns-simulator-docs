---
title: "Discrete-event simulation advances time through events"
cluster: simulation
tags: [concept, simulation]
---
The engine holds a priority queue of events ordered by *simulated* time. The clock
jumps to the next scheduled event - it never ticks in real time. Between two events,
nothing changes, so a 30-second run costs only as much compute as it has events.

**Leads to:** [[simulation/warmup-removes-transient-behavior|Warmup removes transient behavior]]
**Seen in:** [[p04-iot-ingestion|Problem 4 - IoT Ingestion]]
**Taught in:** [[m01-discrete-event-simulation|M01 - DES Core]]
**Spec:** [[arrival-departure-and-request-lifecycle-semantics|arrival-departure-and-request-lifecycle-semantics.md]]

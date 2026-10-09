---
title: "Telemetry sinks drop events instead of failing requests"
cluster: metrics
tags: [concept, metrics]
---
Exporters send logs, metrics and traces asynchronously, so when a collector falls
behind it loses events rather than slowing or failing the application. That loss is silent
to the caller: no error, just missing data. The simulator models it as an opt-in on collector
nodes: events past an ingest ceiling or a full buffer are dropped and counted
(`telemetryDropped`), and head sampling keeps unexported events away. Lower sampling buys
headroom at the price of visibility.

**Contrast:** [[simulation/closed-terminal-taxonomy-enables-honest-errors|A closed terminal taxonomy enables honest error accounting]]
**Spec:** [[node-capability-matrix|node-capability-matrix.md]]
**Map:** [[maps/performance|Performance Engineering]]

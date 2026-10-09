---
title: "Connector edges carry no physics or cost"
cluster: network
tags: [concept, network]
---
Under edgeModel=connector, edges are dumb wires: zero latency and zero protocol overhead,
no bandwidth limit, no connection model or batching, no egress cost, no properties panel. The
protocol is kept for routing and grading only. They express topology only - the "focus on the HLD,
not edge tuning" mode used in graded assignments.

**Contrast:** [[network/latency-is-dominated-by-path-type|Edge latency is dominated by path type]]
**Taught in:** [[m07-edges|M07 - Edges]] · [[m13-environment-profiles|M13 - Environment Profiles]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

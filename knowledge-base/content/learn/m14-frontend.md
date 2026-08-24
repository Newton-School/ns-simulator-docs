---
title: "M14 - Frontend Architecture"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Trace a node-config change from the canvas through the store and worker to a lens update.

## Key ideas
- Shell: React + Zustand (`useStore`), canvas (ReactFlow), Web Worker (`useSimulation`), serialization (`useTopologySerializer`).
- Metric lenses: pre-run (Instance/Concurrency/QueueCapacity/Timeout/Cost) vs runtime (Traffic/Saturation/Latency/Errors/Throughput).
- Chrome: properties panel, simulation tray, header (cost chip, mode badge, settings modal), theming.

## Teaching vehicle
[[p05-live-voting|P05 - Live Voting]] - watch the queueing bottleneck animate on the
ReactFlow canvas in real time, bridging the headless engine to the visual layer.

## Source of truth (specs)
- [[canvas-visualization-and-ux-simplification|canvas-visualization-and-ux-simplification.md]] · [[settings-modal-feature-spec|settings-modal-feature-spec.md]]

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m13-environment-profiles|M13]] · Next [[m15-newton-integration|M15]]

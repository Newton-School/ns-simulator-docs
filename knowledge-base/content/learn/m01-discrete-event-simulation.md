---
title: "M01 - Discrete-Event Simulation Core"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Explain how simulated time advances, why a seed makes runs reproducible, and why
warmup is excluded from the graded window.

## Concepts (atomic notes)
- [[concepts/simulation/discrete-event-simulation-advances-time-through-events|DES advances time through events]]
- [[concepts/simulation/warmup-removes-transient-behavior|Warmup removes transient behavior]]
- [[concepts/simulation/steady-state-differs-from-transient|Steady-state differs from transient]]

## Teaching vehicle
[[p04-iot-ingestion|Problem 4 - High-Volume IoT Ingestion]] - a constant-write stream
shows the empty-queue transient settle into steady state.

## Source of truth (specs)
- Code: `src/engine/engine.ts`, `src/engine/core/*`, `global` config
- Determinism: [[why-this-works-math-tricks-and-skeptics-faq|why-this-works-math-tricks-and-skeptics-faq.md §C]]

## Demo
Run cache-placement's reference topology headless; watch events/second and the
warmup cutoff. Re-run with the same seed → identical stats.

## Exercise
Change the seed → identical stats. Change duration → confidence changes.

---
Curriculum map → [[learn/_moc|Modules]] · Next [[m02-request-lifecycle|M02]]

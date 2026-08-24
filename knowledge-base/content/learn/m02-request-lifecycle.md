---
title: "M02 - Request Lifecycle & Terminal Taxonomy"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Trace a request from emission to a single terminal, and read the closed error taxonomy.

## Concepts (atomic notes)
- [[concepts/simulation/closed-terminal-taxonomy-enables-honest-errors|A closed terminal taxonomy enables honest error accounting]]
- [[concepts/network/synchronous-blocking-exhausts-connection-pools|Synchronous blocking exhausts connection pools]]

## Teaching vehicle
[[p06-notification-gateway|Problem 6 - Notification Gateway]] - a slow 3rd-party API
triggers timeout / connection_reset while CPU stays near 1%.

## Source of truth (specs)
- [[arrival-departure-and-request-lifecycle-semantics|arrival-departure-and-request-lifecycle-semantics.md]] · [[request-rejection-behaviour|request-rejection-behaviour.md]]
- Code: `src/engine/core/events.ts`

## Demo
Inject a tiny store; watch requests time out vs OOM. ## Exercise: classify a failure from the metrics.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m01-discrete-event-simulation|M01]] · Next [[m03-queueing-model|M03]]

---
title: "M00 - Orientation & Mental Model"
type: module
duration: 0.5 lecture
tags: [module]
---
## Objectives
Explain what the product is, the three honesty claims it stands on, and where the code
and docs live.

## The big idea
A "LeetCode for system design": you design an *architecture* (nodes/edges/sizing), not
code; the sim runs load over it and grades it. Three claims kept honest:
1. Every reported number is physically derived and shows its provenance.
2. Concurrency and cost are consequences of hardware, not free dials.
3. A question is "authored" only when a good design passes and a gamed one fails.

## Repo map
- `src/engine/*` - headless sim + grading · `src/renderer/*` - React app
- `ns-simulator-docs/specs/*` - the specs · `system-design-simulator-questions/*` - the bank
- Two runtimes: headless engine (Node, tests + grading) vs the browser app (Web Worker runs the *same* engine).

## Where to go next
- Maps: [[maps/simulator-physics|Simulator Physics]] · [[maps/authoring-grading|Authoring & Grading]]
- Curriculum: [[learn/_moc|Modules]] → start at [[m01-discrete-event-simulation|M01]]

---
Curriculum map → [[learn/_moc|Modules]] · Next [[m01-discrete-event-simulation|M01]]

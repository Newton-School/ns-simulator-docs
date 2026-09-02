---
title: "Runtime state-transition criteria grade modelled correctness"
cluster: grading
tags: [concept, grading]
---
Two semantic-criterion kinds - `stateTransition` and `stateSequence` - read the per-request
state timeline the engine records and grade *what actually happened*, not the graph shape.
`stateTransition` counts matching transitions in a range; the absence pattern
(`minCount:0, maxCount:0`) asserts a state must never occur - "reservation `oversold` never
appears" is the no-double-book check. `stateSequence` requires an ordered chain within one
request's timeline. This is how a correctness lesson gets a real runtime signal
(`reservations.oversells`, `rateLimit.breaches`, quorum loss) instead of only prose - but
only for behavior the engine genuinely models.

**Because:** [[concepts/simulation/state-machines-make-behavior-gradeable]]
**Leads to:** [[concepts/grading/performance-correctness-boundary]]
**Seen in:** [[p12-ps5-restock|Problem 12 - PS5 Restock]]
**Taught in:** [[m12-grading-dsl|M12 - Grading DSL]]
**Spec:** [[runtime-semantic-criteria|runtime-semantic-criteria.md]]

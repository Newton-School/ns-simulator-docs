---
title: "State machines make behavior gradeable"
cluster: simulation
tags: [concept, simulation]
---
A state machine models something as always being in exactly one of a small, fixed set of
named states, moving between them only through defined transitions. Each request in the
simulation walks one (generated → admitted → queued → processing → completed / rejected),
and coordination components layer their own (a reservation is committed / sold-out /
oversold; a lock is acquired → held → released or contended). Because the states are a
closed, named set, behavior becomes something you can *assert about* - "state X must never
appear" - which is exactly what turns an un-gradeable correctness property into a
checkable one.

**Because:** [[concepts/simulation/discrete-event-simulation-advances-time-through-events]]
**Leads to:** [[concepts/grading/runtime-state-transitions-grade-modeled-correctness]]
**Seen in:** [[p08-flash-sale|Problem 8 - Flash Sale]]
**Taught in:** [[m08-traits|M08 - Traits]]
**Spec:** [[replication-quorum-state-machine-walkthrough|replication-quorum-state-machine-walkthrough.md]]

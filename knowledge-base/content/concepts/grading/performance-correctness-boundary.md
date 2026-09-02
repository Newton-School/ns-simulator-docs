---
title: "Performance is simulated; correctness is structural (with a growing runtime slice)"
cluster: grading
tags: [concept, grading]
---
The engine grades what queueing physics can decide (latency, throughput, saturation) via
the rubric, and refuses to fake what it cannot. Historically all correctness lived in
topology structure plus a justification. The V2 landing moved a *modelled slice* of
correctness into gradeable runtime state - no-double-book, dedup, lock contention, quorum
availability, rate-limit over-admission - checkable via [[concepts/grading/runtime-state-transitions-grade-modeled-correctness|runtime state-transition criteria]].
The boundary still holds where it matters: exactly-once *coordination*, linearizability,
and strict ordering stay structural + justification. **Never a latency number standing in
for a correctness claim.**

**Because:** [[concepts/simulation/state-machines-make-behavior-gradeable]]
**Leads to:** [[concepts/grading/runtime-state-transitions-grade-modeled-correctness]]
**Seen in:** [[p08-flash-sale|Problem 8 - Flash Sale]]
**Taught in:** [[m12-grading-dsl|M12 - Grading DSL]]
**Spec:** [[support-ledger-and-runtime-semantics|support-ledger-and-runtime-semantics.md]]

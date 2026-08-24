---
title: "Capstone - Author a question end-to-end"
type: module
tags: [module, capstone]
---
## The exercise
Take a fresh problem - e.g. [[p05-live-voting|Live Voting]] or
[[p13-taylor-swift-news-feed|News Feed]] - and ship it as a graded question.

## Steps (ties every module together)
1. Write the prompt + FR/NFR/scale ([[m11-workload-scale|M11]]).
2. Choose the discriminating axes ([[m12-grading-dsl|M12]]).
3. Build the **reference** topology (passes) and the **gamed** topology (fails).
4. Tune the bottleneck via the instance model ([[m05-instance-model|M05]], [[m06-execution-profiles|M06]]).
5. Script `semanticCriteria` so the gamed design is rejected - the
   [[concepts/grading/dual-topology-rule-defines-a-good-question|Dual-Topology Rule]].
6. Validate through the headless engine, then export to Django rows ([[m15-newton-integration|M15]]).

## Done when
Reference PASSES all checks, gamed FAILS on the intended axis, and it validates via
`validate-question-dir`.

---
Curriculum map → [[learn/_moc|Modules]]

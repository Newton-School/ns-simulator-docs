---
title: "M11 - Workload & Scale"
type: module
duration: 0.5 lecture
tags: [module]
---
## Objectives
Explain where load lives, the request mix, and the tractable-vs-display scale trap.

## Concepts (atomic notes)
- [[concepts/workloads/burst-traffic-creates-transient-instability|Burst traffic creates transient instability]]
- [[concepts/workloads/fanout-on-write-vs-on-read|Fanout-on-write vs on-read]]
- [[concepts/workloads/celebrity-workload-breaks-fanout-on-write|Celebrity workload breaks fanout-on-write]]

## Key trap
Dry-run at 100 rps looks fine; the graded peak (~2k) saturates. Size for the stated
peak, not the toy dry-run.

## Teaching vehicle
[[p13-taylor-swift-news-feed|P13 - News Feed]] - a push architecture passes 100 followers,
fails 100M.

## Source of truth (specs)
- [[request-type-model|request-type-model.md]] · [[request-pattern-configuration|request-pattern-configuration.md]]

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m10-metrics-honesty|M10]] · Next [[m12-grading-dsl|M12]]

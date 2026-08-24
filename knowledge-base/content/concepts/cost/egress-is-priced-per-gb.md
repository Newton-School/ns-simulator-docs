---
title: "Egress is priced per GB and can dwarf compute cost"
cluster: cost
tags: [concept, cost]
---
Data leaving a node/edge is billed per GB by path type (cross-zone, cross-region,
internet). A large payload times millions of users can blow a budget even when compute
is nearly free - the classic pivot to an edge CDN.

**Seen in:** [[p01-static-image-board|Problem 1 - Image Board]]
**Taught in:** [[m09-cost-model|M09 - Cost Model]]
**Spec:** [[cost-calculation-and-budgeting|cost-calculation-and-budgeting.md]]

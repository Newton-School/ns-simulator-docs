---
title: "Provisioned cost is instance-hours times a pricing multiplier"
cluster: cost
tags: [concept, cost]
---
A provisioned node costs pricePerHour x instanceCount x pricingMultiplier
(on-demand 1.0 / reserved 0.6 / spot 0.3). Scaling out for concurrency shows up
directly as money - the lever that makes over-provisioning fail the budget axis.

**Because:** [[compute/derive-and-lock-prices-concurrency|Derive-and-lock prices concurrency]]
**Taught in:** [[m09-cost-model|M09 - Cost Model]]

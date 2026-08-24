---
title: "Edge latency is dominated by path type"
cluster: network
tags: [concept, network]
---
An edge's base latency comes from its path type - same-rack, same-dc, cross-zone,
cross-region, internet - inferred from Region/AZ/Subnet placement. A cross-ocean
internet hop can dwarf every node's service time.

**Seen in:** [[p01-static-image-board|Problem 1 - Image Board]]
**Taught in:** [[m07-edges|M07 - Edges]]
**Spec:** [[edge-properties-and-defaults|edge-properties-and-defaults.md]]

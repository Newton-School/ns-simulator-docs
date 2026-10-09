---
title: "A fault domain fails everything placed inside it"
cluster: simulation
tags: [concept, simulation]
---
Replicas only protect you if they do not share a fate. A Region, Availability Zone or
Subnet is a fault domain: when it fails, every component placed inside it fails together, so
two replicas in the same zone are one replica for availability. Surviving a zone outage needs
a replica of every tier in another zone behind a health-aware router that sits outside the
failed zone, and the surviving zone must be sized for the whole load. In the simulator a
fault on a container box fails its members for the window (the AZ outage chaos preset). A
zone that is only slow or lossy is not modelled.

**Because:** [[simulation/chaos-experiments-need-a-steady-state-first|A chaos experiment means nothing without a steady state first]]
**Contrast:** [[network/latency-is-dominated-by-path-type|Edge latency is dominated by path type]] (the same boxes set path type)
**Spec:** [[node-capability-matrix|node-capability-matrix.md]]
**Map:** [[maps/distributed-systems|Distributed Systems]]

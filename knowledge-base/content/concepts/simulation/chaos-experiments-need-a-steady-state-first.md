---
title: "A chaos experiment means nothing without a steady state first"
cluster: simulation
tags: [concept, simulation]
---
A chaos experiment checks a hypothesis: the system holds its steady state (error rate,
p99, throughput) while a fault happens. If the steady state did not hold before the fault, a
failure afterwards proves nothing. So the simulator's experiments measure a baseline window
first and stop with "not stable" if it fails; only then do the inject, restore and traffic
steps run, each verify step checks its own time window, and a final check confirms recovery.
An experiment is compiled into ordinary scheduled faults, so it is deterministic and runs the
same in the app and headless.

**Because:** [[simulation/steady-state-differs-from-transient|Steady-state behavior differs from transient behavior]]
**Leads to:** [[simulation/a-fault-domain-fails-everything-inside-it|A fault domain fails everything placed inside it]]
**Seen in:** [[p11-celebrity-upload|Problem 11 - Celebrity Upload]] (the cache-stampede preset)
**Map:** [[maps/distributed-systems|Distributed Systems]]

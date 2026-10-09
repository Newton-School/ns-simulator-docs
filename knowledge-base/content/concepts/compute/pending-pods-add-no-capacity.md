---
title: "Pending pods add no capacity"
cluster: compute
tags: [concept, compute]
---
On a cluster, asking for more replicas is not the same as getting them. A pod must fit
on a machine with enough free vCPU and RAM; one that fits nowhere stays pending and serves
nothing. So an autoscaler on a full cluster raises the desired count while capacity stays
flat, and fragmentation can strand resources. When a machine fails, its pods stop at once
but come back only after failure detection and eviction (Kubernetes defaults to minutes), and
then still need room and startup time. The simulator models this on the Kubernetes Cluster
node.

**Because:** [[compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]
**Contrast:** [[compute/derive-and-lock-prices-concurrency|Derive-and-lock makes concurrency cost money]]
**Spec:** [[node-capability-matrix|node-capability-matrix.md]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

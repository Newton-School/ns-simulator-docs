---
title: "Problem 13 - Taylor Swift News Feed"
type: problem
cluster: Workload + fanout + scale
tags: [problem]
---
**Purpose:** a push (fanout-on-write) architecture passes the standard workload but the
celebrity workload (100M followers) saturates workers - motivating a hybrid.

## Teaches (concepts)
- [[concepts/workloads/fanout-on-write-vs-on-read|Fanout-on-write vs on-read]]
- [[concepts/workloads/celebrity-workload-breaks-fanout-on-write|Celebrity workload breaks fanout-on-write]]

## Related modules
- [[m11-workload-scale|M11 - Workload & Scale]]

## Related problems
- [[p04-iot-ingestion|P04 - IoT Ingestion]] · [[p05-live-voting|P05 - Live Voting]]

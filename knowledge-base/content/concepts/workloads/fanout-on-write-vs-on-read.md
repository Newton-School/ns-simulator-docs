---
title: "Fanout-on-write trades write cost for read speed"
cluster: workloads
tags: [concept, workloads]
---
Fanout-on-write pushes each post into every follower's timeline (fast reads, expensive
writes). Fanout-on-read assembles the timeline at read time (cheap writes, slow reads).
The right choice depends on the read/write ratio and follower counts.

**Leads to:** [[workloads/celebrity-workload-breaks-fanout-on-write|Celebrity workload breaks fanout-on-write]]
**Seen in:** [[p13-taylor-swift-news-feed|Problem 13 - News Feed]]
**Taught in:** [[m11-workload-scale|M11 - Workload & Scale]]

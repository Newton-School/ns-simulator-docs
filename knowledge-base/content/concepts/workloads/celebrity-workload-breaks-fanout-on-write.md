---
title: "A celebrity workload breaks pure fanout-on-write"
cluster: workloads
tags: [concept, workloads]
---
A pure push architecture passes the standard workload (100 followers) but a celebrity
(100M followers) makes one write fan out to 100M timelines, saturating workers. The fix
is a hybrid: push for the many, pull for the few celebrities.

**Because:** [[workloads/fanout-on-write-vs-on-read|Fanout-on-write vs on-read]]
**Seen in:** [[p13-taylor-swift-news-feed|Problem 13 - News Feed]]
**Taught in:** [[m11-workload-scale|M11 - Workload & Scale]]

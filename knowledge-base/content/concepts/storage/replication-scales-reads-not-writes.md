---
title: "Replication scales reads, not writes"
cluster: storage
tags: [concept, storage]
---
Read replicas multiply read capacity but every write still lands on the primary. A
read-heavy service can add replicas; a write-heavy one must shard or change the store.

**Related:** [[storage/cqrs-splits-read-and-write-paths|CQRS splits read and write paths]]
**Taught in:** [[m04-nodes-service-time|M04 - Nodes & Service Time]]

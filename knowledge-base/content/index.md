---
title: "Simulator Knowledge Base"
---

A place to **read and learn** how the NS-Simulator works, from the discrete-event core
to authored, graded questions. Three ways in: start with a **map** (a topic hub),
follow the **curriculum** in order, or explore by **problem**.

> [!tip] New here?
> Read [[meta/how-this-vault-works|how this vault is organized]] (2 min), then pick a
> learning path below. Contributing a note? Start from [[meta/templates/concept|a template]].

## Start with a map (MOC)

| Map | Covers |
|-----|--------|
| [[maps/simulator-physics\|Simulator Physics]] | time, queues, compute, network, cost |
| [[maps/distributed-systems\|Distributed Systems]] | caching, replication, locks, CQRS, fanout |
| [[maps/performance\|Performance Engineering]] | latency, throughput, utilization, p99 |
| [[maps/architecture-patterns\|Architecture Patterns]] | CDN, cache-aside, request collapsing, scaling |
| [[maps/authoring-grading\|Authoring & Grading]] | the DSL, anti-gaming, honesty doctrine |

## Follow the curriculum

The full path is [[learn/_moc|Modules M00 to M15 + Capstone]]. Three tracks:

| Track | Modules | Time |
|-------|---------|------|
| **Engineers (full)** | M00-M15 + capstone | ~2.5 days |
| **Content authors (fast)** | M00, M04-M06, M08, M09, M11-M13, M15, capstone | ~1 day |
| **Product / PM overview** | M00, M05-M06, M10, M12, M13 | ~half day |

## Explore by problem

Every module is anchored to a concrete scenario. See the
[[problems/_moc|13 Teaching Vehicles]] and the problem to knowledge-cluster table.

## See the plan

The [[roadmap/index|Execution Roadmap]] shows how the product gets built: 5 phases,
7 workstreams, an amplification chain, and how they map back to these modules and
concepts.

## The four recurring threads

1. **Honesty** - every number is derived and shows its provenance.
2. **You can't fake it** - concurrency & cost cost money.
3. **Discrimination** - a good design passes, a gamed one fails.
4. **Known gaps** - taught openly: the [[concepts/metrics/utilization-display-bug|utilization-display bug]] and the dry-run-vs-graded-load trap.

---

**Reference:** the 107 canonical specs are wired in under [[reference/README|reference/]];
architecture decisions under [[decisions/README|decisions/]]. Full annotated doc index: [[curriculum|CURRICULUM]].

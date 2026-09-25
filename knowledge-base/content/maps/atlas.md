---
title: "Atlas - the whole vault on one page"
type: moc
tags: [moc]
---
> The big picture the graph view can't give you: which **module** teaches which
> **concept cluster**, and which **spec** is the source of truth behind it.

**How to read it.** The course in [[learn/_moc|Learn]] is 16 modules, M00 to M15
(M = module). Read them in number order: each one builds only on the ones before it. The course has three parts (Part II is
split in two to keep it readable), and each gets a diagram below: modules on the left (blue) in reading order,
the concept clusters they teach in the middle (yellow), and the spec behind each
cluster on the right (pink). Every box is a link.

## Part I - Core physics engine
How time, requests and queues work.

```mermaid
flowchart LR
  M1["M01 · Discrete-event simulation"]:::learn
  M2["M02 · Request lifecycle"]:::learn
  M3["M03 · Queueing model"]:::learn
  C_simulation["simulation"]:::concept
  C_network["network"]:::concept
  C_queueing["queueing"]:::concept
  C_metrics["metrics"]:::concept
  S_simulation["Request lifecycle semantics"]:::spec
  S_network["Edge properties & defaults"]:::spec
  S_queueing["Queue-depth calculation"]:::spec
  M1 --> C_simulation
  M2 --> C_simulation
  M2 --> C_network
  M3 --> C_queueing
  M3 --> C_metrics
  C_simulation --> S_simulation
  C_network --> S_network
  C_queueing --> S_queueing
  classDef learn fill:transparent,stroke:#2a78d6,stroke-width:2px
  classDef concept fill:transparent,stroke:#eda100,stroke-width:2px
  classDef spec fill:transparent,stroke:#e87ba4,stroke-width:2px
  click M1 "../learn/m01-discrete-event-simulation"
  click M2 "../learn/m02-request-lifecycle"
  click M3 "../learn/m03-queueing-model"
  click C_simulation "../concepts/simulation/"
  click S_simulation "../reference/specs/arrival-departure-and-request-lifecycle-semantics"
  click C_network "../concepts/network/"
  click S_network "../reference/specs/edge-properties-and-defaults"
  click C_queueing "../concepts/queueing/"
  click S_queueing "../reference/specs/queue-depth-calculation"
  click C_metrics "../concepts/metrics/"
```

[[m00-orientation|M00]] is orientation and doesn’t teach a concept cluster, so it is left off the diagram.


## Part II - Node & edge mechanics (M04–M06)
What a node is and how much work it can do at once.

```mermaid
flowchart LR
  M4["M04 · Nodes & service time"]:::learn
  M5["M05 · Instance model"]:::learn
  M6["M06 · Execution profiles"]:::learn
  C_storage["storage"]:::concept
  C_compute["compute"]:::concept
  S_storage["Replication quorum walkthrough"]:::spec
  S_compute["Resource allocation & derived concurrency"]:::spec
  M4 --> C_storage
  M5 --> C_compute
  M5 --> C_storage
  M6 --> C_compute
  C_storage --> S_storage
  C_compute --> S_compute
  classDef learn fill:transparent,stroke:#2a78d6,stroke-width:2px
  classDef concept fill:transparent,stroke:#eda100,stroke-width:2px
  classDef spec fill:transparent,stroke:#e87ba4,stroke-width:2px
  click M4 "../learn/m04-nodes-service-time"
  click M5 "../learn/m05-instance-model"
  click M6 "../learn/m06-execution-profiles"
  click C_storage "../concepts/storage/"
  click S_storage "../reference/specs/replication-quorum-state-machine-walkthrough"
  click C_compute "../concepts/compute/"
  click S_compute "../reference/specs/resource-allocation-and-derived-concurrency"
```


## Part II - Node & edge mechanics (M07–M09)
What edges and traits add, and what it all costs.

```mermaid
flowchart LR
  M7["M07 · Edges"]:::learn
  M8["M08 · Traits"]:::learn
  M9["M09 · Cost model"]:::learn
  C_network["network"]:::concept
  C_caching["caching"]:::concept
  C_workloads["workloads"]:::concept
  C_simulation["simulation"]:::concept
  C_storage["storage"]:::concept
  C_cost["cost"]:::concept
  S_network["Edge properties & defaults"]:::spec
  S_caching["Trait integration guide"]:::spec
  S_workloads["Support ledger & runtime semantics"]:::spec
  S_simulation["Request lifecycle semantics"]:::spec
  S_storage["Replication quorum walkthrough"]:::spec
  S_cost["Cost calculation & budgeting"]:::spec
  M7 --> C_network
  M8 --> C_caching
  M8 --> C_workloads
  M8 --> C_simulation
  M8 --> C_storage
  M9 --> C_cost
  C_network --> S_network
  C_caching --> S_caching
  C_workloads --> S_workloads
  C_simulation --> S_simulation
  C_storage --> S_storage
  C_cost --> S_cost
  classDef learn fill:transparent,stroke:#2a78d6,stroke-width:2px
  classDef concept fill:transparent,stroke:#eda100,stroke-width:2px
  classDef spec fill:transparent,stroke:#e87ba4,stroke-width:2px
  click M7 "../learn/m07-edges"
  click M8 "../learn/m08-traits"
  click M9 "../learn/m09-cost-model"
  click C_network "../concepts/network/"
  click S_network "../reference/specs/edge-properties-and-defaults"
  click C_caching "../concepts/caching/"
  click S_caching "../reference/specs/trait-integration-guide"
  click C_workloads "../concepts/workloads/"
  click S_workloads "../reference/specs/support-ledger-and-runtime-semantics"
  click C_simulation "../concepts/simulation/"
  click S_simulation "../reference/specs/arrival-departure-and-request-lifecycle-semantics"
  click C_storage "../concepts/storage/"
  click S_storage "../reference/specs/replication-quorum-state-machine-walkthrough"
  click C_cost "../concepts/cost/"
  click S_cost "../reference/specs/cost-calculation-and-budgeting"
```


## Part III - Metrics, grading & authoring
Measuring honestly, and turning it into a graded question.

```mermaid
flowchart LR
  M10["M10 · Metrics honesty"]:::learn
  M11["M11 · Workload & scale"]:::learn
  M12["M12 · Grading DSL"]:::learn
  C_metrics["metrics"]:::concept
  C_storage["storage"]:::concept
  C_workloads["workloads"]:::concept
  C_grading["grading"]:::concept
  S_storage["Replication quorum walkthrough"]:::spec
  S_workloads["Support ledger & runtime semantics"]:::spec
  S_grading["Grading model & anti-gaming"]:::spec
  M10 --> C_metrics
  M10 --> C_storage
  M11 --> C_workloads
  M12 --> C_grading
  C_storage --> S_storage
  C_workloads --> S_workloads
  C_grading --> S_grading
  classDef learn fill:transparent,stroke:#2a78d6,stroke-width:2px
  classDef concept fill:transparent,stroke:#eda100,stroke-width:2px
  classDef spec fill:transparent,stroke:#e87ba4,stroke-width:2px
  click M10 "../learn/m10-metrics-honesty"
  click M11 "../learn/m11-workload-scale"
  click M12 "../learn/m12-grading-dsl"
  click C_metrics "../concepts/metrics/"
  click C_storage "../concepts/storage/"
  click S_storage "../reference/specs/replication-quorum-state-machine-walkthrough"
  click C_workloads "../concepts/workloads/"
  click S_workloads "../reference/specs/support-ledger-and-runtime-semantics"
  click C_grading "../concepts/grading/"
  click S_grading "../reference/specs/question-grading-model-and-anti-gaming"
```

[[m13-environment-profiles|M13]], [[m14-frontend|M14]], [[m15-newton-integration|M15]] are platform tooling and don’t teach a concept cluster, so they are left off the diagram.

The arrows come from the notes themselves: a module → cluster arrow means that
cluster's concept notes say they are **Taught in** that module, and a cluster →
spec arrow is the spec those notes cite. The metrics notes cite no single spec,
so the metrics cluster has none; start from [[m10-metrics-honesty|M10]].

## The same thing, as a table

| Cluster | Taught in | Source of truth | Map |
|---|---|---|---|
| simulation | [[m01-discrete-event-simulation\|M01]] · [[m02-request-lifecycle\|M02]] · [[m08-traits\|M08]] | [[arrival-departure-and-request-lifecycle-semantics]] | [[maps/simulator-physics\|Simulator Physics]] |
| queueing | [[m03-queueing-model\|M03]] | [[queue-depth-calculation]] | [[maps/simulator-physics\|Simulator Physics]] |
| compute | [[m05-instance-model\|M05]] · [[m06-execution-profiles\|M06]] | [[resource-allocation-and-derived-concurrency]] | [[maps/simulator-physics\|Simulator Physics]] |
| network | [[m02-request-lifecycle\|M02]] · [[m07-edges\|M07]] | [[edge-properties-and-defaults]] | [[maps/simulator-physics\|Simulator Physics]] |
| storage | [[m04-nodes-service-time\|M04]] · [[m05-instance-model\|M05]] · [[m08-traits\|M08]] · [[m10-metrics-honesty\|M10]] | [[replication-quorum-state-machine-walkthrough]] | [[maps/distributed-systems\|Distributed Systems]] |
| caching | [[m08-traits\|M08]] | [[trait-integration-guide]] | [[maps/distributed-systems\|Distributed Systems]] |
| workloads | [[m08-traits\|M08]] · [[m11-workload-scale\|M11]] | [[support-ledger-and-runtime-semantics]] | [[maps/distributed-systems\|Distributed Systems]] |
| metrics | [[m03-queueing-model\|M03]] · [[m10-metrics-honesty\|M10]] | - | [[maps/performance\|Performance]] |
| cost | [[m09-cost-model\|M09]] | [[cost-calculation-and-budgeting]] | [[maps/simulator-physics\|Simulator Physics]] |
| grading | [[m12-grading-dsl\|M12]] | [[question-grading-model-and-anti-gaming]] | [[maps/authoring-grading\|Authoring & Grading]] |

The [[capstone|Capstone]] comes after M15. The worked problems (P01–P13) live
in [[problems/_moc|Practice on Problems]], and every spec is in [[reference/README|Reference]].

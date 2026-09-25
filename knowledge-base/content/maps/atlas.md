---
title: "Atlas — the whole vault on one page"
type: moc
tags: [moc]
---
> The big picture the graph view can't give you: which **module** teaches which
> **concept cluster**, and which **spec** is the source of truth behind it. Read it
> left to right. Every box is a link.

```mermaid
flowchart LR
  START(["Home"]):::hub

  subgraph LEARN["Learn — the course"]
    direction TB
    M01["M01 · Discrete-event simulation"]:::learn
    M02["M02 · Request lifecycle"]:::learn
    M03["M03 · Queueing model"]:::learn
    M04["M04 · Nodes & service time"]:::learn
    M05["M05 · Instance model"]:::learn
    M06["M06 · Execution profiles"]:::learn
    M07["M07 · Edges"]:::learn
    M08["M08 · Traits"]:::learn
    M09["M09 · Cost model"]:::learn
    M10["M10 · Metrics honesty"]:::learn
    M11["M11 · Workload & scale"]:::learn
    M12["M12 · Grading DSL"]:::learn
  end

  subgraph CONCEPTS["Concepts — one idea per note"]
    direction TB
    C_SIM["simulation"]:::concept
    C_QUE["queueing"]:::concept
    C_CMP["compute"]:::concept
    C_NET["network"]:::concept
    C_STO["storage"]:::concept
    C_CAC["caching"]:::concept
    C_WRK["workloads"]:::concept
    C_MET["metrics"]:::concept
    C_CST["cost"]:::concept
    C_GRD["grading"]:::concept
  end

  subgraph SPECS["Specs — source of truth"]
    direction TB
    S_LIFE["Request lifecycle semantics"]:::spec
    S_QD["Queue-depth calculation"]:::spec
    S_RA["Resource allocation & derived concurrency"]:::spec
    S_EDGE["Edge properties & defaults"]:::spec
    S_REPL["Replication quorum walkthrough"]:::spec
    S_TRAIT["Trait integration guide"]:::spec
    S_LEDGER["Support ledger & runtime semantics"]:::spec
    S_COST["Cost calculation & budgeting"]:::spec
    S_GRADE["Grading model & anti-gaming"]:::spec
  end

  START --> M01

  M01 --> C_SIM
  M02 --> C_SIM
  M02 --> C_NET
  M03 --> C_QUE
  M03 --> C_MET
  M04 --> C_STO
  M05 --> C_CMP
  M05 --> C_STO
  M06 --> C_CMP
  M07 --> C_NET
  M08 --> C_CAC
  M08 --> C_WRK
  M08 --> C_SIM
  M08 --> C_STO
  M09 --> C_CST
  M10 --> C_MET
  M10 --> C_STO
  M11 --> C_WRK
  M12 --> C_GRD

  C_SIM --> S_LIFE
  C_QUE --> S_QD
  C_CMP --> S_RA
  C_NET --> S_EDGE
  C_STO --> S_REPL
  C_CAC --> S_TRAIT
  C_WRK --> S_LEDGER
  C_CST --> S_COST
  C_GRD --> S_GRADE

  classDef learn fill:transparent,stroke:#2a78d6,stroke-width:2px
  classDef concept fill:transparent,stroke:#eda100,stroke-width:2px
  classDef spec fill:transparent,stroke:#e87ba4,stroke-width:2px
  classDef hub fill:transparent,stroke:#888,stroke-width:2px

  click START "../index"
  click M01 "../learn/m01-discrete-event-simulation"
  click M02 "../learn/m02-request-lifecycle"
  click M03 "../learn/m03-queueing-model"
  click M04 "../learn/m04-nodes-service-time"
  click M05 "../learn/m05-instance-model"
  click M06 "../learn/m06-execution-profiles"
  click M07 "../learn/m07-edges"
  click M08 "../learn/m08-traits"
  click M09 "../learn/m09-cost-model"
  click M10 "../learn/m10-metrics-honesty"
  click M11 "../learn/m11-workload-scale"
  click M12 "../learn/m12-grading-dsl"
  click C_SIM "../concepts/simulation/"
  click C_QUE "../concepts/queueing/"
  click C_CMP "../concepts/compute/"
  click C_NET "../concepts/network/"
  click C_STO "../concepts/storage/"
  click C_CAC "../concepts/caching/"
  click C_WRK "../concepts/workloads/"
  click C_MET "../concepts/metrics/"
  click C_CST "../concepts/cost/"
  click C_GRD "../concepts/grading/"
  click S_LIFE "../reference/specs/arrival-departure-and-request-lifecycle-semantics"
  click S_QD "../reference/specs/queue-depth-calculation"
  click S_RA "../reference/specs/resource-allocation-and-derived-concurrency"
  click S_EDGE "../reference/specs/edge-properties-and-defaults"
  click S_REPL "../reference/specs/replication-quorum-state-machine-walkthrough"
  click S_TRAIT "../reference/specs/trait-integration-guide"
  click S_LEDGER "../reference/specs/support-ledger-and-runtime-semantics"
  click S_COST "../reference/specs/cost-calculation-and-budgeting"
  click S_GRADE "../reference/specs/question-grading-model-and-anti-gaming"
```

Each arrow comes from the notes themselves: a module → cluster arrow means that
cluster's concept notes say they are **Taught in** that module, and a cluster →
spec arrow is the spec those notes cite. The metrics notes cite no single spec,
so the metrics cluster has none; start from [[m10-metrics-honesty|M10]].

## The same thing, as a table

| Cluster | Taught in | Source of truth | Map |
|---|---|---|---|
| simulation | [[m01-discrete-event-simulation\|M01]] · [[m02-request-lifecycle\|M02]] · [[m08-traits\|M08]] | [[arrival-departure-and-request-lifecycle-semantics]] | [[maps/simulator-physics\|Simulator Physics]] |
| queueing | [[m03-queueing-model\|M03]] | [[queue-depth-calculation]] | [[maps/simulator-physics\|Simulator Physics]] |
| compute | [[m05-instance-model\|M05]] · [[m06-execution-profiles\|M06]] | [[resource-allocation-and-derived-concurrency]] | [[maps/simulator-physics\|Simulator Physics]] |
| network | [[m07-edges\|M07]] · [[m02-request-lifecycle\|M02]] | [[edge-properties-and-defaults]] | [[maps/simulator-physics\|Simulator Physics]] |
| storage | [[m04-nodes-service-time\|M04]] · [[m05-instance-model\|M05]] · [[m08-traits\|M08]] · [[m10-metrics-honesty\|M10]] | [[replication-quorum-state-machine-walkthrough]] | [[maps/distributed-systems\|Distributed Systems]] |
| caching | [[m08-traits\|M08]] | [[trait-integration-guide]] | [[maps/distributed-systems\|Distributed Systems]] |
| workloads | [[m11-workload-scale\|M11]] · [[m08-traits\|M08]] | [[support-ledger-and-runtime-semantics]] | [[maps/distributed-systems\|Distributed Systems]] |
| metrics | [[m10-metrics-honesty\|M10]] · [[m03-queueing-model\|M03]] | — | [[maps/performance\|Performance]] |
| cost | [[m09-cost-model\|M09]] | [[cost-calculation-and-budgeting]] | [[maps/simulator-physics\|Simulator Physics]] |
| grading | [[m12-grading-dsl\|M12]] | [[question-grading-model-and-anti-gaming]] | [[maps/authoring-grading\|Authoring & Grading]] |

**Not on the diagram:** the platform modules ([[m13-environment-profiles|M13]],
[[m14-frontend|M14]], [[m15-newton-integration|M15]]) and the
[[capstone|Capstone]] teach tooling rather than a concept cluster. The worked
problems live in [[problems/_moc|Practice on Problems]], and every spec is in
[[reference/README|Reference]].

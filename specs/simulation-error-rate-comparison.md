# Simulation Error-Rate Comparison

This document puts all of the repo's error-rate and failure-rate concepts into one comparison table.

It mixes three kinds of things on purpose:

- **configurable fault knobs** you set before a run
- **derived error metrics** the simulator computes after a run
- **related failure probabilities** that are not literally named `errorRate`, but behave similarly

## Comparison Table

| Name | Where configured | What it represents | What the user sees in results |
| --- | --- | --- | --- |
| **Edge error rate** | Edge config, `edge.errorRate` in topology. In the UI this is the edge's `Error rate` input in the edge properties panel. Serialized in `src/renderer/src/hooks/useTopologySerializer.ts`; runtime type in `src/engine/core/types.ts`. | Probability that a request fails **while crossing the dependency path** between two nodes. This models transport/RPC/path failures before the target node really handles the request. | Requests become `request-rejected` with reason `edge_error_rate`. They increase rejected counts, increase error rate, reduce availability, and appear in edge labels as `/ x% fail` when they occur. |
| **Node error rate** | Node config, `sim.nodeErrorRate`, exposed in the node's **Chaos** section and serialized into `config.nodeErrorRate`. | Probability that a request fails **inside the node**, after it has already arrived there and the node has processed it far enough to complete locally. This models service/app/component failure rather than path failure. | Requests become `request-rejected` with reason `node_error_rate`. They increase rejected counts, increase error rate, reduce availability, and show up under **Rejections by reason**. |
| **Packet loss rate** | Edge config, `edge.packetLossRate`. Set in edge properties. | Probability that traffic is lost **in flight** on the edge. Unlike edge error rate, this is modeled as loss that leads to timeout rather than an immediate rejection. | Requests become `request-timeout` rather than `request-rejected`. This increases timeout counts, which still feed into derived error rate and reduce availability. |
| **Security block rate** | Node config, `sim.securityPolicy.blockRate`, on `security-filter` nodes such as WAF / firewall / security group. | Probability that a security filter **actively blocks** a request as policy. This is not "the network broke"; it is intentional rejection by the security node. | Requests become `request-rejected` with reason `security_blocked`. They increase rejected counts and derived error rate. |
| **Security dropped packets** | Node config, `sim.securityPolicy.droppedPackets`, on `security-filter` nodes. | Probability that the security filter **drops** traffic instead of blocking it explicitly. This behaves more like a silent network/security drop than an application error. | Requests become `request-timeout`. They increase timeout counts and therefore feed into derived error rate and lower availability. |
| **Global error rate** | Not configured directly. Computed in `src/engine/metrics.ts` from post-warmup global totals. | The run-wide fraction of post-warmup requests that failed. This is the simulator's overall error outcome, not a fault injection knob. | Shown in the Results tray / Overview as the run's overall `Error Rate`. Formula: `(postWarmupTotalRequests - postWarmupSuccessfulRequests) / postWarmupTotalRequests`. |
| **Per-node error rate** | Not configured directly. Computed in `src/engine/metrics.ts` for each node. | The fraction of requests that reached a node after warmup and then failed there at that node's accounting boundary. | Shown in the selected node panel, node cards in the **Errors** lens, and the node detail view. Formula: `(postWarmupRejected + postWarmupTimedOut) / postWarmupArrived`. |

## Quick Mental Model

### Configured fault knobs

These are probabilities you inject into the simulation:

- edge error rate
- node error rate
- packet loss rate
- security block rate
- security dropped packets

### Derived results

These are measured outcomes after the run:

- global error rate
- per-node error rate

## Shortest Distinction

| Concept | Short definition |
| --- | --- |
| **Edge error rate** | Failure **on the way to** the node |
| **Node error rate** | Failure **inside** the node |
| **Packet loss rate** | Traffic is **lost in flight**, so it times out |
| **Block rate** | Traffic is **rejected by policy** |
| **Dropped packets** | Traffic is **silently discarded by a filter**, so it times out |
| **Error rate (result)** | Fraction of requests that **actually failed in the run** |

## Why This Matters

Two different knobs can produce the same user-facing symptom (`higher error rate`) while modeling different root causes:

- `edge.errorRate` says "the dependency path is flaky"
- `nodeErrorRate` says "the service itself is flaky"
- `packetLossRate` says "the path lost traffic and the request timed out"
- `blockRate` says "the filter intentionally denied the request"

That distinction matters if you are using the simulator to teach:

- path failures vs service failures
- rejection vs timeout
- transport problems vs policy decisions

## Source Pointers

- Edge fault knobs: `src/engine/core/types.ts`, `src/renderer/src/hooks/useTopologySerializer.ts`, `src/engine/engine.ts`
- Node fault knobs: `src/engine/traits/capabilityModules.ts`, `src/engine/catalog/componentSpecs.ts`, `src/engine/engine.ts`
- Derived error metrics: `src/engine/metrics.ts`

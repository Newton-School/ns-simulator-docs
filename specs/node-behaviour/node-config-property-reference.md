# Node Config Property Reference

This document explains the node-config properties and sections you listed:

- what each one means
- which nodes currently have it
- why those nodes have it

The current implementation is driven by the capability-module system in:

- `src/engine/traits/capabilityModules.ts`
- `src/engine/traits/cache.ts`
- `src/engine/traits/contentRouting.ts`
- `src/engine/traits/healthAwareRouting.ts`
- `src/engine/traits/rateLimiter.ts`
- `src/engine/traits/readWriteSplit.ts`
- `src/engine/traits/ackAndRelease.ts`

## How To Read This

Some items below are:

- **sections** in the config panel, such as `Caching`, `Chaos`, `Performance`
- **fields inside a section**, such as `Base RPS`, `Timeout`, `Cache hit rate`
- **composite ideas**, such as `Routing & Strategy + Health checks`

Where useful, the "Which nodes have it" column gives both:

- the current **code rule**
- a few concrete **palette examples**

## Property Reference

| Property / section | What it means | Which nodes have it | Why those nodes have it |
| --- | --- | --- | --- |
| **Advanced - Distribution model** | The advanced field that changes the service-time distribution shape used under **Performance**. Current options are `constant`, `exponential`, `log-normal`, and `normal`. | All **runtime** nodes: every node except `source` and `composite` profiles. | Every runtime node is currently simulated as a G/G/c/K-style processing node with a service-time distribution, so the engine exposes the distribution model everywhere runtime processing exists. |
| **Base RPS** | The baseline requests-per-second emitted by a source node before burst/spike/sawtooth modifiers. | Source-profile nodes only: `Client App`, `Input Source`. | Only source nodes generate workload. Non-source nodes consume and process traffic, so they do not own the baseline request rate. |
| **Cache Hit rate** | Probability that the node serves a request from cache instead of forwarding/processing it normally. | Cache-capable component types: `cdn`, `in-memory-cache`, `reverse-proxy`. Examples: `CDN`, `Redis Cache`, `Reverse Proxy`. | These nodes can short-circuit work locally and answer without pushing the request deeper into the topology. |
| **Cache hit latency** | Latency cost of a successful cache hit. | Same nodes as `Cache hit rate`: `CDN`, `Redis Cache`, `Reverse Proxy`. | Once a node can serve a cache hit locally, the simulator also needs a cheaper hit-latency path to model that benefit honestly. |
| **Caching** | The section that groups cache behavior fields such as hit rate, hit latency, and TTL. | `CDN`, `Redis Cache`, `Reverse Proxy`. | Those are the nodes the repo currently marks as cache-capable with the cache trait. |
| **Chaos** | The section that exposes node-level failure injection through `sim.nodeErrorRate`. | All runtime nodes except sources/composites. Examples: API servers, workers, routers, DBs, control-plane services, observability nodes, external connectors. | The simulator allows you to inject probabilistic failure into any runtime request-processing node to observe degradation. |
| **Connections** | A relabeled version of the base queueing section for relational databases. `workers` becomes "connection pool size" and `capacity` becomes "query queue limit." | `relational-db` component type. Examples: `Primary DB`, `Read Replica`. | For databases, concurrency is better taught as connection-pool capacity than generic "workers," so the shared queue model is renamed into DB vocabulary. |
| **Consumers** | A relabeled version of the base queueing section for queue nodes. `workers` becomes consumer concurrency and `capacity` becomes backlog limit. | `queue` component type. Example: `Message Queue`. | A queue's concurrency is really the number of consumers draining it, not request-handler workers, so the section is renamed to match async queue semantics. |
| **Content Routing > Routing Rules** | Rules that inspect request content (`type`, `path`, or `host`) and force matching requests to a specific downstream target. | `load-balancer-l7`, `api-gateway`, `ingress-controller`. Examples: `Load Balancer L7`, `API Gateway`, `Ingress Controller`. | These are L7/request-aware routers. They can inspect request metadata, unlike pure L4 transport routers. |
| **Delivery** | A section that explains queue delivery semantics. In the current implementation it is a note, not editable knobs. | `queue` component type only. Example: `Message Queue`. | Queues acknowledge producers at enqueue time and process consumers asynchronously, so they need a delivery-specific explanation instead of generic request/response wording. |
| **Forwarding** | A relabeled version of the base queueing section for request-forwarding nodes. `workers` and `capacity` describe connection/request forwarding concurrency and queueing. | `load-balancer`, `load-balancer-l4`, `load-balancer-l7`, `api-gateway`, `ingress-controller`, `reverse-proxy`, `cdn`. | These nodes spend their capacity forwarding or proxying traffic, not doing generic business logic work, so the queue model is translated into forwarding vocabulary. |
| **Mean Service Time** | The human-facing mean latency of the node's service-time model. Depending on the distribution, the UI may show a direct value or translate the engine's `lambda` into mean milliseconds. | All runtime nodes under the **Performance** section. | Every runtime node has a processing-time model. The simulator exposes that model as "mean service time" because that is how humans reason about latency. |
| **Operations** | A relabeled version of the base queueing section for in-memory caches. `workers` becomes concurrent operations and `capacity` becomes operation queue limit. | `in-memory-cache` component type. Example: `Redis Cache`. | Cache systems are better explained as handling concurrent operations than as running generic request workers. |
| **Performance** | The section that groups request timeout and service-time distribution settings. | All runtime nodes. | Every runtime node has processing latency and timeout behavior in the current engine, so performance settings apply broadly. |
| **Queueing** | The default base concurrency/queue section used when a node does not get a domain-specific title such as `Forwarding`, `Connections`, `Operations`, or `Consumers`. | Most runtime nodes that are not in a specialized vocabulary override. Examples: API Server, Auth Service, Search Service, NoSQL DB, Object Storage, Streaming Analytics, Tool Registry, Health Check Manager. | The underlying simulation model is still a generic queue with workers and capacity; these nodes keep the default queueing vocabulary because no better domain-specific label has been defined yet. |
| **Rate Limiting** | The section that configures token-bucket admission control via bucket size and refill rate. | `api-gateway` and `third-party-api-connector`. Examples: `API Gateway`, `External Service`, `Output Sink`. | These are natural choke points where quota enforcement and upstream throttling are realistic teaching concepts. |
| **READ/WRITE - Read Latency, Write Latency** | Relational-DB-specific latency overrides that let reads and writes have different mean service times. | `relational-db`, but the fields are only visible on non-replica DB nodes. In practice: `Primary DB` gets the inputs; `Read Replica` hides them. | Primary databases often have different cost profiles for reads vs writes. Read replicas use a different trait: they are read-only rather than read/write-tunable. |
| **Routing & Strategy** | The routing section that exposes the node's route-selection strategy, such as `round-robin`, `weighted`, `random`, `least-conn`, or `passthrough/conditional` depending on type. | All `router`-profile nodes. Examples include: `Load Balancer (Legacy)`, `Load Balancer L4`, `Load Balancer L7`, `Ingress Controller`, `Reverse Proxy`, `Service Mesh`, `NAT Gateway`, `VPN Gateway`, `Routing Rule`, `Routing Policy`, `Edge Router`, `Network Interface`, `DNS Resolver`, `DNS Server`, `CDN`, `API Gateway`, `Sharding`, `Hashing`. | These nodes exist to choose or influence the downstream path, so routing strategy is core to their behavior. |
| **Routing & Strategy + Health checks** | The routing section plus an additional `Health checks` toggle that filters out unhealthy downstream targets before choosing a route. | The health-aware routing subset: `load-balancer`, `load-balancer-l4`, `load-balancer-l7`, `api-gateway`, `ingress-controller`, `reverse-proxy`. | These nodes usually fan out to multiple backends and are expected to stop sending traffic to unhealthy targets, so the router gets both routing strategy and health-aware filtering. |
| **SLO Targets** | Optional latency and availability targets used for post-run grading. Current fields are `Latency target (p99)`, `Availability target`, and `Error budget`. | All runtime nodes except `broker` profile nodes. Examples: compute services, workers, datastores, routers, control-plane nodes, observability nodes, security filters, integrations. Excluded: `Message Queue`, `Event Broker`, `Pub/Sub`, `Event Stream`. | The current SLO grading logic is designed around request-serving nodes with latency and availability outcomes. Broker-style async nodes are excluded by the current rule. |
| **Timeout** | Maximum time the node allows a request to spend being processed before timing it out. | All runtime nodes under **Performance**. | Every runtime node in the current model can time out a request if processing exceeds its configured limit. |
| **Workload - Pattern** | The traffic-shape selector for source nodes. Current patterns are `constant`, `poisson`, `bursty`, `diurnal`, `spike`, and `sawtooth`. | Source-profile nodes only: `Client App`, `Input Source`. | Only source nodes generate traffic, so only they own the request-arrival pattern. |

## A Few Important Notes

### `Queueing`, `Forwarding`, `Connections`, `Operations`, and `Consumers` are the same base model

These are not five completely different engines. They are the same shared queue/capacity model with different labels:

- `Queueing` = default vocabulary
- `Forwarding` = router/proxy vocabulary
- `Connections` = DB vocabulary
- `Operations` = cache vocabulary
- `Consumers` = queue/broker vocabulary

The repo does this on purpose so the UI speaks the node's domain language instead of showing the same raw `workers/capacity` wording everywhere.

### `Routing & Strategy` and `Routing & Strategy + Health checks` are not separate modules

Current implementation:

- `Routing & Strategy` comes from the routing strategy module
- `Health checks` is injected into the same `Routing` section for a subset of router types

So the combined phrase is best read as:

> "This node is a router, and this router type also knows how to filter unhealthy targets."

### `Advanced - Distribution model` is a power-user knob

It is marked as `advanced` because most users think in terms of:

- average latency
- timeout

rather than:

- exponential vs log-normal vs normal
- `mu`, `sigma`, `stdDev`

The advanced model exists so the simulator can stay flexible without making the default panel feel like raw engine internals.

## Selection Rules Summary

If you want the shortest "why does this node get this section?" version:

- **Source nodes** get `Workload`, `Pattern`, `Base RPS`
- **All runtime nodes** get `Performance`, `Chaos`, and some flavor of queue/capacity section
- **Router-profile nodes** get `Routing & Strategy`
- **Health-aware routers** get `Routing & Strategy + Health checks`
- **Cache-capable nodes** get `Caching`
- **API gateways and external connectors** get `Rate Limiting`
- **Relational DBs** get `Connections` and `READ/WRITE`
- **Queues** get `Consumers` and `Delivery`
- **Runtime nodes except brokers** get `SLO Targets`

## Related Existing Specs

If you want the broader architectural rationale, the repo already has companion docs here:

- `ns-simulator-docs/specs/node-behaviour/node-config-architecture.md`
- `ns-simulator-docs/specs/node-behaviour/node-config-mapping.md`

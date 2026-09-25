---
title: "Concept Catalogue - every concept, in teaching order"
tags: [moc, curriculum]
---

> **Every concept the simulator uses, defined, in the order to teach it.** Each chapter
> only relies on ideas from the chapters before it. Definitions are checked against the
> engine code (`src/engine/`), not just the specs. Use it to plan lectures; follow the
> **Go deeper** links for the full module, concept notes and spec.

**Why this order.** Distributions come before time, time before a single request, one
request before one node, and one node before connections. Traffic comes before node
behaviours (traits), because every trait changes how traffic is handled. Metrics and
cost come after the behaviour they measure, and grading comes last because it is built
on everything else. Part VIII is product-specific: skip it for a pure system-design
course. It follows the [[learn/_moc|course order (M00–M15)]], with newer topics placed
where their prerequisites are met.

## Part 0 - Orientation

### Chapter 1. What the simulator is
- **Topology:** the design being tested: nodes (components) connected by edges, drawn on the canvas and saved as `TopologyJSON`.
- **Node / component:** one box on the canvas, such as a service, database, cache or load balancer. Each has a component type that sets its default behaviour.
- **Edge:** a directed connection that carries requests from one node to the next.
- **Run:** one simulation of the topology under a workload. It produces metrics, per-request traces, a cost and a grade.
- **Honesty doctrine:** every number the simulator shows is produced by the simulation, never typed in or faked. Anything not modelled is labelled as such.
- **Support ledger:** the single record (`supportLedger.ts`) of what the simulator actually models per domain, component and behaviour, and what it only describes.

**Go deeper:** [[m00-orientation|M00 Orientation]] · [[support-ledger-and-runtime-semantics]]

## Part I - Time and a single request

### Chapter 2. Randomness and reproducibility
- **Distribution:** the shape of a random quantity, such as a service time or edge latency. Supported: constant, deterministic, normal, log-normal, exponential, uniform, Weibull, gamma, beta, Pareto, Poisson, binomial, empirical, and mixtures of these.
- **Seed:** the starting value for the random number generator. The same seed and topology always give the same run.
- **Determinism:** time is stored as whole microseconds and all randomness comes from the seeded generator, so results reproduce exactly.

**Go deeper:** [[simulation-determinism-and-numerics]]

### Chapter 3. Discrete-event simulation
- **Event:** something that happens at an instant: a request arriving, processing starting, a timeout, a node failing. There are 26 event types.
- **Event queue / clock:** events wait in a priority queue ordered by simulated time; the clock jumps straight to the next event.
- **Event priority:** tie-break order for events at the same instant: system, then arrival, then processing, then forwarding, then timeout last, so a request gets its chance to finish first.
- **Stop condition:** when the run ends: after a set duration, or after N requests.
- **Warmup:** the opening stretch of a run, left out of metrics.
- **Transient vs steady state:** a run starts with empty queues (the transient). Steady state is once arrivals and departures balance; only steady state is representative.

**Go deeper:** [[m01-discrete-event-simulation|M01]] · [[discrete-event-simulation-advances-time-through-events]] · [[warmup-removes-transient-behavior]] · [[steady-state-differs-from-transient]]

### Chapter 4. The request lifecycle
- **Request:** one unit of work moving through the topology, with an id, type, size, and optionally a key and headers.
- **Lifecycle:** generated → arrives at a node → queues → is processed → is forwarded → … → ends.
- **Terminal outcome:** every request ends in exactly one of four outcomes: `success`, `timeout`, `rejected` or `connection_reset`.
- **Rejection reason:** why a request was rejected, for example `capacity_exceeded` (queue full), `oom` (out of memory) or `node_failed`.
- **Timeout:** the request didn't finish within its deadline. A timeout is still scheduled even when a request is stuck waiting.
- **Phase timeline:** a request's total latency split exactly into time on each edge, queue wait at each node, and service time at each node.

**Go deeper:** [[m02-request-lifecycle|M02]] · [[arrival-departure-and-request-lifecycle-semantics]] · [[request-rejection-behaviour]] · [[closed-terminal-taxonomy-enables-honest-errors]]

## Part II - One node

### Chapter 5. Queueing
- **G/G/c/K queue:** the model every node follows: arrivals of any shape (G), service times of any shape (G), `c` parallel workers, total capacity `K`.
- **Workers (`c`):** how many requests a node processes at the same time.
- **Capacity (`K`):** the most requests a node can hold, in service plus waiting.
- **Admission control:** when the node already holds K requests, the next arrival is rejected. Capacity is a hard wall, not a gradual slowdown.
- **Queue depth:** requests waiting, not those in service. Rising depth predicts a p99 spike before the average latency moves.
- **Queue discipline:** the order waiting requests are served in: FIFO, LIFO or priority. WFQ is accepted but currently behaves exactly like FIFO.
- **Saturation:** arrivals outpacing service, so the queue grows and latency explodes. A queue can saturate while CPU still looks fine.

**Go deeper:** [[m03-queueing-model|M03]] · [[queue-depth-calculation]] · [[ggck-models-finite-capacity-queues]] · [[queue-saturation-precedes-cpu-saturation]] · [[queue-depth-is-a-leading-indicator-of-latency]]

### Chapter 6. Component types and service time
- **Component type:** one of 148 types in 14 families, each with default behaviour: compute (12), network (17), storage (19), messaging (7), orchestration (13), security (11), observability (9), devops (7), data-infrastructure (5), real-time (6), integration (5), consensus (4), DNS, and auxiliary (13).
- **Service time:** how long one request takes to process at a node. It's drawn from the node's distribution and can be overridden per request (for example different read and write latencies).
- **Storage profile:** service-time curves specific to each kind of data store and operation, so choosing the right store changes the run itself.

**Go deeper:** [[m04-nodes-service-time|M04]] · [[node-capability-matrix]]

### Chapter 7. Resources and derived concurrency
- **Instance type:** a real machine size from the instance catalogue (vCPUs, RAM, price per hour, speed factor).
- **Instance count:** how many copies of the node run (replicas).
- **Derived concurrency:** `c` is worked out from the hardware, not typed in: `c = vCPUs × instances × workers-per-vCPU`. More concurrency means paying for more hardware.
- **Memory-derived capacity:** `K = total RAM ÷ memory per request`, never less than `c`.
- **Speed factor (`perfFactor`):** faster instances shorten service time; the benefit is reduced for I/O-bound work, which is mostly waiting.
- **Pricing model:** on-demand and other plans, applied as a multiplier on the instance price.

**Go deeper:** [[m05-instance-model|M05]] · [[resource-allocation-and-derived-concurrency]] · [[effective-concurrency-determines-service-capacity]] · [[derive-and-lock-prices-concurrency]]

### Chapter 8. Execution profiles and compute contention
- **CPU-bound:** work that keeps the core busy the whole time, so about one worker per vCPU.
- **I/O-bound:** work that mostly waits on disk or network, so one core juggles many requests (32 per vCPU). Compute nodes default to this.
- **`cpuBoundFraction`:** the share of each request that really needs the CPU, fixed per component type.
- **Two-tier contention:** even on an I/O-bound node, the CPU-bound share competes for the few physical cores, so capacity can't exceed what the hardware can do.
- **Worker utilization vs utilization:** how busy the worker pool is, vs the headline figure, which is whichever is higher of worker and CPU occupancy.

**Go deeper:** [[m06-execution-profiles|M06]] · [[execution-profile-and-node-concurrency]] · [[compute-contention-two-tier-model]] · [[cpu-bound-is-one-worker-per-vcpu]] · [[io-bound-multiplexes-many-per-vcpu]]

### Chapter 9. Memory pressure
- **Working set:** the hot data a node needs to keep in RAM.
- **Memory pressure:** as memory fills, latency rises gradually (spilling out of RAM, garbage-collection churn) before the node rejects requests with `oom` at its RAM limit.

**Go deeper:** [[memory-pressure-and-memory-bound-model]]

## Part III - Connecting nodes

### Chapter 10. Edges and the network
- **Edge model:** `network` (edges carry real latency, bandwidth, loss and cost) or `connector` (plain wires with none of these).
- **Path type:** the distance an edge covers: same-rack, same-dc, cross-zone, cross-region or internet. It sets the default latency and bandwidth and is inferred from where the two nodes sit.
- **Edge latency, bandwidth, packet loss, error rate:** how long a trip takes, how much data fits through per second, and the chance the trip is lost or fails.
- **Edge concurrency limit (`maxConcurrentRequests`):** the most requests one edge can carry at once, like a connection limit.
- **Synchronous blocking:** a caller waiting on a slow downstream keeps its worker or connection tied up, which can exhaust connection pools.
- **Location / region:** where a node sits, from an offline location catalogue.
- **Geo latency:** extra delay that CDNs, global traffic managers and edge routers add for the distance to the serving region.
- **Protocol session:** connection open and close, HTTP acknowledgement mode, L4 vs L7 behaviour, WebSocket flow control.

**Go deeper:** [[m07-edges|M07]] · [[edge-properties-and-defaults]] · [[latency-is-dominated-by-path-type]] · [[edge-concurrency-caps-inflight-requests]] · [[synchronous-blocking-exhausts-connection-pools]] · [[connector-edges-carry-no-physics]]

### Chapter 11. Routing and traffic distribution
- **Load-balancing strategy:** how a node picks which target gets each request: round-robin, least-connections, least-response-time, power of two choices (`p2c`), weighted, sticky, IP hash, passthrough, random.
- **Content routing:** choosing a route by request attributes (type, path, host, method, headers), with equals, prefix or regex matching.
- **Key-based routing / consistent hashing:** each request key hashes onto a ring that picks a shard, so skewed keys make skewed shards.
- **Health-aware routing:** skipping targets marked unhealthy.
- **DNS routing policy:** steering and failover done at DNS resolution.
- **Async boundary:** fire-and-forget targets (observability, queues, streams) never compete with real targets for routing and never add latency to the request.

**Go deeper:** [[traffic-distribution-gap-register]]

## Part IV - Traffic

### Chapter 12. Workload
- **Source node:** where traffic enters the topology.
- **Base RPS:** the baseline arrival rate, in requests per second.
- **Arrival pattern:** how arrivals vary over time: constant, poisson, bursty, diurnal, spike, sawtooth, or replay of recorded traffic.
- **Request mix:** the weighted blend of request types and sizes.
- **Keyspace and skew:** the set of keys requests touch; a Zipf skew makes a few keys very hot.
- **Headers / metadata:** extra request attributes that routing can match on.
- **Burst:** a short period where arrivals far exceed the service rate, causing temporary queue instability.

**Go deeper:** [[m11-workload-scale|M11]] · [[request-pattern-configuration]] · [[request-type-model]] · [[burst-traffic-creates-transient-instability]]

### Chapter 13. Heavy load
- **Fluid model:** for very high loads (around 1M requests per second) the result is calculated from rates instead of simulating every request.
- **M/M/c latency:** the textbook formula the fluid model uses to estimate waiting time at that scale.
- **Representative traffic:** a small, capped sample of request flows, so the canvas can still animate a fluid-model run.

**Go deeper:** [[m11-workload-scale|M11]]

## Part V - Node behaviours (traits)

### Chapter 14. What a trait is
- **Trait / capability module:** a pluggable piece of behaviour attached to certain component types; its settings appear automatically in the properties panel.
- **Hooks:** where a trait can act on a request: `beforeArrival`, `beforeRouting`, `filterRoutes`, `afterTerminal` (once a request has finished) and `onTick` (a timer that repeats at a set interval).

**Go deeper:** [[m08-traits|M08]] · [[trait-integration-guide]] · [[node-capability-matrix]]

### Chapter 15. Caching
- **Cache-aside:** each request is a hit (served from the cache) or a miss (continues to the store behind it).
- **Declared hit rate:** a hit probability you type in (the default).
- **Derived LRU:** a real, size-limited LRU cache on each request's key, so the hit rate comes from the traffic.
- **Cache stampede:** a hot key expires and every concurrent miss hits the store at once.
- **Request collapsing:** only the first miss for a key goes to the store; the others wait for its answer.

**Go deeper:** [[derived-cache-hit-rate-model]] · [[cache-aside-is-bernoulli-thinning]] · [[cache-stampede-is-a-thundering-herd]] · [[request-collapsing-dedups-inflight-misses]]

### Chapter 16. Storage behaviours
- **Read/write split:** reads and writes get different service times.
- **Read replica:** a read-only copy that adds read capacity; every write still goes to the primary.
- **Replication:** a write waits for its acknowledgement point, replicas can be slightly out of date (bounded staleness), and traffic is rejected while a failover is in progress.
- **Quorum write:** acknowledged after a majority of replicas confirm, slower but more durable.
- **Replica cluster state machine:** each replica moves between leader, follower and failed.
- **Row lock:** writes to the same key run one at a time, so effective concurrency for that key is 1.
- **Lock lease:** a time-limited lock on a key, with rejection when taken, expiry, and an optional fencing token that stops a stale holder from writing.
- **CQRS:** separate read and write paths, so heavy writes don't hurt read latency.
- **Tiered retrieval:** reading from cold or archive storage takes seconds to minutes.
- **Log replay / event sourcing:** state is rebuilt by replaying the log, so reads slow down as the log grows unless a snapshot limits how far back they go.
- **Scatter-gather (fan-out query):** a query sent to N shards finishes only when the slowest responds, so the latency tail grows with N.
- **Sharding:** splitting data across shard nodes by key.
- **ID allocation:** block allocation (pre-reserved ranges) vs per-request allocation, each with a different service-time cost.

**Go deeper:** [[replication-quorum-state-machine-walkthrough]] · [[id-sequence-generator-node]] · [[replication-scales-reads-not-writes]] · [[quorum-writes-trade-latency-for-durability]] · [[row-locks-serialize-writes]] · [[cqrs-splits-read-and-write-paths]]

### Chapter 17. Messaging and streams
- **Ack-and-release:** a queue acknowledges the producer as soon as it stores the message; the consumer processes it separately.
- **Broadcast fanout (pub/sub):** one published message is delivered to every subscriber.
- **Consumer group:** within a group each message goes to exactly one member; every group gets every message.
- **Stream broker:** Kafka-like: the producer is acknowledged at append, and each partition is always read by the same consumer.
- **Consumer lag:** a backlog that builds when consumers drain slower than messages arrive.
- **Windowing:** fixed back-to-back time windows (tumbling windows), each producing one combined result.
- **Batching:** processing N items together spreads a fixed per-batch cost across them, at the price of waiting for the batch to fill.

**Go deeper:** [[consumer-groups-deliver-once-per-group]] · [[fanout-on-write-vs-on-read]] · [[celebrity-workload-breaks-fanout-on-write]]

### Chapter 18. Latency-cost behaviours
- **External latency:** a call to a third-party provider takes time the caller can't control.
- **Crypto cost:** encrypting, signing and verifying add latency per operation, often with a quota.
- **Token cost:** LLM response time scales with the number of tokens generated.
- **Inspection cost:** a WAF or policy check adds latency to every request and blocks a fraction of them.
- **Capacity limit:** a rolling ops-per-second ceiling on a link or device (IOPS, NAT ports, line rate); anything above it is rejected.
- **Cold start:** extra latency the first time a scaled-to-zero serverless function runs.
- **Connection capacity:** a connection server's limit on open connections, with refused overflow.

**Go deeper:** [[node-capability-matrix]] · [[connection-tier-capacity]]

### Chapter 19. Admission control and correctness guards
- **Rate limiter:** a per-key request limit using token-bucket (the default), fixed-window (which deliberately allows up to twice the limit across a window boundary) or sliding-window.
- **Breach check (`rateLimit.breaches`):** a count of how often the limit was actually exceeded.
- **Idempotency dedup:** retried writes are caught within a time window, and a commit record tracks each one through intent → confirmed → unknown → replay-blocked.
- **Reservation store / oversell:** a record of which request claimed each resource first, so double-booking is counted in `reservations.oversells`.

**Go deeper:** [[rate-limiter-admission-and-breach-model]] · [[rate-limiter-lab-lesson]] · [[contended-inventory-and-oversell-model]]

### Chapter 20. Failure and resilience
- **Failure mode:** how a failed node behaves: `reject` (refuses instantly), `blackhole` (requests vanish; the client waits out its timeout), `hang` (fills its queue, then requests vanish) or `degraded` (still serves, slower).
- **Chaos:** failures deliberately injected into a run.
- **Retry with backoff:** the caller retries, waiting longer each time, with optional random jitter. Retries use real capacity, so they can cause retry storms.
- **Circuit breaker:** closed → open → half-open; stops calling a failing downstream so the failure doesn't spread.
- **Health prober:** a health-check manager that watches nodes and marks them unhealthy.
- **Database failover:** a replica is promoted to primary.
- **Autoscaler:** a control loop on the repeating timer that resizes concurrency to hit a utilization target, reacting with a delay after each cooldown.
- **Single point of failure (SPOF):** a node whose loss cuts the traffic source off from part of the system, found from the topology alone.

**Go deeper:** [[request-rejection-behaviour]] · [[state-machines-make-behavior-gradeable]]

## Part VI - Measuring

### Chapter 21. Metrics
- **Time-weighted metric:** a total over the whole run, not an average of snapshots.
- **Utilization:** total busy time ÷ (`c` × run length).
- **Throughput:** successfully processed requests per second.
- **Error rate / availability:** the share of requests that failed, and the share that succeeded.
- **Latency percentiles (p50, p95, p99):** from histograms. Per-hop p99s can't be added to get the end-to-end p99.
- **Per-node metrics:** arrived, processed, rejected, timed-out and reset counts (each also after warmup); average and peak queue length; service time, queue wait, time in system; throughput, error rate, availability.
- **Post-warmup:** counts that exclude the warmup period.
- **Trace / tracer:** the recorded path each request took, which the canvas can play back.

**Go deeper:** [[m10-metrics-honesty|M10]] · [[throughput-calculation]] · [[utilization-is-a-time-weighted-integral]] · [[percentiles-do-not-sum-across-hops]]

### Chapter 22. Cost and budget
- **Provisioned cost:** instance price per hour × pricing multiplier × instance count.
- **Volume / consumption cost:** traffic-dependent cost (per GB or per request), estimated before a run and made exact from the run's measured traffic.
- **Egress cost:** data leaving a zone, region or the cloud, per GB: cross-zone $0.01, cross-region $0.02, internet $0.09; same-dc is free.
- **Always-on cost:** every topology shows its cost in USD per hour, budget or not.
- **Budget:** an authored limit on node count, edge count or cost that stops the "add everything" answer.
- **Error budget:** how much SLO failure is allowed before the SLO counts as broken.

**Go deeper:** [[m09-cost-model|M09]] · [[cost-calculation-and-budgeting]] · [[provisioned-cost-is-instance-hours]] · [[egress-is-priced-per-gb]]

## Part VII - Questions and grading

### Chapter 23. Questions
- **Question package:** the question text, requirements (NFRs), scenarios, rubric and starting (scaffold) topology.
- **Scenario / test case:** a named workload or condition the design is run against, such as normal load, a spike or a node failure.
- **Environment profile:** how the same question is presented: `AUTHOR` shows everything; `ASSIGNMENT` is graded, with the starting design locked; `PRACTICE` is free editing with live feedback and no grade.

**Go deeper:** [[m13-environment-profiles|M13]] · [[environment-definition-and-configuration-model]] · [[test-case-authoring-handbook]]

### Chapter 24. Grading
- **Rubric check:** a condition "metric operator value", of three kinds: topology, simulation and invariant checks.
- **Invariant:** a condition that must hold throughout the run; the time it's first broken is recorded.
- **Semantic criteria:** checks on the design's meaning: components present and their properties, guarded paths, placement, fanout, storage fit, unjustified components, state transitions and sequences.
- **Runtime state criteria:** grading from the per-request state timeline, such as a replication step or a commit outcome.
- **Justification grading:** the written reasoning is checked against the graph; a claim about something not in the design fails.
- **Five axes:** topology, scale-fit, simulation, justification and budget.
- **Performance vs correctness:** performance is simulated; correctness is mostly judged from the structure, with a growing share checked at runtime.
- **Dual-topology rule:** a question is properly authored only if its reference design passes and a known gamed design fails.
- **Verdict / evaluation envelope:** the final pass/fail result, plus a replay summary with a checksum so the full trace can be verified later.

**Go deeper:** [[m12-grading-dsl|M12]] · [[question-grading-model-and-anti-gaming]] · [[evaluation-authoring-reference-manual]] · [[runtime-semantic-criteria]] · [[five-orthogonal-axes-resist-gaming]] · [[dual-topology-rule-defines-a-good-question]] · [[performance-correctness-boundary]] · [[runtime-state-transitions-grade-modeled-correctness]]

### Chapter 25. Authoring tools
- **Question Studio:** a visual editor for building and checking questions.
- **Service Builder / custom node:** learner-built components. They're graded by their underlying component type, and only fields that actually affect the simulation count.

**Go deeper:** [[m15-newton-integration|M15]] · [[visual-question-authoring-studio-plan]] · [[custom-node-and-service-definition-spec]] · [[capstone|Capstone]]

## Part VIII - The product surface

### Chapter 26. Canvas and results UI
- **Canvas:** where the topology is drawn and edited.
- **Properties panel:** a node's settings, generated from its traits.
- **Metric lens:** which metric the canvas colours nodes and edges by.
- **Traffic animation:** request dots flowing along edges, driven by the real edge-flow events from the run.
- **Request trace overlay:** one request's path highlighted on the canvas.
- **Results tray:** run metrics, grade and SPOF warnings.
- **Scenario bar:** switching between scenarios.
- **Budget meter:** spend so far against the budget.

**Go deeper:** [[m14-frontend|M14]] · [[canvas-visualization-and-ux-simplification]] · [[traffic-animation-taxonomy]]

### Chapter 27. Newton integration
- **Django export / Newton rows:** how a question package becomes Newton platform assignments.
- **Game playground:** the embedded question-playing experience.

**Go deeper:** [[m15-newton-integration|M15]] · [[newton-api-backend-integration]]

---

> [!note] Known gaps (checked against the code)
> - WFQ is accepted as a queue discipline but currently behaves like FIFO.
> - The concept note [[utilization-display-bug]] still describes an open bug; the engine now computes utilization from busy time, so the note looks out of date.
> - The caching concept notes cite [[trait-integration-guide]], which isn't about caching; [[derived-cache-hit-rate-model]] is the real caching spec.
> - Not covered, because they are planned rather than implemented: per-question builder policy and region/AZ/subnet grouping boxes. The 148 component types are covered by family, not one by one.

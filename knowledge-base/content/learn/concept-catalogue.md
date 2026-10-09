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
- **Queue discipline:** the order waiting requests are served in: FIFO, LIFO, priority or WFQ.
- **WFQ (weighted fair queueing):** each request type is a flow, and the node takes turns between waiting flows in proportion to their weights (1 by default, set per type in the Flow weights editor), so one busy type can't starve the others. Each request counts as one unit, so fairness is by request count, not service time.
- **Saturation:** arrivals outpacing service, so the queue grows and latency explodes. A queue can saturate while CPU still looks fine.

**Go deeper:** [[m03-queueing-model|M03]] · [[queue-depth-calculation]] · [[ggck-models-finite-capacity-queues]] · [[queue-saturation-precedes-cpu-saturation]] · [[queue-depth-is-a-leading-indicator-of-latency]]

### Chapter 6. Component types and service time
- **Component type:** one of 131 types in 14 families, each with default behaviour: compute (12), network (17), storage (19), messaging (7), orchestration (13), security (11), observability (9), devops (7), data-infrastructure (5), real-time (6), integration (5), consensus (4), DNS, and auxiliary (13).
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
- **Edge concurrency limit (`maxConcurrentRequests`):** the most requests one edge can carry at once, like a connection limit. Over it, a transfer is refused (`connection_refused`).
- **Link queueing:** an edge is one pipe of `bandwidth` Mbps. A payload holds it for its transmission time, and a transfer that arrives while it is busy waits its turn, so an edge never carries more bytes per second than its bandwidth.
- **Protocol overhead and retransmission:** each protocol adds a fixed cost per request (https 0.5 ms, kafka 2 ms, ...). On a lost packet every protocol except UDP resends (slower, not lost); UDP drops the request.
- **Connection model (opt-in):** an edge can keep a real pool of connections: new ones pay handshake round trips (TCP 1, TLS 1.2 two more or TLS 1.3 one more), keep-alive and persistent connections are reused, TLS resumption shortens later handshakes, and a full pool makes requests wait.
- **HTTP/2 multiplexing:** a gRPC connection carries up to 100 requests at once; an HTTPS (HTTP/1.1) connection carries one, so a full HTTPS pool makes requests queue for a connection.
- **Producer batching (opt-in, Kafka edges):** records wait up to `lingerMs` or until `maxBatchBytes`, then travel as one transfer, buying throughput with a measured batch wait.
- **Per-edge latency breakdown:** each edge reports how its transit splits into propagation, congestion, transmission, link queue, protocol overhead, retransmission, connection wait, handshake and batch wait.
- **Synchronous blocking:** a caller waiting on a slow downstream keeps its worker or connection tied up, which can exhaust connection pools.
- **Location / region:** where a node sits, from an offline location catalogue.
- **Region / AZ / subnet boxes:** grouping boxes on the canvas that nest (subnet in AZ in region). A node inside a box takes its location, and an edge's path type is derived from the boxes its two ends share: same subnet is same-rack, same AZ is same-dc, same region is cross-zone, different regions is cross-region. A path type set on the edge still wins.
- **Geo latency:** extra delay that CDNs, global traffic managers and edge routers add for the distance to the serving region.
- **Protocol session:** connection open and close, HTTP acknowledgement mode, L4 vs L7 behaviour, WebSocket flow control.

**Go deeper:** [[m07-edges|M07]] · [[edge-properties-and-defaults]] · [[latency-is-dominated-by-path-type]] · [[edge-concurrency-caps-inflight-requests]] · [[synchronous-blocking-exhausts-connection-pools]] · [[connector-edges-carry-no-physics]] · [[bandwidth-adds-transmission-and-link-queueing-delay]] · [[tls-1-3-saves-a-round-trip-on-a-new-connection]] · [[http2-multiplexing-removes-head-of-line-waits-at-the-pool]] · [[producer-batching-trades-latency-for-throughput]]

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
- **Client sessions:** `sessions.count` on the source stamps each request with one of N client session ids, so one client's reads and writes share an identity (read-your-writes and monotonic reads need it; sticky routing hashes it).
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
- **Request collapsing (single-flight, opt-in):** only the first miss for a key goes to the store; the others wait at the cache for its answer and share its outcome. It needs keyed requests (a keyspace on the source) and runs in discrete-event runs only.
- **Cache flush:** a chaos fault that empties a cache (a derived LRU loses its contents and re-warms; a declared-rate cache misses everything for the window).

**Go deeper:** [[derived-cache-hit-rate-model]] · [[cache-aside-is-bernoulli-thinning]] · [[cache-stampede-is-a-thundering-herd]] · [[request-collapsing-dedups-inflight-misses]]

### Chapter 16. Storage behaviours
- **Read/write split:** reads and writes get different service times.
- **Read replica:** a read-only copy that adds read capacity; every write still goes to the primary.
- **Replication:** a write waits for its acknowledgement point, replicas can be slightly out of date (bounded staleness), and traffic is rejected while a failover is in progress.
- **Quorum write:** acknowledged after a majority of replicas confirm, slower but more durable.
- **Replica cluster state machine:** each replica moves between leader, follower and failed.
- **Consistency model (opt-in):** on a replicated database, `eventual`, `monotonic-reads`, `read-your-writes` or `strong`. Followers apply each write after the replication lag; a follower read waits for catch-up as its model requires, and that wait is measured latency.
- **Stale read / session anomalies:** counted from real data versions: `consistency.staleReads`, `consistency.readYourWritesViolations`, `consistency.monotonicReadViolations`.
- **Linearizability check:** a bounded single-key check (100 operations per key, 200 keys) over the recorded history; anything beyond the bound is reported as not checked, never as passed.
- **Row lock:** writes to the same key run one at a time, so effective concurrency for that key is 1.
- **Lock lease:** a time-limited lock on a key, with rejection when taken, expiry, and an optional fencing token that stops a stale holder from writing.
- **CQRS:** separate read and write paths, so heavy writes don't hurt read latency.
- **Tiered retrieval:** reading from cold or archive storage takes seconds to minutes.
- **Log replay / event sourcing:** state is rebuilt by replaying the log, so reads slow down as the log grows unless a snapshot limits how far back they go.
- **Scatter-gather (fan-out query):** a query sent to N shards finishes only when the slowest responds, so the latency tail grows with N.
- **Sharding:** splitting data across shard nodes by key.
- **ID allocation:** block allocation (pre-reserved ranges) vs per-request allocation, each with a different service-time cost.

**Go deeper:** [[replication-quorum-state-machine-walkthrough]] · [[id-sequence-generator-node]] · [[replication-scales-reads-not-writes]] · [[quorum-writes-trade-latency-for-durability]] · [[row-locks-serialize-writes]] · [[cqrs-splits-read-and-write-paths]] · [[read-your-writes-costs-a-catch-up-wait-on-replica-reads]] · [[eventual-consistency-makes-stale-reads-countable]]

### Chapter 17. Messaging and streams
- **Ack-and-release:** a queue acknowledges the producer as soon as it stores the message; the consumer processes it separately.
- **Broadcast fanout (pub/sub):** one published message is delivered to every subscriber.
- **Consumer group:** within a group each message goes to exactly one member; every group gets every message.
- **Stream broker:** Kafka-like: the producer is acknowledged at append, and each partition is always read by the same consumer.
- **Consumer lag:** a backlog that builds when consumers drain slower than messages arrive.
- **Windowing:** fixed back-to-back time windows (tumbling windows), each producing one combined result.
- **Batching:** processing N items together spreads a fixed per-batch cost across them, at the price of waiting for the batch to fill.
- **Change-stream ordering (opt-in):** changes are numbered per entity; a consumer that applies an older change after a newer one is counted as an ordering violation. `per-partition` or `per-key` consumers remove violations at a measured throughput cost.

**Go deeper:** [[consumer-groups-deliver-once-per-group]] · [[fanout-on-write-vs-on-read]] · [[celebrity-workload-breaks-fanout-on-write]] · [[per-entity-order-needs-keyed-ordered-consumers]]

### Chapter 18. Latency-cost behaviours
- **External latency:** a call to a third-party provider takes time the caller can't control.
- **Crypto cost:** encrypting, signing and verifying add latency per operation, often with a quota.
- **Token cost:** LLM response time scales with the number of tokens generated.
- **Inspection cost:** a WAF or policy check adds latency to every request and blocks a fraction of them.
- **Capacity limit:** a rolling ops-per-second ceiling on a link or device (IOPS, NAT ports, line rate); anything above it is rejected.
- **Cold start:** extra latency the first time a scaled-to-zero serverless function runs.
- **Connection capacity:** a connection server's limit on open connections, with refused overflow. Held connections pin RAM, heartbeats take CPU from request work, and a push writes one message to every connected recipient.
- **Telemetry sink (opt-in):** a log, metric or trace collector that drops events past an ingest ceiling or a full buffer, counted and never failing the caller; head sampling keeps unexported events away.

**Go deeper:** [[node-capability-matrix]] · [[connection-tier-capacity]] · [[held-connections-cost-ram-and-cpu-while-idle]] · [[telemetry-sinks-drop-events-instead-of-failing-requests]]

### Chapter 19. Admission control and correctness guards
- **Rate limiter:** a per-key request limit using token-bucket (the default), fixed-window (which deliberately allows up to twice the limit across a window boundary) or sliding-window.
- **Breach check (`rateLimit.breaches`):** a count of how often the limit was actually exceeded.
- **Idempotency dedup:** retried writes are caught within a time window, and a commit record tracks each one through intent → confirmed → unknown → replay-blocked.
- **Reservation store / oversell:** a record of which request claimed each resource first, so double-booking is counted in `reservations.oversells`.

**Go deeper:** [[rate-limiter-admission-and-breach-model]] · [[rate-limiter-lab-lesson]] · [[contended-inventory-and-oversell-model]]

### Chapter 20. Failure and resilience
- **Failure mode:** how a failed node behaves: `reject` (refuses instantly), `blackhole` (requests vanish; the client waits out its timeout), `hang` (fills its queue, then requests vanish) or `degraded` (still serves, slower).
- **Chaos:** failures deliberately injected into a run.
- **Chaos experiment:** a steady state that must hold first, then inject / restore / traffic-spike / verify steps with checks over time windows, then a final check. Presets: cache stampede, database failover, traffic spike, AZ outage; several can be composed with offsets. Verdict: passed, failed, not stable (the steady state never held) or inconclusive (the analytic model ran).
- **Fault domain:** a fault on a Region, AZ or Subnet box fails every component inside it for the window. The traffic source is never failed.
- **Bulkhead:** a cap on how many requests of one compartment (a request type or a tenant key) a node holds at once; over it is a fast `bulkhead_full` rejection.
- **Load shedding:** rejecting new arrivals fast (`load_shed`) while the queue or its estimated delay is over a threshold, so admitted requests stay fast.
- **Cluster scheduling:** on a Kubernetes Cluster node, workload replicas are pods placed on finite machines; a pod that fits nowhere stays pending and adds no capacity, and a failed machine's pods come back only after detection and eviction.
- **Retry with backoff:** the caller retries, waiting longer each time, with optional random jitter. Retries use real capacity, so they can cause retry storms.
- **Circuit breaker:** closed → open → half-open; stops calling a failing downstream so the failure doesn't spread.
- **Health prober:** a health-check manager that watches nodes and marks them unhealthy.
- **Database failover:** a replica is promoted to primary.
- **Autoscaler:** a control loop on the repeating timer that resizes concurrency to hit a utilization target, reacting with a delay after each cooldown.
- **Single point of failure (SPOF):** a node whose loss cuts the traffic source off from part of the system, found from the topology alone.

**Go deeper:** [[request-rejection-behaviour]] · [[state-machines-make-behavior-gradeable]] · [[chaos-experiments-need-a-steady-state-first]] · [[a-fault-domain-fails-everything-inside-it]] · [[pending-pods-add-no-capacity]]

## Part VI - Measuring

### Chapter 21. Metrics
- **Time-weighted metric:** a total over the whole run, not an average of snapshots.
- **Utilization:** total busy time ÷ (`c` × run length).
- **Throughput:** successfully processed requests per second.
- **Error rate / availability:** the share of requests that failed, and the share that succeeded.
- **Latency percentiles (p50, p95, p99):** from histograms. Per-hop p99s can't be added to get the end-to-end p99.
- **Per-node metrics:** arrived, processed, rejected, timed-out and reset counts (each also after warmup); average and peak queue length; service time, queue wait, time in system; throughput, error rate, availability.
- **Post-warmup:** counts that exclude the warmup period.
- **Trace / tracer:** the recorded path each request took, which the canvas can play back. For sampled requests (1% by default) it also keeps one admission record per node visit.
- **Event log:** the stream of engine events. A normal run keeps the first 25,000 and says when the log is partial.

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
- **Builder policy:** a question can allow or forbid the builders, limit runtimes, node classes and trait packs, cap the number of definitions and lock them after the first run. Breaking it never blocks a run; it fails a `builder-policy` grading row.

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
- **Playback speed:** 0.5x to 10x of simulated time, or Max (the default). Speed changes pacing only, never results.
- **Request debugger:** steps through one traced request in five views (Rail, Sequence, Stack Trace, State Machine, Filmstrip), plus the Node Intake Lens (the real admission order) and Path Diff (actual vs expected path).
- **Event Log tab:** Table, Requests, Nodes, Incidents and Waterfall views with a query filter (`node:`, `status:`, `reason:`, AND / OR / NOT).
- **In-app terminal:** a command line in the bottom dock (Ctrl+\`) with IOS-style modes; the same commands run headless as `sim shell`.
- **TopologyJSON import / export:** the design as a validated JSON document, with a viewer that edits it in place.

**Go deeper:** [[m14-frontend|M14]] · [[canvas-visualization-and-ux-simplification]] · [[traffic-animation-taxonomy]]

### Chapter 27. Newton integration
- **Django export / Newton rows:** how a question package becomes Newton platform assignments.
- **Game playground:** the embedded question-playing experience.

**Go deeper:** [[m15-newton-integration|M15]] · [[newton-api-backend-integration]]

---

> [!note] Known gaps (checked against the code)
> - Builder policy and Region / AZ / Subnet outages are implemented now (October 2026) and listed above. Still not modelled: a zone that is slow or lossy rather than down, partitions between zones that are both up, multi-key transactions, TTL expiry in the derived cache, and CDC capture lag. The 131 component types are covered by family, not one by one.

# Node Capability Matrix

> **What this is.** A complete audit of every component type the simulator knows
> about (**130** types), classifying each by how much *real, distinct simulation
> behavior* it has today versus running on the generic model. It doubles as the
> V2/V3+ roadmap. Three questions are answered for every node:
>
> 1. **Which trait** does it need, and is that trait already in the system?
> 2. **Why does this node need that trait** (the per-node rationale column)?
> 3. **What config field drives it and what does it do** (the config column)?
>
> The **Trait Glossary** below explains *why each trait exists at all*.

## How a node behaves in the engine

Every node runs the **generic model** unless a capability trait overrides it:

- a **queue** (workers = concurrency, capacity = backlog) →
- a **processing-time distribution** (constant / exponential / log-normal / …) →
- **edge latency** to the next hop.

That baseline gives saturation, queueing delay, and timeouts. A node behaves
*distinctly* only when a **capability trait** in `src/engine/traits/` targets its
`componentType`. There are **15 live trait modules** today. The per-node rows below
are the source of truth for modeled coverage; this matrix is updated incrementally
as traits ship.

### Config convention

Config fields live under **`sim.*`** on the node (e.g. `sim.cacheHitRate`), plus
the typed sections `queue.*`, `processing.*`, `resources.*`, `resilience.*`,
`scaling.*`, `slo.*`. Keys marked **(current)** already exist; all others are proposed.

### Legend

- 📦 available in the drag-in library · **Trait markers:** ✅ exists & applied ·
  ➕ trait exists, just extend its `appliesTo` (no new code) · 🔧 new trait to build ·
  ⚠ code exists but not wired in.
- A node is **Modeled** iff its Trait starts with ✅; everything else is **Generic**
  (generic queue + processing model, differentiated only by config/seed or grading).
- 🟢 in a Why cell marks a **source** node (generates load, not a processor).

---

## Trait Glossary - what each trait is and why it exists

The "why it exists" is the reason the *simulator* needs the trait: without it, some
design decision can't be *felt* in the physics (it would be graded only by rubric
text, or not at all), so students couldn't learn it by running the sim.

### Existing traits (✅ - live today)

| Trait | What it models | Why it exists |
|-------|----------------|---------------|
| `cache` | `cacheHitRate` hit/miss: a hit terminates fast, a miss forwards to origin | Caching is the #1 lever for read-heavy systems. Without a hit/miss model, "put a cache in front of the hot store" can't reduce load in the sim - the core reinforcing-loop lesson. |
| `healthAware` | Routes requests away from unhealthy targets (+ round-robin) | Real load balancers shed dead backends. Needed so removing redundancy or health checks visibly hurts availability. |
| `contentRouting` | Attribute/path-based routing via edge `condition` (`request.type === …`) | Separating hot/cold paths (reads vs writes) is fundamental. The sim needs typed routing so the read/write **ratio actually changes where traffic goes**. |
| `rateLimiter` | Token-bucket admission; rejects requests over the limit | Protects downstreams from overload; lets questions test admission control / back-pressure at the edge. |
| `readOnly` | Read-only replica routing | Read replicas are the canonical read-scaling pattern; the sim must let reads land on a replica. |
| `readWriteSplit` | Reads → replica, writes → primary (`readLatencyMs`/`writeLatencyMs`) | So "add a read replica" genuinely offloads the primary instead of being cosmetic. |
| `ackAndRelease` | Async ack: a queue holds a request until a consumer releases it | Queues decouple producers from consumers. Needed so async designs absorb spikes a synchronous path collapses under. |
| `consumerLag` | Consumer lag / backlog growth when drain < arrival | Lag is *the* health metric for streams. Needed so under-provisioned consumers visibly fall behind. |
| `coldStart` | Cold-start latency on scale-from-zero (`coldStartLatencyMs`, `idleTimeoutMs`) | Serverless's defining tradeoff. Needed so "just use Lambda" isn't free under bursty load. |
| `circuitBreaker` | Trips open on failures, sheds load (`resilience.circuitBreaker.*`) | Stops cascading failure. The backbone of resilience / chaos questions. |
| `keyBasedRouting` | Routes each key by hash to a shard | Sharding / consistent-hashing is how you scale state. Needed so key distribution (and skew) matters. |
| `dnsRoutingPolicy` | DNS-based resolution / steering | Multi-region steering and failover start at DNS. |
| `storageProfile` | Store-specific service-time curves by operation class | Makes "pick the right datastore" visible in runtime physics instead of only in grading text. |
| `broadcastFanout` | Deliver one publish to every downstream subscriber | Pub/sub and broker fanout must be one-to-many at runtime, not merely structurally. |
| `idempotencyDedup` | Time-window keyed dedup **plus** a durable commit-outcome journal (intent → confirmed → unknown → replay-blocked) and modeled external reconciliation probes | Lets retried writes stop at a guard, and makes "did my commit actually happen?" a gradeable `commit-outcome` state instead of prose. |
| `retryBackoff` | Caller-owned retry budget with exponential backoff and optional jitter | Retries are a real source of latency amplification and retry storms; they must consume actual caller capacity instead of living only in prose. |
| `lockLease` | Per-key lease acquisition, contention rejection, TTL expiry, and optional fencing token | Mutual exclusion is the core physics behind ticketing / inventory contention; this makes lock-based designs visible in the run rather than only in justification. |
| `reservationStore` | Atomic per-key reserve at a single authority; oversell when two independent authorities commit the same key | No-double-book contention: a double-book is `reservations.oversells > 0`, gradeable at runtime. |
| `replication` (`storage.replication-boundary`) | Primary/quorum write ack, deterministic leader promotion, bounded replica-read staleness, failover-unavailability window (via `ReplicaCluster`) | Makes quorum loss, leader failover, and stale reads observable `replication`-scope states instead of justify-only claims. |
| `streamBroker` (`stream.partitioned-broker`) | Partition assignment, one-delivery-per-consumer-group, offset commits, retention expiry, replay, rebalancing, broker availability (via `ReplicatedLog`) | Streaming correctness (consumer groups, offsets, retention) becomes gradeable `broker`-scope state, not prose. |
| `protocolSession` (`protocol.session`) | Connection open/close, HTTP ack mode, L4-vs-L7 policy, WebSocket flow-control rejection | The transport/session layer between machines becomes a gradeable `protocol`-scope distinction. |
| `geoLatency` (`cdn`/`global-traffic-manager`/`edge-router`) | Flat per-request region/PoP propagation penalty | Rewards locality — an edge/multi-region design beats always crossing the map. |
| `externalLatency` (`third-party-api-connector`/`payment-gateway`/`third-party-auth`/`webhook-gateway`) | Round-trip latency of an external provider call | Makes a slow dependency a real blast radius, especially paired with retries. |
| `tieredRetrieval` (`archive-storage`/`object-storage`) | Cold-tier retrieval latency (seconds–minutes) | "Just archive it" now has a consequence; you can't serve hot reads from cold storage. |
| `cryptoCost` (`kms-storage`) | Per-op encrypt/verify/sign latency | A KMS on the hot path becomes a measurable bottleneck, not a free box. |
| `tokenCost` (`llm-gateway`) | Latency ∝ output tokens (ms/token × tokens) | LLM serving's defining cost model — a chatty completion is slow regardless of throughput. |
| `inspectionCost` (`network-policy`/`policy-engine`) | Per-request scan latency + probabilistic block rate | A WAF/policy hop adds latency and can drop traffic — not free. |
| `capacityLimit` (`nat-gateway`/`block-storage`/`edge-router`/`transit-gateway`/`vpn-gateway`/`high-perf-nic`) | Rolling-window ops/sec ceiling → rejects excess | Saturates the *link* (IOPS, NAT ports, line rate) independently of CPU. |
| `batching` (`batch-worker`/`gpu-node`) | Formation-wait latency + amortized (fixedCost ÷ batchSize) | The batching tradeoff: pay latency to buy throughput. |
| `logReplay` (`event-sourcing-store`) | Read latency ∝ events-since-snapshot, grows with the log | Makes snapshot cadence a real, gradeable decision. |
| `windowing` (`streaming-analytics`) | Processing-time tumbling windows: accumulate on arrival, emit a per-window aggregate on the recurring timer | First consumer of the `onTick` timer hook — one output per window, not per event. |
| `fanoutQuery` (`search-service`/`search-index`) | Scatter-gather tail latency as the max of N per-shard samples (grows ≈ ln N) | Distributed-search tail: why more shards ≠ always faster. |
| `autoscaler` (`microservice`/`serverless-function`) | A utilization-target control loop on `onTick` that resizes effective concurrency every cooldown (reaction-lagged) | Capacity follows demand — via the `onTick` timer + the new **dynamic-capacity** resize; scaling still costs money. |

### Engine hooks a trait can use

Traits are not arrival-only. The `NodeBehaviourTrait` interface exposes:
`beforeArrival` · `beforeRouting` · `filterRoutes` · **`afterTerminal`** (per-request
completion callback — used by `streamBroker` offset-commit and `idempotencyDedup`
reconciliation) · **`onTick` + `tickIntervalMs`** (a node-scoped recurring timer, fired
by deterministic SYSTEM-priority `trait-tick` events; first used by `windowing`, and the
substrate for autoscaling and periodic sampling).

### Wired and working (previously listed as gaps — corrected)

- **Health probing / detection latency** — a `health-check-manager` node runs periodic
  probes (`handleHealthProbe` re-arms the timer), debounces via `evaluateProbe`, and
  `isNodeHealthy` feeds `healthAwareRouting` so traffic reroutes only *after* detection.
  `healthProber.ts` is wired into the engine, not an unwired file.
- **Node failure / fault injection (engine)** — `topology.faults` → `node-failure` /
  `node-recovery` events → `node.fail()/recover()` (connection resets, status-timeline
  windows, replication + stream rebalancing). The remaining gap is a *canvas UI* to
  author faults; the engine path is complete.

### Proposed new traits (🔧 - ordered by leverage)

| Trait | What it models | Why it exists |
|-------|----------------|---------------|
| `computeContention` | CPU-core / thread-pool saturation + boot delay | Real services are bound by cores and pools, not an abstract "worker" count. Needed for accurate sizing and saturation. |
| `consistencyModel` | one vs quorum vs strong → latency & staleness | The central distributed-data tradeoff; needed so stronger consistency costs latency. |
| `persistentConnFanout` | Millions of long-lived connections + push fan-out | Real-time systems have a fundamentally different concurrency model from request/response. |
| `telemetrySink` | Ingest cap + sampling + query cost (off request path) | Observability has its own load; needed to model sampling tradeoffs and telemetry back-pressure. |
| `scheduler` | Cluster placement / bin-packing (autoscaling itself now ships as `autoscaler`) | Multi-node scheduling remains; single-node autoscale is done. |
| `changeStream` | CDC capture lag + ordering | Data-pipeline latency and ordering guarantees. |
| `requestMix` (extend source) | Typed traffic weights + payload sizing on the source | So read/write ratios and payload sizes actually drive routing and bandwidth. |

---

## Full matrix by category

Columns: **Node · 📦 · Trait · Why this node needs it · Config input → behavior.**

### Compute

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `api-endpoint` | 📦 | ✅`source.workload` +🔧`requestMix` | 🟢 It's the traffic origin - its pattern & mix define the load everything else must survive | `sim.requestMix[]` → typed traffic; `sim.payloadBytes`; `sim.closedLoop`+`sim.thinkTimeMs` |
| `microservice` | 📦 | ✅`retryBackoff` +🔧`computeContention` | Stateless handlers now express real caller-owned retries, but still saturate on abstract workers rather than explicit cores/threads | `resilience.retry.*`, future `sim.cpuBoundRatio`, `sim.threadPool`, `sim.dependencyFanout` |
| `batch-worker` | 📦 | ✅`retryBackoff` +🔧`batching` | Workers often own retry budget as well as batch size; retries now consume real worker capacity while true batching remains future work | `resilience.retry.*`, future `sim.batchSize`, `sim.prefetch`, `sim.parallelism` |
| `sidecar` | 📦 | ✅`circuitBreaker` +✅`retryBackoff` | Proxies every call; breakers protect the mesh and retries now re-enter the caller instead of being prose-only | `resilience.circuitBreaker.*`, `resilience.retry.*`, `sim.proxyOverheadMs`, `sim.mtlsMs` |
| `serverless-function` | 📦 | ✅`coldStart` +✅`retryBackoff` | Scales from zero and can now own retried downstream calls with real backoff cost | `sim.coldStartLatencyMs`,`sim.idleTimeoutMs`,`sim.maxConcurrency`, `resilience.retry.*` |
| `faas-background` | | ➕`coldStart` +🔧`retryBackoff` | Event-triggered and retried async - same cold-start + retry concerns | `sim.triggerBatch`, `resilience.retry.*`, `sim.coldStartLatencyMs` |
| `container` | | 🔧`computeContention` | Hard CPU/memory limits throttle it before the queue does | `resources.cpu/memory`, `sim.restartOnCrash` |
| `vm-instance` | | 🔧`computeContention` | Slow to boot, so scale-out lags demand | `sim.bootMs`, `sim.noisyNeighborVariance` |
| `edge-compute` | 📦 | 🔧`geoLatency` | Runs at PoPs; distance to the user dominates its latency | `sim.popLatencyMs`, constrained `resources.*` |
| `gpu-node` | | 🔧`batching` | Efficient only when inference is batched; VRAM caps concurrency | `sim.batchWindowMs`+`sim.maxBatch`, `sim.vramMB`, `sim.modelLoadMs` |
| `auth-service` | 📦 | ✅`retryBackoff` +➕`cache` | Auth hops now express retry load amplification; a token cache is still the main missing differentiated path | `resilience.retry.*`, future `sim.tokenVerifyMs`, `sim.tokenCacheHitRate` |
| `search-service` | 📦 | ✅`retryBackoff` +✅`fanoutQuery` | Search callers retry real downstream failures and now pay scatter-gather tail latency (max of N shard samples) | `resilience.retry.*`, `sim.shardCount`+`sim.perShardLatencyMs` → `fanoutQueries`/`shardsQueried` |

### Network & Edge

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `load-balancer` | 📦 | ✅`healthAware` | Its whole job is steering traffic away from unhealthy backends | `sim.sticky`, `sim.sslTerminationMs`, `sim.drainMs` |
| `load-balancer-l4` | | ✅`healthAware`+`protocolSession` | Pins flows by connection; the L4 policy + session lifecycle (TCP/connection state) is now modeled; can exhaust NAT ports at scale | `sim.flowHash`, `sim.natPorts`, `sim.sessionProtocol` → `protocol`-scope states |
| `load-balancer-l7` | | ✅`contentRouting`+`healthAware`+`protocolSession` | Routes on headers/paths, terminates TLS, and now models the L7-vs-L4 distinction, HTTP ack mode, and WebSocket flow-control rejection | `sim.tlsTerminationMs`, `sim.headerRouteCostMs`, `sim.sessionProtocol` → `protocol`-scope states + `protocol*` counters |
| `global-traffic-manager` | | 🔧`geoLatency` | Steers each user to the nearest healthy region | `sim.geoSteering`+`sim.regionLatencyMs[]`, `sim.failoverRegion` |
| `edge-router` | 📦 | 🔧`capacityLimit` | Spreads flows across paths; bounded by link capacity | `sim.ecmpPaths`, `sim.routeLookupMs` |
| `nat-gateway` | 📦 | 🔧`capacityLimit` | Finite source ports - exhaustion is a classic outage | `sim.maxPorts` → errors, `sim.connTrackMs` |
| `transit-gateway` | | 🔧`capacityLimit` | Bandwidth-capped interconnect between networks | `sim.bandwidthMbps` |
| `vpn-gateway` | 📦 | 🔧`capacityLimit` | Encryption + tunnel bandwidth cap throughput | `sim.encryptMsPerKB`, `sim.tunnelBandwidthMbps` |
| `cdn` | 📦 | ✅`cache` +🔧`geoLatency` | Absorbs read traffic at the edge; only misses hit origin | `sim.ttlMs`+`sim.invalidationRate`, `sim.popLatencyMs`, `sim.dynamicRatio` |
| `api-gateway` | | ✅`contentRouting`+`healthAware`+`rateLimiter`+`protocolSession` | The policy choke point - auth, routing, keyed rate limits (token-bucket/fixed-window/sliding-window + breach oracle), and session/protocol policy all live here | `sim.authMs`, `sim.transformMs`, `sim.algorithm`+`sim.limit`+`sim.windowMs`+`sim.rateLimitKeyField`, `sim.sessionProtocol` → `rateLimit.breaches` + `protocol`-scope states |
| `service-mesh` | 📦 | ✅`circuitBreaker` +✅`retryBackoff` | Mesh traffic can now both fail-fast and retry with real backoff cost; richer mesh-specific policy remains future work | `resilience.circuitBreaker.*`, `resilience.retry.*`, `sim.sidecarLatencyMs`, `sim.mtlsMs` |
| `ingress-controller` | | ✅`contentRouting`+`healthAware` | Cluster entry point - TLS + path routing cost | `sim.tlsMs`, `sim.rewriteCostMs`, `sim.perRouteLimit` |
| `reverse-proxy` | | ✅`cache`+`healthAware` | Caches and buffers in front of an origin | `sim.compressionMs`, `sim.bufferBytes`, `sim.connReuse` |
| `high-perf-nic` | 📦 | 🔧`capacityLimit` | Line-rate throughput with kernel-bypass/offload | `sim.lineRateGbps`, `sim.offload` |
| `network-policy` | | 🔧`inspectionCost` | Evaluates allow/deny per packet (mostly non-runtime) | `sim.evalMs` |
| `routing-rule` | 📦 | ➕`contentRouting` | Matches attributes and forwards - same primitive as content routing | `sim.matchCostMs` |
| `routing-policy` | 📦 | ➕`contentRouting` | Policy-based forwarding decision per request | `sim.policyEvalMs` |

### Storage & Data

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `relational-db` | 📦 | ✅`readOnly`+`readWriteSplit`+`storageProfile`+`replication` | Reads scale on replicas, store-fit latency is visible, and (with `replicationEnabled`) primary/quorum ack, leader promotion, replica-read staleness, and a failover window are modeled | `sim.readLatencyMs`, `sim.writeLatencyMs`, `sim.storageReadMs`/`sim.storageWriteMs`, `sim.replicationEnabled`+`sim.writeAckPolicy`+`sim.replicaMembers`+`sim.replicationLagMs`+`sim.failoverUntilMs` → `replication`-scope states + `replication*` counters |
| `in-memory-cache` | 📦 | ✅`cache` | Fast only while the working set fits; eviction and hot keys erode hit rate | `sim.maxEntries`+`sim.evictionPolicy`, `sim.hotKeyRatio`, `sim.writeThrough` |
| `nosql-db` | 📦 | ✅`storageProfile`+`replication` +🔧`consistencyModel` +➕`keyBasedRouting` | Scales by sharding; the runtime reflects read/write/query/scan costs and (with `replicationEnabled`) quorum ack, leader promotion, and replica staleness, while strict consistency and hot partitions remain future work | `sim.storageReadMs`/`sim.storageWriteMs`/`sim.storageQueryMs`/`sim.storageScanMs`, `sim.replicationEnabled`+`sim.writeAckPolicy`+`sim.consensusProtocol`, `sim.shardCount` → `replication`-scope states |
| `kv-store` | 📦 | ✅`storageProfile` | Point get/put with hot-key risk; the runtime now makes scans materially more expensive than point lookups | `sim.storageReadMs`, `sim.storageWriteMs`, `sim.storageScanMs`, `sim.ttlMs`, `sim.hotKeyRatio` |
| `time-series-db` | 📦 | ✅`storageProfile` | Write-optimized append + compaction; the runtime now distinguishes append/ingest from heavier reads and scans | `sim.storageReadMs`, `sim.storageQueryMs`, `sim.storageScanMs`, `sim.storageIngestMs` |
| `columnar-db` | | 🔧`storageProfile` | Scans huge column ranges; partition pruning is everything | `sim.scanRowsPerSec`, `sim.compressionRatio`, `sim.partitionPruning` |
| `object-storage` | 📦 | ✅`storageProfile` +🔧`tieredRetrieval` | High-latency, high-throughput blobs; the runtime now exposes a distinct store profile even before cold-tier retrieval semantics ship | `sim.storageReadMs`, `sim.storageWriteMs`, `sim.storageScanMs`, `sim.storageIngestMs`, `sim.coldTierMs` |
| `block-storage` | | 🔧`capacityLimit` | An IOPS/throughput-capped volume | `sim.iops`+`sim.throughputMBps`, `sim.latencyMs` |
| `distributed-file-system` | | 🔧`storageProfile` | Metadata server + replication shape latency | `sim.replicationFactor`, `sim.metadataMs`, `sim.streamMBps` |
| `search-index` | 📦 | ✅`storageProfile` +🔧`fanoutQuery` | Scatter-gather over shards; the runtime now distinguishes query-heavy search traffic from ingest and generic reads before shard fanout ships | `sim.storageReadMs`, `sim.storageQueryMs`, `sim.storageIngestMs`, `sim.refreshLagMs` |
| `graph-db` | 📦 | ✅`storageProfile` | Traversal cost explodes on supernodes; the runtime now gives graph-style queries a distinct service-time profile | `sim.storageReadMs`, `sim.storageWriteMs`, `sim.storageQueryMs`, `sim.maxDepth`, `sim.supernodeThreshold` |
| `vector-db` | 📦 | ✅`storageProfile` | ANN search trades recall for latency; the runtime now exposes separate query/ingest/write curves | `sim.storageReadMs`, `sim.storageWriteMs`, `sim.storageQueryMs`, `sim.storageIngestMs` |
| `data-warehouse` | 📦 | ✅`storageProfile` | MPP scans; the runtime now makes large scans and analytics materially different from point-style reads | `sim.storageReadMs`, `sim.storageQueryMs`, `sim.storageScanMs`, `sim.resultCacheHitRate` |
| `data-lake` | 📦 | ✅`storageProfile` | Cheap scans over partitioned object files, schema-on-read; the runtime now reflects those scan-heavy access patterns | `sim.storageReadMs`, `sim.storageQueryMs`, `sim.storageScanMs`, `sim.storageIngestMs` |
| `archive-storage` | | 🔧`tieredRetrieval` | Cold - retrieval takes minutes, not milliseconds | `sim.retrievalMs`, `sim.minDurationMs` |
| `schema-registry` | | ➕`cache` | Hot lookup on the write path - cache it or it bottlenecks | `sim.lookupCacheHitRate`, `sim.compatCheckMs` |
| `cdc` | | 🔧`changeStream` | Streams DB changes with capture lag + ordering | `sim.captureLagMs`, `sim.throughputRps`, `sim.ordered` |
| `backup-service` | | 🔧`batching` | Throughput-bound snapshot job with RPO/RTO | `sim.snapshotMBps`, `sim.rpoMs`/`sim.rtoMs` |
| `kms-storage` | | 🔧`cryptoCost` | Key ops are latency + quota bound | `sim.cryptoMs`, `sim.opQuotaPerSec` |

### Messaging & Streaming

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `queue` | 📦 | ✅`ackAndRelease` | Decouples producers from consumers; ack/visibility/DLQ define delivery | `sim.visibilityTimeoutMs`, `sim.dlqAfter`, `sim.ordering=fifo`, `sim.prefetch` |
| `stream` | 📦 | ✅`streamBroker` + `consumerLag` | A partitioned, replayable log: partition assignment, one-delivery-per-group, offset commits, retention expiry, replay, rebalancing, availability — plus lag as the health signal | `sim.partitions`, `sim.consumerGroups`, `sim.retentionMs`, `sim.replay` → `broker`-scope states + `stream*` counters |
| `message-broker` | 📦 | ✅`broadcastFanout` | One publish now reaches every downstream subscriber instead of silently choosing one route; groups and guarantees remain future work | `routingStrategy=broadcast` (runtime), future `sim.consumerGroups`, `sim.deliveryGuarantee` |
| `pub-sub` | 📦 | ✅`broadcastFanout` | Broadcast delivery is now modeled at runtime; per-subscription filters are still future work | `routingStrategy=broadcast` (runtime), future `sim.subscriptionFilter`, `sim.retentionMs` |
| `event-bus` | | ✅`broadcastFanout` | Rule-routed broadcast now has one-to-many runtime delivery even before richer rule/filter semantics ship | `routingStrategy=broadcast` (runtime), future `sim.routingRules[]` |
| `event-sourcing-store` | | 🔧`logReplay` | Append-only; rebuilding state means replaying the whole log | `sim.appendMs`+`sim.replayCostPerEvent`, `sim.snapshotEvery` |
| `task-queue` | | ✅`retryBackoff` | Scheduled work now has caller-owned retries/backoff; priority/scheduling semantics are still future work | `resilience.retry.*`, future `sim.scheduleDelayMs`, `sim.priorityLevels`, `sim.dlqAfter` |

### Consensus & Coordination

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `distributed-lock` | 📦 | ✅`lockLease` | Serializes access with real per-key lease acquisition, contention rejection, and TTL expiry | `sim.lockKeyField`, `sim.acquireMs`, `sim.leaseMs`, `sim.fencing` |
| `etcd-consul-kv` | | 🔧`consistencyModel` | Quorum writes are slow but consistent; leader failover pauses writes | `sim.quorumWriteMs`, `sim.leaderFailoverMs`, `sim.watchFanout` |
| `leader-election` | | 🔧`lockLease` | Election + failover windows create unavailability | `sim.electionMs`, `sim.failoverMs` |
| `coordination-service` | | 🔧`consistencyModel` | Consensus rounds add latency to every coordinated op | `sim.consensusRoundMs` |

### Auxiliary

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `sharding` | 📦 | ✅`keyBasedRouting` | Routes each key to its shard; skew makes a hot shard | `sim.shardCount`, `sim.rebalanceMs`, `sim.hotShardRatio` |
| `hashing` | 📦 | ✅`keyBasedRouting` | Consistent-hash placement; virtual nodes smooth skew | `sim.virtualNodes`, `sim.ringSkew` |
| `rate-limiter` | 📦 | ✅`rateLimiter` | Keyed admission control with a selectable algorithm (token-bucket / fixed-window / sliding-window) and a cross-node breach oracle that catches uncoordinated-limiter over-admission and the fixed-window edge-doubling bug | `sim.algorithm`, `sim.limit`, `sim.windowMs`, `sim.rateLimitKeyField`, `sim.maxTokens`/`sim.refillRatePerSecond` → `rateLimit.breaches`/`.admitted`/`.rejected` |
| `idempotency-manager` | 📦 | ✅`idempotencyDedup` | Dedupes retried writes by key, and (with the commit journal) records intent → confirmed → unknown → replay-blocked plus modeled external reconciliation for the unknown-outcome case | `sim.dedupKeyField`, `sim.storeLookupMs`, `sim.dedupWindowMs`, `sim.externalReconciliation` → `idempotency` + `commit-outcome` scopes |
| `circuit-breaker-controller` | 📦 | ✅`circuitBreaker` | A dedicated breaker node now trips open/half-open/closed at runtime | `resilience.circuitBreaker.*` |
| `throttler` | | ✅`rateLimiter` | Sheds load above a ceiling with the keyed limiter (token-bucket/fixed-window/sliding-window + breach oracle) | `sim.algorithm`, `sim.limit`, `sim.windowMs`, `sim.rateLimitKeyField` → `rateLimit.breaches` |
| `backpressure-controller` | | 🔧`backpressure` | Signals upstream to slow when the backlog is high | `sim.highWatermark`+`sim.signalMs` |
| `shard-node` | 📦 | ➕`keyBasedRouting` | Owns a slice of the keyspace with its own capacity | `sim.capacityRps` |
| `partition-node` | 📦 | ➕`keyBasedRouting` | Routes by partition key to one partition | `sim.partitionKey`+`sim.partitions` |
| `request-tracking` | | 🔧`telemetrySink` | Adds trace-context overhead on each hop | `sim.traceOverheadMs` |
| `policy-engine` | | 🔧`inspectionCost` | Evaluates a policy per request | `sim.policyEvalMs` |
| `service-mesh-telemetry` | | 🔧`telemetrySink` | Exports telemetry with per-request overhead | `sim.exportOverheadMs` |

### External & Integration

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `third-party-api-connector` | | ✅`rateLimiter` +✅`retryBackoff` +🔧`externalLatency` | External dependencies now have real keyed quota (token-bucket/fixed-window/sliding-window + breach oracle) and backoff behavior even before richer provider-latency semantics ship | `resilience.retry.*`, `sim.algorithm`+`sim.limit`+`sim.windowMs`+`sim.rateLimitKeyField`, `sim.maxTokens`, `sim.refillRatePerSecond`, future `sim.externalLatencyMs` → `rateLimit.breaches` |
| `llm-gateway` | 📦 | ✅`retryBackoff` +🔧`tokenCost` | AI gateways can now retry retryable downstream/provider failures with real backoff, but token-shaped latency is still missing | `resilience.retry.*`, future `sim.msPerToken`+`sim.outputTokens`, `sim.streaming`, `sim.providerRateLimit` |
| `payment-gateway` | | ✅`retryBackoff` +🔧`externalLatency` | Payment calls now own real retry budgets; richer provider/ledger semantics remain future work | `resilience.retry.*`, future `sim.externalLatencyMs`, `sim.idempotencyKey` |
| `webhook-gateway` | | ✅`retryBackoff` +🔧`broadcastFanout` | Webhook delivery now has real retry/backoff cost; per-endpoint broadcast semantics are still future work | `resilience.retry.*`, future `sim.backoff`, `sim.fanoutTargets` |
| `third-party-auth` | | 🔧`externalLatency` +➕`cache` | OAuth round-trips; cache tokens to avoid them | `sim.oauthRoundTrips`+`sim.roundTripMs`, `sim.tokenCacheHitRate` |

### DNS & Certs

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `internal-dns` | | ✅`dnsRoutingPolicy` +➕`cache` | Resolution is cached by TTL; misses add a round-trip | `sim.ttlMs`+`sim.cacheHitRate`, `sim.negativeCacheMs` |
| `dns-authoritative-server` | | ➕`cache` | Answers queries; TTL caching offloads it | `sim.queryMs`, `sim.ttlMs` |
| `certificate-distro` | | 🔧`batching` | Distributes certs on a schedule | `sim.distributeMs` |

### Orchestration & Infra

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `service-registry` | 📦 | ➕`cache` | Hot discovery lookup - a client-side cache decides if it's a bottleneck | `sim.lookupMs`+`sim.cacheTtlMs` |
| `config-store` | 📦 | ➕`cache` | Read-heavy config with watch/notify - cache reads | `sim.readCacheHitRate`, `sim.watchFanout` |
| `secrets-manager` | 📦 | ➕`cache` | Fetched on startup/rotation; cache + TTL matter | `sim.fetchMs`+`sim.cacheTtlMs`, `sim.rotationMs` |
| `kubernetes-cluster` | | 🔧`scheduler` | Placement/bin-packing/autoscale have real reaction time | `sim.scheduleMs`, `sim.binPacking`, `scaling.*` |
| `cluster-autoscaler` | | 🔧`scheduler` | Scale reaction time + cooldown govern how fast capacity follows demand | `scaling.scaleUpThreshold`+`scaling.cooldown` |
| `orchestrator-scheduler` | | 🔧`scheduler` | Scheduling latency + queueing before work runs | `sim.scheduleMs` |
| `container-registry` | | ➕`cache` | Image pulls are bandwidth-bound; a pull-through cache helps | `sim.pullMBps`+`sim.cacheHitRate` |
| `container-runtime` | | 🔧`computeContention` | Container start latency lags scale-out | `sim.startMs` |
| `provisioner` | | 🔧`scheduler` | Provision time delays new capacity | `sim.provisionMs` |
| `tool-registry` | 📦 | ➕`cache` | Agentic tool lookup - hot read path | `sim.lookupMs` |
| `agent-orchestrator` | 📦 | ✅`retryBackoff` +🔧`scheduler` | Agent dispatch now has real retry pressure when downstream calls fail; placement/scheduling latency is still future work | `resilience.retry.*`, future `sim.dispatchMs` |
| `ci-cd-runner` | | 🔧`scheduler` | Off-path pipeline stages with concurrency limits | `sim.stageCount`+`sim.stageMs` |
| `iac-engine` | | - | Off-path apply/plan work, not on the request path | `sim.applyMs` |

### Security & Identity

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `waf` | 📦 | 🔧`inspectionCost` | Inspects every request - cost + block rate + false positives | `sim.inspectMs`+`sim.blockRate`, `sim.falsePositiveRate` |
| `firewall` | 📦 | 🔧`inspectionCost` | Evaluates rules per connection | `sim.ruleEvalMs`, `sim.connTrack` |
| `identity-provider` | | 🔧`externalLatency` +➕`cache` | External auth + federation latency; cache tokens | `sim.authMs`+`sim.federationMs`, `sim.tokenCacheHitRate` |
| `iam-rbac` | | ➕`cache` +🔧`inspectionCost` | Authz check per request; cache decisions | `sim.authzMs`+`sim.policyCacheHitRate` |
| `kms-security` | | 🔧`cryptoCost` | Crypto ops are latency + quota bound | `sim.cryptoMs`+`sim.opQuota` |
| `dlp-inspection` | | 🔧`inspectionCost` | Scans payload bytes for leaks | `sim.scanMsPerKB` |
| `siem` | | 🔧`telemetrySink` | Ingest + query load, off the request path | `sim.ingestRps`+`sim.queryMs` |
| `certificate-authority` | | 🔧`cryptoCost` | Issue/verify are crypto-bound | `sim.issueMs`/`sim.verifyMs` |
| `bastion-host` | | 🔧`computeContention` | Proxies interactive sessions | `sim.proxyMs` |
| `secrets-rotation` | | - | Control-plane rotation, off critical path | `sim.rotationMs` |
| `privilege-escalation-control` | | 🔧`inspectionCost` | Checks each escalation request | `sim.checkMs` |

### Observability

All are generic **telemetry sinks** (`telemetrySink`), off the request critical
path - they govern their *own* ingest load, they don't shape request latency.

| Node | 📦 | Trait | Why this node needs it |
|------|----|-------|------------------------|
| `centralized-logging` | 📦 | 🔧`telemetrySink` | Ingest cap + sampling govern its own load |
| `distributed-tracing` | 📦 | 🔧`telemetrySink` | Sampling rate trades visibility for overhead |
| `metrics-store` | 📦 | 🔧`telemetrySink` | Cardinality + query cost |
| `alerting-hook` | 📦 | 🔧`telemetrySink` | Alert-rule evaluation latency |
| `health-check-manager` | 📦 | ⚠`healthProber` | Probes backends and produces the health signal `healthAware` consumes |
| `safety-observability-mesh` | 📦 | 🔧`telemetrySink` | Telemetry collection overhead |
| `rum-monitoring` | | 🔧`telemetrySink` | Client-side beacon ingest |
| `dashboard` | | 🔧`telemetrySink` | Query load only |
| `profiling-service` | | 🔧`telemetrySink` | Sampled profile ingest |

### DevOps & Delivery

Mostly control-plane / off the request path.

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `feature-flag-service` | 📦 | ➕`cache` | Evaluated per request - cache flags locally | `sim.flagEvalMs`+`sim.cacheHitRate` |
| `chaos-engineering-framework` | | ⚠ fault system | Injects faults to test resilience - reuse existing edge/scenario faults | `sim.faultRate`+`sim.faultType` |
| `deployment-controller` | | 🔧`scheduler` | Rollout progresses over time | `sim.rolloutMs` |
| `artifact-repository` | | ➕`cache` | Bandwidth-bound artifact pulls | `sim.pullMBps`+`sim.cacheHitRate` |
| `build-system` | | 🔧`scheduler` | Concurrency-limited build jobs | `sim.buildMs`, `sim.concurrency` |
| `policy-as-code` | | 🔧`inspectionCost` | Evaluates policy at admission | `sim.evalMs` |
| `pipeline-secrets` | | ➕`cache` | Hot secret fetch in pipelines | `sim.fetchMs` |

### Data-Infra & Analytics

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `streaming-analytics` | 📦 | ✅`windowing` | Processing-time tumbling windows: accumulate on arrival, emit a per-window aggregate via the `onTick` timer | `sim.windowMs` → `windowsEmitted`/`eventsAggregated` counters |
| `memory-fabric` | 📦 | 🔧`capacityLimit` | RDMA bandwidth-bound shared memory | `sim.rdmaGBps`, `sim.sharedLatencyMs` |
| `etl-pipeline` | | 🔧`batching` | A batch-throughput transform job | `sim.batchSize`+`sim.throughputRps` |
| `feature-store` | | 🔧`storageProfile` +➕`cache` | Online reads must be fast; freshness lags offline | `sim.onlineReadMs` vs `sim.offlineReadMs`, `sim.freshnessMs` |
| `model-serving` | | 🔧`batching` | Batches inference; pays model load + GPU | `sim.batchWindowMs`+`sim.maxBatch`, `sim.gpu`, `sim.modelLoadMs` |

### Real-time & Media

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `push-notification-service` | 📦 | 🔧`broadcastFanout` | Fans one event out to millions of devices; providers throttle | `sim.fanoutDevices`+`sim.providerRateLimit` |
| `websockets-gateway` | | 🔧`persistentConnFanout` | Holds millions of persistent connections + fan-out messaging | `sim.maxConnections`+`sim.fanoutMsg`, `sim.backpressure` |
| `transcoder` | | 🔧`batching` | CPU/GPU-heavy per stream & format | `sim.cpuMsPerSec`+`sim.formatCount`, `sim.gpu` |
| `signaling-server` | | 🔧`persistentConnFanout` | Session setup + per-connection state | `sim.setupMs`+`sim.connState` |
| `sfu-mcu` | | 🔧`persistentConnFanout` | Mixes/forwards media - CPU + bandwidth bound | `sim.mixCpuMs`+`sim.bandwidthMbps` |
| `webrtc-mesh` | | 🔧`persistentConnFanout` | Peer fan-out + NAT traversal | `sim.peerFanout`+`sim.natTraversalMs` |

---

## Trait build plan

### A. Extend an existing trait's `appliesTo` (➕, no new code, remaining)

| Existing trait | Add these node types |
|----------------|----------------------|
| `cache` | `auth-service`, `schema-registry`, `service-registry`, `config-store`, `secrets-manager`, `container-registry`, `tool-registry`, `dns-authoritative-server`, `internal-dns`, `identity-provider`, `iam-rbac`, `feature-flag-service`, `artifact-repository`, `pipeline-secrets`, `third-party-auth`, `feature-store` |
| `keyBasedRouting` | `shard-node`, `partition-node`, `nosql-db` |
| `coldStart` | `faas-background` |
| `contentRouting` | `routing-rule`, `routing-policy` |

### B. Wire a trait that already exists (⚠)

| Trait | Wire into |
|-------|-----------|
| `healthProber` (file present) | `health-check-manager` → produces the health signal for `healthAware` |
| edge/scenario fault injection | `chaos-engineering-framework` |

### C. New trait modules to implement (🔧), highest leverage first

`computeContention` · `consistencyModel` · `persistentConnFanout` ·
`telemetrySink` · `scheduler` (cluster bin-packing) · `changeStream` · `requestMix`
(see the Glossary for each one's rationale). The **`onTick` timer**,
**`afterTerminal` completion**, and **dynamic-capacity resize** primitives all now
exist — so `computeContention` is the main remaining engine gap (an honest CPU/thread
`c`-derivation), while the rest are node-model or source-model work.

**Shipped since (timer batch):** `windowing` · `fanoutQuery` · `autoscaler` — plus
the `onTick` recurring-timer hook and the dynamic-capacity resize that back them.

**Shipped earlier:** `geoLatency` · `externalLatency` · `tieredRetrieval` ·
`cryptoCost` · `tokenCost` · `inspectionCost` (latency/block modifiers),
`capacityLimit` · `batching` · `logReplay` (admission ceiling, batch
amortization, event-log replay), and `windowing` (first `onTick` consumer) —
all now live in `TRAIT_CAPABILITY_MODULES`.

---

## Summary

| | Count / status |
|---|---:|
| Total component types | **130** |
| 📦 In the palette | 60+ |
| Existing live traits | **31+** (`healthProber` is wired via the engine, not unwired) |
| Recently shipped (V2 distributed-systems landing) | `reservationStore`, `replication`, `streamBroker`, `protocolSession`, `rateLimiter` (keyed + breach oracle), `idempotencyDedup` (commit-outcome + external reconciliation) |
| Shipped in the prior refresh | `storageProfile`, `broadcastFanout`, `idempotencyDedup`, `retryBackoff`, `lockLease` |
| ➕ Nodes coverable by extending an existing trait | ~25 |
| 🔧 New trait modules still proposed | ~18 |

**Highest-leverage next steps:** richer broker guarantees (delete-ack,
consumer groups, exactly-once approximations), explicit CPU/thread contention,
and observability/control-plane semantics (`telemetrySink`, `scheduler`). Those
are the remaining blockers for the harder payment, monitoring, and
task-scheduler question families.

_Source of truth: `src/engine/traits/` (`appliesTo` + config `path`s per module) +
`src/engine/catalog/paletteTemplates.ts`. `(current)` config and ✅ trait
assignments are verbatim from the code; ➕/🔧/⚠, the "why" rationale, and proposed
config keys are design proposals._

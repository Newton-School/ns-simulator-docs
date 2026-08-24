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
`componentType`. There are **12 trait modules** covering **18 of 130 types**; the
other 112 are physically indistinguishable from a plain `microservice`.

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

### Existing traits (✅ - 12 modules, live today)

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

### Trait code that exists but is not wired (⚠)

| Trait | What it models | Why it exists / status |
|-------|----------------|------------------------|
| `healthProber` | Actively probes backends to produce the health signal `healthAware` consumes | The routing exists but nothing *generates* health yet. File is present (`src/engine/traits/healthProber.ts`); needs wiring, not writing. |
| edge/scenario **fault injection** | Injects errors/latency on edges & scenarios | Already implemented; a `chaos-engineering-framework` node would just surface it on the canvas. |

### Proposed new traits (🔧 - ordered by leverage)

| Trait | What it models | Why it exists |
|-------|----------------|---------------|
| `storageProfile` | Distinct per-store latency / throughput / ingest curves | **Biggest gap.** Today every store is physically identical, so "choose the right database" is graded only by rubric text. This makes the wrong store actually slower / saturate. |
| `broadcastFanout` | True 1→N delivery to *all* out-edges | Pub/sub's defining behavior. Without it, fan-out questions grade structurally while the simulation silently delivers to only one consumer. |
| `retryBackoff` | Re-issue on downstream failure with backoff + DLQ | Retries turn transient failures into latency and amplification (retry storms) - core resilience physics. |
| `computeContention` | CPU-core / thread-pool saturation + boot delay | Real services are bound by cores and pools, not an abstract "worker" count. Needed for accurate sizing and saturation. |
| `consistencyModel` | one vs quorum vs strong → latency & staleness | The central distributed-data tradeoff; needed so stronger consistency costs latency. |
| `lockLease` | Lock acquire/contention + TTL lease | Mutual exclusion prevents double-book / double-spend; needed to model contention and correctness under concurrency. |
| `idempotencyDedup` | Dedup window; retried writes short-circuit | Exactly-once is impossible without dedup; needed so a retried payment doesn't double-apply. |
| `batching` | Accumulate N items, amortize fixed cost | Throughput systems scale by batch, not per-item; needed so batch workers / inference behave correctly. |
| `capacityLimit` | Bandwidth / IOPS / port ceilings → queue or errors | Hard pipe limits cause outages independent of CPU; needed to saturate the *link*, not the processor. |
| `externalLatency` | Variable 3rd-party latency + quotas + retries | A slow external dependency's blast radius is a top real-world failure; needed to model it. |
| `geoLatency` | PoP / region distance latency | Distance = latency; needed so edge / CDN / multi-region designs are rewarded for locality. |
| `tokenCost` | Latency ∝ output tokens (not request count) | LLM serving has a cost model unlike any other node; needed for AI-system questions. |
| `persistentConnFanout` | Millions of long-lived connections + push fan-out | Real-time systems have a fundamentally different concurrency model from request/response. |
| `fanoutQuery` | Scatter-gather bounded by the slowest shard | Distributed search tail latency; needed to model why more shards ≠ always faster. |
| `logReplay` | Replay cost grows with log length | Event-sourced systems pay to rebuild state; needed so snapshotting strategy matters. |
| `tieredRetrieval` | Cold-storage retrieval latency (s→min) | So "archive it" has a real consequence, not the same latency as hot storage. |
| `cryptoCost` | Encrypt / verify latency + op quotas | Crypto is CPU-heavy and quota-limited; needed to model KMS / TLS as a real bottleneck. |
| `inspectionCost` | Per-byte / per-rule scan + block rate | Security scanning adds latency and can drop traffic; needed so a WAF isn't free. |
| `telemetrySink` | Ingest cap + sampling + query cost (off request path) | Observability has its own load; needed to model sampling tradeoffs and telemetry back-pressure. |
| `scheduler` | Placement / bin-packing + autoscale reaction time & cooldown | So scaling isn't instantaneous - capacity follows demand with a lag. |
| `windowing` | Windowed aggregation + watermark lag + state | Stream analytics is a distinct stateful compute model. |
| `changeStream` | CDC capture lag + ordering | Data-pipeline latency and ordering guarantees. |
| `requestMix` (extend source) | Typed traffic weights + payload sizing on the source | So read/write ratios and payload sizes actually drive routing and bandwidth. |

---

## Full matrix by category

Columns: **Node · 📦 · Trait · Why this node needs it · Config input → behavior.**

### Compute

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `api-endpoint` | 📦 | ✅`source.workload` +🔧`requestMix` | 🟢 It's the traffic origin - its pattern & mix define the load everything else must survive | `sim.requestMix[]` → typed traffic; `sim.payloadBytes`; `sim.closedLoop`+`sim.thinkTimeMs` |
| `microservice` | 📦 | 🔧`computeContention` +🔧`retryBackoff` | Stateless handlers saturate on CPU/threads and cascade downstream failures - the core resilience surface | `sim.cpuBoundRatio`, `sim.threadPool`, `sim.dependencyFanout`, `resilience.retry.*` |
| `batch-worker` | 📦 | 🔧`batching` | Throughput comes from processing many items per pull, not per-request speed | `sim.batchSize`, `sim.prefetch`, `sim.parallelism` |
| `sidecar` | 📦 | ✅`circuitBreaker` | Proxies every call; a tripped breaker here protects the whole mesh | `sim.proxyOverheadMs`, `sim.mtlsMs` |
| `serverless-function` | 📦 | ✅`coldStart` | Scales from zero, so the first request after idle pays a cold-start penalty | `sim.coldStartLatencyMs`,`sim.idleTimeoutMs`,`sim.maxConcurrency` **(current)** |
| `faas-background` | | ➕`coldStart` +🔧`retryBackoff` | Event-triggered and retried async - same cold-start + retry concerns | `sim.triggerBatch`, `resilience.retry.*`, `sim.coldStartLatencyMs` |
| `container` | | 🔧`computeContention` | Hard CPU/memory limits throttle it before the queue does | `resources.cpu/memory`, `sim.restartOnCrash` |
| `vm-instance` | | 🔧`computeContention` | Slow to boot, so scale-out lags demand | `sim.bootMs`, `sim.noisyNeighborVariance` |
| `edge-compute` | 📦 | 🔧`geoLatency` | Runs at PoPs; distance to the user dominates its latency | `sim.popLatencyMs`, constrained `resources.*` |
| `gpu-node` | | 🔧`batching` | Efficient only when inference is batched; VRAM caps concurrency | `sim.batchWindowMs`+`sim.maxBatch`, `sim.vramMB`, `sim.modelLoadMs` |
| `auth-service` | 📦 | ➕`cache` | Verifies a token on every request; a token cache is the difference between fast and a bottleneck | `sim.tokenVerifyMs`, `sim.tokenCacheHitRate` |
| `search-service` | 📦 | 🔧`fanoutQuery` | Answers by scattering to shards and gathering - latency is the slowest shard | `sim.shardCount`+`sim.fanoutLatencyMs`, `sim.queryCostMs` |

### Network & Edge

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `load-balancer` | 📦 | ✅`healthAware` | Its whole job is steering traffic away from unhealthy backends | `sim.sticky`, `sim.sslTerminationMs`, `sim.drainMs` |
| `load-balancer-l4` | | ✅`healthAware` | Pins flows by connection; can exhaust NAT ports at scale | `sim.flowHash`, `sim.natPorts` |
| `load-balancer-l7` | | ✅`contentRouting`+`healthAware` | Routes on headers/paths and terminates TLS - real per-request cost | `sim.tlsTerminationMs`, `sim.headerRouteCostMs` |
| `global-traffic-manager` | | 🔧`geoLatency` | Steers each user to the nearest healthy region | `sim.geoSteering`+`sim.regionLatencyMs[]`, `sim.failoverRegion` |
| `edge-router` | 📦 | 🔧`capacityLimit` | Spreads flows across paths; bounded by link capacity | `sim.ecmpPaths`, `sim.routeLookupMs` |
| `nat-gateway` | 📦 | 🔧`capacityLimit` | Finite source ports - exhaustion is a classic outage | `sim.maxPorts` → errors, `sim.connTrackMs` |
| `transit-gateway` | | 🔧`capacityLimit` | Bandwidth-capped interconnect between networks | `sim.bandwidthMbps` |
| `vpn-gateway` | 📦 | 🔧`capacityLimit` | Encryption + tunnel bandwidth cap throughput | `sim.encryptMsPerKB`, `sim.tunnelBandwidthMbps` |
| `cdn` | 📦 | ✅`cache` +🔧`geoLatency` | Absorbs read traffic at the edge; only misses hit origin | `sim.ttlMs`+`sim.invalidationRate`, `sim.popLatencyMs`, `sim.dynamicRatio` |
| `api-gateway` | | ✅`contentRouting`+`healthAware`+`rateLimiter` | The policy choke point - auth, routing, and rate limits all live here | `sim.authMs`, `sim.transformMs`, `sim.quotaPerKey` |
| `service-mesh` | 📦 | ✅`circuitBreaker` | Enforces retries/breakers/mTLS between every service | `sim.sidecarLatencyMs`, `sim.mtlsMs`, `resilience.retry.*` |
| `ingress-controller` | | ✅`contentRouting`+`healthAware` | Cluster entry point - TLS + path routing cost | `sim.tlsMs`, `sim.rewriteCostMs`, `sim.perRouteLimit` |
| `reverse-proxy` | | ✅`cache`+`healthAware` | Caches and buffers in front of an origin | `sim.compressionMs`, `sim.bufferBytes`, `sim.connReuse` |
| `high-perf-nic` | 📦 | 🔧`capacityLimit` | Line-rate throughput with kernel-bypass/offload | `sim.lineRateGbps`, `sim.offload` |
| `network-policy` | | 🔧`inspectionCost` | Evaluates allow/deny per packet (mostly non-runtime) | `sim.evalMs` |
| `routing-rule` | 📦 | ➕`contentRouting` | Matches attributes and forwards - same primitive as content routing | `sim.matchCostMs` |
| `routing-policy` | 📦 | ➕`contentRouting` | Policy-based forwarding decision per request | `sim.policyEvalMs` |

### Storage & Data

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `relational-db` | 📦 | ✅`readOnly`+`readWriteSplit` +🔧`lockContention` | Reads scale on replicas; writes serialize on the primary under locks | `sim.lockContention`, `sim.isolationLevel`, `sim.indexHitRatio`, `sim.replicationLagMs` |
| `in-memory-cache` | 📦 | ✅`cache` | Fast only while the working set fits; eviction and hot keys erode hit rate | `sim.maxEntries`+`sim.evictionPolicy`, `sim.hotKeyRatio`, `sim.writeThrough` |
| `nosql-db` | 📦 | 🔧`storageProfile` +🔧`consistencyModel` +➕`keyBasedRouting` | Scales by sharding; consistency level trades latency for freshness; hot partitions bottleneck | `sim.shardCount`+`sim.hotPartitionRatio`, `sim.consistency`, `sim.secondaryIndexMs` |
| `kv-store` | 📦 | 🔧`storageProfile` | Point get/put with hot-key risk; the wrong store for scans | `sim.getMs`/`sim.putMs`, `sim.ttlMs`, `sim.hotKeyRatio` |
| `time-series-db` | 📦 | 🔧`storageProfile` | Write-optimized append + compaction; struggles on high cardinality | `sim.ingestBatch`, `sim.compactionOverhead`, `sim.retentionMs`, `sim.cardinalityLimit` |
| `columnar-db` | | 🔧`storageProfile` | Scans huge column ranges; partition pruning is everything | `sim.scanRowsPerSec`, `sim.compressionRatio`, `sim.partitionPruning` |
| `object-storage` | 📦 | 🔧`storageProfile` +🔧`tieredRetrieval` | High-latency, high-throughput blobs; no random update | `sim.getLatencyMs`+`sim.throughputMBps`, `sim.multipartThresholdMB`, `sim.coldTierMs` |
| `block-storage` | | 🔧`capacityLimit` | An IOPS/throughput-capped volume | `sim.iops`+`sim.throughputMBps`, `sim.latencyMs` |
| `distributed-file-system` | | 🔧`storageProfile` | Metadata server + replication shape latency | `sim.replicationFactor`, `sim.metadataMs`, `sim.streamMBps` |
| `search-index` | 📦 | 🔧`fanoutQuery` | Scatter-gather over shards; writes lag behind reads (refresh) | `sim.indexMs` vs `sim.queryMs`, `sim.shardCount`+`sim.fanoutMs`, `sim.refreshLagMs` |
| `graph-db` | 📦 | 🔧`storageProfile` | Traversal cost explodes on supernodes | `sim.hopCostMs`+`sim.maxDepth`, `sim.supernodeThreshold` |
| `vector-db` | 📦 | 🔧`storageProfile` | ANN search trades recall for latency | `sim.annMs`+`sim.recall`, `sim.indexBuildMs` |
| `data-warehouse` | 📦 | 🔧`storageProfile` | MPP scans; concurrency scaling under load | `sim.scanGB`+`sim.mppSlots`, `sim.resultCacheHitRate` |
| `data-lake` | 📦 | 🔧`storageProfile` | Cheap scans over partitioned object files, schema-on-read | `sim.scanGB`, `sim.partitions`, `sim.schemaOnReadMs` |
| `archive-storage` | | 🔧`tieredRetrieval` | Cold - retrieval takes minutes, not milliseconds | `sim.retrievalMs`, `sim.minDurationMs` |
| `schema-registry` | | ➕`cache` | Hot lookup on the write path - cache it or it bottlenecks | `sim.lookupCacheHitRate`, `sim.compatCheckMs` |
| `cdc` | | 🔧`changeStream` | Streams DB changes with capture lag + ordering | `sim.captureLagMs`, `sim.throughputRps`, `sim.ordered` |
| `backup-service` | | 🔧`batching` | Throughput-bound snapshot job with RPO/RTO | `sim.snapshotMBps`, `sim.rpoMs`/`sim.rtoMs` |
| `kms-storage` | | 🔧`cryptoCost` | Key ops are latency + quota bound | `sim.cryptoMs`, `sim.opQuotaPerSec` |

### Messaging & Streaming

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `queue` | 📦 | ✅`ackAndRelease` | Decouples producers from consumers; ack/visibility/DLQ define delivery | `sim.visibilityTimeoutMs`, `sim.dlqAfter`, `sim.ordering=fifo`, `sim.prefetch` |
| `stream` | 📦 | ✅`consumerLag` | A partitioned, replayable log; lag is the health signal | `sim.partitions`+`sim.ordering`, `sim.retentionMs`+`sim.replay`, `sim.consumerGroups` |
| `message-broker` | 📦 | 🔧`broadcastFanout` | Must deliver each event to *every* subscriber - the whole point of pub/sub | `sim.fanout=broadcast\|work-queue`, `sim.consumerGroups`, `sim.deliveryGuarantee` |
| `pub-sub` | 📦 | 🔧`broadcastFanout` | Broadcast with per-subscription filters | `sim.fanout=broadcast`, `sim.subscriptionFilter`, `sim.retentionMs` |
| `event-bus` | | 🔧`broadcastFanout` | Rule-routed broadcast of events | `sim.routingRules[]`, `sim.fanout` |
| `event-sourcing-store` | | 🔧`logReplay` | Append-only; rebuilding state means replaying the whole log | `sim.appendMs`+`sim.replayCostPerEvent`, `sim.snapshotEvery` |
| `task-queue` | | 🔧`retryBackoff` | Scheduled work with retries, backoff, and priority | `sim.scheduleDelayMs`, `resilience.retry.*`, `sim.priorityLevels`, `sim.dlqAfter` |

### Consensus & Coordination

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `distributed-lock` | | 🔧`lockLease` | Serializes access; contention + TTL lease are the failure modes | `sim.acquireMs`+`sim.contentionModel`, `sim.leaseMs`, `sim.fencing` |
| `etcd-consul-kv` | | 🔧`consistencyModel` | Quorum writes are slow but consistent; leader failover pauses writes | `sim.quorumWriteMs`, `sim.leaderFailoverMs`, `sim.watchFanout` |
| `leader-election` | | 🔧`lockLease` | Election + failover windows create unavailability | `sim.electionMs`, `sim.failoverMs` |
| `coordination-service` | | 🔧`consistencyModel` | Consensus rounds add latency to every coordinated op | `sim.consensusRoundMs` |

### Auxiliary

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `sharding` | 📦 | ✅`keyBasedRouting` | Routes each key to its shard; skew makes a hot shard | `sim.shardCount`, `sim.rebalanceMs`, `sim.hotShardRatio` |
| `hashing` | 📦 | ✅`keyBasedRouting` | Consistent-hash placement; virtual nodes smooth skew | `sim.virtualNodes`, `sim.ringSkew` |
| `rate-limiter` | | ➕`rateLimiter` | Rejects traffic above a rate; must share counters across instances or it leaks | `sim.algorithm`, `sim.maxTokens`+`sim.refillRatePerSecond`, `sim.sharedCounter` |
| `idempotency-manager` | | 🔧`idempotencyDedup` | Dedupes retries so an operation applies exactly once | `sim.dedupWindowMs`+`sim.dupRatio`, `sim.storeLookupMs` |
| `circuit-breaker-controller` | | ➕`circuitBreaker` | Trips to stop hammering a failing dependency | `resilience.circuitBreaker.*` |
| `throttler` | | ➕`rateLimiter` | Sheds load above a ceiling | `sim.maxRps` |
| `backpressure-controller` | | 🔧`backpressure` | Signals upstream to slow when the backlog is high | `sim.highWatermark`+`sim.signalMs` |
| `shard-node` | 📦 | ➕`keyBasedRouting` | Owns a slice of the keyspace with its own capacity | `sim.capacityRps` |
| `partition-node` | 📦 | ➕`keyBasedRouting` | Routes by partition key to one partition | `sim.partitionKey`+`sim.partitions` |
| `request-tracking` | | 🔧`telemetrySink` | Adds trace-context overhead on each hop | `sim.traceOverheadMs` |
| `policy-engine` | | 🔧`inspectionCost` | Evaluates a policy per request | `sim.policyEvalMs` |
| `service-mesh-telemetry` | | 🔧`telemetrySink` | Exports telemetry with per-request overhead | `sim.exportOverheadMs` |

### External & Integration

| Node | 📦 | Trait | Why this node needs it | Config → behavior |
|------|----|-------|------------------------|-------------------|
| `third-party-api-connector` | | ✅`rateLimiter` +🔧`externalLatency` | An external dependency - variable latency, provider quotas, retries | `sim.externalLatencyMs`, `resilience.retry.*`, `sim.quota` |
| `llm-gateway` | 📦 | 🔧`tokenCost` | Latency scales with generated tokens, not request count | `sim.msPerToken`+`sim.outputTokens`, `sim.streaming`, `sim.providerRateLimit` |
| `payment-gateway` | | 🔧`externalLatency` +🔧`retryBackoff` | External and must be idempotent + retried | `sim.externalLatencyMs`, `sim.idempotencyKey`, `resilience.retry.*` |
| `webhook-gateway` | | 🔧`retryBackoff` +🔧`broadcastFanout` | Delivers to many endpoints with retries/backoff | `resilience.retry.*`+`sim.backoff`, `sim.fanoutTargets` |
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
| `agent-orchestrator` | 📦 | 🔧`scheduler` | Dispatches agent tasks with scheduling latency | `sim.dispatchMs` |
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
| `streaming-analytics` | 📦 | 🔧`windowing` | Holds windowed state; watermark lag governs output | `sim.windowMs`+`sim.stateSize`, `sim.watermarkLagMs` |
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

### A. Extend an existing trait's `appliesTo` (➕, no new code)

| Existing trait | Add these node types |
|----------------|----------------------|
| `cache` | `auth-service`, `schema-registry`, `service-registry`, `config-store`, `secrets-manager`, `container-registry`, `tool-registry`, `dns-authoritative-server`, `internal-dns`, `identity-provider`, `iam-rbac`, `feature-flag-service`, `artifact-repository`, `pipeline-secrets`, `third-party-auth`, `feature-store` |
| `rateLimiter` | `rate-limiter`, `throttler` |
| `circuitBreaker` | `circuit-breaker-controller` |
| `keyBasedRouting` | `shard-node`, `partition-node`, `nosql-db` |
| `coldStart` | `faas-background` |
| `contentRouting` | `routing-rule`, `routing-policy` |

### B. Wire a trait that already exists (⚠)

| Trait | Wire into |
|-------|-----------|
| `healthProber` (file present) | `health-check-manager` → produces the health signal for `healthAware` |
| edge/scenario fault injection | `chaos-engineering-framework` |

### C. New trait modules to implement (🔧), highest leverage first

`storageProfile` · `broadcastFanout` · `retryBackoff` · `computeContention` ·
`consistencyModel` · `lockLease` · `idempotencyDedup` · `batching` ·
`capacityLimit` · `externalLatency` · `geoLatency` · `tokenCost` ·
`persistentConnFanout` · `fanoutQuery` · `logReplay` · `tieredRetrieval` ·
`cryptoCost` · `inspectionCost` · `telemetrySink` · `scheduler` · `windowing` ·
`changeStream` · `requestMix` (see the Glossary for each one's rationale).

---

## Summary

| | Count |
|---|------:|
| Total component types | **130** |
| ✅ Modeled (≥1 trait) | **18** |
| 🟢 Source | 1 (`api-endpoint`) |
| ⚪ Generic | **111** |
| 📦 In the palette | 60 |
| Existing traits | 12 (+1 unwired: `healthProber`) |
| ➕ Nodes coverable by extending an existing trait | ~25 |
| 🔧 New trait modules proposed | ~23 |

**Highest-leverage next steps:** `storageProfile` (stores are identical today),
`broadcastFanout` (`message-broker` doesn't broadcast), and wiring the eponymous
coordination nodes (`rate-limiter`→`rateLimiter`, `circuit-breaker-controller`→
`circuitBreaker`, plus new `lockLease`/`idempotencyDedup`) - which unblocks the
deferred `payment-system` / `ticketmaster` / `rate-limiter` questions.

_Source of truth: `src/engine/traits/` (`appliesTo` + config `path`s per module) +
`src/engine/catalog/paletteTemplates.ts`. `(current)` config and ✅ trait
assignments are verbatim from the code; ➕/🔧/⚠, the "why" rationale, and proposed
config keys are design proposals._

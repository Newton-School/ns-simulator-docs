# Educative Grokking Modern System Design -> NS Simulator Gap Matrix

> Purpose: map the full 48-section Educative "Grokking Modern System Design Interview" course to the simulator's current coverage, missing semantics, and exact next build items.
>
> Scope: this matrix covers all 48 numbered course sections. It is based on the full lesson export captured through the browser, plus a second pass focused on slide-heavy and diagram-heavy lessons.
>
> Note on lesson counts: an earlier `22 lesson` figure referred only to pages where the browser-extracted text exposed inline slide/deck counters such as `1 / 5`. It was never the total course size. The matrix below covers the full 48-section course.
>
> Shipped since the first draft of this matrix on August 24, 2026: `storageProfile`,
> `broadcastFanout`, `idempotencyDedup`, and the library `Blueprints`
> requirements-first workflow.

## Method

- "Already simulate" means the simulator currently has runtime behavior, scenario coverage, or analysis support that materially teaches the concept.
- "Missing" means the simulator either models the concept only as a generic queue, handles it only in docs/rubrics, or does not expose it at all.
- "Exact feature to build" is the recommended concrete simulator deliverable, not a vague theme.
- Visual lessons matter here: many course sections teach via spectrums, state transitions, timelines, and architecture refinement. Where that changes the recommendation, the build item is intentionally visual, not only engine-side.

## Foundations

| # | Course Section | What The Course Teaches | What We Already Simulate | What We're Missing | Exact Feature To Build |
|---|---|---|---|---|---|
| 1 | Introduction | System design as iterative architecture using reusable building blocks; reliable, scalable, maintainable systems | Core topology builder, DES engine, queueing analysis, sample scenarios, and requirements-first blueprints | Iteration as a first-class activity across multiple saved revisions | `Requirements -> Design -> Run -> Refine` workspace with saved iterations and topology diff |
| 2 | System Design Interviews | How to structure answers, avoid traps, and communicate tradeoffs under time pressure | Question/rubric engine, evaluation envelope, justification grading | Interview-mode workflow, timed prompts, answer structure coaching | `Interview Mode` with timer, prompt scaffold, and post-run rubric feedback |
| 3 | Preliminary System Design Concepts | Abstraction, RPC/network boundaries, consistency spectrum, failure spectrum | Request routing, protocol labels, queueing/failure primitives, some resilience traits | First-class consistency/failure model controls and explanations | `Distributed Systems Concepts` panel with consistency/failure policy selectors and explainers |
| 4 | Non-Functional System Characteristics | Availability, reliability, scalability, maintainability, fault tolerance as explicit design goals | SLO targets, latency/throughput/error metrics, bottleneck analysis | NFR planning before topology design and explicit tradeoff scoring | `NFR Scorecard` that turns user goals into scenario checks and tradeoff warnings |
| 5 | Back-of-the-Envelope Calculations | Capacity estimation for servers, storage, bandwidth, peak load assumptions | Cost model, workload inputs, some scenario sizing intuition | Dedicated estimation tooling tied to topology assumptions | `BOTEC Workbook` for DAU, RPS, storage, bandwidth, peak factor, and node count |
| 6 | Building Blocks Intro | Why modern design is built by composing standard primitives | Rich component catalog and palette | Stronger cross-links between concept, component, and scenario | `Building Block Explorer` linking each node type to scenarios, traits, and tradeoffs |

## Building Blocks

| # | Course Section | What The Course Teaches | What We Already Simulate | What We're Missing | Exact Feature To Build |
|---|---|---|---|---|---|
| 7 | DNS | Recursive lookup, TTL, caching, routing policies, global traffic steering | `dnsRoutingPolicy` with weighted/failover/latency/geolocation plus TTL cache | Recursive chain, authoritative vs resolver split, visible resolution path | `DNS Resolution Timeline` with resolver cache, root/TLD/authoritative hops, and answer selection trace |
| 8 | Load Balancers | Global vs local balancing, LB algorithms, hierarchical balancing | Round-robin, weighted, least-conn, health-aware routing, content routing, L4/L7 nodes | Sticky sessions, least-response-time, IP/URL hash, client-side LB, LB hierarchy drill-down | `Load Balancing Lab` with pluggable algorithms, session affinity, and client-side discovery mode |
| 9 | Databases | DB types, replication, partitioning, centralized vs distributed tradeoffs | Read/write split, read-only replicas, key-based routing, generic stores, cost tiers, plus shipped `storageProfile` service-time curves | Consistency cost, replication lag, failover, lock contention, and richer store internals | `consistencyModel` + `replicationLag` + `lockContention` on top of shipped `storageProfile` |
| 10 | Key-Value Store | Scalability, replication, configurability, versioning, failure detection | KV store node, sharding/key-based routing, cache, DNS, health-aware routing | Version vectors, quorum semantics, hot-key dynamics, replica repair, failure detector behavior | `KV Store Scenario Pack` with quorum reads/writes, hot-key skew, and anti-entropy lag |
| 11 | CDN | Edge caching, origin fallback, global serving, CDN evaluation tradeoffs | CDN/cache trait, path-type latency, weighted DNS, edge cost defaults | POP topology, origin shield, eviction, stale content, purge semantics | `CDN POP Model` with regional edges, origin shield, purge/TTL, and stale-hit visualization |
| 12 | Sequencer | Unique IDs, ordering, causality, logical time | Unique request IDs only; some routing semantics | No explicit ID-generation or causality model | `Sequencer / ID Generator` node with Snowflake, time-sortable IDs, and Lamport-style logical ordering mode |
| 13 | Distributed Monitoring | Metrics system requirements, ingestion/storage/query design | Metrics collector, snapshots, results views, observability nodes in catalog | TSDB/blob/rules-store architecture, pull vs push monitoring topologies | `Monitoring Topology Pack` with collector, TSDB, blob retention, rules DB, and alert manager |
| 14 | Monitor Server-Side Errors | Monitoring internals, alerting, visualization of server-side telemetry | Error metrics, traces, results tray, some observability nodes | Async telemetry sinks, sampling, batching, alert evaluation latency, dashboard query load | `telemetrySink` trait family for logs, traces, metrics, and alerts |
| 15 | Monitor Client-Side Errors | RUM/client telemetry, beacon flows, frontend error capture | RUM node exists in catalog only | Client-side beacon generation and ingestion semantics | `RUM / Client Telemetry` scenario with browser beacon traffic and async collector load |
| 16 | Distributed Cache | Service discovery, hot keys, SPOF removal, cache internals, eviction | Cache hit/miss trait, reverse proxy/CDN cache, cache sample scenario | Eviction policy, working-set pressure, write-through/write-behind, cache cluster membership | `Advanced Cache Trait` with eviction, hot-key amplification, and cluster discovery |
| 17 | Distributed Messaging Queue | Broker placement, replication, metadata service, queue backends | Queue async ack/release, at-most-once/at-least-once style delivery mode, visibility-timeout redelivery, DLQ handoff, caller-owned retry backoff, stream lag, broker/pub-sub nodes, async boundaries | Broker replication models, consumer groups, delete-ack boundaries, true exactly-once coordination | `Queue Cluster Pack` + richer broker guarantees |
| 18 | Pub-Sub | Topic queue plus subscriber fanout and per-consumer delivery | Broadcast fanout is now modeled for broker/pub-sub runtime behavior, and async delivery exists | Subscription filters, consumer groups, partition ownership, delivery guarantees | Extend shipped `broadcastFanout` with filters, groups, and delivery mode selection |
| 19 | Rate Limiter | Token bucket, leaky bucket, fixed/sliding windows, algorithm tradeoffs | Token-bucket rate limiter trait | Other algorithms and side-by-side comparison lab | `Rate Limiter Playground` with token bucket, leaky bucket, fixed window, sliding window log/counter |
| 20 | Blob Store | Blob metadata, partitioning, indexing, pagination, replication, large object handling | Object-storage node, volume-oriented cost model, generic queue behavior | Multipart upload, metadata/index plane, tiered retrieval, partition strategies | `Blob Store Pack` with metadata service, multipart upload path, cold tier, and index lookup |
| 21 | Distributed Search | Indexing, inverted index, decoupled indexing/search, shard fanout | Search-index node exists; scenario/rubric coverage is partial | Search/query fanout, refresh lag, shard scatter-gather, indexing pipeline | `fanoutQuery` + `refreshLag` + indexing pipeline scenario |
| 22 | Distributed Logging | Log ingestion and centralized logging architecture | Logging node exists; async boundaries available | Ingest caps, batching, sampling, retention, query load | `Logging Pipeline` scenario built on `telemetrySink` with retention tiers |
| 23 | Distributed Task Scheduler | FCFS vs priority, delayed tasks, cron, node assignment, scalability | Queueing engine, cron-job node, task-queue node in catalog | Priority queues, scheduled execution, placement latency, autoscale cooldown | `scheduler` trait with priority lanes, cron timing, placement delay, and cooldown |
| 24 | Sharded Counters | Read/write amplification tradeoff, shard count tuning, aggregation | Sharding primitives and key-based routing | Counter-specific write/read semantics and aggregation cost | `Sharded Counter Lab` with shard-count tuner and read-vs-write cost curves |
| 25 | Building Blocks Wrap-Up / RESHADED | Structured design method: requirements, estimation, HLD, API, detail, evaluation, unique challenge | Rubric engine, question grading, some design justification checks | End-to-end guided design workflow that mirrors the course method | `RESHADED Wizard` that scaffolds every simulator exercise from requirement capture to evaluation |

## Case Studies And Modern Systems

| # | Course Section | What The Course Teaches | What We Already Simulate | What We're Missing | Exact Feature To Build |
|---|---|---|---|---|---|
| 26 | Design YouTube | Media upload, stream delivery, scale, custom storage/index choices | CDN/cache, storage nodes, queueing, async processing patterns | Video ingest/transcode pipeline, chunked media delivery, recommendation sidecars | `YouTube Scenario Pack` with upload, transcode queue, CDN, metadata, and fanout reads |
| 27 | Design Quora | Q&A platform, community answers, search-vs-human knowledge flow | Search, feeds, storage, cache primitives exist separately | Integrated Q&A/write-heavy/read-heavy scenario and ranking path | `Quora Scenario` with answer write path, question retrieval, and ranking/search split |
| 28 | Design Google Maps | Geo data, ETA, route planning, traffic-aware reads | Path-type latency and geographic containers | Spatial indexing, route graph query cost, ETA pipeline | `Geo Index / Route Service` nodes with geospatial query semantics |
| 29 | Design Yelp / Proximity Service | Radius search, geo indexing, low-latency proximity lookups | Search/index nodes, sample rubrics, generic stores | Real geo-partitioning and radius query cost model | `Proximity Search` scenario with geohash/quadtree-like partition model |
| 30 | Design Uber | Real-time matching, driver/rider location, payment/fraud path | Web/API nodes, async edges, payment gateway node, basic resilience | Persistent connections, matchmaking, location streams, dispatch loop, fraud sidepath | `Ride Matching` scenario with location stream, matcher, dispatch, payment, fraud |
| 31 | Design Twitter | Fanout, client-side LB, read/write asymmetry, cache-heavy scale | Streams, queues, cache, sharding, least-conn, content routing | Client-side service discovery, feed fanout strategies, celebrity hot-spot dynamics | `Twitter Architecture Lab` with fanout-on-write vs fanout-on-read and client-side LB |
| 32 | Design Newsfeed System | Personalized feed generation at scale | Queueing, cache, storage, event streams, read/write split | Feed materialization semantics and ranking freshness tradeoffs | `Feed Generation Lab` comparing precompute, pull, and hybrid feed models |
| 33 | Design Instagram | Media-heavy social graph, feed, hashtags, CDN-backed reads | CDN, cache, object storage, feed-adjacent primitives | Media upload + fanout + hashtag discovery as one cohesive system | `Instagram Scenario` with media store, feed fanout, hashtag index, and CDN |
| 34 | Design TinyURL | Redirect path, short-code generation, analytics, dependency on KV | KV store, cache, sequencer gap identified, URL shortener example exists | Explicit short-code generator, redirect analytics, collision strategy | `URL Shortener` upgraded scenario with ID generator and redirect analytics node |
| 35 | Design Web Crawler | Seed URLs, frontier, politeness, dedupe, storage | Queueing, storage, search/index building blocks exist | Frontier semantics, robots/politeness, dedupe, batch indexing handoff | `Crawler Frontier` scenario with frontier queue, dedupe index, politeness scheduler |
| 36 | Design WhatsApp | Massive messaging scale, low latency, secure delivery | Streams, queues, pub-sub, async edges, websocket protocol labels | Long-lived connection fanout, per-chat ordering, ack/delivery semantics | `persistentConnFanout` + `messageOrdering` mode for chat scenarios |
| 37 | Design Typeahead Suggestion | Prefix index, ranking, freshness, low-latency autocomplete | Search-index node, caching, request routing | Prefix trie/index refresh, ranking updates, popularity windows | `Typeahead Lab` with trie-like prefix store, refresh lag, and ranking decay |
| 38 | Design Google Docs | Collaborative editing, concurrency, OT/CRDT, convergence | No true collaborative editing runtime today; only generic topology/rubric support | Operation transform/CRDT semantics, divergence window, merge visualization | `Collaborative Editing` scenario with OT vs CRDT mode and convergence timeline |
| 39 | Design Code Deployment System | CI/CD stages, rollout strategies, release risk reduction | Deployment-controller node exists only conceptually; health nodes and routing exist | Rollout state machine, canary/blue-green, health gates, rollback | `Deployment Pipeline` scenario with rollout controller, health gate, and rollback path |
| 40 | Design Payment System | Payment flow, card processing, correctness, security, consistency | Payment-style guarded writes now have shipped `idempotencyDedup`, `retryBackoff`, and `lockLease` foundations plus a payment idempotency sample/blueprint | Ledger semantics, reconciliation, and full exactly-once approximations | `Payment Correctness Pack` building on shipped guard-node semantics, then adding reconciliation |
| 41 | Design ChatGPT System | Inference gateway, session context, caching, feedback loop | API gateway, cache, logging, some AI-oriented catalog nodes | Token-based latency/cost, context-window pressure, model-serving semantics | `tokenCost` + `modelServing` scenario for conversational inference |
| 42 | Design Data Infrastructure For AI/ML | Ingestion, batch + stream, feature store, model serving, training-serving skew | Streams, object storage, feature-store node, model-serving node in catalog | Batch/windowing/change-stream semantics and online/offline freshness gap | `AI Data Infra Pack` with `windowing`, `changeStream`, `batching`, and feature freshness |
| 43 | LLM-Powered Customer Support Bot | RAG, grounding, escalation, company knowledge + real-time data | ChatGPT-like primitives and search/storage nodes exist separately | Retrieval freshness, grounding chain, escalation workflow, tool latency budget | `RAG Support Bot` scenario with retriever, vector/doc store, policy gate, and handoff queue |
| 44 | AI-Powered Code Assistant | IDE latency, context retrieval, code generation, developer workflow constraints | AI/code-assistant concepts appear only as general components and docs | IDE request mix, repository context retrieval, suggestion latency budget | `Code Assistant` scenario with editor events, context fetch, model call, and debounce/cache |
| 45 | Lessons From System Failures | Outage anatomy, independent failure domains, cascading failures, operational lessons | Failure injection, tracer, metrics, causal graph, resilience traits | Incident timeline playback and failure-domain visualization | `Incident Replay Mode` with trigger -> propagation -> mitigation timeline and blast-radius map |

## Closing Sections, Resources, And Case Studies

| # | Course Section | What The Course Teaches | What We Already Simulate | What We're Missing | Exact Feature To Build |
|---|---|---|---|---|---|
| 46 | Concluding Remarks | Synthesis of patterns, picking the right tools, reflecting on tradeoffs | Existing docs, examples, and question framework | A canonical simulator learning path that mirrors course progression | `Learning Path` inside the app that orders scenarios from fundamentals to advanced systems |
| 47 | Free System Design Lessons / Resources | External study resources, mock interviews, targeted practice | Docs and examples in-repo, but not organized as a course companion | Curated study mode and importable practice problems | `Practice Library` linking simulator scenarios to external-style design prompts |
| 48 | System Design Case Studies / External Case Studies | Real-world postmortems and named systems such as Spotify Wrapped, Dropbox, Ticketmaster | Some scenario and grading groundwork; several relevant nodes already exist | Importable case-study kits with guided questions, reference topology, and failure drills | `Case Study Library` with packaged Spotify/Dropbox/Ticketmaster-style simulator exercises |

## Visual Lessons: What The Diagrams Add

The course's diagrams repeatedly teach things that the current simulator does not yet surface well enough:

- Spectrums: consistency and failure models are presented as ranges, not toggles.
- Sequences: rate limiting, replication, DNS, and outages are taught as ordered steps.
- Architecture refinement: many lessons move from baseline to improved design visually.
- Control plane vs data plane: monitoring, deployment, discovery, and routing are separated visually.
- Causality: collaborative editing, ID generation, and failure propagation are explained through event order.

The simulator should therefore add not only engine features, but also visual teaching surfaces:

1. `Policy Spectrum Panels` for consistency, failure, and routing choices.
2. `Algorithm Labs` for token bucket, replication, sharding, queue priority, and DNS resolution.
3. `Incident Replay Mode` for outage lessons.
4. `Iteration Compare Mode` for baseline vs refined architecture design.

## Cross-Cutting Build Order

Recommended order if the goal is to align the simulator with the course quickly:

1. Shipped foundation slice
   - `Blueprints` requirements-first workflow
   - `storageProfile`
   - `broadcastFanout`
   - `idempotencyDedup`
   - `retryBackoff`
   - `lockLease`
2. Remaining store and messaging semantics
   - `consistencyModel`
   - `replicationLag`
   - delete-ack / consumer-group semantics
3. Remaining operational semantics
   - `scheduler`
   - `telemetrySink`
   - `computeContention`
4. `Modern-system packs`
   - ChatGPT
   - AI/ML data infra
   - deployment pipeline
   - Google Docs collaboration
5. `Visual teaching modes`
   - incident replay
   - algorithm labs
   - iteration compare

# NS-Simulator: Node Behaviour Specification & Architecture Redesign

> **Purpose:** Exhaustive audit of every simulator node — what it does today, what it must do to be teachable, and the architectural changes required to get there.
>
> **Date:** June 2026
>
> **Key finding:** Every non-source node in the simulator runs identical logic. An L4 Load Balancer, a Redis Cache, a Kafka Broker, and a PostgreSQL Database all execute the same code path: `GGcKNode.handleArrival() → queue → sample service time → handleCompletion() → route to next`. The only differences are cosmetic (labels, icons) and numerical (seed-derived default service times). No node has behaviour that reflects what it actually does in the real world.

---

## Table of Contents

1. [How the Engine Works Today](#1-how-the-engine-works-today)
2. [The Core Problem](#2-the-core-problem)
3. [Node-by-Node Specification](#3-node-by-node-specification)
   - [3.1 Sources](#31-sources)
   - [3.2 Network & Routing](#32-network--routing)
   - [3.3 Compute](#33-compute)
   - [3.4 Storage & Data](#34-storage--data)
   - [3.5 Messaging & Streaming](#35-messaging--streaming)
   - [3.6 Security & Identity](#36-security--identity)
   - [3.7 Observability](#37-observability)
   - [3.8 Orchestration & Infrastructure](#38-orchestration--infrastructure)
   - [3.9 External & Integration](#39-external--integration)
   - [3.10 Auxiliary](#310-auxiliary)
   - [3.11 DNS & Certificates](#311-dns--certificates)
   - [3.12 Composites (Visual Only)](#312-composites-visual-only)
4. [OSI Layers, Protocols, and Layer-Aware Behaviour](#4-osi-layers-protocols-and-layer-aware-behaviour)
5. [Edge Specification: Properties, Constraints, and Node Compatibility](#5-edge-specification-properties-constraints-and-node-compatibility)
   - [5.1 Edge Properties Audit: What Exists vs. What Works](#51-edge-properties-audit-what-exists-vs-what-works)
   - [5.2 Edge Defaults by Path Type](#52-edge-defaults-by-path-type)
   - [5.3 Protocol-to-Node Compatibility Matrix](#53-protocol-to-node-compatibility-matrix)
   - [5.4 Mode-to-Node Compatibility Rules](#54-mode-to-node-compatibility-rules)
   - [5.5 Edge Defaults by Source→Target Pair](#55-edge-defaults-by-sourcetarget-pair)
   - [5.6 Edge Behaviour Traits (Engine-Level)](#56-edge-behaviour-traits-engine-level)
   - [5.7 EdgePropertiesPanel Adaptation](#57-edgepropertiespanel-adaptation)
   - [5.8 Edge Validation Rules](#58-edge-validation-rules)
   - [5.9 Implementation Priority for Edges](#59-implementation-priority-for-edges)
6. [Proposed Architecture Redesign](#6-proposed-architecture-redesign)
7. [Behavioural Trait System](#7-behavioural-trait-system)
8. [Implementation Priority](#8-implementation-priority)

---

## 1. How the Engine Works Today

### 1.1 The Single Code Path

Every node in the simulator (except sources and composites) is instantiated as a `GGcKNode` — a generic G/G/c/K queue. The engine processes events in a loop:

```
for each event in min-heap:
  switch event.type:
    request-generated → workload creates request, routing resolves target, enqueue edge transfer
    request-arrival   → node.handleArrival(request)
                        if workers free → start processing (sample service time distribution)
                        if queue has room → enqueue
                        else → reject (capacity_exceeded)
    processing-complete → node.handleCompletion(request)
                          routing.resolveTarget() → forward to next node
                          or if no outgoing edges → request-complete
    request-forwarded  → edge latency delay → request-arrival at target
    request-complete   → record metrics
    request-timeout    → record timeout
    request-rejected   → record rejection
```

**This loop is the same for every node type.** The engine (`engine.ts:238–270`) does a `switch` on event type but never on node type, component type, or category.

### 1.2 What Actually Differentiates Nodes Today

| Mechanism | Where | What It Does | Scope |
|---|---|---|---|
| **Service time mean** | `componentSpecs.ts:18–59` | Different `TYPE_MEAN_SERVICE_MS` per component type. E.g., `load-balancer-l4: 0.15ms`, `relational-db: 8ms`, `in-memory-cache: 0.1ms` | Affects how long `handleCompletion` takes. Does NOT change what the node does. |
| **Seed-derived defaults** | `paletteTemplates.ts` | Each palette entry has `{ throughput, load, queueDepth }` seeds that derive initial workers/capacity/service time | Initial config only. User can override everything in the UI. |
| **Routing strategy** | `routing.ts:211–222` | Nodes whose ID contains `"load-balancer"`, `"lb"`, `"ingress"`, or `"reverse-proxy"` use round-robin. Pub/Sub and Message Broker use broadcast. Everything else: uniform random or weighted. | String-match heuristic on node ID, not on component type. |
| **Security policy** | `engine.ts:668–695` | Nodes with `securityPolicy.blockRate > 0` or `droppedPackets > 0` probabilistically reject requests before queue admission | Only WAF, Firewall Rule, Security Group use this via seeds. But any node could have it. |
| **Error rate** | `engine.ts:352–367` | Nodes with `nodeErrorRate > 0` probabilistically fail requests after processing | Any node can have this. Not type-specific. |
| **Structural role** | `nodeSpecTypes.ts:10` | `source`, `processor`, `storage`, `router`, `sink`, `composite` | Used for UI rendering and serialization decisions. **Not used by the engine at all.** |
| **Profile** | `nodeSpecTypes.ts:12–24` | `source`, `router`, `compute-service`, `worker`, `datastore`, `broker`, `security-filter`, `control-plane`, `observability`, `integration`, `composite` | Used for UI categorization and validation. **Not used by the engine at all.** |

### 1.3 What This Means

An instructor who drops an "L4 Load Balancer" and an "L7 Load Balancer" onto the canvas gets two nodes that:
- Have different labels and icons
- Have slightly different default service times (0.15ms vs 0.4ms)
- Run the exact same code
- Support the exact same routing logic
- Cannot demonstrate any L4 vs L7 behavioural difference

The same is true for every pair of nodes. Redis Cache vs PostgreSQL DB? Same queue, different service time. CDN vs API Gateway? Same queue, different label. Kafka vs SQS? Same queue, different icon.

---

## 2. The Core Problem

For the simulator to teach, each node must have **observable behaviour that matches its real-world concept**. A student must be able to:

1. Place a node
2. Send traffic to it
3. See it behave in a way that demonstrates the concept it represents
4. Change its configuration and see the behaviour change in a way that matches their mental model

Today, every node demonstrates exactly one concept: "a queue that processes requests at a configurable rate." That's a valid queueing theory lesson, but it doesn't teach load balancing, caching, pub/sub, firewalling, or any other distributed systems concept.

**The fix is not to rewrite the engine.** The G/G/c/K queue is a good foundation — real infrastructure components are queues under the hood. The fix is to add **behavioural traits** that overlay type-specific logic on top of the queue. A cache node should still queue requests, but it should also have a hit/miss probability that determines whether the request is completed locally or forwarded downstream.

---

## 3. Node-by-Node Specification

For each node, I document:
- **Today:** What the node actually does in the engine
- **Real world:** What this component does in production infrastructure
- **Teaching gap:** What an instructor cannot demonstrate
- **Required behaviour:** The minimum simulation behaviour needed for teaching
- **Config knobs:** What students should be able to adjust to see different outcomes

### 3.1 Sources

#### Client App / Input Source

| Aspect | Detail |
|---|---|
| **Palette IDs** | `client-user`, `input-source` |
| **Today** | Generates requests via `WorkloadGenerator`. Supports 7 patterns (constant, Poisson, bursty, spike, diurnal, sawtooth, replay). Routes requests to first outgoing edge. Not a `GGcKNode` — no queue processing. |
| **Real world** | End users, mobile apps, browsers, or external systems that send requests |
| **Teaching gap** | None significant. This is the one node type with genuinely distinct behaviour. |
| **Required behaviour** | Current implementation is adequate. |
| **Possible enhancements** | Support multiple request types with different routing (e.g., 70% GET, 30% POST with different targets). Currently supports `requestDistribution` by weight but routing doesn't use `request.type` unless edges have conditions. |

---

### 3.2 Network & Routing

#### Load Balancer (Legacy)

| Aspect | Detail |
|---|---|
| **Palette ID** | `load-balancer` |
| **Today** | GGcKNode queue (mean service 0.2ms). Round-robin routing via ID substring match. Does not check target health. |
| **Real world** | Distributes traffic across backend servers. AWS ELB (Classic). |
| **Teaching gap** | Cannot show: health-check-aware routing, connection draining, sticky sessions. Routes to failed servers. |
| **Required behaviour** | Skip failed targets. Support configurable routing strategy (round-robin, weighted, least-connections). |
| **Config knobs** | `routingStrategy`, `healthCheckEnabled`, `stickySessionEnabled` |

#### Load Balancer L4 (NLB)

| Aspect | Detail |
|---|---|
| **Palette ID** | `load-balancer-l4` |
| **Today** | GGcKNode queue (mean service 0.15ms). Identical logic to L7 and Legacy LBs. |
| **Real world** | Operates at transport layer (TCP/UDP). Forwards connections without inspecting content. Very fast, very simple. AWS NLB. Cannot route by URL path, HTTP header, or request content. Preserves source IP. |
| **Teaching gap** | Cannot demonstrate any L4-specific behaviour. Same as L7 in every functional way. An instructor cannot explain "L4 doesn't inspect HTTP headers" because neither L4 nor L7 inspects anything. |
| **Required behaviour** | (1) Must NOT support conditional routing by `request.type` — this is an L7 feature. L4 can only route by connection, not by content. (2) Should have lower processing overhead than L7 (already true via service time, but should be enforced). (3) Should support: round-robin, weighted, least-connections. Should NOT support: path-based routing, header-based routing, host-based routing. |
| **Config knobs** | `routingStrategy` (limited to: round-robin, weighted, least-connections, source-ip-hash), `healthCheckEnabled`, `protocol` (TCP or UDP — affects metrics labels, not queue logic) |

#### Load Balancer L7 (ALB)

| Aspect | Detail |
|---|---|
| **Palette ID** | `load-balancer-l7` |
| **Today** | GGcKNode queue (mean service 0.4ms). Identical logic to L4. |
| **Real world** | Operates at application layer (HTTP/HTTPS/gRPC). Inspects request content: URL path, HTTP headers, host, cookies. Routes based on content rules. Can do SSL termination. AWS ALB. Higher latency than L4 because it must parse HTTP. |
| **Teaching gap** | Cannot demonstrate content-based routing as an L7-exclusive capability. Conditional routing via edge conditions works on any node, so students see no difference between L4 and L7. |
| **Required behaviour** | (1) Must support conditional routing by `request.type`, path, or headers — this is the core L7 differentiator. (2) Higher processing overhead than L4 (already true). (3) Should support: round-robin, weighted, least-connections, path-based routing, host-based routing. (4) The engine should ENFORCE that L4 nodes cannot use conditional edge routing, while L7 nodes can. This is the teachable moment: "L4 can't do this, L7 can." |
| **Config knobs** | `routingStrategy` (full set including path-based, host-based), `healthCheckEnabled`, `sslTermination` (adds processing overhead), `routingRules` (list of path → target mappings) |

**Key teaching requirement for L4 vs L7:** The simulator must make it impossible (or visibly wrong) to configure content-based routing on an L4 LB. When a student tries, the UI should explain: "L4 operates at the transport layer and cannot inspect HTTP content. Use an L7 Load Balancer for content-based routing." This constraint IS the lesson.

#### API Gateway

| Aspect | Detail |
|---|---|
| **Palette ID** | `api-gateway` |
| **Today** | GGcKNode queue (mean service 1ms). Same as any router. |
| **Real world** | Entry point for APIs. AWS API Gateway, Kong, Apigee. Does: request validation, authentication, rate limiting, request transformation, routing to backend services, response caching, throttling, API key management. |
| **Teaching gap** | Cannot demonstrate: rate limiting, authentication overhead, request transformation, API-level throttling. Behaves identically to a load balancer. |
| **Required behaviour** | (1) Rate limiting — configurable token-bucket rate limiter that rejects requests with `rate_limited` when exhausted. (2) Authentication overhead — configurable probability of auth rejection (simulating invalid API keys). (3) Content-based routing — same as L7 LB (API gateways are L7 devices). (4) Request transformation adds processing overhead. |
| **Config knobs** | `rateLimiter: { maxTokens, refillRatePerSecond }`, `authRejectionRate`, `routingRules`, `transformationOverheadMs` |

#### CDN

| Aspect | Detail |
|---|---|
| **Palette ID** | `cdn` |
| **Today** | GGcKNode queue (mean service 2ms). Forwards all requests downstream. No caching behaviour whatsoever. |
| **Real world** | Content Delivery Network. AWS CloudFront, Cloudflare. Caches content at edge locations. On cache hit: responds immediately from edge cache (very fast, no origin traffic). On cache miss: forwards to origin server, caches response, then responds. The entire point of a CDN is to REDUCE traffic to the origin. |
| **Teaching gap** | This is one of the most broken nodes for teaching. Adding a CDN to a topology has zero effect on downstream traffic. An instructor cannot demonstrate "CDN reduces database load" because the CDN forwards 100% of requests downstream. Students cannot see the fundamental concept: cache hit = fast + no origin traffic, cache miss = slow + origin traffic. |
| **Required behaviour** | (1) `cacheHitRate` (0.0–1.0) — probability that a request is served from cache. (2) On cache HIT: complete the request immediately with minimal latency (e.g., 1ms). Do NOT forward downstream. (3) On cache MISS: forward to origin (next node) via normal routing. (4) Cache hit should be visible in metrics: "X% of requests served from cache." (5) Time-to-live (TTL): optional cache expiry that degrades hit rate over time. |
| **Config knobs** | `cacheHitRate` (0.0–1.0), `cacheHitLatencyMs` (default: 1ms, the edge response time), `ttlSeconds` (optional, affects hit rate over time) |

#### Ingress Controller

| Aspect | Detail |
|---|---|
| **Palette ID** | `ingress-controller` |
| **Today** | GGcKNode queue (mean service 0.3ms). Round-robin routing. |
| **Real world** | Kubernetes Ingress (NGINX Ingress Controller, Traefik). Routes external HTTP traffic to Kubernetes services based on hostname and path rules. Essentially an L7 load balancer that's aware of Kubernetes service objects. |
| **Teaching gap** | Cannot demonstrate: path-based routing to different services (the core Ingress use case), TLS termination, host-based virtual hosting. Identical to a generic LB. |
| **Required behaviour** | Same as L7 LB: content-based routing by path and host. The difference from a standalone L7 LB is conceptual (Kubernetes context), not mechanical. For simulation purposes, the Ingress Controller should behave like an L7 LB with path/host routing. |
| **Config knobs** | Same as L7 LB: `routingRules`, `healthCheckEnabled`, `sslTermination` |

#### Reverse Proxy

| Aspect | Detail |
|---|---|
| **Palette ID** | `reverse-proxy` |
| **Today** | GGcKNode queue (mean service 0.5ms). Round-robin routing. |
| **Real world** | NGINX, HAProxy, Envoy. Sits in front of backend servers. Does: SSL termination, compression, caching, load balancing, request buffering, connection pooling. Key difference from a load balancer: a reverse proxy can also cache responses. |
| **Teaching gap** | Cannot demonstrate caching (same gap as CDN). Cannot show connection pooling or compression. Identical to an LB. |
| **Required behaviour** | (1) Optional caching (same `cacheHitRate` behaviour as CDN). (2) L7 routing. (3) Compression overhead (slightly higher processing time when enabled). |
| **Config knobs** | `cacheHitRate` (optional), `compressionEnabled` (adds latency overhead), `routingStrategy` |

#### Service Mesh

| Aspect | Detail |
|---|---|
| **Palette ID** | `service-mesh` |
| **Today** | GGcKNode queue (mean service 0.6ms). Round-robin routing. |
| **Real world** | Istio, Linkerd. Manages service-to-service communication via sidecar proxies injected alongside each service. Provides: mutual TLS, traffic management, observability, retries, circuit breaking, fault injection — all without application code changes. |
| **Teaching gap** | Cannot demonstrate: sidecar injection pattern, mTLS overhead, retry logic, circuit breaking, traffic splitting (canary deployments). Behaves like a single node, not a mesh of sidecars. |
| **Required behaviour** | (1) When placed in a topology, should conceptually represent the control plane. (2) Sidecar proxies (already in palette as "Sidecar Proxy") are the data plane — they should be placed adjacent to each service. (3) The service mesh node should be able to configure all its sidecars centrally: retry policy, circuit breaker settings, mTLS overhead. (4) For MVP: treat as an L7 router with built-in retry and circuit breaker config. |
| **Config knobs** | `retryPolicy: { maxAttempts, baseDelayMs }`, `circuitBreaker: { failureThreshold, recoveryTimeoutMs }`, `mtlsOverheadMs`, `trafficSplit: { canaryWeight }` |

#### NAT Gateway

| Aspect | Detail |
|---|---|
| **Palette ID** | `nat-gateway` |
| **Today** | GGcKNode queue (mean service 0.5ms). Generic routing. |
| **Real world** | AWS NAT Gateway. Allows instances in a private subnet to connect to the internet while preventing the internet from initiating connections. Translates private IP addresses to a public IP. |
| **Teaching gap** | Cannot demonstrate: directionality (outbound only), IP address translation, bandwidth limits. Behaves like a generic pass-through node. |
| **Required behaviour** | (1) Bandwidth cap — NAT gateways have throughput limits (e.g., 45 Gbps for AWS). Should reject/queue requests when throughput exceeds limit. (2) One-directional — should only be used on edges going from private subnet to internet. The UI could warn if used for inbound traffic. (3) For simulation: primarily a bandwidth-limited passthrough. The teaching value is in topology placement (private subnet → NAT → internet), not in complex node behaviour. |
| **Config knobs** | `bandwidthLimitMbps`, `direction: 'outbound-only'` (validation hint) |

#### VPN Gateway

| Aspect | Detail |
|---|---|
| **Palette ID** | `vpn-gateway` |
| **Today** | GGcKNode queue (mean service 2ms). Generic routing. |
| **Real world** | AWS VPN Gateway, IPSec tunnel endpoint. Encrypts traffic between VPCs or between VPC and on-premises. Adds significant latency due to encryption/decryption. |
| **Teaching gap** | Cannot demonstrate: encryption overhead scaling with traffic, bandwidth limits, tunnel redundancy. |
| **Required behaviour** | (1) Higher base latency (already has 2ms service time). (2) Encryption overhead that scales with request size — larger requests take longer. (3) Bandwidth limit. |
| **Config knobs** | `encryptionOverheadFactor` (multiplier on service time based on request size), `bandwidthLimitMbps`, `tunnelRedundancy` (number of active tunnels) |

#### Routing Rule / Routing Policy

| Aspect | Detail |
|---|---|
| **Palette IDs** | `routing-rule`, `routing-policy` |
| **Today** | GGcKNode queue (mean service 0.1ms). Generic passthrough routing. |
| **Real world** | Configuration objects that define how traffic is routed. Not physical components — they're rules attached to load balancers or API gateways. Routing rules match on path/host/header. Routing policies define traffic distribution (weighted, latency-based, failover). |
| **Teaching gap** | These are conceptual duplicates of L7 LB routing capabilities. |
| **Required behaviour** | These should be treated as configuration artifacts, not standalone nodes. They make more sense as properties of router nodes (LB, API Gateway) rather than separate palette entries. If kept as separate nodes, they should enforce: (1) Routing Rule = content-based matching (path, host, header). (2) Routing Policy = distribution strategy (weighted, failover, latency-based). |
| **Config knobs** | For Routing Rule: `matchType` (path, host, header), `matchPattern`, `targetNodeId`. For Routing Policy: `distributionStrategy` (weighted, failover, latency-based), `weights`. |

#### Edge Router

| Aspect | Detail |
|---|---|
| **Palette ID** | `edge-router` |
| **Today** | GGcKNode queue (mean service 0.8ms). Generic routing. |
| **Real world** | Network router at the edge of a network. Routes packets between networks. Operates at L3 (IP level). |
| **Teaching gap** | Cannot demonstrate: L3 routing (IP-based), routing table lookups, BGP/OSPF concepts. |
| **Required behaviour** | For simulation purposes, this is a pass-through node with latency. The teaching value is in topology placement (at network boundaries) and edge latency configuration (cross-region links), not in complex node-level behaviour. |
| **Config knobs** | Current config is adequate. Teaching comes from edge `pathType` (same-rack, cross-zone, cross-region, internet). |

#### Network Interface

| Aspect | Detail |
|---|---|
| **Palette ID** | `network-interface` |
| **Today** | GGcKNode queue (mean service very low). Generic passthrough. |
| **Real world** | AWS ENI (Elastic Network Interface). Physical or virtual network interface on a server. Has bandwidth limits and packet-per-second limits. |
| **Teaching gap** | Cannot demonstrate: bandwidth saturation, PPS limits. |
| **Required behaviour** | (1) Bandwidth cap. (2) Packets-per-second limit. Primarily a bandwidth-limited passthrough. |
| **Config knobs** | `bandwidthLimitMbps`, `ppsLimit` |

---

### 3.3 Compute

#### API Server / Generic Service / My Service

| Aspect | Detail |
|---|---|
| **Palette IDs** | `backend-server`, `generic-service`, `my-service` |
| **Today** | GGcKNode queue. Workers, capacity, service time distribution, timeout. |
| **Real world** | Application servers that process business logic. The most generic node type. |
| **Teaching gap** | Minimal. This is the node type that most naturally maps to the GGcKNode model. A server IS a queue that processes requests with configurable concurrency and service time. |
| **Required behaviour** | Current implementation is largely adequate. Enhancements: (1) CPU-bound vs I/O-bound processing mode — CPU-bound work scales with workers but has a hard cap at vCPU count; I/O-bound work can have more workers than vCPUs. (2) Memory pressure — when queue is deep, service time degrades (simulating GC pressure, swap). |
| **Config knobs** | Current knobs (workers, capacity, distribution, timeout) are good. Add: `processingMode: 'cpu-bound' | 'io-bound'`, `memoryPressureThreshold` (queue depth at which service time degrades). |

#### Serverless Function (Lambda)

| Aspect | Detail |
|---|---|
| **Palette ID** | `lambda-function` |
| **Today** | GGcKNode queue (mean service varies). Same as API Server. |
| **Real world** | AWS Lambda, Google Cloud Functions. Key differences from servers: (1) Cold start penalty — first invocation is slow. (2) Concurrency limit — hard cap on concurrent executions. (3) No persistent state. (4) Auto-scales to zero. (5) Billed per invocation, not per uptime. |
| **Teaching gap** | Cannot demonstrate: cold start latency, auto-scaling to zero, concurrency limits as a hard cap (vs. server's configurable workers), invocation-based billing model. Identical to a regular server. |
| **Required behaviour** | (1) Cold start — first N requests (or requests after idle period) incur additional latency sampled from `coldStartDistribution`. (2) Concurrency limit — hard cap (not soft queue) at `maxConcurrency`. Requests beyond this are throttled (429), not queued. (3) Timeout — Lambda has a hard 15-minute max timeout, but typical is 3–30 seconds. |
| **Config knobs** | `coldStartLatencyMs` (distribution), `maxConcurrency` (hard cap, rejects beyond this), `idleTimeoutMs` (time after last request before functions scale to zero, triggering cold start again), `timeoutMs` (hard cap at 900,000ms) |

#### Job Worker / Cron Job

| Aspect | Detail |
|---|---|
| **Palette IDs** | `async-worker`, `cron-job` |
| **Today** | GGcKNode queue. `asyncBoundary: true` on the palette template, but the engine does not use this flag. |
| **Real world** | Background processors. Job Workers pull from queues and process asynchronously. Cron Jobs run on a schedule independently of incoming traffic. |
| **Teaching gap** | Cannot demonstrate: pull-based processing (worker pulls from queue vs. queue pushes to worker), scheduled execution (cron), or the async nature (results not returned to caller). The `asyncBoundary` flag is purely cosmetic. |
| **Required behaviour** | (1) Job Worker: should always be downstream of async edges. The engine should enforce/encourage this. Processing is fire-and-forget — no response flows back to the caller. (2) Cron Job: should self-trigger on a schedule, independent of incoming traffic. Not request-driven. (3) Both: high queue tolerance (large capacity, slow processing OK). |
| **Config knobs** | Job Worker: current config adequate, but incoming edges should default to async. Cron Job: `scheduleIntervalMs`, `triggerSource: 'scheduled'` (generates own events on timer). |

#### Auth Service

| Aspect | Detail |
|---|---|
| **Palette ID** | `auth-service` |
| **Today** | GGcKNode queue (mean service varies). Same as any compute node. |
| **Real world** | Handles authentication (verify identity) and authorization (check permissions). Issues/validates tokens (JWT, OAuth). On the critical path for every authenticated request. |
| **Teaching gap** | Cannot demonstrate: token validation (fast) vs. token issuance (slow), auth failure (401/403) rates, the critical-path nature (if auth is down, everything is down). |
| **Required behaviour** | (1) Two processing modes with different latencies: token validation (fast, ~1ms) and token issuance/login (slow, ~50ms). Request type could determine which mode. (2) Auth rejection rate — configurable percentage of requests that fail authentication. Distinct from node error rate: these return 401/403, not 500. (3) Critical dependency — if this node fails, all downstream nodes should see increased errors (models the cascading effect of auth outage). |
| **Config knobs** | `validationLatencyMs`, `issuanceLatencyMs`, `authRejectionRate`, `isCriticalPath: true` |

#### Search Service

| Aspect | Detail |
|---|---|
| **Palette ID** | `search-service` |
| **Today** | GGcKNode queue. Same as any compute node. |
| **Real world** | Query processing service backed by a search index (Elasticsearch, Solr). Latency depends heavily on query complexity. |
| **Teaching gap** | Cannot demonstrate: variable latency based on query complexity, the distinction between simple lookups (fast) and complex aggregations (slow). |
| **Required behaviour** | (1) Variable service time based on request type — simple queries (fast distribution) vs. complex queries (slow distribution). (2) Connection to a search index storage node. |
| **Config knobs** | `simpleQueryLatencyMs`, `complexQueryLatencyMs`, `queryTypeDistribution` |

#### Sidecar Proxy

| Aspect | Detail |
|---|---|
| **Palette ID** | `sidecar-proxy` |
| **Today** | GGcKNode queue (mean service 0.18ms). Same as any compute node. |
| **Real world** | Envoy sidecar in a service mesh. Sits alongside every service, handling: TLS termination, retries, circuit breaking, observability, traffic management. Adds latency to every request (both inbound and outbound). |
| **Teaching gap** | Cannot demonstrate: per-request overhead (should be on both ingress and egress of a service), retry logic, circuit breaking, the fact that EVERY service gets one. |
| **Required behaviour** | (1) Small fixed latency addition on both inbound and outbound traffic for the associated service. (2) Retry on failure (configurable). (3) Circuit breaker (configurable). (4) Conceptually paired with a service — the UI should encourage placing one next to each service. |
| **Config knobs** | `perRequestOverheadMs`, `retryPolicy: { maxAttempts, baseDelayMs }`, `circuitBreaker: { failureThreshold, recoveryTimeoutMs }` |

---

### 3.4 Storage & Data

#### Primary DB (Relational/SQL)

| Aspect | Detail |
|---|---|
| **Palette ID** | `primary-db` |
| **Today** | GGcKNode queue (mean service 8ms). Same as any node. |
| **Real world** | PostgreSQL, MySQL, Aurora. Handles reads and writes. Writes go to a write-ahead log. Connections are limited and pooled. Complex queries are slow, simple lookups are fast. Supports transactions (ACID). |
| **Teaching gap** | Cannot demonstrate: read vs. write latency difference, connection pool exhaustion, the difference between OLTP queries (fast) and analytical queries (slow), replication lag to replicas. |
| **Required behaviour** | (1) Differentiate read vs. write processing time — writes are slower than reads (due to WAL, locking, replication). Request type (`read` vs `write`) determines which distribution is sampled. (2) Connection pool — workers represent connection pool size. When exhausted, requests queue (this is already modeled by GGcKNode). (3) Replication — when a write completes, optionally emit an async event to connected read replicas (simulating replication). |
| **Config knobs** | `readLatencyMs` (distribution), `writeLatencyMs` (distribution), `connectionPoolSize` (maps to workers), `replicationEnabled`, `replicationLagMs` |

#### Read Replica

| Aspect | Detail |
|---|---|
| **Palette ID** | `read-replica` |
| **Today** | GGcKNode queue (mean service similar to primary DB). Same as primary DB. |
| **Real world** | Read-only copy of a primary database. Receives replication stream from primary. Can serve read queries. Cannot serve writes. Has replication lag (data may be slightly stale). |
| **Teaching gap** | Cannot demonstrate: read-only enforcement (should reject writes), replication lag (data staleness), the scaling pattern of adding replicas for read-heavy workloads. |
| **Required behaviour** | (1) Read-only — should reject or redirect requests with type `write`. (2) Replication lag — metrics should show a configurable delay from primary (how stale the data is). (3) Same read performance as primary DB. |
| **Config knobs** | `readOnly: true` (rejects `write` request types), `replicationLagMs` |

#### Redis Cache (In-Memory)

| Aspect | Detail |
|---|---|
| **Palette ID** | `redis-cache` |
| **Today** | GGcKNode queue (mean service 0.1ms). Forwards all requests downstream. No caching. |
| **Real world** | In-memory key-value store. Sub-millisecond latency. Used as a cache layer: hit = return value (no downstream call), miss = pass through to database, store result, return. The entire point is to ABSORB traffic that would otherwise hit the database. |
| **Teaching gap** | Critical failure. Same as CDN: adding a Redis cache has zero effect on downstream traffic. Cannot demonstrate the fundamental cache concept. An instructor shows "add a cache to reduce DB load" but the DB sees the same traffic regardless. |
| **Required behaviour** | Same cache hit/miss model as CDN: (1) `cacheHitRate` (0.0–1.0). (2) On HIT: complete immediately with sub-millisecond latency, do NOT forward downstream. (3) On MISS: forward to downstream node (database), cache the result. (4) Cache eviction: when capacity is reached, LRU eviction (can model as decreasing hit rate under high load). |
| **Config knobs** | `cacheHitRate`, `cacheHitLatencyMs` (default: 0.1ms), `maxMemoryMb` (capacity limit, affects eviction), `evictionPolicy: 'lru' | 'lfu' | 'ttl'`, `ttlSeconds` |

#### NoSQL DB

| Aspect | Detail |
|---|---|
| **Palette ID** | `nosql-db` |
| **Today** | GGcKNode queue (mean service 3ms). Same as relational DB. |
| **Real world** | DynamoDB, MongoDB, Cassandra. Key-value or document model. Designed for horizontal scaling. Consistent read latency at any scale (DynamoDB's promise). Different consistency models (eventual vs. strong). |
| **Teaching gap** | Cannot demonstrate: consistent latency at scale (vs. relational DB's degradation under load), the read/write capacity unit model (DynamoDB), eventual consistency effects. |
| **Required behaviour** | (1) Consistent latency — service time should NOT degrade with load (unlike relational DB). Model as constant or narrow-distribution service time. (2) Provisioned throughput — configurable RCU/WCU (read/write capacity units) that act as a hard throughput cap. Requests beyond capacity get throttled. (3) Eventual consistency mode — reads may return stale data (for simulation: lower latency for eventual reads, higher for strongly consistent). |
| **Config knobs** | `readCapacityUnits`, `writeCapacityUnits`, `consistencyModel: 'eventual' | 'strong'`, `eventualConsistencyLatencyMs`, `strongConsistencyLatencyMs` |

#### Object Storage (S3)

| Aspect | Detail |
|---|---|
| **Palette ID** | `object-storage` |
| **Today** | GGcKNode queue (mean service 20ms). Same as any storage. |
| **Real world** | AWS S3, GCS. High latency but unlimited scale. Stores blobs. 99.999999999% durability. Eventual consistency on overwrites (historically). Latency depends on object size. |
| **Teaching gap** | Cannot demonstrate: latency scaling with object size, the difference from a database (high latency, unlimited capacity, no queries — just GET/PUT by key), eventual consistency on overwrites. |
| **Required behaviour** | (1) Latency proportional to request size (sizeBytes on request). (2) Unlimited capacity (very high or infinite queue capacity). (3) No complex queries — simple GET/PUT semantics. |
| **Config knobs** | `latencyPerMbMs` (latency scales with object size), `maxObjectSizeMb`, `storageClass: 'standard' | 'infrequent' | 'glacier'` (different latency profiles) |

#### Search Index (Elasticsearch)

| Aspect | Detail |
|---|---|
| **Palette ID** | `search-index` |
| **Today** | GGcKNode queue (mean service 10ms). Same as any storage. |
| **Real world** | Elasticsearch, OpenSearch. Full-text search and analytics. Write = index (slow, must update inverted index). Read = search (fast for simple, slow for complex aggregations). |
| **Teaching gap** | Cannot demonstrate: indexing overhead on writes, variable read latency based on query complexity. |
| **Required behaviour** | (1) Write (index) operations are significantly slower than reads. (2) Read latency varies by query type. (3) Index refresh interval — newly written data isn't immediately searchable. |
| **Config knobs** | `indexLatencyMs` (write distribution), `searchLatencyMs` (read distribution), `refreshIntervalMs` |

#### Time-Series DB

| Aspect | Detail |
|---|---|
| **Palette ID** | `time-series-db` |
| **Today** | GGcKNode queue (mean service 6ms). Same as any storage. |
| **Real world** | InfluxDB, TimescaleDB, Prometheus storage. Optimized for append-heavy workloads (metrics, events). Writes are fast (append-only). Reads can be slow (aggregating over time ranges). |
| **Teaching gap** | Cannot demonstrate: write-optimized behaviour (fast writes, slower reads), the time-range query pattern. |
| **Required behaviour** | (1) Fast writes (append-only, low service time). (2) Read latency proportional to query time range. |
| **Config knobs** | `writeLatencyMs` (low), `readLatencyPerHourOfRangeMs` (scales with query scope) |

#### Other Storage Nodes

For **Graph DB** (`graph-db`), **Vector DB** (`vector-db`), **Data Warehouse** (`data-warehouse`), **Data Lake** (`data-lake`), **KV Store** (`kv-store`):

| Aspect | Detail |
|---|---|
| **Today** | All identical GGcKNode queues with different default service times. |
| **Teaching gap** | Cannot demonstrate any type-specific behaviour. |
| **Required behaviour (per type):** | |
| **Graph DB** | Traversal queries scale with depth/hops. Single-hop lookups are fast, multi-hop traversals are slow. Config: `hopLatencyMs`, `maxTraversalDepth`. |
| **Vector DB** | ANN search latency scales with index size and dimensions. Config: `dimensions`, `indexSizeMultiplier`. |
| **Data Warehouse** | OLAP queries are slow (seconds to minutes). Not for OLTP. Very high latency but can process massive data volumes. Config: `queryLatencyMs` (wide distribution, 100ms–30s). |
| **Data Lake** | Raw storage + query. Even higher latency than data warehouse. Schema-on-read. Config: `scanLatencyPerGbMs`. |
| **KV Store** | Ultra-fast lookups by key. Sub-millisecond. Similar to Redis but without cache semantics. Config: `lookupLatencyMs` (very low, narrow distribution). |

---

### 3.5 Messaging & Streaming

#### Message Queue (SQS / RabbitMQ)

| Aspect | Detail |
|---|---|
| **Palette ID** | `message-queue` |
| **Today** | GGcKNode queue. `asyncBoundary: true` on palette (not used by engine). Same as any other node. |
| **Real world** | Point-to-point message delivery. Producer sends message to queue. One consumer receives and processes each message. Messages are buffered until consumed. Decouples producer from consumer. Dead letter queue for failed messages. Visibility timeout. |
| **Teaching gap** | Cannot demonstrate: decoupling (producer doesn't wait for consumer), message buffering (queue depth growing when consumers are slow), dead letter queue (failed messages go to a separate queue), exactly-once vs at-least-once delivery, visibility timeout. |
| **Required behaviour** | (1) Producer-side: accept the message and complete the producer's request immediately (acknowledge receipt). The producer should NOT wait for the consumer to process. (2) Consumer-side: messages are pulled by consumers at their own pace. If consumer is slow, queue depth grows visibly. (3) Dead letter queue — after N failed processing attempts, move message to a configured DLQ node. (4) Deduplication — optionally reject duplicate message IDs. |
| **Config knobs** | `deliverySemantics: 'at-least-once' | 'at-most-once' | 'exactly-once'`, `visibilityTimeoutMs`, `maxReceiveCount` (before DLQ), `dlqNodeId`, `maxRetentionMs` |

#### Event Broker (Kafka)

| Aspect | Detail |
|---|---|
| **Palette ID** | `message-broker` |
| **Today** | GGcKNode queue. `routingStrategy: 'broadcast'` — sends to all outgoing edges. |
| **Real world** | Apache Kafka. Distributed log. Key differences from a queue: (1) Messages are NOT removed after consumption — they persist on the log. (2) Multiple consumer groups can each read the full stream independently. (3) Messages are partitioned by key — ordering guaranteed within a partition. (4) Very high throughput. (5) Consumer lag is a key metric (how far behind the consumer is). |
| **Teaching gap** | Broadcast routing approximates fan-out to multiple consumers, which is partially correct. But cannot demonstrate: consumer group independence, partition-level ordering, consumer lag, the difference from a queue (messages persist vs. messages are consumed). |
| **Required behaviour** | (1) Fan-out to all downstream consumer groups (broadcast is correct for this). (2) Consumer lag metric — track how many messages each consumer group hasn't processed yet. (3) Ordering within partitions — if request has a partition key, requests with the same key go to the same downstream partition/consumer. (4) Retention — messages don't disappear after consumption (for Kafka this is implicit; simulate by not counting consumption as "removing" from the broker). |
| **Config knobs** | `partitionCount`, `replicationFactor`, `retentionMs`, `consumerGroups` (list of downstream node groups) |

#### Pub/Sub

| Aspect | Detail |
|---|---|
| **Palette ID** | `pub-sub` |
| **Today** | GGcKNode queue. `routingStrategy: 'broadcast'`. Same as Kafka. |
| **Real world** | Google Cloud Pub/Sub, AWS SNS + SQS. Topic-based publish/subscribe. Publisher sends to a topic. All subscribers to that topic receive a copy. Unlike Kafka: messages are typically deleted after delivery. Push-based (system pushes to subscribers) vs. pull-based. |
| **Teaching gap** | Broadcast routing is correct for fan-out. Cannot demonstrate: topic filtering (subscribers filter by message attributes), push vs. pull delivery, message acknowledgment. |
| **Required behaviour** | (1) Broadcast to all subscribers (already works). (2) Topic/attribute filtering — subscribers can filter which messages they receive based on `request.type` or attributes. (3) Acknowledgment — unacknowledged messages are redelivered. |
| **Config knobs** | `deliveryMode: 'push' | 'pull'`, `filterExpression` (per-subscriber edge), `ackDeadlineMs` |

#### Event Stream

| Aspect | Detail |
|---|---|
| **Palette ID** | `stream` |
| **Today** | GGcKNode queue. Same as any storage node. |
| **Real world** | AWS Kinesis Data Streams. Ordered sequence of records. Similar to Kafka but managed. Shard-based throughput model. |
| **Teaching gap** | Cannot demonstrate: shard-based throughput limits, ordered processing, the difference from a queue or topic. |
| **Required behaviour** | (1) Shard-based capacity — each shard handles X reads/sec and Y writes/sec. Total throughput = shards × per-shard capacity. (2) Ordering within shard. |
| **Config knobs** | `shardCount`, `readCapacityPerShard`, `writeCapacityPerShard`, `retentionHours` |

---

### 3.6 Security & Identity

#### WAF (Web Application Firewall)

| Aspect | Detail |
|---|---|
| **Palette ID** | `waf` |
| **Today** | GGcKNode queue. Has `blockRate` in security policy. Probabilistically blocks a percentage of requests with `security_blocked` status. |
| **Real world** | AWS WAF, Cloudflare WAF. Inspects HTTP requests against rules. Blocks malicious requests (SQL injection, XSS, bot traffic). Rules match on IP, headers, body, URI, query string. Rate-based rules throttle by IP. |
| **Teaching gap** | The block rate is realistic for a simple model — a WAF does block a percentage of traffic. However: cannot demonstrate rule-based blocking (block by request type or attribute, not just probability), cannot distinguish between different attack types, cannot show rate-based blocking (block IPs that exceed a rate). |
| **Required behaviour** | (1) Probability-based blocking is a reasonable simplification (already exists). (2) Rule-based blocking — block requests matching a condition (e.g., `request.type === 'attack'`). This would let instructors create attack traffic and show the WAF filtering it. (3) Rate-based blocking — block requests exceeding a per-source rate. |
| **Config knobs** | Current `blockRate` is adequate for basic teaching. Add: `blockRules` (list of conditions that trigger blocking), `rateLimitPerSourceRps` |

#### Firewall Rule

| Aspect | Detail |
|---|---|
| **Palette ID** | `firewall-rule` |
| **Today** | GGcKNode queue. Has `droppedPackets` in security policy. |
| **Real world** | Network-level packet filter. Operates at L3/L4. Drops packets based on IP, port, protocol. Stateless (each packet evaluated independently) or stateful (tracks connections). |
| **Teaching gap** | The dropped packets rate is a reasonable L3/L4 simplification. Cannot demonstrate: the difference from WAF (L3/L4 vs L7 — firewall drops packets, WAF blocks HTTP requests), stateful vs stateless filtering. |
| **Required behaviour** | (1) Drops packets (already exists via `droppedPackets`). (2) The key teaching difference from WAF: firewall operates at L3/L4 (drops by packet, no HTTP awareness), WAF operates at L7 (inspects HTTP content). In simulation: firewall should use `droppedPackets`, WAF should use `blockRate`. Firewall should NOT support content-based rules (that's L7). |
| **Config knobs** | `droppedPacketRate`, `allowedProtocols` (only pass traffic matching specified protocols) |

#### Security Group

| Aspect | Detail |
|---|---|
| **Palette ID** | `security-group` |
| **Today** | GGcKNode queue. Has both `blockRate` and `droppedPackets`. |
| **Real world** | AWS Security Group. Stateful firewall at the instance level. Allow/deny rules based on IP, port, protocol. Default deny all inbound, allow all outbound. |
| **Teaching gap** | Cannot demonstrate: stateful nature (return traffic is automatically allowed), the allow/deny rule model, the difference from a NACL (Network ACL is stateless, Security Group is stateful). |
| **Required behaviour** | Similar to Firewall but stateful. For simulation: (1) Default-deny inbound (unless edge is marked as allowed). (2) Return traffic automatically allowed (stateful). In practice, the simulation already handles this implicitly since requests flow along defined edges. The teaching value is in topology placement and understanding the concept, not in complex packet-level simulation. |
| **Config knobs** | `defaultPolicy: 'deny-all'`, `allowRules` (list of source nodes allowed through) |

---

### 3.7 Observability

#### Metrics Collector / Log Collector / Tracing Collector / Centralized Logging

| Aspect | Detail |
|---|---|
| **Palette IDs** | `metrics-collector-agent`, `log-collector-agent`, `distributed-tracing-collector`, `log-aggregation-service` |
| **Today** | All GGcKNode queues with `asyncBoundary: true` on palette (unused by engine). Same as any compute node. |
| **Real world** | Prometheus/Grafana (metrics), Fluentd/Loki (logs), Jaeger/OpenTelemetry (traces). Key property: they receive telemetry data asynchronously and must NOT be on the critical path. If the metrics collector goes down, application traffic should be unaffected. |
| **Teaching gap** | Cannot demonstrate: the async/non-blocking nature (these nodes should receive traffic on async edges and never affect the producer's latency), the difference between metrics/logs/traces, sampling (not every request generates a trace). |
| **Required behaviour** | (1) Must be connected via async edges — the engine should enforce or strongly warn if sync edges are used. (2) If these nodes fail or become saturated, it should NOT affect upstream application nodes. This is the core teaching point: "observability is a separate plane." (3) For tracing: should support sampling (only trace 1% of requests). The engine already has `traceSampleRate` but it's global, not per-node. |
| **Config knobs** | Current config is adequate. Key teaching is enforced via async edges. Add: `samplingRate` for tracing collector. |

#### Alerting Engine

| Aspect | Detail |
|---|---|
| **Palette ID** | `alerting-engine` |
| **Today** | GGcKNode queue. Sink node (no outgoing edges). |
| **Real world** | PagerDuty, OpsGenie, webhook alerting. Receives alert triggers and sends notifications. |
| **Teaching gap** | Cannot demonstrate: threshold-based alerting (trigger when metric exceeds threshold), alert deduplication, escalation. |
| **Required behaviour** | For simulation: adequate as a sink. The teaching value is in showing it exists as the end of the observability pipeline. Advanced: could emit visible "alert fired" events in the UI when upstream metrics exceed thresholds. |
| **Config knobs** | `alertThresholds` (list of metric conditions that trigger visible alerts in UI) |

#### Health Check Manager

| Aspect | Detail |
|---|---|
| **Palette ID** | `health-check-monitor` |
| **Today** | GGcKNode queue. Same as any node. |
| **Real world** | Synthetic monitoring that periodically probes nodes to check if they're healthy. ALB health checks, Kubernetes liveness/readiness probes. |
| **Teaching gap** | Critical gap: this node should be the mechanism that informs load balancers about failed targets. Currently it does nothing — it's just a queue that processes requests. The LB routes to dead servers because nothing tells it they're dead. |
| **Required behaviour** | (1) Periodically sends health check probes to monitored nodes (on a configurable interval). (2) Reports node health status to registered load balancers. (3) When a monitored node fails the health check, the health check manager marks it unhealthy, and LBs stop routing to it. (4) When the node recovers, marks it healthy again after N consecutive successes. |
| **Config knobs** | `checkIntervalMs`, `unhealthyThreshold` (consecutive failures before marking unhealthy), `healthyThreshold` (consecutive successes before marking healthy), `monitoredNodes` (list of node IDs to check), `registeredBalancers` (list of LB node IDs to notify) |

---

### 3.8 Orchestration & Infrastructure

#### Discovery Service (Service Registry)

| Aspect | Detail |
|---|---|
| **Palette ID** | `discovery-service` |
| **Today** | GGcKNode queue. Same as any node. |
| **Real world** | Consul, Eureka, Kubernetes service discovery. Services register themselves. Clients query to find available instances of a service. Enables dynamic routing without hardcoded addresses. |
| **Teaching gap** | Cannot demonstrate: service registration, dynamic discovery, the difference from static routing (hardcoded edges in the topology). |
| **Required behaviour** | For simulation: primarily conceptual. The teaching value is in understanding WHY service discovery exists (dynamic environments where instances come and go). For advanced simulation: could be the source of truth that load balancers query to find available targets, replacing the static edge-based routing. |
| **Config knobs** | `registeredServices` (list of node IDs that register), `heartbeatIntervalMs`, `deregistrationTimeoutMs` |

#### Config Store / Secrets Manager / Feature Flag Service

| Aspect | Detail |
|---|---|
| **Palette IDs** | `config-store`, `secrets-manager`, `feature-flag-service` |
| **Today** | All GGcKNode queues. Same as any node. |
| **Real world** | Consul KV, AWS Parameter Store (config). AWS Secrets Manager, Vault (secrets). LaunchDarkly, Unleash (feature flags). Provide configuration data to services at runtime. Low throughput, high availability requirement. |
| **Teaching gap** | Cannot demonstrate: configuration change propagation, secrets rotation, feature flag toggle effects. |
| **Required behaviour** | For simulation: these are low-throughput, high-availability services. The teaching value is in topology placement (every service depends on them) and understanding the criticality (if config store is down, services can't start or reconfigure). Current GGcKNode model is adequate for basic teaching. |
| **Config knobs** | Current config adequate. `isCriticalDependency: true` could enforce that dependent services fail if this node is down. |

---

### 3.9 External & Integration

#### External Service / Output Sink

| Aspect | Detail |
|---|---|
| **Palette IDs** | `external-service`, `output-sink` |
| **Today** | GGcKNode queue. Sink role (no outgoing edges typically). |
| **Real world** | Third-party APIs (Stripe, Twilio, SendGrid). Uncontrolled by the system designer. Variable latency. May rate-limit the caller. |
| **Teaching gap** | Cannot demonstrate: rate limiting from the external service side, variable latency (third-party APIs are unpredictable), the risk of depending on external services (no control over availability). |
| **Required behaviour** | (1) High and variable latency (wide distribution, e.g., log-normal with high sigma). (2) Rate limiting — returns 429 when caller exceeds the external service's rate limit. (3) Higher error rate than internal services. |
| **Config knobs** | `rateLimitRps` (caller is throttled beyond this), `errorRate` (higher default than internal services, e.g., 1–5%), `latencyDistribution` (wide/unpredictable) |

#### LLM Gateway

| Aspect | Detail |
|---|---|
| **Palette ID** | `llm-gateway` |
| **Today** | GGcKNode queue (mean service 6ms). Same as any compute node. |
| **Real world** | Proxy for LLM API calls (Claude, GPT). Very high latency (1–60 seconds per request). Token-based rate limiting. Streaming responses. Request size (prompt tokens) and response size (completion tokens) dramatically affect latency. |
| **Teaching gap** | Cannot demonstrate: extremely high and variable latency, token-based rate limiting, the unique cost/latency profile of LLM calls. 6ms default service time is wildly unrealistic (real LLM calls are 1000–60000ms). |
| **Required behaviour** | (1) Very high latency (log-normal distribution, mean 2000ms, high variance). (2) Token-based rate limiting (tokens per minute, not just requests per second). (3) Latency proportional to prompt + completion tokens. |
| **Config knobs** | `meanLatencyMs` (default: 2000ms), `tokensPerMinuteLimit`, `promptTokensPerRequest`, `completionTokensPerRequest` |

---

### 3.10 Auxiliary

#### Sharding / Hashing

| Aspect | Detail |
|---|---|
| **Palette IDs** | `sharding`, `hashing` |
| **Today** | GGcKNode queue. Router role with passthrough routing. |
| **Real world** | Sharding distributes data across multiple storage nodes based on a shard key. Hashing (consistent hashing) determines which shard a key maps to. Ensures even distribution and minimal re-mapping when shards are added/removed. |
| **Teaching gap** | Cannot demonstrate: key-based routing to specific shards (requests with the same key always go to the same shard), even distribution across shards, hot shard problems (one shard gets disproportionate traffic), the effect of adding/removing a shard. |
| **Required behaviour** | (1) Key-based deterministic routing — requests with the same partition key always route to the same downstream shard node. (2) Consistent hashing — adding a shard re-routes only 1/N of keys, not all keys. (3) Hot shard detection — if one shard gets disproportionate traffic, it should be visible in per-node metrics. |
| **Config knobs** | `hashAlgorithm: 'consistent' | 'modulo'`, `virtualNodes` (for consistent hashing ring), `shardKeyField` (which request attribute to hash on) |

#### Shard Node / Partition Node

| Aspect | Detail |
|---|---|
| **Palette IDs** | `shard-node`, `partition-node` |
| **Today** | GGcKNode queue. Storage role. |
| **Real world** | Individual shard/partition of a distributed database. Contains a subset of the data. Independent failure domain. |
| **Teaching gap** | Cannot demonstrate: that each shard has independent capacity and failure (already partially modeled via GGcKNode), the hot shard problem. |
| **Required behaviour** | Current GGcKNode model is adequate — each shard IS an independent queue with its own capacity. The teaching value comes from the Sharding/Hashing node routing to them correctly. |
| **Config knobs** | Current config adequate. Each shard is a standard queue. |

---

### 3.11 DNS & Certificates

#### DNS Server / DNS Resolver

| Aspect | Detail |
|---|---|
| **Palette IDs** | `dns-server`, `dns` |
| **Today** | GGcKNode queue. Router role with passthrough routing. |
| **Real world** | DNS resolves domain names to IP addresses. DNS Resolver (client-side, recursive) queries DNS Server (authoritative). Responses are cacheable (TTL). Route 53 supports routing policies: simple, weighted, latency-based, failover, geolocation. |
| **Teaching gap** | Cannot demonstrate: DNS caching (resolved names are cached, subsequent requests don't hit DNS again), DNS routing policies (weighted, failover, latency-based), TTL-based cache expiry. |
| **Required behaviour** | (1) DNS caching — first request for a name incurs DNS latency, subsequent requests within TTL are resolved instantly (cache hit). Same `cacheHitRate` pattern as CDN/Redis but with TTL as the driver. (2) Routing policies — weighted, failover (route to secondary when primary is unhealthy), latency-based (route to lowest-latency target). |
| **Config knobs** | `cacheTtlSeconds`, `routingPolicy: 'simple' | 'weighted' | 'failover' | 'latency-based' | 'geolocation'` |

---

### 3.12 Composites (Visual Only)

#### VPC Region / Availability Zone / Subnet

| Aspect | Detail |
|---|---|
| **Palette IDs** | `vpc-region`, `availability-zone`, `subnet` |
| **Today** | Visual container nodes. `serializable: false` — not included in simulation. Pure UI grouping. |
| **Real world** | Network isolation boundaries. VPC = Virtual Private Cloud (isolated network). AZ = independent failure domain within a region. Subnet = IP address range within an AZ (public or private). |
| **Teaching gap** | Cannot demonstrate: network isolation (nodes in different VPCs can't communicate without peering), AZ-level failure (bringing down an AZ should fail all nodes inside it), public vs. private subnet (private subnet has no direct internet access). |
| **Required behaviour** | These are visual-only and that's acceptable for MVP. The teaching value is in understanding the topology hierarchy. Advanced: (1) AZ failure — failing an AZ composite should fail all child nodes. (2) Subnet isolation — edges between different subnets should automatically get higher latency. (3) Private subnet enforcement — nodes in a private subnet can't have edges directly from the internet; they need a NAT Gateway. |
| **Config knobs** | `isPublic: true | false` (for subnets), `failureMode: 'independent'` (for AZs). These are validation/enforcement knobs, not simulation knobs. |

---

## 4. OSI Layers, Protocols, and Layer-Aware Behaviour

### 4.1 The Problem: Protocols Are Decorative

Every edge in the simulator has a `protocol` field that accepts one of: `https`, `grpc`, `tcp`, `udp`, `websocket`, `amqp`, `kafka`. This field is:

- **Defined** in the type system (`EdgeDefinition.protocol` in `types.ts:315`)
- **Set** in topology JSON files and mock topologies
- **Validated** by the schema validator (`validator.ts:361`)
- **Never read** by the engine, routing table, or any node

The protocol label is purely cosmetic. An edge labeled `tcp` produces identical simulation behaviour to one labeled `https`, `grpc`, or `kafka`. The engine processes all edges the same way: sample latency from the edge's distribution, schedule a `request-arrival` event at the target after the delay.

This means the simulator cannot teach **any** protocol-level concept:

- TCP vs UDP (reliable vs unreliable)
- HTTP vs gRPC (text vs binary, request-response vs streaming)
- WebSocket (persistent connection, bidirectional)
- AMQP vs Kafka (message broker protocols)
- TLS/SSL overhead
- Connection establishment overhead (TCP handshake)

### 4.2 OSI Layer Mapping of Simulator Nodes

The OSI model is Week 1–2 material in the Computer Networks course. The simulator has nodes that operate at different layers, but this layer identity has zero effect on behaviour.

| OSI Layer | Layer Name | Simulator Nodes That Should Operate Here | What They Should Do at This Layer | What They Actually Do |
|---|---|---|---|---|
| **L7** | Application | L7 Load Balancer, API Gateway, WAF, CDN, Reverse Proxy, Ingress Controller | Inspect HTTP/gRPC content: URL path, headers, cookies, request body. Route by content. Modify requests (rewrite, transform). Terminate SSL. | Same as L4. No content inspection. |
| **L6** | Presentation | *(No dedicated nodes — see note below)* | Data encoding (JSON/protobuf), encryption (TLS), compression (gzip). | N/A |
| **L5** | Session | *(No dedicated nodes — see note below)* | Session establishment, maintenance, teardown. | N/A |
| **L4** | Transport | L4 Load Balancer, NAT Gateway, Firewall Rule, Security Group | Forward TCP/UDP connections without inspecting payload. Route by IP:port tuple. Track connections (stateful) or not (stateless). Cannot see HTTP headers or URL paths. | Same as L7. No transport-layer constraints. |
| **L3** | Network | Edge Router, VPN Gateway, NAT Gateway | Route by IP address. Apply routing tables. Perform NAT (address translation). | Same as L4/L7. No IP-level logic. |
| **L2/L1** | Data Link / Physical | Network Interface | Frame-level operations, bandwidth limits. | Same as everything else. |
| **Application Protocol** | (Within L7) | gRPC edges, AMQP edges, Kafka edges, WebSocket edges | Different serialisation overhead, connection model (long-lived vs per-request), multiplexing behaviour. | All identical. Protocol label ignored. |

**Why L5 (Session) and L6 (Presentation) have no simulator nodes:**

The OSI model defines 7 layers, but L5 and L6 have no distinct representation in modern infrastructure — and therefore no dedicated node in the simulator:

- **L5 — Session Layer:** Manages connection sessions (open, close, resume). In theory, this is a separate concern. In practice, TCP (L4) already handles connection lifecycle (3-way handshake, keepalive, teardown), and application-level session management (cookies, JWT tokens, OAuth flows) is handled by L7 services. No real-world infrastructure component operates purely as a "session layer device." In the simulator, session-like behaviour appears as a property of L7 nodes (e.g., `stickySessionEnabled` on load balancers) and edge properties (e.g., persistent connections / keepalive), not as a separate node.

- **L6 — Presentation Layer:** Handles data format translation, encryption, and compression. In practice, TLS encryption runs between L4 and L7 and is modeled as an edge property in the simulator (`protocol: https` implies TLS termination at the receiving node). Serialization format (JSON vs protobuf vs Avro) is an application concern inside L7 nodes. Compression (gzip, brotli) is a feature of L7 proxies like Nginx or CDNs. None of these justify a standalone node — they're properties of existing nodes and edges.

This matches how the TCP/IP model (which the real world actually uses) collapses L5, L6, and L7 into a single "Application" layer. The simulator follows the same practical reality: L5/L6 concerns exist but are absorbed into L4 edge properties (TCP connections), L7 node configurations (session stickiness, TLS termination), and edge protocol settings.

### 4.3 What Layer-Awareness Means for Teaching

The reason layers matter for teaching is that each layer **constrains what the component can see and do**. This constraint IS the concept:

| Teaching Concept | How It Should Manifest in the Simulator |
|---|---|
| "L4 can't see HTTP headers" | An L4 LB should be **unable** to use conditional routing by `request.type`. If a student tries, the simulator should explain why: "L4 operates at the transport layer. It sees TCP/UDP connections, not HTTP content." |
| "L7 adds latency because it parses HTTP" | An L7 LB should have measurably higher processing overhead than L4, and the metrics should attribute it to "HTTP parsing overhead." |
| "WAF operates at L7" | The WAF should be able to block based on request attributes (URL pattern, header values). A firewall at L4 should only block by connection-level criteria (drop rate), not by content. |
| "TCP is reliable, UDP is not" | Edges with protocol `tcp` should guarantee delivery (all packets arrive). Edges with protocol `udp` should have a configurable packet loss probability that models real UDP behaviour (no retransmission, packets can be lost). |
| "TCP has connection setup overhead" | Edges with protocol `tcp` should add a one-time handshake latency for the first request on a connection. Subsequent requests on the same connection (keep-alive) skip the handshake. |
| "gRPC uses HTTP/2 multiplexing" | gRPC edges should be able to handle multiple concurrent requests on a single connection without head-of-line blocking. HTTP/1.1 edges should show head-of-line blocking under concurrent requests. |
| "TLS adds encryption overhead" | Edges with protocol `https` should have slightly higher latency than `http` (if we add it) or `tcp`, reflecting the TLS handshake and encryption cost. |
| "Kafka uses a binary protocol optimised for throughput" | Kafka edges should support batching (multiple messages per request) and have very high throughput but higher per-request latency than HTTP. |

### 4.4 Current Protocol Field: What Each Should Do

#### TCP (`protocol: 'tcp'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **Reliability** | Same as UDP — no packet loss model | Reliable delivery. Packet loss on the edge triggers retransmission (adds latency) rather than data loss. |
| **Connection setup** | None | First request between two nodes incurs a 3-way handshake overhead (~1.5× round-trip latency). Subsequent requests reuse the connection (if within keepalive window). |
| **Flow control** | None | Optional: when receiver queue is nearly full, sender backs off (reduces throughput). This models TCP flow control. Not critical for basic teaching. |
| **Congestion control** | None | Optional: when edge latency increases (congestion signal), sender reduces rate. Models TCP congestion avoidance. Advanced topic. |
| **Ordering** | Implicit (events are sequential) | Guaranteed in-order delivery. Already true in the simulator since events are processed sequentially. |

**Teaching value:** "TCP guarantees delivery and ordering, but at the cost of connection setup time and reduced throughput under congestion."

#### UDP (`protocol: 'udp'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **Reliability** | Same as TCP | Unreliable. Packets can be lost based on edge `packetLossRate`. Lost packets are NOT retransmitted — they're gone. |
| **Connection setup** | Same as TCP (none) | None — UDP is connectionless. No handshake. First request has the same latency as subsequent requests. |
| **Ordering** | Same as TCP | No ordering guarantee. Packets can arrive out of order (for simulation: not critical to model, but could be noted in metrics). |
| **Overhead** | Same as TCP | Lower per-packet overhead than TCP (no ACKs, no sequence numbers). Slightly lower edge latency. |

**Teaching value:** "UDP is faster and simpler than TCP, but packets can be lost. Used for real-time applications (gaming, video, DNS) where retransmission would be worse than loss."

**The key teaching experiment:** A student connects two nodes — once with TCP and once with UDP. They set the edge `packetLossRate` to 5%. With TCP: 0% data loss (retransmissions handle it) but higher latency under loss. With UDP: 5% data loss but consistently low latency. THIS is the L4 transport layer lesson.

#### HTTPS (`protocol: 'https'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **TLS overhead** | None — same as TCP | TLS handshake on first request (adds ~2× round-trip latency for full handshake, ~1× for session resumption). Per-request encryption/decryption overhead (small but measurable, ~0.1ms). |
| **Content visibility** | None | Enables L7 features: content-based routing, WAF inspection, request transformation. Nodes connected via HTTPS can see the request content. Nodes connected via TCP cannot. |
| **Certificate validation** | None | Optional: configurable probability of certificate error (simulating expired/invalid certs). |

**Teaching value:** "HTTPS = HTTP + TLS. The encryption adds latency (handshake + per-request overhead) but enables security and L7 features."

#### gRPC (`protocol: 'grpc'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **HTTP/2 multiplexing** | None | Multiple requests over a single connection without head-of-line blocking. Models as: no connection setup overhead after the first request, and concurrent requests don't block each other. |
| **Binary serialisation** | None | Slightly lower per-request overhead than HTTP/JSON (smaller payload, faster parsing). Models as: slightly lower edge latency. |
| **Streaming** | None | Supports server streaming, client streaming, and bidirectional streaming. For simulation: streaming edges have a long-lived connection with continuous data flow rather than discrete request-response. |

**Teaching value:** "gRPC uses HTTP/2 for multiplexing and Protocol Buffers for compact serialisation. Lower latency than REST for service-to-service communication."

#### WebSocket (`protocol: 'websocket'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **Persistent connection** | None | Single connection establishment (HTTP upgrade), then bidirectional messaging over the same connection. No per-message connection overhead. |
| **Bidirectional** | Requests flow one way | Both sides can send messages at any time. Server can push to client without client requesting. |
| **Connection cost** | None | Higher initial cost (HTTP upgrade handshake) but much lower per-message cost than HTTP. |

**Teaching value:** "WebSocket maintains a persistent connection for real-time bidirectional communication. Better than HTTP polling for live updates."

#### AMQP (`protocol: 'amqp'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **Message broker protocol** | Same as any edge | Used between message producers and RabbitMQ/AMQP brokers. Features: message acknowledgment, prefetch/QoS control, exchange-based routing (direct, topic, fanout, headers). |
| **Acknowledgment** | None | Messages require explicit ACK from consumer. Unacknowledged messages are redelivered. |
| **Prefetch** | None | Consumer limits how many unacknowledged messages it receives (backpressure). |

**Teaching value:** "AMQP provides reliable message delivery with acknowledgment and consumer flow control."

#### Kafka protocol (`protocol: 'kafka'`)

| Aspect | Today | Required for Teaching |
|---|---|---|
| **Batching** | None | Producers batch multiple messages into a single request for throughput. Higher per-batch latency but much higher overall throughput. |
| **Partitioning** | None | Messages are partitioned by key. Each partition is an ordered log. Consumer reads from assigned partitions. |
| **Consumer groups** | None | Multiple consumers in a group split partitions. Different groups each see all messages. |

**Teaching value:** "Kafka's protocol optimises for throughput through batching and partitioning, sacrificing per-message latency."

### 4.5 How Layer-Awareness Fits Into the Trait Architecture

The protocol/layer behaviour is best modeled as **edge traits** (complementing the **node traits** proposed in Section 7). Edges already carry the `protocol` field — we just need the engine to read it. See Section 5 for the full edge specification.

```
Edge Traits (NEW — applied to EdgeDefinition)
  │
  ├── ReliableDeliveryTrait (TCP, HTTPS, gRPC, WebSocket, AMQP)
  │     └── On packet loss: retransmit (add latency), do NOT drop the request
  │
  ├── UnreliableDeliveryTrait (UDP)
  │     └── On packet loss: drop the request (request-timeout or request-lost)
  │
  ├── ConnectionSetupTrait (TCP, HTTPS, gRPC, WebSocket)
  │     └── First request between two nodes incurs handshake latency
  │     └── Subsequent requests skip handshake (keep-alive)
  │     └── HTTPS: additional TLS handshake overhead
  │
  ├── MultiplexingTrait (gRPC, HTTP/2)
  │     └── Concurrent requests don't block each other
  │     └── No head-of-line blocking
  │
  └── BatchingTrait (Kafka)
        └── Groups multiple messages into batches
        └── Higher per-batch latency, higher throughput
```

#### Edge Trait Interface

```typescript
interface EdgeBehaviourTrait {
  /**
   * Called when a request is about to traverse this edge.
   * Can modify latency (connection setup overhead, TLS),
   * or drop the request (UDP packet loss).
   */
  onTraverse?(
    request: Request,
    edge: EdgeDefinition,
    clock: bigint,
    isFirstRequestOnConnection: boolean
  ):
    | { action: 'deliver'; additionalLatencyUs: bigint }  // normal delivery with optional extra latency
    | { action: 'drop'; reason: string }                   // UDP packet loss — request is gone
    | { action: 'retransmit'; retransmitLatencyUs: bigint } // TCP packet loss — retry adds latency
}
```

#### Engine Integration

The engine's `enqueueEdgeTransfer` method currently samples edge latency from the distribution and schedules a `request-arrival` at the target. The modification:

```
enqueueEdgeTransfer(request, edge, targetNodeId):
  edgeTrait = resolveEdgeTrait(edge.protocol)
  
  if edgeTrait:
    result = edgeTrait.onTraverse(request, edge, clock, isFirstConnection(edge))
    
    switch result.action:
      'deliver':  latency = sampleLatency(edge) + result.additionalLatencyUs
      'drop':     emit request-timeout event (UDP loss). RETURN.
      'retransmit': latency = sampleLatency(edge) + result.retransmitLatencyUs
  else:
    latency = sampleLatency(edge)  // current behaviour, unchanged
  
  schedule request-arrival at clock + latency
```

### 4.6 Node-Layer Enforcement Matrix

This matrix defines which protocols are valid on edges connected to each node type, and which L7 features each node can use. The engine or UI should enforce these constraints.

| Node | Valid Inbound Protocols | Valid Outbound Protocols | Can Use Content Routing? | Can Inspect HTTP? | OSI Layer |
|---|---|---|---|---|---|
| **L4 Load Balancer** | tcp, udp | tcp, udp | **No** — this is the key L4 constraint | **No** | L4 |
| **L7 Load Balancer** | https, grpc, websocket | https, grpc, websocket, tcp | **Yes** — path, host, header routing | **Yes** | L7 |
| **API Gateway** | https, grpc | https, grpc, tcp | **Yes** | **Yes** | L7 |
| **WAF** | https, grpc | https, grpc | N/A (filter, not route) | **Yes** — inspects request to block | L7 |
| **Firewall Rule** | tcp, udp | tcp, udp | **No** | **No** — drops by connection, not content | L3/L4 |
| **Security Group** | tcp, udp | tcp, udp | **No** | **No** | L3/L4 |
| **CDN** | https | https, tcp | **Limited** — by URL path for cache key | **Yes** — needs URL to determine cache key | L7 |
| **Ingress Controller** | https, grpc | https, grpc, tcp | **Yes** — path and host routing | **Yes** | L7 |
| **Reverse Proxy** | https, grpc | https, grpc, tcp | **Yes** | **Yes** | L7 |
| **NAT Gateway** | tcp, udp | tcp, udp | **No** | **No** — translates IP, doesn't inspect | L3 |
| **Edge Router** | tcp, udp | tcp, udp | **No** | **No** — routes by IP | L3 |
| **VPN Gateway** | tcp, udp (encrypted tunnel) | tcp, udp | **No** | **No** — encrypted, opaque | L3 |
| **Service Mesh (data plane)** | https, grpc | https, grpc | **Yes** — sidecar inspects at L7 | **Yes** | L7 |
| **API Server** | https, grpc | https, grpc, tcp, amqp, kafka | N/A (processes, doesn't route) | N/A | L7 (receives) |
| **Primary DB** | tcp | tcp | N/A | N/A | L4 (receives raw connections) |
| **Redis Cache** | tcp | tcp | N/A | N/A | L4 (custom protocol over TCP) |
| **Message Queue** | amqp, tcp | amqp, tcp | N/A | N/A | L7 (AMQP) or L4 (raw TCP) |
| **Kafka Broker** | kafka, tcp | kafka, tcp | N/A | N/A | L7 (Kafka protocol) |

**Teaching use of this matrix:**

An instructor can ask: "Why can't we put a WAF in front of the database?" Answer: the WAF operates at L7 (HTTP) but the database speaks a L4 protocol (TCP with a database-specific wire protocol). The WAF can't inspect database traffic because it's not HTTP.

Similarly: "Why do we need both a Firewall AND a WAF?" Answer: the firewall operates at L3/L4 (drops by IP/port/protocol), the WAF operates at L7 (blocks by HTTP content). They protect against different threat categories at different layers.

### 4.7 Teaching Scenarios Enabled by Layer-Awareness

#### Scenario 1: TCP vs UDP

**Concept:** Reliable vs unreliable transport.

**Setup:** Client → Server, two edges — one TCP, one UDP. Edge `packetLossRate: 0.05` on both.

**Observable difference:**
- TCP edge: 0% data loss, but ~5% of requests have higher latency (retransmission delay). Total throughput slightly lower.
- UDP edge: ~5% data loss (requests never arrive), but remaining 95% have consistently low latency. No retransmission overhead.

**Discussion:** When to use each? UDP for gaming/video (low latency matters more than occasional loss). TCP for banking/email (every byte must arrive).

#### Scenario 2: Why L4 LB Is Faster Than L7 LB

**Concept:** The cost of content inspection.

**Setup:** Client → [L4 LB, L7 LB] → [Server A, Server B]. Same backend servers, same workload.

**Observable difference:**
- L4 path: Lower per-request latency (no HTTP parsing). But L4 LB can only do round-robin/weighted — cannot route `/api` to Server A and `/static` to Server B.
- L7 path: Higher per-request latency (HTTP header parsing). But L7 LB can route by URL path, enabling content-aware distribution.

**Discussion:** L4 is faster but blind. L7 is smarter but slower. Use L4 for raw TCP/UDP services (databases, game servers). Use L7 for HTTP APIs where content-based routing matters.

#### Scenario 3: TLS Handshake Overhead

**Concept:** The cost of encryption.

**Setup:** Client → Server. Two edges — one with `protocol: tcp` (no TLS) and one with `protocol: https` (TLS).

**Observable difference:**
- TCP edge: Lower first-request latency (no handshake beyond TCP 3-way).
- HTTPS edge: Higher first-request latency (TCP handshake + TLS handshake). Subsequent requests similar (session resumption). Slightly higher per-request latency (encryption/decryption).

**Discussion:** TLS adds security but costs latency. Modern TLS 1.3 reduced the handshake to 1 round trip (from 2 in TLS 1.2). This is why CDNs terminate TLS at the edge — to avoid the handshake latency crossing the internet.

#### Scenario 4: Firewall (L3/L4) vs WAF (L7)

**Concept:** Layer-appropriate security.

**Setup:** Internet → Firewall → WAF → API Server.

**Observable difference:**
- Firewall drops packets by connection criteria (e.g., drop 2% of traffic from untrusted sources). Cannot distinguish between a legitimate API call and an SQL injection attack — they look the same at L4.
- WAF inspects HTTP content and blocks by request pattern (e.g., block requests with `request.type === 'attack'`). Can distinguish legitimate from malicious HTTP requests, but can't see non-HTTP traffic.

**Discussion:** Defense in depth — L3/L4 filtering (firewall) reduces volume, L7 filtering (WAF) catches application-level attacks. Neither alone is sufficient.

#### Scenario 5: Database Protocol Is Not HTTP

**Concept:** Why you can't put a WAF in front of a database.

**Setup:** Student tries to connect WAF → Primary DB with `protocol: https`.

**Expected behaviour:** The simulator should warn or error: "Databases communicate over TCP using database-specific wire protocols (PostgreSQL wire protocol, MySQL protocol), not HTTP. A WAF cannot inspect this traffic. Use a Firewall for L4 protection of database connections."

**Discussion:** This is a common misconception — that security = WAF. WAFs protect HTTP endpoints. Databases need network-level security (Security Groups, Firewalls, VPC isolation).

### 4.8 Implementation Approach for Layer-Awareness

#### Priority Tiers

| Priority | What to Implement | Teaching Impact |
|---|---|---|
| **P0** | Protocol-based enforcement on L4 LB: block conditional routing on L4 nodes. This is a UI/validation change, not an engine change. | Makes L4 vs L7 instantly teachable. |
| **P0** | Engine reads `edge.protocol` and applies packet loss differently: TCP retransmits (adds latency), UDP drops (request lost). | Makes TCP vs UDP teachable. |
| **P1** | Connection setup overhead: first request on TCP/HTTPS edges incurs handshake latency. | Teaches connection reuse, TLS cost. |
| **P1** | Protocol-valid-edge enforcement: warn when invalid protocol is used (e.g., `https` edge to a database). | Teaches layer-appropriate communication. |
| **P2** | gRPC multiplexing: concurrent requests on gRPC edges don't block each other. | Teaches HTTP/2 benefits. |
| **P2** | Kafka batching: messages on Kafka edges are batched for throughput. | Teaches Kafka's throughput model. |
| **P3** | Full connection state tracking: keep-alive, connection pooling, connection limits. | Advanced networking concepts. |

#### Minimal Engine Changes for P0

The most impactful change is small. In `engine.ts`, the `enqueueEdgeTransfer` method currently ignores the edge protocol:

```typescript
// Current: protocol is ignored
private enqueueEdgeTransfer(request: Request, edge: EdgeDefinition, targetNodeId: string): void {
  const latencyUs = this.sampleEdgeLatency(edge)
  this.eventQueue.insert(
    createEvent('request-arrival', targetNodeId, request.id, { request }, this.clock + latencyUs)
  )
}
```

The change:

```typescript
// Proposed: protocol affects delivery
private enqueueEdgeTransfer(request: Request, edge: EdgeDefinition, targetNodeId: string): void {
  const latencyUs = this.sampleEdgeLatency(edge)
  
  // UDP packet loss: request is dropped, not retransmitted
  if (edge.protocol === 'udp' && edge.packetLossRate > 0) {
    if (this.distributions.random() < edge.packetLossRate) {
      // Packet lost — no retransmission. Request times out eventually.
      return
    }
  }
  
  // TCP packet loss: retransmit (adds latency), request still arrives
  if ((edge.protocol === 'tcp' || edge.protocol === 'https') && edge.packetLossRate > 0) {
    if (this.distributions.random() < edge.packetLossRate) {
      // Retransmission: add one round-trip latency
      const retransmitLatencyUs = latencyUs // roughly doubles the delivery time
      this.eventQueue.insert(
        createEvent('request-arrival', targetNodeId, request.id, { request }, 
          this.clock + latencyUs + retransmitLatencyUs)
      )
      return
    }
  }
  
  this.eventQueue.insert(
    createEvent('request-arrival', targetNodeId, request.id, { request }, this.clock + latencyUs)
  )
}
```

This is ~15 lines of code that makes TCP vs UDP a real, observable, teachable difference.

---

## 5. Edge Specification: Properties, Constraints, and Node Compatibility

> **Key finding:** Edges in the simulator carry 12+ configurable properties, but the engine only reads 3 of them (`latency.distribution`, `packetLossRate`, `errorRate`), plus 3 routing properties (`mode`, `weight`, `condition`) via `RoutingTable`. The `protocol`, `bandwidth`, `maxConcurrentRequests`, and `pathType` fields are defined, validated by schema, configurable in the UI, serialized into topology JSON — and then completely ignored by the engine. Every edge behaves identically regardless of protocol, bandwidth, or connected node types.

### 5.1 Edge Properties Audit: What Exists vs. What Works

| Property | Type | Default | Engine Reads It? | Where | What It Does Today | What It Should Do |
|---|---|---|---|---|---|---|
| `id` | `string` | auto-generated | Yes | Serialization | Identifies the edge | No change needed |
| `source` | `string` | — | Yes | Routing | Source node of the edge | No change needed |
| `target` | `string` | — | Yes | Routing | Target node of the edge | No change needed |
| `label` | `string?` | `undefined` | No (UI only) | — | Display label on canvas | No change needed |
| `mode` | `'synchronous' \| 'asynchronous' \| 'streaming' \| 'conditional'` | `'synchronous'` (or `'asynchronous'` for asyncBoundary targets) | **Yes** | `routing.ts:97-98` | Async edges fan-out to all targets. Sync edges pick one (round-robin/weighted/random). Conditional edges require a matching `condition`. Streaming is treated as sync. | Streaming should have distinct behaviour (persistent connection, multiplexed messages). See 5.6. |
| `protocol` | `'https' \| 'grpc' \| 'tcp' \| 'udp' \| 'websocket' \| 'amqp' \| 'kafka'` | Auto-inferred: `amqp` for queues/brokers/pub-sub, `kafka` for streams, `https` for everything else | **No** | Never read by `engine.ts`, `routing.ts`, or `GGcKNode.ts` | Purely cosmetic. Set during serialization by `inferProtocol()`, shown in UI dropdown. | Protocol must affect edge behaviour. TCP retransmits on loss; UDP drops. HTTPS adds TLS handshake latency. gRPC multiplexes. See Section 4 and 5.6. |
| `latency.distribution` | `DistributionConfig` | `{ type: 'log-normal', mu: 2.3, sigma: 0.5 }` | **Yes** | `engine.ts:490` (`sampleEdgeLatencyUs`) | Sampled to determine transit time between nodes | Should additionally vary by `pathType`. See 5.2. |
| `latency.pathType` | `'same-rack' \| 'same-dc' \| 'cross-zone' \| 'cross-region' \| 'internet'` | `'same-dc'` | **No** | Never read | Purely cosmetic. Stored in topology JSON but engine ignores it. | Should set baseline latency defaults. See 5.2. |
| `bandwidth` | `number` (Mbps) | `1000` | **No** | Never read | Configurable in UI, serialized, ignored. | Should cap effective throughput on the edge. Requests exceeding bandwidth queue or are delayed. See 5.6. |
| `maxConcurrentRequests` | `number` | `100` | **No** | Never read | Configurable in UI, serialized, ignored. | Should act as a connection pool limit. Excess requests queue at the source node or are rejected (connection refused). See 5.6. |
| `packetLossRate` | `number` [0, 1] | `0` (UI shows as %) | **Yes** | `engine.ts:729` | If `random() < packetLossRate`, the request is dropped (times out at deadline). Same behaviour for ALL protocols. | TCP/HTTPS: retransmit (add latency, no data loss). UDP: drop (data lost). AMQP/Kafka: protocol-level ack prevents loss. See Section 4 and 5.6. |
| `errorRate` | `number` [0, 1] | `0.001` (0.1%, UI shows as %) | **Yes** | `engine.ts:743` | If `random() < errorRate`, the request gets a `request-rejected` event with reason `edge_error_rate`. Same for all protocols. | Should differentiate: HTTP → 500/502/503 error. TCP → connection reset. gRPC → status code. This affects retry behaviour when retries are implemented. |
| `weight` | `number?` | `undefined` | **Yes** | `routing.ts:124` | Used by `pickByWeight()` for weighted routing when defined. | No change needed for base behaviour. But see 5.4 — only valid when source is a routing node. |
| `condition` | `string?` | `undefined` | **Yes** | `routing.ts:142-171` | Evaluates `request.type === "X"` / `request.type !== "X"` expressions. Only used when `mode === 'conditional'` or when condition string is present. | Should be extended to support header-based conditions for L7 nodes. L4 nodes should NOT support conditions (enforce at validation time). |

#### Summary: 5 of 12 Properties Are Ignored

The engine reads: `latency.distribution`, `packetLossRate`, `errorRate`, `mode`, `weight`, `condition`.

The engine ignores: `protocol`, `pathType`, `bandwidth`, `maxConcurrentRequests`, `label`, `sourceHandle`/`targetHandle`/`animated` (React Flow metadata).

This means an instructor cannot demonstrate:
- TCP vs UDP behaviour differences (both drop on packet loss)
- Same-rack vs cross-region latency differences (same latency distribution used)
- Bandwidth saturation or connection limits
- Protocol-appropriate error responses

### 5.2 Edge Defaults by Path Type

The `pathType` field exists but the engine ignores it. When implemented, it should set **baseline latency defaults** that reflect real-world network characteristics. These defaults should be used when the user doesn't manually configure latency values, or as multipliers on the user's configured values.

| Path Type | Real-World RTT | Proposed Default Latency (mu, sigma) | Proposed Default Packet Loss | Teaching Concept |
|---|---|---|---|---|
| `same-rack` | 0.1–0.5ms | `{ mu: -1.2, sigma: 0.3 }` (~0.3ms median) | 0% | Nodes on same physical rack. Near-zero latency. |
| `same-dc` | 0.5–2ms | `{ mu: 0.0, sigma: 0.5 }` (~1ms median) | 0% | Within same data center but different racks. Current default. |
| `cross-zone` | 1–5ms | `{ mu: 1.1, sigma: 0.4 }` (~3ms median) | 0.001% | Across availability zones within same region. |
| `cross-region` | 30–100ms | `{ mu: 4.0, sigma: 0.3 }` (~55ms median) | 0.01% | Between AWS regions (e.g., us-east-1 → eu-west-1). |
| `internet` | 50–300ms | `{ mu: 4.6, sigma: 0.6 }` (~100ms median) | 0.1–1% | Over the public internet. High variance. |

**Teaching value:** An instructor can show why CDNs matter by comparing `internet` vs `same-dc` path types. A request going Client → CDN (internet, ~100ms) → Origin Server (same-dc, ~1ms) demonstrates that the CDN's proximity to the user is the key optimization — not the CDN's processing speed.

**Implementation:** `sampleEdgeLatencyUs()` in `engine.ts` should use `pathType` to select the latency distribution when no explicit distribution is configured by the user:

```typescript
private sampleEdgeLatencyUs(edge: EdgeDefinition): bigint {
  // If user explicitly configured latency, use that
  if (edge.latency.distribution) {
    return this.distributions.sampleMicroseconds(edge.latency.distribution)
  }
  // Otherwise, derive from pathType
  const pathDefaults = PATH_TYPE_LATENCY_DEFAULTS[edge.latency.pathType]
  return this.distributions.sampleMicroseconds(pathDefaults.distribution)
}
```

### 5.3 Protocol-to-Node Compatibility Matrix

Not every protocol makes sense on every edge. The simulator should enforce (or at minimum warn about) protocol constraints based on the **source and target node types**. This is critical for teaching — students should understand WHY certain protocols are used with certain components.

#### Valid Inbound Protocols (edges arriving at a node)

| Target Node Category | Valid Inbound Protocols | Invalid/Warning | Rationale |
|---|---|---|---|
| **L4 Load Balancer** | `tcp`, `udp` | `https`, `grpc` (warning: L4 doesn't terminate these) | L4 operates at transport layer — forwards raw TCP/UDP, doesn't parse application protocols |
| **L7 Load Balancer** | `https`, `grpc`, `websocket` | `tcp`, `udp` (warning: L7 needs application protocol) | L7 needs to parse HTTP headers for content routing |
| **API Gateway** | `https`, `grpc` | `tcp`, `udp`, `amqp`, `kafka` | API Gateways expose HTTP/gRPC APIs |
| **CDN** | `https` | `tcp`, `udp`, `grpc`, `amqp`, `kafka` | CDNs serve HTTP content (static assets, API responses) |
| **WAF** | `https`, `grpc` | `tcp`, `udp` | WAFs inspect HTTP request content |
| **Firewall Rule** | `tcp`, `udp` | (all valid — firewall can filter any L4 traffic) | Firewalls operate at L3/L4, protocol-agnostic |
| **API Endpoint / Microservice** | `https`, `grpc`, `websocket` | `amqp`, `kafka` (use via broker) | Services receive HTTP requests |
| **Relational DB / NoSQL DB** | `tcp` | `https`, `grpc`, `udp` | Databases use TCP with custom wire protocols (PostgreSQL, MySQL, MongoDB) |
| **In-Memory Cache (Redis)** | `tcp` | `https`, `grpc`, `udp` | Redis uses custom protocol over TCP (RESP) |
| **Queue / Message Broker** | `amqp`, `tcp` | `https`, `udp` | Message systems use AMQP or custom TCP protocols |
| **Kafka Broker / Stream** | `kafka`, `tcp` | `https`, `udp`, `amqp` | Kafka uses its own binary protocol over TCP |
| **Pub/Sub** | `amqp`, `tcp` | `https`, `udp` | Pub/Sub systems use AMQP or similar |
| **WebSocket Gateway** | `websocket`, `https` | `tcp`, `udp`, `amqp` | WebSocket upgrades from HTTP |
| **DNS Server** | `udp`, `tcp` | `https`, `grpc`, `amqp`, `kafka` | DNS uses UDP (queries) and TCP (zone transfers, large responses) |
| **Ingress Controller** | `https`, `grpc` | `tcp`, `udp` | Ingress operates at L7 (HTTP) |
| **Reverse Proxy** | `https`, `grpc`, `websocket` | `udp`, `amqp`, `kafka` | Reverse proxies operate at L7 |
| **Service Mesh (data plane)** | `https`, `grpc` | `tcp`, `udp` | Sidecar proxies operate at L7 |
| **Serverless Function** | `https`, `grpc` | `tcp`, `udp`, `amqp`, `kafka` | Functions are triggered by HTTP events |
| **Observability nodes** | `https`, `grpc`, `tcp` | (all valid — observability is protocol-flexible) | Accept telemetry via various protocols |

#### Valid Outbound Protocols (edges leaving a node)

| Source Node Category | Valid Outbound Protocols | Rationale |
|---|---|---|
| **L4 Load Balancer** | `tcp`, `udp` | L4 forwards raw transport — the outbound protocol matches inbound |
| **L7 Load Balancer** | `https`, `grpc`, `websocket`, `tcp` | L7 can terminate TLS and proxy to backends in same or different protocol |
| **API Gateway** | `https`, `grpc`, `tcp`, `amqp`, `kafka` | API Gateway may fan out to services, databases, queues |
| **Microservice** | `https`, `grpc`, `tcp`, `amqp`, `kafka`, `websocket` | Services communicate with various backends |
| **Primary DB** | `tcp` | Databases respond over their wire protocol connection |
| **Queue / Broker** | `amqp`, `tcp` | Consumers pull from brokers |

### 5.4 Mode-to-Node Compatibility Rules

The `mode` field determines how routing works (fan-out vs pick-one). Not every mode makes sense for every node pair.

| Mode | Meaning | Valid Source Nodes | Invalid Source Nodes | Current Behaviour | Needed Change |
|---|---|---|---|---|---|
| `synchronous` | Pick one target. Request-response. Caller waits. | Any node that calls another and waits for response | — | RoutingTable picks one sync edge via round-robin/weighted/random | None for base behaviour |
| `asynchronous` | Fan-out to ALL targets. Fire-and-forget. | Message brokers, pub/sub, event bus, Kafka | Load balancers (should not fan-out), databases (respond to caller) | All async edges are routed in parallel | Validate: warn if LB has async edges (likely a misconfiguration) |
| `streaming` | Persistent connection, bidirectional data flow | WebSocket Gateway, gRPC (bidirectional), Kafka consumer | Most request-response nodes | Treated identically to synchronous (bug) | Implement streaming semantics: connection stays open, multiple messages flow without re-routing |
| `conditional` | Pick target based on `condition` expression | L7 LB, API Gateway, Service Mesh (content routing) | L4 LB (cannot inspect content), databases, queues | Evaluates `request.type === "X"` | L4 nodes should be prevented from having conditional edges (enforced at validation, not engine) |

#### Auto-Inference Rules (Current)

Currently `useTopologySerializer.ts:195-197` auto-infers `mode`:
- If the target node has `asyncBoundary: true` → `mode: 'asynchronous'`
- Otherwise → `mode: 'synchronous'`

**Nodes with `asyncBoundary: true`** (from `paletteTemplates.ts`): `message-broker`, `pub-sub`, `event-bus`, `stream`, `queue`, `task-queue`.

**What should change:**
- Auto-inference should also consider the **source** node. An edge FROM a message broker TO a consumer should be async (consumer pulls asynchronously). Currently only target is checked.
- WebSocket edges should auto-infer `mode: 'streaming'`.
- Conditional mode should only be auto-suggested when the source is an L7 routing node (API Gateway, L7 LB, Ingress Controller, Reverse Proxy).

### 5.5 Edge Defaults by Source→Target Pair

The current `EDGE_DEFAULTS` object applies the same defaults to every edge regardless of what nodes it connects:

```typescript
const EDGE_DEFAULTS = {
  latencyMu: 2.3,
  latencySigma: 0.5,
  pathType: 'same-dc',
  bandwidth: 1000,
  maxConcurrentRequests: 100,
  packetLossRatePercent: 0,
  errorRatePercent: 0.1
}
```

This is unrealistic. An edge between two microservices within the same data center has very different characteristics than an edge from a CDN to an origin server, or from an API server to a database.

#### Proposed Context-Aware Defaults

| Source → Target | Protocol | Latency (mu) | Bandwidth | Max Concurrent | Packet Loss | Error Rate | Rationale |
|---|---|---|---|---|---|---|---|
| **Client → CDN** | https | 4.6 (internet) | 100 | 1000 | 0.1% | 0.1% | User is on public internet |
| **Client → L7 LB** | https | 4.6 (internet) | 100 | 1000 | 0.1% | 0.1% | User hitting the load balancer directly |
| **L7 LB → Microservice** | https | 0.0 (same-dc) | 10000 | 500 | 0% | 0.01% | Internal data center traffic |
| **L4 LB → Microservice** | tcp | -0.5 (same-dc) | 10000 | 1000 | 0% | 0.01% | L4 has lower overhead than L7 |
| **Microservice → Microservice** | https/grpc | 0.0 (same-dc) | 10000 | 200 | 0% | 0.05% | Service-to-service calls |
| **Microservice → Primary DB** | tcp | -0.5 (same-rack) | 10000 | 50 | 0% | 0.01% | DB connection pools are limited |
| **Microservice → Redis Cache** | tcp | -1.2 (same-rack) | 10000 | 100 | 0% | 0.001% | Redis is typically co-located, very fast |
| **Microservice → Queue/Broker** | amqp | 0.0 (same-dc) | 5000 | 100 | 0% | 0.01% | Message broker in same DC |
| **Microservice → Kafka** | kafka | 0.5 (same-dc) | 5000 | 50 | 0% | 0.01% | Kafka batches, slightly higher latency |
| **CDN → Origin** | https | 1.1 (cross-zone) | 10000 | 200 | 0% | 0.01% | CDN to origin is cross-zone, high bandwidth |
| **API GW → Microservice** | https | 0.0 (same-dc) | 10000 | 300 | 0% | 0.01% | Internal routing |
| **WAF → Backend** | https | -0.5 (same-rack) | 10000 | 500 | 0% | 0.001% | WAF is inline, same rack |
| **Primary DB → Read Replica** | tcp | 1.1 (cross-zone) | 1000 | 10 | 0% | 0.001% | Replication is cross-zone for HA |
| **Cross-region replication** | tcp | 4.0 (cross-region) | 1000 | 5 | 0.01% | 0.01% | Cross-region adds significant latency |

**Implementation:** The `inferProtocol()` function in `useTopologySerializer.ts` should be expanded into a `inferEdgeDefaults(source, target)` function that returns protocol, latency, bandwidth, and other defaults based on the source and target node types.

```typescript
function inferEdgeDefaults(
  sourceData: CanvasNodeDataV2 | undefined,
  targetData: CanvasNodeDataV2 | undefined
): Partial<EdgeDefinition> {
  const sourceType = sourceData?.componentType
  const targetType = targetData?.componentType
  
  // Source is a client/internet node → internet path
  if (sourceType === 'cdn' || isClientFacing(sourceType)) {
    return { protocol: 'https', latency: { pathType: 'internet', ... } }
  }
  
  // Target is a database → TCP, same-rack, limited connections
  if (isDatabase(targetType)) {
    return { protocol: 'tcp', latency: { pathType: 'same-rack', ... }, maxConcurrentRequests: 50 }
  }
  
  // Target is a message broker → AMQP, same-dc
  if (isMessaging(targetType)) {
    return { protocol: 'amqp', latency: { pathType: 'same-dc', ... } }
  }
  
  // ... more rules
}
```

### 5.6 Edge Behaviour Traits (Engine-Level)

Just as nodes need behavioural traits (Section 7), edges need behaviour that varies by protocol, mode, and connected node types. The `EdgeBehaviourTrait` interface proposed in Section 4.5 should be the mechanism for this.

#### Trait: TcpEdgeTrait

**Applies to:** Edges with `protocol: 'tcp'` or `protocol: 'https'`

**Behaviour:**
- **Reliable delivery:** On packet loss, retransmit rather than drop. The request still arrives, but with added latency (roughly doubles the transit time per retransmission).
- **Connection setup:** First request on a new connection incurs TCP 3-way handshake overhead (~1.5× the base latency). Subsequent requests on the same connection skip the handshake.
- **Connection tracking:** Track active connections per edge. If `maxConcurrentRequests` is defined and reached, new requests queue at the source or receive a "connection refused" rejection.

```typescript
class TcpEdgeTrait implements EdgeBehaviourTrait {
  private connectionEstablished = new Map<string, boolean>() // edgeId → has active connection
  private activeConnections = new Map<string, number>()       // edgeId → count

  onTraverse(request, edge, clock, isFirstRequest) {
    // Connection limit enforcement
    const active = this.activeConnections.get(edge.id) ?? 0
    if (edge.maxConcurrentRequests && active >= edge.maxConcurrentRequests) {
      return { action: 'drop', reason: 'connection_refused' }
    }
    
    // TCP 3-way handshake on first request
    let additionalLatencyUs = 0n
    if (!this.connectionEstablished.get(edge.id)) {
      additionalLatencyUs = baseLatencyUs * 3n / 2n  // 1.5 RTT for handshake
      this.connectionEstablished.set(edge.id, true)
    }
    
    // Packet loss → retransmit (adds latency, no data loss)
    if (edge.packetLossRate > 0 && random() < edge.packetLossRate) {
      const retransmitLatency = baseLatencyUs  // one additional RTT
      return { action: 'retransmit', retransmitLatencyUs: additionalLatencyUs + retransmitLatency }
    }
    
    return { action: 'deliver', additionalLatencyUs }
  }
}
```

**Teaching value:** Students see that TCP guarantees delivery but at a latency cost. Packet loss on a TCP connection doesn't cause data loss — it causes slowdowns.

#### Trait: UdpEdgeTrait

**Applies to:** Edges with `protocol: 'udp'`

**Behaviour:**
- **Unreliable delivery:** On packet loss, the request is dropped permanently. No retransmission.
- **No connection setup:** No handshake overhead. First request is as fast as subsequent requests.
- **No connection tracking:** UDP is connectionless. `maxConcurrentRequests` is not applicable.

```typescript
class UdpEdgeTrait implements EdgeBehaviourTrait {
  onTraverse(request, edge, clock, isFirstRequest) {
    // UDP packet loss: gone forever
    if (edge.packetLossRate > 0 && random() < edge.packetLossRate) {
      return { action: 'drop', reason: 'udp_packet_loss' }
    }
    // No handshake overhead
    return { action: 'deliver', additionalLatencyUs: 0n }
  }
}
```

**Teaching value:** Students see that UDP is faster (no handshake) but unreliable. Gaming, video streaming, and DNS queries use UDP because occasional packet loss is acceptable in exchange for lower latency.

#### Trait: HttpsEdgeTrait (extends TcpEdgeTrait)

**Applies to:** Edges with `protocol: 'https'`

**Behaviour (in addition to TCP):**
- **TLS handshake:** First request on a new connection adds TLS handshake overhead on top of the TCP handshake (~2× the base latency for TLS 1.2, ~1× for TLS 1.3).
- **Encryption overhead:** Small per-request latency increase for encryption/decryption (~0.1ms).
- **Session resumption:** After the first TLS handshake, subsequent connections within a time window skip the full handshake (abbreviated handshake, ~0.5× overhead).

**Teaching value:** Students see why CDNs terminate TLS at the edge — to avoid TLS handshake latency crossing the full internet RTT. Also shows why HTTP/2 and connection reuse matter.

#### Trait: GrpcEdgeTrait (extends HttpsEdgeTrait)

**Applies to:** Edges with `protocol: 'grpc'`

**Behaviour (in addition to HTTPS):**
- **HTTP/2 multiplexing:** Multiple concurrent requests on the same connection don't block each other (head-of-line blocking eliminated at HTTP level).
- **Binary framing:** Slightly lower per-request overhead than HTTPS/JSON (~10% faster serialization).
- **Streaming support:** When edge `mode: 'streaming'`, maintains a persistent connection that allows multiple messages without connection re-establishment.

**Teaching value:** Students see why gRPC is preferred for inter-service communication — multiplexing and binary framing reduce latency under high concurrency.

#### Trait: AmqpEdgeTrait

**Applies to:** Edges with `protocol: 'amqp'`

**Behaviour:**
- **Acknowledgement-based delivery:** Messages are not lost on packet loss — the broker re-delivers unacknowledged messages.
- **Connection overhead:** AMQP connections involve a multi-step handshake (protocol header → connection tune → open channel), higher overhead than TCP alone.
- **Persistent connections:** AMQP uses long-lived connections with channels multiplexed over them.

**Teaching value:** Students understand why message brokers provide reliable delivery guarantees — the protocol itself handles acknowledgement and re-delivery, unlike raw TCP where the application must handle retries.

#### Trait: KafkaEdgeTrait

**Applies to:** Edges with `protocol: 'kafka'`

**Behaviour:**
- **Batched delivery:** Messages are accumulated and sent in batches. Higher throughput, but individual message latency is higher (batch wait time).
- **Producer acknowledgement levels:** `acks=0` (fire-and-forget, fastest, can lose data), `acks=1` (leader acknowledged), `acks=all` (all replicas acknowledged, slowest, strongest guarantee).
- **Consumer lag:** If the consumer processes slower than the producer publishes, lag accumulates (tracked as a metric).

**Teaching value:** Students see the throughput-latency tradeoff of batching, and understand Kafka's acknowledgement modes (at-most-once vs at-least-once vs exactly-once semantics).

#### Trait: WebSocketEdgeTrait

**Applies to:** Edges with `protocol: 'websocket'`

**Behaviour:**
- **Upgrade handshake:** First request incurs HTTP upgrade handshake overhead (~1.5× base latency).
- **Persistent bidirectional connection:** After upgrade, messages flow in both directions without new connection setup.
- **No request-response pairing:** Unlike HTTP, WebSocket messages are independent — they don't pair as request-response.
- **Keep-alive:** Connection stays open until explicitly closed.

**Teaching value:** Students understand why WebSocket is used for real-time applications (chat, live updates, gaming) — the upgrade handshake costs more upfront, but subsequent messages are faster because there's no per-message HTTP overhead.

#### Trait: BandwidthLimitTrait

**Applies to:** All edges (when `bandwidth` is configured and engine reads it)

**Behaviour:**
- Track bytes-in-flight on each edge per time window.
- When bytes-in-flight exceeds `bandwidth × window`, additional requests are delayed (queued at edge level).
- `request.sizeBytes` (from workload profile) determines how much bandwidth each request consumes.

```typescript
class BandwidthLimitTrait implements EdgeBehaviourTrait {
  private bytesInWindow = new Map<string, number>()  // edgeId → bytes used in current window
  
  onTraverse(request, edge, clock, isFirstRequest) {
    const currentBytes = this.bytesInWindow.get(edge.id) ?? 0
    const requestBytes = request.sizeBytes ?? 1024
    const bandwidthBytesPerMs = (edge.bandwidth * 1000000) / 8 / 1000  // Mbps → bytes/ms
    
    if (currentBytes + requestBytes > bandwidthBytesPerMs * windowMs) {
      // Bandwidth saturated — delay this request
      const delayMs = (requestBytes / bandwidthBytesPerMs)
      return { action: 'deliver', additionalLatencyUs: BigInt(delayMs * 1000) }
    }
    
    this.bytesInWindow.set(edge.id, currentBytes + requestBytes)
    return { action: 'deliver', additionalLatencyUs: 0n }
  }
}
```

**Teaching value:** Students see bandwidth saturation in action — a 100 Mbps internet link serving high-traffic requests will bottleneck at the edge, not at the node. Shows why CDNs and edge caching reduce bandwidth pressure on origin servers.

### 5.7 EdgePropertiesPanel Adaptation

The current `EdgePropertiesPanel` (`EdgePropertiesPanel.tsx`) shows all 7 protocols and all 5 path types for every edge, regardless of what nodes the edge connects. This should change based on source and target node types.

#### Current Problem

A student can configure:
- An `https` edge from an API Server to a PostgreSQL Database (databases don't speak HTTP)
- A `kafka` edge from a Load Balancer to a Microservice (LBs don't produce Kafka messages)
- A `udp` edge to a Redis Cache (Redis uses TCP exclusively)

None of these are flagged as warnings or errors. The protocol field is cosmetic, so it doesn't matter — but for teaching, it should matter.

#### Proposed Panel Behaviour

**1. Protocol dropdown should be filtered by connected nodes:**

When a user clicks an edge between an API Server and a PostgreSQL Database, the protocol dropdown should show:
- `tcp` (default, recommended)
- Other options greyed out with tooltip: "Databases communicate via TCP wire protocol, not HTTP"

When a user clicks an edge between an L7 LB and a Microservice, the protocol dropdown should show:
- `https` (default, recommended)
- `grpc` (valid alternative)
- `websocket` (valid for WebSocket traffic)
- `tcp` greyed out with tooltip: "L7 LB operates at application layer — use https or grpc"

**2. Mode dropdown should be filtered by source node:**

- If source is an L4 LB → `conditional` mode disabled (tooltip: "L4 operates at transport layer — cannot route by content")
- If source is a message broker → `asynchronous` default and `synchronous` warned (tooltip: "Message brokers typically use fire-and-forget delivery")

**3. Bandwidth and maxConcurrentRequests should show contextual defaults:**

- DB edges → maxConcurrentRequests defaults to 50 (connection pool size)
- Internet edges → bandwidth defaults to 100 Mbps
- Same-rack edges → bandwidth defaults to 10000 Mbps

**4. New: Connection indicator:**

When `protocol` is `tcp` or `https`, show an info badge: "Reliable (retransmits on loss)".
When `protocol` is `udp`, show: "Unreliable (packets may be dropped)".

**Implementation approach:**

```typescript
function getEdgeConstraints(
  sourceType: ComponentType | undefined,
  targetType: ComponentType | undefined
): EdgeConstraints {
  return {
    validProtocols: computeValidProtocols(sourceType, targetType),
    defaultProtocol: computeDefaultProtocol(sourceType, targetType),
    validModes: computeValidModes(sourceType, targetType),
    defaultMode: computeDefaultMode(sourceType, targetType),
    suggestedDefaults: computeSuggestedDefaults(sourceType, targetType)
  }
}
```

The `EdgePropertiesPanel` should receive `sourceType` and `targetType` as props (currently it doesn't) and use `getEdgeConstraints()` to filter and default the dropdowns.

### 5.8 Edge Validation Rules

The serializer (`useTopologySerializer.ts`) currently does no edge-level validation beyond checking that source and target nodes exist. For teaching, the following validation rules should be added.

#### Hard Errors (block simulation)

| Rule | Reason | Example |
|---|---|---|
| Edge source and target must be different nodes | Self-loops don't make physical sense | Node A → Node A |
| Edge must not create a cycle of purely synchronous edges with no exit | Infinite routing loop would hang the simulation | A → B → C → A, all synchronous |
| `conditional` mode edges must have a non-empty `condition` | Engine treats conditionless conditional edges as ineligible | `mode: 'conditional', condition: ''` |

#### Warnings (allow simulation but flag to user)

| Rule | Severity | Teaching Purpose | Example |
|---|---|---|---|
| Invalid protocol for target node type | Warning | Teaches protocol-layer alignment | `https` edge to a database |
| Invalid protocol for source node type | Warning | Teaches outbound protocol constraints | `amqp` edge from a Load Balancer |
| L4 node with `conditional` mode edge | Warning | Teaches L4 vs L7 distinction | L4 LB with conditional routing |
| `asynchronous` mode on an edge from a Load Balancer | Warning | LBs pick one target, not fan-out | LB → [A, B] with async edges |
| `bandwidth` < 10 on same-rack edge | Warning | Unrealistically low for LAN | 1 Mbps same-rack edge |
| `maxConcurrentRequests` > 10000 | Warning | Unrealistically high connection pool | 50000 concurrent connections |
| `packetLossRate` > 0.1 (10%) | Warning | Unrealistically high for non-internet | 20% packet loss same-dc |
| `udp` protocol with `errorRate > 0` and target is not DNS | Info | UDP errors manifest as packet loss, not error responses | UDP edge with 5% error rate |

#### Implementation

Validation should happen in two places:
1. **Serialization time** (in `useTopologySerializer.ts`) — validate edges during `serialize()` and return warnings alongside the topology.
2. **Real-time on canvas** — when user connects two nodes, immediately check edge constraints and show a toast or edge annotation for warnings.

```typescript
interface EdgeValidationResult {
  errors: string[]    // block simulation
  warnings: string[]  // show to user, allow simulation
  infos: string[]     // educational hints
}

function validateEdge(
  edge: EdgeDefinition,
  sourceNode: ComponentNode,
  targetNode: ComponentNode
): EdgeValidationResult {
  const results: EdgeValidationResult = { errors: [], warnings: [], infos: [] }
  
  const constraints = getEdgeConstraints(sourceNode.type, targetNode.type)
  
  if (!constraints.validProtocols.includes(edge.protocol)) {
    results.warnings.push(
      `Protocol "${edge.protocol}" is unusual for ${sourceNode.type} → ${targetNode.type}. ` +
      `Expected: ${constraints.validProtocols.join(', ')}. ` +
      `Reason: ${constraints.protocolReason}`
    )
  }
  
  if (edge.mode === 'conditional' && isL4Node(sourceNode.type)) {
    results.warnings.push(
      `L4 node "${sourceNode.label}" cannot do content-based routing. ` +
      `L4 operates at the transport layer and doesn't inspect request content. ` +
      `Use an L7 Load Balancer or API Gateway for conditional routing.`
    )
  }
  
  return results
}
```

### 5.9 Implementation Priority for Edges

| Priority | Task | Files Changed | Teaching Impact |
|---|---|---|---|
| **P0** | **Engine reads `protocol`**: TCP retransmits on packet loss, UDP drops. ~15 lines in `engine.ts:enqueueEdgeTransfer`. | `engine.ts` | Makes TCP vs UDP instantly teachable. The single most impactful edge change. |
| **P0** | **Engine reads `pathType`**: Use path-type-specific latency defaults when user hasn't configured explicit latency. | `engine.ts` | Makes same-rack vs internet latency visible. Teaches CDN value proposition. |
| **P1** | **Protocol dropdown filtering**: Filter EdgePropertiesPanel protocol options based on source/target node types. | `EdgePropertiesPanel.tsx`, new `edgeConstraints.ts` | Prevents nonsensical configurations. Teaches protocol-layer alignment. |
| **P1** | **Edge validation warnings**: Warn on invalid protocol/mode combinations during serialization. | `useTopologySerializer.ts` | Provides educational feedback on edge configuration errors. |
| **P1** | **Context-aware edge defaults**: `inferEdgeDefaults(source, target)` replaces global `EDGE_DEFAULTS`. | `useTopologySerializer.ts` | Realistic defaults make drag-and-drop topologies more accurate. |
| **P2** | **Engine reads `maxConcurrentRequests`**: Enforce connection limits on edges. Excess requests get `connection_refused`. | `engine.ts` | Teaches connection pooling and database connection limits. |
| **P2** | **Engine reads `bandwidth`**: Delay requests when bandwidth is saturated. | `engine.ts` | Teaches bandwidth constraints and link saturation. |
| **P2** | **TLS handshake overhead**: First request on HTTPS edge incurs handshake latency. | `engine.ts` or `HttpsEdgeTrait` | Teaches TLS cost and connection reuse. |
| **P3** | **gRPC multiplexing**: Multiple concurrent requests on gRPC don't block each other. | `GrpcEdgeTrait` | Teaches HTTP/2 head-of-line blocking elimination. |
| **P3** | **Kafka batching**: Messages on Kafka edges are batched for throughput. | `KafkaEdgeTrait` | Teaches Kafka's throughput model. |
| **P3** | **WebSocket persistent connections**: Upgrade handshake then persistent bidirectional flow. | `WebSocketEdgeTrait` | Teaches real-time communication patterns. |
| **P3** | **AMQP acknowledgement**: Protocol-level message reliability. | `AmqpEdgeTrait` | Teaches message delivery guarantees. |

#### Relationship to Node Traits (Section 8)

Edge traits and node traits are complementary:
- **Node traits** modify behaviour at the node level (cache hit, health-aware routing, rate limiting).
- **Edge traits** modify behaviour at the link level (protocol semantics, connection setup, bandwidth limits).
- Both use the same hook architecture (Section 6) and can be implemented independently.
- **P0 edge work** (protocol awareness, pathType latency) should be done alongside or immediately after **Phase 0** of the node trait work (trait interface and engine hooks), since the engine changes are in the same area of code (`enqueueEdgeTransfer` in `engine.ts`).

---

## 6. Proposed Architecture Redesign (Node Traits + Edge Traits)

### 6.1 Current Architecture

```
Engine (SimulationEngine)
  │
  ├── for each node in topology:
  │     └── new GGcKNode(config)    ← every node, regardless of type
  │
  ├── RoutingTable
  │     └── resolveTarget()         ← same logic for all node types
  │         └── isRoundRobinSource() ← string match on node ID
  │
  └── Event Loop
        └── handleEvent()           ← switch on event type, NOT node type
            ├── handleRequestArrival()   → node.handleArrival()
            ├── handleProcessingComplete() → node.handleCompletion()
            └── ... (same for all nodes)
```

**Problem:** Node type information is discarded after the palette template instantiates default config values. The engine sees every node as a `GGcKNode` and has no concept of caching, load balancing strategies, message persistence, or any other type-specific behaviour.

### 6.2 Proposed Architecture: Behavioural Traits

Instead of creating different node classes (which would be complex and fragile), add a **trait system** that attaches behavioural hooks to the existing GGcKNode pipeline.

```
Engine (SimulationEngine)
  │
  ├── for each node in topology:
  │     ├── new GGcKNode(config)            ← base queue (unchanged)
  │     └── traits = resolveTraits(node)    ← NEW: behavioural overlays
  │           ├── CacheTrait          (CDN, Redis, Reverse Proxy)
  │           ├── HealthAwareRoutingTrait   (L4 LB, L7 LB, Ingress)
  │           ├── ContentRoutingTrait (L7 LB, API Gateway, Ingress)
  │           ├── BroadcastTrait      (Kafka, Pub/Sub)
  │           ├── RateLimiterTrait    (API Gateway, External Service)
  │           ├── ReadWriteSplitTrait (Primary DB, Read Replica)
  │           ├── ColdStartTrait      (Serverless Function)
  │           ├── AckAndReleaseTrait  (Message Queue)
  │           └── ...
  │
  ├── RoutingTable (enhanced)
  │     └── resolveTarget()
  │         └── filters by target health (HealthAwareRoutingTrait)
  │         └── enforces routing constraints (ContentRoutingTrait on L7, blocked on L4)
  │
  └── Event Loop (enhanced)
        └── handleRequestArrival()
        │     ├── trait.beforeArrival()     ← rate limiting, security filtering
        │     ├── node.handleArrival()      ← base queue logic (unchanged)
        │     └── trait.afterArrival()      ← (future hooks)
        │
        └── handleProcessingComplete()
              ├── trait.beforeRouting()     ← cache hit check (skip routing on hit)
              ├── routing.resolveTarget()   ← with health filtering
              └── trait.afterRouting()      ← ack-and-release for queues
```

### 6.3 Trait Interface

```typescript
interface NodeBehaviourTrait {
  /**
   * Called before the request enters the GGcKNode queue.
   * Can reject (rate limited, security blocked) or short-circuit (cache hit).
   * Return 'continue' to proceed to queue, 'handled' to skip queue entirely,
   * or 'rejected' with a reason.
   */
  beforeArrival?(request: Request, clock: bigint): 
    | { action: 'continue' }
    | { action: 'handled'; latencyUs: bigint }   // cache hit → complete immediately
    | { action: 'rejected'; reason: string }      // rate limited, blocked

  /**
   * Called after processing completes, before routing to next node.
   * Can modify routing decisions or short-circuit.
   * Return 'route' to proceed normally, 'complete' to end the request here,
   * or 'reroute' to override the target.
   */
  beforeRouting?(request: Request, clock: bigint):
    | { action: 'route' }
    | { action: 'complete' }    // e.g., cache hit served, no forwarding needed
    | { action: 'reroute'; targetNodeId: string }

  /**
   * Called when routing resolves targets, to filter unhealthy nodes
   * or enforce routing constraints.
   */
  filterRoutes?(candidates: ResolveRoute[], request: Request): ResolveRoute[]
}
```

### 6.4 Why Traits, Not Subclasses

| Approach | Pros | Cons |
|---|---|---|
| **Subclass per node type** (CacheNode, LoadBalancerNode, etc.) | Clear class hierarchy | 50+ classes. Complex inheritance. Hard to compose (a reverse proxy is both a cache AND an LB). |
| **Behavioural traits** (composition) | Composable. Small, focused. Easy to test in isolation. A node can have multiple traits. | Slightly more indirection. Need a clear execution order for multiple traits. |
| **Strategy pattern per node** | Familiar pattern | Same complexity as subclasses, just using composition syntax. |

**Traits win because they're composable.** A Reverse Proxy needs both `CacheTrait` and `HealthAwareRoutingTrait`. An API Gateway needs `RateLimiterTrait`, `ContentRoutingTrait`, and `HealthAwareRoutingTrait`. Traits let us snap these together without creating a combinatorial explosion of subclasses.

### 6.5 Mapping Palette Nodes to Traits

| Palette Node | Traits | Priority |
|---|---|---|
| **Load Balancer L4** | `HealthAwareRoutingTrait` | P0 |
| **Load Balancer L7** | `HealthAwareRoutingTrait`, `ContentRoutingTrait` | P0 |
| **Load Balancer (Legacy)** | `HealthAwareRoutingTrait` | P0 |
| **CDN** | `CacheTrait`, `HealthAwareRoutingTrait` | P0 |
| **Redis Cache** | `CacheTrait` | P0 |
| **API Gateway** | `HealthAwareRoutingTrait`, `ContentRoutingTrait`, `RateLimiterTrait` | P1 |
| **Ingress Controller** | `HealthAwareRoutingTrait`, `ContentRoutingTrait` | P1 |
| **Reverse Proxy** | `HealthAwareRoutingTrait`, `CacheTrait` (optional) | P1 |
| **Primary DB** | `ReadWriteSplitTrait` | P1 |
| **Read Replica** | `ReadOnlyTrait` | P1 |
| **Serverless Fn** | `ColdStartTrait`, `ConcurrencyCapTrait` | P2 |
| **Message Queue** | `AckAndReleaseTrait`, `DeadLetterTrait` | P2 |
| **Kafka / Pub/Sub** | `BroadcastTrait` (already exists as routing), `ConsumerLagTrait` | P2 |
| **WAF** | `SecurityFilterTrait` (already exists via securityPolicy) | Exists |
| **Firewall / SG** | `SecurityFilterTrait` (already exists via securityPolicy) | Exists |
| **Health Check Mgr** | `HealthProberTrait` (generates probes, updates health registry) | P0 |
| **Sharding / Hashing** | `KeyBasedRoutingTrait` | P2 |
| **DNS** | `CacheTrait`, `DnsRoutingPolicyTrait` | P2 |
| **External Service** | `RateLimiterTrait`, `HighVarianceLatencyTrait` | P2 |
| **Observability nodes** | `AsyncOnlyTrait` (enforces async edges) | P1 |
| All other nodes | No traits (base GGcKNode behaviour) | — |

---

## 7. Behavioural Trait System (Node Traits)

### 7.1 Trait: CacheTrait

**Applies to:** CDN, Redis Cache, Reverse Proxy (optional), DNS

**Config:**
```typescript
interface CacheTraitConfig {
  cacheHitRate: number        // 0.0–1.0, probability of cache hit
  cacheHitLatencyMs: number   // latency when served from cache (default: 1ms for CDN, 0.1ms for Redis)
  ttlSeconds?: number         // optional: hit rate degrades over time
}
```

**Behaviour in the engine:**
- `beforeArrival`: Roll `rng.next() < cacheHitRate`.
  - If HIT: return `{ action: 'handled', latencyUs: cacheHitLatencyMs * 1000 }`. Engine schedules a `request-complete` event after the hit latency. Request is NOT forwarded downstream. Metrics record this as a completed request with the hit latency.
  - If MISS: return `{ action: 'continue' }`. Request enters GGcKNode queue normally and is forwarded downstream after processing.
- **Metric impact:** CDN with 90% hit rate means downstream origin sees only 10% of traffic. This is the single most important teachable behaviour for caching nodes.

### 7.2 Trait: HealthAwareRoutingTrait

**Applies to:** All load balancers, API Gateway, Ingress Controller, Reverse Proxy

**Config:**
```typescript
interface HealthAwareRoutingConfig {
  healthCheckEnabled: boolean  // default: true
}
```

**Behaviour in the engine:**
- `filterRoutes`: Remove candidates whose target node has `status === 'failed'` or is marked unhealthy in the health registry.
- If all candidates are unhealthy, reject the request with `no_healthy_targets`.
- This is the fix for the "LB sends traffic to dead servers" bug.

### 7.3 Trait: ContentRoutingTrait

**Applies to:** L7 LB, API Gateway, Ingress Controller

**NOT applied to:** L4 LB (this IS the teaching point)

**Config:**
```typescript
interface ContentRoutingConfig {
  routingRules: Array<{
    matchField: 'type' | 'path' | 'host'
    matchValue: string
    targetNodeId: string
  }>
}
```

**Behaviour in the engine:**
- `filterRoutes`: Evaluate routing rules against request attributes. If a rule matches, route to the specified target. If no rule matches, fall through to default routing (round-robin/weighted).
- **L4 enforcement:** If a user places conditional edges on an L4 LB, the engine (or UI validation) should warn: "L4 load balancers operate at the transport layer and cannot route by request content."

### 7.4 Trait: RateLimiterTrait

**Applies to:** API Gateway, External Service

**Config:**
```typescript
interface RateLimiterConfig {
  maxTokens: number          // bucket capacity
  refillRatePerSecond: number // tokens added per second
}
```

**Behaviour in the engine:**
- `beforeArrival`: Check token bucket. If tokens available, consume one and return `continue`. If exhausted, return `{ action: 'rejected', reason: 'rate_limited' }`.
- Token bucket refills at `refillRatePerSecond` rate, checked against simulation clock.

### 7.5 Trait: ReadWriteSplitTrait

**Applies to:** Primary DB

**Config:**
```typescript
interface ReadWriteSplitConfig {
  readLatency: DistributionConfig    // e.g., exponential(lambda=0.25) → mean 4ms
  writeLatency: DistributionConfig   // e.g., exponential(lambda=0.1) → mean 10ms
}
```

**Behaviour in the engine:**
- Override the service time distribution based on `request.type`. If `request.type === 'read'`, sample from `readLatency`. If `request.type === 'write'`, sample from `writeLatency`. Otherwise, use the default distribution.

### 7.6 Trait: ReadOnlyTrait

**Applies to:** Read Replica

**Behaviour in the engine:**
- `beforeArrival`: If `request.type === 'write'`, return `{ action: 'rejected', reason: 'read_only_node' }`. Read replicas cannot serve writes.

### 7.7 Trait: ColdStartTrait

**Applies to:** Serverless Function

**Config:**
```typescript
interface ColdStartConfig {
  coldStartLatency: DistributionConfig  // e.g., exponential(lambda=0.005) → mean 200ms
  idleTimeoutMs: number                  // time after last request before function cools down
}
```

**Behaviour in the engine:**
- Track `lastRequestTime`. If `clock - lastRequestTime > idleTimeoutMs`, the next request incurs `coldStartLatency` added to normal service time.
- After cold start, subsequent requests within `idleTimeoutMs` are warm (no extra latency).

### 7.8 Trait: AckAndReleaseTrait

**Applies to:** Message Queue

**Behaviour in the engine:**
- When a message arrives at the queue node, immediately emit a `request-complete` event back to the producer (acknowledging receipt). The producer's request is done.
- Separately, the message enters the queue and waits for consumer processing. This is an independent lifecycle.
- **Teaching effect:** The producer's latency includes only the time to enqueue, NOT the time for the consumer to process. This is the fundamental decoupling concept.

### 7.9 Trait: HealthProberTrait

**Applies to:** Health Check Manager

**Config:**
```typescript
interface HealthProberConfig {
  checkIntervalMs: number
  unhealthyThreshold: number   // consecutive failures before marking unhealthy
  healthyThreshold: number     // consecutive successes before marking healthy
  monitoredNodes: string[]     // node IDs to probe
}
```

**Behaviour in the engine:**
- On a timer (`checkIntervalMs`), sends synthetic probe events to each monitored node.
- If probe arrives at a node with `status === 'failed'`, counts as a failed probe.
- After `unhealthyThreshold` consecutive failures, marks the node as unhealthy in a shared health registry.
- Load balancers with `HealthAwareRoutingTrait` consult this registry.

---

## 8. Implementation Priority

### Phase 0: The Foundation (Blocks Everything Else)

| # | Task | Description |
|---|---|---|
| 0.1 | **Create the trait interface** | Define `NodeBehaviourTrait` in `src/engine/traits/types.ts`. |
| 0.2 | **Create the trait resolver** | `resolveTraits(node: ComponentNode): NodeBehaviourTrait[]` — maps component type to trait list. |
| 0.3 | **Add trait hooks to the engine event loop** | Modify `handleRequestArrival` and `handleProcessingComplete` to call `beforeArrival` and `beforeRouting` on the node's traits. |
| 0.4 | **Add trait-based route filtering to RoutingTable** | Modify `resolveTarget` to call `filterRoutes` on the source node's traits. |

This is a medium-effort refactor that touches `engine.ts` and `routing.ts` but does NOT change the GGcKNode class at all. The base queue model stays untouched.

### Phase 1: Critical Teaching Behaviours

| # | Trait | Nodes | Teaching Impact |
|---|---|---|---|
| 1.1 | `HealthAwareRoutingTrait` | All LBs, Ingress | Fixes the #1 blocker: LB routing to dead servers |
| 1.2 | `CacheTrait` | CDN, Redis Cache | Makes caching teachable — the #1 missing teaching feature |
| 1.3 | `ContentRoutingTrait` + L4 enforcement | L7 LB, API Gateway | Makes L4 vs L7 distinction real and observable |
| 1.4 | `HealthProberTrait` | Health Check Manager | Enables health-aware routing to work with the health check concept |

### Phase 2: Important Teaching Behaviours

| # | Trait | Nodes | Teaching Impact |
|---|---|---|---|
| 2.1 | `RateLimiterTrait` | API Gateway, External Service | Teaches rate limiting and API throttling |
| 2.2 | `ReadWriteSplitTrait` | Primary DB | Teaches read/write workload patterns |
| 2.3 | `ReadOnlyTrait` | Read Replica | Teaches read replica constraints |
| 2.4 | `AckAndReleaseTrait` | Message Queue | Teaches async decoupling |
| 2.5 | `AsyncOnlyTrait` | Observability nodes | Enforces that observability is non-blocking |

### Phase 3: Advanced Teaching Behaviours

| # | Trait | Nodes | Teaching Impact |
|---|---|---|---|
| 3.1 | `ColdStartTrait` | Serverless Function | Teaches serverless cold start |
| 3.2 | `KeyBasedRoutingTrait` | Sharding, Hashing | Teaches consistent hashing and shard routing |
| 3.3 | `ConsumerLagTrait` | Kafka | Teaches consumer lag monitoring |
| 3.4 | `DnsRoutingPolicyTrait` | DNS | Teaches Route 53 policies |
| 3.5 | `CircuitBreakerTrait` | Service Mesh, Sidecar | Teaches circuit breaker pattern |

### Summary: What Changes, What Stays

| Component | Changes? | Detail |
|---|---|---|
| `GGcKNode` | **No** | Base queue model stays exactly as-is |
| `SimulationEngine` event loop | **Yes (small)** | Add trait hook calls before/after arrival and routing |
| `RoutingTable` | **Yes (small)** | Add health filtering and content routing |
| `componentSpecs.ts` | **Yes (small)** | Map component types to trait lists |
| New: `src/engine/traits/` | **Yes (new)** | Directory with one file per trait |
| Palette templates | **Yes (small)** | Add trait-specific config knobs to seed values |
| UI Properties panel | **Yes (medium)** | Expose trait-specific config knobs |
| Engine tests | **Yes (medium)** | Test each trait in isolation and in integration |

The total blast radius is moderate. The engine's core event loop gets 4–6 additional hook calls. The GGcKNode class is untouched. Each trait is a small, independently testable module. No existing behaviour is broken — traits only ADD behaviour on top of the existing queue model.

---

*This document should serve as the technical specification for making the simulator teachable. Every gap identified here represents a concept that an instructor currently cannot demonstrate. The trait system is designed to close these gaps incrementally without rewriting the engine.*

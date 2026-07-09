# Node Config Mapping - Current vs. Apt

> **Purpose:** For every one of the 72 palette nodes, the config a user *should* see (apt, in domain language) mapped against what the panel shows *today*. This is the reference for making node configuration make sense - to a first-year student and to a senior engineer alike.
>
> **Date:** July 2026
>
> **Why this exists:** The config panel is currently rendered in the *engine's* vocabulary (lambda, workers, raw G/G/c/K bounds), shown near-identically for every node type regardless of whether those knobs teach anything. A senior looking at a Load Balancer L4 sees `Lambda: 6.666666666667`, `Workers: 8`, and `Availability Target: 0 ratio` and reasonably asks "why is this here?" - and there is no answer. This doc defines the apt config per node so that every field on screen earns its place.
>
> **Source of truth:** the "Config knobs" already written per node in [`node-behaviour-specification.md §3`](./node-behaviour-specification.md) (reused, not reinvented - P22), the current `fieldConfig.ts` / `PROFILE_FIELD_GROUPS`, the seeded `TYPE_MEAN_SERVICE_MS`, and the four display fixes diagnosed on the live L4 panel.
>
> **Companion:** [`node-config-architecture.md`](./node-config-architecture.md) - *how* every "Proposed" column below gets produced: the capability-module system (traits grown to own their config, defaults, constraints, and honesty notes) that derives each panel by composition instead of authoring 72 forms. The mapping is the *what*; the architecture is the *how*.

---

## The five design rules that generate every "Proposed" column

Every proposal below follows these - so the mapping is principled, not opinion:

1. **Domain vocabulary, never engine internals.** "Mean service time: 0.15 ms", never "Lambda: 6.666". A user configures *behaviour*, not a distribution's rate parameter. (Engine keeps lambda internally; the panel translates.)
2. **No unset value shown as a real number.** SLO P99 and Availability Target become opt-in ("Add an SLO target"), never an ambient `0` that reads as a chosen value. (P2, P6)
3. **Relabel the base-queue params per node.** "Workers" means different physical things on an LB (max concurrent connections), a DB (connection pool size), and a serverless fn (concurrency limit). The label must match the node. (P1)
4. **Two altitudes.** Teaching-relevant knobs are primary; the raw queueing-model internals (discipline, distribution shape) live under an **Advanced ▸** disclosure - available, not amputated. (P12)
5. **Every field carries provenance.** Each is tagged user-set / default (with a one-line rationale) / not-simulated, so "why is this here / why this value?" is always answerable on hover. (P6, P11)

---

## The shared base, today (stated once so it isn't repeated 72×)

Every non-source node currently shows the same three sections, in raw engine terms, regardless of type:

| Section | Fields shown today | Problem |
|---|---|---|
| **Queueing** | `Workers`, `Capacity`, `Queue Discipline` | Same label on every node; "workers" is wrong for LBs, caches, storage |
| **Processing** | `Timeout`, `Distribution`, **`Lambda`/`Mu`/`Sigma`** | Raw distribution parameters exposed - the single worst offender |
| **Reliability** | `Node Health` + error %, `SLO P99`, `Availability Target` | SLO/availability show `0` when unset; error % is a chaos knob with no label |

**The trait overlay** (Routing, Caching, Rate Limiting, Read/Write Split, Content Routing) is the *only* part that currently differs by node type - and it's the only part that's honest. The proposals below keep and extend the overlay, and fix the shared base per rule 3–4.

---

## Legend

| Mark | Meaning |
|---|---|
| ✅ | Trait/config **built** and wired (this branch) |
| 🔶 | **In-flight** (uncommitted on branch) |
| 📋 | **Proposed** in the spec, not yet built |
| 🔒 | Constraint / locked field (teaching-by-denial, e.g. L4 content routing) |
| - | Base queue only today (no distinguishing config) |

---

## Summary - all 72 nodes, distinguishing config only

*(The shared base - queueing/processing/reliability - is on every row and omitted here; only the config that makes each node **itself** is shown.)*

### Clients & Edge

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| Client App `client-user` | Workload pattern, Base RPS ✅ | Pattern, Base RPS, request-type mix (%GET/%POST → routing) | ✅ / 📋 mix |
| Input Source `input-source` | Workload pattern, Base RPS ✅ | same as Client App | ✅ |
| DNS Resolver `dns` | - | Cache TTL, Routing policy (simple/weighted/failover/latency/geo) | 📋 |
| CDN `cdn` | Cache hit rate, hit latency, TTL ✅ | Cache hit rate, hit latency, TTL, origin-shield toggle | ✅ |

### Network

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| Load Balancer (Legacy) `load-balancer` | Routing strategy, Health check ✅ | Strategy, Health check, sticky sessions | ✅ / 📋 sticky |
| Load Balancer L4 `load-balancer-l4` | Strategy, Health check ✅ · 🔒 content routing | Strategy *(L4 set: RR, weighted, least-conn, source-IP-hash)*, Health check, Protocol (TCP/UDP) · 🔒 content routing | ✅ |
| Load Balancer L7 `load-balancer-l7` | Strategy, Health check, **Routing rules** ✅🔶 | Strategy *(full + path/host)*, Health check, Routing rules, SSL termination | ✅ / 📋 SSL |
| API Gateway `api-gateway` | Strategy, Health check, Routing rules, **Rate limit** ✅🔶 | Rate limiter (bucket, refill), Auth rejection rate, Routing rules, Transform overhead | ✅ / 📋 auth,transform |
| Ingress Controller `ingress-controller` | Strategy, Health check, Routing rules ✅🔶 | Routing rules, Health check, SSL termination | ✅ / 📋 SSL |
| Reverse Proxy `reverse-proxy` | Cache hit rate, Health check ✅ | Cache hit rate (optional), Compression toggle, Strategy | ✅ / 📋 compression |
| Service Mesh `service-mesh` | - | Retry policy (attempts, delay), Circuit breaker (threshold, recovery), mTLS overhead, Canary split | 📋 |
| NAT Gateway `nat-gateway` | - | Bandwidth limit, Direction (outbound-only, validation) | 📋 |
| VPN Gateway `vpn-gateway` | - | Encryption overhead factor, Bandwidth limit, Tunnel redundancy | 📋 |
| Routing Rule `routing-rule` | - | Match type (path/host/header), Match pattern, Target node | 📋 |
| Routing Policy `routing-policy` | - | Distribution strategy (weighted/failover/latency), Weights | 📋 |
| Edge Router `edge-router` | - | *(base adequate; teaching is on the edge `pathType`)* | 📋 (edge) |
| Network Interface `network-interface` | - | Bandwidth limit, Packets-per-second limit | 📋 |
| DNS Server `dns-server` | - | Cache TTL, Routing policy (simple/weighted/failover/latency/geo) | 📋 |
| Sharding `sharding` | - | Hash algorithm (consistent/modulo), Virtual nodes, Shard-key field | 📋 |
| Hashing `hashing` | - | same as Sharding | 📋 |

### Security

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| WAF `waf` | Block rate, Dropped packets ✅ | Block rate, Block rules (conditions), Rate limit per source | ✅ / 📋 rules |
| Firewall Rule `firewall-rule` | Block rate, Dropped packets ✅ | Dropped-packet rate, Allowed protocols *(L3/L4 - no content rules)* | ✅ / 📋 protocols |
| Security Group `security-group` | Block rate, Dropped packets ✅ | Default policy (deny-all), Allow rules (source nodes) | ✅ / 📋 rules |

### Compute

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| API Server `backend-server` | - | *(base good)* + Processing mode (CPU/IO-bound), Memory-pressure threshold | 📋 |
| Serverless Fn `lambda-function` | - | Cold-start latency, Max concurrency (hard cap), Idle timeout, Timeout | 📋 |
| Auth Service `auth-service` | - | Validation latency, Issuance latency, Auth rejection rate, Critical-path flag | 📋 |
| Search Service `search-service` | - | Simple-query latency, Complex-query latency, Query-type mix | 📋 |
| Sidecar Proxy `sidecar-proxy` | - | Per-request overhead, Retry policy, Circuit breaker | 📋 |
| Streaming Analytics `streaming-analytics` | - | *(base)* + window size, watermark lag | 📋 |
| LLM Gateway `llm-gateway` | - | Mean latency (~2000ms), Tokens-per-minute limit, Prompt/completion tokens | 📋 |
| Service / My Service `generic-service`,`my-service` | - | *(base is the point - the generic node)* | - |
| Job Worker `async-worker` | - | *(base)* + incoming edges default async | 📋 |
| Cron Job `cron-job` | - | Schedule interval, Trigger source (scheduled - self-generates) | 📋 |
| Notification Service `push-notification-service` | - | *(base)* + fan-out factor | 📋 |

### Data Stores

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| Primary DB `primary-db` | Read/Write latency ✅🔶 | Read latency, Write latency, Connection-pool size *(was "workers")*, Replication + lag | ✅ / 📋 pool,repl |
| Read Replica `read-replica` | Read-only (role) ✅ | Read-only (rejects writes → `read_only_node`), Replication lag | ✅ |
| Redis Cache `redis-cache` | Cache hit rate, hit latency, TTL ✅ | Hit rate, Hit latency, Max memory (eviction), Eviction policy (LRU/LFU/TTL), TTL | ✅ / 📋 memory,evict |
| NoSQL DB `nosql-db` | - | Read/Write capacity units, Consistency (eventual/strong) + per-mode latency | 📋 |
| Object Storage `object-storage` | - | Latency-per-MB, Max object size, Storage class (standard/IA/glacier) | 📋 |
| Search Index `search-index` | - | Index latency (write), Search latency (read), Refresh interval | 📋 |
| Time-series DB `time-series-db` | - | Write latency (low), Read-latency-per-hour-of-range | 📋 |
| Graph DB `graph-db` | - | Hop latency, Max traversal depth | 📋 |
| Vector DB `vector-db` | - | Dimensions, Index-size multiplier (ANN latency) | 📋 |
| Data Warehouse `data-warehouse` | - | Query latency (wide, 100ms–30s) - OLAP, not OLTP | 📋 |
| Data Lake `data-lake` | - | Scan-latency-per-GB (schema-on-read) | 📋 |
| KV Store `kv-store` | - | Lookup latency (very low, narrow) | 📋 |
| Memory Fabric `memory-fabric` | - | *(base)* + access latency | 📋 |
| Shard / Partition Node | - | *(base - each shard is a standard queue)* | - |

### Messaging

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| Message Queue `message-queue` | Ack-at-enqueue (unconditional) ✅ | Delivery semantics, Visibility timeout, Max-receive→DLQ, DLQ node, Retention | ✅ / 📋 dlq,semantics |
| Event Broker (Kafka) `message-broker` | Broadcast routing ✅ | Partition count, Replication factor, Retention, Consumer groups | ✅ / 📋 partitions |
| Pub/Sub `pub-sub` | Broadcast routing ✅ | Delivery mode (push/pull), Filter expression (per-sub), Ack deadline | ✅ / 📋 filter |
| Event Stream `stream` | - | Shard count, Read/Write capacity per shard, Retention hours | 📋 |

### Infrastructure & Control

| Node | Current distinguishing config | Proposed apt config | Status |
|---|---|---|---|
| Health Check Manager `health-check-monitor` | Probe config ✅ | Check interval, Unhealthy/Healthy thresholds, Monitored nodes, Registered LBs | ✅ |
| Discovery Service `discovery-service` | - | Registered services, Heartbeat interval, Deregistration timeout | 📋 |
| Config/Secrets/Feature-Flag | - | *(base)* + Critical-dependency flag (dependents fail if down) | 📋 |
| External Service `external-service` | Rate limiter ✅ | Rate limit RPS, Error rate (1–5% default), Wide latency distribution | ✅ / 📋 |
| Output Sink `output-sink` | - | *(terminal - base adequate)* | - |
| Observability (Metrics/Log/Trace/Alerting) | Async-only ✅ | Async edges (enforced); Tracing: sampling rate; Alerting: alert thresholds | ✅ / 📋 sampling |
| VPC / AZ / Subnet | - | *(validation knobs, not sim)*: subnet `isPublic`, AZ `failureMode: independent` | 📋 |

---

## Detailed blocks - the traited nodes (full treatment)

These 11 componentTypes have real behaviour today; their config is where the "apt" bar must be highest.

### Load Balancer L4 · `load-balancer-l4` · router · ✅

| | Config |
|---|---|
| **Current** | Routing Strategy · Health Check ✓ · Workers `8` · Capacity `14` · Discipline `fifo` · Timeout `100ms` · Distribution `exponential` · **Lambda `6.666666666667`** · SLO P99 `0` · Availability `0` · Node Health `0%` |
| **Proposed** | **Routing** → Strategy *(RR / weighted / least-conn / source-IP-hash)*, Health check · **Forwarding capacity** → Max concurrent connections `8` *(was "Workers")*, Connection queue limit `14` *(was "Capacity")* · **Performance** → Mean forwarding latency `0.15 ms` *(was "Lambda 6.666")*, Timeout · **Content routing** → 🔒 locked note · **Advanced ▸** → discipline, distribution shape, injected error % · *SLOs: "Add SLO target" (hidden until added)* |
| **Why** | Lambda→mean latency (rule 1); Workers→connections, Capacity→connection queue (rule 3); unset SLO/availability removed (rule 2); queue internals demoted (rule 4). Nothing removed - everything relabeled or moved. |

### Load Balancer L7 · `load-balancer-l7` · router · ✅🔶

| | Config |
|---|---|
| **Current** | Routing Strategy · Health Check ✓ · Routing Rules (list editor 🔶) · + same base as L4 |
| **Proposed** | **Routing** → Strategy *(full set incl. path/host)*, Health check · **Content routing** → Routing rules *(field → value → target)*, SSL termination *(adds overhead)* · **Forwarding** → Max connections, Connection queue · **Performance** → Mean latency `0.4 ms`, Timeout · **Advanced ▸** base internals |
| **Why** | The L7-vs-L4 difference *is* the presence of Routing rules + SSL. Higher mean latency (0.4 vs 0.15) shown as a human number makes "L7 costs more per request" visible. |

### API Gateway · `api-gateway` · router · ✅🔶

| | Config |
|---|---|
| **Current** | Strategy · Health Check · Routing Rules 🔶 · Rate limit (bucket, refill) 🔶 · + base |
| **Proposed** | **Rate limiting** → Bucket size, Refill rate/s · **Auth** → Auth rejection rate *(→ 401/403, distinct from errors)* · **Content routing** → Routing rules · **Transform** → Transformation overhead ms · **Advanced ▸** base |
| **Why** | A gateway is the compose-point: rate limiter + content routing + auth. Each knob maps to a distinct `rate_limited` / auth-reject / routed outcome the student can see. |

### CDN · `cdn` · router · ✅ &nbsp;·&nbsp; Redis Cache · `redis-cache` · datastore · ✅

| | Config |
|---|---|
| **Current** | Cache Hit Rate · Cache Hit Latency · TTL ✅ · + base |
| **Proposed (CDN)** | **Caching** → Hit rate, Hit latency `1 ms`, TTL, Origin-shield toggle · **Advanced ▸** base |
| **Proposed (Redis)** | **Caching** → Hit rate, Hit latency `0.1 ms`, Max memory *(eviction trigger)*, Eviction policy (LRU/LFU/TTL), TTL · **Advanced ▸** base |
| **Why** | Cache is the flagship "node must be true" win - hit rate genuinely diverts traffic. Redis adds memory/eviction (why hit rate degrades under load); CDN adds origin shield. Same trait, node-specific knobs. |

### Reverse Proxy · `reverse-proxy` · router · ✅

| | Config |
|---|---|
| **Current** | Cache Hit Rate · Health Check ✅ · + base |
| **Proposed** | **Caching** → Hit rate *(optional - off by default)* · **Routing** → Strategy, Health check · **Processing** → Compression toggle *(adds latency)* · **Advanced ▸** base |
| **Why** | A reverse proxy is an LB that *can* cache - the optional cache is the teaching distinction from a plain LB. |

### Primary DB · `primary-db` · datastore · ✅🔶 &nbsp;·&nbsp; Read Replica · `read-replica` · datastore · ✅

| | Config |
|---|---|
| **Current (Primary)** | Read latency · Write latency 🔶 · + base |
| **Proposed (Primary)** | **Read/Write** → Read latency, Write latency *(writes slower - WAL/locking)* · **Connections** → Connection-pool size *(was "workers")* · **Replication** → Enabled, Lag ms · **Advanced ▸** base |
| **Proposed (Replica)** | **Role** → Read-only *(writes rejected `read_only_node`)* · **Replication** → Lag ms *(data staleness)* · **Advanced ▸** base |
| **Why** | "Workers" on a DB is really the connection pool - the thing that exhausts. Read/write split makes the workload mix matter; replica read-only + lag teaches the scaling pattern and its cost (staleness). |

### Message Queue · `message-queue` · broker · ✅

| | Config |
|---|---|
| **Current** | Ack-at-enqueue (unconditional, shown as identity chip) ✅ · + base |
| **Proposed** | **Delivery** → Semantics (at-least/at-most/exactly-once), Visibility timeout · **Failure** → Max-receive → DLQ, DLQ node · **Retention** → Max retention · **Advanced ▸** base |
| **Why** | The producer-decoupling (ack-at-enqueue) is already true; the missing knobs are the ones that make a queue a *queue* vs a broker - DLQ, visibility, semantics. |

### Observability nodes · async-only · ✅

| | Config |
|---|---|
| **Current** | Async edges enforced (no blocking) ✅ · + base |
| **Proposed** | **Delivery** → Async (enforced, shown as locked note) · Tracing collector adds Sampling rate · Alerting adds Alert thresholds · **Advanced ▸** base |
| **Why** | The honest thing here is the *constraint*: these never add latency to the request path. Show it as a locked note (why the base timeout doesn't matter), not a raw editable field. |

---

## What this mapping changes, in one paragraph

Today, config is **the engine's data model with labels** - 72 nodes drawing from one shared base of `workers / capacity / lambda / SLO`, differentiated only by a thin trait overlay on 11 of them. The proposal turns it into **each node's real operating manual**: the base is relabeled to the node's own vocabulary and demoted under Advanced, the raw distribution parameter is replaced by a mean latency anyone can read, unset SLOs stop masquerading as zeros, and the 39 untraited nodes gain the specific knobs the node-behaviour spec already wrote for them. The test for "done" is the senior's question - *"why is this field here, and why this value?"* - being answerable, on hover, for every field on every node.

---

## Implementation note

This mapping is a **spec, not a migration**. Delivering it splits cleanly:

1. **Display-layer fixes (no engine change, biggest immediate win):** lambda→mean-latency translation, unset-as-zero removal, per-node relabels, the Advanced disclosure. All in `fieldConfig.ts` + the properties form.
2. **Provenance (B1/B2):** the hover rationale that answers "why this value" - needs the unified default resolver.
3. **New trait knobs (📋 rows):** each ships with its trait per the node-behaviour spec's priority order (#178 → #180). The config field lands with the behaviour, never ahead of it (P20).

Do (1) first: it makes the *existing* config honest for all 72 nodes at once, and it's pure frontend.

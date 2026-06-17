# NS-Simulator: Real-World Fidelity, Telemetry Mapping, and Infrastructure-as-Code Export

> **Purpose:** Make the simulator faithful to how real-world infrastructure actually works — real technologies (Nginx, PostgreSQL, Redis, Kafka), real network physics (propagation delay, TCP overhead, bandwidth limits), real observability formats (OpenTelemetry, Prometheus, structured logs), and real Infrastructure-as-Code export (Terraform HCL for AWS, GCP, and Azure). If a student builds it in the simulator, it should translate accurately to the real world.
>
> **Date:** June 2026
>
> **Key insight:** The simulator already produces the right *categories* of data (throughput, latency percentiles, queue depth, utilization, traces with spans). What's missing is (1) node configs use abstract simulation parameters instead of real technology configs, (2) edge behaviour ignores real network physics, (3) the output format doesn't match any real observability standard, and (4) there's no IaC export path to turn a diagram into deployable infrastructure.

---

## Table of Contents

1. [The Translation Problem](#1-the-translation-problem)
2. [Real-World Technology Configs — What Each Node Actually Is](#2-real-world-technology-configs)
3. [Real-World Network Physics — How Edges Actually Behave](#3-real-world-network-physics)
4. [Node-to-Cloud Resource Mapping (AWS, GCP, Azure)](#4-node-to-cloud-resource-mapping)
5. [Edge-to-Cloud Networking Mapping](#5-edge-to-cloud-networking-mapping)
6. [Simulator Config → Real Config Translation](#6-simulator-config--real-config-translation)
7. [Telemetry Fidelity: Simulator Output → Real Observability](#7-telemetry-fidelity-simulator-output--real-observability)
8. [Terraform HCL Export Specification](#8-terraform-hcl-export-specification)
9. [Multi-Cloud Export Architecture](#9-multi-cloud-export-architecture)
10. [Implementation Roadmap](#10-implementation-roadmap)

---

## 1. The Translation Problem

### 1.1 What "Real-World Translation" Means

A student builds a topology in the simulator:

```
Client → CDN → L7 LB → [API Server, API Server] → Primary DB
                                                  → Redis Cache
```

Today, this is a teaching diagram with a simulation engine behind it. The student sees throughput, latency, queue depth. But they can't:

1. **Deploy it** — no way to turn the diagram into real infrastructure (AWS, GCP, Azure, or on-prem)
2. **Compare telemetry** — simulator metrics don't look like what Grafana, Datadog, or CloudWatch actually show
3. **Understand real config** — simulator knobs (`workers`, `capacity`, `meanServiceMs`) don't map to real technology parameters (Nginx `worker_processes`, PostgreSQL `max_connections`, Redis `maxmemory`)
4. **Reason about network behaviour** — edges have abstract latency distributions instead of real physics (propagation delay + serialization delay + TCP handshake + TLS negotiation)

### 1.2 The Four Translation Layers

| Layer | From (Simulator) | To (Real World) | Status |
|---|---|---|---|
| **Technology fidelity** | `workers: 4, distribution: exponential(λ=0.125)` | Nginx `worker_processes 4`, PostgreSQL `max_connections 200`, Redis `maxmemory 4gb` | Not started |
| **Network physics** | `latency: lognormal(μ=2.3, σ=0.5)` | Propagation delay + serialization + TCP/TLS overhead + queueing at each hop | Not started |
| **Telemetry translation** | `{ throughput: 850, latencyP99: 12.3 }` | OTEL spans, Prometheus histograms, structured JSON logs | Not started |
| **IaC export** | `TopologyJSON` → ? | Terraform HCL for AWS / GCP / Azure | Not started |

### 1.3 Why This Matters for Teaching

- **Computer Networks course:** Students learn about CDNs, load balancers, firewalls. Seeing real Nginx config or Terraform for a cloud load balancer makes it tangible.
- **System Design course:** Students design architectures. Exporting to Terraform validates that their design is deployable, not just a whiteboard drawing.
- **DevOps course:** Students need to understand IaC. Generating Terraform from a visual diagram bridges "I designed a system" and "I deployed a system."
- **Cloud-agnostic thinking:** Real engineers work across AWS, GCP, Azure, and on-prem. The simulator should teach concepts, not vendor lock-in.

---

## 2. Real-World Technology Configs — What Each Node Actually Is

> The simulator's nodes represent real technologies. A "Load Balancer L7" isn't an abstract box — it's Nginx, HAProxy, Envoy, or a cloud ALB. This section defines the real configuration parameters for each technology so the simulator can show students what they'd actually configure in production.

### 2.1 Load Balancers

#### Nginx (reverse proxy / L7 load balancer)

The most widely deployed web server and reverse proxy. Real production config:

```nginx
# /etc/nginx/nginx.conf
worker_processes auto;           # Typically = CPU cores (sim workers)
worker_connections 1024;         # Max simultaneous connections per worker
keepalive_timeout 65;            # Connection reuse timeout
client_max_body_size 10m;        # Max request size

upstream api_servers {
    # Round-robin is default — matches sim routingStrategy: 'round-robin'
    # Alternative: least_conn; ip_hash; random;
    server 10.0.1.10:8080 weight=5;    # sim edge weight
    server 10.0.1.11:8080 weight=3;
    server 10.0.1.12:8080 backup;      # only used when others are down

    keepalive 32;                       # persistent connections to upstream
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate     /etc/ssl/certs/api.pem;
    ssl_certificate_key /etc/ssl/private/api.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location /api/ {
        proxy_pass http://api_servers;
        proxy_connect_timeout 5s;       # sim edge latency budget
        proxy_read_timeout 60s;         # sim processing.timeout
        proxy_send_timeout 60s;

        # Health checking
        proxy_next_upstream error timeout http_500 http_502 http_503;
        proxy_next_upstream_tries 2;    # sim resilience.retry
    }
}
```

**Simulator property mapping:**

| Simulator Property | Nginx Config | Real-World Notes |
|---|---|---|
| `queue.workers` | `worker_processes` | Typically set to CPU core count. Each worker handles thousands of connections via epoll/kqueue. |
| `queue.capacity` | `worker_connections * worker_processes` | Nginx uses event-driven I/O — "capacity" is connection count, not queue depth. Default 512-1024 per worker. |
| `routingStrategy: round-robin` | Default upstream behaviour | Nginx round-robins by default. `least_conn` available. |
| `routingStrategy: weighted` | `server ... weight=N` | Direct mapping — weight determines traffic proportion. |
| `processing.timeout` | `proxy_read_timeout` | Time waiting for upstream response. Default 60s. |
| `resilience.retry` | `proxy_next_upstream_tries` | Number of upstream servers to try on failure. |
| `resilience.circuitBreaker` | `max_fails` + `fail_timeout` on upstream server | `server 10.0.1.10:8080 max_fails=3 fail_timeout=30s;` |
| Edge `protocol` | `listen 443 ssl` vs `listen 80` | TLS termination at Nginx is the norm. |

#### HAProxy (L4/L7 load balancer)

Purpose-built load balancer, common in high-throughput environments:

```haproxy
# /etc/haproxy/haproxy.cfg
global
    maxconn 50000                       # Total max connections (sim capacity)
    nbproc 1                            # Process count
    nbthread 4                          # Thread count (sim workers)

defaults
    mode http                           # L7 mode (vs 'tcp' for L4)
    timeout connect 5s                  # Time to establish connection to backend
    timeout client  30s                 # Client inactivity timeout
    timeout server  30s                 # Backend response timeout (sim processing.timeout)
    timeout queue   10s                 # Time waiting in queue (sim queue wait)
    retries 3                           # Retry count (sim resilience.retry)

frontend http_front
    bind *:443 ssl crt /etc/ssl/cert.pem
    default_backend api_servers
    maxconn 10000                       # Frontend connection limit

backend api_servers
    balance roundrobin                  # or leastconn, source, uri, random
    option httpchk GET /health          # Health check
    http-check expect status 200

    server api1 10.0.1.10:8080 check inter 5s fall 3 rise 2 weight 100 maxconn 1000
    server api2 10.0.1.11:8080 check inter 5s fall 3 rise 2 weight 100 maxconn 1000
```

**Key real-world parameters not in the simulator:**

| Real Config | What It Does | Impact on Simulation |
|---|---|---|
| `timeout queue` | Max time a request waits in HAProxy's queue before being rejected | Should map to a queue timeout (separate from processing timeout) |
| `maxconn` (per server) | Connection limit to each backend — HAProxy queues beyond this | This IS the real-world analog of `queue.capacity` per downstream node |
| `inter 5s fall 3 rise 2` | Health check every 5s, mark down after 3 failures, up after 2 successes | Health-check timing affects how quickly failed nodes are removed from rotation |
| `option httpchk` | Active health checking with real HTTP requests | Sim only has failure/recovery events, not health-check probing |

#### Envoy Proxy (service mesh / L7 proxy)

Modern proxy used in service mesh architectures (Istio, App Mesh):

```yaml
# Envoy config (simplified)
static_resources:
  clusters:
    - name: api_service
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN              # or LEAST_REQUEST, RANDOM, RING_HASH
      connect_timeout: 5s
      load_assignment:
        cluster_name: api_service
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: api-server
                      port_value: 8080
      circuit_breakers:
        thresholds:
          - max_connections: 1000          # sim queue.capacity
            max_pending_requests: 1000     # sim queue waiting slots
            max_requests: 1500             # sim max concurrent
            max_retries: 3                 # sim resilience.retry
      outlier_detection:
        consecutive_5xx: 5                 # Mark host unhealthy after 5 errors
        interval: 10s                      # Check interval
        base_ejection_time: 30s            # Min ejection time
        max_ejection_percent: 50           # Max % of hosts ejected
      health_checks:
        - timeout: 5s
          interval: 10s
          unhealthy_threshold: 3
          healthy_threshold: 2
          http_health_check:
            path: /health
```

**Key insight for simulator:** Envoy's circuit breaker config (`max_connections`, `max_pending_requests`, `max_requests`) is the **real-world equivalent** of the simulator's queue model. `max_connections` + `max_pending_requests` ≈ `queue.capacity`.

### 2.2 Databases

#### PostgreSQL (relational-db)

The most common production RDBMS. Real config (`postgresql.conf`):

```ini
# Connection Management
max_connections = 200                    # Total connection slots (sim workers analog)
superuser_reserved_connections = 3
idle_in_transaction_session_timeout = 30s

# Memory (critical for performance)
shared_buffers = 4GB                     # ~25% of RAM. Cache for frequently accessed data.
work_mem = 64MB                          # Per-query sort/hash memory
maintenance_work_mem = 512MB             # VACUUM, CREATE INDEX memory
effective_cache_size = 12GB              # ~75% of RAM. Tells planner about OS cache.

# WAL & Durability
wal_level = replica                      # Required for replication
max_wal_size = 2GB
synchronous_commit = on                  # Set 'off' for ~2x write throughput but risk data loss

# Query Performance
random_page_cost = 1.1                   # For SSD storage (default 4.0 for HDD)
effective_io_concurrency = 200           # For SSD: 200. For HDD: 2.
statement_timeout = 30s                  # Kill queries longer than this (sim processing.timeout)

# Replication (for read replicas)
max_replication_slots = 4
hot_standby = on                         # Allow reads on replicas
```

**Simulator property mapping:**

| Simulator Property | PostgreSQL Config | Real-World Notes |
|---|---|---|
| `queue.workers` | `max_connections` | Not 1:1 — each connection can run 1 query at a time, but Postgres uses a process-per-connection model. Real `max_connections` is typically 100-500. |
| `queue.capacity` | Connection pool queue (e.g., PgBouncer `default_pool_size`) | Postgres itself doesn't queue — connection pools do (PgBouncer, pgpool-II). |
| `processing.distribution` (mean ~8ms) | Depends on query complexity, data size, indexes | Simple key lookup: ~0.5ms. Complex join: ~50-500ms. Full table scan: seconds. The mean of 8ms is reasonable for indexed OLTP queries. |
| `processing.timeout` | `statement_timeout` | Direct mapping. Kills queries exceeding this. |
| `resources.memory` | `shared_buffers` (~25% of RAM) | If sim says 16GB RAM → `shared_buffers = 4GB`, `effective_cache_size = 12GB` |

**Real latency breakdown for a PostgreSQL query:**

| Phase | Typical Duration | What Causes It |
|---|---|---|
| Network round-trip to DB | 0.1-2ms (same DC) | TCP + possible TLS |
| Parse + Plan | 0.01-0.5ms | SQL parsing, query planner |
| Execute (index lookup) | 0.1-2ms | B-tree traversal, page reads |
| Execute (sequential scan) | 10-1000ms | Full table scan |
| Execute (complex join) | 5-500ms | Hash join, merge join |
| Lock wait (contention) | 0-∞ | Row locks, table locks |
| WAL write (durability) | 0.01-0.5ms | Flush to disk |
| Return results | 0.01-10ms | Depends on result set size |

#### MySQL / MariaDB (relational-db alternative)

```ini
# my.cnf
[mysqld]
max_connections = 200                    # Similar to PostgreSQL
innodb_buffer_pool_size = 12G            # ~70-80% of RAM (like shared_buffers)
innodb_io_capacity = 2000                # IOPS budget for background tasks
innodb_flush_log_at_trx_commit = 1       # 1 = durable, 2 = faster but riskier
wait_timeout = 28800                     # Idle connection timeout (seconds)
max_allowed_packet = 64M                 # Max query/result size
query_cache_size = 0                     # Deprecated in MySQL 8.0
thread_cache_size = 16                   # Thread pool size
```

#### Redis (in-memory-cache)

Single-threaded event loop (since Redis 6.0, I/O threads for networking):

```
# redis.conf
maxmemory 4gb                            # Memory limit (sim resources.memory)
maxmemory-policy allkeys-lru             # Eviction policy when full
maxclients 10000                         # Max connections (sim queue.capacity)
tcp-keepalive 300                        # TCP keepalive interval
timeout 0                                # Client idle timeout (0 = never)

# Persistence
save 900 1                               # RDB snapshot every 900s if 1+ keys changed
save 300 10
appendonly yes                           # AOF persistence
appendfsync everysec                     # Fsync every second

# Replication
replica-read-only yes
repl-diskless-sync yes
min-replicas-to-write 1                  # Require at least 1 replica for writes
min-replicas-max-lag 10                  # Max replication lag in seconds

# Cluster (for horizontal scaling)
cluster-enabled yes
cluster-node-timeout 15000
```

**Simulator property mapping:**

| Simulator Property | Redis Config | Real-World Notes |
|---|---|---|
| `queue.workers` | **1** (single-threaded) | Redis processes commands sequentially on a single thread. It achieves 100K+ ops/s through efficient event loop, not parallelism. The sim's `workers: 4` for Redis is **wrong** — should be `workers: 1`. |
| `queue.capacity` | `maxclients` | Max simultaneous connections. Commands are queued in each connection's buffer. |
| `processing.distribution` (mean ~0.1ms) | Inherent | Single-threaded in-memory operations: GET ~25µs, SET ~25µs, LPUSH ~30µs. 0.1ms is realistic. |
| `resources.memory` | `maxmemory` | Direct mapping. When exceeded, eviction policy kicks in. |

**Real Redis latency by operation:**

| Operation | Typical Latency | Notes |
|---|---|---|
| GET (simple key) | 10-30µs | Single key lookup in hash table |
| SET (simple key) | 10-30µs | Hash table insert |
| MGET (100 keys) | 100-300µs | Batch read |
| LPUSH / RPOP | 20-40µs | List operations |
| ZADD (sorted set) | 30-80µs | O(log N) insertion |
| ZRANGEBYSCORE | 50-500µs | Depends on result set size |
| KEYS * (pattern scan) | 1-100ms+ | **Dangerous** — scans all keys, blocks single thread |
| Network round-trip | 50-200µs | Same-DC. Dominates for simple commands. |

**Critical insight:** For Redis, network round-trip often exceeds command execution time. The sim's `edgeLatency` to a Redis node matters more than `serviceTime`.

#### Apache Kafka (message-broker / stream)

Distributed streaming platform. Real broker config:

```properties
# server.properties
num.io.threads=8                         # Threads for disk I/O
num.network.threads=3                    # Threads for network requests
num.partitions=6                         # Default partitions per topic
default.replication.factor=3             # Replicas per partition
min.insync.replicas=2                    # Must ack before commit

log.retention.hours=168                  # 7 days retention
log.segment.bytes=1073741824             # 1GB log segments
log.retention.bytes=-1                   # No size-based retention

socket.send.buffer.bytes=102400          # TCP send buffer
socket.receive.buffer.bytes=102400       # TCP receive buffer
socket.request.max.bytes=104857600       # Max request size (100MB)

message.max.bytes=1048576                # Max message size (1MB)

replica.lag.time.max.ms=30000            # Max lag before replica is out of sync
unclean.leader.election.enable=false     # Don't allow out-of-sync replica to become leader
```

**Real Kafka latency breakdown:**

| Phase | Duration | What Drives It |
|---|---|---|
| Producer → broker network | 0.1-2ms (same DC) | TCP/TLS |
| Broker receive + validate | 0.01-0.1ms | Message validation |
| Write to page cache | 0.01-0.05ms | OS page cache (not disk yet) |
| Replicate to followers | 0.5-5ms | Network + follower write |
| Ack to producer | 0.1ms | After `min.insync.replicas` ack |
| **Total (acks=all)** | **1-10ms** | Dominated by replication |
| **Total (acks=1)** | **0.5-3ms** | Leader-only ack |
| **Total (acks=0)** | **0.1-0.5ms** | Fire-and-forget |
| Consumer poll → fetch | 1-50ms | Depends on `fetch.max.wait.ms` |

**Simulator property mapping:**

| Simulator Property | Kafka Config | Real-World Notes |
|---|---|---|
| `queue.workers` | `num.partitions` (topic-level parallelism) | Partitions are the unit of parallelism. Consumers can have at most 1 consumer per partition in a group. |
| `queue.capacity` | `log.retention.bytes` or `log.retention.hours` | Kafka doesn't have a "queue depth" — it retains by time/size. Unbounded backlog is normal. |
| `routingStrategy: broadcast` | Topic with multiple consumer groups | Each consumer group gets every message — this IS broadcast. |
| `asyncBoundary: true` | Fundamental property | Kafka is always async. Producers don't wait for consumers. |
| `processing.distribution` (mean ~0.5ms) | Depends on `acks` setting | `acks=all`: 2-10ms. `acks=1`: 1-3ms. `acks=0`: 0.1-0.5ms. |

#### RabbitMQ (message-queue)

Traditional message broker with AMQP protocol:

```ini
# rabbitmq.conf
listeners.tcp.default = 5672
management.listener.port = 15672

# Resource limits
vm_memory_high_watermark.relative = 0.6   # Block publishers at 60% RAM
disk_free_limit.relative = 1.5            # Block at 1.5x RAM free disk

# Queue defaults
queue.max_length = 100000                  # Max messages in queue (sim capacity!)
queue.max_length_bytes = 1073741824        # 1GB per queue

# Consumer limits
consumer_timeout = 1800000                 # 30 min consumer ack timeout
channel_max = 2047                         # Max channels per connection
```

**Simulator property mapping:**

| Simulator Property | RabbitMQ Config | Real-World Notes |
|---|---|---|
| `queue.capacity` | `queue.max_length` | **Direct real-world analog!** RabbitMQ actually has a queue depth limit. |
| `queue.discipline: fifo` | Default behaviour | Queues are FIFO by default. Priority queues supported with `x-max-priority`. |
| `processing.timeout` | `consumer_timeout` | How long a consumer can hold a message before it's requeued. |
| `routingStrategy: broadcast` | Fanout exchange | Direct mapping to AMQP exchange types: fanout, direct, topic, headers. |

### 2.3 Caches and CDNs

#### Varnish Cache (CDN / caching proxy)

```vcl
# default.vcl
vcl 4.1;

backend api {
    .host = "api-server";
    .port = "8080";
    .connect_timeout = 5s;
    .first_byte_timeout = 60s;        # sim processing.timeout
    .between_bytes_timeout = 2s;
    .probe = {
        .url = "/health";
        .interval = 5s;
        .timeout = 2s;
        .threshold = 3;               # 3 out of 5 probes must pass
    }
}

sub vcl_recv {
    # Cache only GET/HEAD
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }
    # Strip cookies for static assets
    if (req.url ~ "\.(css|js|png|jpg|gif|ico)$") {
        unset req.http.Cookie;
        return (hash);
    }
}

sub vcl_backend_response {
    set beresp.ttl = 300s;            # Cache for 5 minutes
    set beresp.grace = 3600s;         # Serve stale for 1 hour on backend failure
}
```

**Real cache performance:**

| Metric | Varnish | CloudFront | Fastly | Nginx Cache |
|---|---|---|---|---|
| Cache hit latency | 0.05-0.5ms | 1-50ms (PoP dependent) | 1-30ms | 0.1-1ms |
| Cache miss penalty | Full backend latency + cache write | Origin fetch + edge cache | Origin fetch | Backend latency |
| Typical hit ratio | 80-99% (depends on content) | 70-95% | 80-98% | 70-90% |
| Max object size | Limited by RAM | 30GB | 5GB | Limited by disk |

### 2.4 Firewalls and Security

#### iptables / nftables (Linux network firewall)

```bash
# iptables rules — what the sim's "firewall" actually is
iptables -A INPUT -p tcp --dport 443 -j ACCEPT           # Allow HTTPS
iptables -A INPUT -p tcp --dport 80 -j ACCEPT            # Allow HTTP
iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT  # SSH from private network only
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -j DROP                                  # Drop everything else

# Rate limiting (sim blockRate analog)
iptables -A INPUT -p tcp --dport 443 -m limit --limit 100/s --limit-burst 200 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j DROP               # Drop if rate exceeded
```

**Real-world firewall latency:** iptables adds ~0.01-0.05ms per packet for simple rulesets. Complex rulesets (1000+ rules) can add 0.1-0.5ms. nftables is faster. The simulator's `waf` node with mean service time of 0.3ms is realistic.

#### ModSecurity / OWASP WAF

```
# WAF rule example (ModSecurity)
SecRule REQUEST_URI "@contains /admin" \
    "id:1001,phase:1,deny,status:403,msg:'Admin access blocked'"

SecRule ARGS "@detectSQLi" \
    "id:1002,phase:2,deny,status:403,msg:'SQL injection detected'"

SecRule REQUEST_HEADERS:Content-Length "@gt 10485760" \
    "id:1003,phase:1,deny,status:413,msg:'Request too large'"
```

### 2.5 DNS

#### BIND / CoreDNS (internal-dns)

```
; BIND zone file
$TTL 300                                  ; 5 minute TTL (sim cache trait TTL)
@       IN  SOA  ns1.example.com. admin.example.com. (
            2024010101  ; Serial
            3600        ; Refresh
            900         ; Retry
            604800      ; Expire
            300         ; Minimum TTL
)

; A records
api     IN  A    10.0.1.10
api     IN  A    10.0.1.11               ; Round-robin DNS (sim routingStrategy)
db      IN  A    10.0.2.10
cache   IN  A    10.0.3.10

; SRV records for service discovery
_http._tcp.api  IN  SRV  10 60 8080 api1.example.com.
_http._tcp.api  IN  SRV  10 40 8080 api2.example.com.  ; Weighted routing
```

**Real DNS latency:**

| Scenario | Latency | Notes |
|---|---|---|
| Local DNS cache hit | 0-1ms | Resolved from OS or application cache |
| Internal DNS server (same DC) | 0.5-2ms | Authoritative response |
| Recursive resolution (cold) | 20-200ms | Root → TLD → authoritative |
| Route 53 / Cloud DNS | 1-10ms | Anycast, globally distributed |

### 2.6 Compute Runtimes

#### Container Runtime (Docker / containerd)

Key metrics that affect sim `processing.distribution`:

| Phase | Duration | Notes |
|---|---|---|
| Container cold start (Docker) | 300-2000ms | Image pull + layer extraction + process start |
| Container warm start | 10-50ms | Already running, new request arrives |
| Lambda cold start (Node.js) | 100-500ms | Init runtime + load code + establish connections |
| Lambda cold start (Java) | 3000-10000ms | JVM startup + class loading |
| Lambda warm invocation | 1-5ms | Reuse existing execution environment |
| Fargate task start | 30-60s | Provision compute + pull image + start container |
| Kubernetes pod scheduling | 5-30s | Scheduler + image pull + init containers |

**Critical insight for simulator:** The sim's `scaling.coldStartPenalty` should vary dramatically by technology. A Lambda Node.js cold start (200ms) is very different from a Fargate task start (45s).

### 2.7 Summary: Real Config Parameters the Simulator Should Expose

| Node Type | Technology | Key Real Config Parameters |
|---|---|---|
| L7 Load Balancer | Nginx / HAProxy / Envoy | `worker_processes`, `keepalive_timeout`, `proxy_read_timeout`, `upstream` algorithm, health check interval, circuit breaker thresholds |
| L4 Load Balancer | HAProxy / NLB | `maxconn`, `timeout connect/server`, balancing algorithm |
| API Gateway | Kong / Traefik / Envoy | Rate limiting (req/s), auth plugin, circuit breaker, request size limit |
| Primary DB | PostgreSQL / MySQL | `max_connections`, `shared_buffers`, `statement_timeout`, `wal_level`, replication config |
| Read Replica | PostgreSQL / MySQL | Same + `hot_standby`, replication lag monitoring |
| Redis Cache | Redis | `maxmemory`, `maxmemory-policy`, `maxclients`, persistence mode (RDB/AOF/none) |
| Message Queue | RabbitMQ / SQS | `max_length`, exchange type, consumer timeout, dead-letter config |
| Event Broker | Kafka | `num.partitions`, `replication.factor`, `acks`, `retention.hours`, `min.insync.replicas` |
| Pub/Sub | Redis Pub/Sub / NATS | Channel buffer size, subscriber timeout |
| CDN | Varnish / CloudFront | TTL, grace period, cache key config, origin timeout |
| WAF | ModSecurity / AWS WAF | Rule sets, rate limit threshold, action (block/count/allow) |
| Firewall | iptables / nftables | Rule chains, rate limiting, stateful tracking |
| DNS | BIND / CoreDNS | TTL, record types, weighted routing |

---

## 3. Real-World Network Physics — How Edges Actually Behave

> The simulator currently models edge latency as a single lognormal sample. Real network latency is the SUM of multiple physical delays. This section defines the real physics so edges can behave like real networks.

### 3.1 Latency Decomposition

Real network latency between two nodes = sum of:

```
Total Latency = Propagation Delay
              + Serialization Delay
              + Processing Delay (per hop)
              + Queueing Delay (variable)
              + Protocol Overhead (TCP/TLS)
```

#### Propagation Delay (speed of light in fiber)

Light travels at ~200,000 km/s in fiber optic cable (⅔ speed of light in vacuum). Distance determines the floor.

| Path Type (sim) | Real-World Distance | Propagation Delay | Notes |
|---|---|---|---|
| `same-rack` | < 3m | ~0.015µs | Copper cable at near-speed-of-light |
| `same-dc` | 50-500m | 0.25-2.5µs | Within a data center |
| `cross-zone` | 1-10 km (same metro) | 5-50µs | Between availability zones (same city) |
| `cross-region` | 1,000-15,000 km | 5-75ms | Between AWS/GCP regions |
| `internet` | Variable, 100-20,000 km | 0.5-100ms | Public internet, multiple hops |

**Common real-world cross-region latencies:**

| From → To | Distance (km) | Propagation Only | Real Measured (incl. hops) |
|---|---|---|---|
| US-East ↔ US-West | ~4,000 | ~20ms | 60-80ms |
| US-East ↔ EU-West (Ireland) | ~5,500 | ~28ms | 70-90ms |
| US-East ↔ AP-Southeast (Singapore) | ~15,000 | ~75ms | 200-250ms |
| EU-West ↔ AP-Northeast (Tokyo) | ~9,500 | ~48ms | 150-200ms |
| Within same city (AZ to AZ) | 1-10 | ~0.05ms | 0.5-2ms |
| Within same data center | 0.05-0.5 | ~0.003ms | 0.05-0.5ms |

#### Serialization Delay (time to put bits on the wire)

```
Serialization Delay = Packet Size / Link Bandwidth
```

| Packet Size | 1 Gbps Link | 10 Gbps Link | 100 Gbps Link |
|---|---|---|---|
| 64 bytes (minimum) | 0.5µs | 0.05µs | 0.005µs |
| 1,500 bytes (MTU) | 12µs | 1.2µs | 0.12µs |
| 64 KB (max TLS record) | 524µs | 52.4µs | 5.24µs |
| 1 MB (large response) | 8.4ms | 0.84ms | 0.084ms |

**Critical for simulator:** For small requests (< 10KB), serialization delay is negligible on modern networks. For large file transfers or video streaming, it dominates. The sim should factor in `request.sizeBytes`.

#### Protocol Overhead

**TCP Handshake (3-way):**
```
Client → SYN           → Server     (1 × RTT/2)
Client ← SYN+ACK       ← Server     (1 × RTT/2)
Client → ACK            → Server     (1 × RTT/2)
                                      Total: 1.5 × RTT
```
With connection reuse (keepalive), this cost is amortized across requests.

**TLS 1.3 Handshake:**
```
Client → ClientHello              → Server     (1 × RTT/2)
Client ← ServerHello+Certs+Finish ← Server     (1 × RTT/2)
Client → Finished                 → Server     (1 × RTT/2)
                                                Total: 1 × RTT (TLS 1.3)
                                                      2 × RTT (TLS 1.2)
```
With TLS session resumption (0-RTT): **0 additional RTT**.

**Total first-request overhead:**

| Scenario | Additional Latency | Notes |
|---|---|---|
| TCP + TLS 1.3 (first connection) | 2 × RTT | TCP handshake + TLS handshake |
| TCP + TLS 1.2 (first connection) | 3 × RTT | TCP handshake + 2-RTT TLS handshake |
| TCP + TLS 1.3 (0-RTT resumption) | 1 × RTT | TCP handshake only, TLS piggybacked |
| HTTP/2 multiplexed (existing connection) | 0 | Reuses existing connection |
| HTTP/3 QUIC (first connection) | 1 × RTT | Combined transport + TLS handshake |
| HTTP/3 QUIC (0-RTT) | 0 | Sends data with first packet |

**Real impact example:**
- Same-DC (RTT ≈ 0.5ms): TCP+TLS = ~1ms overhead → negligible
- Cross-region (RTT ≈ 70ms): TCP+TLS = ~140ms overhead → **massive**, dominates request latency
- Internet (RTT ≈ 100ms): TCP+TLS = ~200ms overhead → must use connection pooling

### 3.2 Real Bandwidth Constraints

The simulator has `bandwidth` as an edge property (default 1000 Mbps) but the engine ignores it. Real bandwidth matters:

| Network Segment | Typical Bandwidth | Bottleneck? |
|---|---|---|
| Server NIC | 10-25 Gbps | Rarely |
| Top-of-rack switch | 10-100 Gbps | Rarely |
| Data center backbone | 100-400 Gbps | Rarely |
| Cross-AZ link | 5-25 Gbps per flow | Sometimes (throttled by cloud provider) |
| Cross-region link | 1-10 Gbps | Often for large transfers |
| Public internet (last mile) | 10 Mbps - 1 Gbps | Very often |
| Client device (mobile 4G) | 10-50 Mbps | Almost always |
| Client device (mobile 5G) | 50-500 Mbps | Sometimes |

**When bandwidth matters in the sim:**
- CDN → Client: client bandwidth is the bottleneck for media content
- Cross-region replication: database replication + data sync bandwidth limited
- Large message queues: Kafka with high-throughput topics can saturate cross-AZ links
- Object storage: bulk data transfers to/from S3-equivalents

### 3.3 Real Packet Loss Rates

| Network Segment | Typical Loss Rate | Notes |
|---|---|---|
| Same data center | 0.0001% (nearly zero) | Switch fabric is reliable |
| Cross-AZ (same region) | 0.001-0.01% | Cloud provider backbone |
| Cross-region (cloud) | 0.01-0.1% | Dedicated fiber but longer path |
| Public internet (good path) | 0.1-1% | Normal conditions |
| Public internet (congested) | 1-5% | Peak hours, ISP issues |
| Mobile network | 1-10% | Wireless variability |
| International (undersea cable) | 0.01-0.5% | Generally reliable |

**Impact on TCP:** Every lost packet triggers retransmission. With 1% packet loss:
- Single packet request: ~1% chance of +1 RTT delay
- 100-packet response: ~63% chance of at least 1 retransmission (1 - 0.99^100)
- This causes tail latency spikes — explains real-world P99 >> P50

### 3.4 Connection Pooling — The Hidden Multiplier

Real systems don't open a new TCP connection per request. Connection pools are critical:

| Technology | Typical Pool Config | Impact |
|---|---|---|
| HTTP (Nginx upstream) | `keepalive 32` | 32 persistent connections to each upstream |
| Database (PgBouncer) | `default_pool_size = 20` | 20 connections shared across hundreds of app threads |
| Redis (Jedis) | `maxTotal = 128, maxIdle = 32` | Pool of reusable connections |
| gRPC | Multiplexed on single HTTP/2 connection | One connection, many concurrent streams |

**Without connection pooling:** Every request pays TCP+TLS handshake (2-3 RTTs).
**With connection pooling:** Only the first request pays. Subsequent requests reuse.

**Simulator impact:** The sim should model whether edges use persistent connections. First-request latency ≠ steady-state latency.

### 3.5 DNS Resolution — The Invisible Latency

Every first request to a new hostname requires DNS resolution:

```
Application → Local resolver → Root DNS → TLD DNS → Authoritative DNS → IP address
                (cache check)   (13 servers)  (.com)    (example.com)
```

| Scenario | Added Latency | Notes |
|---|---|---|
| OS DNS cache hit | 0ms | Cached from previous lookup |
| Local resolver cache hit | 0.5-2ms | Datacenter DNS server |
| Full recursive resolution | 20-200ms | All the way to authoritative |
| DNS-based load balancing | Adds 1 RTT to resolver | Weighted DNS records (Route 53 weighted) |

**Simulator impact:** DNS resolution should be modeled as a one-time cost per edge at the start of simulation, or as a TTL-based cache with periodic refresh. Currently completely absent from the sim.

### 3.6 Revised Edge Default Values

Based on real-world measurements, the simulator's edge defaults should be updated:

| Path Type | Current `latencyMu` | Recommended `latencyMu` | Recommended `latencySigma` | Packet Loss | Bandwidth |
|---|---|---|---|---|---|
| `same-rack` | (not available) | -2.0 (≈0.14ms mean) | 0.3 | 0.0001% | 25 Gbps |
| `same-dc` | 2.3 (≈10ms mean — **too high**) | 0.0 (≈1ms mean) | 0.5 | 0.001% | 10 Gbps |
| `cross-zone` | (not available) | 0.7 (≈2ms mean) | 0.4 | 0.01% | 5 Gbps |
| `cross-region` | (not available) | 4.3 (≈74ms mean) | 0.3 | 0.05% | 1 Gbps |
| `internet` | (not available) | 4.6 (≈100ms mean) | 0.8 | 0.5% | 100 Mbps |

> **Note:** The current `EDGE_DEFAULTS.latencyMu = 2.3` with `latencySigma = 0.5` gives a lognormal mean of ~14ms, which is far too high for same-datacenter communication. Real same-DC latency is 0.1-1ms.

### 3.7 Protocol-Specific Overhead

The sim should add protocol overhead to edge latency:

| Protocol | Connection Setup | Per-Request Overhead | Notes |
|---|---|---|---|
| `https` (HTTP/1.1) | TCP + TLS = 2 RTT | ~0 (keepalive) | Pipelining possible but rarely used |
| `https` (HTTP/2) | TCP + TLS = 2 RTT | ~0 | Multiplexed streams, header compression |
| `https` (HTTP/3 QUIC) | 1 RTT (or 0-RTT resume) | ~0 | UDP-based, no head-of-line blocking |
| `grpc` | TCP + TLS + HTTP/2 = 2 RTT | ~0 | Built on HTTP/2, binary protobuf encoding |
| `tcp` (raw) | TCP = 1.5 RTT | ~0 | No encryption overhead |
| `amqp` (RabbitMQ) | TCP + AMQP handshake = 2.5 RTT | ~0 | Protocol-level handshake after TCP |
| `kafka` | TCP + SASL/TLS = 2-3 RTT | ~0 | Persistent connection always |
| `websocket` | TCP + TLS + HTTP upgrade = 3 RTT | ~0 | Full-duplex after upgrade |
| `udp` | 0 (connectionless) | Per-packet | No connection setup, no guarantees |

---

## 4. Node-to-Cloud Resource Mapping (AWS, GCP, Azure)

> The same simulator node maps to different managed services depending on the cloud provider. This section covers all three major providers so the simulator is cloud-agnostic in its teaching.

### 4.0 Multi-Cloud Quick Reference

| Simulator Node | Real Technology | AWS | GCP | Azure | Terraform Resource (AWS) |
|---|---|---|---|---|---|
| **L4 Load Balancer** | HAProxy, Nginx (stream) | NLB | Regional TCP/UDP LB | Azure Load Balancer | `aws_lb` (network) |
| **L7 Load Balancer** | Nginx, HAProxy, Envoy | ALB | Global HTTP(S) LB | Application Gateway | `aws_lb` (application) |
| **API Gateway** | Kong, Traefik | API Gateway v2 | Apigee / Cloud Endpoints | API Management (APIM) | `aws_apigatewayv2_api` |
| **CDN** | Varnish, Nginx cache | CloudFront | Cloud CDN | Azure CDN / Front Door | `aws_cloudfront_distribution` |
| **Microservice** | Docker container | ECS Fargate | Cloud Run / GKE | Container Apps / AKS | `aws_ecs_service` |
| **Serverless Fn** | Node.js/Python runtime | Lambda | Cloud Functions | Azure Functions | `aws_lambda_function` |
| **Primary DB** | PostgreSQL, MySQL | RDS / Aurora | Cloud SQL / AlloyDB | Azure SQL / PostgreSQL Flex | `aws_db_instance` |
| **Redis Cache** | Redis | ElastiCache Redis | Memorystore Redis | Azure Cache for Redis | `aws_elasticache_replication_group` |
| **NoSQL DB** | MongoDB, DynamoDB | DynamoDB | Firestore / Bigtable | Cosmos DB | `aws_dynamodb_table` |
| **Message Queue** | RabbitMQ | SQS | Cloud Tasks / Pub/Sub | Service Bus Queue | `aws_sqs_queue` |
| **Event Broker** | Apache Kafka | MSK | Confluent on GCP / Pub/Sub | Event Hubs (Kafka API) | `aws_msk_cluster` |
| **Pub/Sub** | NATS, Redis Pub/Sub | SNS | Cloud Pub/Sub | Event Grid / Service Bus Topics | `aws_sns_topic` |
| **Event Stream** | Apache Kafka | Kinesis | Cloud Pub/Sub (streaming) | Event Hubs | `aws_kinesis_stream` |
| **Object Storage** | MinIO | S3 | Cloud Storage (GCS) | Blob Storage | `aws_s3_bucket` |
| **Search Index** | Elasticsearch | OpenSearch | Elastic Cloud on GCP | Azure Cognitive Search | `aws_opensearch_domain` |
| **WAF** | ModSecurity | WAFv2 | Cloud Armor | Azure WAF | `aws_wafv2_web_acl` |
| **Firewall** | iptables, nftables | Network Firewall / SG | VPC Firewall Rules | Azure Firewall / NSG | `aws_security_group` |
| **DNS** | BIND, CoreDNS | Route 53 | Cloud DNS | Azure DNS | `aws_route53_zone` |
| **NAT Gateway** | Linux NAT (iptables) | NAT Gateway | Cloud NAT | NAT Gateway | `aws_nat_gateway` |
| **VPN Gateway** | WireGuard, strongSwan | VPN Gateway | Cloud VPN | VPN Gateway | `aws_vpn_gateway` |
| **Service Mesh** | Istio, Linkerd, Envoy | App Mesh | Traffic Director / Anthos | Open Service Mesh | `aws_appmesh_mesh` |
| **Secrets Manager** | Vault | Secrets Manager | Secret Manager | Key Vault | `aws_secretsmanager_secret` |
| **Tracing** | Jaeger, Zipkin | X-Ray | Cloud Trace | Application Insights | `aws_xray_sampling_rule` |
| **Logging** | ELK Stack, Loki | CloudWatch Logs | Cloud Logging | Azure Monitor Logs | `aws_cloudwatch_log_group` |
| **Metrics** | Prometheus, Graphite | CloudWatch Metrics | Cloud Monitoring | Azure Monitor Metrics | `aws_cloudwatch_metric_alarm` |
| **Data Warehouse** | ClickHouse | Redshift | BigQuery | Synapse Analytics | `aws_redshift_cluster` |
| **Graph DB** | Neo4j | Neptune | N/A (use Neo4j on GCE) | Cosmos DB (Gremlin API) | `aws_neptune_cluster` |
| **Time-series DB** | InfluxDB, TimescaleDB | Timestream | Bigtable (time-series) | ADX (Data Explorer) | `aws_timestreamwrite_database` |

### 4.1 Compute Nodes

| Simulator Node | AWS Resource | Terraform Resource | Key Terraform Parameters | Simulator Config That Maps |
|---|---|---|---|---|
| **API Server / Microservice** (`microservice`) | ECS Fargate Service | `aws_ecs_service` + `aws_ecs_task_definition` | `desired_count`, `cpu`, `memory`, container definition, health check | `workers` → `desired_count`, `vCPU`/`ram` → `cpu`/`memory` |
| **Serverless Fn** (`serverless-function`) | AWS Lambda | `aws_lambda_function` | `memory_size`, `timeout`, `reserved_concurrent_executions`, `runtime`, handler | `capacity` → `reserved_concurrent_executions`, `processing.timeout` → `timeout` |
| **Job Worker** (`batch-worker`) | AWS Batch Compute Environment | `aws_batch_job_definition` + `aws_batch_compute_environment` | `vcpus`, `memory`, `type` (FARGATE/EC2), retry strategy | `workers` → parallel job slots, `processing.timeout` → `timeout` |
| **Auth Service** (`auth-service`) | ECS Fargate + Cognito User Pool | `aws_ecs_service` + `aws_cognito_user_pool` | Same as microservice + Cognito pool settings | Same as microservice |
| **Search Service** (`search-service`) | ECS Fargate + OpenSearch | `aws_ecs_service` + `aws_opensearch_domain` | Search domain instance type, EBS volume | `workers` → `desired_count` |
| **Sidecar Proxy** (`sidecar`) | App Mesh Virtual Node (Envoy sidecar) | `aws_appmesh_virtual_node` with listener | `listener`, `backend`, `service_discovery` | Routing config → listener/backend mapping |

#### ECS Fargate Task Definition Example (for microservice)

```hcl
resource "aws_ecs_task_definition" "api_server" {
  family                   = "api-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024    # 1 vCPU — derived from simulator vCPU seed
  memory                   = 2048    # 2 GB — derived from simulator ram seed
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "api-server"
    image     = "ECR_IMAGE_URI"         # placeholder — user fills in
    cpu       = 1024
    memory    = 2048
    essential = true

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/api-server"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "api_server" {
  name            = "api-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_server.arn
  desired_count   = 4    # From simulator workers count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.api_server.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_server.arn
    container_name   = "api-server"
    container_port   = 8080
  }
}
```

#### Lambda Function Example (for serverless-function)

```hcl
resource "aws_lambda_function" "serverless_fn" {
  function_name = "serverless-fn"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"       # placeholder
  runtime       = "nodejs20.x"          # placeholder
  timeout       = 30                    # From simulator processing.timeout (ms → s)
  memory_size   = 512                   # From simulator ram seed

  reserved_concurrent_executions = 100  # From simulator capacity

  environment {
    variables = {
      STAGE = "production"
    }
  }

  tracing_config {
    mode = "Active"                     # X-Ray tracing enabled
  }
}
```

### 4.2 Network & Routing Nodes

| Simulator Node | AWS Resource | Terraform Resource | Key Parameters | Config Mapping |
|---|---|---|---|---|
| **L4 Load Balancer** (`load-balancer-l4`) | Network Load Balancer (NLB) | `aws_lb` (type=`"network"`) | `internal`, `subnets`, `enable_cross_zone_load_balancing` | `routingStrategy: 'round-robin'` → NLB default |
| **L7 Load Balancer** (`load-balancer-l7`) | Application Load Balancer (ALB) | `aws_lb` (type=`"application"`) | `internal`, `subnets`, `security_groups`, `idle_timeout` | `routingStrategy` → listener rules |
| **API Gateway** (`api-gateway`) | API Gateway v2 (HTTP) | `aws_apigatewayv2_api` | `protocol_type`, `cors_configuration`, routes, integrations | Edge conditions → route keys |
| **CDN** (`cdn`) | CloudFront Distribution | `aws_cloudfront_distribution` | `origin`, `default_cache_behavior`, `price_class`, `viewer_certificate` | Cache trait → cache policy TTL |
| **Ingress Controller** (`ingress-controller`) | ALB Ingress Controller on EKS | `aws_lb` + `kubernetes_ingress_v1` | ALB annotations, path-based routing rules | Similar to L7 LB |
| **Reverse Proxy** (`reverse-proxy`) | Nginx on ECS/EC2 | `aws_ecs_service` with Nginx image | Nginx config, upstream servers | Routing strategy → upstream config |
| **NAT Gateway** (`nat-gateway`) | NAT Gateway | `aws_nat_gateway` | `allocation_id` (Elastic IP), `subnet_id` | Minimal config — just needs EIP and subnet |
| **VPN Gateway** (`vpn-gateway`) | VPN Gateway | `aws_vpn_gateway` + `aws_vpn_connection` | `type`, `amazon_side_asn`, customer gateway | No direct sim config mapping |
| **Service Mesh** (`service-mesh`) | AWS App Mesh | `aws_appmesh_mesh` + virtual services/routers/nodes | Mesh name, virtual services, route config | Routing strategy → route action weights |
| **Edge Router** (`edge-router`) | Transit Gateway | `aws_ec2_transit_gateway` | `auto_accept_shared_attachments`, route tables | Routing config |
| **WAF** (`waf`) | AWS WAFv2 | `aws_wafv2_web_acl` | `rule` blocks (rate limiting, IP sets, managed rules), `default_action` | `blockRate` → rate-based rule threshold |
| **Firewall Rule** (`firewall`) | AWS Network Firewall | `aws_networkfirewall_firewall` + `aws_networkfirewall_rule_group` | Stateful/stateless rules, protocol, source/dest CIDR | `droppedPackets` → drop action rules |
| **DNS Server** (`internal-dns`) | Route 53 Hosted Zone | `aws_route53_zone` + `aws_route53_record` | `type` (A, CNAME, ALIAS), `ttl`, routing policy | Routing → weighted/latency/failover policy |

#### ALB Example (for L7 Load Balancer)

```hcl
resource "aws_lb" "l7_lb" {
  name               = "l7-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  idle_timeout               = 60

  tags = {
    Name = "L7 Load Balancer"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.l7_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server.arn
  }
}

resource "aws_lb_target_group" "api_server" {
  name        = "api-server-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"    # For Fargate

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
}
```

#### NLB Example (for L4 Load Balancer)

```hcl
resource "aws_lb" "l4_lb" {
  name               = "l4-load-balancer"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.l4_lb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp_backend.arn
  }
}

resource "aws_lb_target_group" "tcp_backend" {
  name        = "tcp-backend-tg"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 10
    port                = "traffic-port"
    protocol            = "TCP"
    unhealthy_threshold = 3
  }
}
```

### 4.3 Storage & Data Nodes

| Simulator Node | AWS Resource | Terraform Resource | Key Parameters | Config Mapping |
|---|---|---|---|---|
| **Primary DB** (`relational-db`) | RDS PostgreSQL/MySQL | `aws_db_instance` | `instance_class`, `allocated_storage`, `engine`, `multi_az`, `max_connections` | `workers` → `max_connections` (approx), `processing.distribution` → expected query latency |
| **Read Replica** (`relational-db`, template `read-replica`) | RDS Read Replica | `aws_db_instance` with `replicate_source_db` | `instance_class`, source DB identifier | Same as primary, plus replication config |
| **Redis Cache** (`in-memory-cache`) | ElastiCache Redis | `aws_elasticache_replication_group` | `node_type`, `num_cache_clusters`, `parameter_group_name` | `workers` → `num_cache_clusters` (node count in cluster) |
| **NoSQL DB** (`nosql-db`) | DynamoDB | `aws_dynamodb_table` | `billing_mode`, `read_capacity`, `write_capacity`, `hash_key`, `range_key` | `throughput` → provisioned capacity units |
| **Object Storage** (`object-storage`) | S3 Bucket | `aws_s3_bucket` + policies | `versioning`, `lifecycle_rule`, `server_side_encryption_configuration` | Minimal — S3 has no "workers" concept |
| **Search Index** (`search-index`) | OpenSearch Service | `aws_opensearch_domain` | `instance_type`, `instance_count`, `ebs_options`, `zone_awareness_config` | `workers` → `instance_count`, `capacity` → EBS volume size |
| **Time-series DB** (`time-series-db`) | Amazon Timestream | `aws_timestreamwrite_database` + `aws_timestreamwrite_table` | `magnetic_store_retention`, `memory_store_retention` | Limited config mapping — Timestream is serverless |
| **Graph DB** (`graph-db`) | Amazon Neptune | `aws_neptune_cluster` + `aws_neptune_cluster_instance` | `instance_class`, `cluster_size`, `engine_version` | `workers` → cluster instance count |
| **Vector DB** (`vector-db`) | OpenSearch with k-NN plugin | `aws_opensearch_domain` with k-NN | Same as OpenSearch + k-NN settings | Same as search index |
| **Data Warehouse** (`data-warehouse`) | Amazon Redshift | `aws_redshift_cluster` | `node_type`, `number_of_nodes`, `cluster_type` | `workers` → `number_of_nodes` |
| **KV Store** (`kv-store`) | DynamoDB or ElastiCache | `aws_dynamodb_table` (on-demand) | `billing_mode = "PAY_PER_REQUEST"`, key schema | `throughput` → approximate capacity |

#### RDS Example (for Primary DB)

```hcl
resource "aws_db_instance" "primary" {
  identifier     = "primary-db"
  engine         = "postgres"
  engine_version = "16.1"
  instance_class = "db.r6g.large"    # Derived from simulator vCPU/ram seed
  
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "appdb"
  username = "dbadmin"              # placeholder
  password = "CHANGE_ME"            # placeholder — should use Secrets Manager

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  skip_final_snapshot     = true

  performance_insights_enabled = true

  parameter_group_name = aws_db_parameter_group.custom.name

  tags = {
    Name = "Primary DB"
  }
}

resource "aws_db_parameter_group" "custom" {
  family = "postgres16"
  name   = "custom-pg16"

  parameter {
    name  = "max_connections"
    value = "200"               # Derived from simulator workers/capacity
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }
}
```

#### ElastiCache Redis Example (for Redis Cache)

```hcl
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "redis-cache"
  description          = "Redis Cache cluster"
  
  node_type            = "cache.r6g.large"   # Derived from simulator seeds
  num_cache_clusters   = 2                    # Derived from simulator workers
  
  engine               = "redis"
  engine_version       = "7.0"
  port                 = 6379
  parameter_group_name = "default.redis7"
  
  automatic_failover_enabled = true
  multi_az_enabled           = true
  
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = {
    Name = "Redis Cache"
  }
}
```

### 4.4 Messaging & Streaming Nodes

| Simulator Node | AWS Resource | Terraform Resource | Key Parameters | Config Mapping |
|---|---|---|---|---|
| **Message Queue** (`queue`) | SQS | `aws_sqs_queue` | `visibility_timeout_seconds`, `message_retention_seconds`, `delay_seconds`, `max_message_size`, DLQ config | `processing.timeout` → `visibility_timeout_seconds`, `capacity` → conceptual max messages |
| **Event Broker / Kafka** (`message-broker`) | Amazon MSK | `aws_msk_cluster` | `broker_node_group_info` (instance type, count, storage), `kafka_version` | `workers` → broker count, `throughput` → instance sizing |
| **Pub/Sub** (`pub-sub`) | SNS | `aws_sns_topic` + `aws_sns_topic_subscription` | `protocol`, `endpoint`, `filter_policy` | Fan-out routing → subscription list |
| **Event Stream** (`stream`) | Kinesis Data Streams | `aws_kinesis_stream` | `shard_count`, `retention_period`, `stream_mode_details` | `workers` → `shard_count`, `throughput` → provisioned throughput |
| **Event Bus** (not yet in palette) | EventBridge | `aws_cloudwatch_event_bus` + `aws_cloudwatch_event_rule` | Rules, targets, event patterns | Conditional routing → event pattern matching |

#### SQS Example (for Message Queue)

```hcl
resource "aws_sqs_queue" "message_queue" {
  name                       = "message-queue"
  visibility_timeout_seconds = 30      # From simulator processing.timeout
  message_retention_seconds  = 345600  # 4 days
  max_message_size           = 262144  # 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 20      # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "Message Queue"
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "message-queue-dlq"
  message_retention_seconds = 1209600  # 14 days
}
```

#### MSK Example (for Kafka Broker)

```hcl
resource "aws_msk_cluster" "kafka" {
  cluster_name           = "event-broker"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3            # Derived from simulator workers

  broker_node_group_info {
    instance_type   = "kafka.m5.large"  # Derived from simulator throughput seed
    client_subnets  = var.private_subnet_ids
    security_groups = [aws_security_group.kafka.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100               # GB
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka.name
      }
    }
  }

  tags = {
    Name = "Event Broker (Kafka)"
  }
}
```

### 4.5 Security Nodes

| Simulator Node | AWS Resource | Terraform Resource | Key Parameters | Config Mapping |
|---|---|---|---|---|
| **WAF** (`waf`) | AWS WAFv2 Web ACL | `aws_wafv2_web_acl` | `rule` blocks, `default_action`, `scope` (REGIONAL/CLOUDFRONT) | `blockRate` → rate-based rule limit |
| **Firewall Rule** (`firewall`) | Network Firewall / Security Group | `aws_security_group` + `aws_security_group_rule` | `ingress`/`egress` rules, CIDR blocks, protocol, port range | `droppedPackets` → deny rules |
| **Security Group** (`firewall`, template `security-group`) | Security Group | `aws_security_group` | Same as firewall | Same |
| **Secrets Manager** (`secrets-manager`) | AWS Secrets Manager | `aws_secretsmanager_secret` | `recovery_window_in_days`, rotation config | Minimal mapping |

#### WAF Example

```hcl
resource "aws_wafv2_web_acl" "main" {
  name        = "web-app-firewall"
  scope       = "REGIONAL"
  description = "WAF for application protection"

  default_action {
    allow {}
  }

  # Rate-based rule — derived from simulator blockRate
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000    # requests per 5 min — derived from blockRate
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-rule"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rules — common protections
  rule {
    name     = "aws-managed-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf-main"
    sampled_requests_enabled   = true
  }
}
```

### 4.6 Observability Nodes

| Simulator Node | AWS Resource | Terraform Resource | Key Parameters | Config Mapping |
|---|---|---|---|---|
| **Metrics Collector** (`metrics-store`) | CloudWatch Agent / Prometheus | `aws_cloudwatch_metric_alarm` + agent config | Namespace, metric name, dimensions | Sim metrics → CW metric dimensions |
| **Log Collector** (`centralized-logging`) | CloudWatch Logs | `aws_cloudwatch_log_group` | `retention_in_days`, `kms_key_id` | Log retention config |
| **Tracing Collector** (`distributed-tracing`) | AWS X-Ray | `aws_xray_sampling_rule` | `fixed_rate`, `reservoir_size`, `service_name` | `traceSampleRate` → `fixed_rate` |
| **Alerting Engine** (`alerting-hook`) | CloudWatch Alarms + SNS | `aws_cloudwatch_metric_alarm` + `aws_sns_topic` | `metric_name`, `threshold`, `comparison_operator`, `alarm_actions` | SLO config → alarm thresholds |
| **Health Check Manager** | Route 53 Health Check | `aws_route53_health_check` | `fqdn`, `port`, `type`, `failure_threshold`, `request_interval` | Health prober config → check parameters |

### 4.7 Composite / Infrastructure Nodes

| Simulator Node | AWS Resource | Terraform Resource | Notes |
|---|---|---|---|
| **VPC Region** (composite) | VPC | `aws_vpc` + `aws_subnet` + `aws_internet_gateway` + `aws_route_table` | Container for all nodes in a region |
| **Availability Zone** (composite) | Availability Zone (logical) | Subnet placement in different AZs | Affects subnet assignment |
| **Subnet** (composite) | Subnet | `aws_subnet` | Public vs private determines routing |

---

## 5. Edge-to-Cloud Networking Mapping

### 5.1 How Edges Translate

Simulator edges represent network connections between nodes. In AWS, these don't have a single Terraform resource — instead they're the *emergent result* of security groups, target groups, VPC routing, and service configurations.

| Simulator Edge Property | AWS Equivalent | How It's Configured |
|---|---|---|
| `protocol: 'https'` | HTTPS listener on ALB, TLS termination | `aws_lb_listener` protocol, certificate |
| `protocol: 'tcp'` | TCP listener on NLB, direct TCP connection | `aws_lb_listener` protocol = "TCP" |
| `protocol: 'grpc'` | gRPC target group on ALB | `aws_lb_target_group` protocol_version = "GRPC" |
| `protocol: 'amqp'` | SQS/MQ connection, SDK client config | Not a Terraform resource — it's application code |
| `protocol: 'kafka'` | MSK bootstrap broker connection | `aws_msk_cluster` bootstrap brokers output |
| `mode: 'synchronous'` | Request-response (HTTP, gRPC call) | Default for most connections |
| `mode: 'asynchronous'` | SQS/SNS/Kinesis publish | Producer SDK config |
| `mode: 'streaming'` | WebSocket, Kinesis consumer | ALB WebSocket support / KCL config |
| `latency.pathType: 'same-dc'` | Same AZ subnets | Both nodes in same `aws_subnet` |
| `latency.pathType: 'cross-zone'` | Different AZ subnets | Nodes in different AZs, same region |
| `latency.pathType: 'cross-region'` | VPC Peering / Transit Gateway cross-region | `aws_vpc_peering_connection` or Transit Gateway |
| `latency.pathType: 'internet'` | Through IGW + public internet | Public subnet + IGW route |
| `bandwidth` | Not directly configurable in AWS networking | AWS provides baseline bandwidth per instance type |
| `maxConcurrentRequests` | Connection pool / target group attributes | `aws_lb_target_group` `stickiness`, connection draining |
| `packetLossRate` | N/A (AWS internal network has near-zero loss) | Would only apply to internet-facing edges |
| `errorRate` | N/A (network errors are rare) | Application-level error rates |
| `weight` | Target group weight in ALB | `aws_lb_listener_rule` with weighted action |
| `condition` | ALB listener rule conditions | `aws_lb_listener_rule` with path/host conditions |

### 5.2 Security Group Generation from Edges

Each edge in the topology implies a security group rule:

```hcl
# Edge: L7 LB → API Server (protocol: https, port: 8080)
resource "aws_security_group_rule" "alb_to_api_server" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.api_server.id
  description              = "Allow traffic from L7 LB to API Server"
}
```

The exporter should automatically generate one security group per node and one rule per edge, with ports derived from the protocol:

| Protocol | Default Port | Security Group Rule |
|---|---|---|
| `https` | 443 (listener) / 8080 (target) | TCP 443 inbound on LB, TCP 8080 inbound on target |
| `grpc` | 443 (listener) / 50051 (target) | TCP 443 inbound on LB, TCP 50051 inbound on target |
| `tcp` | Varies | TCP on specified port |
| `amqp` | 5672 | TCP 5672 inbound on broker |
| `kafka` | 9092 (plaintext) / 9094 (TLS) | TCP 9094 inbound on MSK |
| `websocket` | 443 | TCP 443 inbound (ALB handles WS upgrade) |

---

## 6. Simulator Config → Real Config Translation

### 6.1 The Config Translation Table

This is the core mapping that makes the simulator faithful to real-world infrastructure.

| Simulator Config Property | Unit | Real-World AWS Equivalent | Translation Logic |
|---|---|---|---|
| `queue.workers` | count | ECS `desired_count`, Lambda `reserved_concurrent_executions`, RDS `max_connections`, Redis `num_cache_clusters` | Direct mapping. Workers = concurrency capacity. |
| `queue.capacity` | count | ECS + ALB queuing (not directly configurable), SQS `max_receive_count`, Lambda concurrency overflow to SQS | Capacity overflow → queue depth before rejection. AWS uses auto-scaling instead of fixed capacity. |
| `queue.discipline` | enum | ALB: round-robin (FIFO equivalent), SQS: FIFO queue vs standard queue, priority queues via separate queues | `'fifo'` → SQS FIFO queue or standard ALB. `'priority'` → multiple SQS queues with priority polling. |
| `processing.distribution` | statistical dist | Average response time. Not configurable — emergent from instance type + code + data. | The simulator's distribution IS the prediction. AWS doesn't let you set "mean response time." |
| `processing.timeout` | ms | ALB `idle_timeout`, Lambda `timeout`, API Gateway `timeout_milliseconds`, SQS `visibility_timeout_seconds` | Direct mapping in seconds. |
| `nodeErrorRate` | probability [0,1] | Not directly configurable. Emergent from code quality + infra reliability. | Used for Chaos Engineering injection (AWS FIS). |
| `securityPolicy.blockRate` | probability [0,1] | WAFv2 `rate_based_statement.limit` | `blockRate` → approximate RPS threshold. E.g., 1.2% blockRate at 10K RPS ≈ 120 req/5min rate limit. |
| `securityPolicy.droppedPackets` | probability [0,1] | Network Firewall drop rules, Security Group deny rules | Maps to deny rule coverage. Not a probability in AWS — it's binary (allow/deny). |
| `slo.latencyP99` | ms | CloudWatch Alarm threshold | Direct: alarm when p99 > target. |
| `slo.availabilityTarget` | fraction [0,1] | CloudWatch Alarm + error budget calculation | `availabilityTarget: 0.999` → alarm when error rate > 0.1%. |
| `resources.cpu` | vCPUs | ECS `cpu`, Lambda `memory_size` (proportional), EC2 `instance_type` | Direct for ECS. Lambda CPU scales with memory. |
| `resources.memory` | MB | ECS `memory`, Lambda `memory_size`, RDS `instance_class` | Direct for ECS/Lambda. RDS uses instance class tiers. |
| `resources.replicas` | count | ECS `desired_count`, ASG `desired_capacity` | Direct mapping. |

### 6.2 Instance Type Derivation

The simulator uses `vCPU` and `ram` seed values. These need to map to actual AWS instance types:

```typescript
function deriveInstanceType(vCPU: number, ramGB: number, nodeType: string): string {
  // ECS Fargate — discrete CPU/memory combos
  if (nodeType === 'microservice' || nodeType === 'auth-service') {
    const fargateConfigs = [
      { cpu: 256, memory: [512, 1024, 2048] },
      { cpu: 512, memory: [1024, 2048, 3072, 4096] },
      { cpu: 1024, memory: [2048, 3072, 4096, 5120, 6144, 7168, 8192] },
      { cpu: 2048, memory: [4096, 5120, 6144, 7168, 8192, ...range(9216, 16384, 1024)] },
      { cpu: 4096, memory: range(8192, 30720, 1024) },
    ]
    // Find closest Fargate config...
    return `${closestCpu} CPU / ${closestMemory} MB`
  }
  
  // RDS — instance class tiers
  if (nodeType === 'relational-db') {
    if (ramGB <= 2) return 'db.t3.small'
    if (ramGB <= 4) return 'db.t3.medium'
    if (ramGB <= 8) return 'db.r6g.large'
    if (ramGB <= 16) return 'db.r6g.xlarge'
    return 'db.r6g.2xlarge'
  }
  
  // ElastiCache — node types
  if (nodeType === 'in-memory-cache') {
    if (ramGB <= 3) return 'cache.t3.medium'
    if (ramGB <= 6) return 'cache.r6g.large'
    if (ramGB <= 13) return 'cache.r6g.xlarge'
    return 'cache.r6g.2xlarge'
  }
}
```

### 6.3 What DOESN'T Map

Some simulator config is simulation-specific and has no AWS equivalent:

| Simulator Concept | Why It Doesn't Map | What to Show Instead |
|---|---|---|
| `processing.distribution` (the statistical distribution itself) | AWS services don't let you configure response time distributions | Show as a comment: `# Expected p99 latency: ~12ms based on simulation` |
| `packetLossRate` on internal edges | AWS VPC network has near-zero packet loss | Omit from Terraform, note in comment |
| `errorRate` on edges | Not a configurable parameter — emergent from service health | Map to chaos engineering fault injection via AWS FIS |
| `queue.discipline: 'lifo'` | AWS services are FIFO (SQS FIFO) or unordered (SQS Standard) | Map LIFO to a comment: `# Note: LIFO discipline used in simulation — SQS doesn't support LIFO` |
| Exact throughput numbers | Throughput is emergent from instance sizing + code + network | Use as sizing guidance in comments |

---

## 7. Telemetry Fidelity: Simulator Output → Real Observability

### 7.1 Current Simulator Output Format

The simulator currently produces `SimulationOutput` with these fields:

```typescript
interface SimulationOutput {
  summary: {
    totalRequests, successfulRequests, failedRequests, 
    rejectedRequests, timedOutRequests,
    throughput, errorRate,
    latency: { p50, p90, p95, p99, min, max, mean }
  }
  perNode: Record<string, {
    totalArrived, totalProcessed, totalRejected, totalTimedOut,
    avgQueueLength, avgServiceTime, avgQueueWait, avgTimeInSystem,
    peakQueueLength, utilization, throughput, errorRate, availability,
    latencyP50, latencyP95, latencyP99
  }>
  timeSeries: Array<{
    timestamp: number,
    node: Record<string, { queueLength, activeWorkers, utilization, status }>
  }>
  traces: Array<{
    requestId, totalLatency, status,
    spans: Array<{ nodeId, start, end, queueWait, serviceTime, edgeLatency }>
  }>
  sloBreaches: Array<{ nodeId, metric, target, actual, severity }>
  littlesLawCheck: Array<{ nodeId, observedL, expectedL, error }>
}
```

**The data is there. The format is wrong.** The simulator already tracks everything needed — it just doesn't output in standards-compliant formats.

### 7.2 OpenTelemetry Trace Format

The simulator's `RequestTrace` should be exportable as OTEL-compatible spans. Here's what a real OTEL span looks like:

```json
{
  "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
  "spanId": "051581bf3cb55c13",
  "parentSpanId": "ab1f0e229e0a10d6",
  "operationName": "api-server.handleRequest",
  "startTime": "2026-06-16T10:30:00.000Z",
  "duration": 12345,
  "status": { "code": "OK" },
  "kind": "SERVER",
  "attributes": {
    "service.name": "api-server",
    "service.version": "1.0.0",
    "http.method": "GET",
    "http.url": "/api/users",
    "http.status_code": 200,
    "http.response_content_length": 1024,
    "net.peer.name": "l7-load-balancer",
    "net.peer.port": 8080
  },
  "events": [
    { "name": "queue.enter", "timestamp": "...", "attributes": { "queue.depth": 3 } },
    { "name": "processing.start", "timestamp": "..." },
    { "name": "processing.complete", "timestamp": "..." }
  ],
  "resource": {
    "service.name": "api-server",
    "service.namespace": "ns-simulator",
    "deployment.environment": "simulation"
  }
}
```

#### Mapping: Simulator Trace → OTEL Span

| Simulator Field | OTEL Span Field | Derivation |
|---|---|---|
| `trace.requestId` | `traceId` | Hash to 32-char hex string |
| `span.nodeId` | `spanId` | Hash `requestId + nodeId + hopIndex` to 16-char hex |
| Previous span's `spanId` | `parentSpanId` | Chain spans by hop order |
| `span.nodeId` | `attributes["service.name"]` | Direct |
| `request.type` | `attributes["http.method"]` | Map: "GET" → GET, "POST" → POST, "default" → GET |
| `span.start` (ms offset) | `startTime` | Add to simulation base timestamp |
| `span.end - span.start` | `duration` (microseconds) | Convert ms → µs |
| `trace.status` | `status.code` | `"success"` → OK, `"timeout"` → DEADLINE_EXCEEDED, `"rejected"` → RESOURCE_EXHAUSTED |
| `span.queueWait` | `events[0]` ("queue.enter") | Timestamp from span.start |
| `span.serviceTime` | `events[1..2]` ("processing.start/complete") | Timestamps derived from queue wait + service time |
| `span.edgeLatency` | Separate CLIENT span | Edge latency becomes the parent client span duration |

#### Span Kind Mapping

| Node Profile | OTEL Span Kind | Reason |
|---|---|---|
| `source` | `CLIENT` | Initiates requests |
| `router` (LB, Gateway) | `SERVER` + `CLIENT` | Receives then forwards |
| `compute-service` | `SERVER` | Processes and may call downstream |
| `datastore` | `SERVER` | Terminal processing |
| `broker` | `PRODUCER`/`CONSUMER` | Async messaging |
| Edge traversal | `CLIENT` (on source side) | Network hop |

### 7.3 CloudWatch Metrics Format

Each simulator per-node metric should map to a CloudWatch metric with proper namespace and dimensions:

```json
{
  "Namespace": "NSSimulator/ECS",
  "MetricName": "CPUUtilization",
  "Dimensions": [
    { "Name": "ServiceName", "Value": "api-server" },
    { "Name": "ClusterName", "Value": "production" }
  ],
  "Timestamp": "2026-06-16T10:30:00Z",
  "Value": 72.5,
  "Unit": "Percent"
}
```

#### Per-Node Metric Mapping to CloudWatch

| Simulator Metric | CloudWatch Namespace | Metric Name | Dimensions | Unit | Notes |
|---|---|---|---|---|---|
| `utilization` | `AWS/ECS` | `CPUUtilization` | ServiceName, ClusterName | Percent | `utilization * 100` |
| `throughput` | `AWS/ApplicationELB` | `RequestCount` | LoadBalancer, TargetGroup | Count | Per period |
| `latencyP50` | `AWS/ApplicationELB` | `TargetResponseTime` | LoadBalancer | Seconds | p50 statistic |
| `latencyP99` | `AWS/ApplicationELB` | `TargetResponseTime` | LoadBalancer | Seconds | p99 statistic |
| `avgQueueLength` | `AWS/SQS` | `ApproximateNumberOfMessagesVisible` | QueueName | Count | For queue nodes |
| `errorRate` | `AWS/ApplicationELB` | `HTTPCode_Target_5XX_Count` | LoadBalancer | Count | `errorRate * throughput` |
| `totalRejected` | `AWS/ApplicationELB` | `RejectedConnectionCount` | LoadBalancer | Count | Or `HTTPCode_ELB_503_Count` |
| Cache hit ratio | `AWS/ElastiCache` | `CacheHitRate` | ReplicationGroupId | Percent | When CacheTrait is implemented |
| `peakQueueLength` | `AWS/SQS` | `ApproximateNumberOfMessagesVisible` | QueueName | Count | Max statistic |
| `avgServiceTime` | Custom | `ProcessingDuration` | ServiceName | Milliseconds | Custom metric via CloudWatch agent |

#### Service-Specific CloudWatch Metrics

**For ECS/Fargate nodes (microservice, auth-service, etc.):**
```
AWS/ECS/CPUUtilization          — from utilization
AWS/ECS/MemoryUtilization       — derived from ram utilization  
AWS/ECS/RunningTaskCount        — from workers (active count)
```

**For ALB nodes (L7 LB):**
```
AWS/ApplicationELB/RequestCount           — from throughput * period
AWS/ApplicationELB/TargetResponseTime     — from latency percentiles
AWS/ApplicationELB/HTTPCode_Target_2XX    — from successfulRequests
AWS/ApplicationELB/HTTPCode_Target_5XX    — from failedRequests
AWS/ApplicationELB/HealthyHostCount       — from workers - failed workers
AWS/ApplicationELB/UnHealthyHostCount     — from failed workers count
AWS/ApplicationELB/ActiveConnectionCount  — from queue length + active workers
```

**For NLB nodes (L4 LB):**
```
AWS/NetworkELB/ActiveFlowCount       — from active connections
AWS/NetworkELB/ProcessedBytes        — from throughput * avg request size
AWS/NetworkELB/TCP_Target_Reset      — from error count
```

**For RDS nodes (relational-db):**
```
AWS/RDS/DatabaseConnections      — from activeWorkers
AWS/RDS/ReadLatency              — from avgServiceTime (for read replicas)
AWS/RDS/WriteLatency             — from avgServiceTime (for primary)
AWS/RDS/CPUUtilization           — from utilization
AWS/RDS/FreeableMemory           — derived from ram - (utilization * ram)
AWS/RDS/ReadIOPS                 — derived from throughput (reads)
AWS/RDS/WriteIOPS                — derived from throughput (writes)
```

**For ElastiCache Redis nodes (in-memory-cache):**
```
AWS/ElastiCache/CacheHits        — from cache trait hit count (when implemented)
AWS/ElastiCache/CacheMisses      — from cache trait miss count
AWS/ElastiCache/CurrConnections  — from activeWorkers
AWS/ElastiCache/Evictions        — from rejections (capacity exceeded)
AWS/ElastiCache/ReplicationLag   — from edge latency to read replica
```

**For Lambda nodes (serverless-function):**
```
AWS/Lambda/Invocations           — from totalArrived
AWS/Lambda/Duration              — from avgServiceTime
AWS/Lambda/Errors                — from totalRejected + totalTimedOut
AWS/Lambda/Throttles             — from rejections (capacity exceeded)
AWS/Lambda/ConcurrentExecutions  — from activeWorkers
```

**For SQS nodes (queue):**
```
AWS/SQS/ApproximateNumberOfMessagesVisible   — from queueLength
AWS/SQS/ApproximateAgeOfOldestMessage        — from max queue wait time
AWS/SQS/NumberOfMessagesSent                  — from totalArrived
AWS/SQS/NumberOfMessagesReceived              — from totalProcessed
AWS/SQS/NumberOfMessagesDeleted               — from totalProcessed (successful)
```

**For CloudFront nodes (cdn):**
```
AWS/CloudFront/Requests          — from totalArrived
AWS/CloudFront/BytesDownloaded   — from throughput * avg response size
AWS/CloudFront/4xxErrorRate      — from client errors / total
AWS/CloudFront/5xxErrorRate      — from server errors / total
AWS/CloudFront/CacheHitRate      — from cache trait (when implemented)
```

### 7.4 Prometheus Exposition Format

For students learning Prometheus/Grafana monitoring, the simulator should be able to output metrics in Prometheus exposition format:

```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{service="api-server",method="GET",status="200"} 8450
http_requests_total{service="api-server",method="GET",status="500"} 127

# HELP http_request_duration_seconds HTTP request latency
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{service="api-server",le="0.005"} 1000
http_request_duration_seconds_bucket{service="api-server",le="0.01"} 4500
http_request_duration_seconds_bucket{service="api-server",le="0.025"} 6800
http_request_duration_seconds_bucket{service="api-server",le="0.05"} 7900
http_request_duration_seconds_bucket{service="api-server",le="0.1"} 8300
http_request_duration_seconds_bucket{service="api-server",le="0.25"} 8420
http_request_duration_seconds_bucket{service="api-server",le="0.5"} 8440
http_request_duration_seconds_bucket{service="api-server",le="1"} 8450
http_request_duration_seconds_bucket{service="api-server",le="+Inf"} 8450
http_request_duration_seconds_sum{service="api-server"} 84.5
http_request_duration_seconds_count{service="api-server"} 8450

# HELP node_queue_length Current queue depth
# TYPE node_queue_length gauge
node_queue_length{service="api-server"} 12
node_queue_length{service="primary-db"} 5
node_queue_length{service="redis-cache"} 0

# HELP node_utilization Current CPU utilization ratio
# TYPE node_utilization gauge
node_utilization{service="api-server"} 0.72
node_utilization{service="primary-db"} 0.45

# HELP node_active_workers Current number of active processing workers
# TYPE node_active_workers gauge
node_active_workers{service="api-server"} 3
```

### 7.5 Structured Log Format

Real microservices emit structured JSON logs. The simulator should optionally output logs that match:

```json
{
  "timestamp": "2026-06-16T10:30:00.123Z",
  "level": "INFO",
  "service": "api-server",
  "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
  "spanId": "051581bf3cb55c13",
  "message": "Request processed successfully",
  "request": {
    "id": "req-001",
    "method": "GET",
    "path": "/api/users",
    "sizeBytes": 1024
  },
  "response": {
    "status": 200,
    "durationMs": 12.3
  },
  "queue": {
    "waitMs": 2.1,
    "depthOnArrival": 3
  }
}
```

For errors:
```json
{
  "timestamp": "2026-06-16T10:30:01.456Z",
  "level": "ERROR",
  "service": "api-server",
  "traceId": "abc123def456...",
  "spanId": "789012345678",
  "message": "Request rejected: capacity_exceeded",
  "error": {
    "type": "capacity_exceeded",
    "queueLength": 100,
    "capacity": 100,
    "activeWorkers": 4
  }
}
```

For ALB access logs:
```
https 2026-06-16T10:30:00.123456Z app/l7-lb/abc123 192.168.1.100:443 10.0.1.50:8080 0.001 0.012 -1 200 200 1024 2048 "GET /api/users HTTP/2.0" "Mozilla/5.0" ECDHE-RSA-AES128-GCM-SHA256 TLSv1.3 arn:aws:elasticloadbalancing:... "Root=1-5b8aa5a2-d2c872e8321cf37308d69df2"
```

### 7.6 SLI/SLO Dashboard Metrics

The simulator already computes SLO breaches. These should export in a format compatible with SLO dashboards:

```json
{
  "slo": {
    "name": "api-server-latency",
    "objective": { "target": 0.999, "metric": "latencyP99", "threshold_ms": 50 },
    "window": "30d",
    "current": {
      "sli_value": 0.9975,
      "is_compliant": false,
      "error_budget_remaining": -0.0015,
      "error_budget_consumed_pct": 125.0,
      "burn_rate_1h": 2.5,
      "burn_rate_6h": 1.8
    }
  }
}
```

---

## 8. Terraform HCL Export Specification

### 8.1 Export Output Structure

When a user clicks "Export as Terraform", the simulator generates a set of `.tf` files:

```
terraform-export/
├── main.tf              # Provider config, backend
├── variables.tf         # Input variables (region, VPC ID, etc.)
├── vpc.tf               # VPC, subnets, IGW, NAT GW (if VPC composites exist)
├── security_groups.tf   # One SG per node, rules from edges
├── compute.tf           # ECS cluster, task definitions, services
├── networking.tf        # ALBs, NLBs, target groups, listeners
├── storage.tf           # RDS, ElastiCache, DynamoDB, S3
├── messaging.tf         # SQS, SNS, MSK, Kinesis
├── security.tf          # WAF, Network Firewall
├── observability.tf     # CloudWatch, X-Ray, alarms
├── iam.tf               # IAM roles and policies
├── outputs.tf           # Endpoint URLs, ARNs
└── terraform.tfvars     # Default values
```

### 8.2 The Export Pipeline

```
TopologyJSON
    │
    ├── nodes[] ──→ For each node:
    │                 1. Look up componentType → AWS resource mapping
    │                 2. Translate simulator config → Terraform parameters
    │                 3. Generate HCL resource block
    │                 4. Generate IAM role if needed
    │                 5. Generate CloudWatch alarms from SLO config
    │
    ├── edges[] ──→ For each edge:
    │                 1. Generate security group rule (source SG → target SG, port from protocol)
    │                 2. If target is LB: generate target group + listener rule
    │                 3. If target is queue/broker: generate SDK connection config comment
    │
    └── composites[] ──→ For each VPC/AZ/Subnet:
                          1. Generate aws_vpc + aws_subnet + aws_route_table
                          2. Place nodes in appropriate subnets
```

### 8.3 Minimal Viable Export (Phase 1)

For the first version, generate:
1. **VPC** with public/private subnets in 2 AZs
2. **Security groups** for each node (auto-generated from edges)
3. **ECS Cluster** + task definitions + services (for compute nodes)
4. **ALB/NLB** (for load balancer nodes)
5. **RDS instance** (for relational-db nodes)
6. **ElastiCache cluster** (for in-memory-cache nodes)
7. **SQS queues** (for queue nodes)
8. **CloudWatch alarms** (from SLO config)

Defer to later phases:
- MSK/Kafka (complex setup)
- API Gateway (many config options)
- CloudFront (origin config complexity)
- App Mesh (service mesh config)
- Lambda (requires code artifact)

### 8.4 Generated Provider and Backend

```hcl
# main.tf — generated by NS-Simulator
# This Terraform configuration was exported from a simulator topology.
# Review and customize before applying to a real AWS account.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "ns-simulator/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Source      = "ns-simulator"
    }
  }
}
```

### 8.5 Variables Template

```hcl
# variables.tf

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "ns-simulator-export"  # From topology.name
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "development"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Container image URIs — user must fill these in
variable "container_images" {
  description = "Map of service name to container image URI"
  type        = map(string)
  default     = {}
}
```

### 8.6 Placeholders and User Action Items

The exported Terraform will have placeholders that the user must fill in:

```hcl
# ⚠️ USER ACTION REQUIRED: Set the container image URI for this service.
# Replace "PLACEHOLDER" with your ECR image URI, e.g.:
#   123456789012.dkr.ecr.us-east-1.amazonaws.com/api-server:latest
image = lookup(var.container_images, "api-server", "PLACEHOLDER")
```

The export should also generate a `README.md` with:
1. Prerequisites (AWS account, Terraform installed, AWS CLI configured)
2. List of user action items (container images, database passwords, SSL certificates)
3. Deployment steps (`terraform init`, `plan`, `apply`)
4. Cost estimate (based on resource types selected)
5. Cleanup steps (`terraform destroy`)

---

## 9. Multi-Cloud Export Architecture

### 9.1 Why Terraform HCL (and Not Alternatives)

| Option | Pros | Cons | Decision |
|---|---|---|---|
| **Terraform HCL** | Industry standard. Declarative. **Multi-cloud out of the box** (AWS, GCP, Azure use different providers, same HCL syntax). Huge community. Students will encounter it everywhere. | HCL syntax is specific to Terraform. Requires Terraform CLI. | **Primary export format** |
| **Pulumi (TypeScript)** | Multi-cloud. Real programming language. Same TS as our codebase. | Smaller community than Terraform. Requires Pulumi CLI. | **Future secondary** — good for TS-native teams |
| **AWS CDK / GCP CDK / Azure Bicep** | Vendor-native, type-safe, higher-level. | Vendor-locked. Each cloud has different IaC tooling. | Not recommended for multi-cloud teaching |
| **CloudFormation / Deployment Manager / ARM Templates** | Native to each cloud. No extra tools. | Verbose. Non-portable. | Not recommended |
| **Docker Compose** | Simple for local dev. | Not cloud infrastructure — just container orchestration. | Separate export for local dev |
| **Kubernetes Manifests (YAML)** | Cloud-agnostic if targeting K8s. Runs on EKS/GKE/AKS. | Only covers compute, not managed services (RDS, SQS, etc.). | Separate K8s export |

### 9.2 Multi-Cloud Terraform Provider Architecture

The same topology can export to different cloud providers. The exporter uses a provider abstraction:

```typescript
type CloudProvider = 'aws' | 'gcp' | 'azure'

interface TerraformExportResult {
  provider: CloudProvider
  files: Map<string, string>   // filename → HCL content
  warnings: string[]           // issues found during export
  userActions: string[]        // things the user must do before applying
  estimatedMonthlyCost: {
    min: number
    max: number
    currency: 'USD'
    breakdown: Record<string, number>
  }
}

function exportToTerraform(
  topology: TopologyJSON, 
  provider: CloudProvider
): TerraformExportResult {
  const mapper = providerMappers[provider]  // AWS, GCP, or Azure resource mapper
  // 1. Analyze topology
  // 2. mapper.generateResources(nodes, edges)
  // 3. mapper.generateNetworking(edges)
  // 4. mapper.generateIAM()
  // 5. Estimate costs (provider-specific pricing)
}
```

#### Provider Blocks

**AWS:**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = var.region   # default: "us-east-1"
}
```

**GCP:**
```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
provider "google" {
  project = var.project_id
  region  = var.region    # default: "us-central1"
}
```

**Azure:**
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

### 9.3 GCP Terraform Examples

#### Cloud Run (microservice equivalent)

```hcl
resource "google_cloud_run_v2_service" "api_server" {
  name     = "api-server"
  location = var.region

  template {
    containers {
      image = "gcr.io/PROJECT/api-server:latest"  # placeholder

      resources {
        limits = {
          cpu    = "1000m"      # 1 vCPU — from sim resources.cpu
          memory = "2Gi"        # 2 GB — from sim resources.memory
        }
      }

      ports {
        container_port = 8080
      }

      startup_probe {
        http_get { path = "/health" }
        initial_delay_seconds = 10
      }
    }

    scaling {
      min_instance_count = 2    # From sim resources.replicas
      max_instance_count = 10   # From sim resources.maxReplicas
    }
  }
}
```

#### Cloud SQL (database equivalent)

```hcl
resource "google_sql_database_instance" "primary" {
  name             = "primary-db"
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = "db-custom-2-8192"   # 2 vCPU, 8GB RAM — from sim seeds
    availability_type = "REGIONAL"           # Multi-AZ equivalent
    disk_type         = "PD_SSD"
    disk_size         = 100

    database_flags {
      name  = "max_connections"
      value = "200"                          # From sim queue.workers
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
  }
}
```

#### Global HTTP(S) Load Balancer (L7 LB equivalent)

```hcl
resource "google_compute_global_forwarding_rule" "https" {
  name       = "l7-lb-forwarding-rule"
  target     = google_compute_target_https_proxy.default.id
  port_range = "443"
}

resource "google_compute_target_https_proxy" "default" {
  name             = "l7-lb-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

resource "google_compute_url_map" "default" {
  name            = "l7-lb-url-map"
  default_service = google_compute_backend_service.api.id
}

resource "google_compute_backend_service" "api" {
  name                  = "api-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30               # From sim processing.timeout

  health_checks = [google_compute_health_check.api.id]

  backend {
    group           = google_compute_region_network_endpoint_group.api.id
    balancing_mode  = "RATE"
    max_rate        = 1000                 # From sim throughput seed
  }
}
```

#### Memorystore Redis (cache equivalent)

```hcl
resource "google_redis_instance" "cache" {
  name           = "redis-cache"
  tier           = "STANDARD_HA"           # High availability (like Multi-AZ)
  memory_size_gb = 4                       # From sim resources.memory
  region         = var.region

  authorized_network = google_compute_network.vpc.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  redis_configs = {
    "maxmemory-policy" = "allkeys-lru"
  }

  redis_version = "REDIS_7_0"
}
```

### 9.4 Azure Terraform Examples

#### Container Apps (microservice equivalent)

```hcl
resource "azurerm_container_app" "api_server" {
  name                         = "api-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  template {
    container {
      name   = "api-server"
      image  = "myacr.azurecr.io/api-server:latest"  # placeholder
      cpu    = 1.0       # From sim resources.cpu
      memory = "2Gi"     # From sim resources.memory
    }

    min_replicas = 2     # From sim resources.replicas
    max_replicas = 10    # From sim resources.maxReplicas
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
```

#### Azure Database for PostgreSQL Flexible Server

```hcl
resource "azurerm_postgresql_flexible_server" "primary" {
  name                   = "primary-db"
  resource_group_name    = azurerm_resource_group.main.name
  location               = var.location
  version                = "16"
  sku_name               = "GP_Standard_D2ds_v4"   # 2 vCPU, 8GB — from sim seeds
  storage_mb             = 102400
  zone                   = "1"
  high_availability {
    mode = "ZoneRedundant"      # Multi-AZ equivalent
  }
  
  administrator_login    = "dbadmin"
  administrator_password = var.db_password
}

resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.primary.id
  value     = "200"                                # From sim queue.workers
}
```

#### Application Gateway (L7 LB equivalent)

```hcl
resource "azurerm_application_gateway" "l7_lb" {
  name                = "l7-load-balancer"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  backend_address_pool {
    name = "api-server-pool"
  }

  backend_http_settings {
    name                  = "api-http-settings"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 30    # From sim processing.timeout (seconds)
    cookie_based_affinity = "Disabled"

    probe_name = "api-health-probe"
  }

  probe {
    name                = "api-health-probe"
    protocol            = "Http"
    path                = "/health"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "api-cert"
  }

  request_routing_rule {
    name                       = "api-routing"
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "api-server-pool"
    backend_http_settings_name = "api-http-settings"
    priority                   = 100
  }
}
```

### 9.5 The Export Button and Download

In the UI, add an "Export" dropdown in the toolbar:

```
[File v] [Edit v] [Simulate ▶] [Export v]
                                 ├── Export as JSON (current)
                                 ├── Export as Terraform (AWS)
                                 ├── Export as Terraform (GCP)
                                 ├── Export as Terraform (Azure)
                                 ├── Export as Docker Compose (future)
                                 └── Export Telemetry (OTEL/Prometheus)
```

"Export as Terraform" should:
1. Ask the user which cloud provider (AWS / GCP / Azure)
2. Validate the topology (check for unsupported nodes, missing edges)
3. Show a preview dialog with the file list, warnings, and cost estimate
4. Generate a ZIP file containing all `.tf` files
5. Download the ZIP

### 9.6 Cost Estimation (Multi-Cloud)

| Resource Type | AWS (~monthly) | GCP (~monthly) | Azure (~monthly) |
|---|---|---|---|
| Container (1 vCPU, 2GB) | ~$30 (Fargate) | ~$25 (Cloud Run) | ~$28 (Container Apps) |
| L7 Load Balancer | ~$20 + $5/LCU (ALB) | ~$18 + $8/rule (Global LB) | ~$20 + per-rule (App GW) |
| L4 Load Balancer | ~$20 (NLB) | ~$18 (Regional LB) | ~$18 (Azure LB) |
| Relational DB (2 vCPU, 8GB, Multi-AZ) | ~$350 (RDS) | ~$300 (Cloud SQL) | ~$320 (PostgreSQL Flex) |
| Redis Cache (6GB, HA) | ~$250 (ElastiCache) | ~$200 (Memorystore) | ~$230 (Azure Cache) |
| Message Queue | ~$0.40/M msg (SQS) | ~$0.40/M msg (Pub/Sub) | ~$0.05/M ops (Service Bus) |
| Serverless Function | ~$10 (Lambda) | ~$8 (Cloud Functions) | ~$10 (Azure Functions) |
| CDN | ~$50 (CloudFront) | ~$45 (Cloud CDN) | ~$50 (Azure CDN) |
| Kafka (3 brokers) | ~$500 (MSK) | ~$400 (Confluent) | ~$450 (Event Hubs) |

> **Note:** These are rough estimates for educational purposes. Real costs depend heavily on traffic patterns, data transfer, and reserved instance commitments.

---

## 10. Implementation Roadmap

### Phase 0: Real-World Config Fidelity (Foundation — Do First)

| Task | Effort | Impact |
|---|---|---|
| Add real technology name to each palette template (e.g., `technology: 'nginx'` for L7 LB) | Low | Students see what the node actually is |
| Fix edge default latencies (current `latencyMu=2.3` gives ~14ms same-DC — should be ~1ms, see Section 3.6) | Low | Massive accuracy improvement |
| Fix Redis `workers` seed (currently 4, should be 1 — Redis is single-threaded, see Section 2.2) | Low | Correct a factual error |
| Add network physics to edge latency: propagation delay + serialization + protocol overhead (Section 3) | Medium | Edges behave like real networks |
| Add per-path-type edge defaults with correct latencies, packet loss, bandwidth (Section 3.6) | Low | Accurate defaults |

### Phase 1: Telemetry Export (Low Effort, High Teaching Value)

| Task | Effort | Files | Impact |
|---|---|---|---|
| Add OTEL trace exporter — convert `RequestTrace[]` to OTLP JSON with semantic conventions | Medium | New `src/engine/export/otelExporter.ts` | Students see real trace format |
| Add Prometheus metrics exporter — convert `PerNodeMetrics` to exposition format with histograms | Low | New `src/engine/export/prometheusExporter.ts` | Students see real metrics format |
| Add structured JSON log exporter — convert `DebugEvent[]` to JSON logs with traceId correlation | Low | New `src/engine/export/logExporter.ts` | Students see real log format |
| Add "Export Telemetry" button to ResultsTray | Low | Modify `ResultsTray.tsx`, add `FileService` call | User can download telemetry |

### Phase 2: Terraform AWS Export (Medium Effort, High Value)

| Task | Effort | Files | Impact |
|---|---|---|---|
| Create provider-agnostic resource mapping registry | Medium | New `src/engine/export/terraform/resourceMapping.ts` | Core mapping logic — works for all providers |
| Create HCL code generator | Medium | New `src/engine/export/terraform/hclGenerator.ts` | Generates `.tf` content |
| Implement AWS compute export (ECS + Lambda) | Medium | New `src/engine/export/terraform/aws/compute.ts` | Most common resource type |
| Implement AWS networking export (ALB + NLB + target groups) | Medium | New `src/engine/export/terraform/aws/networking.ts` | Critical for LB nodes |
| Implement AWS storage export (RDS + ElastiCache + DynamoDB) | Medium | New `src/engine/export/terraform/aws/storage.ts` | Database nodes |
| Implement security group generation from edges | Low | New `src/engine/export/terraform/aws/securityGroups.ts` | Auto-generated from topology |
| Implement VPC generation from composites | Low | New `src/engine/export/terraform/aws/vpc.ts` | Infrastructure base |
| Add "Export as Terraform (AWS)" button + ZIP download | Low | Modify toolbar, add `FileService.saveZip()` | User-facing export |

### Phase 3: Terraform GCP + Azure Export (Extends Phase 2)

| Task | Effort | Impact |
|---|---|---|
| Implement GCP compute export (Cloud Run + Cloud Functions) | Medium | Second cloud provider |
| Implement GCP networking export (Global LB + Cloud SQL + Memorystore) | Medium | Core GCP services |
| Implement GCP VPC generation | Low | GCP networking base |
| Implement Azure compute export (Container Apps + Azure Functions) | Medium | Third cloud provider |
| Implement Azure networking export (App Gateway + PostgreSQL Flex) | Medium | Core Azure services |
| Cloud provider picker in export UI | Low | User selects AWS/GCP/Azure |

### Phase 4: Real Technology Config Panel

| Task | Effort | Impact |
|---|---|---|
| Add real config fields to node properties panel — show Nginx/HAProxy/Postgres config alongside sim params | Medium | Students see real technology configs |
| Add instance type derivation from vCPU/RAM seeds (per cloud provider) | Low | Auto-suggest appropriate instance types |
| Add cost estimation to export (per cloud provider) | Medium | Help students understand cloud costs |
| Generate monitoring config (CloudWatch alarms / GCP alerts / Azure Monitor) from SLO config | Low | Direct SLO → alerting mapping |

### Phase 5: Advanced Export Formats (Future)

| Task | Effort | Impact |
|---|---|---|
| Docker Compose export for local dev | Medium | Students can run a local version with real containers |
| Kubernetes manifests export (YAML) | Medium | Cloud-agnostic deployment to EKS/GKE/AKS |
| Pulumi TypeScript export | Medium | Alternative IaC for TS-native teams |
| Ansible playbook export (for on-prem) | Medium | On-premises deployment option |

### Relationship to Other Specifications

This document builds on:
- **Node Behaviour Specification** (Sections 1-4): Defines what each node should *do* in the simulator. This document defines what each node maps to in the real world.
- **Edge Specification** (Section 5): Defines edge properties and constraints. This document maps those to real network physics and cloud networking config.
- **Architecture Redesign** (Section 6-7): The trait system. Trait behaviour affects what observability data is produced (e.g., CacheTrait → cache hit/miss metrics).

---

*This document defines the bridge between the simulator and the real world. Every node should feel like a real technology, every edge should behave like a real network link, every metric should look like real observability data, and every topology should be exportable as deployable infrastructure on any major cloud provider.*

*This document defines the bridge between the simulator and the real world. Every node should feel like a real AWS resource, every metric should look like a real CloudWatch datapoint, and every topology should be one `terraform apply` away from running infrastructure.*

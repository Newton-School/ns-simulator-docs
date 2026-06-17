# NS-Simulator Course Integration Plan

> **Purpose:** Planning and strategy document for using the NS-Simulator as a teaching and learning tool across three Rishihood University courses.
>
> **Target Audience:** Instructors, curriculum designers, and the product/engineering team building the simulator.
>
> **Date:** June 2026

---

## Table of Contents

1. [Course Overview](#1-course-overview)
2. [Where the NS-Simulator Can Be Used](#2-where-the-ns-simulator-can-be-used)
3. [How the NS-Simulator Helps in Teaching and Learning](#3-how-the-ns-simulator-helps-in-teaching-and-learning)
4. [Example Teaching Use Cases](#4-example-teaching-use-cases)
5. [Assignment and Question Ideas](#5-assignment-and-question-ideas)
6. [Missing Functionality and Required Future Work](#6-missing-functionality-and-required-future-work)

---

## 1. Course Overview

| Attribute | System Design & Software Engineering (SESD) | Full Stack DevOps Engineering (FSDE) | Computer Networks (CN) |
|---|---|---|---|
| **Code** | CSA234 | -- | -- |
| **Semester** | 7 (Odd, 2026) | Even, 2025-26 | 5 (AY 26-27) |
| **Major** | B.Tech CS & AI, CS & DS | B.Tech CS & AI, CS & DS | B.Tech CS & AI |
| **Credits** | 4 | 4 | 4 |
| **LTP** | 2-0-4 | 2-0-4 | 2-1-2 |
| **Core Focus** | OOP, UML, Design Patterns, SOLID, SDLC, Testing, Scaling | DevOps, CI/CD, Docker, K8s, Terraform, Monitoring | OSI/TCP-IP, HTTP/DNS, TCP/UDP, Load Balancers, Routing, VPC, Security |

---

## 2. Where the NS-Simulator Can Be Used

### 2.1 Topic-to-Simulator Mapping: Computer Networks (CN)

This is the **highest-alignment course**. The simulator directly models many of the networking and infrastructure concepts taught here.

| Week | Course Topic | Simulator Component / Feature | Alignment |
|---|---|---|---|
| 1-2 | Internet architecture, network devices, topologies, load balancers | Canvas topology builder; L4/L7 load balancer nodes; edge-router; CDN; topology visualization | **Direct** |
| 1-2 | Delay, loss, throughput measurement | Edge latency distributions; packet loss rate; bandwidth config; time-series metrics | **Direct** |
| 3-4 | HTTP/HTTPS, DNS, CDNs, caching, client-server vs P2P | API Gateway, CDN node, DNS Resolver, edge protocols (https, grpc, tcp, udp, websocket) | **Direct** |
| 3-4 | Route 53 routing policies (simple, weighted, latency, failover, geolocation) | Routing strategies (round-robin, weighted, conditional routing via edge conditions) | **Partial** -- weighted and round-robin exist; latency-based, failover, and geolocation routing do not |
| 5-6 | Transport layer: TCP/UDP, multiplexing, TCP handshake, flow/congestion control | L4 Load Balancer node (TCP/UDP sublabel); protocol field on edges (tcp, udp); edge latency modeling | **Partial** -- protocol labels exist but no actual TCP handshake or flow control simulation |
| 5-6 | ALB (Layer 7, path/host routing) vs NLB (Layer 4, TCP/UDP) | Distinct `load-balancer-l4` and `load-balancer-l7` palette nodes with different processing characteristics (L4: 0.15ms mean, L7: 0.4ms mean) | **Direct** |
| 5-6 | Health checks, target groups, high availability with ALB + Auto Scaling | Health Check Manager node; scaling config (horizontal/vertical, thresholds, cooldown); SLO breach detection | **Partial** -- scaling config exists in types but auto-scaling runtime logic is not fully simulated |
| 7-8 | IP addressing, subnetting, NAT, DHCP, CIDR | VPC Region, Availability Zone, Subnet composite containers; NAT Gateway node | **Partial** -- visual containers exist but no IP address simulation or CIDR math |
| 9-10 | Routing algorithms (Dijkstra, Bellman-Ford, OSPF, RIP, BGP) | RoutingTable class with round-robin, weighted, and conditional routing; Edge Router node | **Partial** -- request-level routing exists but no network-layer routing protocol simulation |
| 9-10 | Firewalls, Security Groups, NACLs, TLS/SSL, WAF | WAF node (with blockRate), Firewall Rule node (with droppedPackets), Security Group node; security policy enforcement in engine | **Direct** |
| 11-12 | VPC Peering, Transit Gateway, CloudFront, physical layer | VPC Region / AZ / Subnet containers; VPN Gateway; CDN node; edge path types (same-rack, same-dc, cross-zone, cross-region, internet) | **Partial** |

### 2.2 Topic-to-Simulator Mapping: System Design & Software Engineering (SESD)

The simulator is a strong fit for the **later weeks** of this course, particularly around scaling, architecture, and system design thinking.

| Week | Course Topic | Simulator Component / Feature | Alignment |
|---|---|---|---|
| 1 | What is Software Engineering -- reliability, testability, maintainability | SLO config (latencyP99, availabilityTarget, errorBudget); SLO breach detection; reliability as an observable metric | **Conceptual** -- simulator demonstrates *why* reliability matters through observable failures |
| 3 | Scalability, Reliability, Observability -- how they shape design | Scaling config; utilization metrics; metrics-store, centralized-logging, distributed-tracing, alerting-hook nodes | **Direct** |
| 6 | Design Patterns -- Singleton, Factory | Not directly applicable (code-level patterns, not infrastructure) | **None** |
| 7 | Observer pattern, event-driven design, pub/sub fan-out | Pub/Sub node with broadcast routing; Message Broker (Kafka); Event Stream; async edge mode | **Direct** -- pub/sub fan-out and event-driven architecture are first-class simulator features |
| 8 | Strategy pattern -- pluggable behaviors | Routing strategies (round-robin, weighted, passthrough, broadcast) are a live example of the Strategy pattern applied to load balancer behavior | **Conceptual** |
| 12* | Scale from Zero to Millions of Users | Full topology builder; load balancers; caching (Redis Cache); database scaling (Read Replica, Shard Node, Partition Node); CDN; horizontal scaling config | **Direct** -- this is the simulator's core use case |
| 12* | Vertical vs horizontal scaling, bottleneck identification, load balancing basics | Time-series utilization/queue-length charts; per-node throughput and latency metrics; Little's Law verification | **Direct** |

### 2.3 Topic-to-Simulator Mapping: Full Stack DevOps Engineering (FSDE)

The simulator complements this course for **infrastructure visualization and monitoring concepts**, though the course's primary focus on CI/CD tooling is outside the simulator's scope.

| Week | Course Topic | Simulator Component / Feature | Alignment |
|---|---|---|---|
| 3 | Linux & Cloud Basics: EC2, ports, IPs, networking | API Server node; edge definitions with protocol and latency; VPC/Subnet containers | **Conceptual** -- demonstrates the *result* of what students configure on EC2 |
| 8 | AWS architecture: ECS, S3, CloudFront | CDN node; Object Storage node; container runtime concepts | **Partial** |
| 10 | Kubernetes: pods, deployments, services, ingress | Ingress Controller node; Service Mesh; microservice nodes with queue/processing config | **Partial** -- K8s concepts are represented as node types but no actual K8s orchestration |
| 12 | Monitoring: Grafana, Prometheus, Loki; health checks; alerting | Metrics Collector, Log Collector, Centralized Logging, Distributed Tracing, Alerting Engine, Health Check Manager nodes; time-series snapshots | **Direct** -- the observability pipeline is fully modeled |
| 12 | Automated health checks, notifications for failures | Health Check Manager node; node failure/recovery events; SLO breach detection | **Direct** |

---

## 3. How the NS-Simulator Helps in Teaching and Learning

### 3.1 Teaching Foundational Concepts From Scratch

The simulator can build understanding progressively, starting from the most rudimentary concepts:

#### What is a Server?

An instructor drops a single **"API Server"** node onto the canvas. The node visually shows:
- A label ("API Server") and sublabel ("Long-running Process")
- A configuration panel where students can see **workers** (how many requests the server can process concurrently), **queue capacity** (how many waiting requests it can hold), and **processing distribution** (how long each request takes)

This immediately grounds the abstract idea of "a server" in concrete, observable terms: a server is something that **receives requests**, **queues them if busy**, and **processes them over time**.

#### How is a Server Configured?

Students open the properties panel and adjust:
- **Workers:** 1 -> 4 (the server can now handle 4 requests concurrently)
- **Queue capacity:** 10 -> 100 (the server can now buffer more traffic)
- **Processing time distribution:** exponential with lambda=0.1 (mean 10ms) -> lambda=0.01 (mean 100ms, simulating a slower database call)
- **Timeout:** 5000ms (requests that take longer than 5 seconds are terminated)

Students run the simulation and see how each knob changes throughput, latency percentiles, and rejection rates.

#### How Does a Server Handle Requests?

The simulator uses the **G/G/c/K queueing model**:
1. A request arrives at the node
2. If a worker is free, it begins processing immediately
3. If all workers are busy but the queue has room, the request waits (FIFO, LIFO, priority, or WFQ)
4. If the queue is full, the request is **rejected**
5. Processing time is sampled from a configurable distribution (exponential, normal, uniform, log-normal, etc.)
6. If processing exceeds the timeout, the request is **timed out**

In **debug mode**, students can trace a single request through this lifecycle step-by-step, seeing the exact events: `request-arrival` -> `processing-complete` -> `request-forwarded` -> `request-complete`.

#### How Does Request Flow Change Based on Configuration?

Students build a topology: **Client -> Load Balancer -> [Server A, Server B] -> Database**

They experiment:
- Change the load balancer from round-robin to weighted routing (80/20 split) and observe uneven utilization
- Increase the client's RPS from 100 to 1000 and watch queue lengths grow and rejection rates spike
- Add a Redis Cache between the servers and the database to reduce DB load
- Kill Server A (node failure event) and watch all traffic route to Server B, which becomes saturated

Each change produces immediately visible differences in the time-series charts and per-node metrics.

### 3.2 Instructor Demonstration Capabilities

| Demonstration Goal | How the Simulator Supports It |
|---|---|
| Show how a single overloaded server behaves | Place one server with low workers/capacity, send high RPS, observe queue saturation and rejection rates in real time |
| Compare L4 vs L7 load balancing | Place both node types in parallel topologies; L4 processes at 0.15ms (TCP-level forwarding) while L7 processes at 0.4ms (HTTP header inspection). Show the latency-throughput tradeoff |
| Demonstrate pub/sub fan-out | Connect a Message Broker to 3 downstream services via async edges; all three receive every message (broadcast routing) |
| Show how a WAF protects a system | Insert a WAF node with 5% block rate; observe that ~5% of requests are rejected with reason `security_blocked` before they reach the application |
| Illustrate why caching matters | Build a topology without cache (Client -> Server -> DB). Measure DB latency. Add Redis Cache between Server and DB with 0.1ms mean processing time vs DB's 8ms. Show the dramatic latency reduction |
| Visualize request tracing | Enable debug mode for a single request; trace its path through Client -> DNS -> CDN -> Load Balancer -> Server -> DB, seeing latency at each hop |
| Demonstrate SLO monitoring | Set SLO targets on nodes (e.g., p99 latency < 50ms, availability > 99.9%), then increase load until SLO breaches are detected |
| Show effect of network path type | Configure edges with different path types (same-rack: ~0.1ms, cross-region: ~50ms, internet: ~100ms) and observe how placement decisions affect end-to-end latency |

### 3.3 Visual Learning Advantages

The simulator provides several visual feedback mechanisms that make abstract concepts tangible:

1. **Canvas topology view** -- students see the architecture as a graph of connected components, building spatial intuition about system structure
2. **Animated edges** -- request flow is visually animated along edges, showing traffic direction and volume
3. **Real-time metrics** -- per-node utilization, queue length, and status (idle/busy/saturated/failed) update during simulation
4. **Time-series charts** -- line charts showing how metrics evolve over the simulation duration, making patterns like "queue buildup under load" visually obvious
5. **Debug event stream** -- step-by-step event log showing exactly what happened to each request (arrival, queuing, processing, forwarding, completion/rejection/timeout)
6. **VPC/AZ/Subnet grouping** -- composite container nodes visually communicate network isolation and hierarchical infrastructure organization

---

## 4. Example Teaching Use Cases

### 4.1 Teaching Scenario: "Your First Server"

**Course:** CN Week 1-2, or SESD Week 1

**Setup:**
1. Instructor drops a **Client App** (source node) and an **API Server** onto the canvas
2. Connects them with a single edge (protocol: https, latency: constant 5ms)
3. Configures the Client to send 10 RPS with a constant workload pattern
4. Configures the Server with 2 workers, capacity 20, exponential processing (mean 50ms), timeout 5000ms

**Demonstration flow:**
1. Run the simulation. Show the metrics: ~10 req/s throughput, ~55ms mean latency, 0 rejections
2. Increase RPS to 50. Queue length grows, latency increases. Still 0 rejections because capacity is sufficient
3. Increase RPS to 200. Queue fills up. Rejections begin. Students see *why* servers need to be sized for their traffic
4. Increase workers from 2 to 8. Rejections drop to zero. Students see horizontal scaling in action

**Learning outcome:** Students understand that a server has finite processing capacity, and that the relationship between arrival rate, processing speed, and concurrency determines whether requests succeed or fail.

### 4.2 Teaching Scenario: "L4 vs L7 Load Balancers"

**Course:** CN Week 5-6

**Setup:**
1. Build two parallel topologies:
   - **Path A:** Client -> L4 Load Balancer -> [Server 1, Server 2]
   - **Path B:** Client -> L7 Load Balancer -> [Server 3, Server 4]
2. Both load balancers use round-robin routing
3. Both sets of servers have identical configurations
4. Same workload (500 RPS constant) sent to both

**Demonstration flow:**
1. Run the simulation. Compare metrics:
   - L4 LB adds ~0.15ms processing overhead per request (TCP-level forwarding, no header inspection)
   - L7 LB adds ~0.4ms processing overhead (HTTP header parsing, path evaluation)
2. Now add **conditional routing** on the L7 path: requests with `type === "GET"` go to Server 3, `type !== "GET"` go to Server 4
3. Show that L7 can route by request content, while L4 cannot -- it only sees TCP/UDP packets

**Key discussion points:**
- L4 is faster but content-blind
- L7 is slower but can make intelligent routing decisions (path-based, header-based, host-based)
- AWS NLB = L4, AWS ALB = L7

**Learning outcome:** Students can articulate the tradeoff between L4 (speed, simplicity) and L7 (intelligence, flexibility) load balancing, and know when to use each.

### 4.3 Teaching Scenario: "What Happens When a Server Fails?"

**Course:** CN Week 5-6 (high availability), SESD Week 12 (reliability)

**Setup:**
1. Client -> Load Balancer (round-robin) -> [Server A, Server B, Server C] -> Database
2. 300 RPS constant workload
3. Set a 5% node error rate on Server B

**Demonstration flow:**
1. Run simulation. Show per-node metrics: Server B has ~5% error rate while A and C have 0%
2. Now set Server B's error rate to 100% (simulating a complete crash). Observe:
   - Load balancer still sends 1/3 of traffic to Server B (round-robin)
   - All those requests fail
   - Servers A and C handle the remaining 2/3, but now at higher utilization
3. Discussion: This is why we need **health checks** (add Health Check Manager node) and **circuit breakers** (resilience config)

**Learning outcome:** Students understand why redundancy alone is insufficient without health-aware routing, and why circuit breaker patterns exist.

### 4.4 Teaching Scenario: "Observability Pipeline"

**Course:** FSDE Week 12

**Setup:**
Build a complete observability pipeline alongside a simple application:
1. Client -> API Server -> Database (the application path)
2. API Server -> (async edge) -> Log Collector -> Centralized Logging (the logging path)
3. API Server -> (async edge) -> Metrics Collector -> Alerting Engine (the metrics path)
4. API Server -> (async edge) -> Tracing Collector (the tracing path)

**Demonstration flow:**
1. Show that all observability edges are **asynchronous** -- they don't block the main request path
2. Show that the observability nodes process independently and don't affect application latency
3. Increase the application RPS and observe how log/metrics volume grows proportionally
4. Discussion: This mirrors a real Prometheus + Loki + Jaeger setup. Grafana dashboards read from the Metrics Collector; alerting fires from Alerting Engine

**Learning outcome:** Students understand why observability is a separate pipeline, why it must be async (to avoid impacting application performance), and how logs, metrics, and traces flow through a system.

### 4.5 Teaching Scenario: "Designing for Scale -- Zero to Millions"

**Course:** SESD Week 12

**Progressive build-up:**

**Stage 1: Single server**
- Client -> Server -> Database
- 100 RPS. Works fine.

**Stage 2: Server becomes a bottleneck**
- Increase to 1000 RPS. Server saturates. Add a load balancer and 3 server replicas.

**Stage 3: Database becomes a bottleneck**
- All 3 servers hit the same DB. DB utilization spikes. Add Redis Cache between servers and DB. Cache hit ratio reduces DB load.

**Stage 4: Read-heavy workload optimization**
- Add Read Replicas. Configure conditional routing: `request.type === "read"` goes to replicas, `request.type === "write"` goes to primary DB.

**Stage 5: Global scale**
- Add CDN in front for static content. Add DNS Resolver for name resolution. Place components inside VPC > Availability Zone > Subnet containers.

At each stage, students can compare before/after metrics and see exactly which bottleneck was resolved and which new one appeared.

**Learning outcome:** Students experience the iterative process of scaling a system, understanding that scaling is not a one-time decision but a series of bottleneck identifications and targeted solutions.

---

## 5. Assignment and Question Ideas

### 5.1 Beginner Level

#### Q1: "Configure and Observe" (CN Week 1-2)

> **Task:** You are given a pre-built topology: Client -> Server -> Database. The server has 1 worker and capacity 5. The client sends 50 RPS.
>
> 1. Run the simulation. Record the rejection rate and mean latency.
> 2. Increase workers to 4. Run again. What changed?
> 3. Increase queue capacity to 50. Run again. What changed?
> 4. Explain in 2-3 sentences why increasing workers reduced rejections but increasing capacity alone did not reduce latency.
>
> **How the simulator is used:** Students interact with the properties panel, run simulations, and read output metrics.
>
> **Learning outcome:** Understanding the difference between concurrency (workers) and buffering (queue capacity), and their distinct effects on latency vs rejection rate.

#### Q2: "Identify the Component" (CN Week 3-4)

> **Task:** Match each description to the correct simulator component:
>
> | Description | Component |
> |---|---|
> | Resolves domain names to IP addresses | ? |
> | Caches static content at the edge | ? |
> | Routes HTTP requests based on URL path | ? |
> | Forwards TCP packets without inspecting content | ? |
> | Blocks malicious HTTP requests | ? |
>
> Then, build a topology using all five components in the correct order for a web application request flow.
>
> **How the simulator is used:** Students drag components from the palette and connect them in the correct order.
>
> **Learning outcome:** Understanding what each network component does and where it sits in a request path.

#### Q3: "Read the Metrics" (SESD Week 1)

> **Task:** You are given a simulation output with the following per-node metrics:
>
> | Node | Throughput | Latency P50 | Latency P99 | Utilization | Rejections |
> |---|---|---|---|---|---|
> | API Server | 485 req/s | 12ms | 95ms | 92% | 312 |
> | Database | 485 req/s | 8ms | 45ms | 55% | 0 |
>
> 1. Which node is the bottleneck? How can you tell?
> 2. The API Server has a 92% utilization and 312 rejections. What does this suggest about its capacity?
> 3. Suggest two changes to reduce API Server rejections without changing the database.
>
> **How the simulator is used:** Students analyze simulation output (they may also re-run the scenario to validate their suggestions).
>
> **Learning outcome:** Reading and interpreting system metrics; identifying bottlenecks from utilization and rejection data.

### 5.2 Intermediate Level

#### Q4: "L4 vs L7 Comparison" (CN Week 5-6)

> **Task:** Build two separate topologies:
> - **Topology A:** Client -> L4 Load Balancer -> [Server 1, Server 2]
> - **Topology B:** Client -> L7 Load Balancer -> [Server 1, Server 2]
>
> Configure the client to send 1000 RPS with two request types: "api" (weight 0.7) and "static" (weight 0.3).
>
> 1. Run both topologies with round-robin routing. Compare the load balancer latency overhead.
> 2. On Topology B, add conditional routing: "static" requests go to Server 1, "api" requests go to Server 2. Is the traffic distribution more efficient? Why?
> 3. Can you achieve the same content-based routing on Topology A? Explain why or why not.
> 4. For each of the following use cases, recommend L4 or L7 and justify: (a) a gaming server using UDP, (b) an e-commerce API with /cart and /search endpoints, (c) a database connection pool.
>
> **How the simulator is used:** Students build topologies, configure routing, run simulations, and compare results.
>
> **Learning outcome:** Practical understanding of L4 vs L7 tradeoffs; ability to choose the right load balancer type for a given use case.

#### Q5: "Security Layer Design" (CN Week 9-10)

> **Task:** You have a 3-tier web application: Client -> Web Server -> App Server -> Database.
>
> 1. Add a WAF before the Web Server. Set blockRate to 3% (simulating bot traffic filtering). Run the simulation and note the reduction in downstream traffic.
> 2. Add a Security Group between the App Server and Database. Set droppedPackets to 0.5% (simulating network-level filtering).
> 3. Compare: How does WAF filtering (application-layer) differ from Security Group filtering (network-layer) in terms of where rejected requests are stopped?
> 4. If the WAF blocks a request, does the App Server ever see it? What about if the Security Group drops a packet?
>
> **How the simulator is used:** Students insert security nodes, configure policies, and trace requests through the security layers.
>
> **Learning outcome:** Understanding the difference between L7 security (WAF, application-aware) and L4 security (firewall/security group, packet-level), and where each operates in the request path.

#### Q6: "Event-Driven Architecture" (SESD Week 7)

> **Task:** Build an order processing system:
> - Client -> API Server -> Message Broker (Kafka) -> [Order Service, Notification Service, Analytics Service]
> - All edges from the Message Broker to downstream services should be **asynchronous**
>
> 1. Configure the Message Broker with broadcast routing. Run the simulation.
> 2. Verify that all three downstream services receive every message. What is the broadcast routing strategy doing?
> 3. Now change one downstream edge to **synchronous**. What happens to the request flow?
> 4. Explain in the context of the Observer pattern: who is the publisher, who are the subscribers, and what decoupling benefit does this architecture provide?
>
> **How the simulator is used:** Students build event-driven topologies, configure edge modes, and observe fan-out behavior.
>
> **Learning outcome:** Understanding pub/sub fan-out, async vs sync communication, and how event-driven architecture maps to the Observer pattern.

### 5.3 Advanced Level

#### Q7: "Diagnose the Bottleneck" (CN Week 5-6 / SESD Week 12)

> **Task:** You are given a pre-built topology with 8 nodes and a workload of 2000 RPS. The system has a p99 latency of 450ms and a 12% rejection rate. The SLO target is p99 < 100ms and availability > 99%.
>
> 1. Run the simulation and identify which node(s) are bottlenecks using the per-node metrics.
> 2. Examine the Little's Law verification results. Which nodes violate Little's Law and what does that indicate?
> 3. Check the conservation check. Are any nodes showing significant in-flight request imbalance?
> 4. Propose and implement exactly TWO configuration changes to bring the system within SLO. Justify each change.
> 5. Re-run and verify that SLO breaches are resolved.
>
> **How the simulator is used:** Students use advanced simulation output (Little's Law, conservation checks, SLO breaches) to diagnose and fix performance problems.
>
> **Learning outcome:** Systematic bottleneck analysis using queueing theory metrics; understanding that fixing one bottleneck may reveal another.

#### Q8: "Design a Highly Available Architecture" (CN Week 5-6, SESD Week 12)

> **Task:** Design a topology for a payment processing system that must achieve:
> - p99 latency < 200ms
> - Availability > 99.95%
> - Handle 5000 RPS
>
> Requirements:
> - Must include at least one load balancer
> - Must include a primary database and at least one read replica
> - Must include caching
> - Must include a WAF
> - Must use VPC/AZ/Subnet containers to show isolation
>
> Deliverables:
> 1. Screenshot of the topology
> 2. Simulation output showing SLO compliance
> 3. A 1-page write-up explaining your design decisions and tradeoffs
>
> **How the simulator is used:** Students design a complete architecture from scratch, tune configurations to meet SLOs, and defend their design.
>
> **Learning outcome:** End-to-end system design thinking; balancing performance, reliability, security, and cost.

#### Q9: "Scaling Under Traffic Spikes" (SESD Week 12)

> **Task:** You have a baseline topology handling 500 RPS. Configure the workload to use the **spike** pattern: after 30 seconds, traffic spikes to 5000 RPS for 10 seconds, then returns to 500 RPS.
>
> 1. Run the simulation with the current configuration. How does the system behave during the spike? Capture the time-series charts.
> 2. What is the maximum queue length during the spike? What percentage of requests are rejected?
> 3. Implement changes to survive the spike without rejections. You may add replicas, adjust queue sizes, add caching, or restructure the topology.
> 4. Re-run and compare the time-series charts before and after your changes.
> 5. Discuss: Is it always economical to provision for peak traffic? What alternatives exist in real-world systems?
>
> **How the simulator is used:** Students use spike workload patterns and time-series analysis to study transient behavior.
>
> **Learning outcome:** Understanding burst traffic handling; tradeoff between over-provisioning and graceful degradation.

#### Q10: "Build an Observability Pipeline" (FSDE Week 12)

> **Task:** Starting from a simple application topology (Client -> LB -> [Server A, Server B] -> DB), add a complete observability pipeline:
>
> 1. Add a **Metrics Collector** that receives data from both servers (async edges)
> 2. Add a **Log Collector** that aggregates logs from both servers (async edges)
> 3. Add a **Tracing Collector** for distributed traces (async edges)
> 4. Add a **Centralized Logging** service downstream from the Log Collector
> 5. Add an **Alerting Engine** downstream from the Metrics Collector
>
> Questions:
> 1. Why must all observability edges be asynchronous? What would happen if they were synchronous?
> 2. Run the simulation. Does the observability pipeline affect the application's p99 latency?
> 3. If the Log Collector becomes saturated (set low workers/capacity), does it affect application availability?
> 4. Map your simulator topology to real-world tools: which node corresponds to Prometheus? Grafana? Loki? Jaeger?
>
> **How the simulator is used:** Students build an observability pipeline, test that it's non-blocking, and map simulator abstractions to real tools.
>
> **Learning outcome:** Understanding observability architecture, the importance of async telemetry, and the mapping between abstract patterns and specific tools (Prometheus, Grafana, Loki, Jaeger).

---

## 6. Missing Functionality and Required Future Work

### 6.1 Feature Status Overview

| Feature | Status | Importance for Teaching |
|---|---|---|
| Visual topology builder with drag-and-drop | **Exists** | Core -- everything depends on this |
| 80+ component types (compute, network, storage, messaging, security, observability) | **Exists** | Core -- covers most infrastructure concepts |
| L4 and L7 load balancer distinction | **Exists** | High -- directly teaches CN Week 5-6 |
| Routing strategies (round-robin, weighted, conditional, broadcast) | **Exists** | High -- teaches routing concepts |
| Workload patterns (constant, poisson, bursty, spike, diurnal, sawtooth) | **Exists** | High -- enables traffic pattern experiments |
| Edge latency with statistical distributions | **Exists** | High -- models network delay realistically |
| Security nodes (WAF, Firewall, Security Group) with block/drop rates | **Exists** | High -- teaches security filtering |
| VPC / Availability Zone / Subnet containers | **Exists** | Medium -- visual only, no network simulation |
| Per-node metrics (throughput, latency percentiles, utilization, availability) | **Exists** | Core -- all analysis depends on this |
| SLO breach detection | **Exists** | High -- teaches SRE concepts |
| Little's Law verification | **Exists** | Medium -- advanced queueing theory validation |
| Conservation checks | **Exists** | Medium -- validates simulation correctness |
| Debug mode with request lifecycle tracing | **Exists** | High -- enables step-by-step request tracing |
| Time-series snapshots | **Exists** | High -- shows temporal behavior |
| Request tracing with spans | **Exists** | High -- teaches distributed tracing |
| Async/sync edge modes | **Exists** | High -- teaches async architecture |
| Node failure/recovery events | **Exists** | High -- teaches fault tolerance |
| Protocol labels (https, grpc, tcp, udp, websocket, amqp, kafka) | **Exists** | Medium -- correct labeling, but no protocol simulation |
| Edge path types (same-rack, same-dc, cross-zone, cross-region, internet) | **Exists** | Medium -- influences latency defaults |
| Topology save/load (JSON) | **Exists** | High -- enables assignment distribution |
| DNS routing policies (latency-based, failover, geolocation) | **Does not exist** | High (CN) |
| Auto-scaling runtime behavior | **Partially exists** | High (CN/SESD) |
| Health-check-aware load balancer routing | **Does not exist** | High (CN) |
| Cache hit/miss simulation | **Does not exist** | High (SESD/CN) |
| Database read/write split routing | **Partially exists** | Medium (SESD) |
| Circuit breaker runtime behavior | **Partially exists** | Medium (SESD) |
| Rate limiter runtime behavior | **Partially exists** | Medium (SESD/CN) |
| Pre-built scenario library / templates | **Does not exist** | High (all courses) |
| Guided walkthrough / tutorial mode | **Does not exist** | High (all courses) |
| Side-by-side topology comparison | **Does not exist** | Medium (CN) |
| Assignment mode with validation | **Does not exist** | High (all courses) |
| Exportable reports (PDF/Markdown) | **Does not exist** | Medium (all courses) |

### 6.2 Detailed Missing Feature Analysis

#### 6.2.1 DNS Routing Policies (latency-based, failover, geolocation)

**Current state:** The simulator has a DNS Resolver node and a RoutingTable that supports round-robin and weighted routing. Conditional routing exists but only supports `request.type` matching.

**What's needed:** The CN course covers Route 53 routing policies extensively (Week 3-4):
- **Simple routing** -- already supported (single edge)
- **Weighted routing** -- already supported (edge weights)
- **Latency-based routing** -- route to the target with lowest latency. Requires the routing table to consider edge latency when selecting a target
- **Failover routing** -- route to a secondary target when the primary is unhealthy. Requires health-aware routing
- **Geolocation routing** -- route based on geographic origin. Requires request metadata to carry a region/location field

**Why it matters:** Route 53 routing policies are a dedicated topic in the CN course. Students need to compare how different policies distribute traffic, which is currently only possible for weighted and round-robin.

**Recommendation:** Extend the `RoutingTable` to support a `routingStrategy` field on nodes with values `latency-based`, `failover`, and `geolocation` in addition to the existing `round-robin`, `weighted`, and `passthrough`.

#### 6.2.2 Auto-Scaling Runtime Behavior

**Current state:** The `ScalingConfig` interface exists in `types.ts` with fields for `type`, `metric`, `scaleUpThreshold`, `scaleDownThreshold`, `cooldown`, and `coldStartPenalty`. However, the `SimulationEngine` does not read or act on this config -- no replicas are added or removed during simulation.

**What's needed:** The CN course covers ALB + Auto Scaling (Week 5-6), and SESD covers horizontal/vertical scaling (Week 12). Students should be able to:
- Configure an auto-scaling policy on a node (e.g., "add replica when utilization > 80%, remove when < 30%")
- See replicas being added/removed during the simulation time-series
- Observe cold-start penalty when new replicas spin up
- See the cooldown period preventing thrashing

**Why it matters:** Auto-scaling is one of the most important cloud concepts. Without runtime simulation, students can only configure the policy but never observe its effect.

**Recommendation:** Implement a `ScalingController` that monitors per-node utilization during the simulation loop and dynamically adds/removes `GGcKNode` instances within the engine. The cold-start penalty distribution is already part of the config.

#### 6.2.3 Health-Check-Aware Load Balancer Routing

**Current state:** The Health Check Manager node exists as a palette component, and nodes can have `status: 'failed'` state. However, the `RoutingTable` does not check node health when resolving routes -- it routes to failed nodes equally.

**What's needed:** Load balancers should skip unhealthy targets. This is fundamental to the CN course's coverage of elastic load balancing and target groups (Week 5-6).

**Why it matters:** In the current simulator, demonstrating "what happens when a server fails" shows that the load balancer *continues* sending traffic to the dead server, which is unrealistic and confusing for students. Real ALBs/NLBs stop routing to unhealthy targets.

**Recommendation:** Add a `nodeHealth` lookup to the `RoutingTable`. When resolving routes, filter out edges whose target node has `status === 'failed'`. Allow an optional `healthCheckInterval` config on router nodes.

#### 6.2.4 Cache Hit/Miss Simulation

**Current state:** The Redis Cache and CDN nodes exist and process requests, but they process *all* requests identically. There is no concept of a cache hit (fast, doesn't propagate to origin) vs cache miss (slow, propagates to origin for data).

**What's needed:** Cache nodes should:
- Have a configurable **hit rate** (e.g., 85%)
- On a hit: respond immediately with minimal latency and not forward the request downstream
- On a miss: forward the request to the origin (database/backend) and cache the response

**Why it matters:** Caching is a central topic in both SESD (Week 12) and CN (CDN/caching in Week 3-4). Without hit/miss simulation, adding a cache node has no meaningful effect on downstream traffic, making caching demonstrations hollow.

**Recommendation:** Add a `cacheHitRate: number` (0.0-1.0) field to the node config. In the routing resolution, implement a probabilistic check: on hit, emit `request-complete` immediately; on miss, forward downstream. This is the single most impactful missing feature for teaching.

#### 6.2.5 Circuit Breaker Runtime Behavior

**Current state:** The `ResilienceConfig` interface includes a full circuit breaker configuration (`failureThreshold`, `failureCount`, `recoveryTimeout`, `halfOpenRequests`). However, the engine does not implement circuit breaker state transitions (closed -> open -> half-open -> closed).

**What's needed:** When a node's error rate exceeds the threshold, the circuit should open (rejecting requests immediately without forwarding), then transition to half-open after the recovery timeout (allowing a few test requests), and close again if those succeed.

**Why it matters:** Circuit breakers are a key resilience pattern covered in SESD Week 12 and referenced in the SESD reading list (Site Reliability Engineering). Without runtime behavior, students can only discuss the pattern theoretically.

**Recommendation:** Implement a `CircuitBreakerState` machine per-node that tracks failure counts and transitions between states during the simulation.

#### 6.2.6 Pre-Built Scenario Library and Templates

**Current state:** The simulator has a rich palette of individual components but no pre-built topologies. Every demonstration or assignment requires building a topology from scratch.

**What's needed:** A library of ready-to-use scenarios mapped to course topics:
- **"Single Server"** -- Client -> Server (for "What is a server?" lessons)
- **"Load Balanced Web App"** -- Client -> LB -> [Server x3] -> DB
- **"L4 vs L7 Comparison"** -- Side-by-side L4 and L7 topologies
- **"3-Tier with Security"** -- Client -> WAF -> Web -> App -> DB with Security Groups
- **"Event-Driven Order Processing"** -- Client -> API -> Kafka -> [Order, Notification, Analytics]
- **"Observability Pipeline"** -- Application + Metrics + Logging + Tracing pipelines
- **"Scale from Zero"** -- Progressive stages of scaling a simple app
- **"VPC Multi-AZ"** -- Components organized in VPC > AZ > Subnet hierarchy

**Why it matters:** Instructors need to start teaching immediately without spending 15 minutes building a topology on the canvas. Pre-built scenarios also ensure consistency across sections and semesters.

**Recommendation:** Create a `scenarios/` directory with `.json` topology files. Add a "Scenario Library" panel in the UI with thumbnails and descriptions. Tag each scenario with the course and week it supports.

#### 6.2.7 Guided Walkthrough / Tutorial Mode

**Current state:** No guided tutorials exist. The simulator assumes users already know how to use it.

**What's needed:** Step-by-step interactive tutorials that guide students through:
1. Placing their first node
2. Connecting nodes with edges
3. Configuring node properties
4. Running a simulation
5. Reading simulation results
6. Using debug mode to trace a request

**Why it matters:** Students encountering the simulator for the first time (CN Week 1, SESD Week 1) need structured onboarding. Without it, the first class session will be consumed by tool orientation rather than concept learning.

**Recommendation:** Implement a tooltip-driven tutorial overlay that highlights UI elements in sequence and prompts users to perform actions. Could reuse the existing Vite SPA architecture with a tutorial state machine.

#### 6.2.8 Assignment Mode with Validation

**Current state:** Instructors can share topology JSON files for students to load, but there is no mechanism for:
- Defining assignment requirements (e.g., "topology must include a load balancer")
- Auto-validating student submissions
- Grading based on simulation output (e.g., "achieve p99 < 100ms")

**What's needed:** An "assignment mode" where:
1. The instructor defines a scenario with constraints and target SLOs
2. Students modify or build a topology to meet the requirements
3. The simulator validates the solution against the constraints
4. A summary report is generated for grading

**Why it matters:** The courses have significant assignment weight (10-15% for in-class assignments, 15-20% for projects). Automated validation would scale assessment and provide instant feedback.

**Recommendation:** Define an `AssignmentSpec` JSON schema that includes required components, forbidden components, SLO targets, and workload configs. The validator checks the student's topology against this spec and reports pass/fail with details.

#### 6.2.9 Side-by-Side Topology Comparison

**Current state:** Students can only view one topology at a time. Comparing two configurations (e.g., L4 vs L7, with-cache vs without-cache) requires running simulations sequentially and manually comparing numbers.

**What's needed:** A split-view mode where two topologies run simultaneously with synchronized time-series charts, allowing direct visual comparison.

**Why it matters:** Many teaching scenarios and assignments involve A/B comparisons. The CN course's L4 vs L7 lesson, the SESD course's caching lesson, and scaling experiments all benefit from side-by-side views.

**Recommendation:** This is a significant UI feature. A lighter alternative is an "export metrics as CSV" function that lets students compare results in a spreadsheet, which requires minimal simulator changes.

#### 6.2.10 Rate Limiter Runtime Behavior

**Current state:** The `ResilienceConfig` interface includes `rateLimiter` with `maxTokens` and `refillRate`, but the engine does not implement token bucket rate limiting.

**What's needed:** Runtime token bucket rate limiting on nodes -- requests exceeding the rate are rejected with a specific reason code. Students should be able to observe the effect of different rate limits.

**Why it matters:** Rate limiting is a key concept in both CN (DDoS protection, API throttling) and SESD (system protection, graceful degradation). It's directly referenced in the auxiliary node types (`rate-limiter`, `throttler`).

**Recommendation:** Implement a `TokenBucket` class that integrates with the `GGcKNode` arrival handler. Check rate limiter before queue admission; reject with reason `rate_limited` if tokens are exhausted.

### 6.3 Priority Ranking for Development

Based on teaching impact and development complexity:

| Priority | Feature | Effort Estimate | Course Impact |
|---|---|---|---|
| **P0** | Pre-built scenario library | Low (JSON files + UI panel) | All courses -- enables immediate classroom use |
| **P0** | Cache hit/miss simulation | Medium (routing + node logic) | SESD, CN -- caching is central to both |
| **P1** | Health-check-aware LB routing | Low (filter in RoutingTable) | CN -- fixes unrealistic failure behavior |
| **P1** | Guided walkthrough / tutorial | Medium (tutorial overlay) | All courses -- essential for onboarding |
| **P1** | Auto-scaling runtime | High (ScalingController + dynamic nodes) | CN, SESD -- core scaling concept |
| **P2** | Circuit breaker runtime | Medium (state machine) | SESD -- resilience pattern |
| **P2** | DNS routing policies | Medium (RoutingTable extension) | CN -- Route 53 coverage |
| **P2** | Rate limiter runtime | Low (TokenBucket class) | CN, SESD -- protection patterns |
| **P2** | Assignment mode with validation | High (spec schema + validator + UI) | All courses -- scales assessment |
| **P3** | Side-by-side comparison | High (split-view UI) | CN -- A/B comparison scenarios |
| **P3** | Exportable reports | Medium (report generation) | All courses -- assignment submission |

---

## Appendix A: Simulator Component Catalog Summary

The simulator currently supports the following node types, organized by category:

| Category | Components | Count |
|---|---|---|
| **Compute** | API Server, Serverless Fn, Job Worker, Cron Job, Auth Service, Search Service, Sidecar Proxy, Generic Service | 8 |
| **Network & Edge** | Load Balancer (Legacy), L4 LB, L7 LB, Ingress Controller, Reverse Proxy, Service Mesh, API Gateway, CDN, NAT Gateway, VPN Gateway, Routing Rule, Routing Policy, Edge Router, Network Interface | 14 |
| **Storage & Data** | Primary DB, Read Replica, NoSQL DB, Redis Cache, Object Storage, Search Index, Time-series DB, Graph DB, Vector DB, Data Warehouse, Data Lake, KV Store | 12 |
| **Messaging & Streaming** | Message Queue, Event Broker (Kafka), Pub/Sub, Event Stream | 4 |
| **Security & Identity** | WAF, Firewall Rule, Security Group | 3 |
| **Orchestration & Infra** | Discovery Service, Config Store, Secrets Manager, Tool Registry, Agent Orchestrator | 5 |
| **Observability** | Metrics Collector, Log Collector, Centralized Logging, Tracing Collector, Alerting Engine, Health Check Manager, Safety & Observability Mesh | 7 |
| **External & Integration** | External Service, Output Sink, LLM Gateway | 3 |
| **DNS & Certs** | DNS Server, DNS Resolver | 2 |
| **Auxiliary** | Sharding, Hashing, Shard Node, Partition Node | 4 |
| **Composite (visual)** | VPC Region, Availability Zone, Subnet | 3 |
| **Source** | Client App, Input Source | 2 |
| | **Total** | **67 palette entries** |

## Appendix B: Workload Pattern Reference

| Pattern | Description | Teaching Use Case |
|---|---|---|
| `constant` | Fixed RPS throughout simulation | Baseline measurement, steady-state analysis |
| `poisson` | Random arrivals (exponentially distributed inter-arrival times) | Realistic web traffic modeling |
| `bursty` | Alternating high/low RPS periods | Microservice burst handling |
| `spike` | Normal RPS with a short-duration traffic spike | Flash sale / viral event scenarios |
| `diurnal` | 24-hour cycle with configurable hourly multipliers | Day/night traffic patterns |
| `sawtooth` | Linear ramp to peak, then immediate drop | Load testing / capacity planning |
| `replay` | Replay recorded traffic patterns | Production traffic simulation |

## Appendix C: Course Week Quick Reference

### When to Introduce the Simulator

| Course | Recommended Introduction Week | Reason |
|---|---|---|
| CN | Week 1 | Simulator directly models network devices, topologies, and traffic flow from the very first topic |
| SESD | Week 1 (conceptual), Week 7+ (hands-on) | Early weeks use it to demonstrate "why architecture matters"; later weeks use it for scaling and pattern exercises |
| FSDE | Week 3 (conceptual), Week 12 (hands-on) | Early use for demonstrating server/networking concepts; primary use in the monitoring and observability module |

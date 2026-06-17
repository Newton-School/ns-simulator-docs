# NS-Simulator: Meeting Feedback Analysis & Implementation Roadmap

> **Purpose:** Feasibility assessment and implementation plan for feedback collected across demo meetings and discussions.
>
> **Date:** June 2026
>
> **Scope:** Covers teaching use cases, product direction, and critical fixes identified in meeting feedback.

---

## Table of Contents

1. [Feedback Summary](#1-feedback-summary)
2. [Teaching and Classroom Use Cases](#2-teaching-and-classroom-use-cases)
3. [Product Improvements and Future Directions](#3-product-improvements-and-future-directions)
4. [Critical Fixes (Later Thoughts)](#4-critical-fixes-later-thoughts)
5. [Recommended Execution Order](#5-recommended-execution-order)
6. [Appendix: Current Capability Snapshot](#appendix-current-capability-snapshot)

---

## 1. Feedback Summary

Three themes emerged across the meetings:

1. **The simulator is already strong for teaching**, but needs blueprints, accurate node behaviour, and lower setup friction to be classroom-ready.
2. **Product direction should be incremental** — nail the fundamentals before layering on observability, gamification, or interview prep.
3. **The load balancer routing-to-dead-servers bug is a blocker** — until core node behaviour is correct, demos will undermine trust in the tool.

The feedback is well-aligned. The "later thoughts" section essentially says: fix the foundation first, demo it, collect feedback, then build forward. That should be the governing principle for everything below.

---

## 2. Teaching and Classroom Use Cases

### 2.1 Teach L4 vs L7 Load Balancing, Service Meshes, CDNs, etc.

**Feasibility: Fully possible today.**

The simulator already has distinct L4 and L7 load balancer nodes with different processing characteristics (L4: ~0.15ms mean service time for TCP-level forwarding; L7: ~0.4ms mean for HTTP header inspection). Both support round-robin and weighted routing, and L7 supports conditional routing by request type.

Service Mesh, CDN, Ingress Controller, Reverse Proxy, and API Gateway nodes all exist in the palette with pre-configured defaults.

| Component | Palette Status | Teaching-Ready? |
|---|---|---|
| L4 Load Balancer | Exists (`load-balancer-l4`) | Yes — distinct from L7 in latency profile |
| L7 Load Balancer | Exists (`load-balancer-l7`) | Yes — supports content-based routing |
| Service Mesh | Exists (`service-mesh`) | Partial — node exists but sidecar-proxy injection pattern not automated |
| CDN | Exists (`cdn`) | Partial — processes requests but no cache hit/miss simulation yet |
| WAF | Exists (`waf`) | Yes — configurable block rate, security_blocked rejection |
| API Gateway | Exists (`api-gateway`) | Yes — L7 routing with gateway semantics |

**What's needed to make this classroom-ready:**

- **Cache hit/miss on CDN and Redis nodes** — without this, adding a cache node doesn't meaningfully change downstream traffic, making caching demos hollow. Implementation: add a `cacheHitRate` field (0.0–1.0) to node config; on hit, complete the request immediately without forwarding downstream; on miss, forward to origin. This is a medium-effort change in `GGcKNode` arrival handling and the `RoutingTable`.
- **Service Mesh sidecar pattern** — currently, students must manually place sidecar proxies beside each service. A "wrap in service mesh" action that auto-inserts sidecars would make the pattern teachable in minutes rather than a 15-minute setup exercise. This is a nice-to-have, not a blocker.

**How to go ahead:**

1. CDN/Redis cache hit/miss is the highest-impact teaching feature missing. Implement it as a P0 alongside the load balancer fix (Section 4.1).
2. For service mesh, the current manual approach is acceptable for now. Document a step-by-step "build a service mesh" tutorial in the scenario library.
3. L4 vs L7 teaching is ready today — create a pre-built comparison topology (Section 2.3) and it's demo-ready.

---

### 2.2 Show What Each Component Does, Then Connect to Real-World Use Cases

**Feasibility: Possible with documentation and scenario design, not code changes.**

The simulator has 67 palette entries across 12 categories. Each node already has a label, sublabel, and configurable properties visible in the inspector panel. What's missing is the pedagogical layer: explanations of what each component does in real-world terms and when you'd use it.

**What's needed:**

- **Component info cards** — a tooltip or expandable panel on each node showing: (a) what this component does in plain English, (b) the real-world AWS/GCP equivalent, (c) when you'd use it. The data for this mostly exists in the canonical catalogue CSVs (`Component taxonomy.csv`, `Provider mapping (quick).csv`), it just needs to surface in the UI.
- **"Real-world mapping" labels** — optional annotations showing "This is your AWS ALB" or "This is your Cloudflare CDN" alongside the generic component name.

**How to go ahead:**

1. Short-term: add a markdown-rendered `description` field to palette templates that shows on hover or in the properties panel. Low effort — it's a UI-only change reading from existing catalogue data.
2. Medium-term: build the "Component Reference" panel as a sidebar tab that students can browse independently of the canvas.

---

### 2.3 Add Blueprints, Templates, and Sample Topologies

**Feasibility: Fully possible, low effort, high impact.**

The simulator already supports save/load of topology JSON files. Pre-built scenarios are just curated JSON files with a UI to browse and load them. The canonical catalogue already defines 7 scenarios to ship and 23 architectural patterns.

**What's needed:**

- **A `scenarios/` directory** with `.json` topology files for common teaching use cases.
- **A "Scenario Library" UI panel** — a browsable list with titles, descriptions, course/week tags, and one-click load. Could be a new tab in the left sidebar alongside the existing node palette.
- **Starter set of 8–10 scenarios**, prioritized by meeting feedback:

| Scenario | Purpose | Priority |
|---|---|---|
| Single Server Basics | "What is a server?" — 1 client, 1 server | P0 |
| Load Balanced Web App | Client → LB → 3 servers → DB | P0 |
| L4 vs L7 Comparison | Side-by-side topologies showing latency and routing differences | P0 |
| Caching Impact | Same topology with and without Redis cache | P0 (depends on cache hit/miss) |
| 3-Tier with Security | Client → WAF → Web → App → DB with security groups | P1 |
| Event-Driven (Pub/Sub) | Client → API → Kafka → [Order, Notification, Analytics] | P1 |
| Observability Pipeline | App path + async metrics/logging/tracing | P1 |
| Scale from Zero | Progressive stages from single server to multi-tier | P1 |
| VPC Multi-AZ Layout | Components in VPC > AZ > Subnet hierarchy | P2 |
| Microservice Mesh | Multiple services with sidecar proxies | P2 |

**How to go ahead:**

1. Create the JSON topology files first — this can be done by building each topology in the existing UI and saving. No code changes required.
2. Build the Scenario Library panel as a lightweight sidebar component that reads from a manifest file listing available scenarios. Medium effort.
3. Tag each scenario with metadata: course (CN/SESD/FSDE), week, difficulty, concepts covered.

---

### 2.4 Reduce Setup Overhead Compared to AWS Demos

**Feasibility: This is already the simulator's core value proposition.**

The simulator runs entirely in the browser as a Vite SPA — no AWS account, no billing, no IAM configuration, no waiting for resource provisioning. Students open a URL and start building.

**Current advantages over AWS demos:**

| Dimension | AWS Demo | NS-Simulator |
|---|---|---|
| Setup time | 20–45 min (IAM, VPC, EC2, ALB config) | 0 min (open browser) |
| Cost | Real AWS charges | Free |
| Risk | Accidental charges, misconfigured security groups | None |
| Reproducibility | Depends on account state, region, quotas | Deterministic (seeded PRNG) |
| Observability | Requires CloudWatch setup | Built-in metrics, traces, SLOs |
| Iteration speed | Minutes per change (provision/deprovision) | Seconds (change config, re-run) |

**What's needed to fully deliver on this promise:**

- **Pre-built scenarios** (Section 2.3) — eliminates the remaining setup: building the topology from scratch.
- **Guided tutorial for first-time users** — a tooltip-driven walkthrough of "place a node → connect it → configure it → run → read results." Medium effort, but essential for the first class session. Without it, the first 30 minutes of class becomes tool orientation.
- **Shareable URLs or embed codes** — so instructors can share a topology link rather than a JSON file students must download and load. This requires a backend or URL-encoded state, so it's a later feature.

**How to go ahead:**

1. Scenarios + tutorial mode are the immediate priorities.
2. Shareable URLs can wait — JSON file sharing via LMS (Google Classroom, etc.) is good enough for now.

---

### 2.5 Use Demos to Collect Progressive Feedback

**Feasibility: Fully possible, this is a process decision not a feature.**

The feedback loop proposed in the meetings is:

```
Fix core behaviour → Demo with accurate fundamentals → Collect feedback → Iterate → Demo again
```

This is the right approach. The simulator is mature enough that a demo with fixed load balancer routing and a handful of pre-built scenarios would be compelling.

**Recommended demo milestones:**

| Demo | Gate Criteria | Audience | Goal |
|---|---|---|---|
| **Demo 1: Fundamentals** | LB routing fixed, 4 pre-built scenarios, basic tutorial | Instructors only | Validate teaching value, collect feature requests |
| **Demo 2: Classroom Pilot** | Cache hit/miss, 8 scenarios, component info cards | 1 section of CN students | Observe real classroom use, identify UX friction |
| **Demo 3: Multi-Course** | Auto-scaling, circuit breaker, assignment mode | All 3 courses | Full integration into curriculum |

**How to go ahead:**

1. Fix the load balancer bug (Section 4.1) and build 4 scenarios — that's Demo 1.
2. Schedule Demo 1 with instructors and collect structured feedback (what worked, what confused, what's missing).
3. Use Demo 1 feedback to prioritize Demo 2 features.

---

## 3. Product Improvements and Future Directions

### 3.1 Observability Features (Datadog-like Experience)

**Feasibility: Partially possible now, full vision requires significant work.**

**What exists today:**

The simulator already captures rich observability data during simulation:

- **Per-node metrics:** throughput, latency percentiles (P50/P90/P95/P99), utilization, queue depth, error rate, availability — displayed in the ResultsTray.
- **Request tracing:** sampled waterfall traces showing queue wait, service time, and edge latency per hop — displayed in the Traces tab.
- **Time-series snapshots:** 1-second interval captures of node state (queue length, active workers, utilization) — used for live canvas colouring.
- **SLO breach detection:** compares observed metrics against configured targets, flags breaches with severity.
- **Health checks:** Little's Law verification, conservation checks, warmup adequacy.
- **Observability pipeline nodes:** Metrics Collector, Log Collector, Centralized Logging, Tracing Collector, Alerting Engine, Health Check Manager — all exist as palette components.

**What a "Datadog-like experience" would require:**

| Feature | Current State | Gap |
|---|---|---|
| Real-time dashboards with custom charts | Time-series data exists but only surfaces as canvas colours and summary stats | Need a dashboard view with configurable line/bar charts per metric per node |
| Trace waterfall viewer | Exists in Traces tab | Already close to Datadog's trace view — needs filtering and search |
| Log stream viewer | Debug events captured | Need a formatted log stream panel with severity filtering |
| Alerting with thresholds | SLO breaches detected post-simulation | Need real-time alerting during simulation (toast/badge when threshold crossed) |
| Service map with live traffic | Canvas shows nodes with status colours | Need animated traffic flow rates on edges (partially exists via PacketEdge pulse) |
| APM-style service dependency graph | Topology is the dependency graph | Need latency/error annotations on edges in the canvas view |

**How to go ahead:**

1. **Short-term (low effort):** Surface the existing time-series snapshot data in a new "Dashboard" tab in the ResultsTray. Show line charts for utilization, queue depth, and throughput per node over simulation time. This uses data that already exists — it's purely a visualization task.
2. **Medium-term:** Add real-time SLO breach toasts during simulation (the engine already detects them, just needs to emit them as live events to the UI).
3. **Long-term:** Build a dedicated "Observability View" mode that presents the same topology but with Datadog-style overlays: per-edge latency labels, per-node error rate badges, and a trace search panel. This is a significant UI effort but would be a differentiating feature.

**Important caveat:** The observability features should enhance the teaching experience, not replicate Datadog. The goal is to teach students what observability looks like and why it matters, not to build a production monitoring tool.

---

### 3.2 Keep System Behaviour Realistic

**Feasibility: This is an ongoing quality bar, not a feature.**

The simulator's G/G/c/K queueing model is already grounded in real queueing theory. The current realism gaps that matter most for teaching are:

| Behaviour | Current Realism | Issue |
|---|---|---|
| Load balancer routing | Unrealistic | Routes to failed nodes (Section 4.1) |
| Cache behaviour | Unrealistic | No hit/miss, all requests treated identically |
| Auto-scaling | Not simulated | Config exists but engine ignores it |
| Circuit breaker | Not simulated | Config exists but no state transitions |
| Rate limiting | Not simulated | Config exists but no token bucket |
| Processing time distributions | Realistic | 12 distributions including empirical mixtures |
| Queue discipline | Realistic | FIFO, LIFO, Priority, WFQ all implemented |
| Network latency | Realistic | Path-type-aware defaults (same-rack to internet) |
| Security filtering | Realistic | WAF block rate, firewall drop rate functional |

**How to go ahead:**

1. Fix the items flagged as "Unrealistic" in priority order: LB routing → cache hit/miss → auto-scaling → circuit breaker → rate limiting.
2. For each fix, add a targeted test that validates the behaviour against expected queueing theory results.
3. Don't chase perfect realism in areas that don't affect teaching (e.g., TCP handshake simulation, IP address allocation). The simulator models system-level behaviour, not packet-level protocols.

---

### 3.3 Availability and Reliability Through Dedicated Workflows

**Feasibility: Possible, builds on existing infrastructure.**

The simulator already has the raw ingredients:

- **Node error rates** — configurable per-node failure injection.
- **Node failure/recovery events** — nodes can transition to `failed` status.
- **SLO configuration** — latency P99 targets, availability targets, error budgets.
- **SLO breach detection** — post-simulation analysis flags violations with severity.
- **Health check manager node** — exists in the palette.

**What "dedicated workflows" means in practice:**

A set of guided scenarios that progressively introduce reliability concepts:

| Workflow | Concept | Scenario |
|---|---|---|
| **Workflow 1: What is Availability?** | Uptime, error rate, SLOs | Single server with increasing error rate; students observe availability drop below SLO |
| **Workflow 2: Redundancy** | Replicas, failover | Add server replicas; show that 1 failure no longer kills the system |
| **Workflow 3: Health-Aware Routing** | Health checks, target groups | LB stops routing to failed servers (requires Section 4.1 fix) |
| **Workflow 4: Circuit Breakers** | Failure isolation | Cascading failure prevented by circuit breaker opening (requires circuit breaker runtime) |
| **Workflow 5: Error Budgets** | SRE practices | Students configure error budgets and observe how deployment velocity trades off against reliability |

**How to go ahead:**

1. Workflows 1–2 are possible today with pre-built scenarios and instructor narration.
2. Workflow 3 requires the LB routing fix.
3. Workflows 4–5 require circuit breaker runtime and error budget tracking — schedule for later.
4. Package these as a "Reliability 101" scenario collection in the scenario library.

---

### 3.4 System Design Interview Preparation

**Feasibility: Possible as a long-term direction, not immediate.**

The simulator's topology builder is inherently a system design tool — students drag components, connect them, configure behaviour, and observe the system under load. This maps directly to system design interview questions:

| Interview Question Type | Simulator Support |
|---|---|
| "Design a URL shortener" | Build topology: Client → LB → App Server → Cache → DB. Configure workload, observe metrics. |
| "Design a notification system" | Build: Client → API → Message Queue → [Email, SMS, Push] services. Show async fan-out. |
| "How would you scale this?" | Start with 1 server, progressively add LB, replicas, cache, CDN, read replicas. |
| "What happens when X fails?" | Inject node failures, observe cascading effects and mitigation strategies. |
| "How would you monitor this?" | Add observability pipeline alongside the application. |

**What's needed to make this a dedicated product surface:**

- **Interview question templates** — pre-built starting points and target architectures for common questions.
- **Constraints mode** — "design a system that handles 10,000 RPS with P99 < 200ms" with automated validation.
- **Scoring rubric** — did the student include caching? Load balancing? Database scaling? Observability? Score based on architectural completeness and SLO compliance.
- **Time pressure** — optional timer for interview simulation.

**How to go ahead:**

1. This is a natural extension of the scenario library + assignment validation features.
2. Don't build a separate "interview prep" mode. Instead, make the core product good enough for teaching, and interview prep falls out naturally.
3. Once the scenario library, SLO validation, and assignment mode exist, create an "Interview Prep" scenario collection with 10–15 common system design questions.
4. This is a Phase 3 initiative — after the classroom use case is solid.

---

### 3.5 Inspiration from Balwa Sir's Terraform Repository

**Feasibility: Applicable as a UX and content model, not a code dependency.**

The Terraform repository likely provides structured, progressive labs with clear instructions and expected outcomes. The analogous pattern for the simulator:

- **Each scenario = one "lab"** with a title, objective, pre-built starting topology (or empty canvas with instructions), and expected outcome (SLO targets to hit, specific metrics to observe).
- **Progressive difficulty** — labs build on each other: Lab 1 teaches single server, Lab 2 adds a load balancer, Lab 3 introduces caching, etc.
- **Self-contained** — each lab includes all instructions and doesn't require external documentation.

**How to go ahead:**

1. Review the Terraform repo structure to understand the lab format (number of labs, progression, instruction style).
2. Map the lab structure to simulator scenarios: each lab = one JSON topology + one markdown instruction file.
3. Build 5–6 progressive labs as a proof of concept for one course (CN is the highest alignment).
4. This aligns with the scenario library work (Section 2.3) — labs are scenarios with added instructional metadata.

---

### 3.6 Gamification and Better Visualisations

**Feasibility: Partially possible, requires design work.**

**Gamification:**

The simulator currently has no gamification. Adding it requires defining what "success" looks like in measurable terms. The existing SLO framework provides a natural scoring mechanism:

| Gamification Element | Implementation Approach | Effort |
|---|---|---|
| **Score per scenario** | Points based on: SLO compliance, cost efficiency, component count (fewer = better) | Medium — scoring function over existing metrics |
| **Achievements / badges** | "First SLO breach resolved", "Survived a traffic spike", "Zero rejections under 5000 RPS" | Medium — event-driven badge system |
| **Leaderboard** | Rank students by score on a shared scenario | High — requires backend for score submission |
| **Progressive challenges** | Unlock harder scenarios by completing easier ones | Low — metadata on scenario library |
| **Star rating per scenario** | 1–3 stars based on how well SLOs were met | Low — threshold-based on existing metrics |

The Python farming game reference suggests the team values visual feedback loops where actions have immediate, visible consequences. The simulator already provides this through canvas colouring (green → yellow → red), animated edges, and real-time metrics. Areas to improve:

| Visualisation | Current State | Improvement |
|---|---|---|
| Node status | Colour-coded (idle/busy/saturated/failed) | Add particle effects or pulse animations for high-traffic nodes |
| Edge traffic | Pulsing animation | Vary pulse speed/density by actual throughput |
| Queue buildup | Badge showing depth number | Add a visual "fill meter" bar on the node |
| Failure cascading | Node turns red | Add a ripple/wave effect showing failure propagating downstream |
| Results celebration | Static metrics display | Add confetti or success animation when all SLOs pass |

**How to go ahead:**

1. **Immediate:** Star rating per scenario is low-effort and high-engagement. Show 1–3 stars on the results screen based on SLO compliance, throughput efficiency, and cost.
2. **Short-term:** Progressive challenges via scenario library ordering (complete Scenario 1 to unlock Scenario 2).
3. **Medium-term:** Scoring function that combines SLO compliance, cost efficiency, and architecture quality.
4. **Long-term:** Leaderboard requires a backend. Defer until the classroom pilot validates that gamification drives engagement.
5. **Visualisation improvements** can be sprinkled in incrementally — each one is a small, independent UI change.

---

### 3.7 Focus and Iterate (Don't Build Everything at Once)

**This is the most important piece of feedback and should govern all planning.**

The simulator already has a large surface area (67 node types, 12 distributions, 7 workload patterns, detailed metrics, tracing, SLOs, cost estimation). The risk is spreading effort across too many features and shipping none well.

**Proposed focus areas for the next phase:**

| Focus Area | Why | Deliverables |
|---|---|---|
| **Core behaviour accuracy** | Trust in the tool depends on correct simulation | LB routing fix, cache hit/miss, node behaviour validation |
| **Classroom readiness** | The primary use case from meetings | 8 pre-built scenarios, component info cards, basic tutorial |
| **Feedback collection** | Enables data-driven prioritisation | Demo 1 with instructors, structured feedback template |

**What to explicitly defer:**

- Auto-scaling runtime (complex, not needed for Demo 1)
- Circuit breaker / rate limiter runtime (same)
- System design interview mode (Phase 3)
- Leaderboard and advanced gamification (needs backend)
- Side-by-side comparison view (significant UI work)
- Assignment validation mode (needs spec design)
- Shareable URLs (needs backend or encoding strategy)

---

## 4. Critical Fixes (Later Thoughts)

### 4.1 Fix Load Balancer Routing to Down Servers

**This is the single most important fix. It blocks demo credibility.**

**Current behaviour:** The `RoutingTable` in `src/engine/routing.ts` resolves outgoing edges using round-robin or weighted strategies without checking whether the target node is healthy. When a node fails (status = `failed`), the load balancer continues sending traffic to it. All those requests fail, producing unrealistic error rates and confusing demos.

**Expected behaviour:** Load balancers should skip unhealthy targets. When Server B is down, a round-robin LB with [A, B, C] should route only to A and C.

**Implementation approach:**

1. In `RoutingTable.resolve()`, filter candidate edges to exclude those whose target node has `status === 'failed'`.
2. This requires the routing table to have access to node state — either by passing a `nodeHealth` map at resolution time, or by registering a health callback when building the routing table.
3. If all targets are unhealthy, the request should be rejected with reason `no_healthy_targets` rather than silently failing.
4. Optional: add a configurable `healthCheckInterval` on router-type nodes to control how quickly they detect failures (instant vs delayed detection adds realism).

**Effort:** Low. The routing table already receives the node map during engine initialisation. Adding a health filter is a small change to the route resolution path.

**Test cases to add:**

- LB with 3 targets, 1 failed → traffic distributed to remaining 2
- LB with 3 targets, all failed → requests rejected with `no_healthy_targets`
- Node recovers → LB resumes routing to it
- Weighted routing with 1 failed target → weights redistributed to healthy targets

---

### 4.2 Validate Core Node Behaviour at a Granular Level

**Current test coverage:** The engine has test suites for the simulation engine, GGcKNode queue model, min-heap scheduler, distributions, workload generation, routing, tracing, metrics, and output analysis. However, the tests focus on integration-level behaviour (does a simulation run end-to-end?) rather than validating specific node behaviours against queueing theory expectations.

**What granular validation means:**

| Validation | Method | Status |
|---|---|---|
| M/M/1 queue: mean wait time = ρ / (μ(1-ρ)) | Run M/M/1 simulation, compare observed vs theoretical | Exists partially (Little's Law check) |
| M/M/c queue: Erlang C formula validation | Run with c workers, compare P(wait) against formula | Not tested |
| Rejection rate under G/G/c/K: empirical vs simulated | Compare observed rejection rate with analytical approximation | Not tested |
| Throughput ceiling: min(arrival rate, service rate × workers) | Run above and below capacity, verify throughput saturates | Not tested |
| Distribution sampling accuracy | KS-test on sampled vs theoretical CDF | Exists for basic distributions |
| Routing weight accuracy | Run 10,000 requests through weighted router, verify distribution | Exists for round-robin |

**How to go ahead:**

1. Add a `__tests__/queueing-theory-validation.test.ts` suite that runs known analytical scenarios and compares observed metrics against theoretical values (with tolerance bands for stochastic variation).
2. Focus on the nodes that matter most for teaching: API Server (basic queue), Load Balancer (routing accuracy), Cache (hit/miss once implemented), and Message Broker (fan-out correctness).
3. Use deterministic seeding (already supported) to make validation tests reproducible.

---

### 4.3 Demo Once Fundamentals Are Accurate

**This is a process gate, not a feature.** The criteria for "fundamentals are accurate" should be:

- [ ] Load balancer does not route to failed nodes
- [ ] Round-robin produces even distribution (within 5% tolerance at 1000+ requests)
- [ ] Weighted routing produces distribution matching configured weights (within 5%)
- [ ] Node with 0% error rate produces 0 errors
- [ ] Node with 100% error rate produces 100% errors
- [ ] Queue rejection occurs when queue is full (not before, not after)
- [ ] Timeout fires at the configured deadline (not earlier, not later)
- [ ] Request count is conserved: arrived = processed + rejected + timed_out + errored per node
- [ ] Little's Law holds within 10% tolerance for steady-state scenarios
- [ ] Deterministic: same seed + same topology = same results

Most of these are already validated by existing tests. The main gap is the LB routing fix.

---

### 4.4 Gather Feedback → Improve Incrementally

This is the iteration model proposed in the meetings. Translating it into a concrete process:

**After each demo:**

1. **Structured feedback form** — 5 questions: (a) What concept did you try to teach? (b) Did the simulator behave as expected? (c) What confused you or your students? (d) What was missing? (e) What would you show in the next demo?
2. **Bug triage** — any behaviour that contradicted real-world expectations goes into a "realism fix" backlog.
3. **Feature requests** — ranked by how many instructors/students asked for the same thing.
4. **Next demo gate** — address top 3 bugs and top 1 feature request before the next demo.

---

## 5. Recommended Execution Order

Based on all the feedback, here is the recommended phased approach:

### Phase 1: Foundation (Target: Demo 1 with Instructors)

**Goal:** Accurate core behaviour + enough content for a compelling demo.

| # | Task | Type | Effort | Depends On |
|---|---|---|---|---|
| 1 | Fix LB routing to skip failed nodes | Bug fix | Low | — |
| 2 | Add queueing theory validation tests | Testing | Medium | — |
| 3 | Build 4 core scenarios (Single Server, LB Web App, L4 vs L7, Security Layers) | Content | Low | #1 |
| 4 | Add component description tooltips from catalogue data | UI | Low | — |
| 5 | Run Demo 1 with instructors, collect feedback | Process | — | #1–4 |

**Timeline estimate:** 1–2 weeks of focused work for tasks 1–4.

### Phase 2: Classroom Ready (Target: Demo 2 with Students)

**Goal:** Rich enough for a full class session, accurate enough for student trust.

| # | Task | Type | Effort | Depends On |
|---|---|---|---|---|
| 6 | Implement cache hit/miss simulation | Engine | Medium | — |
| 7 | Build 4 more scenarios (Caching, Pub/Sub, Observability, Scale from Zero) | Content | Low | #6 |
| 8 | Build guided tutorial (first-time user walkthrough) | UI | Medium | — |
| 9 | Add time-series dashboard tab in ResultsTray | UI | Medium | — |
| 10 | Add star rating per scenario | UI | Low | — |
| 11 | Run Demo 2 with one CN section, collect feedback | Process | — | #6–10 |

**Timeline estimate:** 2–3 weeks of focused work for tasks 6–10.

### Phase 3: Depth and Breadth (Target: Multi-Course Integration)

**Goal:** Cover advanced topics, support assignments, begin interview prep exploration.

| # | Task | Type | Effort | Depends On |
|---|---|---|---|---|
| 12 | Implement auto-scaling runtime | Engine | High | — |
| 13 | Implement circuit breaker state machine | Engine | Medium | — |
| 14 | Implement rate limiter (token bucket) | Engine | Low | — |
| 15 | Build reliability workflow scenarios | Content | Medium | #12, #13 |
| 16 | Build assignment validation mode | Engine + UI | High | — |
| 17 | Build interview prep scenario collection | Content | Medium | #16 |
| 18 | Add scoring function (SLO + cost + architecture quality) | Engine | Medium | — |
| 19 | Explore real-time alerting during simulation | UI | Medium | — |

**Timeline estimate:** 4–6 weeks, can be parallelised across team members.

### Phase 4: Polish and Scale (Future)

- Leaderboard (requires backend)
- Shareable URLs
- Side-by-side comparison view
- Exportable PDF/Markdown reports
- Advanced visualisation effects (failure ripples, traffic density)
- Terraform-style progressive lab format

---

## Appendix: Current Capability Snapshot

For reference, here is what the simulator can do today without any changes:

**Engine:**
- Discrete event simulation with microsecond-precision timing
- G/G/c/K queueing model per node (configurable workers, capacity, service time distribution)
- 12 statistical distributions (constant, uniform, exponential, normal, log-normal, Poisson, Weibull, gamma, beta, Pareto, empirical, mixture)
- 7 workload patterns (constant, Poisson, bursty, spike, diurnal, sawtooth, replay)
- Deterministic via seeded PRNG (SFC32)
- Round-robin, weighted, conditional, broadcast, passthrough routing
- Async and sync edge modes
- Node failure injection (error rate, security block rate, packet drop rate)
- Edge latency with configurable distributions and path-type-aware defaults
- Request timeout enforcement

**Analysis:**
- Per-node metrics: throughput, latency P50/P90/P95/P99, utilization, queue depth, error rate, availability
- SLO breach detection with severity classification
- Little's Law verification
- Conservation checks (arrived = processed + rejected + timed_out)
- Warmup adequacy check
- Cost estimation (AWS/GCP/Azure pricing)
- Request tracing with waterfall spans

**UI:**
- Three-panel resizable layout (palette, canvas, properties)
- Drag-and-drop topology builder with 67 node types
- React Flow canvas with animated edges and colour-coded node status
- Properties inspector for all node and edge configuration
- Simulation controls (run/pause/resume/stop, workload selector, RPS slider, seed input)
- Results tray with summary, per-node, and traces tabs
- VPC/AZ/Subnet visual containers
- Topology save/load via JSON files

**Testing:**
- Vitest test suites for engine, nodes, scheduler, distributions, workload, routing, tracing, metrics, output, validation
- Deterministic test support via seeded PRNG
- Mock topologies for reproducible scenarios

---

*This document should be updated after each demo with feedback outcomes and revised priorities.*

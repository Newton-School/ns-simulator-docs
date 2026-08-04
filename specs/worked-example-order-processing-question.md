# Worked Example — Order Processing Question, Environment Model, and Paper Evaluation

This document is a worked example of what a good simulator-graded system design question could look like before committing to implementation details. It uses the existing order-processing example and turns it into a full paper design artifact: the question, the canonical solution topology, the environment model, the constraint model, and the evaluation logic.

This is intentionally more concrete than [system-design-leetcode-environment-model.md](./system-design-leetcode-environment-model.md). That document defines the product model in general. This document applies the model to one realistic intermediate question.

---

## Table of Contents

1. [Purpose](#purpose)
2. [Question Scenario](#question-scenario)
3. [Mental Model](#mental-model)
4. [Environment Modes](#environment-modes)
5. [Environment Isolation Levers](#environment-isolation-levers)
6. [Constraint Taxonomy](#constraint-taxonomy)
7. [Worked Environment Design](#worked-environment-design)
8. [Canonical Solution Topology](#canonical-solution-topology)
9. [Paper Evaluation](#paper-evaluation)
10. [Editorial and Progression Surfaces](#editorial-and-progression-surfaces)
11. [Implementation Notes](#implementation-notes)

---

## Purpose

The purpose of this document is to answer three questions before implementation:

1. What is a good example of a simulator-native system design problem?
2. How should that problem be exposed differently in `PRACTICE`, `ASSIGNMENT`, and `AUTHOR` environments?
3. How do we evaluate the submission behaviorally and structurally without collapsing into snapshot topology matching?

This document assumes the current date is July 28, 2026 and uses the current example assets already present in the repo:

- Question source: [sample-question.example.json](../../sample-question.example.json)
- Canonical answer topology: [answer-order-platform.topology.json](../../answer-order-platform.topology.json)

---

## Question Scenario

### Prompt

**OPEN-BUILD · INTERMEDIATE**

**Design an order-processing platform**

Design the backend for an e-commerce order platform. It must stay responsive and low-error under both steady and peak load.

### Functional requirements

- Accept order-create requests
- Look up catalog and inventory
- Persist orders durably

### Non-functional requirements

- Error rate under `10%`
- Sustains at least `100 req/s`

### Scale

- Peak RPS: `1000`
- Read / Write ratio: `80:20`

### Teaching intent

This question is not meant to test every possible architecture concept. It is meant to test a bounded family of decisions:

- ingress routing
- service tier fan-out
- read scaling
- durable writes
- asynchronous event publication after order creation

It is an intermediate problem because the student must reason about mixed read and write traffic rather than a single straight-line request path.

### Scope note

The current repo sample question in [sample-question.example.json](../../sample-question.example.json) is an empty-scaffold open-build question. This worked example intentionally proposes a more guided deployment of the same content family:

- same prompt intent
- same canonical answer topology
- same simulator-facing grading style
- better runtime isolation through a partial scaffold and curated environment profiles

That change is deliberate. The purpose of this document is to decide what the better teaching and evaluation shape should be before freezing implementation.

---

## Mental Model

This worked example follows the core separation used throughout the question-platform design:

- `QuestionPackage` = what the problem is
- `EnvironmentProfile` = how much of the simulator is exposed
- `AttemptState` = the student's current work

| Layer | Role in this example |
|---|---|
| `QuestionPackage` | defines the prompt, scaffold, constraints, suite, and rubric |
| `EnvironmentProfile` | determines whether the problem is shown as `PRACTICE`, `ASSIGNMENT`, or `AUTHOR` |
| `AttemptState` | stores the student topology, test-run count, and grade state |

The important product rule is:

The content should stay the same while the environment changes the teaching lens.

---

## Environment Modes

This same problem should be deployable in three modes.

| Mode | Primary goal | Student experience |
|---|---|---|
| `PRACTICE` | concept acquisition | guided, curated, explanatory |
| `ASSIGNMENT` | evaluation signal | constrained, quieter, less revealing |
| `AUTHOR` | question verification | unrestricted preview of the problem |

### `PRACTICE`

- Prompt visible
- Scaffold visibly marked
- Curated palette
- Live test runs
- Live rubric feedback
- Curated result cards
- Editorial unlocked after completion

### `ASSIGNMENT`

- Prompt visible
- Scaffold visible but fixed
- Curated palette
- Limited dry runs
- Hidden grading suite
- Post-submit rubric only
- Minimal chrome

### `AUTHOR`

- Full palette
- Full result surfaces
- Full suite visibility
- Full rubric visibility
- Used by question-setter, not learner

---

## Environment Isolation Levers

This example uses the following isolation levers.

| Lever | Decision in this example | Why |
|---|---|---|
| Palette allowlist | only routing, service, cache, relational DB, and queue components | keeps the problem about order flow, not every infra primitive |
| Locked scaffold | fixed source and API gateway | removes edge-ingress churn from the learning objective |
| Editability | scaffold nodes are not removable or editable in student modes | prevents wasting time on the wrong layer |
| Curated results | summary, service tier, cache / replica / primary DB / queue cards | shows only the components that matter to the lesson |
| Feedback timing | live in `PRACTICE`, post-submit in `ASSIGNMENT` | supports learning without trivializing contest mode |
| Structural invariants | broad family checks, not exact graph equality | constrains the solution family without nitpicking |
| Budget box | node count and worker ceiling | makes overbuilding visible and bounded |

---

## Constraint Taxonomy

### 1. Input Constraints

These constrain what the student is allowed to build.

For this example:

- allowed component families are limited
- the scaffold is partially pre-built
- scaffold nodes cannot be modified or removed
- maximum node count is capped

### 2. Output Constraints

These constrain what the topology must achieve behaviorally.

For this example:

- error rate must stay under `10%`
- throughput must stay above `100 req/s`
- invariant violations must be zero
- no node may pin at full saturation

### 3. Resource and Budget Constraints

These constrain how expensive or overbuilt the solution can become.

For this example:

- maximum total node count
- maximum total workers
- optional future budget-point model

### 4. Structural Invariants

These constrain the acceptable solution family without requiring one frozen graph.

For this example:

- there must be an ingress tier
- there must be a service-processing tier
- there must be a durable primary store
- there must be at least one read-scaling mechanism
- there must be no direct client-to-database shortcut

### 5. Interaction Constraints

These constrain how the student can explore and what is shown while doing so.

For this example:

- `PRACTICE` allows live testing and live rubric feedback
- `ASSIGNMENT` allows only a small number of dry runs
- full traces and raw suite details are withheld from student modes

### Anti-goals

This example explicitly avoids:

- exact topology snapshot comparison
- grading by visual layout or node positions
- exposing every simulator component
- hidden "gotcha" constraints that are unrelated to the lesson
- forcing both `api-gateway` and `load-balancer-l7` unless the question is about their distinction

---

## Worked Environment Design

### 1. Environment profile injection and runtime gating

### Proposed host payload

The host should inject this problem through the existing launch seam as a single payload containing:

```ts
interface LaunchContextPayload {
  questionPackage: QuestionPackage
  environmentProfile: EnvironmentProfile
  priorAttempt?: AttemptState | null
}
```

### Example `PRACTICE` profile

```json
{
  "mode": "PRACTICE",
  "visibility": {
    "prompt": true,
    "scaffoldSourceNodes": true,
    "gradingSuiteDetails": true,
    "liveMetrics": true,
    "rubricChecks": "LIVE_DURING_BUILD"
  },
  "capabilities": {
    "editPaletteList": [
      "load-balancer-l7",
      "microservice",
      "in-memory-cache",
      "relational-db",
      "queue"
    ],
    "canEditScaffoldNodes": false,
    "canTriggerTestRuns": true,
    "maxTestRuns": null
  },
  "graded": false,
  "chromeDensity": "minimal"
}
```

### Example `ASSIGNMENT` profile

```json
{
  "mode": "ASSIGNMENT",
  "visibility": {
    "prompt": true,
    "scaffoldSourceNodes": true,
    "gradingSuiteDetails": false,
    "liveMetrics": false,
    "rubricChecks": "POST_SUBMIT_ONLY"
  },
  "capabilities": {
    "editPaletteList": [
      "load-balancer-l7",
      "microservice",
      "in-memory-cache",
      "relational-db",
      "queue"
    ],
    "canEditScaffoldNodes": false,
    "canTriggerTestRuns": true,
    "maxTestRuns": 3
  },
  "graded": true,
  "chromeDensity": "minimal"
}
```

### Example `AUTHOR` profile

```json
{
  "mode": "AUTHOR",
  "visibility": {
    "prompt": true,
    "scaffoldSourceNodes": true,
    "gradingSuiteDetails": true,
    "liveMetrics": true,
    "rubricChecks": "LIVE_DURING_BUILD"
  },
  "capabilities": {
    "editPaletteList": null,
    "canEditScaffoldNodes": true,
    "canTriggerTestRuns": true,
    "maxTestRuns": null
  },
  "graded": false,
  "chromeDensity": "full"
}
```

### Runtime gating map

| Surface | Gating rule in this example |
|---|---|
| `WorkspaceLayout` | stores `questionPackage`, `environmentProfile`, and `priorAttempt` from launch context |
| `LibrarySidebar` | filters to `editPaletteList` |
| `FlowCanvas` | locks scaffold nodes and edges, enforces max node count |
| `PropertiesPanel` | renders scaffold nodes read-only in student modes |
| `QuestionPanel` | hides or disables dry-run controls based on `canTriggerTestRuns` and `maxTestRuns` |
| `ResultsTray` | switches to curated student view in `PRACTICE` and `ASSIGNMENT` |

### 2. Palette allowlist and scaffold locks

### Question-level accepted solution family

At the content level, this question accepts the following component families:

- `api-endpoint`
- `api-gateway`
- `load-balancer-l7`
- `microservice`
- `in-memory-cache`
- `relational-db`
- `queue`

### Student-facing palette

The student does not need the entire family exposed as drag-and-drop tiles because the scaffold provides the ingress anchor.

| Surface | Exposed palette |
|---|---|
| `PRACTICE` | `load-balancer-l7`, `microservice`, `in-memory-cache`, `relational-db`, `queue` |
| `ASSIGNMENT` | same as `PRACTICE` |
| `AUTHOR` | full palette |

### Scaffold

This problem should use a partial scaffold containing:

- locked `client`
- locked `api-gateway`
- locked edge `client -> api-gateway`

### Locked IDs

```json
{
  "lockedNodeIds": ["client", "api-gateway"],
  "lockedEdgeIds": ["e-client-gateway"],
  "canModifyScaffold": false,
  "canRemoveScaffoldNodes": false
}
```

Rationale:

- The problem is not about whether the system needs a client or an API gateway.
- The problem begins after ingress.
- Locking these nodes reduces variance without forcing one exact solution beyond the intended lesson.

### 3. Curated results and feedback timing

### Curated results

In student modes, the results surface should show only:

- global throughput
- global error rate
- global p99 latency
- service-tier utilization
- cache throughput and utilization
- read-replica throughput and utilization
- primary DB throughput and utilization
- order-events queue throughput and utilization

### Hide in student modes

- raw trace explorer
- full per-edge debugging
- entire suite case definitions in `ASSIGNMENT`
- full author diagnostics

### Feedback timing

| Mode | Dry-run feedback | Submit feedback |
|---|---|---|
| `PRACTICE` | live metrics + live rubric checks | full summary + explanation |
| `ASSIGNMENT` | curated metrics only, limited runs | post-submit rubric only |
| `AUTHOR` | full live everything | full author view |

### 4. Structural invariant checks

These are proposed checks for the problem family. They are deliberately broad.

| Check ID | Rule | Why it exists | Canonical solution status |
|---|---|---|---|
| `has-router-tier` | at least one `load-balancer-l7` downstream of ingress | avoids all traffic collapsing into a single service node | pass |
| `has-service-tier` | at least two `microservice` nodes | enforces actual service fan-out under the load profile | pass |
| `has-durable-primary` | at least one `relational-db` with `replicationRole = primary` | ensures durable writes | pass |
| `has-read-scaling` | at least one `in-memory-cache` or one replica read path | aligns with 80:20 read-heavy traffic | pass |
| `has-async-post-write-path` | `POST` traffic also reaches a `queue` asynchronously | models order-event publication after writes | pass |
| `no-client-db-shortcut` | no direct path from source to database bypassing compute | prevents degenerate solutions | pass |
| `no-write-to-replica` | no `POST` edge to a replica-only node | preserves durability semantics | pass |

These are not yet the engine's live grading mechanism. They are the proposed structural layer that should sit alongside verdict-based grading.

### 5. Resource and budget constraints

### Concrete first-cut constraints

```json
{
  "maxNodeCount": 10,
  "maxTotalWorkers": 1200
}
```

### Why these numbers

The canonical solution uses:

- `10` nodes
- `17` edges
- `1152` total workers

That leaves:

- `0` spare nodes under a `10`-node cap
- `48` worker headroom under a `1200`-worker cap

This creates a real design box without making the question brittle.

### Budget-scope note

Today `maxTotalWorkers` is naturally defined over the whole topology. Pedagogically, a later refinement may be needed:

```ts
type BudgetScope = 'all-nodes' | 'student-added-only'
```

If the scaffold becomes more substantial, counting scaffold-owned workers against the student can become unfair.

### 6. Editorial and progression surfaces

After solve, the learner should see:

- what the accepted architecture family was
- why the read path used cache plus read-replica
- why the write path used primary DB plus async queue
- why the topology did not need more exotic components

### Suggested editorial framing

1. Start with ingress and fan-out.
2. Split read-heavy traffic from durable writes.
3. Use a cache for common reads.
4. Send misses to a replica, not the primary.
5. Send writes to the primary.
6. Publish order events asynchronously after writes.

### Progression after this problem

Good next problems:

- remove the cache and repair the read path
- survive a primary DB failure
- fit the same design under a tighter worker budget
- compare `api-gateway` vs `load-balancer-l7` as a focused router-choice problem

---

## Canonical Solution Topology

### Source of truth

Canonical answer topology:

- [answer-order-platform.topology.json](../../answer-order-platform.topology.json)

### Text diagram

```text
Client
  -> API Gateway
  -> Order Service LB
  -> Order Service A / B / C

Order Service A / B / C
  -> Redis Cache        (GET_HIT)
  -> Read Replica       (GET_MISS)
  -> Primary DB         (POST)
  -> Order Events Queue (POST, async)
```

### Workload config

```json
{
  "sourceNodeId": "client",
  "pattern": "poisson",
  "baseRps": 250,
  "spike": {
    "spikeTime": 30000,
    "spikeRps": 1000,
    "spikeDuration": 5000
  },
  "requestDistribution": [
    { "type": "GET_HIT", "weight": 0.68, "sizeBytes": 1024 },
    { "type": "GET_MISS", "weight": 0.12, "sizeBytes": 1024 },
    { "type": "POST", "weight": 0.2, "sizeBytes": 2048 }
  ]
}
```

### Node config table

| Node ID | Type | Role | Label | Workers | Capacity | Processing | Timeout (ms) | Extra config |
|---|---|---|---|---:|---:|---|---:|---|
| `client` | `api-endpoint` | `source` | Client / User | - | - | - | - | `{}` |
| `api-gateway` | `api-gateway` | `router` | API Gateway | 160 | 16000 | `constant:1` | 800 | `{"latencyP99":20,"availabilityTarget":0.999,"errorBudget":0.001}` |
| `order-lb` | `load-balancer-l7` | `router` | Order Service LB | 240 | 24000 | `constant:0.5` | 800 | `{}` |
| `order-svc-1` | `microservice` | `processor` | Order Service A | 36 | 1400 | `log-normal:mu=1.75, sigma=0.22` | 900 | `{"cpu":8,"memory":4096,"replicas":1}` |
| `order-svc-2` | `microservice` | `processor` | Order Service B | 36 | 1400 | `log-normal:mu=1.75, sigma=0.22` | 900 | `{"cpu":8,"memory":4096,"replicas":1}` |
| `order-svc-3` | `microservice` | `processor` | Order Service C | 36 | 1400 | `log-normal:mu=1.75, sigma=0.22` | 900 | `{"cpu":8,"memory":4096,"replicas":1}` |
| `redis-cache` | `in-memory-cache` | `storage` | Redis Cache | 300 | 30000 | `constant:0.8` | 120 | `{"cacheHitRate":0.85,"ttlSeconds":60}` |
| `read-replica` | `relational-db` | `storage` | Read Replica | 80 | 8000 | `constant:2.5` | 250 | `{"replicationRole":"replica"}` |
| `primary-db` | `relational-db` | `storage` | Primary DB | 64 | 6000 | `log-normal:mu=1.5, sigma=0.18` | 300 | `{"replicationRole":"primary"}` |
| `order-events` | `queue` | `storage` | Order Events Queue | 200 | 50000 | `constant:1` | 200 | `{}` |

### Edge config table

| Edge ID | Source | Target | Mode | Protocol | Condition | Latency (ms) | Bandwidth | Max concurrency |
|---|---|---|---|---|---|---:|---:|---:|
| `e-client-gateway` | `client` | `api-gateway` | `synchronous` | `https` | - | 12 | 1000 | 5000 |
| `e-gateway-lb` | `api-gateway` | `order-lb` | `synchronous` | `grpc` | - | 1 | 10000 | 8000 |
| `e-lb-order-1` | `order-lb` | `order-svc-1` | `synchronous` | `grpc` | - | 0.8 | 10000 | 6000 |
| `e-lb-order-2` | `order-lb` | `order-svc-2` | `synchronous` | `grpc` | - | 0.8 | 10000 | 6000 |
| `e-lb-order-3` | `order-lb` | `order-svc-3` | `synchronous` | `grpc` | - | 0.8 | 10000 | 6000 |
| `e-order1-cache` | `order-svc-1` | `redis-cache` | `conditional` | `tcp` | `request.type === "GET_HIT"` | 0.5 | 10000 | 8000 |
| `e-order2-cache` | `order-svc-2` | `redis-cache` | `conditional` | `tcp` | `request.type === "GET_HIT"` | 0.5 | 10000 | 8000 |
| `e-order3-cache` | `order-svc-3` | `redis-cache` | `conditional` | `tcp` | `request.type === "GET_HIT"` | 0.5 | 10000 | 8000 |
| `e-order1-replica` | `order-svc-1` | `read-replica` | `conditional` | `tcp` | `request.type === "GET_MISS"` | 1.5 | 10000 | 4000 |
| `e-order2-replica` | `order-svc-2` | `read-replica` | `conditional` | `tcp` | `request.type === "GET_MISS"` | 1.5 | 10000 | 4000 |
| `e-order3-replica` | `order-svc-3` | `read-replica` | `conditional` | `tcp` | `request.type === "GET_MISS"` | 1.5 | 10000 | 4000 |
| `e-order1-primary` | `order-svc-1` | `primary-db` | `conditional` | `tcp` | `request.type === "POST"` | 2 | 10000 | 4000 |
| `e-order2-primary` | `order-svc-2` | `primary-db` | `conditional` | `tcp` | `request.type === "POST"` | 2 | 10000 | 4000 |
| `e-order3-primary` | `order-svc-3` | `primary-db` | `conditional` | `tcp` | `request.type === "POST"` | 2 | 10000 | 4000 |
| `e-order1-events` | `order-svc-1` | `order-events` | `asynchronous` | `amqp` | `request.type === "POST"` | 2 | 10000 | 10000 |
| `e-order2-events` | `order-svc-2` | `order-events` | `asynchronous` | `amqp` | `request.type === "POST"` | 2 | 10000 | 10000 |
| `e-order3-events` | `order-svc-3` | `order-events` | `asynchronous` | `amqp` | `request.type === "POST"` | 2 | 10000 | 10000 |

---

## Evaluation Philosophy

This example follows a three-layer evaluation model.

### Layer 1: Behavioral correctness

The first question is:

Does the topology satisfy the simulator-facing SLOs under the grading scenarios?

For this example, the current rubric checks:

- `summary.errorRate < 0.1`
- `summary.throughput >= 100`
- `invariantViolations.count == 0`
- `perNode.maxUtilization < 1`

### Layer 2: Coarse structural validity

The second question is:

Is the student solving the intended architectural problem, or routing around it?

For this example, the proposed checks are:

- must have router tier
- must have service tier
- must have durable primary
- must have read-scaling mechanism
- must have async event publication
- must not bypass the compute tier

### Layer 3: Resource discipline

The third question is:

Did the student stay inside the intended design box?

For this example:

- node count must be `<= 10`
- total workers must be `<= 1200`

The long-term version of this layer can incorporate a real cost model, but the example does not require that to be useful today.

---

## Paper Evaluation

This section shows how to reason about the problem before implementation. The simulator verdict remains authoritative. The paper math is a sanity-check layer.

### 1. Request-mix calculations

### Baseline traffic mix

Base rate = `250 req/s`

- `GET_HIT = 250 * 0.68 = 170 req/s`
- `GET_MISS = 250 * 0.12 = 30 req/s`
- `POST = 250 * 0.20 = 50 req/s`

Assuming even load-balance across three order services:

- each service receives `250 / 3 = 83.33 req/s`
- each service sees about `56.67 GET_HIT`, `10 GET_MISS`, `16.67 POST`

### Peak traffic mix

Peak rate = `1000 req/s`

- `GET_HIT = 1000 * 0.68 = 680 req/s`
- `GET_MISS = 1000 * 0.12 = 120 req/s`
- `POST = 1000 * 0.20 = 200 req/s`

Assuming even load-balance across three order services:

- each service receives `1000 / 3 = 333.33 req/s`
- each service sees about `226.67 GET_HIT`, `40 GET_MISS`, `66.67 POST`

### 2. Rough capacity calculations

The following is a back-of-envelope estimate using:

`approx capacity (req/s) = workers * 1000 / mean_service_time_ms`

For log-normal distributions, use:

`mean = exp(mu + sigma^2 / 2)`

### Approximate capacities

| Component | Mean service ms | Workers | Approx capacity req/s |
|---|---:|---:|---:|
| API Gateway | 1.000 | 160 | 160000.00 |
| Order Service LB | 0.500 | 240 | 480000.00 |
| One Order Service | 5.896 | 36 | 6106.29 |
| Redis Cache | 0.800 | 300 | 375000.00 |
| Read Replica | 2.500 | 80 | 32000.00 |
| Primary DB | 4.555 | 64 | 14050.85 |
| Order Events Queue | 1.000 | 200 | 200000.00 |

### Headroom interpretation

Under the peak split:

- each order service sees about `333 req/s`
- one order service can theoretically process about `6106 req/s`
- the primary DB sees about `200 POST req/s`
- the primary DB can theoretically process about `14050 req/s`

This suggests large headroom even before running the simulator.

### 3. Actual simulator verdicts

The following results were captured from the current engine with:

- baseline verdict on [answer-order-platform.topology.json](../../answer-order-platform.topology.json)
- peak verdict on the same topology with `workload.baseRps = 1000`
- question grade on [sample-question.example.json](../../sample-question.example.json)

### Baseline verdict summary

| Metric | Value |
|---|---:|
| Simulation duration | `60000 ms` |
| Warmup duration | `5000 ms` |
| Events processed | `252301` |
| Total requests | `20714` |
| Post-warmup successful requests | `18956` |
| Throughput | `344.6545 req/s` |
| Error rate | `0` |
| p50 latency | `24.448 ms` |
| p99 latency | `31.104 ms` |
| SLO breaches | `0` |
| Invariant violations | `0` |
| Max node utilization | `0.0135063` |

### Peak verdict summary

| Metric | Value |
|---|---:|
| Simulation duration | `60000 ms` |
| Warmup duration | `5000 ms` |
| Events processed | `1027501` |
| Total requests | `84406` |
| Post-warmup successful requests | `77250` |
| Throughput | `1404.5455 req/s` |
| Error rate | `0` |
| p50 latency | `24.448 ms` |
| p99 latency | `31.104 ms` |
| SLO breaches | `0` |
| Invariant violations | `0` |
| Max node utilization | `0.0550770` |

### Key per-node signals

#### Baseline

| Node | Throughput | Utilization | Error rate | p99 latency |
|---|---:|---:|---:|---:|
| API Gateway | `344.8182` | `0.0015488` | `0` | `1.004 ms` |
| Order Service A | `115.5455` | `0.0134811` | `0` | `9.536 ms` |
| Order Service B | `114.3455` | `0.0135063` | `0` | `9.408 ms` |
| Order Service C | `114.9273` | `0.0134916` | `0` | `9.664 ms` |
| Redis Cache | `170.6545` | `0.0000677` | `0` | `0.804 ms` |
| Read Replica | `28.4545` | `0.0008938` | `0` | `2.512 ms` |
| Primary DB | `48.5636` | `0.0034574` | `0` | `6.816 ms` |
| Order Events Queue | `145.6909` | `0.0002437` | `0` | `1.004 ms` |

#### Peak

| Node | Throughput | Utilization | Error rate | p99 latency |
|---|---:|---:|---:|---:|
| API Gateway | `1405.0545` | `0.0063050` | `0` | `1.004 ms` |
| Order Service A | `469.9091` | `0.0549824` | `0` | `9.664 ms` |
| Order Service B | `467.5818` | `0.0550770` | `0` | `9.664 ms` |
| Order Service C | `467.4909` | `0.0549604` | `0` | `9.664 ms` |
| Redis Cache | `688.7636` | `0.0002765` | `0` | `0.804 ms` |
| Read Replica | `120.1818` | `0.0037495` | `0` | `2.512 ms` |
| Primary DB | `198.6545` | `0.0141643` | `0` | `6.816 ms` |
| Order Events Queue | `596.0727` | `0.0009954` | `0` | `1.004 ms` |

### 4. Current rubric scoring

The current question rubric has four checks across two cases, for `8` total boolean contract rows.

### Baseline case

| Check | Threshold | Actual | Result |
|---|---:|---:|---|
| Error rate | `< 0.1` | `0` | pass |
| Throughput | `>= 100` | `344.6545` | pass |
| Invariant violations | `== 0` | `0` | pass |
| Max node utilization | `< 1` | `0.0135063` | pass |

### Peak case

| Check | Threshold | Actual | Result |
|---|---:|---:|---|
| Error rate | `< 0.1` | `0` | pass |
| Throughput | `>= 100` | `1395.52` in grade run, `1404.5455` in direct verdict run | pass |
| Invariant violations | `== 0` | `0` | pass |
| Max node utilization | `< 1` | `0.0544904` in grade run, `0.0550770` in direct verdict run | pass |

### Why the grade-run numbers differ slightly

The direct peak verdict and the question-grade peak case were run through different entry paths and seeds / suite settings. They are materially consistent for product purposes:

- both show `0` error rate
- both show throughput far above the `100 req/s` threshold
- both show max utilization far below saturation

### Final contract

- total tests: `8`
- passed tests: `8`
- overall result: `PASS`

### 5. Proposed structural evaluation

If the structural layer were implemented, this canonical solution would pass as follows:

| Structural check | Evidence |
|---|---|
| has router tier | `order-lb` exists downstream of ingress |
| has service tier | `order-svc-1`, `order-svc-2`, `order-svc-3` exist |
| has durable primary | `primary-db` has `replicationRole = primary` |
| has read-scaling path | `redis-cache` handles hits, `read-replica` handles misses |
| has async event path | `POST` traffic also goes to `order-events` asynchronously |
| no client-db shortcut | no edge from `client` or `api-gateway` directly to a DB node |
| no write-to-replica | all `POST` conditions route to `primary-db`, not `read-replica` |

### 6. Proposed budget evaluation

| Resource | Threshold | Actual | Result |
|---|---:|---:|---|
| Node count | `<= 10` | `10` | pass |
| Total workers | `<= 1200` | `1152` | pass |

This gives a clean example of layered evaluation:

- behavioral checks pass
- structural checks pass
- resource checks pass

---

## Editorial and Progression Surfaces

### Editorial notes for the learner

- The architecture separates ingress, service logic, read scaling, durable writes, and asynchronous event publication.
- The read-heavy `80:20` workload justifies cache and replica usage.
- The write path remains durable because all `POST` traffic goes to the primary DB.
- The queue is not used for durability itself. It is used for asynchronous downstream work after the durable write.
- The solution succeeds because it is appropriately scoped. It does not introduce unrelated infrastructure.

### Progression ideas

Immediate follow-up problems:

1. Remove the cache and ask the learner to recover read performance.
2. Remove the read replica and ask the learner to protect the primary.
3. Add a hard worker budget and force a cheaper variant.
4. Inject a DB failure and require graceful degradation.
5. Convert the problem into a router-choice comparison between gateway-first and balancer-first designs.

---

## Implementation Notes

This worked example intentionally goes beyond what the engine enforces today.

### Already supported today

- `QuestionPackage`
- `AttemptState`
- verdict-based grading
- question launch context and submit seam
- canonical topology answer

### Defined in this document but not fully implemented

- environment profile injection into runtime
- palette allowlist enforcement
- scaffold locks in student modes
- curated student result surfaces
- structural invariant checks
- budget scope refinements

### Why this document matters

It provides a pre-implementation reference for design decisions. Before building the missing runtime and grading slices, the team can evaluate whether:

- the environment feels bounded enough
- the canonical solution family is too wide or too narrow
- the rubric is too weak or too strict
- the structural layer adds signal without turning into graph nitpicking
- the budget layer creates meaningful tradeoffs

That is the point of the exercise: decide the product and pedagogy on paper before freezing the implementation.

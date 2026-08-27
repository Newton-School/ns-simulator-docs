# System-Design Question Families → Simulation Bottlenecks

> A taxonomy that maps every class of system-design interview question to the
> **underlying simulation bottleneck** it exercises, the architectural **fix**, and -
> crucially - **what the ns-simulator can actually model today**. Part 2 is the concrete
> V1 action plan for the 9 shipped questions.
>
> Companion to `node-capability-matrix.md` (per-node physics + trait roadmap),
> `trait-integration-guide.md` (how to add the missing physics), and the budget docs.

## Legend - simulator status

| Mark | Meaning |
|------|---------|
| ✅ **Physics** | The bottleneck is *simulated* - a real run saturates and the fix relieves it |
| 🟡 **Structural/semantic** | Graded by topology/access-pattern rules or justification, **not** by distinct physics |
| ❌ **Deferred (V2)** | No physics and no meaningful grading yet - needs a new trait (see the matrix) |

The gap between ✅ and 🟡 is the whole roadmap: many "correct" answers are currently
*graded* right but not *felt* in the simulation, because the differentiating trait
(`storageProfile`, `broadcastFanout`, `connectionPool`, …) isn't built.

---

## What a domain does (and why)

> A **domain** is a *scoping boundary*. It declares which bottleneck a question is
> about, so the platform can strip away every lever and concern that belongs to other
> bottlenecks - leaving a problem small enough to have **one thing that breaks and one
> family of fixes**. It doesn't describe the question; it **constrains** it.

**What it isolates - three things:**

1. **The concern space** - "this question is about read-heavy saturation," not "about
   everything a real system faces at once."
2. **The available levers** - the student can only reach for tools that belong to the
   declared domain(s), so they can't accidentally (or deliberately) solve it with a move
   from a domain they haven't been taught.
3. **The grading axis** - points land on the intended skill, not on incidental choices.

**Why that gives teachable granularity.** Real systems fire *every* bottleneck at once -
overwhelming for a learner. A domain is a teaching scaffold: it holds the other
bottlenecks fixed (or removes them) so the student builds *one* clean mental model -
"when nodes saturate on reads, I cache" - before facing the messy composite. One
bottleneck → one lesson → one verifiable fix.

**How the isolation is enforced.** This is where a domain stops being a label and becomes
mechanism - it drives four switches:

| Switch | How it isolates | Status |
|--------|-----------------|--------|
| **Edge lock** | Removes the *network* lever from a compute/storage question, so pipe-tuning can't stand in for the real fix | ✅ **wired** (`canEditEdgesForQuestion`) |
| Palette subset | Hides nodes from unrelated domains, so the toolbox itself scopes the problem | 🎯 designed |
| Traits / physics | Only the relevant bottleneck actually saturates in the sim | 🎯 designed |
| Grading emphasis | Weights the intended axis | 🎯 designed |

The **edge-lock is the clearest live proof**: a `compute` question locks edges
*specifically so a student can't escape the "add a cache" lesson by inflating a pipe* - a
lever that belongs to the `network` domain. That is isolation, enforced. (See
`canEditEdgesForQuestion`: edges unlock only when `domains` includes `network`.)

**The one nuance.** Isolation is to a *declared set*, not always a single domain. A
beginner question isolates one (`['compute']`); an advanced one **composes** a couple
(`['compute','storage']` - news-feed) once the student holds each model separately. So a
domain isn't "always exactly one topic" - it's "exactly *these* topics and nothing else."
The progression is **isolate to learn → compose to master**.

---

## `domains` is a first-class question field

A question's bottleneck **domains** are **authored on the QuestionPackage**, not inferred -
so the platform can switch behavior off them (and so a question can't be silently mis-tagged).
A question may exercise **more than one** domain (news-feed, ride-hailing and url-shortener
are all `compute` *and* `storage`), so it is a set, not a single value.

- **Field:** `domains?: Array<'compute' | 'storage' | 'network' | 'resilience' | 'correctness' | 'cost'>`
  on `question.json` (and in the Django `SIMULATOR_CONFIG` row). Optional for back-compat but
  non-empty when present; V1 uses `compute` / `storage` only.
- **Distinct from** `type` (task shape) and `workloadCategory` (injected load).
- **Drives switching:** palette subset, the edge-config lock policy (e.g. a `network`
  question would *unlock* edges because they're the lesson), which traits/physics apply,
  and grading emphasis. With multiple domains, these compose (union of palettes, etc.).
- **Authoring guard (advisory):** `validateAuthoredQuestion` checks **each** declared domain
  against how the question is graded - `compute` expects a simulation check or a
  `forbidUnjustified` judgment; `storage` expects `storageFit` or `fanout`; `correctness`
  expects `justify`; `network`/`resilience`/`cost` warn as V2 (no physics yet). Missing or
  duplicate domains warn too. This is why a question is only tagged `storage` when it actually
  carries a `storageFit`/`fanout` criterion.
- **Naming (naming history):** earlier drafts called this `family` (singular). Renamed to the
  plural, controlled-array `domains` so one question can span several bottleneck domains.

| Axis | Field | Cardinality | Answers |
|------|-------|-------------|---------|
| Task shape | `type` | one | `open-build`, `optimize`, `fix`, … |
| Injected load | `workloadCategory` | one | `read-heavy`, `write-heavy`, … |
| **Bottleneck domain** | **`domains`** | **one or more** | `compute`, `storage`, `network`, … |

---

## Concept taught per question (V1 bank)

What each shipped question actually *teaches* - the single concept it isolates, mapped to
its domain(s) and the criterion that grades it. This is the lesson-level view: read it as
"`<question>` teaches `<concept>`". The bold names are the exact `concepts` slugs on each
`question.json` (a first-class, machine-readable field, finer-grained than `domains`).

| Question | Concept taught | Domain(s) | The lesson in one line | Graded by |
|----------|----------------|-----------|------------------------|-----------|
| `async-sla` | **async-decoupling** | compute | Put a queue + workers between a fast ingest and a slow downstream so spikes don't collapse the request path (ack-and-release). | `guardedPath` (ingest→queue) + p99 |
| `cache-placement` | **cache-placement** | compute | Place an in-memory cache *between* the service and the DB to absorb read-hot traffic. | `placement` + p99 |
| `cargo-cult-cdn` | **justified-omission** (anti-cargo-cult) | compute | Don't add a CDN for dynamic, per-user (non-cacheable) responses - defend omission as much as inclusion. | `forbidUnjustified` |
| `url-shortener` | **read-cache + store-fit** | compute + storage | Read-heavy lookup: cache in front, and a KV store (not relational) for the short→long mapping. | `storageFit` + p99 |
| `news-feed` | **fan-out-on-write + read-cache** | compute + storage | Fan a post out to follower timelines on write, and cache the read path to hit the feed p99. | `fanout` + `storageFit` + p99 |
| `ride-hailing` | **store-fit + geo-cache-placement** | compute + storage | Right store per data type (payments ≠ geospatial), with a geospatial cache for match reads. | `storageFit` + `placement` + p99 |
| `messaging-fanout` | **pubsub-fanout** | storage | Deliver each event to N *independent* consumers with a broker (1→N), not a work-queue (1-of-N). | `fanout` |
| `sensor-store` | **store-fit** (time-series) | storage | Swap a relational DB for a time-series/NoSQL store to sustain continuous high-volume writes. | `storageFit` + throughput |
| `web-crawler` | **dedup-gate (idempotent pipeline)** | compute | Route every enqueue through a dedup index so pages aren't re-crawled; order the frontier→fetch→process pipeline. | `guardedPath` + `placement` + throughput |

> Every one of these is a **single-concept lesson** (some composing two domains). The three
> deferred questions add the V2 concepts: `payment-system` → **idempotency / exactly-once**,
> `ticketmaster` → **contention / distributed-lock**, `rate-limiter` → **shared-state rate
> limiting** - all `correctness`/`resilience` domains awaiting their traits.

---

## Part 1 - The exhaustive master list

### Family 1 - Compute & Capacity (node-bottlenecks)
*Plenty of bandwidth; the processing nodes melt down.*

| Bottleneck | The fix | Simulator mechanism | Status | Real-world questions |
|------------|---------|---------------------|--------|----------------------|
| **Read-heavy saturation** - repetitive reads overwhelm the store | `in-memory-cache` in front of the store | `cache` trait (hit/miss via `cacheHitRate`) relieves store `queue.workers` saturation | ✅ Physics | URL shortener, Newsfeed, Key-value store |
| **Synchronous blocking** - fast web tier waits on slow downstream, times out | `queue`/`message-broker` + scalable `batch-worker`s | `ackAndRelease` (async decouple) + worker `queue.workers` | ✅ Physics | Video transcoding, Async report generator, Web crawler frontier |
| **CPU / thread contention** - work too heavy for one pool | Scale out (`replicas`/`workers`) or add a load balancer | `queue.workers` is a **proxy**; true CPU/thread-pool model needs `computeContention` | 🟡 Structural | LLM serving gateway, Collaborative editor |

### Family 2 - Storage & State (data-bottlenecks)
*Database choice, sharding, access patterns.*

| Bottleneck | The fix | Simulator mechanism | Status | Real-world questions |
|------------|---------|---------------------|--------|----------------------|
| **Write-throughput saturation** - relational IOPS lock up under ingest | Swap to `time-series-db` / `nosql-db` | Graded by `storageFit` (access pattern) + `throughput` rubric; stores are **physically identical** until `storageProfile` | 🟡 Structural/semantic | IoT ingestion, Metrics/logging platform |
| **Broadcast / fan-out exhaustion** - one event to millions | `pub-sub` with true 1→N | Graded by `fanout` criterion (edge count); the sim does **not** actually broadcast until `broadcastFanout` | 🟡 Structural | Push notifications, Massive chat |
| **Scan vs. lookup penalty** - full table scans | `search-index` / spatial index | Graded by `storageFit` (point-lookup); `search-index` is physically generic until `fanoutQuery` | 🟡 Semantic | Product search, Proximity service |
| **Storage tiering & cost** - petabytes on SSD is expensive | Blobs → `object-storage`, metadata → DB | Needs `tieredRetrieval` + a real budget model | ❌ Deferred (V2) | Google Drive / Dropbox |

### Family 3 - Network & Edge (connection-bottlenecks)
*Nodes are fine; the pipes and connections choke.* **Entirely deferred - no edge physics yet.**

| Bottleneck | The fix | Needs trait | Status | Real-world questions |
|------------|---------|-------------|--------|----------------------|
| **Connection-pool / port exhaustion** | Multiplexer, scale NATs | `connectionPool`, `capacityLimit` | ❌ Deferred (V2) | Multiplayer gaming, WebRTC signaling |
| **Bandwidth / pipe saturation** | `cdn` / edge caching | `capacityLimit` + traffic-weighted edges | ❌ Deferred (V2) | Global CDN, Netflix delivery |
| **Speed-of-light (geo-latency)** | Multi-region routing / geo-sharding | `geoLatency` | ❌ Deferred (V2) | Spanner, Active-active finance |

> This is exactly why edge config is being **locked** for V1 (Part 2 §2): the physics a
> student would reason about here doesn't exist yet, so exposing `bandwidth` /
> `maxConcurrentRequests` only invites brute-forcing.

### Family 4 - Resilience & Chaos (fault-bottlenecks)

| Bottleneck | The fix | Simulator mechanism | Status | Real-world questions |
|------------|---------|---------------------|--------|----------------------|
| **Cascading failure / retry storms** | `circuit-breaker` + `rate-limiter` + bounded retries | `circuitBreaker`, `rateLimiter`, and caller-owned `retryBackoff` now run at runtime; dedicated `rate-limiter` and `circuit-breaker-controller` nodes are first-class palette/catalog nodes | ✅ Physics | API rate limiter, HA gateway |
| **Data-center failover** | DNS steering, active-passive | Edge/scenario fault injection exists; `dnsRoutingPolicy` partial | 🟡 Partial | Payment DR |

### Family 5 - Correctness (concurrency-bottlenecks)
*Strict distributed guarantees the physics engine cannot measure.*

| Constraint | The fix | Simulator mechanism | Status | Real-world questions |
|------------|---------|---------------------|--------|----------------------|
| **Contention / double-booking** | `distributed-lock` or consistent `relational-db` | `lockLease` now models per-key lease acquire/contention/TTL; grading still uses `guardedPath` + structural + **justification** because correctness is not a single summary metric | ✅ Physics + justification | Ticketmaster, Hotel booking |
| **Exactly-once / idempotency** | `idempotency-manager` / append-only ledger | `idempotencyDedup` now models keyed duplicate suppression on retryable write paths; grading still uses `guardedPath` + justification | ✅ Physics + justification | Payment gateway (Stripe) |

> The deferred correctness questions (`payment-system`, `ticketmaster`,
> `rate-limiter`) are no longer blocked on missing lock/retry/idempotency physics.
> What still remains is richer ledger/reconciliation/exactly-once approximation,
> not the basic runtime behavior of the guard nodes themselves.

### Family 6 - Meta-constraint

| Constraint | The fix | Status |
|------------|---------|--------|
| **Cost-optimization** - fix the bottleneck within a budget cap | Elegant architecture (1 cache) over brute force (10 replicas) | ❌ Deferred (V2) - the V1 heuristic couldn't discriminate; full redesign in `budget-v2-design.md` |

---

## Part 2 - V1 action plan for the 9 existing questions

The 9 shipped questions fall **strictly in Family 1 (Compute) and Family 2 (Storage)**.
Because the simulator has no network/backpressure traits yet, treating them as pure
**node-bottleneck** questions is the correct V1 choice.

### Question → family map

| Question | Family / bottleneck | Graded by |
|----------|---------------------|-----------|
| `url-shortener` | F1 read-heavy | Σ p99 + storageFit |
| `cache-placement` | F1 read-heavy | placement + Σ p99 |
| `news-feed` | F1 read-heavy + F2 fan-out | Σ p99 + fanout + storageFit |
| `ride-hailing` | F1 read-heavy (geo cache) + F2 store-fit | Σ p99 + storageFit + placement |
| `cargo-cult-cdn` | F1/F3 judgment (don't over-build) | forbidUnjustified + justify |
| `messaging-fanout` | F2 broadcast/fan-out | fanout (structural) |
| `sensor-store` | F2 write-throughput | storageFit + Σ throughput |
| `web-crawler` | F1 sync-blocking pipeline | guardedPath + Σ throughput |
| `async-sla` | F1 sync-blocking | structural + Σ p99 |

### The 4 steps

**1. Fix the edge defaults (generator).** Today every edge is `bandwidth: 1,000,000`
(1 Tbps) and `maxConcurrentRequests: 200,000` - absurd for ~3000 rps. But **do not** drop
concurrency to ~1,000: under saturation, in-flight ≈ `rps × timeout` (thousands), so a low
cap would bind and produce **false edge rejections**, turning the gamed store-saturation
lesson into an edge-rejection artifact. Set:
  - `bandwidth: 1000` (1 Gbps - a real link; payload rate is capped by source rps, so it
    stays non-binding even under saturation),
  - `maxConcurrentRequests: 50000` (headroom above the saturated worst-case `rps × timeout`,
    so **nodes remain the sole bottleneck**).
  Change `scripts/gen-question-fixtures.ts` `edge()` defaults, regenerate, and **re-validate
  all 9** - outcomes must be identical (edges stay non-binding).

**2. Lock the edge UI in ASSIGNMENT mode (UX).** Students shouldn't reason about bandwidth
or pools yet - that physics isn't built, and exposing it invites brute-forcing. When
`environmentProfile.mode === 'ASSIGNMENT'`, disable edge selection / hide the edge config
panel. The student's only levers: drag nodes, change storage types, scale workers/replicas.

**3. Strip the budget (done).** `budget` already removed from `async-sla` / `sensor-store`;
`BudgetMeter` auto-hides (renders only when a question declares a budget). V2 redesign in
`budget-feature-implementation-v3.md`.

**4. Confirm each rubric grades three axes.** Every V1 question should carry:
  - **Simulation:** `summary.latency.p99` or `summary.throughput` - proves the node
    bottleneck was actually relieved.
  - **Semantic:** `storageFit` / `placement` - proves the architectural choice (cache
    placed, right store) is correct.
  - **Structural:** `requires_component` / `guardedPath` - proves required components exist
    and are on the path (e.g. a broker for async decoupling).

### Status of the 4 steps

| Step | State |
|------|-------|
| 1. Edge defaults (1 Gbps / 50k) | **done** - `edge()` defaults set to `bandwidth: 1000` / `maxConcurrentRequests: 50000`; all 9 regenerated + re-validated (outcomes identical, edges non-binding) |
| 2. Lock edge UI in ASSIGNMENT | **done** - new `canEditEdges` capability (AUTHOR/PRACTICE true, ASSIGNMENT false); edge config renders read-only (disabled fieldset + lock note) while edge *results* stay inspectable |
| 3. Strip budget + hide meter | **done** |
| 4. Three-axis rubric | **mostly done** - audit the 9 to confirm each has sim + semantic + structural |

> **Authoring artifacts.** The generator now also emits a domain-tagged Django-admin guide
> per question - `django-admin-assignment-<domains>.md` where `<domains>` is the domain set
> joined by `-` (e.g. `compute`, `storage`, or `compute-storage`) - derived from
> `question.json` (justify hidden for V1, budget omitted), alongside the existing
> hand-authored `django-admin-assignment.md`, which is left untouched. Stale domain-suffixed
> guides from a prior domain set are pruned on regenerate.

**Result:** the 9 V1 questions become a clean, gaming-resistant experience focused purely
on **node and data architecture**. Network, edge, resilience, correctness-physics, and cost
are cleanly deferred to V2 behind the traits catalogued in `node-capability-matrix.md`.

# Question Bank — `initial_game_state` for 12 archetypes

> Ready-to-paste **`QuestionPackage` JSON** for each canonical question. Paste one
> into a GAME question's **`initial_game_state`** field (see
> `authoring-a-simulator-game-question-runbook.md`). Each is built against the
> alignment contract in `question-simulation-alignment.md` and the grading model
> in `question-grading-model-and-anti-gaming.md`.
>
> **Authoring notes (read once):**
> - **Metric keys are real verdict paths:** `summary.latency.p99`,
>   `summary.errorRate`, `summary.throughput`, `invariantViolations.count`,
>   `perNode.<id>.utilization`. (NOT `summary.latencyP99Ms` — that never resolves.)
> - **Tractable RPS.** `prompt.scale` shows the *real-world* target (e.g. 200000);
>   `suite.workload.baseRps` uses a **representative** load the browser can run
>   (~2–5K rps) that still stresses the design. Size nodes + thresholds together.
> - **Read/write matters only when injected as typed traffic AND routed on type**
>   (`requestDistribution` + `condition: request.type === "read"`). A read-heavy
>   prompt with no typed routing does not exercise the cache.
> - **Performance vs correctness:** put a `simulation` rubric check only on things
>   the sim measures (latency/throughput/util). Correctness (exactly-once,
>   no-double-book, dedup) is graded by `structuralRules`/`semanticCriteria` +
>   `justify` — never a `simulation` check.
> - **`guardedPath` is for ALL-traffic guards** (rate-limiter→shared-cache,
>   payment→idempotency-store). It does *not* fit "reads-but-not-writes through a
>   cache" — that's a **simulation** obligation (the store saturates without it).

**Dimension legend** (per grading-model §3): FR · NFR(lat/thru/consistency/durability) ·
Scale · StorageFit · R:W · Fanout · Placement · Direction · Tradeoffs · Omission ·
Hot/Cold · Async/Sync · Cost.

---

## 1. URL Shortener — read-heavy, point-lookup
**Covers:** FR · NFR-latency · Scale · StorageFit · R:W. **Graded by:** Σ (p99 under injected 99:1) + S (storageFit) + J. **Sim helps:** yes (proven, alignment §9).

```json
{
  "version": "1.0", "id": "url-shortener", "title": "Design a URL shortener",
  "difficulty": "intermediate", "type": "open-build", "workloadCategory": "read-heavy",
  "prompt": {
    "text": "Design a URL shortener that stays fast under a read-heavy load. Reads (redirects) dominate writes ~99:1.",
    "functionalRequirements": ["Create a short code for a long URL (write path to a store)", "Redirect a short code to its long URL (read path)"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":100,"unit":"ms","description":"p99 redirect latency under 100ms"}],
    "scale": {"dau":50000000,"peakRps":200000,"readWriteRatio":99}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":12},
  "structuralRules": [{"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}],
  "semanticCriteria": [{"id":"store-fits-point-lookup","kind":"storageFit","description":"Short-code lookup is a point-lookup","accessPattern":"point-lookup","accept":["kv-store","nosql-db"],"partial":["in-memory-cache"],"antiPattern":["relational-db"],"points":3,"hardFail":true}],
  "justify": [{"id":"why-store","decision":"Why this store type for lookups at this scale?","boundTo":{"componentType":"kv-store"},"requires":{"choice":true,"number":true,"tradeoff":true}}],
  "suite": {"name":"url-shortener-suite","visibleToStudent":false,"cases":[{"id":"peak","description":"Read-heavy peak (injected 99:1)","workload":{"baseRps":2000,"requestDistribution":[{"type":"read","weight":0.99,"sizeBytes":256},{"type":"write","weight":0.01,"sizeBytes":512}]}}]},
  "rubric": {"id":"url-rubric","passThreshold":1,"checks":[
    {"id":"p99","kind":"simulation","description":"p99 under 100ms","metric":"summary.latency.p99","op":"<","value":100,"points":3},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 2. Feed / News — read-heavy, fan-out-on-write
**Covers:** FR · NFR-latency · Scale · R:W · Fanout · Hot/Cold. **Graded by:** Σ (read p99) + T (fanout to timelines) + S (cache) + J.

```json
{
  "version": "1.0", "id": "news-feed", "title": "Design a news feed",
  "difficulty": "intermediate", "type": "open-build", "workloadCategory": "read-heavy",
  "prompt": {
    "text": "Design a news feed. Reads dominate ~50:1; a write (post) must fan out to followers' timelines. Keep feed loads fast.",
    "functionalRequirements": ["Post an item (write, fan out to follower timelines)", "Load a follower's feed (read path, cacheable)"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":200,"unit":"ms","description":"p99 feed-load under 200ms"}],
    "scale": {"dau":10000000,"peakRps":50000,"readWriteRatio":98}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":14},
  "structuralRules": [{"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}],
  "semanticCriteria": [
    {"id":"fanout-timelines","kind":"fanout","description":"A broker fans posts out to independent timeline builders","broker":"message-broker","minConsumers":2,"forbiddenBroker":"queue","points":3,"hardFail":false},
    {"id":"feed-store-fit","kind":"storageFit","description":"Timeline reads are point-lookups by user","accessPattern":"point-lookup","accept":["kv-store","nosql-db"],"partial":["in-memory-cache"],"antiPattern":["relational-db"],"points":2}
  ],
  "justify": [{"id":"why-fanout","decision":"Fan-out on write vs read — why, given a 50:1 read ratio?","boundTo":{"componentType":"message-broker"},"requires":{"choice":true,"number":true,"tradeoff":true}}],
  "suite": {"name":"feed-suite","visibleToStudent":false,"cases":[{"id":"peak","description":"Read-heavy feed peak","workload":{"baseRps":3000,"requestDistribution":[{"type":"read","weight":0.98,"sizeBytes":512},{"type":"write","weight":0.02,"sizeBytes":1024}]}}]},
  "rubric": {"id":"feed-rubric","passThreshold":1,"checks":[
    {"id":"p99","kind":"simulation","description":"feed p99 under 200ms","metric":"summary.latency.p99","op":"<","value":200,"points":3},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 3. Sensor store (Lab 4) — write-heavy, time-series
**Covers:** NFR-durability · Scale · StorageFit(hardFail) · R:W(write) · Tradeoffs · Cost. **Graded by:** S (storageFit; SQL = hard fail) + J + $ ; Σ only for write throughput.

```json
{
  "version": "1.0", "id": "sensor-store", "title": "Design a sensor-metrics store",
  "difficulty": "intermediate", "type": "open-build", "workloadCategory": "write-heavy",
  "prompt": {
    "text": "Ingest 200K sensor writes/sec (append-only, time-partitioned, no joins). Choose a store that fits a time-series access pattern.",
    "functionalRequirements": ["Ingest time-stamped sensor readings (write-heavy)", "Range-query recent windows by sensor"],
    "nonFunctionalRequirements": [{"metric":"throughput","operator":">=","value":2000,"unit":"req_per_sec","description":"Sustain the injected write throughput without drops"}],
    "scale": {"peakRps":200000,"readWriteRatio":5}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":10,"maxBudget":500},
  "structuralRules": [{"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}],
  "semanticCriteria": [{"id":"store-fits-time-series","kind":"storageFit","description":"200K writes/s time-series → wide-column/time-series, NOT relational","accessPattern":"time-series","accept":["time-series-db","columnar-db","nosql-db"],"antiPattern":["relational-db"],"points":6,"hardFail":true}],
  "justify": [{"id":"why-db","decision":"Why this DB type for 200000 writes/sec time-series?","boundTo":{"componentType":"time-series-db"},"requires":{"choice":true,"number":true,"tradeoff":true}}],
  "budget": {"unit":"cost","cap":500},
  "suite": {"name":"sensor-suite","visibleToStudent":false,"cases":[{"id":"ingest","description":"Write-heavy ingest","workload":{"baseRps":3000,"requestDistribution":[{"type":"write","weight":0.95,"sizeBytes":256},{"type":"read","weight":0.05,"sizeBytes":256}]}}]},
  "rubric": {"id":"sensor-rubric","passThreshold":1,"checks":[
    {"id":"throughput","kind":"simulation","description":"Sustains write throughput","metric":"summary.throughput","op":">=","value":2000,"points":2},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 4. Cache placement (Lab 2) — read-heavy, placement
**Covers:** Placement/Ordering · R:W · NFR-latency. **Graded by:** T (placement: cache between service & DB, not before LB) + Σ (p99).

```json
{
  "version": "1.0", "id": "cache-placement", "title": "Place the cache correctly",
  "difficulty": "beginner", "type": "open-build", "workloadCategory": "read-heavy",
  "prompt": {
    "text": "Reads dominate ~20:1. Place a cache so it accelerates reads to the database — between the app service and the DB, never in front of the load balancer.",
    "functionalRequirements": ["Serve reads via a cache between the service and the DB", "Route all traffic through the load balancer first"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":120,"unit":"ms","description":"p99 read under 120ms"}],
    "scale": {"peakRps":20000,"readWriteRatio":95}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":10},
  "structuralRules": [
    {"id":"has-lb","kind":"requires_component","componentType":"load-balancer","description":"A load balancer fronts the system"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}
  ],
  "semanticCriteria": [{"id":"cache-between","kind":"placement","description":"Cache sits between the service and the DB, not before the LB","componentType":"in-memory-cache","between":["microservice","relational-db"],"notBefore":"load-balancer","points":4,"hardFail":false}],
  "suite": {"name":"cache-suite","visibleToStudent":false,"cases":[{"id":"peak","description":"Read-heavy","workload":{"baseRps":2000,"requestDistribution":[{"type":"read","weight":0.95,"sizeBytes":256},{"type":"write","weight":0.05,"sizeBytes":512}]}}]},
  "rubric": {"id":"cache-rubric","passThreshold":1,"checks":[
    {"id":"p99","kind":"simulation","description":"p99 under 120ms","metric":"summary.latency.p99","op":"<","value":120,"points":3},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 5. Messaging fan-out (Lab 3) — connection/event, topology
**Covers:** Fanout/Messaging · Direction. **Graded by:** T only (a broker must fan out to N; a queue→N is a hard fail). Sim does not help.

```json
{
  "version": "1.0", "id": "messaging-fanout", "title": "Fan out events to N consumers",
  "difficulty": "beginner", "type": "open-build", "workloadCategory": "connection-heavy",
  "prompt": {
    "text": "One producer must deliver each event to 3 independent consumers. Use a broadcast broker (pub/sub) — a work-queue only delivers each message to ONE consumer.",
    "functionalRequirements": ["Publish events once", "Each of 3 consumers receives every event"],
    "nonFunctionalRequirements": [],
    "scale": {"peakRps":5000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":10},
  "structuralRules": [
    {"id":"has-broker","kind":"requires_component","componentType":"message-broker","description":"A broadcast broker is present"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one producer"}
  ],
  "semanticCriteria": [{"id":"fanout","kind":"fanout","description":"Broker fans out to >=3 independent consumers; a queue to 3 is wrong","broker":"message-broker","minConsumers":3,"forbiddenBroker":"queue","points":5,"hardFail":true}],
  "justify": [{"id":"why-broker","decision":"Why a pub/sub broker and not a work-queue for fan-out?","boundTo":{"componentType":"message-broker"},"requires":{"choice":true,"tradeoff":true}}],
  "suite": {"name":"fanout-suite","visibleToStudent":false,"cases":[{"id":"baseline","description":"Nominal","workload":{"baseRps":1000}}]},
  "rubric": {"id":"fanout-rubric","passThreshold":1,"checks":[{"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 6. Cargo-cult CDN (Lab 5) — omission, anti-cargo-cult
**Covers:** Omission · Tradeoffs. **Graded by:** T+J (a CDN must be ABSENT, or present *and* defended by a valid justification). Sim does not help.

```json
{
  "version": "1.0", "id": "cargo-cult-cdn", "title": "Justify omission — the CDN trap",
  "difficulty": "intermediate", "type": "open-build", "workloadCategory": "read-heavy",
  "prompt": {
    "text": "This service serves dynamic, per-user API responses (not cacheable static assets). Adding a CDN here is cargo-cult. Either omit it, or defend it with a real reason.",
    "functionalRequirements": ["Serve dynamic per-user responses", "Do not add components that give no benefit"],
    "nonFunctionalRequirements": [],
    "scale": {"peakRps":8000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":10},
  "structuralRules": [{"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}],
  "semanticCriteria": [{"id":"cdn-justified","kind":"forbidUnjustified","description":"CDN must be absent, or defended by a valid justification","componentType":"cdn","justifyId":"why-cdn","points":4,"hardFail":false}],
  "justify": [{"id":"why-cdn","decision":"If you include a CDN for dynamic per-user responses, justify it; otherwise omit it.","boundTo":{"componentType":"cdn"},"requires":{"choice":true,"tradeoff":true}}],
  "suite": {"name":"cdn-suite","visibleToStudent":false,"cases":[{"id":"baseline","description":"Nominal","workload":{"baseRps":1000}}]},
  "rubric": {"id":"cdn-rubric","passThreshold":1,"checks":[{"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 7. Ride / track / pay (Exam 1) — mixed, hot/cold
**Covers:** FR · NFR-consistency · Placement · Hot/Cold · StorageFit · Direction. **Graded by:** Σ (match latency) + S (pay path = SQL) + T (hot/cold split) + J.

```json
{
  "version": "1.0", "id": "ride-hailing", "title": "Ride-hailing: match, track, pay",
  "difficulty": "advanced", "type": "open-build", "workloadCategory": "read-heavy",
  "prompt": {
    "text": "Match riders to nearby drivers (hot geospatial path, <3s), stream location updates, and process payments on a strongly-consistent path. Keep the hot geospatial lookups off the transactional DB.",
    "functionalRequirements": ["Match rider→driver via a geospatial hot path", "Track live location (high-frequency updates)", "Process payment on a strongly-consistent (SQL) path"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":3000,"unit":"ms","description":"p99 match under 3s"}],
    "scale": {"peakRps":40000,"readWriteRatio":80}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":16},
  "structuralRules": [
    {"id":"has-payment-db","kind":"requires_component","componentType":"relational-db","description":"A strongly-consistent DB for payments"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}
  ],
  "semanticCriteria": [
    {"id":"pay-fits-relational","kind":"storageFit","description":"Payment is transactional-relational (ACID), not KV","accessPattern":"transactional-relational","accept":["relational-db"],"antiPattern":["in-memory-cache"],"points":3,"hardFail":false},
    {"id":"geo-hot-path","kind":"placement","description":"Geospatial matching uses a cache/index, not the payment DB","componentType":"in-memory-cache","between":["microservice","relational-db"],"points":2}
  ],
  "justify": [{"id":"why-hot-cold","decision":"Why separate the geospatial hot path from the payment DB?","boundTo":{"componentType":"in-memory-cache"},"requires":{"choice":true,"number":true,"tradeoff":true}}],
  "suite": {"name":"ride-suite","visibleToStudent":false,"cases":[{"id":"peak","description":"Match-heavy peak","workload":{"baseRps":3000,"requestDistribution":[{"type":"read","weight":0.8,"sizeBytes":256},{"type":"write","weight":0.2,"sizeBytes":512}]}}]},
  "rubric": {"id":"ride-rubric","passThreshold":1,"checks":[
    {"id":"match-latency","kind":"simulation","description":"p99 match under 3s","metric":"summary.latency.p99","op":"<","value":3000,"points":3},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 8. Rate limiter (Exam 2) — correctness, shared state
**Covers:** Direction/Data-flow · Correctness · Tradeoffs. **Graded by:** T (rate-limiter → SHARED cache edge) + J (algorithm; cache-not-DB). **Sim does NOT help** (contention isn't modeled) — no `simulation` check.

```json
{
  "version": "1.0", "id": "rate-limiter", "title": "Distributed rate limiter",
  "difficulty": "advanced", "type": "open-build", "workloadCategory": "correctness-heavy",
  "prompt": {
    "text": "Build a rate limiter that is correct across many app instances. Counters must live in a SHARED store (e.g. Redis) — per-instance in-memory counters let a user exceed the limit by hitting different instances.",
    "functionalRequirements": ["Rate-limit requests before they reach the service", "Share counter state across all instances (no per-instance counters)"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":10,"unit":"ms","description":"Counter check adds <10ms"}],
    "scale": {"peakRps":100000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":10},
  "structuralRules": [
    {"id":"has-rate-limiter","kind":"requires_component","componentType":"rate-limiter","description":"A rate limiter is present"},
    {"id":"has-shared-cache","kind":"requires_component","componentType":"in-memory-cache","description":"A shared counter store is present"},
    {"id":"rl-to-shared-cache","kind":"requires_edge","fromType":"rate-limiter","toType":"in-memory-cache","description":"Rate limiter must connect to the SHARED cache (not per-instance counters)"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}
  ],
  "semanticCriteria": [{"id":"counters-in-shared-store","kind":"guardedPath","description":"All rate-limit checks traverse the shared counter store","from":"rate-limiter","guard":"in-memory-cache","points":4,"hardFail":true}],
  "justify": [
    {"id":"which-algo","decision":"Which limiting algorithm (token bucket / sliding window) and why?","boundTo":{"componentType":"rate-limiter"},"requires":{"choice":true,"tradeoff":true}},
    {"id":"why-cache","decision":"Why a cache and not a DB for counters?","boundTo":{"componentType":"in-memory-cache"},"requires":{"choice":true,"number":true,"tradeoff":true}}
  ],
  "suite": {"name":"rl-suite","visibleToStudent":false,"cases":[{"id":"baseline","description":"Nominal","workload":{"baseRps":1000}}]},
  "rubric": {"id":"rl-rubric","passThreshold":1,"checks":[{"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 9. Async SLA (Exam 3) — async vs sync, cost
**Covers:** Async/Sync · NFR-throughput · Autoscaling/Cost · FR. **Graded by:** Σ (sync violates SLA at load) + T (queue + workers present) + $ + J.

```json
{
  "version": "1.0", "id": "async-sla", "title": "Async pipeline for a 15s SLA",
  "difficulty": "advanced", "type": "open-build", "workloadCategory": "write-heavy",
  "prompt": {
    "text": "Process 50K jobs/min within a 15s SLA. A synchronous request path collapses under spikes — decouple with a queue and scalable workers.",
    "functionalRequirements": ["Accept jobs quickly", "Process each within the 15s SLA via an async queue + workers"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":15000,"unit":"ms","description":"p99 job completion under 15s"}],
    "scale": {"peakRps":3000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":12,"maxBudget":600},
  "structuralRules": [
    {"id":"has-queue","kind":"requires_component","componentType":"queue","description":"An async queue decouples ingest from processing"},
    {"id":"has-workers","kind":"requires_component","componentType":"batch-worker","description":"Scalable workers process the queue"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}
  ],
  "semanticCriteria": [{"id":"ingest-through-queue","kind":"guardedPath","description":"Jobs enter the queue before workers","from":"microservice","guard":"queue","to":"batch-worker","points":3,"hardFail":false}],
  "justify": [{"id":"why-async","decision":"Why async (queue + workers) over a synchronous path at 50K/min?","boundTo":{"componentType":"queue"},"requires":{"choice":true,"number":true,"tradeoff":true}}],
  "budget": {"unit":"cost","cap":600},
  "suite": {"name":"async-suite","visibleToStudent":false,"cases":[{"id":"spike","description":"Spike load","workload":{"baseRps":3000,"requestDistribution":[{"type":"write","weight":1.0,"sizeBytes":1024}]}}]},
  "rubric": {"id":"async-rubric","passThreshold":1,"checks":[
    {"id":"sla","kind":"simulation","description":"p99 completion under 15s","metric":"summary.latency.p99","op":"<","value":15000,"points":3},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 10. Ticketmaster — correctness-under-contention
**Covers:** Correctness · StorageFit · Direction · FR. **Graded by:** T (booking→lock; waiting queue) + S (SQL + search-index) + J (no-double-book). **Sim** only for waiting-queue latency.

```json
{
  "version": "1.0", "id": "ticketmaster", "title": "Event ticketing without double-booking",
  "difficulty": "expert", "type": "open-build", "workloadCategory": "correctness-heavy",
  "prompt": {
    "text": "Sell event seats under a thundering herd without double-booking. Serialize seat holds through a distributed lock (with TTL), search events via a search index, and persist bookings in a transactional DB. A virtual waiting queue absorbs the surge.",
    "functionalRequirements": ["Search events", "Hold a seat exactly once (no double-booking)", "Confirm and persist the booking transactionally"],
    "nonFunctionalRequirements": [{"metric":"latency_p99","operator":"<","value":2000,"unit":"ms","description":"p99 hold response under 2s via the waiting queue"}],
    "scale": {"peakRps":50000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":16},
  "structuralRules": [
    {"id":"has-lock","kind":"requires_component","componentType":"distributed-lock","description":"A distributed lock serializes seat holds"},
    {"id":"has-search","kind":"requires_component","componentType":"search-index","description":"A search index for event search"},
    {"id":"has-waiting-queue","kind":"requires_component","componentType":"queue","description":"A virtual waiting queue absorbs the surge"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}
  ],
  "semanticCriteria": [
    {"id":"holds-through-lock","kind":"guardedPath","description":"Every seat hold traverses the distributed lock","from":"microservice","guard":"distributed-lock","to":"relational-db","points":5,"hardFail":true},
    {"id":"booking-fits-relational","kind":"storageFit","description":"Bookings are transactional-relational","accessPattern":"transactional-relational","accept":["relational-db"],"antiPattern":["in-memory-cache"],"points":3}
  ],
  "justify": [{"id":"no-double-book","decision":"How do you guarantee no double-booking under contention (lock + TTL + OCC)?","boundTo":{"componentType":"distributed-lock"},"requires":{"choice":true,"tradeoff":true}}],
  "suite": {"name":"tm-suite","visibleToStudent":false,"cases":[{"id":"surge","description":"Onsale surge","workload":{"baseRps":3000,"requestDistribution":[{"type":"read","weight":0.7,"sizeBytes":256},{"type":"write","weight":0.3,"sizeBytes":512}]}}]},
  "rubric": {"id":"tm-rubric","passThreshold":1,"checks":[
    {"id":"queue-latency","kind":"simulation","description":"waiting-queue p99 under 2s","metric":"summary.latency.p99","op":"<","value":2000,"points":2},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 11. Web Crawler — batch / throughput, async pipeline
**Covers:** Batch/Throughput · Async pipeline (ordered) · Fanout · Direction(dedup). **Graded by:** T (frontier→fetch→process ordered pipeline; enqueue→dedup guard; fanout to fetchers) + Σ (aggregate throughput).

```json
{
  "version": "1.0", "id": "web-crawler", "title": "Distributed web crawler",
  "difficulty": "expert", "type": "open-build", "workloadCategory": "batch-heavy",
  "prompt": {
    "text": "Crawl billions of pages. Pipeline: frontier(queue) → fetchers → processors. Dedup URLs against an index before enqueueing (no re-crawls), fan work out to many fetchers, and store content in object storage.",
    "functionalRequirements": ["Enqueue only new URLs (dedup against an index)", "Fetch via many workers (fan-out)", "Process fetched pages in an ordered pipeline"],
    "nonFunctionalRequirements": [{"metric":"throughput","operator":">=","value":2000,"unit":"req_per_sec","description":"Sustain aggregate crawl throughput"}],
    "scale": {"peakRps":23000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":16},
  "structuralRules": [
    {"id":"has-frontier","kind":"requires_component","componentType":"queue","description":"A frontier queue"},
    {"id":"has-dedup","kind":"requires_component","componentType":"kv-store","description":"A dedup index"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one seed source"}
  ],
  "semanticCriteria": [
    {"id":"enqueue-through-dedup","kind":"guardedPath","description":"URLs pass the dedup index before the frontier","from":"microservice","guard":"kv-store","to":"queue","points":4,"hardFail":false},
    {"id":"crawl-pipeline","kind":"placement","description":"Ordered pipeline frontier → fetchers → processors","componentType":"batch-worker","orderedPipeline":["queue","batch-worker","microservice"],"points":3}
  ],
  "justify": [{"id":"why-dedup","decision":"Why dedup before enqueue, and how (bloom filter / index)?","boundTo":{"componentType":"kv-store"},"requires":{"choice":true,"tradeoff":true}}],
  "suite": {"name":"crawler-suite","visibleToStudent":false,"cases":[{"id":"steady","description":"Steady crawl","workload":{"baseRps":3000,"requestDistribution":[{"type":"write","weight":1.0,"sizeBytes":2048}]}}]},
  "rubric": {"id":"crawler-rubric","passThreshold":1,"checks":[
    {"id":"throughput","kind":"simulation","description":"aggregate throughput sustained","metric":"summary.throughput","op":">=","value":2000,"points":2},
    {"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## 12. Payment — exactly-once + auditability
**Covers:** Correctness(exactly-once) · NFR-durability · StorageFit(ledger) · Direction. **Graded by:** T (write→idempotency guard) + S (append-only ledger) + J. **Sim does NOT help** (exactly-once/immutability aren't simulatable).

```json
{
  "version": "1.0", "id": "payment-system", "title": "Payments: exactly-once + immutable ledger",
  "difficulty": "expert", "type": "open-build", "workloadCategory": "correctness-heavy",
  "prompt": {
    "text": "Process payments exactly once and keep an auditable trail. Every write passes an idempotency check (idempotency key) before an immutable, append-only double-entry ledger. A cache is never the system of record.",
    "functionalRequirements": ["Deduplicate retried payments via an idempotency key", "Append to an immutable double-entry ledger (never mutate)"],
    "nonFunctionalRequirements": [{"metric":"availability","operator":">=","value":99.99,"unit":"percent","description":"Ledger writes are durable and highly available"}],
    "scale": {"peakRps":10000}
  },
  "scaffold": {"type":"empty"},
  "constraints": {"canModifyScaffold":true,"canRemoveScaffoldNodes":true,"maxNodeCount":14},
  "structuralRules": [
    {"id":"has-idempotency","kind":"requires_component","componentType":"idempotency-manager","description":"An idempotency check guards writes"},
    {"id":"has-ledger","kind":"requires_component","componentType":"event-sourcing-store","description":"An append-only ledger"},
    {"id":"single-source","kind":"requires_single_source","description":"Exactly one traffic source"}
  ],
  "semanticCriteria": [
    {"id":"writes-through-idempotency","kind":"guardedPath","description":"Every payment write passes the idempotency store before the ledger","from":"microservice","guard":"idempotency-manager","to":"event-sourcing-store","points":5,"hardFail":true},
    {"id":"ledger-append-only","kind":"storageFit","description":"Ledger is an append-only immutable store, not a cache","accessPattern":"append-only-ledger","accept":["event-sourcing-store"],"antiPattern":["in-memory-cache"],"points":3,"hardFail":true}
  ],
  "justify": [{"id":"exactly-once","decision":"How do you guarantee exactly-once (idempotency key) and auditability (immutable ledger)?","boundTo":{"componentType":"idempotency-manager"},"requires":{"choice":true,"tradeoff":true}}],
  "suite": {"name":"pay-suite","visibleToStudent":false,"cases":[{"id":"baseline","description":"Nominal","workload":{"baseRps":1000,"requestDistribution":[{"type":"write","weight":0.9,"sizeBytes":512},{"type":"read","weight":0.1,"sizeBytes":256}]}}]},
  "rubric": {"id":"pay-rubric","passThreshold":1,"checks":[{"id":"no-invariants","kind":"invariant","description":"No invariant violations","metric":"invariantViolations.count","op":"==","value":0,"points":1}]},
  "author":"question-bank"
}
```

---

## Coverage matrix (which archetype exercises which dimension)

| # | Question | FR | NFR | Scale | StorageFit | R:W | Fanout | Place | Direction | Tradeoff | Omission | Hot/Cold | Async | Cost |
|---|----------|----|----|-------|-----------|-----|--------|-------|-----------|----------|----------|----------|-------|------|
| 1 | URL Shortener | ● | lat | ● | ● | ● | | | | ● | | | | |
| 2 | Feed / News | ● | lat | ● | ● | ● | ● | | | ● | | ● | | |
| 3 | Sensor store | ● | dur | ● | ●! | ● | | | | ● | | | | ● |
| 4 | Cache placement | ● | lat | ● | | ● | | ● | ● | | | | | |
| 5 | Messaging fan-out | ● | | ● | | | ●! | | ● | ● | | | | |
| 6 | Cargo-cult CDN | ● | | ● | | | | | | ● | ● | | | |
| 7 | Ride/track/pay | ● | con | ● | ● | ● | | ● | ● | ● | | ● | ● | |
| 8 | Rate limiter | ● | lat | ● | | | | | ●! | ● | | | | |
| 9 | Async SLA | ● | thru | ● | | | | | ● | ● | | | ●! | ● |
| 10 | Ticketmaster | ● | lat | ● | ● | ● | | | ●! | ● | | | | |
| 11 | Web Crawler | ● | thru | ● | | | ● | ● | ●! | ● | | | ● | |
| 12 | Payment | ● | dur | ● | ●! | ● | | | ●! | ● | | | | |

`●!` = hard-fail / defining check. `lat/thru/con/dur` = the NFR flavor.

> **Reminder (alignment §1/§9):** questions 5, 6, 8, 10, 12 are **correctness- or
> topology-graded** — the `simulation` checks are minimal (just the invariant
> guard) and the real credit is `structural` + `semantic` + `justify`. Questions
> 1–4, 7, 9, 11 lean on the simulation for latency/throughput. Author accordingly:
> never put a `simulation` check on a property the sim can't measure.

---

## Validation status (graded reference-vs-gamed)

All 12 packages pass `parseQuestionPackage` (schema). Eight were additionally
**graded through `sim evaluate question`** with a correct reference topology and a
deliberately-gamed one — each reference **passed**, each gamed **failed on its
defining check**:

| # | Question | Defining check exercised | Gamed failure message |
|---|----------|--------------------------|------------------------|
| 1 | URL Shortener | `simulation` p99 loop | *actual 1003.52 ≥ 100 (no cache → store saturates)* |
| 3 | Sensor store | `storageFit` hardFail | *relational-db is an anti-pattern for a time-series workload* |
| 4 | Cache placement | `placement` | *cache does not sit on a path from service to DB* |
| 5 | Messaging fan-out | `structural` (broker) → `fanout` | *expected ≥1 message-broker, found 0* |
| 6 | Cargo-cult CDN | `forbidUnjustified` | *cdn present but its justification was not defended* |
| 8 | Rate limiter | `requires_edge` (RL→shared cache) | *expected edge from rate-limiter to in-memory-cache* |
| 11 | Web Crawler | `guardedPath` (dedup) + `placement` pipeline | *can reach queue without passing through the dedup index* |
| 12 | Payment | `guardedPath` hardFail | *can reach the ledger without passing idempotency* |

Questions **2, 7, 9, 10** (feed, ride, async, Ticketmaster) reuse only check
kinds already proven above (fanout, storageFit, placement, guardedPath, structural,
p99 sim), so they grade by the same validated mechanisms.

### Authoring gotchas found during validation (avoid these)

1. **A full topology's `workload.requestDistribution` entries require `sizeBytes`.**
   (The `suite.workload` *override* is a partial and tolerates its absence, but the
   student's/reference topology does not.) Always include `sizeBytes`.
2. **Type ≠ category.** `batch-worker` is a *component type*; its **category** is
   `compute`. Categories come from a fixed enum (`compute`, `network-and-edge`,
   `storage-and-data`, `messaging-and-streaming`, `consensus-and-coordination`, …),
   not from the type name.
3. **A `structuralRule` short-circuits semantic checks.** If a rule requires a
   `message-broker` and the gamed design uses a `queue`, the design fails at the
   *structural* gate before the `fanout` check runs. That's fine (it still fails),
   but if you want a specific semantic check to be the failure point, make sure the
   gamed design passes structural first.
4. **`forbidUnjustified` via the CLI always fails a present component** ("justification
   not evaluated"), because the CLI captures no justification answers. In-app, once
   justification capture is wired, a *defended* component passes. Test the *absent*
   case for a clean pass via CLI.

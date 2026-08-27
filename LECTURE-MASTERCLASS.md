# The NS-Simulator Masterclass — A Ground-Up, Self-Contained Guide

> **What this document is.** A single, standalone, read-it-cover-to-cover
> explanation of the NS-Simulator: what it is, why it exists, the mathematics and
> physics it runs, the architecture that makes it work, how questions are
> authored, how designs are graded and defended against gaming, and — woven
> throughout — the *design story*: the problems we hit trying to "simulate a
> systems architecture" and the tradeoffs we chose to overcome them.
>
> **Who it's for.** You (the lecturer), so you can teach the whole thing from
> first principles without holding any other doc open. It assumes only: basic
> queueing intuition, a little TypeScript/React, and comfort with high-level
> system design vocabulary (load balancer, cache, database, queue).
>
> **How to read / teach it.** It's organized as a *spine*: follow one request
> through the machine, then zoom out one ring at a time — one request → one node's
> physics → one topology's cost & metrics → one graded question → the product
> around it. Every part ends with **"The problem we hit / how we solved it / the
> tradeoff"** so you can narrate the engineering decisions, not just the features.
>
> **Two running examples** appear everywhere:
> - **`cache-placement`** — a read-heavy service whose database collapses under
>   load unless a cache shields it.
> - **`url-shortener`** — a point-lookup store plus a read cache.

---

## Table of Contents

**Part 0 — The Thesis: why a "LeetCode for system design" is even possible**

**Part I — The Machine (bottom-up)**
- 1. Discrete-Event Simulation core
- 2. Determinism & numerics (the part people don't believe works)
- 3. The request lifecycle & the closed terminal taxonomy
- 4. The queueing model: G/G/c/K
- 5. Nodes, component types & service time
- 6. The instance model & derived concurrency (the crown jewel)
- 7. Execution profiles: CPU-bound vs IO-bound
- 8. Edges: network physics vs dumb connectors
- 9. Traits: pluggable node behaviors
- 10. Cost model & budgets
- 11. Metrics, aggregation & the honesty doctrine
- 12. Workload & scale

**Part II — Turning it into a Course: authoring & grading**
- 13. The grading DSL & the five orthogonal axes
- 14. Anti-gaming & the Dual-Topology Rule
- 15. Environment profiles & capabilities
- 16. The performance/correctness boundary
- 17. Authoring a question end-to-end (capstone walkthrough) — incl. a full annotated `question.json`

**Part II-B — Translating any online interview question into the simulator**
- 18. Why a generic translation is possible
- 19. The six bottleneck families (the translation key)
- 20. The 8-step translation procedure
- 21. Worked translations (URL shortener, rate limiter, news feed, Ticketmaster, web crawler, notification, IoT)
- 22. Translation anti-patterns

**Part III — The Product Around It**
- 23. Frontend architecture
- 24. Newton integration & the authoring workflow

**Part IV — The Skeptic's FAQ (your keynote defense)**

**Part V — Known gaps & honest caveats (teach these openly)**

**Appendix A — Glossary**
**Appendix B — Source-of-truth file map**
**Appendix C — Lecture delivery plan & tracks**

---

# Part 0 — The Thesis

## 0.1 Why this is a hard problem

"LeetCode for system design" sounds obvious until you try to build it, and then
every assumption you borrowed from coding-interview platforms falls apart:

| LeetCode (coding) | System design |
|---|---|
| There is a **right answer** (or a small set) | There is **no single right answer** — many valid architectures |
| You **compile & run** against hidden tests | There's nothing to "run" — a diagram isn't executable |
| The design space is **bounded** (one function, fixed I/O) | The design space is **unbounded** (any topology of any size) |
| The graded skill is **algorithmic correctness** | The graded skill is **scaling & tradeoffs** — which *looks* un-gradeable |

So the naïve objections write themselves: *"system design has no right answer,"*
*"you can't run a diagram,"* *"the real skill is judgment, and you can't grade
judgment."* Every one of those is answered later in Part IV. But the whole
document is really one long answer to a single reframed question:

> **We do not grade *the answer*. We grade whether the design *satisfies its
> requirements under load*. That is a constraint-satisfaction problem, and
> constraint satisfaction is gradeable.**

## 0.2 The one idea that makes it work

The core trick: **make the physics the impartial grader.**

Instead of comparing a student's diagram to a reference diagram (answer-matching),
we take the student's diagram, **inject a realistic, question-controlled workload
over it, simulate the queueing physics, and measure whether it meets the stated
SLO** (e.g. "p99 latency < 200ms at 2000 rps"). *Any* topology that meets the SLO
with the right structural guards passes. Multiple valid solutions is a **feature**,
not a bug.

This turns the un-gradeable "is this a good design?" into the gradeable "does this
design, under this load, keep its promises?" — and it does so with a **real
discrete-event simulation grounded in queueing theory**, not an animation and not
an LLM's opinion.

## 0.3 The three honesty claims (the north star)

Everything in the machine is built to make three claims literally true. If you
remember nothing else from the whole course, remember these — they are the recurring
threads in every lecture:

1. **Every number is physically derived and shows its provenance.** No metric
   appears without a *why*. Utilization isn't a guess; it's a time-weighted
   integral of the busy area. No "seeded default error rate" leaking in unexplained.

2. **Concurrency and cost are hardware *consequences*, not free dials.** You cannot
   type "workers = 1,000,000" to make a bottleneck disappear. Concurrency is
   *derived* from a priced, capped instance catalog. Buying capacity costs money and
   can breach a budget or a quota. **Scaling is a real physical tradeoff.**

3. **A question is "authored" only when a *good* design passes *and* a known
   *gamed* design fails** on the intended axis. That's the Dual-Topology Rule — an
   executable definition of "this is a fair question."

Keep these three in view. Almost every engineering decision in the rest of the
document exists to protect one of them.

---

# Part I — The Machine

We build strictly bottom-up. Each section is: *what it is → the math/mechanism →
the source of truth → the problem we hit and the tradeoff we chose.*

## 1. Discrete-Event Simulation (DES) core

### 1.1 What DES is

A discrete-event simulation models a system as a **sequence of instantaneous
events** ordered by *simulated* time. There is a **clock**, and it does **not** tick
uniformly like a wall clock. Instead it **jumps from one event to the next**.
Between two events, by definition, nothing changes — so we don't waste any
computation on the gaps. This is the DEVS formalism used in real capacity planning,
not a cartoon of moving dots.

Concretely, the engine holds a **priority queue of events**, each stamped with the
time it should fire. The loop is:

```
while (running and queue not empty):
    event = queue.extractMin()          # earliest-timestamped event
    if event.timestamp > simulationDuration: stop
    clock = event.timestamp             # jump the clock forward
    dispatch(event)                     # a handler mutates state, maybe schedules more events
```

An event handler can **schedule future events**. A "request arrives at node A"
event, when handled, might sample a service time of 8ms and schedule a
"processing-complete at A" event 8ms into the future. That completion, when it
fires, might schedule a "request forwarded onto edge A→B" event, and so on. The
whole simulation is this cascade.

The scheduler is a **MinHeap** (`src/engine/scheduler/min-heap.ts`) ordered by the
key `(timestamp, priority)` — more on `priority` in §3.

### 1.2 The time model — three durations

Three configured durations shape every run (`topology.global`):

- **`simulationDuration`** — how long (in simulated time) the run lasts. The run
  ends when the next event would fire past this horizon.
- **`warmupDuration`** — an initial slice that is **excluded** from reported
  statistics. When you start a queueing system empty, it goes through a *transient*:
  queues are unnaturally short, latencies unnaturally low, because the pipeline
  hasn't filled. We want to report the **steady state**, so we throw away the warmup.
  This is standard practice in output analysis for stochastic simulations.
- **`timeResolution`** — the granularity of the clock (microseconds; see §2).

The run boundary is dead simple to invoke:

```ts
const output: SimulationOutput = new SimulationEngine(topology).run()
```

`SimulationOutput` carries per-node metrics, per-edge metrics, a system summary,
invariant checks, and `reproducible: true`.

### 1.3 The problem we hit / the tradeoff

**Problem:** DES is only useful for grading if it is *reproducible*. If the same
topology + seed could produce different numbers on two machines (or two runs), a
grading threshold would be meaningless and students could "reroll" until they got
lucky.

**Solution & tradeoff:** we committed to *total determinism* (next section), which
constrains how we're allowed to write the engine (no `Math.random()` anywhere,
`bigint` clock, quantized sampling). That's a real tax on contributors — it's easy
to accidentally break reproducibility with one stray float — but it's the price of a
gradeable instrument. We pay it deliberately and guard it with tests.

---

## 2. Determinism & numerics — the part people don't believe works

This is the single most common "gotcha" a skeptical engineer will throw at you:

> *"You're sampling continuous probability distributions (arrival times, service
> times) in JavaScript, across millions of events. Floating-point error will
> accumulate and drift, and your runs won't be reproducible. Grading on that is
> nonsense."*

The answer is a **three-layer** design, and it fully closes the drift worry.

### 2.1 Layer 1 — an integer-only PRNG (no float in its state)

The random stream is produced by an integer generator, seeded from a string:
`xmur3(seedString)` produces the initial state, and `sfc32(a,b,c,d)` evolves it.
The generator's **entire state is four 32-bit unsigned integers**, advanced with
`Math.imul`, bit-shifts, XOR, and `>>> 0` (unsigned coercion). **No floating-point
value ever enters the recurrence.** Therefore the random *stream* is bit-identical
on every JavaScript engine (V8, JSC, …) and cannot drift no matter how long it
runs. Only the *final* presentation step divides to land in `[0, 1)`:
`t / 4294967296` — a single, deterministic IEEE-754 operation, not an accumulating
one.

*Lives in `src/engine/stochastic/random.ts`.*

### 2.2 Layer 2 — standard transform sampling built on that one uniform

Every continuous distribution is drawn deterministically from that uniform
`rng.next()` via textbook inverse-transform / transform sampling:

- **Exponential** (used for arrival gaps and service times): inverse-CDF
  `−ln(1−U)/λ`.
- **Normal:** Box-Muller, `√(−2 ln U₁)·cos(2π U₂)`; **log-normal** = `exp(normal(μ,σ))`.
- **Weibull:** inverse-CDF `scale·(−ln(1−U))^{1/shape}`; **Gamma:** Marsaglia–Tsang
  acceptance–rejection.
- Dispatched by `distribution.type` (`constant | exponential | log-normal | …`).

*Lives in `src/engine/stochastic/distribution.ts`.*

### 2.3 Layer 3 — the clock is BigInt microseconds; floats never accumulate

This is the crux, and it's worth teaching slowly.

The quantity that *accumulates* over the whole run — the event-loop clock, every
scheduled timestamp, every summed duration, the busy-area integral — is **`bigint`
integer microseconds** (`this.clock`, `simulationDurationUs`, `interArrivalUs`,
`latencyUs`, `totalQueueTime`, `totalServiceTime`, …). A sampled float duration is
**quantized to whole microseconds the instant it enters the timeline**:

```ts
const interArrivalUs = BigInt(Math.max(1, Math.round(interArrivalMs * 1000)))
this.scheduleRequestGeneratedAt(currentTime + interArrivalUs)  // BigInt + BigInt — exact
```

So floating-point math is confined to a **single, non-accumulating leaf step**:
drawing one duration. The moment that value joins the event queue it is an exact
integer, and every subsequent operation — ordering events, summing millions of
durations, computing integrals — is **exact BigInt arithmetic**. There is no growing
epsilon because **nothing floating-point is ever summed.**

Why this fully answers the drift worry:

- **Ordering** of events is exact (integer comparison) → the event *sequence* is
  reproducible.
- **Accumulation** (clock, integrals, totals) is exact (BigInt) → no epsilon growth
  over long runs.
- **Sampling** floats affect only the *value* of one duration, by at most a
  sub-microsecond, and that difference is **erased by µs quantization**
  (`Math.round(ms*1000)`, floored at 1µs).
- **Honest caveat:** the transcendental functions (`Math.log/sqrt/pow/cos`) *can*
  differ in the last ULP across JS engines. But because every result is rounded to a
  whole microsecond before use, those sub-ULP differences vanish. Reproducibility is
  guaranteed within an engine and effectively across engines. If we ever needed
  *bit-identical cross-engine* transcendentals, we'd swap in a fixed-point/polynomial
  `log` — not currently necessary.

### 2.4 Why determinism is an anti-gaming weapon, not just a nicety

Because the seed is fixed *by the question* (not by the student), a student cannot
re-run until a lucky seed passes. Fix the seed → kill seed-farming. Determinism is
therefore load-bearing for fairness, which is why we guard it so aggressively.

**Cohesion guardrail (teach this to contributors):** any new stochastic behavior —
GC jitter, cache stampede, packet loss — **must** draw from the engine's seeded
source, never `Math.random()`. A single unseeded call makes runs non-reproducible
and flakes every rubric check.

### 2.5 The gap (be honest in the lecture)

There is currently **no dedicated spec** that states this determinism contract
(integer PRNG + BigInt clock + µs-quantized sampling) as a first-class invariant.
It's correct in code and covered by unit tests, but a new engineer has to
reverse-engineer it. This is a documented follow-up (`specs/simulation-determinism-and-numerics.md`).

---

## 3. The request lifecycle & the closed terminal taxonomy

### 3.1 One request's journey

Follow a single request through the machine. This is the "spine" and it's the best
opening demo for a lecture:

```
source generates request
   → edge transit (latency, maybe packet loss)
      → arrival at node
         → admission control (admit? reject? queue?)
            → queue wait (if all workers busy)
               → service (a worker processes it for a sampled time)
                  → departure
                     → route to next hop  → (repeat)  OR  → terminal
```

Every request ends in exactly **one terminal state**. The engine tracks the terminal
reason on `request.metadata.__terminal` and then **removes the request from the live
map**, which elegantly prevents double-counting (see §3.4).

### 3.2 The event types & the priority tie-breaker

There are 20 `EventType` values; 9 have full handlers (the request-lifecycle and
node-failure/recovery events), and 11 are stubs reserved for future
infrastructure/resilience features (circuit breakers, partitions, etc.).

The subtle, important part is the **priority system** that breaks ties when two
events share the same timestamp (`EventPriority`, lower = processed first):

| Priority | Value | Events | Why this order |
|---|---|---|---|
| SYSTEM | 0 | node-failure, node-recovery, partitions… | System state must settle before requests move |
| ARRIVAL | 1 | request-generated, request-arrival | Arrivals before processing (causality) |
| PROCESSING | 2 | processing-complete, request-complete, request-rejected, cache-hit/miss | Results after arrivals |
| DEPARTURE | 3 | request-forwarded | Departures after processing |
| TIMEOUT | 4 | request-timeout | **Timeouts last** |

**Why timeout is dead last is a beautiful little correctness detail.** Suppose a
`processing-complete` and a `request-timeout` are scheduled for the *exact same*
microsecond. Because processing (priority 2) runs before timeout (priority 4), the
request **completes successfully first**, sets `__terminal = 'success'`, and is
removed from the map. When the timeout handler then runs, it looks the request up,
finds nothing, and silently discards itself. Result: **a request that just barely
makes its deadline is not falsely timed out.** Get this ordering wrong and you'd
punish designs that are actually meeting their SLO by a hair.

### 3.3 The closed terminal taxonomy — why "closed" = honest

This is one of the honesty pillars. Every terminated request is classified into a
**closed** set of causes. "Closed" means: there is no catch-all "other," and the
counts **reconcile exactly** (`generated = Σ terminals-by-cause + still-in-flight`).

The causes:

- **`success`** — completed within deadline.
- **`timeout`** — exceeded its deadline (either at a node, or in-flight on an edge).
- **`capacity_exceeded` / `queue_full`** — arrived at a node already at capacity K
  (system is *overloaded*).
- **`oom`** — admission blocked because RAM can't hold another request (distinct from
  queue_full: too many waiting vs. no memory to hold them; see §6).
- **`connection_reset`** — an in-flight request killed by a node failure.
- **`node_failed`** — arrived at a node that is currently down (*dead*, not
  overloaded).
- **edge failures** — packet loss / edge error.

**Why the split matters pedagogically:** the operator's very first question about a
sick component is *"is it dead, sick, or overloaded?"* An unblended "Rejected: 4,182"
number can't answer that. `node_failed` (dead) vs `queue_full` (overloaded) vs
`timeout` (slow) each point at a *different fix*. The taxonomy is the difference
between a metric that scolds you and a metric that diagnoses you.

Classification lives in
`src/engine/metrics/windowedLatencyAggregator.ts` (`classifyRejectionCause`), and the
UI renders **only** the causes that actually fired — no zero-rows of fake precision.

### 3.4 Timeout mechanics (two kinds)

- **Node-level timeout:** scheduled when a request is admitted to a node. Fires at
  `min(clock + nodeTimeout, request.deadline)`. If the request finishes first, it's a
  no-op (per §3.2).
- **Edge/deadline timeout:** fires during edge transit if the request would arrive
  *after* its deadline (`request.deadline <= arrivalTime`), or on packet loss.

The per-request deadline originates as
`request.deadline = createdAt + defaultTimeout` (`topology.global.defaultTimeout`).

*Source: `src/engine/core/events.ts`, `src/engine/engine.ts` handlers,
`arrival-departure-and-request-lifecycle-semantics.md`.*

### 3.5 The problem we hit / the tradeoff

**Problem:** early on, "rejected" was a single blended bucket, and the books didn't
balance — you couldn't prove a metric wasn't silently dropping requests.

**Solution & tradeoff:** we made the taxonomy *closed* and added a conservation
identity (`generated = Σ terminals + in-flight`). The tradeoff is more bookkeeping in
the hot path (every terminal must funnel through one `recordTerminal` and be
attributed to a cause and a *locus* — the node or edge it died at). We accept the
extra plumbing because "the books balance ✓" is exactly the property that lets an
instructor trust a threshold.

---

## 4. The queueing model: G/G/c/K

Every non-source node in the topology is the **same fundamental unit: a queue.**
This is the beating heart of the simulator, so teach it carefully.

### 4.1 What G/G/c/K means

It's Kendall's notation for the most general finite multi-server queue:

- **G** (arrivals) — *general* arrival distribution. We make **no** assumption; any
  supported distribution can drive arrivals.
- **G** (service) — *general* service-time distribution (constant, exponential,
  log-normal, …). Real components differ wildly: a CDN might be a near-constant
  0.1ms; a database an 8ms log-normal with a heavy right tail.
- **c** — the number of **parallel servers** (workers). While ≤ c requests are in
  service, they run concurrently; the (c+1)-th waits.
- **K** — the **total system capacity** (workers + queue slots). This is the crucial
  finite-buffer part.

The class is `GGcKNode` (`src/engine/nodes/GGcKNode.ts`).

### 4.2 The capacity model — K is *total*, not queue-only

A common misread: people think "capacity = queue length." **No.** `capacity` (K) is
the *total items in system*:

```
totalInSystem = activeWorkers + queue.length
maxCapacity   = K                       # workers + queue slots together
queueSlots    = K − c
Admission:  totalInSystem >= K  →  REJECT (capacity_exceeded)
```

So a node with `workers: 4, capacity: 10` has 4 worker slots and 6 queue slots. When
all 4 workers are busy and 6 requests are queued, the 11th item is rejected. A node
with `workers: 4, capacity: 4` can never queue anything (all slots are worker slots).

### 4.3 The arrival decision (admission control)

When a request arrives (`handleArrival`), three checks, in order:

1. **Node failed?** → reject with `node_failed` (a failed node rejects everything
   and clears its queue — a failure loses all in-flight and queued work at that node).
2. **`totalInSystem >= K`?** → reject with `capacity_exceeded`.
3. **A worker free (`activeWorkers < c`)?** → start processing immediately (sample a
   service time, schedule `processing-complete`). Else → **enqueue** (wait for a
   worker).

On completion, a worker frees up, the node computes a `RequestSpan`
(`{arrivalTime, queueWait, serviceTime, departureTime}`), and if the queue is
non-empty it **dequeues** the next request per its discipline.

### 4.4 Queue disciplines

Four are typed; three are truly distinct:

| Discipline | Algorithm | Note |
|---|---|---|
| `fifo` | `queue.shift()` | Fair, arrival order — the default |
| `lifo` | `queue.pop()` | Newest first; early arrivals can starve |
| `priority` | linear scan for min `request.priority`, then splice | Lower number = higher precedence |
| `wfq` | **currently identical to FIFO** | Honest gap: weighted-fair-queuing isn't implemented yet |

Teaching the `wfq` gap openly is on-brand for the honesty doctrine — the union has 4
values but only 3 behaviors ship.

### 4.5 Utilization must be a time-weighted integral (a hard-won rule)

This is one of the most important honesty rules in the whole system, and it came from
a real, embarrassing bug — so it makes a *great* lecture story.

**The rule:** a reported scalar time-average (utilization, occupancy) **must be a
time-weighted integral over the run**, never the mean of point samples.

**Utilization** is the fraction of server-capacity that was busy:

```
ρ = ∫ busy(t) dt / (c · T)
```

In code, the node **owns the integral** and accrues it at *every* worker-count
change (arrival, completion, cancel, fail, recover):

```
busyAreaUs += activeWorkers × (now − lastChangeUs)
```

and at run end reports `busyAreaUs / (durationUs × c)`.

**The bug that forced this (tell this story):** the collector used to *snapshot*
`activeWorkers/maxWorkers` about once per second and average ~5 samples. At 8ms
service time, a worker toggles busy/idle ~120 times per second — so a 1-second
snapshot cadence **undersamples by ~120×**. In one run the true busy fraction was
~92.5% (578 completions × 8ms ÷ 5000ms), but the "average of 5 snapshots" read
**80%** — a pure sampling artifact (4 of 5 snapshots happened to catch a busy worker).
It disagreed with the completion count *and* with Little's Law. The fix: own the
integral where state actually changes; keep snapshots **only** for time-series charts
and a live gauge, and even there emit per-window integrals, never point samples.

> **The general lesson for the course:** a lenient or mis-sampled metric is itself a
> gaming surface. If utilization can read low while the node is actually saturated,
> a student "passes" a node that's on fire. Metric honesty *is* anti-gaming.

### 4.6 Little's Law as an invariant check

Little's Law, `L = λ·W`, relates the average number in system `L`, the arrival rate
`λ`, and the average time in system `W`. Because we measure all three independently
(post-warmup), they must agree. We use this as a **validation invariant** — if the
measured `L` disagrees with `λ·W`, something in the metrics is lying. (This is exactly
the check that caught the utilization bug above.)

### 4.7 The saturation "hockey stick" (intuition to draw on the board)

For stochastic arrivals, queue depth stays near zero while utilization is modest,
then **explodes** as ρ → 1. Rule of thumb: below ~70% utilization, most distributions
rarely queue; above ~85%, queue length grows roughly exponentially. This nonlinearity
is *why* "just add a little load" can suddenly collapse a design — and why the dry-run
trap in §12 is so dangerous.

*Source: `GGcKNode.ts`, `queue-depth-calculation.md`, `throughput-calculation.md`,
`no-point-sampled-scalars` (the utilization-integral rule).*

---

## 5. Nodes, component types & service time

### 5.1 The palette

The canvas offers a palette of component **types**, grouped into categories:
*compute* (microservice, batch-worker, auth-service, container, …),
*storage-and-data* (relational-db, nosql-db, in-memory-cache, time-series-db,
object-storage, …), *network-and-edge* (load-balancer L4/L7, api-gateway, cdn,
reverse-proxy, …), *messaging* (queue, message-broker, pub-sub, stream), and
*sources* (api-endpoint, serverless-function). Each type is a **preset** — it seeds
sensible defaults so a freshly-dragged node behaves plausibly without any tuning.

### 5.2 Service-time distribution & the tail

A node's `processing.distribution` decides how long one request takes:

- **`constant`** — deterministic, always the same duration (a clean teaching baseline).
- **`exponential`** — memoryless, heavy right tail. Key intuition to teach:

> For exponential service, **p99 ≈ mean × ln(100) ≈ 4.6 × mean.**

That single fact explains a lot of "why is my p99 so bad when my mean looks fine?"
The per-hop mean can be small, but the **tail compounds** and a chain of hops with
small means can still produce a large end-to-end p99. (This is also why you can't
just add per-hop p99s — percentiles don't sum; see §11.)

Per-type mean service times live in `TYPE_MEAN_SERVICE_MS` (with category floors);
palette seeding is `buildSeededSimulationConfig` / `paletteTemplates.ts`;
type→spec resolution is `componentSpecs.ts`.

### 5.3 The problem we hit / the tradeoff

**Problem:** if every node just used a generic fallback service time, the physics
would be uniform and uninteresting — worse, a bug once made an `api-endpoint` source
default to a 68.5ms exponential (it was missing from `TYPE_MEAN_SERVICE_MS` and fell
to the generic `10 + util×90` fallback), which quietly made an entire question
*unsolvable* — the p99 was ~170ms with **or** without a cache, so the cache (the whole
point of the question) was irrelevant.

**Solution & tradeoff:** give each type an honest, curated default (that bug was
fixed by adding `'api-endpoint': 0.2`). The tradeoff is a **curation burden** — every
new type needs a defensible default service time and category floor, and those
defaults interact with question difficulty. We accept the burden because "every node
behaves like the thing it claims to be" is what makes "pick the right component" a
real decision instead of cosmetics.

---

## 6. The instance model & derived concurrency — the crown jewel

This is the single most important design decision in the whole product, and the one
that most sets it apart from a toy. Budget a full lecture on it.

### 6.1 The problem, stated bluntly

If `workers` (c) and `capacity` (K) are **free-typed numbers**, the entire grading
model collapses. Why? Because **every bottleneck vanishes for free.** A student who
sees "database saturates at 500 rps" just types `workers = 100000` and the saturation
is gone — *without buying anything, without any tradeoff, without understanding
anything.* We literally saw a student input of `8e20` workers. If capacity is a free
dial, "add a cache" is never the right answer because "add a zero to the worker count"
always is. Nothing discriminates. The question is dead.

### 6.2 The move: **derive-and-lock**

Concurrency is **no longer an input.** It is **derived** from a *priced, capped
hardware catalog* and shown read-only. You don't pick workers; you pick an **instance
type** and an **instance count**, and *everything follows*:

```
effectiveC = vCPU × instanceCount × workersPerVcpu
effectiveK = max(effectiveC, memCeiling)
memCeiling = ⌊ totalRAM / perRequestMemMb ⌋
```

- `workersPerVcpu` is **1** for cpu-bound work and **32** for io-bound work (§7).
- `memCeiling` is how many concurrent requests the RAM can *hold*; when arrivals
  exceed it, you get an **`oom`** terminal (distinct from `queue_full`).
- Utilization automatically divides by `effectiveC`, so the honesty integral (§4.5)
  stays correct under any instance choice.

Authored `workersPerInstance` / `queueSlots` are *ignored* for the derivation (they
remain visible as provenance). This is the "lock" in derive-and-lock.

### 6.3 The catalog (t3 / m5 / c5 / r5 / x1e)

Rather than let people free-type `{cpu, memory}` (infinite dials, infinite gaming),
you pick from a **frozen `INSTANCE_CATALOG`** of ~12 curated AWS-shaped types across
2/4/8 vCPU, RAM ratios from ~1 to ~30 GB/vCPU, each carrying an AWS-proportional
`pricePerHour`. Because **CPU and RAM are coupled** (a bigger-RAM box is a bigger
instance ⇒ more vCPU ⇒ more cost), you can't cheat one dimension in isolation. Here
are the actual catalog entries (verbatim from `instanceCatalog.ts`), so you can put
real numbers on the board:

| instanceType | vCPU | RAM (GB) | family | $/hr | perfFactor |
|---|---:|---:|---|---:|---:|
| `t3.small` | 2 | 2 | burstable | 0.021 | 0.8 |
| `t3.medium` | 2 | 4 | burstable | 0.042 | 0.8 |
| `m5.large` | 2 | 8 | general | 0.096 | 1.0 |
| `m5.xlarge` | 4 | 16 | general | 0.192 | 1.0 |
| `m5.2xlarge` | 8 | 32 | general | 0.384 | 1.0 |
| `c5.large` | 2 | 4 | compute | 0.085 | 1.3 |
| `c5.xlarge` | 4 | 8 | compute | 0.170 | 1.3 |
| `c5.2xlarge` | 8 | 16 | compute | 0.340 | 1.3 |
| `r5.large` | 2 | 16 | memory | 0.126 | 1.0 |
| `r5.xlarge` | 4 | 32 | memory | 0.252 | 1.0 |
| `r5.2xlarge` | 8 | 64 | memory | 0.504 | 1.0 |
| `x1e.xlarge` | 4 | 122 | memory | 0.834 | 1.0 |

Each family also has a `perfFactor`:

| Family | perfFactor | Character |
|---|---|---|
| t3 | 0.8 | burstable / cheap, slower core |
| m5 | 1.0 | general purpose |
| c5 | 1.3 | compute-optimized, fast core |
| r5 | 1.0 | memory-optimized |
| x1e | 1.0 | huge RAM |

### 6.4 perfFactor → service-time multiplier

A faster core makes CPU work finish faster:

```
serviceTimeMultiplier = 1 / effectivePerf
effectivePerf (cpu-bound) = perfFactor                       # full benefit
effectivePerf (io-bound)  = 1 + (perfFactor − 1) × 0.25      # damped
```

The damping for io-bound work encodes a real fact: a faster CPU barely helps a request
that's blocked waiting on disk or network. So a c5 speeds up a compute service a lot
and a datastore only a little. (Verified in-app: `c5.large` cpu-bound shows service
`×0.77`.)

### 6.5 The three caps (quota, cost, per-node) — all independent

Because capacity now costs money and hardware, we can enforce **three separate walls**:

1. **Per-node `maxInstances`** — an author-set ceiling; exceeding it is a *build-time*
   validation error. Without it, a student dodges a bottleneck by relocating "workers"
   into "instanceCount."
2. **Per-environment `resourceBudget {totalVcpu, totalRamGb}`** — a hardware/quota
   wall (you only have so much fleet).
3. **Per-environment `costBudget {maxPerHour}`** — a money wall, `Σ pricePerHour ×
   count`. **Independent** of the quota wall: you can pass one and fail the other.

Crucially, **cost is *always displayed*** (per-node and total), regardless of whether
any cap is set. "Unbounded" means *no gate*, never *no number*. This is honesty claim
#1 applied to money.

### 6.6 Pricing models

`pricingModel ∈ {on-demand, reserved, spot}` with multipliers `1.0 / 0.6 / 0.3`:

```
cost = pricePerHour × pricingMultiplier × instanceCount
```

So `c5.large` at $0.085/hr on spot = `0.085 × 0.3 = $0.026/hr`. (Spot's reclaim risk
is a hook for a future reliability-vs-cost question via fault injection.)

### 6.7 The demo that sells it

Scale `url-shortener`'s API Server from `c5.large ×1` to `×4`: p99 drops from ~156ms
to ~21ms — and the cost chip in the header climbs in lockstep. The student *watches
cost and SLO move together* — that is the real capacity-planning loop, not a slider
with no consequence.

### 6.8 The problem we hit / the tradeoff

**Problem:** the honest instance model made io-bound stores *too* powerful — a default
io-bound datastore gets 32 workers/vCPU, so it has huge headroom and won't saturate at
the suite's ~2-3k rps. Several bank questions (url-shortener, news-feed) stopped
discriminating because the bottleneck they relied on evaporated.

**Solution & tradeoff:** rather than weaken the model, we made bottlenecks a
*deliberate authored choice* — flip the specific store to **cpu-bound on a small
instance** (see §7.6). The tradeoff: authors now need to understand the execution
profile to place a bottleneck, and every existing question had to be migrated to the
instance model while *preserving its saturation point* (the "Dual-Topology Rule"
had to keep holding: ref PASS, gamed FAIL). That was a substantial migration — but the
result is that "more capacity" is now always a real, priced, capped tradeoff.

*Source: `instanceCatalog.ts`, `resourceDefaults.ts`, `resourceDerivation.ts`,
`analysis/cost.ts`, `resource-allocation-and-derived-concurrency.md`.*

---

## 7. Execution profiles: CPU-bound vs IO-bound

### 7.1 The question this answers

Drop a fresh service and a fresh database on the canvas, both on 2-vCPU instances,
turn on the **Concurrency** lens, and you'll see the service reads "**2 workers**" and
the database reads "**128 connections**." Students think it's a bug. **It's the
single most physically-correct thing in the tool.**

### 7.2 The principle — the profile is *per-tier*, not universal

A node's **execution profile** (`workloadKind: cpu-bound | io-bound`) reflects what it
actually does with a CPU core:

```
effectiveC = vCPU × instanceCount × workersPerVcpu
  workersPerVcpu = 1   (cpu-bound)   # CPU_WORKERS_PER_VCPU
  workersPerVcpu = 32  (io-bound)    # IO_WORKERS_PER_VCPU
```

- **cpu-bound** (1/vCPU): a compute service *occupies* the core computing. Real
  parallelism ≈ number of cores. Claiming 1000 workers on 4 vCPU just time-slices 4
  cores across 1000 half-done requests — that's *contention*, not throughput.
- **io-bound** (32/vCPU): a datastore, cache, load balancer, or broker spends almost
  all its time *waiting* on disk/network, so one core legitimately juggles many
  concurrent in-flight requests. Real anchors: a Postgres box serves hundreds of
  connections per core; Redis, brokers, and LBs likewise. The `32` is a tier-wide
  constant — generous but firmly tethered to paid hardware, never infinite.

### 7.3 Per-type defaults

- **cpu-bound:** `microservice`, `batch-worker`, `auth-service`, `search-service`,
  `container`, `vm-instance`, `edge-compute`, `gpu-node`, …
- **io-bound:** sources, `load-balancer`, `api-gateway`, all stores (`relational-db`,
  `nosql-db`, `in-memory-cache`, `time-series-db`, …), all messaging, CDN, storage.
- **Unknown types default to io-bound.**

### 7.4 Worked numbers

- API Server — `c5.large` (2 vCPU) × 1 × **cpu-bound (1)** = **2**
- Primary DB — `m5.xlarge` (4 vCPU) × 1 × **io-bound (32)** = **128**
- Redis — `r5.large` (2 vCPU) × 1 × **io-bound (32)** = **64**
- Load Balancer — `m5.large` (2 vCPU) × 1 × **io-bound (32)** = **64**

So "128 connections" is exactly `vCPU × 32` — correct, not inflated.

### 7.5 "One number, many labels"

The same derived `c` is shown under **per-type vocabulary**: **workers** (services),
**connections** (databases, LBs), **consumers** (brokers, queues), **ops** (caches).
The label is cosmetic; the physics is one quantity.

### 7.6 The bottleneck lever

Because io-bound stores have so much headroom, an author who wants a store to be the
**deliberate bottleneck** flips *that node* to **cpu-bound on a small instance**. In
`cache-placement`, the reference DB is a `t3.small` (2 vCPU) **cpu-bound** = **2
servers**. At read-heavy load it saturates, p99 collapses, and the cache becomes
mandatory — *that is the entire lesson,* and it's created by the execution profile,
not a hand-typed worker count.

### 7.7 What the profile does *not* change

- **Service time** — set by `processing.distribution` × instance perfFactor. Concurrency
  (`c`) and service time are **orthogonal** knobs.
- **Admission ceiling K** — set by RAM (`memCeiling`), not the profile.
- **Cost** — priced off the instance, independent of profile.

### 7.8 The lock

Whether a *student* can change a node's execution profile is gated by
`canEditExecutionProfile` — `true` in AUTHOR, `false` in ASSIGNMENT/PRACTICE — so a
graded student **cannot dodge a cpu-bound bottleneck by flipping it to io-bound.** A
`cost`-domain question unlocks resource editing when allocation *is* the lesson.

*Source: `execution-profile-and-node-concurrency.md`, `resourceDerivation.ts`.*

---

## 8. Edges: network physics vs dumb connectors

### 8.1 What an edge can model

An edge is a directed link with real properties:

- **latency** — either a path-type **constant** or a **log-normal** (jittered) draw.
- **`pathType`** — `same-rack | same-dc | cross-zone | cross-region | internet`, each
  with a latency profile (`PATH_TYPE_LATENCY_PROFILES`). same-rack is sub-ms;
  cross-region is ~60ms flat (v1 is *not* distance-aware).
- **bandwidth**, **`maxConcurrentRequests`** — throughput ceilings.
- **packet loss**, **error rate** — reliability.

### 8.2 Path-type inference from composite placement

There are **composite/layout nodes** — VPC Region, Availability Zone, Subnet — that
*contain* other nodes on the canvas. They have **zero engine effect of their own**;
instead, at serialize time we walk each node's container ancestry and set an edge's
`pathType` from the **deepest shared container**: same Subnet → same-rack; same AZ →
same-dc; same Region → cross-zone; different Region → cross-region. Containment uses
**center-inside** semantics (a node is captured when its *center* falls in the
container), which fixes the old bug where you couldn't wrap a container around an
already-built topology.

**Fill-defaults only:** we derive `pathType` *only* for edges still on defaults and
never overwrite a manually-set latency. Location shapes **latency only** — never
throughput or error rate (those are physically the service rate and the failure
system, not geography).

### 8.3 Conditional routing — the mix only matters if you route on it

An edge can carry a condition, e.g. `condition: request.type === "read"`. This is how
a topology sends reads to a cache and writes to the store. **Critical subtlety:** a
read/write *mix* in the workload has **no effect** unless the topology actually
**routes on `request.type`.** Distribution without type-routing = the ratio is inert
(this was a real bug — see §12.3).

### 8.4 `edgeModel`: network vs connector

An environment can set `edgeModel`:

- **`connector`** — a **dumb wire**: visual topology only, **zero simulation physics,
  zero egress cost, no editable properties, no edge lenses.** The point: let students
  focus on the *shape* of the HLD without getting pulled into edge sizing.
- **`network`** — edges carry real physics (and can be locked or editable via
  `canEditEdges`).

This composes with `canEditEdges` as a **ladder**: connector (dumb) → network+locked
(affects calc, inspectable, not editable) → network+editable. The deployed default is
**PRACTICE + connector** so a learner lands on the architecture, not edge math; an
author switches to Network via the Settings modal, and a `network`-domain question
forces network because *sizing the network is the lesson.*

Implementation elegance worth calling out: connector edges are neutralized at a
**single choke point** — the serializer's `neutralizeConnectorEdge()` sets latency 0,
same-rack path (free egress), infinite bandwidth, zero loss. Because both the
simulation run *and* the cost chip go through the serializer, that one function covers
both surfaces; the authored canvas data is left untouched.

*Source: `edge-properties-and-defaults.md`, `edgeLensPresentation.ts`,
`request-flow-direction-and-topology-rules.md`, `composite-nodes-v1-schema`.*

---

## 9. Traits: pluggable node behaviors

### 9.1 The trait system

Not every behavior belongs in the generic queue. A **trait** (`NodeBehaviourTrait` /
`NodeCapabilityModule`) is a plug-in with two halves:

1. **`hooks`** — the physics, firing at three points per request:
   - `beforeArrival(ctx)` — delay / reject / short-circuit a request as it reaches the
     node (GC pause, connection-pool wait, **cache hit**).
   - `beforeRouting(ctx)` — change the routing decision.
   - `filterRoutes(ctx)` — drop candidate routes.
2. **`config`** — declarative `sections: ConfigField[]` (path, type, label, `why`,
   altitude) that the UI renders **automatically** — no PropertiesPanel edits.

Registration: a module in `src/engine/traits/<trait>.ts`, listed in
`capabilityModules.ts`, attached to types via `appliesTo`, resolved by
`resolveTraits.ts`.

### 9.2 The cohesion win (and where it isn't free)

Because `node.config` is validated as a free-form record, **config validation never
breaks** and **the config UI is generated for free.** What is *not* automatic — and
where cohesion actually lives — is making the effect **visible and gradable**:
surface the metric in `output.ts` **and** `verdict.ts` (or a rubric `metric:` path
silently resolves to `undefined` and fails), add a canvas lens so students *see* it,
add a timeline glyph so they *watch it happen*.

### 9.3 The cache trait (deep) — inline pass-through

The cache is the flagship trait and the best one to teach. It's modeled as an
**inline pass-through**, not a separate routing dance:

- On `beforeArrival`, with probability `cacheHitRate`, the request is a **hit** — it's
  **served locally** (`handled`) and never touches the downstream store.
- With probability `1 − cacheHitRate`, it's a **miss** — it `continue`s downstream to
  the store.

Mathematically this is **Bernoulli thinning**: a fraction `hitRate` of arrivals is
"thinned off" and absorbed at the cache; the rest flow through. **We never model the
cache's *contents*** — only *which backend the request routes to*, which is all the
latency/throughput metric cares about. That's a deliberate, honest simplification.

The student's solution to `cache-placement` is therefore beautifully simple: drop a
default in-memory cache and wire the reads through it. The default `hitRate` (0.8)
auto-offloads 80% of reads. Vary `cacheHitRate` 0.5 → 0.9 and watch DB load fall.

**The actual shipped `cache-placement` reference topology (verbatim shape).** This is
the real `reference-topology.json` — teach it as the canonical worked answer:

```
nodes (5):
  client  api-endpoint      m5.large  ×1  io-bound
  lb      load-balancer     m5.large  ×1  io-bound
  svc     microservice      c5.large  ×1  io-bound
  cache   in-memory-cache   r5.large  ×1  io-bound
  db      relational-db     t3.small  ×1  cpu-bound   ← the deliberate bottleneck
edges (5):
  client → lb
  lb     → svc
  svc    → cache   condition: request.type === "read"     ← reads go to cache
  svc    → db      condition: request.type === "write"    ← writes go to DB
  cache  → db                                             ← cache misses fall through
```

Two things to point out:

1. **The bottleneck is the `t3.small` cpu-bound DB** (2 vCPU × 1 × cpu-bound = **2
   servers**). At the injected read-heavy load it saturates — *unless* the cache
   absorbs ~80% of reads first. That single instance/profile choice, not a hand-typed
   worker count, is what makes the question have a right answer.
2. **This reference uses explicit conditional edges** (`request.type === "read"` →
   cache, `"write"` → db) *as well as* the cache trait's own hit/miss thinning. So
   there are two valid teaching framings: (a) the *inline pass-through* framing above
   (drop a cache, let its `hitRate` do the thinning — no conditions needed), and (b)
   the *explicit routing-split* framing the shipped reference uses (type-conditional
   edges make the read/write split visible on the canvas). Both grade identically on
   the p99 axis; the routing-split version is more legible to a student reading the
   diagram, which is why the shipped reference chose it.

> **Two caching mechanisms, one source of truth (a subtlety for authors).** There are
> actually two ways to model caching: (1) the node-level cache trait above, and (2)
> *routing-level cache-aside*, where the source emits typed `READ_HIT`/`READ_MISS`
> requests and an upstream node routes them via conditional edges. For cache-aside
> scenarios, **routing-level is the source of truth**, and the per-node "Cache panel"
> (hit ratio) is only shown when a `cacheHitRate` is actually configured — otherwise
> an unconfigured cache counts every arrival as a "miss" and shows a misleading 0%.

### 9.4 Other traits

Cold-start, health-aware routing, content routing, service-time overrides, and a
planned failure-mode set (GC jitter, connection pool, cache stampede, data skew) —
each a self-contained "aha" and often a whole new question class.

**Grading-axis alignment (important rule):** correctness-style traits (idempotency
dedup, lock lease) are graded by **topology + justification**, *not* a simulation
metric — don't add a `summary.*` check for them. Performance traits (storage profile,
connection pool, GC jitter) *are* graded by simulation metrics. (This is the
performance/correctness boundary again — §16.)

*Source: `traits/*`, `trait-integration-guide.md`, `node-behaviour/node-behaviour-specification.md`,
`cache-aside-routing-split`.*

---

## 10. Cost model & budgets

### 10.1 The philosophy: only bill what the engine measures

Cloud pricing has ~9 dimensions. We deliberately model **only the three we can source
honestly** from quantities the engine actually measures, and refuse to invent the rest:

1. **Compute-time (provisioned):** `pricePerHour × count × pricingMultiplier`. Solid —
   it's the instance you chose.
2. **Request/invocation (consumption):** `pricePerMillionRequests × throughput`, from
   real MetricsCollector counts. This is the **serverless/Lambda** regime.
3. **Network egress (volume):** per-edge `bytes/duration × 3600 × $/GB`, keyed off the
   edge's `pathType` (same-dc free, cross-zone $0.01/GB, cross-region $0.02, internet
   $0.09). Estimated pre-run from the workload, **measured exactly post-run** from
   accumulated `bytesTransferred`.

**What we refuse to model** (because there's no honest quantity behind it):
storage-at-rest GB-month, per-user/MAU, subscriptions, %-of-spend, licensing, physical
hardware. If someone wants to "bolt on S3 storage pricing," the answer is no — there's
no stored-bytes quantity in the sim, so that number would be a lie.

### 10.2 The `costModel` primitive (per component type)

Each type carries a `costModel`:

- **`provisioned`** — instance-hours (a pure function; live pre-run). Most compute/stores.
- **`consumption`** — per-request (serverless-function = $0.20/M req).
- **`volume`** — per-GB egress (CDN, object-storage — priced on traffic, *not* on the
  instance placeholder; this fixed a dishonest "m5.large on a CDN" artifact).
- **`none`** — sources.

**The core lesson this unlocks:** *provisioned vs. consumption regime* — an always-on
fleet ($/hr no matter the traffic) versus serverless (pay per request). Both normalize
to $/hr, so they're **comparable**, so a student can ask *"which is cheaper at this
traffic shape?"* — the real capacity-planning question.

### 10.3 Budgets — two independent walls

- **`resourceBudget {totalVcpu, totalRamGb}`** — the quota/hardware wall.
- **`costBudget {maxPerHour}`** — the money wall (`Σ pricePerHour × count`).

They're **independent** — you can be within your vCPU quota but over your dollar
budget, or vice-versa. Both are optional (absent = unbounded), and **cost is always
displayed regardless.** There's also a graded `budget` rubric axis (`unit: cost/nodes/
edges`, a build-time heuristic) that is distinct from the always-on live cost chip.

### 10.4 The problem we hit / the tradeoff

**Problem:** the original `ResourceConfig` (cpu/memory/replicas) was *scored* by the
grader but **never read by the engine** — pure decoration. `replicas` earned points but
didn't multiply concurrency, so the score rewarded what the physics ignored.

**Solution & tradeoff:** we made cost and concurrency both flow from the *same* real
instance model (§6), so the number you're graded on and the number the physics runs are
the same number. The tradeoff is that cost is now "only" as rich as three honest axes —
we gave up the breadth of a full cloud-billing model in exchange for never displaying an
invented number. That's honesty claim #1 again: better to model three things truthfully
than nine things fictionally.

*Source: `cost.ts`, `cost-calculation-and-budgeting.md`, `budget/*`.*

---

## 11. Metrics, aggregation & the honesty doctrine

### 11.1 The doctrine

> **Every UI view is a mechanical projection of one rich per-request truth**, designed
> around the operator's first question: *is this component dead, sick, or overloaded?*

We don't compute UI numbers ad hoc; we record one honest per-request record and
*project* every view from it. That projection discipline is what keeps the views
mutually consistent (the books balance).

### 11.2 The machinery

- **`Hist`** — an HDR-style histogram for latency percentiles.
- **`WindowedLatencyAggregator`** — 1-second tumbling windows, per-cause error
  histograms, all fed through a **single `recordTerminal` funnel** in the
  `MetricsCollector`. System-wide and per-node aggregators share *identical math* (the
  same functions, parameterized by which aggregator) so a per-node p95 and a
  system p95 mean the same thing.
- **Latency decomposition** — `decomposeLatency(createdAt, hops, spans, terminal)`
  splits end-to-end latency into **edge / queue / service** contributions that **sum
  exactly** (any residual is labeled `unattributed`, never hidden). This is the "where
  did the time go?" verdict.
- **Failure-by-locus Pareto** — every failure is attributed to the exact node or edge
  it died at (`failuresByLocus`), bottleneck-first, each with a dominant cause. Edge
  drops attribute to the *edge*, never the node behind it. Totals reconcile exactly
  with the time-to-error samples.

### 11.3 The rules that keep numbers honest

1. **Time-weighted integrals, never point samples** (§4.5).
2. **Post-warmup gating** — steady-state only; the transient is excluded everywhere.
3. **Percentiles don't sum across hops** — you cannot add per-hop p99s to get an
   end-to-end p99 (tails don't add). We report end-to-end percentiles from the
   end-to-end histogram, and decomposition for *where* the time went — two different,
   both-honest views.
4. **`null` → "N/A", never a fake `0`.** If there were no successful requests, the
   success-latency is `N/A`, not a comforting zero.
5. **Every number renders its population/window/locus inline** — "node-local · 512
   served," "over successes only, 8% failed" — not buried in a tooltip. **Status first,
   numbers second.**

### 11.4 The canvas-badge honesty fix (a concrete example)

A node's latency badge used to show a green ✓ based on latency alone — so an
*overloaded, mostly-failing* node could still look healthy because its handful of
*surviving* requests were fast (survivor bias). The fix: the latency lens now gates its
✓ on the node's **error rate** (`worseTone(sloTone, errorTone)`) and annotates "over
successes only, X% failed." No more green checkmark on a node that's on fire.

*Source: `metrics.ts`, `windowedLatencyAggregator.ts`, `analysis/phaseTimeline.ts`,
`analysis/output.ts`, `honesty-redesign-roadmap`, `no-point-sampled-scalars`.*

---

## 12. Workload & scale

### 12.1 Who owns the load

There are two workload surfaces, and the distinction is an anti-gaming cornerstone:

- **The student's dry-run scenario** — what they can play with while designing (RPS,
  pattern). Ungraded.
- **`suite.cases[].workload`** — the **question-owned, injected** load used at grade
  time. The student **cannot** lower it, reseed it, or change the mix. It's applied
  *over their topology* by `mergeTopologyWithOverrides` at grade time.

### 12.2 What a workload contains

- **`baseRps`** — the arrival rate the sim actually runs.
- **`requestDistribution`** — typed request classes with weights and `sizeBytes`, e.g.
  `[{type:"read", weight:0.99}, {type:"write", weight:0.01}]`.
- **pattern** — `constant | poisson | bursty | …` (the *arrival process* shape). A
  constant (D/D) edge gives clockwork arrivals; a log-normal/poisson process gives
  jitter, which — per the hockey stick — causes rejections a constant process wouldn't.

### 12.3 The 99:1 display-only bug (a great teaching story)

`prompt.scale.readWriteRatio` was rendered as a nice "99:1" chip in the UI but **never
converted into `workload.requestDistribution`.** So a URL-shortener that *claimed* 99:1
actually ran **GET 100%** in the sim. `peakRps` was wired; the ratio wasn't. The lesson:
**a number that's only displayed is not a number that's simulated.** The authoring
contract now demands *no orphan requirements* — every scale number must land in the
workload, every FR in structure, every perf-NFR in the rubric.

Also recall §8.3: even a correctly-injected mix does nothing **unless the topology
routes on `request.type`.** The read-heavy→cache→p99-passes loop only closes when the
mix *and* the type-routing *and* the cache all line up. When they do, the discrimination
is razor-sharp: cached → p99 8ms, 4/4 pass; no cache → store util 1.0, p99 1003ms (100%
timeouts), 1/4 fail.

### 12.4 Tractable vs. display scale — and "scale-invariance of discrimination"

A prompt might say "200,000 rps," but the sim runs `baseRps` ≈ 2,000. **Why is that
honest?** Because what determines whether a design breaks is the **offered/capacity
ratio**, not the absolute number. If you downscale rps *and* capacity together, the
ratio — and therefore the saturation behavior — is preserved. Running 200k rps would
just be 100× slower for zero extra discrimination (indeed a 20k-rps sim times out in
>2 min; the suite runs a representative ~2k slice).

### 12.5 The dry-run-vs-graded-load trap (teach it openly)

The most dangerous student experience: dry-run at 100 rps, everything's green, feel
confident — then the **graded peak at 2k rps saturates** the under-provisioned node and
the design fails. This is not a bug; it's the *point* (the hockey stick means "fine at
100, dead at 2k" is real physics). But it's a UX sharp edge worth naming so students
learn to test at the stated scale.

*Source: `request-type-model.md`, `request-pattern-configuration.md`,
`question-simulation-alignment`.*

---

# Part II — Turning it into a Course: authoring & grading

Part I built an instrument. Part II is how we turn that instrument into *fair,
un-gameable questions.* This is the intellectual core of "how I came up with how to
create, grade, and evaluate questions."

## 13. The grading DSL & the five orthogonal axes

### 13.1 The central finding: single-axis grading *is* gaming

Faculty grade a design on multiple axes; a simulator that grades on only **one** is
trivially gameable, because **any single axis is exploitable:**

- Grade only on **simulation metrics** → crank one node's capacity/timeout until the
  metric passes, with the wrong architecture. ("200K writes to a single SQL" can pass a
  *lenient* sim.)
- Grade only on **node presence** → the **kitchen-sink**: drop every component and wire
  everything to everything to satisfy every `requires_X`.
- Grade **justification by keyword match** → keyword-stuffing.

So anti-gaming isn't a feature bolted on afterward — it's the **organizing principle**:
grade on **≥3 orthogonal axes + a graph-consistent justification + a cost budget**, so
that gaming one axis is caught by another.

### 13.2 The five axes (T / S / Σ / J / $)

| Axis | Symbol | What it grades | Mechanism |
|---|---|---|---|
| **Topology** | T | node/edge presence, placement, direction, fan-out | `structuralRules`, `semanticCriteria.ts` |
| **Scale-fit semantics** | S | storage type fits the access pattern; consistency claims | `storageFit`, guardedPath |
| **Simulation** | Σ | behavior under load meets NFR targets | `rubric.checks` over verdict metrics |
| **Justification** | J | reasoning is real and graph-consistent | `justification.ts` |
| **Budget** | $ | total cost/nodes/edges under a cap | `budget` check |

### 13.3 The reasoning spine we're eliciting

Every good answer follows one spine, and every check exists to verify some instance of it:

```
Requirements (FR + NFR) → API / Data Model → Capacity (the numbers)
   → HLD node-by-node "why each box exists" → Bottlenecks & Tradeoffs
```

The target sentence we grade, verbatim from the interview-prep canon:

> **"I'm choosing X because [number], the tradeoff is Y."**

and its closing frame: *"The workload is [read-/write-/connection-/correctness-heavy],
so I optimized for X and accepted Y."*

### 13.4 The check-kind taxonomy

Every rubric criterion is one of these — each a **pure function of the graph (+ scale +
justification)** returning pass / partial / fail, optionally `hardFail`:

| kind | passes when | example |
|---|---|---|
| `structural` | required nodes present (min/max counts) | "API Gateway present" |
| `placement` | node in required position (`between`, `notBefore`, `orderedPipeline`) | cache between service↔DB, not before LB |
| `direction` | traffic flows the correct way; no reverse/bypass edge | redirect path, no Client→DB shortcut |
| `guardedPath` | **all** `from→to` traffic traverses a guard (no bypass) | rate-limiter→shared cache |
| `fanout` | a **broker** fans out to N consumers (a *queue* to N ≠ fan-out) | 1 broker + 3 consumers ✅ |
| `storageFit` | store type matches the access pattern; anti-patterns flagged | time-series → wide-column, SQL = fail |
| `simulation` | verdict metric meets NFR target under injected load | p99 < 15s SLA |
| `justification` | names a real node + cites a real number + states a tradeoff, graph-consistent | every "justify" prompt |
| `forbidUnjustified` | component absent, OR present *and* defended | CDN must be absent or justified |
| `budget` | total cost/nodes/edges ≤ cap | anti-kitchen-sink |

### 13.5 The evaluation algorithms (how the clever ones actually work)

These ship in `src/engine/analysis/semanticCriteria.ts` as deterministic graph
computations (BFS/reachability), returning `passed | partial | failed`. Points are
**full** (passed), **⌊points/2⌋** (partial), or **zero** (failed); a failing `hardFail`
drops the whole question's `allPassed`.

- **`guardedPath(from, guard, to?)`** — the cleverest one. Confirm `to` is reachable
  from `from`; then **rebuild the graph with the guard nodes removed** and re-run
  reachability. **Fails if a `from→to` path *survives* guard removal** — i.e. an
  unguarded *bypass* exists. This is how you enforce "**all** traffic must go through
  the cache/lock/rate-limiter," not merely "a path through it exists."
- **`placement`** — `between[A,B]`: some node is reachable from an A *and* reaches a B.
  `notBefore X`: no node reaches an X upstream. `orderedPipeline[T₁..Tₙ]`: layered
  reachability, each stage's frontier must reach the next type.
- **`fanout`** — for each `broker` node, count **distinct** out-edge targets; pass if
  any ≥ `minConsumers`. If a **forbidden** broker (queue semantics) meets the count
  instead, hard-fail with "queue ≠ fan-out."
- **`storageFit`** — classify the store types present: any `antiPattern` present →
  fail; else any `accept` present → pass; else `partial` → partial; else fail.
- **`forbidUnjustified`** — absent ⇒ pass; present ⇒ pass only if the bound
  justification passed (conservatively fails if undefended).

**Ordering:** semantic criteria run **after** the structural gate passes; a
structurally-broken topology short-circuits *before* simulation and semantics (don't
waste a 2-minute run on a graph that's already disqualified).

### 13.6 The justification model — deterministic, un-stuffable, no LLM

**Decision: structured, graph-consistent justification — not keyword matching, not an
LLM judge.** A prompt is *bound to a decision* and graded on three requirements:

1. **Graph-consistency (the anti-stuffing core).** The claimed choice must match
   what's *actually in the student's graph.* If the text says "I used Cassandra for
   throughput" but the graph has a SQL node on that path → **fail**, and the mismatch is
   surfaced. **You cannot write a correct-sounding justification for a wrong graph.**
2. **Number-citation.** Must cite a scale number the question actually defines
   (randomized per attempt), so memorized prose from a reference answer doesn't fit.
3. **Tradeoff presence.** Must name a real cost/limitation (matched against authored
   tradeoff tokens plus a "not a non-answer" check).

This makes the justification a **cross-check on the topology,** not a parallel prose
channel — which is exactly what defeats keyword-stuffing, deterministically, at zero
per-grade cost.

*Source: `structural.ts`, `semanticCriteria.ts`, `rubric.ts`, `justification.ts`,
`authoringValidator.ts`, `evaluation-authoring-reference-manual.md` (the master DSL),
`question-grading-model-and-anti-gaming.md`.*

---

## 14. Anti-gaming & the Dual-Topology Rule

### 14.1 The test/architecture split (the single most important rule)

> **The question owns the test conditions; the student owns only the architecture.**

| Surface | Owner | Why |
|---|---|---|
| Workload (RPS, pattern, mix, sizes) | **question** | else the student sets a 1-rps all-hit load and passes trivially |
| Global run config (seed, duration, warmup) | **question** | else the student shortens the run or farms lucky seeds |
| Fault injection | **question** | the student can't opt out of the scenario they're graded on |
| Node design config (instance, profile) | **student (bounded)** | but priced & capped — cranking is caught by $ + physics |
| Edge design config | **student (bounded)** | same — real ceilings + edge cost |

This split is already how the engine works: `QuestionSuiteCase` carries `global` /
`workload` / `faults` overrides that `gradeAttempt` injects. The graded scenario is
**authored, not student-supplied.**

### 14.2 The gaming matrix (each exploit → its catcher)

| Exploit | Caught by |
|---|---|
| Node kitchen-sink | `budget` · `forbidUnjustified` · max-count · sim ignores unwired nodes |
| Edge kitchen-sink | edge `budget` · `direction` (specific paths) |
| Crank one node's capacity | derived-and-locked concurrency · node cost · `storageFit` is config-independent |
| Edge tuning (`bandwidth=∞`, `errorRate=0`) | edge cost · faithful edge bounds |
| Workload tampering | **question injects the workload** |
| Seed/run tampering | **question fixes seed + duration**; `maxTestRuns` caps attempts |
| Keyword-stuffing | graph-consistent `justification` |
| Wrong-but-passes-sim | workload **derived from scale numbers** so load genuinely stresses it |
| Copy a reference diagram | **randomize scale numbers per attempt** + novel prompts |
| Decorative/disconnected nodes | connectivity/`direction`; unwired nodes cost but give no metric benefit |

### 14.3 The Dual-Topology Rule — an *executable definition of a good question*

This is the crown jewel of the authoring philosophy, and the answer to "how do you
*know* a question is fair?"

> **A question is valid only if the *reference* topology PASSES and a known *gamed*
> shortcut FAILS on the intended axis. If the gamed design also passes, the question is
> rejected as under-constrained.**

This is the architecture-world equivalent of **hidden test cases.** You don't just
write a good answer; you write the *most tempting wrong answer* and *prove the grader
catches it.* The validator that runs both is
`scripts/validate-question-dir.ts` (~2 min across the bank), and the discipline is:
after **every** engine change, re-run it across all questions to prove references still
pass and gamed still fails on the intended axis.

**The lesson (state it as a principle):** *gaming is a bug we test for before ship.* If
you can't author a gamed topology that fails, you haven't found the thing your question
actually tests.

### 14.4 The problem we hit / the tradeoff

**Problem:** the validation harness only graded the ref/gamed *fixtures* — never what a
student *actually builds from the palette.* We discovered a cache-placement question
where a student's palette-default build gave p99 ~170ms **with or without** a cache:
unsolvable *and* the cache was irrelevant, because the palette defaults (exponential
service, io-bound stores) didn't match the old hand-tuned constant/cpu-bound fixtures.

**Solution & tradeoff:** two moves together — (1) fix the genuinely-wrong defaults (the
api-endpoint 68.5ms bug), and (2) **scaffold-pin**: ship the question as a *partial
scaffold* with the client/LB/service/DB pinned (constant service, the DB deliberately
`t3.small` cpu-bound = the bottleneck, `lockedNodeIds` so it can't be resized away).
The student's job becomes the *actual lesson*: drop a cache and rewire. The tradeoff:
authoring is more work (you must pin a defensible bottleneck and lock it), and the
"empty canvas" ideal gives way to a guided scaffold. We accept it because a question
that's only solvable in a hand-tuned fixture — but not from the palette a student
actually uses — isn't a real question.

---

## 15. Environment profiles & capabilities

### 15.1 Three modes

- **AUTHOR** — full control; everything editable; used to build questions.
- **ASSIGNMENT** — graded; locked down (fixed resources/edges, capped test runs).
- **PRACTICE** — ungraded sandbox; free edit; **connector edges.**

The **deployed/standalone default is PRACTICE + connector**, so a learner lands on the
HLD, not on edge physics. Newton's graded host forces ASSIGNMENT on its own path, so the
default never overrides a graded launch.

### 15.2 Capabilities (the knobs a profile sets)

`editPaletteList`, `canEditScaffoldNodes`, `canEditEdges`, `canEditResources`,
`canEditExecutionProfile`, `edgeModel` (network/connector), `maxTestRuns`,
`resourceBudget` / `costBudget`, and visibility flags.

### 15.3 Domain overrides — the lesson unlocks the knob

A question's `domains` can *override* a capability when the locked thing **is** the
lesson:

- a **`network`-domain** question forces `edgeModel: network` and editable edges —
  *sizing the network is the point.*
- a **`cost`-domain** question unlocks `canEditResources` (and the execution profile) —
  *allocation within a budget is the point.*

This is a clean design principle: **default to locked, unlock exactly the axis the
question teaches.** A student can't dodge a cpu-bound bottleneck by flipping the profile
*unless* the question is *about* the profile.

*Source: `environmentProfile.ts`, `environment-definition-and-configuration-model.md`,
`system-design-leetcode-environment-model.md`, `resource-allocation-derived-concurrency`.*

---

## 16. The performance/correctness boundary

This is the most intellectually honest part of the whole system, and a keynote-worthy
point on its own.

**Some invariants are simulatable; some are not — and we refuse to fake the ones that
aren't.**

- **Performance invariants** — latency, throughput, utilization, saturation — are
  exactly what queueing physics decides. → graded by the **simulation (Σ)** axis.
- **Correctness invariants** — exactly-once, no-double-booking, dedup, immutability,
  ordering, "generates the *right* short code" — the metrics engine models neither
  contention nor content, so it **cannot** decide these. → graded by **topology
  (structural + guardedPath) + justification (J)**, *never* by a latency number.

**Topology-as-proxy** is how we still grade the un-simulatable: "generate a unique code"
isn't simulatable, but "a durable store sits on the write path" is a **structural
proxy**, and a **justification prompt** carries the nuance ("why a durable store, what's
the tradeoff"). We assert the *shape* that the correct behavior requires, and require the
student to *explain* it.

**Why the boundary is a feature, not a limitation:** the moment you let a latency number
stand in for "exactly-once," you've shipped a lie. Being explicit about the boundary
(and refusing to author a `simulation` check for a correctness property — the authoring
validator flags it) is what keeps every green checkmark *true.* Honesty about what you
*can't* do is what makes the things you *can* do trustworthy.

*Source: `question-simulation-alignment`, grading model §11.2,
`simulator-request-workload-model-gaps` (Request has no body/endpoint/response-code — so
"301 vs 302, base62, request body" are narrative/justify context, never sim checks).*

---

## 17. Authoring a question end-to-end (capstone walkthrough)

Put it all together with a fresh problem, e.g. a **write-heavy sensor store.**

1. **Write the prompt.** FRs (ingest readings, query recent), NFRs (p99 write < X ms at
   scale), and a scale block (writes/sec, access pattern = time-series). *No orphan
   requirements:* every FR → structure, every perf-NFR → rubric, every scale number →
   workload.
2. **Choose the discriminating axes.** For a write-heavy store the sharp axes are
   **`storageFit`** (time-series-db/columnar accept; relational-db anti-pattern,
   hardFail) and a **simulation** p99 check under the injected write load. Maybe a
   **justification** ("why this store for 200k writes/s, tradeoff?").
3. **Author the *reference* topology** — the design you claim is good. Tune the
   bottleneck **through the instance model** (§6/§7): make the naïve store choice
   saturate (e.g. relational on a small cpu-bound instance) so the *correct* store choice
   is what passes.
4. **Author the *gamed* topology** — the most tempting shortcut (SQL + cranked
   instanceCount, or a kitchen-sink of stores). Prove it **fails on the intended axis**
   (`storageFit` hard-fails independent of the sim; kitchen-sink trips `budget`).
5. **Validate dual-topology** — `validate-question-dir.ts`: reference PASSES, gamed
   FAILS on the intended axis, and the question is *not* under-constrained. Fix the
   metric keys (`summary.latency.p99`, **not** `summary.latencyP99Ms` — a real bug that
   silently resolved to `undefined`), the scale-vs-mix wiring, and the scaffold pins
   until both hold.
6. **Convert to the host format** — Django rows (SIMULATOR_CONFIG + STRUCTURAL_RULE /
   SEMANTIC_CRITERION / RUBRIC_CHECK) for Newton, or ship the standalone `question.json`.

The recurring authoring contract: **every requirement maps to a check; no requirement is
an orphan; the reference passes with margin; the gamed design fails clearly.**

### 17.1 A full annotated `question.json` (the real `cache-placement`)

Here is the actual shipped question, annotated. This is the single best artifact to
project when teaching authoring — every field ties back to a concept from Parts I–II.

```jsonc
{
  "version": "1.0",
  "id": "cache-placement",
  "title": "Scale a read-hot product API",
  "difficulty": "beginner",
  "type": "open-build",              // task shape: build a topology on an (empty) canvas
  "workloadCategory": "read-heavy",  // author-side axis selector (§12); NOT shown to student

  "prompt": {
    "text": "…All traffic must enter through a load balancer, reach the service, and
             read from the primary database. Introduce a cache so reads are shielded…
             Target: read p99 < 120 ms at peak. Traffic: 20,000 peak RPS at 95:5 read:write.",
    "functionalRequirements": [      // each FR → a topology (T) check below
      "Route all traffic through the load balancer before the service.",
      "Serve reads through a cache between the service and the database."
    ],
    "nonFunctionalRequirements": [   // each perf-NFR → a simulation (Σ) rubric check
      { "metric": "latency_p99", "operator": "<", "value": 120, "unit": "ms",
        "description": "Read p99 under 120 ms at peak." }
    ],
    "scale": { "peakRps": 20000, "readWriteRatio": 95 }  // DISPLAY numbers (the panel)
  },

  "scaffold": { "type": "empty" },   // student builds from scratch (vs. a partial scaffold)
  "constraints": { "canModifyScaffold": true, "maxNodeCount": 10 },  // anti-kitchen-sink cap

  "structuralRules": [               // AXIS T — presence/shape, pure graph checks
    { "id": "has-lb",  "kind": "requires_component", "componentType": "load-balancer" },
    { "id": "single-source", "kind": "requires_single_source" }
  ],

  "semanticCriteria": [              // AXIS S — placement/fit, pure graph checks
    { "id": "cache-between", "kind": "placement", "componentType": "in-memory-cache",
      "between": ["microservice", "relational-db"],   // cache on the svc→db path
      "notBefore": "load-balancer",                   // …never in front of the LB
      "points": 4, "hardFail": false }
  ],

  "suite": {                         // QUESTION-OWNED injected load (§14.1) — student can't touch
    "visibleToStudent": false,
    "cases": [
      { "id": "peak",
        "workload": {                // the DERIVED, TRACTABLE load (2k rps, not 20k — §12.4)
          "baseRps": 2000,
          "requestDistribution": [   // the 95:5 ratio, actually injected as typed traffic
            { "type": "read",  "weight": 0.95, "sizeBytes": 256 },
            { "type": "write", "weight": 0.05, "sizeBytes": 512 }
          ] } }
    ]
  },

  "rubric": {                        // AXIS Σ — the simulation verdict checks
    "passThreshold": 1,
    "checks": [
      { "id": "p99", "kind": "simulation",
        "metric": "summary.latency.p99",   // ← REAL verdict key (NOT summary.latencyP99Ms!)
        "op": "<", "value": 120, "points": 3 },
      { "id": "no-invariants", "kind": "invariant",
        "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
    ]
  },

  "domains": ["compute"],            // scoping: locks edges (network lever removed), §15.3
  "concepts": ["cache-placement"]
}
```

Read it top to bottom and every earlier concept appears: the *display scale* (20k) vs
the *tractable injected scale* (2k) — §12.4; the read/write *mix as typed traffic* —
§12.2/§12.3; the *five axes* wired as `structuralRules` (T), `semanticCriteria` (S),
`rubric` (Σ); the *question-owned workload* — §14.1; the *real verdict key* pitfall —
§17 step 5; and `domains: ["compute"]` *locking edges* — §15.3.

---

# Part II-B — Translating **any** online interview question into the simulator

This is the practical heart of authoring: given a system-design interview question you
found online (URL shortener, rate limiter, Ticketmaster, a news feed, …), how do you
turn it into a *simulator-gradeable question* — and how do you know when you *can't*
(and what to do instead)? This part is a repeatable procedure plus a worked catalog.

## 18. Why a generic translation is even possible

The canonical interview questions repeat. The industry-standard set — the ones every
prep site lists — is small: **URL shortener, news feed / social feed, chat/messaging,
rate limiter, notification/push, distributed cache, ride-hailing dispatch, video
streaming, payment/ledger, search autocomplete, web crawler, ticket booking
(Ticketmaster), metrics/monitoring pipeline.** (See Sources at the end of this part.)

The key insight: **you don't translate the *whole* question — you translate its
*dominant bottleneck*.** Every one of these questions, stripped to its teachable core,
is one (occasionally two) of a *small, finite set of bottleneck families*. Translation
is therefore: **identify the bottleneck family → map it to what the simulator can model
→ pick the discriminating axis → author reference + gamed → validate dual-topology.**

## 19. The six bottleneck families (the whole translation key)

Every interview question lands in one or more of these. The table tells you, for each,
**the fix, what the simulator does today, and which grading axis carries it** — this is
the single most useful thing to memorize.

| # | Family | The bottleneck | Architectural fix | Simulator status | Graded by |
|---|---|---|---|---|---|
| **F1** | **Compute & capacity** | reads/work overwhelm a node; sync tier blocks on a slow downstream | cache in front; queue + workers to decouple | ✅ **Physics** (cache trait, ackAndRelease, derived concurrency saturate & relieve) | **Σ** p99/throughput (+ T placement) |
| **F2** | **Storage & state** | wrong store for the access pattern; fan-out; write saturation | pick the fitting store; broker 1→N; wide-column for writes | 🟡 **Structural/semantic** (stores are physically similar until `storageProfile`; broker doesn't truly broadcast yet) | **S** `storageFit` / `fanout` |
| **F3** | **Network & edge** | connection/port exhaustion; bandwidth; geo-latency | multiplexers, CDN, multi-region | ❌ **Deferred (V2)** (edges have latency/bandwidth, but pool/geo traits unbuilt) | **T** + edge props (partial) |
| **F4** | **Resilience & chaos** | cascading failure; retry storms; DC failover | circuit breaker, rate limiter, DR steering | 🟡 **Partial** (traits exist, fault-injection not fully wired) | **T** + **J** (justify) |
| **F5** | **Correctness** | double-booking; exactly-once; ordering | distributed lock; idempotency key store; ledger | 🟡 **Topology + justification** (sim can't model contention/dedup — §16) | **T** `guardedPath` + **J** |
| **F6** | **Cost / meta** | solve within a budget; brute force vs. elegance | one cache beats ten replicas | 🟡/❌ (live cost chip works; graded budget axis is v1 heuristic) | **$** budget |

**The one rule that makes translation honest:** *grade the family the simulator can
actually decide, and route everything else to topology + justification.* If the
question's whole point is F5 correctness (Ticketmaster's no-double-book), do **not**
fake a `simulation` check for it — that's the performance/correctness boundary (§16).
Grade the *guard structure* it requires and *make the student justify it.*

## 20. The translation procedure (do this every time)

A repeatable 8-step recipe. Follow it for any question you pull off the web.

**Step 1 — Extract FRs, NFRs, and the scale numbers.** Copy the prompt. List functional
requirements ("shorten a URL," "redirect," "rate-limit per user"), non-functional
targets ("p99 < 200ms," "99.9% availability"), and every *number* ("100M URLs," "100:1
read:write," "10k rps"). If the source doesn't state numbers, invent defensible ones —
you need them to drive load and to require in justifications.

**Step 2 — Name the dominant bottleneck family (§19).** Ask: *"what is the one thing
that breaks at scale here, and what family is it?"* URL shortener → F1 read-heavy (+ F2
store-fit). Rate limiter → F5 correctness (shared counter). Ticketmaster → F5
contention. Web crawler → F1 async pipeline. This decision drives everything else.

**Step 3 — Decide what's simulatable vs. structural (the §16 boundary).** Split each
requirement:
- **Performance** (latency/throughput/util/saturation) → a **simulation (Σ)** rubric
  check. *These are real, felt, un-gameable.*
- **Correctness** (exactly-once, no-double-book, ordering, "right code") → a **topology
  (T) `guardedPath`/`structural`** proxy + a **justification (J)** prompt. *Never a Σ
  check.*
- **Scale-fit** (which store for this access pattern) → a **semantic (S) `storageFit`**.

**Step 4 — Choose the discriminating axis and the tempting wrong answer.** For the
question to be fair, there must be a *specific* thing a lazy student does that fails.
Write that gamed design down now: "puts everything on one SQL," "skips the cache,"
"uses a work-queue instead of a broker," "per-instance rate-limit counters." *This is
the thing your checks must catch.*

**Step 5 — Set the workload (question-owned).** Convert the scale numbers into
`suite.cases[].workload`: a **tractable `baseRps`** (~2–5k, not the headline 200k —
§12.4), and a `requestDistribution` encoding the read/write (or typed) mix with
`sizeBytes`. **Only inject the mix if the topology will route on `request.type`** —
otherwise the ratio is inert (§8.3, §12.3). Fix the seed and duration (anti-farming).

**Step 6 — Author the reference topology and tune the bottleneck via the instance
model.** Build the design you claim is good. Make the *naïve* choice actually saturate
by sizing it honestly: put the store the lazy student would over-use on a **small
cpu-bound instance** (§7.6) so it bites, and give the correct component (the cache, the
right store) enough headroom to pass. *Never* hand-type a worker count — derive it.

**Step 7 — Author the gamed topology and prove it fails on the intended axis.** Build
the tempting wrong answer from Step 4. Run both through
`scripts/validate-question-dir.ts`: **reference PASSES, gamed FAILS on the intended
axis.** If the gamed design also passes, the question is *under-constrained* — add a
check (a `storageFit` hard-fail, a `guardedPath`, a `budget` cap) until it fails.

**Step 8 — Scope with `domains` and ship.** Set `domains` (e.g. `["compute"]` locks
edges so pipe-tuning can't substitute for the cache lesson; `["storage"]` expects a
`storageFit`; `["correctness"]` expects a `justify`). The authoring validator warns if a
declared domain isn't backed by a matching check. Convert to Django rows for Newton, or
ship the standalone `question.json`.

## 21. Worked translations of the canonical questions

Each row is a full translation you can lift. "Discriminator" = the gamed design your
checks must fail; "Axis" = which of T/S/Σ/J/$ carries the grade.

### 21.1 URL shortener — *F1 read-heavy + F2 store-fit* ✅ fully simulatable
- **Requirements:** shorten (write), redirect (read); 100:1 read:write; p99 redirect < X ms.
- **Simulatable:** the read-heavy p99 (Σ). **Structural:** KV store fits point-lookup (S
  `storageFit`), cache on the read path (S `placement`).
- **Reference:** source → LB → service → **cache** (reads) → **kv-store**; writes → kv-store.
  Store sized so that *without* the cache it saturates at the injected read load.
- **Discriminator (must fail):** (a) no cache → read p99 blows the SLO (Σ fails); (b)
  `relational-db` instead of KV → `storageFit` anti-pattern fails (S).
- **Justify:** "why KV not SQL for short→long? cite the read:write number; tradeoff = no
  ad-hoc joins." (Note: *"generate a unique base62 code"* is **not** simulatable — it's
  a `guardedPath` to a durable store + a justification, per §16.)

### 21.2 Rate limiter — *F5 correctness (shared state)* 🟡 topology + justification
- **Requirements:** limit N req/user/window; correct under many app instances.
- **Not simulatable:** the *correctness* of counting (the sim doesn't model shared-counter
  contention). **So grade the structure:** `guardedPath(rate-limiter → shared cache)` —
  **all** checks must traverse a *shared* store (remove the guard → no bypass survives,
  §13.5), which **fails per-instance in-memory counters** (the classic wrong answer).
- **Discriminator (must fail):** rate-limiter with a *local* counter and no edge to a
  shared Redis → `guardedPath` fails; a structural rule forbids the no-shared-store shape.
- **Justify:** "which algorithm (token bucket / sliding window) and why; why a cache not a
  DB for counters — cite the ~ms budget; tradeoff." No Σ check for correctness.

### 21.3 News feed — *F1 read-heavy + F2 fan-out* ✅/🟡
- **Requirements:** post (write) fans out to followers; feed read is fast; 50:1 read:write.
- **Simulatable:** feed-read p99 with a read cache (Σ). **Structural:** `fanout`
  (fan-out-on-write from a broker to N timeline consumers — a *queue* to N is the wrong
  shape, §13.5), `storageFit` for the timeline store.
- **Reference:** write path → **message-broker** → N timeline workers → timeline store;
  read path → **cache** → feed. **Discriminator:** (a) synchronous fan-out on the read
  path → feed p99 fails (Σ); (b) a *work-queue* (1-of-N) instead of a broadcast broker
  (1→N) → `fanout` hard-fails.

### 21.4 Ticketmaster / ticket booking — *F5 contention* 🟡 topology + justification
- **Requirements:** no double-booking of a seat; virtual waiting queue under a flash sale.
- **Not simulatable:** mutual exclusion / no-double-book (contention isn't modeled — §16).
  **Grade the structure:** `guardedPath(booking → lock-store/transactional-db)` so **all**
  booking traffic traverses the guard; `structural` for the admission/waiting queue.
- **Discriminator (must fail):** a booking path that reaches the seat store *without*
  going through the lock/transaction guard (a bypass edge) → `guardedPath` fails.
- **Justify:** "distributed lock + TTL vs. optimistic concurrency; why; tradeoff." The
  *waiting-queue* part (F1) *can* get a Σ throughput/latency check under a burst workload.

### 21.5 Web crawler — *F1 async pipeline + dedup* ✅/🟡
- **Requirements:** crawl billions of pages; don't re-crawl; per-domain politeness.
- **Simulatable:** the async pipeline throughput (queue + workers decouple frontier from
  fetch — Σ throughput). **Structural:** `guardedPath(enqueue → dedup-index)` (every URL
  passes the dedup gate), `placement`/ordered-pipeline for frontier→fetch→process.
- **Discriminator (must fail):** a synchronous fetch path (no queue) collapses under the
  ingest rate (Σ); an enqueue path that skips the dedup index → `guardedPath` fails.

### 21.6 Notification / push — *F2 broadcast fan-out* 🟡 structural
- **Requirements:** one event → millions of devices via multiple channels.
- **Grade the structure:** `fanout` (a real pub-sub 1→N, not a work queue). Today this is
  structural — the broker doesn't *physically* broadcast in the sim until the
  `broadcastFanout` trait ships, so **don't** promise a Σ check for the fan-out itself.
- **Discriminator:** a single work-queue feeding N consumers (1-of-N delivery) → `fanout`
  hard-fails with "queue ≠ fan-out."

### 21.7 IoT / sensor ingestion (write-heavy) — *F2 write saturation + store-fit* 🟡/✅
- **Requirements:** 200k writes/s time-series; query recent windows.
- **Structural:** `storageFit(time-series)` — `time-series-db`/`columnar` accept,
  `relational-db` is an anti-pattern **hard-fail** (SQL at 200k w/s). **Simulatable:** the
  write p99/throughput once you make the naïve relational choice a small cpu-bound
  bottleneck (Σ). **Discriminator:** SQL store → `storageFit` hard-fails *independent of
  the sim*; kitchen-sink of stores → `budget`.

### 21.8 The "can't fully simulate it — here's what you grade instead" summary

| Question | Fully simulatable part (Σ) | Routed to topology + justification (T/J) |
|---|---|---|
| URL shortener | read p99 with cache | base62 uniqueness → durable-store guard + justify |
| Rate limiter | (little) | shared-counter `guardedPath` + algorithm justify |
| News feed | feed-read p99 | fan-out *shape* (`fanout`) |
| Ticketmaster | waiting-queue throughput | no-double-book → lock `guardedPath` + justify |
| Web crawler | pipeline throughput | dedup gate `guardedPath` + pipeline order |
| Payment/ledger | (little) | idempotency-key guard + immutable-ledger structure + justify |
| Notification | (deferred) | broadcast `fanout` (structural) |

## 22. Translation anti-patterns (what *not* to do)

- **Don't author a `simulation` check for a correctness property.** "p99 < X" cannot mean
  "exactly-once." The authoring validator flags this; §16 is the boundary.
- **Don't inject a read/write mix without type-routing.** The ratio is inert unless the
  topology routes on `request.type` (§8.3). Either add conditional edges / a cache that
  thins reads, or don't claim the mix matters.
- **Don't leave a scale number display-only.** Every number in the prompt must land in the
  workload or be *required in a justification* — no orphan requirements (the 99:1 bug,
  §12.3).
- **Don't run the headline scale.** 200k rps just times out; run a proportional ~2k slice
  (§12.4). Discrimination is scale-invariant in the offered/capacity ratio.
- **Don't ship without the gamed topology.** If you can't build a tempting wrong answer
  that fails, you haven't found what your question tests (§14.3). It's under-constrained.
- **Don't hand-type worker counts to make the bottleneck.** Derive it from a small
  cpu-bound instance (§7.6), or a student dodges it by resizing — and lock it
  (`maxInstances`, `canEditExecutionProfile: false`).

*External anchor for the canonical question set:*
[DesignGurus — Common System Design Interview Examples](https://www.designgurus.io/answers/detail/common-system-design-interview-examples),
[System Design Handbook — 40+ Examples](https://www.systemdesignhandbook.com/guides/system-design-interview-questions/),
[The Coding Gopher — Top 10 Most Common](https://thecodinggopher.substack.com/p/the-top-10-most-common-system-design).
*Internal source of truth:* `specs/question-families-and-bottlenecks.md` (the
family→bottleneck→status map), `specs/evaluation-authoring-reference-manual.md` (master
DSL), and the shipped bank in `system-design-simulator-questions/questions/*`.

---

# Part III — The Product Around It

## 23. Frontend architecture

- **App shell:** React + **Zustand** (`useStore`) for state, **ReactFlow** for the
  canvas, an **XState** machine for the run lifecycle.
- **The same engine runs in two places:** a headless Node runtime (tests + grading) and
  the browser, where a **Web Worker** (`useSimulation`) runs the *identical* engine so
  the UI stays responsive. Determinism means the worker and the CLI produce the same
  numbers.
- **Serialization:** `useTopologySerializer` turns the canvas graph into the engine's
  `Topology` — and it's the **single choke point** for important transforms (edge weights,
  connector neutralization, location→pathType derivation). Both "run the sim" and
  "compute cost" go through it, so a fix there fixes both surfaces at once.
- **Metric lenses:** the canvas colors nodes/edges by a chosen lens.
  - *Pre-run lenses* (before you run): **Instance · Concurrency · QueueCapacity ·
    Timeout · Cost** — showing derived facts (e.g. "eff. c = 3 × c5.xlarge = 24",
    "$0.085/hr").
  - *Runtime lenses* (after a run): **Traffic · Saturation · Latency · Errors ·
    Throughput.**
  - Under **connector** edge mode, every lens has a *node* projection and edges recede to
    a neutral wire — so we deliberately **don't** filter the palette by lens (that would
    strip the node story).
- **Chrome:** the properties panel (config, generated from trait `config.sections`), the
  simulation results tray (verdicts first: "api — queue 68.7%" / "api — Queue Full 100%",
  node condition cards "Overloaded / Down / Failing", status-timeline strip), the header
  (always-on **cost chip**, mode badge, **Settings modal**), and theming.

*Source: `src/renderer/src/{store,hooks,components}`,
`canvas-visualization-and-ux-simplification.md`, `settings-modal-feature-spec.md`,
`nodePresentation.ts`, ADRs on state management and node architecture.*

## 24. Newton integration & the authoring workflow

- **Two authoring shapes:** a standalone `question.json`, or **Newton Django rows**
  (SIMULATOR_CONFIG + STRUCTURAL_RULE / SEMANTIC_CRITERION / RUBRIC_CHECK) plus the host
  contract.
- **The bridge:** `newtonGamePlayground.ts` (`parseNewtonSeed`,
  `buildQuestionPackageFromRows`), host messaging, and `environmentProfile` passthrough
  (so the host forces ASSIGNMENT mode on a graded launch).
- **The loop:** author terse → **validate** (`parseQuestionPackage` +
  `validateAuthoredQuestion`) → **dual-topology grade** → ship rows.
- The embed runtime and origin security (which origins may post messages, grading-safe
  persistence of the evaluation envelope) are handled in the question-platform-hardening
  layer.

*Source: authoring manual §11, `newton-api-backend-integration.md`,
`authoring-a-simulator-game-question-runbook.md`, question-platform-hardening 06–07.*

---

# Part IV — The Skeptic's FAQ (your keynote defense)

Use these verbatim as your Q&A slides. Each is a real objection you *will* get.

> **"System design has no single right answer — you can't grade it."**
> We don't grade *the* answer; we grade whether the design **satisfies the requirements
> under load.** Constraint-satisfaction, not answer-matching — *any* topology that meets
> the SLO with the store shielded passes. Multiple valid solutions is a feature.

> **"You can't simulate a real distributed system in a browser."**
> We don't. We simulate the **queueing physics that decide whether it meets its SLO** —
> arrival, service, contention, saturation — on a tractable, proportionally-faithful
> slice. Well-founded DES/queueing theory: a calibrated instrument, not a cloud oracle.

> **"Correctness (exactly-once, no double-book) can't be simulated."**
> Correct — and we **don't fake it.** Hard boundary: performance → simulation;
> correctness → the required guard on the topology + a justification prompt. Never a
> correctness claim behind a latency number.

> **"Students will just game it / get lucky."**
> Multi-axis grading + Dual-Topology validation. Each question is authored so a known
> gamed shortcut fails on a specific axis; if it passes, the question is rejected.
> **Gaming is a bug we test for before ship.**

> **"Anyone can crank the servers up to pass."**
> Not anymore. Concurrency is derived from a priced, capped catalog — cranking "workers"
> does nothing, buying capacity costs money and can breach a budget/quota, and
> over-provisioning fails the **$** axis.

> **"Latency from a toy sim is meaningless."**
> It's **relative and physically consistent,** not an absolute prediction. The threshold
> is co-authored *with* the sim's numbers (reference passes with margin, gamed fails
> clearly), and every question is validated both ways.

> **"The real skill is the reasoning/tradeoffs — you can't grade that."**
> Deterministic justification grading does exactly that: name-a-real-node + cite-a-number
> + state-a-tradeoff, cross-checked against the graph. No LLM, fully reproducible.

> **"Floating-point drift will make your runs non-reproducible."**
> Integer-only PRNG + BigInt-microsecond clock + µs-quantized sampling. Floats touch a
> single non-accumulating leaf step and are erased by quantization. Reproducible given a
> seed — guaranteed within an engine, effectively across engines.

> **"Scaling up vs out, cost tradeoffs — you can't explore those in a toy."**
> That's precisely what the instance model exposes: scale up (bigger SKU) vs out (more
> instances), cpu- vs io-bound, on-demand/reserved/spot, RAM ceilings → OOM, per-region
> egress. The learner watches **cost and SLO move together** — the real capacity-planning
> loop.

---

# Part V — Known gaps & honest caveats (teach these openly)

Teaching these builds credibility — they're consistent with the honesty doctrine.

1. **The utilization-display bug (class of).** A node can, in some paths, *report* low
   utilization while queueing heavily, because a utilization denominator can use the wrong
   worker count vs. the scheduler's derived `c`. This is the same class as the
   point-sampled-scalar bug (§4.5) — worth a dedicated fix. Use it as the live example in
   Module 3.
2. **The dry-run-vs-graded-load trap (§12.5).** Green at 100 rps, dead at the graded 2k.
   Real physics, but a UX sharp edge — name it so students test at scale.
3. **No determinism spec.** The integer-PRNG + BigInt-clock + µs-quantization contract is
   correct in code and tested, but undocumented as a first-class invariant. → propose
   `simulation-determinism-and-numerics.md`.
4. **WFQ is FIFO.** The discipline union has 4 values; only 3 behaviors ship.
5. **11 of 20 event types are stubs.** Circuit breakers, partitions, latency spikes, etc.
   are reserved but not yet wired.
6. **Fault injection isn't wired into the app yet.** The engine records outage windows
   and the UI can shade them, but no app path defines faults, so the status timeline is
   empty in-app until `topology.faults` → scheduled node-failure/recovery events + a
   fault-authoring control are wired.
7. **Bank revamp is partial.** One question (cache-placement) is the fixed
   scaffold-pinned template; the remaining bank questions still need the same
   scaffold-pin migration so student palette builds (not just fixtures) discriminate.
8. **Request model is thin.** `Request = {type, sizeBytes, priority, metadata}` — no
   endpoint, no body, no response code. So application-level nuance is narrative/justify
   context, never a simulation check (which is exactly the performance/correctness
   boundary in §16).

**Highest-leverage doc follow-ups:** (1) a determinism/numerics spec; (2) a dedicated
sim-core spec for Modules 1–3; (3) split Part IV into a standalone skeptic-facing
one-pager for sales/keynote use.

---

# Appendix A — Glossary

- **DES** — Discrete-Event Simulation: model as time-ordered events; the clock jumps
  event→event.
- **G/G/c/K** — general-arrival, general-service, `c`-server, `K`-total-capacity queue.
  Every node is one.
- **c (effectiveC)** — parallel servers, *derived* = `vCPU × instanceCount ×
  workersPerVcpu`.
- **K (effectiveK)** — total system capacity (workers + queue), = `max(c, memCeiling)`.
- **ρ (utilization)** — busy fraction, the time-weighted integral `∫busy dt / (c·T)`.
- **Little's Law** — `L = λ·W`; used as a validation invariant.
- **workloadKind** — `cpu-bound` (1 worker/vCPU) or `io-bound` (32/vCPU).
- **perfFactor** — per-instance-family speed multiplier; `serviceTimeMultiplier =
  1/effectivePerf` (io-bound damped).
- **Terminal taxonomy** — the closed set of request end-states (success, timeout,
  queue_full, oom, connection_reset, node_failed, edge failures).
- **pathType** — edge locality (same-rack…internet) → latency profile; derived from
  Region/AZ/Subnet containment.
- **Trait** — a plug-in node behavior (hooks + auto-rendered config); the cache is the
  flagship.
- **Bernoulli thinning** — the cache model: hit with prob `hitRate` (served locally),
  else miss (continue downstream).
- **The five axes (T/S/Σ/J/$)** — Topology, Scale-fit semantics, Simulation,
  Justification, Budget.
- **Dual-Topology Rule** — a question is valid iff the reference passes and a known gamed
  shortcut fails on the intended axis.
- **Derive-and-lock** — concurrency is derived from a priced/capped catalog and shown
  read-only, so it can't be free-typed to dodge a bottleneck.
- **Environment profile** — AUTHOR/ASSIGNMENT/PRACTICE + capabilities; deployed default
  is PRACTICE + connector.
- **edgeModel** — `network` (real physics) vs `connector` (dumb wire, zero physics/cost).

# Appendix B — Source-of-truth file map

| Concern | Primary source |
|---|---|
| Event loop, clock, dispatch | `src/engine/engine.ts` |
| Event types & priorities | `src/engine/core/events.ts` |
| Scheduler | `src/engine/scheduler/min-heap.ts` |
| PRNG & distributions | `src/engine/stochastic/{random,distribution}.ts` |
| The queue node | `src/engine/nodes/GGcKNode.ts` |
| Instance catalog & derivation | `src/engine/catalog/{instanceCatalog,resourceDefaults}.ts`, `src/engine/nodes/resourceDerivation.ts` |
| Component specs / service time | `src/engine/catalog/componentSpecs.ts`, `paletteTemplates.ts` |
| Traits | `src/engine/traits/{types,capabilityModules,resolveTraits}.ts`, `traits/cache.ts` |
| Cost | `src/engine/analysis/cost.ts` |
| Metrics & aggregation | `src/engine/metrics.ts`, `metrics/windowedLatencyAggregator.ts`, `analysis/{phaseTimeline,output,verdict}.ts` |
| Grading — structural/semantic/rubric/justification | `src/engine/analysis/{structural,semanticCriteria,rubric,justification}.ts` |
| Authoring validation | `authoringValidator.ts`; `scripts/validate-question-dir.ts` |
| Environment profiles | `src/engine/analysis/environmentProfile.ts` |
| Frontend | `src/renderer/src/{store,hooks,components}`, `useTopologySerializer.ts`, `nodePresentation.ts` |
| Newton bridge | `newtonGamePlayground.ts` |
| **Master DSL doc** | `specs/evaluation-authoring-reference-manual.md` |

# Appendix C — Lecture delivery plan & tracks

**Format per lecture:** Objectives → Concepts → Source of truth → Live demo → Exercise.
~12 lectures at 75 min, or a 3-day workshop. Suggested module→lecture spine (matches Part
I): 0 Orientation · 1 DES core · 2 Determinism · 3 Lifecycle+taxonomy · 4 Queueing · 5
Nodes/service-time · 6 Instance model (**crown jewel — full lecture**) · 7 Execution
profiles · 8 Edges · 9 Traits · 10 Cost · 11 Metrics/honesty · 12 Workload/scale · 13
Grading DSL (**full lecture**) · 14 Anti-gaming/Dual-Topology · 15 Environments · 16
Correctness boundary · 17 Capstone author-a-question.

**Tracks:**
- **Engineers (full):** everything + capstone (~2.5 days).
- **Content authors (fast):** 0, 5–7, 9, 10, 12, 13–17 (~1 day).
- **Product/PM overview:** 0, 6–7, 11, 13–16, Part IV (~half day).

**Recurring threads — call out in every lecture:**
1. **Honesty** — every number derived + shows provenance (M4, M6, M11).
2. **You can't fake it** — concurrency & cost cost money (M6, M7, M10).
3. **Discrimination** — good passes, gamed fails (M14).
4. **Known gaps** — the utilization-display bug + the dry-run-vs-graded-load trap; teach
   them openly (Part V).

**Best live demos:**
- Reseed a run → byte-identical stats (determinism, M2).
- `cache-placement`: run with the `service→db` edge → p99 1003ms, fails; rewire
  `service→cache→db` → p99 ~17ms, passes (traits + grading, M9/M14).
- Scale `url-shortener` API Server c5.large ×1→×4 → p99 156ms→21ms while the cost chip
  climbs (instance model, M6).
- Flip a store io-bound→cpu-bound on a small instance → watch it become the bottleneck
  (execution profiles, M7).

---

*End of the masterclass. This document is self-contained; every claim traces to a
source file or spec listed in Appendix B, and the full DSL reference lives in
`specs/evaluation-authoring-reference-manual.md`.*

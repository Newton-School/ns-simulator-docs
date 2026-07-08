# Governing Principles

> **Purpose:** The decision rules for ns-simulator. Every feature, spec, PR, and UI change should be checkable against this list — if a change violates a principle, either the change is wrong or the principle needs a documented amendment here.
>
> **Date:** July 2026
>
> **Format:** Each principle is a name you can cite in review ("this violates *No number without a why*"), a rule, and the consequence of ignoring it.

---

## A. Truth of the model

### 1. Nodes must be true
A cache must absorb traffic. A load balancer must skip dead servers. L4 must refuse content routing. A queue must decouple its producer from its consumer. Until each node behaves like the thing it claims to be, every demo undermines trust — and a teaching tool that demonstrates falsehoods is worse than no tool.

### 2. Failure is injected, never ambient
Zero is the only acceptable default for error rates, packet loss, and jitter. Failure is something the user (or a scenario) deliberately adds — a chaos experiment, a WAF block rate, a dead node. Noise the student didn't cause teaches nothing and can't be explained when they ask "why 0.5%?"

### 3. Model honestly or don't model it
Every node documents what it simulates *and what it doesn't*. A declared simplification ("health detection is instantaneous unless you add a Health Check Manager") is fine; a silent fake (a CDN that forwards 100% of traffic) is not. When fidelity and honesty conflict, honesty wins — say "not modeled" rather than render a plausible-looking nothing.

### 4. Behaviour keys off type, never name
What a node *does* is resolved from its component type through one registry. Never from ID substrings, label matching, or icon choice. A student renaming "Load Balancer" to "traffic-thing" must change nothing about the simulation.

### 5. The queue stays; traits overlay
The G/G/c/K core is correct and shared — real infrastructure components *are* queues under the hood. Type-specific behaviour is added as composable traits on top of it, never by forking the engine or subclassing per node. If a proposed behaviour can't be expressed as a hook on the queue lifecycle, question the behaviour before questioning the architecture.

---

## B. Truth of the numbers

### 6. No number without a why
Every displayed value is exactly one of: **user-set**, **defaulted** (with visible provenance and a rationale), or **measured** (with an inspectable cause). If a number can't answer "where did you come from?" in two clicks, it doesn't ship.

### 7. A number needs its limit
Show values against their capacity: `6.2 / 8 workers ⚠`, not `6.2`. A bare number forces the user to judge; a ratio with a status glyph carries its own interpretation. Every metric the engine reports has a limit it knows — use it.

### 8. Determinism is the product
Same seed + same topology + same workload ⇒ byte-identical output, in the canvas, the CLI, and the grader. Reproducibility is what separates this from a hand-waved whiteboard — it's what makes comparison rigorous and grading defensible. Any feature that breaks determinism (wall-clock time, unseeded randomness, environment-dependent defaults) is rejected by default.

### 9. The event log is the ground truth
Every number, animation, and finding in the UI must be derivable from the canonical event stream. If it can't be replayed, it can't be displayed. This is also the test: any UI claim ("87% served from cache") must be checkable by filtering the log.

### 10. Conservation always balances
Generated = completed + rejected + timed out, at every node and end-to-end. If the accounting doesn't close, the run is wrong — not the check. Checks like this (Little's Law, warmup adequacy) exist to catch *our* bugs before they become a student's confusion.

### 11. Defaults are teaching artifacts
Every default value has one source of truth, one owner, and a one-line real-world rationale ("8ms — typical Postgres OLTP query"). A default the user can see and question teaches; a default buried in five uncoordinated code sites misleads. Zero-configuration must produce a *meaningful and explainable* run, not merely a running one.

---

## C. Structure of the presentation

### 12. Altitude, not amputation
Complexity stays available, but never all at once. Three levels: canvas shows status plus one number per node; selection shows full detail for one element; analysis holds the tables and verification math behind a disclosure. Removing information is a failure; showing it all simultaneously is a bigger one.

### 13. One question at a time
The canvas answers a single question per view — saturation *or* latency *or* errors *or* throughput — chosen by an explicit lens. A view that answers every question at once answers none.

### 14. Configuration is not a result
Node cards show state and measurements; configuration lives in the properties panel with its provenance. Never echo settings back styled as findings — the RUN CONTEXT block is one collapsed line, not the first screenful.

### 15. The verdict comes first
A completed run opens with findings in ranked prose — what's wrong, why, what to change — before any table. Severity-ordered, each naming its evidence. Tables, percentile grids, and λ/W/L are the appendix for those who want to verify, not the headline.

### 16. Show the flow, not just the totals
Causality is seen in motion: packet density that reflects measured throughput, a cache visibly starving its downstream edge, one request traced hop-by-hop with its latency accumulating. Summary statistics confirm what the animation already made obvious.

---

## D. Teaching

### 17. The constraint is the lesson
When the user tries something a real system forbids, block it *and explain the real-world reason*: "L4 operates at the transport layer and cannot inspect HTTP content." A well-worded rejection teaches more than a permissive canvas. Validation rules are curriculum, written once and enforced everywhere (canvas, validator, importer).

### 18. Compare, don't just run
The fundamental teaching move is A/B: same seed, same workload, one topology change — so every delta is attributable. With/without cache, before/after replica, L4 vs L7. Features should make comparison one click, and the delta the headline.

### 19. Two minutes to meaning
A first-time user reaches a meaningful, explainable completed run inside two minutes — via curated scenarios, not a blank canvas. Every minute of tool orientation is a minute of the lesson lost; the simulator's core value proposition over AWS demos *is* the missing setup time.

### 20. Every behaviour ships with its demonstration
A trait without a scenario that demonstrates it is unfinished. The definition of done for engine behaviour includes the curated topology, the "what to look at" note, and the A/B that makes the concept visible.

### 21. Errors are never console-only
Every failure the user can cause — a file that won't load, a migration that skips a node, a blocked run — produces a visible, specific, actionable message. A silent failure in a teaching tool converts instantly into "the tool is broken" or, worse, a false lesson.

---

## E. Engineering discipline

### 22. One truth per rule
Compatibility matrices, default values, trait mappings, validation rules: each lives in exactly one declarative table, consumed by the canvas, the validator, the engine, and the grader alike. The moment a rule exists in two places, they will diverge — the engine/validator default duplication already proved it.

### 23. Depth before breadth
One question type graded end-to-end before a framework of ten. One trait demonstrated in class before five half-built. One scenario polished before a library. Breadth built on an unproven slice multiplies rework; a complete vertical slice de-risks everything behind it.

### 24. Grading is only as credible as behaviour
Assessment features sequence strictly after node truthfulness and number provenance. A deterministic grade computed from a simulation that lies is a deterministic lie — and it carries a student's marks. Never let the assessment layer get ahead of the engine's honesty.

---

## F. Visualization governance

Visualization is not decoration on top of the simulator — it *is* the teaching instrument. A student who watches a run should be able to narrate what the system is doing before they open a single table. These rules govern everything drawn on the canvas during and after a run.

### 25. Every pixel of motion encodes a simulated quantity
Animation exists only to carry data: dot density carries throughput, dot speed carries edge latency, dot color carries outcome. If an animation would look identical when the underlying numbers change, it's decoration — cut it. The test for any proposed effect: *"what would a student learn by watching this that the numbers alone don't show?"* No answer, no animation.

### 26. One meaning per channel, everywhere
Each visual channel has exactly one system-wide meaning, and no meaning uses two channels:

| Channel | Meaning | Never used for |
|---|---|---|
| **Color (hue)** | Outcome / status: green = healthy/success, amber = degraded/warning, red = failed/rejected, blue = in-flight/info, violet = served-from-cache, gray = inactive/not-simulated | Node categories, decoration, brand |
| **Density** (dots per second on an edge) | Measured throughput | Latency, importance |
| **Speed** (dot traversal time) | Edge latency (time-scaled) | Throughput, urgency |
| **Fill level** (bars, slots) | Utilization against a limit | Anything without a limit |
| **Opacity / desaturation** | Not participating (warmup, inactive, filtered out by lens) | Severity |
| **Pulsing / glow** | At or past a limit *right now* | Selection, novelty |
| **Dashed stroke** | Async or severed (circuit open, unhealthy-excluded) path | Style variety |
| **Shape glyphs** (✓ ⚠ ✕ 🛇) | Status, redundant with color (accessibility) | — |

Node *category* identity stays where it already lives — icon and label — so hue remains free to mean state. A violation of this table is a blocking review comment, same as any principle here.

### 27. Motion runs on simulated time
All animation derives from event timestamps on the canonical stream (principle 9), rendered through one global time-scale control: pause, slow, accelerate. Dots depart when `request-forwarded` fires and arrive when `request-arrived` fires — so a 15ms edge visibly takes 3× longer than a 5ms edge at any playback speed. Wall-clock-driven or framerate-driven motion is forbidden: it animates the renderer, not the system. Corollary: because motion is event-driven, **any live view is also a replay view** — the same renderer serves during-run and after-run playback for free.

### 28. The workload pattern is a character in the story
Traffic patterns (constant, Poisson, bursty, spike, diurnal, sawtooth, replay) must be visible twice: as a **shape** — a sparkline of the full pattern in the scenario bar with a playhead marking "now" — and as **behaviour** — emission density at the source visibly following that shape. When the spike hits, the student sees the sparkline playhead climb *and* the dot storm leave the source *and* the queues downstream fill, in that order. Cause → propagation → effect is the whole lesson of load, and it only lands if all three are on screen together.

### 29. Routing strategies must be visually distinguishable
If two routing strategies produce indistinguishable animations, the visualization has failed even if the metrics differ. Each strategy has a signature a student can recognize without labels:

| Strategy | Visual signature |
|---|---|
| **Round-robin** | Dots peel off to targets in strict rotation — 1, 2, 3, 1, 2, 3 |
| **Weighted** | Streams of visibly proportional density (70/30 looks like 70/30) |
| **Least-connections** | Dots steer toward the target with the emptiest worker slots; watch traffic shift when one server slows |
| **Random / uniform** | No discernible order — and that *is* the signature, next to round-robin's rhythm |
| **Broadcast (Kafka, Pub/Sub)** | One dot arrives, N dots leave simultaneously — visible duplication |
| **Content-based (L7)** | Dots colored by request type diverge at the router: writes peel toward the primary, reads toward replicas |
| **Sticky / hash-keyed** | Same-key dots repeatedly land on the same target (brief target highlight on repeat hits) |
| **Health-aware** | A target flatlines and its stream visibly redistributes to survivors after the detection window |

Side-by-side, these signatures *are* the routing lecture.

### 30. State lives at the node: queues, workers, verdicts
A node's card visualizes its queue mechanics, not just summary numbers: **worker slots** (c discrete slots, filled = busy — utilization becomes countable), a **queue bar** that grows as arrivals outpace service (depth against capacity K), and **visible rejection** — dots that arrive at a full queue bounce with a red flash rather than vanish. Saturation must look like what it is: slots full, queue climbing, arrivals bouncing. This sequence — slots fill, then queue grows, then rejections start — is queueing theory taught by animation.

### 31. Trait behaviour must be watchable
Every behavioural trait ships with its visual signature in the same PR (extends principle 20): cache hits absorb the dot at the cache with a violet flash while misses pass through — the downstream edge visibly starves as hit rate rises; rate limiters shed red at the gateway in rhythm with token exhaustion; an open circuit breaker renders the path dashed-red and dots stop entering it; an async queue completes the producer's dot at enqueue while the consumer side drains at its own pace and backlog visibly accumulates; a cold start holds the first dot at a serverless node with a warm-up shimmer, then subsequent dots pass fast. A trait you can't watch working is (by principle 20) unfinished.

### 32. Warmup and windows are visually honest
Anything excluded from the reported numbers is visually excluded too: the warmup period renders desaturated (canvas and time-series alike, with a shaded warmup band and a marked measurement window on every chart), and pre-warmup dots are dimmed. Never let a student watch traffic that the summary then pretends didn't happen — that mismatch between what was seen and what is reported is exactly the kind of unexplainable gap principle 6 forbids.

### 33. Config-time previews, not just run-time views
Visualization starts before the run: picking a service-time distribution shows its density curve (exponential vs. normal vs. constant — the shape *is* the concept); editing workload parameters live-updates the pattern sparkline; setting weights on edges previews the split proportions. The properties panel teaches with pictures at the moment of choice, so the run confirms an expectation instead of revealing a mystery.

### 34. Degrade aggregation, never truth
Above the renderer's budget (edge count, dots per second, FPS floor), visualizations aggregate — dots become flowing streams with density-mapped thickness, per-request flashes become per-second counts — but the mapping to measured values survives aggregation. Two rules are absolute: the visualization layer must never influence simulation results or determinism (rendering reads the event stream; it never touches the engine), and it must never fabricate — a smooth "busy-looking" stream on an edge carrying 3 rps is a lie. Include a reduced-motion mode (glyphs and fill levels only, no dots) as both the accessibility path and the ultimate degradation level.

### 35. Every encoding is inspectable
Anything visualized answers a click: a dot → its request (and from there the D2 trace), a queue bar → depth over time, an edge stream → that edge's measured rates, a status glyph → the threshold that set it. A persistent, lens-aware legend explains the active encodings in one line ("dots = requests · speed = edge latency · violet = cache hit"). No student should have to guess what a visual means — an unexplained encoding is an unexplained number (principle 6) wearing paint.

---

### Visualization catalog — what must be visualizable, and what each view teaches

The buildable inventory implied by the rules above. **Live** = during run; **Post** = after completion; **Config** = before running. (Task references: D1/D2 per the execution roadmap.)

| # | Visualization | When | Teaches | Governed by |
|---|---|---|---|---|
| V1 | Request dots on edges (density/speed/color mapped) | Live + replay | Flow, latency differences, where traffic actually goes | 25–27 |
| V2 | Workload pattern sparkline + playhead in scenario bar | Config + Live | Traffic patterns; cause of downstream load changes | 28 |
| V3 | Routing-strategy signatures | Live + replay | LB strategies, broadcast vs. point-to-point, L7 content routing | 29 |
| V4 | Worker slots + queue bar + rejection bounce per node | Live + replay | Utilization, queueing, capacity, rejection — G/G/c/K itself | 30 |
| V5 | Trait signatures (cache absorb, rate-limit shed, breaker open, async ack, cold start) | Live + replay | Each distributed-systems concept the trait models | 31 |
| V6 | Node health transitions + traffic redistribution | Live + replay | Failure, detection latency, health-aware routing | 29, 31 |
| V7 | Follow-one-request trace with latency accumulator | Post (D2) | Where end-to-end time goes; request lifecycle | 27, 35 |
| V8 | Per-hop latency waterfall (stacked bar) | Post | Latency decomposition; which hop dominates | 6, 35 |
| V9 | Time-series: utilization / queue depth / throughput per node, warmup-shaded, pattern-overlaid | Post | Dynamics over time; correlation of load pattern with saturation | 28, 32 |
| V10 | Metric-lens canvas heatmap | Post + Live | System-level hotspots one question at a time | 12, 13 |
| V11 | A/B run comparison (side-by-side + per-node deltas) | Post | Effect of one architectural change, attributably | 18 |
| V12 | Latency histogram with percentile markers | Post | Distributions vs. averages; why p99 ≠ p50 | 6, 33 |
| V13 | Distribution-shape preview in properties panel | Config | Service-time distributions; variance as a concept | 33 |
| V14 | Backpressure / cascade view (saturation propagating upstream) | Live + replay | Cascading failure, bottleneck upstream effects | 25, 30 |
| V15 | Conservation waterfall (generated → completed/cached/rejected/timed-out) | Post | Request accounting; where requests end up | 10 |

Sequencing note: V1–V4 are the foundation (V1 exists in early form; V2–V4 make it meaningful); V5–V6 land with each trait (workstream A); V7–V12 are the analysis layer (workstream B/C/E); V13–V15 fill in as their engine features mature.

---

## Using this list

- **In specs:** cite principles by name in the rationale section.
- **In review:** a violation is a blocking comment; either the PR changes or this document does (with the amendment recorded).
- **In prioritization:** P0 is whatever currently violates principles 1–11 in shipped behaviour — those are trust debts, not features.

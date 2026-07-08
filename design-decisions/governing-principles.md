# Governing Principles

> **Purpose:** The decision rules for ns-simulator. Every feature, spec, PR, and UI change should be checkable against this list — if a change violates a principle, either the change is wrong or the principle needs a documented amendment here.
>
> **Date:** July 2026 (textbook revision — each principle expanded into a teaching entry)
>
> **Format:** Each principle has a name you can cite in review ("this violates *No number without a why*"), a **rule** stated in one or two sentences, a teaching explanation of why it exists and what breaks without it, and an **Applies in** line mapping it to roadmap tasks.
>
> **Companion:** `planning/roadmap-reference.html` renders this document with a diagram per principle, nine live simulation demos, and an algorithms appendix (DES loop, trait pseudocode, routing selection, determinism, verification math). Anchors follow the pattern `roadmap-reference.html#p14`.

---

## A. Truth of the model
*What the engine is allowed to pretend.*

### 1. Nodes must be true

**Rule:** A cache must absorb traffic. A load balancer must skip dead servers. L4 must refuse content routing. A queue must decouple its producer from its consumer.

A simulator's only asset is the belief that what it shows corresponds to reality. Every palette node makes an implicit promise — "I behave like the thing I'm named after" — and today every non-source node breaks it, because all of them run the same generic queue. The failure isn't cosmetic: an instructor who demonstrates "add a cache to protect the database" while the database's arrival count doesn't move has taught a falsehood, on the record, to a room. The test for truthfulness is behavioural, not visual: place the node, send traffic, and check that the downstream numbers change the way the real component would change them. Until a node passes that test it should not claim the name.

**Applies in:** A1–A8, E1, F2. Violated today by: CDN, Redis, L4/L7, Kafka, SQS, and most of the palette. Verified live (July 2026): Redis received 2,656 requests, the downstream DB received 5,312 — the cache absorbed exactly zero.

### 2. Failure is injected, never ambient

**Rule:** Zero is the only acceptable default for error rates, packet loss, and jitter. Failure is something the user deliberately adds.

Every lesson in the simulator has the logical form **"you did X, therefore Y happened."** That inference only holds if a fresh, untouched topology runs perfectly — otherwise the student's Y is contaminated by errors they never caused. The live run proved the violation: an unmodified 6-node topology reported 0.5% errors from seeded defaults nobody chose, and no screen in the product could answer "why?". Ambient noise also destroys alerting: if a healthy system shows red, red stops meaning anything (the boy who cried wolf, as a UI). Failure remains central to the curriculum — but as a chaos experiment, a WAF block rate, a killed node: authored, visible, attributable.

**Applies in:** B3, C4, D1, F2.

### 3. Model honestly or don't model it

**Rule:** Every node documents what it simulates *and what it doesn't*. A declared simplification is fine; a silent fake is not.

No simulator models everything, and pretending otherwise is the fastest way to lose an expert user. The distinction that matters is between a **declared simplification** — "health detection is instantaneous unless you add a Health Check Manager" — and a **silent fake** — a CDN that renders convincingly but forwards 100% of its traffic. The first is a teaching choice a student can reason about; the second is a lie they'll build a mental model on. Operationally this means every component's info card carries a "what's simulated / what's not" section, kept current by a checklist item on every trait PR. When fidelity and honesty conflict, honesty wins: say "not modeled" rather than render a plausible-looking nothing.

**Applies in:** E2, A5. Enforced by: per-trait-PR info-card checklist.

### 4. Behaviour keys off type, never name

**Rule:** What a node does is resolved from its component type through one registry — never from ID substrings, labels, or icons.

Today `routing.ts` decides round-robin by checking whether the node's **ID contains "lb"** — so a student renaming "Load Balancer" to "traffic-thing" silently changes how the simulation routes, and a plain service named "lb-ish" starts round-robining. This is the worst category of bug for teaching: behaviour that changes for reasons invisible in the model. The rule generalizes: identity lives in exactly one field (the component/template type), and everything downstream — trait resolution, routing, validation, grading — derives from it. Names, labels, and icons belong to the human; the engine must be blind to them. The regression test writes itself: rename every node in a topology, re-run with the same seed, and require a byte-identical result.

**Applies in:** A8, A1. Test: rename-everything ⇒ identical output.

### 5. The queue stays; traits overlay

**Rule:** Type-specific behaviour is composed as traits hooked onto the G/G/c/K lifecycle — never engine forks, never per-node subclasses.

The G/G/c/K queue is not the problem — it's the correct common denominator, because real infrastructure components **are** queues under the hood: a database is workers over a connection pool; an LB is a very fast queue with a routing decision. What differs between components is a small set of decisions at three moments: on arrival (admit? serve from cache? shed?), before routing (forward? complete here? reroute?), and during target selection (which candidates are eligible?). Traits are those three hooks, made composable: a Reverse Proxy is Cache + HealthAwareRouting; an API Gateway is RateLimiter + ContentRouting + HealthAwareRouting. Fifty subclasses would freeze those combinations; a fork would duplicate the physics. If a proposed behaviour can't be expressed as a hook, question the behaviour before questioning the architecture.

**Applies in:** A1. Invariant: `GGcKNode` is untouched by the entire roadmap.

---

## B. Truth of the numbers
*What a number must be able to answer.*

### 6. No number without a why

**Rule:** Every displayed value is exactly one of: user-set, defaulted (with visible provenance), or measured (with an inspectable cause).

This is the family's root principle and the roadmap's central test. A number on screen is a claim, and every claim owes the student an answer to "where did you come from?" — within two clicks. The taxonomy is exhaustive on purpose: **user-set** values answer with the user's own action; **defaulted** values answer with a badge naming their source and rationale; **measured** values answer with a decomposition down to the events that produced them. Anything that fits none of the three — the observed 0.5% error rate, the "jitter/0.3% fail" edge labels — is by definition unexplainable, and unexplainable numbers are what users experience as clutter, then as distrust. The shipping rule is literal: if a metric can't answer, it doesn't render.

**Applies in:** B1, B2, B3, B4, C2.

### 7. A number needs its limit

**Rule:** Show values against their capacity: `6.2 / 8 workers ⚠`, never a bare `6.2`.

A bare number outsources the hardest part of reading it — judgment — to the viewer. "Queue depth 12": is that fine? Catastrophic? It depends entirely on the capacity, which the engine knows and the student doesn't. Pairing every value with its limit and a status glyph turns each metric into a self-interpreting statement: the ratio says how close, the glyph says whether to worry. This single pattern is why a Pinpole node card reads instantly ("concurrency 847 / 1,000 ⚠") while the current card's Workers/Capacity/Timeout grid reads as noise — same information density, opposite interpretability. Every metric the simulator reports has a natural limit: workers, queue capacity, token buckets, provisioned throughput, SLO thresholds. Use them.

**Applies in:** C2, C3, V4. Source pattern: Pinpole value/limit cards.

### 8. Determinism is the product

**Rule:** Same seed + same topology + same workload ⇒ byte-identical output — in the canvas, the CLI, and the grader.

Determinism is what separates this simulator from a hand-waved whiteboard and from real infrastructure alike: the whiteboard can't compute, and AWS never gives you the counterfactual. With seeded randomness, "we changed one thing and p99 dropped 40ms" is a **provable attribution**, not an anecdote — which is what makes A/B comparison rigorous and grading defensible. The discipline is mostly about what to forbid: wall-clock reads, unseeded `Math.random()`, environment-dependent defaults, iteration over unordered maps. One subtle requirement: give each node its own RNG substream (derived from the master seed + node ID + purpose), so adding a node doesn't shift every other node's draws — otherwise "add a cache" changes the DB's sampled service times and the comparison lies. Certify with golden-file tests, not code review.

**Applies in:** B1, E3, F1. See: seeded-RNG substream algorithm in the companion reference.

### 9. The event log is the ground truth

**Rule:** Every number, animation, and finding must be derivable from the canonical event stream. If it can't be replayed, it can't be displayed.

The engine already emits a canonical, timestamped record of everything that happens — every generation, hop, queue entry, completion, rejection. Making that stream the **single source for all rendering** buys three things at once. Consistency: the canvas, the tables, and the trace can never disagree, because they're three projections of one record. Replayability: any live view is automatically an after-the-fact view, since the renderer only ever consumed timestamps. And testability: any UI claim ("87% served from cache") is checkable by filtering the log — which means visualizations can be verified headlessly. The inverse rule matters equally: state that exists only in the renderer is state that can silently diverge from the simulation. Don't create any.

**Applies in:** A1 (trait decisions become canonical events), B4, D1, D2.

### 10. Conservation always balances

**Rule:** Generated = completed + rejected + timed-out (+ in-flight at cutoff), at every node and end-to-end. If it doesn't close, the run is wrong — not the check.

Requests are not created or destroyed inside the system; they only change category. That accounting identity is the simulator's equivalent of double-entry bookkeeping, and it exists to catch **our** bugs before they become a student's confusion — a request dropped by a routing edge case shows up as an imbalance long before anyone notices a slightly-wrong percentile. The principle carries a posture, too: when the check fails, the temptation is to loosen the tolerance; the rule forbids it. New behaviours must declare their accounting up front — a cache hit is a completion (tagged `servedFromCache`), an acked queue message completes the producer's request while spawning a message lifecycle — so the waterfall stays closed as traits land.

**Applies in:** A3, A6, C4, V15. Companion check: Little's Law (L = λW within tolerance).

### 11. Defaults are teaching artifacts

**Rule:** Every default has one source of truth, one owner, and a one-line real-world rationale — "8ms: typical Postgres OLTP query."

Defaults are the simulator's most-read documentation, because zero-configuration is the primary path: drop a node, connect, run. Every parameter the user didn't set is a statement the product made on their behalf — and today those statements are made at five uncoordinated code sites, with no rationale, sometimes contradicting each other (catalog says exponential, engine falls back to constant). The fix has two halves. Structurally: one resolver, one precedence order (user → environment → catalog → engine), one trace recording where each value came from. Pedagogically: every catalog default carries its real-world justification, surfaced as a badge in the panel and reused in the info card. A default a student can see and question teaches; a buried one misleads.

**Applies in:** B1, B2, E2. See: default-resolution algorithm in the companion reference.

---

## C. Structure of the presentation
*Where information lives.*

### 12. Altitude, not amputation

**Rule:** Three levels: canvas (status + one number per node) → selection (full detail for one element) → analysis (findings, tables, verification math behind a disclosure).

The tempting response to clutter is deletion, and it's wrong — the requirement is real: the tool must show complexity. The correct response is **assignment**: every fact gets exactly one altitude where it lives, chosen by the question it answers. "Is the system OK?" is a canvas question — glance-level, one number per node. "What exactly is happening at this node?" is a selection question — full metrics, one element at a time. "What should I change, and can I verify the math?" is an analysis question — the tray. Clutter is simply information rendered at the wrong altitude: config on canvas cards, λ/W/L as a default column. The assignment also settles every future debate — "can the card also show X?" is answered by asking which question X serves, not by negotiation.

**Applies in:** C1, C2, C3, C4.

### 13. One question at a time

**Rule:** The canvas answers a single lens per view — Saturation, Latency, Errors, or Throughput — chosen explicitly by the user.

A view that answers every question at once answers none: four metric families competing on every node and edge is exactly the observed clutter. The lens inverts the relationship — instead of the canvas broadcasting everything, the **user declares which question they're asking**, and every node card and edge label switches to that family. This is "solve one numbers problem at a time" implemented as a mode rather than as data loss: the other three families are one click away, never gone. The lens also becomes teaching vocabulary: an instructor stages each concept's reveal by naming its lens ("switch to Throughput — now watch the cache→DB edge"), turning vague observation into directed observation. Default to Saturation; it's the question most runs are implicitly asking.

**Applies in:** C1, C6, V10.

### 14. Configuration is not a result

**Rule:** Cards and trays show state and measurements; configuration lives in the properties panel, with provenance. Never echo settings styled as findings.

Two observed violations define this principle. Pre-run node cards display Workers/Capacity/Timeout — the user's own inputs, restyled as if the simulator had discovered them. And the results tray opens with RUN CONTEXT: six cells repeating the source, pattern, RPS, duration, warmup, and seed the user just typed, occupying the first screenful where the verdict belongs. Echoing inputs back has a real cost beyond wasted space: it trains users that the product's displays carry no new information, so they stop reading them. The separation is strict — the panel is where you *choose* (with default badges showing what you didn't), cards and trays are where you *learn what happened*. Run context collapses to one expandable line; it's reference material, not a result.

**Applies in:** C2, C4, B2.

### 15. The verdict comes first

**Rule:** A completed run opens with severity-ranked findings in prose — node, problem, consequence, suggested change — before any table.

A student finishing a run has one question: **"so… what's wrong?"** Today the answer is distributed across a summary strip, a checklist, and a 12-column table, and assembling it is left as an exercise. The verdict-first rule makes synthesis the product's job: the tray opens with ranked findings ("Primary DB is the first bottleneck: 10% utilization at 100 rps → saturation ≈ 1,000 rps. Add a read replica, or give the cache a real hit rate."), each naming its evidence and linking to the decomposition that proves it. Everything else — percentile grids, per-node tables, Little's Law — remains available as the appendix, behind a "Verification" disclosure, for readers who want to check the work. The same machinery, run headlessly, becomes the grader's feedback voice: build the findings generator once, serve both.

**Applies in:** C4, F2. Source pattern: Pinpole ranked recommendations, deepened.

### 16. Show the flow, not just the totals

**Rule:** Causality is seen in motion — packet density, a starving edge, one request traced hop-by-hop. Statistics confirm what the animation made obvious.

Summary statistics are answers; flow is **explanation**. A table can report that the DB received 10% of traffic after adding a cache, but only motion shows the mechanism: dots absorbed violet at the cache, the downstream edge visibly thinning. Distributed-systems concepts are inherently dynamic — backpressure, bursts, detection latency, decoupling — and each has a motion signature that lands in seconds where a paragraph takes minutes. The principle also assigns the two media their proper jobs: animation carries causality and sequence ("the spike hit, *then* the queue grew, *then* rejections started"), while numbers carry precision and proof. A classroom projection is the acid test: at the back of a lecture hall nobody reads a p95 column, but everyone can see one edge starving and another flooding.

**Applies in:** D1, D2, V1–V7.

---

## D. Teaching
*How lessons happen.*

### 17. The constraint is the lesson

**Rule:** When the user tries something a real system forbids, block it and explain the real-world reason. Validation rules are curriculum.

Most tools treat validation as damage control; here it's a teaching channel — often the best one, because it fires at the exact moment of maximum curiosity: the student just *tried* the thing. "L4 operates at the transport layer and cannot inspect HTTP content — use an L7 Load Balancer for content-based routing" delivers the L4/L7 distinction more memorably than any info card, precisely because it interrupted an intention. This requires rejection messages to be written as explanations, not errors: name the real-world constraint, not the schema rule. And because rules are curriculum, they get curriculum's quality bar — one declarative table (P22), enforced identically at the canvas, in the validator, and by the grader, so the student is warned while designing by exactly the rule that will judge them.

**Applies in:** C5, A4, A6-c, F2.

### 18. Compare, don't just run

**Rule:** The fundamental teaching move is A/B: same seed, same workload, one topology change — so every delta is attributable to that change alone.

A single run produces numbers; a comparison produces **meaning**. "p99 is 97ms" teaches little; "p99 dropped from 97ms to 31ms when you added the cache — and nothing else changed, provably" teaches architecture. The proof is the point: because the engine is deterministic (P8), holding the seed and workload fixed makes the topology change the *only* free variable, which is an experimental rigor real infrastructure can never offer — AWS has no counterfactual button. Nearly every lesson in the curriculum is natively an A/B: with/without cache, health checks on/off, L4 vs L7, one replica vs three, server vs serverless under burst. The product implication: comparison is one click, the per-node delta is the headline ("DB arrivals: 5,312 → 531, −90%"), and the UI says out loud why the delta is trustworthy.

**Applies in:** E3, A2, A3, F3.

### 19. Two minutes to meaning

**Rule:** A first-time user reaches a meaningful, explainable completed run inside two minutes — via curated scenarios, not a blank canvas.

The simulator's core pitch over cloud demos is eliminated setup: no IAM, no billing, no provisioning wait. That promise is only as good as its weakest minute, and today the weakest minute is the blank canvas — a first-timer faces 67 palette entries and no path. "Two minutes to meaning" is a measurable budget: open → pick a scenario → run → read a finding you can explain. Scenarios are what make it achievable (a curated topology, a "what to look at" note, a designed teaching moment); the walkthrough makes it repeatable; and the budget disciplines everything else — any feature that adds friction to the first two minutes needs a reason. For the adopting instructor this is the whole ballgame: the difference between "I can use this Monday" and "I'll need a training session first."

**Applies in:** E1, E4. Metric: time-to-first-explainable-run.

### 20. Every behaviour ships with its demonstration

**Rule:** A trait's definition of done includes the curated scenario, the "what to look at" note, and the visual signature that make it teachable.

An engine behaviour with no demonstration is, for this product, indistinguishable from an unbuilt one: the cache trait could work perfectly and still teach nothing if no scenario stages it, no lens frames it, and no animation shows the absorption. This principle redefines "done" for the whole A workstream — each trait PR carries (or is immediately followed by) its scenario file, its finding template, its visual signature, and its info-card honesty update (P3). The discipline pays both ways: scenarios double as end-to-end regression tests (the CI loads and runs every one), and writing the demonstration first is the cheapest design review a behaviour can get — if you can't stage a teachable moment for it, that's evidence the config knobs are wrong before a line of engine code exists.

**Applies in:** A2–A7, E1, V5.

### 21. Errors are never console-only

**Rule:** Every failure the user can cause produces a visible, specific, actionable message. Silence is the one response that's always wrong.

The live review found the canonical violation: a topology file that fails migration throws `Unable to migrate legacy node 'api-gw'` — into the console. On screen: nothing. The canvas stays empty, and the user is left to choose between two conclusions, both fatal: "the tool is broken" or, worse for a teaching product, a false lesson ("I guess my file was empty"). In a classroom the stakes compound — an instructor five minutes before a lecture doesn't debug, they abandon. The rule requires every user-triggerable failure path to end in UI: a toast with counts and a details link for partial successes ("Loaded 12 nodes · 2 migrated with warnings"), a blocking explanation for hard failures. Corollary: keep the console quiet by policy — the observed wall of React Flow warnings is exactly the noise floor under which the next real error hides.

**Applies in:** G1, G2, G3, C5.

---

## E. Engineering discipline
*How the codebase stays coherent.*

### 22. One truth per rule

**Rule:** Compatibility matrices, default values, trait mappings, findings logic: each lives in exactly one declarative table, consumed by canvas, validator, engine, and grader alike.

The codebase has already run this experiment and published the result: the engine and the validator each apply node defaults independently, with identical values — for now. The moment one is updated without the other, the validator starts approving topologies the engine runs differently, and nobody notices until a student does. The rule generalizes the fix: any knowledge consumed in more than one place is expressed as **data**, once, and imported everywhere — never re-implemented. The payoff compounds across the roadmap: the connection rule that warns a student at wiring time is the same table row that grades their submission; the rationale string in a default badge is the same text in the info card; the findings generator that opens the tray is the grader's feedback voice. Divergence stops being a bug class because the second copy never exists.

**Applies in:** B1, C5, C4/F2, E2.

### 23. Depth before breadth

**Rule:** One question type graded end-to-end before a framework of ten. One trait demonstrated in class before five half-built. One scenario polished before a library.

Breadth built on an unproven slice multiplies rework: if the first complete vertical — say, one "fix the bottleneck" question authored, solved, and graded by real users — reveals that the rubric model is wrong, that discovery costs one question; discovered after a ten-type framework, it costs ten. The vertical slice is also the only honest validator of demand: a framework describes what instructors *might* author; a shipped question shows what they *do*. The rule has a sharp operational reading in this roadmap — F2 ships one question type completely before F3 generalizes, each A6/A7 trait lands with its scenario before the next trait starts, and the scenario library opens with four polished entries rather than twenty stubs. Frameworks are extracted from working examples, never speculated ahead of them.

**Applies in:** F2→F3, A6, E1.

### 24. Grading is only as credible as behaviour

**Rule:** Assessment sequences strictly after node truthfulness and number provenance. A deterministic grade computed from a simulation that lies is a deterministic lie.

Determinism is often mistaken for correctness; this principle keeps them separate. A grader can be perfectly reproducible — same submission, same score, every time — while scoring against physics that are wrong: a cache that absorbs nothing would fail every student who correctly added one. Reproducible injustice is worse than noisy grading, because it's *systematic* and carries an aura of objectivity. Hence the roadmap's ordering is not a preference but a dependency: A makes the physics true, B makes results reproducible and explainable, C/D make evidence visible to the student — and only then does F attach marks. The stakes justify the patience: everywhere else an unfixed lie is a UX problem; in assessment it becomes a number on someone's transcript, defended by an appeal process.

**Applies in:** F1, F2, F3. This is why Phase 5 is last.

---

## F. Visualization governance
*What may move on screen.*

Visualization is not decoration on top of the simulator — it *is* the teaching instrument. A student who watches a run should be able to narrate what the system is doing before they open a single table. These rules govern everything drawn on the canvas during and after a run.

### 25. Every pixel of motion encodes a simulated quantity

**Rule:** Animation exists only to carry data. The test: what would a student learn by watching this that the numbers alone don't show? No answer, no animation.

Animation is the scarcest resource on the canvas — it seizes attention involuntarily, so whatever moves is whatever the student studies. Spending that attention on decoration isn't neutral; it actively teaches wrong things ("traffic looks constant" when it isn't). The falsifiability test makes the rule mechanical: pick any proposed effect and ask whether it would **look different if the underlying numbers changed**. Dots whose density tracks measured throughput pass; a looping "busy" shimmer fails. Passing the test converts the whole animation layer into an instrument — which is why, once packets obey it (D1), every trait becomes watchable with no additional visualization code: the cache starves its downstream edge because the *numbers* starve it, and the pixels merely obey.

**Applies in:** D1, V1. Every animation PR cites its encoded quantity.

### 26. One meaning per channel, everywhere

**Rule:** Each visual channel has exactly one system-wide meaning, and no meaning uses two channels.

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

A visual channel is a word in a language, and a word with two meanings produces sentences nobody can parse. If green sometimes means "healthy" and sometimes means "database category," the student must stop and disambiguate every time — exactly the cognitive tax visualization exists to remove. Two corollaries carry most of the enforcement weight: node *category* identity stays in icon and label — never hue — so color remains free to mean state; and every color meaning is doubled by a glyph, which is simultaneously the accessibility path and a check that the meaning survives without color. A violation of this table is a blocking review comment, identical in weight to any principle here.

**Applies in:** D1, C2, every demo and diagram in the companion reference.

### 27. Motion runs on simulated time

**Rule:** All animation derives from event timestamps, rendered through one global time-scale control. Wall-clock or framerate-driven motion animates the renderer, not the system.

The simulation has its own clock — microsecond-resolution, deterministic, recorded on every event. Animation must be a **projection of that clock**, not a parallel one: a dot departs when `request-forwarded` fired and arrives when `request-arrived` fired, so a 15ms edge visibly takes three times longer than a 5ms edge at any playback speed. Break this and the picture lies about the one thing students most need to internalize — where time goes. Honoring it yields two free features: a single pause/slow/accelerate control governs everything at once (time-scaling one clock), and the distinction between "live view" and "replay" disappears entirely — the renderer only ever consumed timestamps, so re-feeding recorded ones is the same code path. That's why D2's trace mode needs zero engine work.

**Applies in:** D1, D2. Forbidden: `Date.now()`-driven motion.

### 28. The workload pattern is a character in the story

**Rule:** Patterns are visible twice: as a shape (sparkline + "now" playhead in the scenario bar) and as behaviour (emission density following that shape). Cause, propagation, and effect share the screen.

Load is the protagonist of most system-design lessons, and today it's invisible — a dropdown label ("bursty") with no body. The lesson of a traffic spike is a causal chain with three links: the pattern climbs (cause), the dot storm leaves the source (propagation), the downstream queues fill and drain late (effect). If any link is off-screen, students see correlation at best; with all three visible, they watch causation happen in order. The sparkline-plus-playhead does double duty at config time (P33): choosing "diurnal" shows the day-curve before a single request runs, so the run confirms an expectation instead of springing a surprise. The companion reference's patterns demo shows the arc for all six patterns — including the spike whose queue takes far longer to drain than the spike lasted, a capacity-planning lesson no static chart delivers.

**Applies in:** V2, D1, E1 scenario notes.

### 29. Routing strategies must be visually distinguishable

**Rule:** Each strategy has a signature a student recognizes without labels. If two strategies produce indistinguishable animations, the visualization has failed even if the metrics differ.

| Strategy | Visual signature |
|---|---|
| **Round-robin** | Dots peel off to targets in strict rotation — 1, 2, 3, 1, 2, 3 |
| **Random / uniform** | No discernible order — and that *is* the signature, next to round-robin's rhythm |
| **Weighted** | Streams of visibly proportional density (70/30 looks like 70/30) |
| **Least-connections** | Dots steer toward the target with the emptiest in-flight bar; traffic shifts when one server slows |
| **Broadcast (Kafka, Pub/Sub)** | One dot arrives, N dots leave simultaneously — visible duplication |
| **Content-based (L7)** | Dots colored by request type diverge at the router: writes peel toward the primary, reads toward replicas |
| **Sticky / hash-keyed** | Same-key dots repeatedly land on the same target |
| **Health-aware** | A target flatlines and its stream visibly redistributes to survivors after the detection window |

Routing strategies are *defined* by their decision patterns, so the pattern is the concept — hiding it behind identical animations discards the entire lesson. Side by side, these signatures **are** the routing lecture — and the failure mode they prevent is today's reality, where round-robin and broadcast render identically and a student learns that "routing strategy" is a cosmetic dropdown. All eight run live in the companion reference's routing demo.

**Applies in:** V3, A2, A4.

### 30. State lives at the node: queues, workers, verdicts

**Rule:** A node's card visualizes its queue mechanics: c worker slots (filled = busy), a queue bar against capacity K, and rejections that visibly bounce. Saturation must look like what it is.

G/G/c/K is abstract until you can count it. Rendering the c workers as discrete slots makes utilization **countable** — "3 of 4 busy" needs no legend — and the queue bar gives depth a limit to be judged against (P7). What the composition buys is the sequence: as load rises, students watch slots fill *first*, the queue grow *second*, and rejections bounce *third* — which is queueing theory's core narrative arc, taught by animation instead of by formula. The bounce matters as much as the bars: a rejected request that silently vanishes teaches nothing, while a red bounce at a full queue shows both the fact and the location of the loss. The full state vocabulary is five states — healthy, degraded, critical, failed, inactive — with inactive reserved for genuinely unreached nodes, never the source (bug G2).

**Applies in:** V4, C2, G2. State machine: see the companion reference's algorithms section.

### 31. Trait behaviour must be watchable

**Rule:** Every behavioural trait ships with its visual signature in the same PR. A trait you can't watch working is unfinished.

This is P20's demonstration rule specialized to pixels, with a catalog attached: cache hits absorb the dot violet at the cache while the downstream edge starves; rate limiters shed red in rhythm with token exhaustion; an open circuit breaker renders its path dashed-red and refuses dots at the boundary; an async queue flashes the producer's ✓ at enqueue while backlog accumulates at the consumer's pace; a cold start holds the first dot with an amber warm-up ring while the rest of the burst zips through warm and green. Most signatures cost almost nothing once P25/P27 hold — the cache signature is just truthful packets reacting to truthful physics. The discipline is the same-PR requirement: it forces the question "what will the student *see*?" into the trait's design review, where it improves config knobs before code exists.

**Applies in:** A2–A7, V5, V6. All five signatures run live in the companion reference's trait gallery.

### 32. Warmup and windows are visually honest

**Rule:** Anything excluded from the reported numbers is visually excluded too: warmup renders desaturated, and every chart marks its measurement window.

The simulator correctly discards its warmup period — queueing systems need time to reach steady state, and measuring the ramp would bias every statistic. But statistical correctness creates a visual trap: the student *watches* two thousand requests flow during warmup, then reads a summary that pretends they never happened. That gap between what was seen and what is reported is precisely the kind of unexplainable discrepancy P6 forbids — except here the "number" is the student's own memory. The fix is to make exclusion visible: warmup traffic renders dimmed on the canvas, time-series charts shade the warmup band and bracket the measurement window, and the summary states its window explicitly ("t=5s → t=60s, 5,328 samples" — which, to its credit, the current tray already does). One clock, one story, visibly partitioned.

**Applies in:** V9, D1. Related: warmup-adequacy check in the Bottlenecks tab.

### 33. Config-time previews, not just run-time views

**Rule:** Picking a distribution shows its curve; editing a workload live-updates its sparkline; setting weights previews the split. The panel teaches with pictures at the moment of choice.

Visualization that starts at "Run" arrives too late to shape decisions. The properties panel is where mental models are actually formed — and most of its concepts are shapes, not numbers. "Exponential vs. normal service time" is nearly meaningless as a dropdown, but as two curves (one long-tailed, one symmetric) it explains itself, and it quietly teaches the deepest idea in the course: variance, not the mean, is what queues punish. The pattern generalizes: a weight editor previews its 60/30/10 split, a workload form live-updates the pattern sparkline, a cache slider could preview expected origin traffic. The pedagogical effect is to change the run's role — from revealing a mystery to confirming a prediction — which is the difference between demonstration and experiment.

**Applies in:** V13, B2, V2.

### 34. Degrade aggregation, never truth

**Rule:** Past the render budget, dots become density-mapped streams and per-request flashes become per-second counts — but the mapping to measured values survives, and rendering never touches the engine.

Big topologies will exceed any dot budget, so degradation must be designed rather than suffered. The gradient is: individual dots → aggregated streams whose *thickness* carries the same throughput mapping → glyphs-and-fill-levels only (which doubles as the reduced-motion accessibility mode). Two lines may never be crossed on the way down. First, **no fabrication**: a smooth "busy-looking" stream on an edge carrying 3 rps is a lie — low traffic must look low at every degradation level. Second, **isolation**: the visualization layer reads the event stream and nothing else; frame drops may cost fidelity of the picture, never correctness or determinism of the simulation. Classroom hardware makes this a first-class requirement, not an edge case — the target machine is a lecture-hall laptop, and G3's memoization fix is this principle's down payment.

**Applies in:** D1, G3. Accessibility: reduced-motion = final degradation level.

### 35. Every encoding is inspectable

**Rule:** Anything visualized answers a click — a dot opens its request, a bar its history, a glyph its threshold — and a persistent, lens-aware legend explains the active encodings in one line.

This is P6 extended from numbers to pictures: an unexplained encoding is an unexplained number wearing paint. Every visual element is a claim about the simulation, so every element owes an answer — the dot yields its request ID and, from there, the full trace (D2); the queue bar yields depth-over-time; the ⚠ glyph yields the exact threshold that set it; the edge stream yields its measured rates. Inspectability also closes the trust loop for the visualization layer itself: because every picture links to the events beneath it (P9), a skeptical student can always audit what they're seeing — the same right the λ/W/L disclosure grants for statistics. The legend handles the ambient half: one line, always visible, updated with the lens — "dots = requests · speed = edge latency · violet = cache hit" — so nobody is ever guessing what a color means.

**Applies in:** B4, D2, C3. UI: persistent lens-aware legend.

---

### Visualization catalog — what must be visualizable, and what each view teaches

The buildable inventory implied by the rules above. **Live** = during run; **Post** = after completion; **Config** = before running. Items marked ● have working prototype demos in `planning/roadmap-reference.html`. (Task references: D1/D2 per the execution roadmap.)

| # | Visualization | When | Teaches | Governed by |
|---|---|---|---|---|
| V1 ● | Request dots on edges (density/speed/color mapped) | Live + replay | Flow, latency differences, where traffic actually goes | 25–27 |
| V2 ● | Workload pattern sparkline + playhead in scenario bar | Config + Live | Traffic patterns; cause of downstream load changes | 28 |
| V3 ● | Routing-strategy signatures (all 8) | Live + replay | LB strategies, broadcast vs. point-to-point, L7 content routing | 29 |
| V4 ● | Worker slots + queue bar + rejection bounce per node | Live + replay | Utilization, queueing, capacity, rejection — G/G/c/K itself | 30 |
| V5 ● | Trait signatures (cache absorb, rate-limit shed, breaker open, async ack, cold start) | Live + replay | Each distributed-systems concept the trait models | 31 |
| V6 ● | Node health transitions + traffic redistribution | Live + replay | Failure, detection latency, health-aware routing | 29, 31 |
| V7 | Follow-one-request trace with latency accumulator | Post (D2) | Where end-to-end time goes; request lifecycle | 27, 35 |
| V8 | Per-hop latency waterfall (stacked bar) | Post | Latency decomposition; which hop dominates | 6, 35 |
| V9 | Time-series: utilization / queue depth / throughput per node, warmup-shaded, pattern-overlaid | Post | Dynamics over time; correlation of load pattern with saturation | 28, 32 |
| V10 | Metric-lens canvas heatmap | Post + Live | System-level hotspots one question at a time | 12, 13 |
| V11 | A/B run comparison (side-by-side + per-node deltas) | Post | Effect of one architectural change, attributably | 18 |
| V12 | Latency histogram with percentile markers | Post | Distributions vs. averages; why p99 ≠ p50 | 6, 33 |
| V13 | Distribution-shape preview in properties panel | Config | Service-time distributions; variance as a concept | 33 |
| V14 ● | Backpressure / cascade view (saturation propagating upstream) | Live + replay | Cascading failure, bottleneck upstream effects | 25, 30 |
| V15 | Conservation waterfall (generated → completed/cached/rejected/timed-out) | Post | Request accounting; where requests end up | 10 |

Sequencing note: V1–V4 are the foundation (V1 exists in early form; V2–V4 make it meaningful); V5–V6 land with each trait (workstream A); V7–V12 are the analysis layer (workstream B/C/E); V13–V15 fill in as their engine features mature.

---

## Using this list

- **In specs:** cite principles by name in the rationale section.
- **In review:** a violation is a blocking comment; either the PR changes or this document does (with the amendment recorded).
- **In prioritization:** P0 is whatever currently violates principles 1–11 in shipped behaviour — those are trust debts, not features.
- **For diagrams, live demos, and algorithms:** open `planning/roadmap-reference.html` — every principle above has a diagram there (`#p1`…`#p35`), nine simulation demos make F-family principles watchable, and the algorithms appendix holds the pseudocode (DES loop, G/G/c/K admission, all trait algorithms, routing selection, RNG substreams, default resolution, verification math), the rejection taxonomy, and the metrics glossary.

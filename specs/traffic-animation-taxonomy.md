# Traffic Animation Taxonomy — Every Factor That Changes How Traffic Flows

> **Goal.** An exhaustive, code-grounded catalogue of everything that determines
> how request traffic flows and animates across the canvas — so the edge-dot
> animation (and any "explain this" preview) can faithfully reflect the real
> mechanism for every node type, edge type, strategy, and outcome. This is the
> reference behind making the runtime dots legible per pattern.
>
> **Status.** Analysis (2026-09-11). The runtime edge dots are already driven by
> real per-hop `EdgeFlowEvent`s the engine emits ([engine.ts] `emitEdgeFlowEvent`
> on `route.edge.id`), so distribution is faithful by construction; the open work
> is *visual encoding* of these patterns and authoring the request metadata
> (Axis G) that several of them depend on.

Traffic flow is the product of **seven orthogonal axes**. Any given dot's
existence, path, speed, and fate is a combination of one value from each.

---

## Axis A — Temporal shape: *when* dots appear (rate over time)

Driven by the source `workload.pattern` (`edgeFlowPatterns.ts` `patternMultiplier`).
Controls dot **frequency/density**, not direction.

| Pattern | Animation |
|---|---|
| `constant` | steady, even dot cadence |
| `poisson` | randomized jitter around a mean rate |
| `bursty` | alternating dense-burst / sparse-normal windows |
| `spike` | a sudden dense window at `spikeTime`, then back to baseline |
| `sawtooth` | ramp from base → peak, snap down, repeat |
| `diurnal` | slow hourly-multiplier swell and ebb |
| `replay` | fixed cadence from a recorded/committed offset |

## Axis B — Spatial distribution: *which edge(s)* get the dot at a fork

Driven by the source node's distribution mechanism (`routing.ts` + traits). This is
the core "how is it distributed" axis.

| Mechanism | Node types | Distribution | Animation |
|---|---|---|---|
| round-robin | LBs, routers | even, rotating | dots cycle edge→edge in order |
| weighted | any multi-out (edge weights) | proportional | heavier edge gets proportionally more dots |
| random | any multi-out | even (stochastic) | dots scatter uniformly |
| least-conn | LBs | adaptive to load | dots favor the currently-idle edge |
| least-response-time | LBs | adaptive to latency | dots favor the fastest-returning target |
| p2c (power-of-two) | LBs | near-even, sampled | dot picks the lighter of two sampled edges |
| passthrough | routers | single | always the first eligible edge |
| sticky / ip-hash | LBs | pinned per key | same client/session key → always the same edge (consistent-hash ring) |
| broadcast fan-out | pub-sub, message-broker, event-bus | all | one dot per subscriber edge simultaneously |
| consumer groups | broker/stream + subscribers | one-per-group | one dot per group; members within a group share |
| key/partition routing | sharding, hashing | key→shard | same key → same shard edge (consistent-hash) |
| stream partitioning | stream | key→partition (modulo) | same key → same partition |
| content routing | L7 LB, api-gateway, ingress | rule-matched | dot follows the edge whose rule matches (type/method/path/host/header; equals/prefix/regex) |
| scatter/gather | search-service, search-index | fan-out + join | dots scatter to all shards, then a gathered return |
| fan-out amplification | any edge w/ `fanoutFactor>1` | multiplied | one inbound dot becomes N dots on that edge |

## Axis C — Edge mode: *how* the dot travels (semantics)

Driven by `edge.mode` (`core/types.ts`).

| Mode | Animation |
|---|---|
| `synchronous` | dot travels out **and a response dot returns** along the path |
| `asynchronous` | fire-and-forget: dot travels out, no return; **always fans out** to every async edge |
| `streaming` | continuous flow rather than discrete request/response |
| `conditional` | edge only carries a dot when its condition matches the request |

## Axis D — Node effect: does the dot continue, short-circuit, split, drop, or multiply

Driven by node traits. This changes flow *at* a node, not just at the fork.

| Trait / node | Effect on flow | Animation |
|---|---|---|
| cache hit | short-circuit | dot returns from the cache, **never reaches downstream** |
| cache miss | pass-through | dot continues to the origin, then back |
| rate limiter (admit) | pass-through | dot continues |
| rate limiter (breach) | drop | dot **dies at the limiter** |
| circuit breaker (closed) | pass-through | dot continues |
| circuit breaker (open) | reject / reroute | dot bounces / diverts |
| reservation store | commit / conflict / oversell | dot resolves as success or a fast "sold out" |
| retry + backoff | repeat | a failed dot **re-fires** on the same edge after a delay |
| replication (write) | fan to replicas | write dot **splits** to leader + followers |
| read/write split | role-based | reads → replica edges, writes → leader edge |
| cold start / autoscaler | delay then flow | first dot **stalls** (warm-up) before travelling |
| batching | coalesce | several dots **merge** into one downstream dot |

## Axis E — Outcome: the dot's *fate* (drives color / end-state)

Driven by `EdgeFlowStatus` + `EdgeFailureCause` (`core/events.ts`).

| Status / cause | Animation |
|---|---|
| `success` | dot completes and fades normally |
| `edge-error` (`connection_refused`) | dot fails at the far end |
| `edge-error` (`edge_error_rate`) | dot fails mid-edge (random error) |
| `packet-loss` | dot vanishes in transit |
| `timeout` (`deadline_exceeded`) | dot stalls then expires before arrival |
| consumer-group-rebalance | (event) group reassignment ripple |
| network-partition | (event) an edge/region goes dark |

## Axis F — Edge physical properties: dot *speed* and appearance

Driven by `edge.latency.pathType`, `bandwidth`, `packetLossRate`, `errorRate`.

| Property | Animation |
|---|---|
| `pathType` same-rack → same-dc → cross-region | dot travels progressively slower |
| `bandwidth` cap | under load, dots **queue/backpressure** on the edge |
| `packetLossRate` | a fraction of dots vanish (feeds Axis E) |
| `errorRate` | a fraction of dots fail (feeds Axis E) |

## Axis G — Request identity: *which* dot, and where it pins (the authoring gap)

Driven by request metadata. **This is what makes Axis-B affinity/key/content
patterns actually differ** — and most of it has no authoring UI yet (the in-flight
work). Fields the engine reads:

| Field | Read by | Enables |
|---|---|---|
| `type` | edge conditions, content routing | conditional edges, type rules |
| `method` / `path` / `host` | content routing | L7 rule routing (authorable today) |
| `headers[name]` | content routing (`header` rules) | header routing (needs authoring) |
| `sessionId` | sticky | session affinity (needs authoring) |
| `clientIp` | ip-hash | IP affinity (needs authoring) |
| `__key` (from `keyspace`) | sticky fallback, cache LRU, key routing | affinity + cache + shard/partition + Zipf skew (needs authoring) |
| `partitionKey` / `shardKey` | stream / sharding | partition / shard placement (needs authoring) |

**Authoring plan:** extend `RequestDistributionEditor` (which already authors
type/method/host/path) with `keyspace` (field/size/skew — one input unblocks
sticky, ip-hash via `clientIp`, key/shard/partition routing, cache LRU, and Zipf
skew) and a `headers` key/value editor (unblocks header routing). `requestDistribution`
passes through to the engine verbatim (`useTopologySerializer.ts`), so these are
live wires, not dead dials.

---

## How the axes compose

A single dot = **A** (born on this tick) × **B** (sent down this edge) × **C**
(this travel semantics) × **D** (this node's effect) × **E** (this fate) × **F**
(this speed), selected by **G** (this request's identity). The runtime animation
already realizes all of this from real events; the product work is (1) authoring
Axis G, and (2) visually **encoding** Axes B, D, and E so the *pattern* — not just
the motion — is legible at a glance.

---

## What is actually rendered today (per-axis)

- **A** ✅ dot cadence + `packetSpeedJitter(workload.pattern,…)`.
- **B** ✅ *effect* (busier edges = more dots + thicker stroke, from real
  `countsByEdgeId`) **plus** a node-card `Distributes: <mechanism>` label
  (`describeDistribution`, 2026-09-15) **plus** a per-edge **weight-share %** badge
  on weighted-routing edges (2026-09-15, guarded so it only shows when the source
  actually routes by weight). Remaining nicety: a canvas legend / live run readout.
- **C** ✅ edge mode → `strokeDasharray` (line style).
- **D** ◑ node effects now surface as **runtime markers on the card** (2026-09-15):
  `describeNodeEffects(metrics)` → `RuntimeNodeMetrics` shows badges for the
  *hidden* effects — `⚡ cache X%` (short-circuit), `↻ N retries`, `⇉ replicated`,
  `⋔ scatter/gather`, `⊘ N dupes blocked`. Drops/timeouts stay in the
  Rejected/Timed-out cell (not duplicated). Still no on-edge animation for these
  (e.g. a dot visibly bouncing back from a cache).
- **E** ✅ failure pulses colored by cause; failing link stroke turns red.
- **F** ✅ stroke width = volume; **dot speed now also scales with `pathType`
  latency** (2026-09-15, `latencySpeedFactor`) — cross-region dots visibly crawl
  vs same-rack. (Bandwidth backpressure still not visualized.)
- **G** ◑ authoring landed 2026-09-11; **"color dots by key" mode shipped
  2026-09-15** — `EdgeFlowEvent.key` (engine `affinityKeyOf`: __key / partitionKey
  / shardKey / sessionId / clientIp) + a `colorDotsByKey` display toggle tint each
  edge dot by a stable per-key hue (`keyToColor`, golden-angle). A key's color
  stays on one edge under sticky/shard and scatters under round-robin. Off by
  default. (Dots are still synthetic — colored from real keys sampled per edge,
  not one-dot-per-request.)

**Progress:** shipped — Axis-G authoring (keyspace + headers, 2026-09-11);
Axis-B mechanism label + per-edge weight-share %; Axis-D node-effect markers;
Axis-F latency-driven dot speed; Axis-G color-dots-by-key (all 2026-09-15).
**Every axis is now legible to at least ◑.**

**Deliberately deferred (rework disproportionate to payoff):**
- **On-edge D animation** (a dot bouncing back from a cache / splitting at a
  replicator): needs per-node return-path animation; the card markers already name
  every hidden effect, so this is polish, not a gap.
- **True per-request dots**: the success stream is synthetic (count/speed from
  aggregate rate) for performance at high RPS; color-by-key samples real keys per
  edge, which already conveys the pattern. Exact per-request dots would be a costly
  animation rework with little added insight.
- **Bandwidth backpressure** viz and a **canvas legend**: minor niceties.

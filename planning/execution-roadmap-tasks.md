# Execution Roadmap — Detailed Task Breakdown

> **Purpose:** Actionable task list derived from the July 2026 product diagnosis: the simulator computes queueing numbers correctly but cannot answer *"why is this number what it is"* for anything on screen. Node types don't behave like what they claim to be, numbers appear without provenance, and the UI renders everything at maximum detail all the time.
>
> **Date:** July 2026
>
> **Sources:** `specs/node-behaviour/node-behaviour-specification.md` (trait system design), `specs/default-driven-simplification-layer.md` (default provenance), `planning/analysis/meeting-feedback-analysis.md` (classroom priorities), `specs/question-creation-feature-spec.md` (grading), plus a live run of the app (Client → L7 LB → 2× API Server → Redis → Primary DB, Poisson 100 rps, 60s) and a competitive review of Pinpole (app.pinpole.cloud).
>
> **Governing principles:** see `design-decisions/governing-principles.md` for the full set of 35 (including visualization governance, section F). The three that anchor this roadmap:
> 1. **Nodes must be true.** A cache must absorb traffic; an LB must skip dead servers; L4 must refuse content routing. Until then, every demo undermines trust.
> 2. **No number without a why.** Every displayed value is user-set, defaulted (with visible provenance), or measured (with an inspectable cause).
> 3. **Altitude, not amputation.** Complexity stays available, but never all at once. One metric family on the canvas at a time; detail on selection; verification math behind a disclosure.

---

## How to read the tasks

Each task has:

- **Priority** — P0 (trust blocker, do first), P1 (makes it usable/teachable), P2 (expansion).
- **Effort** — S (≤1 day), M (2–4 days), L (1–2 weeks), XL (multi-week).
- **Depends on** — hard ordering constraints only.
- **Acceptance criteria** — observable behaviour that closes the task. Written so a run of the app (or a test) can verify them.

Dependency spine: **A1 → A2/A3/A4 → everything in A** • **B1 → B2/B3** • **C is independent of A but lands best after B2** • **D2 needs nothing new from the engine** • **F needs A + a verdict contract**.

---

## Workstream A — Node Truthfulness (Behavioural Trait System)

Implements `specs/node-behaviour/node-behaviour-specification.md` §6–8. The base `GGcKNode` queue stays untouched; traits overlay type-specific behaviour via hooks. This workstream is the foundation for accuracy (goal 1), node nuance (goal 2), and system cohesion (goal 3).

### A1 — Trait interface + engine hooks (Phase 0 foundation)

**Priority:** P0 · **Effort:** M · **Depends on:** nothing

Create the `NodeBehaviourTrait` interface and wire its three hooks into the engine event loop. This is pure plumbing — no behaviour change until traits exist — but it blocks every other task in this workstream.

**What to build:**
- `src/engine/traits/types.ts` — the `NodeBehaviourTrait` interface exactly as specified in the node-behaviour spec §6.3: `beforeArrival` (returns `continue` / `handled` / `rejected`), `beforeRouting` (returns `route` / `complete` / `reroute`), `filterRoutes` (candidate filtering).
- `src/engine/traits/resolveTraits.ts` — `resolveTraits(node: ComponentNode): NodeBehaviourTrait[]`, mapping component type → trait list per the table in spec §6.5. Resolution must key off the component/template type, **not** node-ID substring matching (see A8).
- Hook calls in `src/engine/engine.ts`: `beforeArrival` inside `handleRequestArrival` (before queue admission, after the existing security-policy check), `beforeRouting` inside `handleProcessingComplete` (before `routing.resolveTarget`).
- Hook call in `src/engine/routing.ts`: `filterRoutes` inside `resolveTarget`, applied to the candidate edge list before strategy selection.
- Deterministic ordering when a node has multiple traits (declare order in the trait list; document it).
- Trait decisions must be recorded as canonical events (e.g. `trait-cache-hit`, `trait-rejected: rate_limited`) so the replay log and event debugger can explain them — this is what makes B4 ("click a number, see why") possible later.

**Acceptance criteria:**
- All existing engine tests pass unchanged with an empty trait registry (zero behaviour delta).
- A dummy test trait that rejects every request produces 100% rejections with the trait's reason string in the event log.
- Trait hook calls appear in the replay/event stream with node ID, trait name, and decision.

---

### A2 — `HealthAwareRoutingTrait` + health registry (the LB-routes-to-dead-servers fix)

**Priority:** P0 · **Effort:** M · **Depends on:** A1

The #1 demo-killer from meeting feedback: load balancers currently route to failed servers. Add a shared health registry to the engine and a `filterRoutes` trait that consults it.

**What to build:**
- A `HealthRegistry` in the engine: per-node health state (`healthy`/`unhealthy`), updatable by node failure status and by probes (A5).
- `src/engine/traits/healthAwareRouting.ts` — `filterRoutes` removes candidates whose target is failed/unhealthy. If **all** candidates are unhealthy, reject with reason `no_healthy_targets` (a new rejection reason surfaced in metrics and the results tray).
- Config knob `healthCheckEnabled` (default `true`) on all LB variants, API Gateway, Ingress Controller, Reverse Proxy — exposed in the properties panel.
- Applies to: `load-balancer`, `load-balancer-l4`, `load-balancer-l7`, `api-gateway`, `ingress-controller`, `reverse-proxy` (spec §6.5).

**Acceptance criteria:**
- Topology: LB → 2 servers, one marked failed. With trait on: 100% of traffic reaches the healthy server; zero requests arrive at the failed one. With `healthCheckEnabled: false`: old behaviour (traffic splits, requests to the dead server fail) — the *difference* is the lesson.
- LB → 1 failed server: all requests rejected `no_healthy_targets`, visible in the results tray with that reason.
- Unit tests for the registry and the filter; integration test for the two-server scenario, deterministic under a fixed seed.

---

### A3 — `CacheTrait` for CDN, Redis Cache, Reverse Proxy (the caching fix)

**Priority:** P0 · **Effort:** M · **Depends on:** A1

The most broken teaching behaviour, verified live: Redis received 2,656 requests and the downstream Primary DB received 5,312 — the cache absorbed **zero** traffic. The entire point of a cache is to reduce origin load.

**What to build:**
- `src/engine/traits/cache.ts` — `beforeArrival` rolls the seeded RNG against `cacheHitRate`:
  - **HIT** → return `handled` with `cacheHitLatencyMs`; engine schedules `request-complete` after that latency; request is **not** forwarded downstream. Metrics record it as completed, tagged `servedFromCache`.
  - **MISS** → `continue`: normal queue + forward to origin.
- Config knobs per spec §7.1: `cacheHitRate` (0.0–1.0), `cacheHitLatencyMs` (defaults: CDN 1ms, Redis 0.1ms), optional `ttlSeconds`.
- Per-node metric: hit count, miss count, hit ratio — surfaced on the node's selection panel and in the Nodes table.
- Palette defaults: CDN `cacheHitRate: 0.9`, Redis `0.8`, Reverse Proxy `0` (opt-in). Defaults must be visible/editable in the properties panel (ties into B2).
- Applies to: `cdn`, `redis-cache`, `reverse-proxy` (optional), later `dns`.

**Acceptance criteria:**
- Topology: source(100 rps) → cache(hitRate 0.9) → DB. DB arrivals ≈ 10% of cache arrivals (within seeded-RNG tolerance); cache-hit completions have latency ≈ `cacheHitLatencyMs`, not queue service time.
- Setting `cacheHitRate: 0` reproduces today's pass-through behaviour exactly (regression guard).
- Node card / panel shows "87% served from cache" (exact wording per C2).
- Conservation check still balances: generated = completed + rejected + timed out, with cache-served counted as completed.

---

### A4 — `ContentRoutingTrait` + L4 enforcement (the L4 vs L7 lesson)

**Priority:** P0 · **Effort:** M · **Depends on:** A1

Make the L4/L7 distinction real and observable — currently they differ only by 0.25ms of default service time.

**What to build:**
- `src/engine/traits/contentRouting.ts` — `filterRoutes` evaluates `routingRules` (`matchField: 'type' | 'path' | 'host'`, `matchValue`, `targetNodeId`) against request attributes; on match, route to the rule's target; otherwise fall through to the default strategy.
- Applies to: `load-balancer-l7`, `api-gateway`, `ingress-controller`. **Explicitly not** `load-balancer-l4` — that omission is the feature.
- **Enforcement (the teachable moment):** when a user attaches a conditional edge or routing rule to an L4 LB, block it at the canvas level (see C5) with the exact message from spec §3.2: *"L4 operates at the transport layer and cannot inspect HTTP content. Use an L7 Load Balancer for content-based routing."* The engine validator must also reject it (defense in depth) so headless/JSON-authored topologies get the same rule.
- `routingRules` editor in the L7/Gateway properties panel (simple list UI: field, value, target dropdown of connected nodes).

**Acceptance criteria:**
- L7 LB with rule `type=write → node_db_primary`: all write-type requests land on the primary; reads follow round-robin.
- Same rule config on an L4 LB: canvas blocks with the explanatory message; validator errors on JSON import with a matching code.
- An instructor can build the "L4 vs L7 comparison" scenario (E1) with no code changes.

---

### A5 — `HealthProberTrait` (Health Check Manager becomes functional)

**Priority:** P0 · **Effort:** M · **Depends on:** A2

Gives the health registry its real-world mechanism, and makes the Health Check Manager palette node do something.

**What to build:**
- `src/engine/traits/healthProber.ts` per spec §7.9: on a simulated-clock timer (`checkIntervalMs`), send synthetic probe events to `monitoredNodes`; count consecutive failures/successes; flip registry state at `unhealthyThreshold` / `healthyThreshold`.
- Probes are engine events (visible in the replay log, filterable) but excluded from user-facing throughput/latency metrics.
- If no Health Check Manager node exists, LBs with `healthCheckEnabled` fall back to instantaneous health knowledge (A2 behaviour) — document this simplification in the node's info card (E2).

**Acceptance criteria:**
- Scenario: server fails mid-run (via node failure schedule). For `unhealthyThreshold × checkIntervalMs` after the failure, the LB still routes to it (requests fail); after detection, traffic shifts to healthy targets. The detection window is visible in the event log — this *is* the lesson about why health checks have detection latency.
- Probe events appear in replay tagged as probes; summary metrics unchanged by their presence.

---

### A6 — Phase 2 traits: RateLimiter, ReadWriteSplit, ReadOnly, AckAndRelease, AsyncOnly

**Priority:** P1 · **Effort:** L · **Depends on:** A1 (A6-d also touches metrics)

Five smaller traits, spec §7.4–7.8 and §8 Phase 2. Implement in this order:

- **A6-a `RateLimiterTrait`** (API Gateway, External Service): token bucket (`maxTokens`, `refillRatePerSecond`) in `beforeArrival`; exhaustion → reject `rate_limited`. Acceptance: gateway limited to 50 rps under a 100 rps workload rejects ≈50% with `rate_limited`, and the rejection reason is distinct from `capacity_exceeded` everywhere it renders.
- **A6-b `ReadWriteSplitTrait`** (Primary DB): sample service time from `readLatency` or `writeLatency` distribution based on `request.type`. Acceptance: 70/30 read/write workload shows bimodal per-type latency in the Nodes table.
- **A6-c `ReadOnlyTrait`** (Read Replica): `beforeArrival` rejects `request.type === 'write'` with `read_only_node`. Acceptance: writes routed at a replica get rejected with that reason; reads succeed.
- **A6-d `AckAndReleaseTrait`** (Message Queue): producer's request completes at enqueue time (ack); consumer processing is an independent lifecycle. Producer latency excludes consumer time — the decoupling lesson. Acceptance: producer p50 ≈ enqueue latency even when the consumer is saturated and queue depth grows visibly.
- **A6-e `AsyncOnlyTrait`** (observability nodes): edges into metrics/logging/tracing nodes default to async and never block or add latency to the request path. Acceptance: deleting an observability node from a topology does not change end-to-end latency percentiles.

---

### A7 — Phase 3 traits: ColdStart, KeyBasedRouting, ConsumerLag, CircuitBreaker

**Priority:** P2 · **Effort:** L · **Depends on:** A1, A6

Advanced teaching behaviours per spec §8 Phase 3: `ColdStartTrait` (serverless first-invocation latency + `maxConcurrency` hard cap with 429-style throttling), `KeyBasedRoutingTrait` (sharding/consistent hashing: same key → same target), `ConsumerLagTrait` (Kafka consumer-group lag metric), `CircuitBreakerTrait` (service mesh / sidecar: open after `failureThreshold`, half-open after `recoveryTimeoutMs`). Each ships with one scenario file (E1) that demonstrates it. Detailed configs are in spec §3.3, §3.5, and §7.7.

---

### A8 — Remove node-ID string matching from routing

**Priority:** P0 (bundled with A1) · **Effort:** S · **Depends on:** A1

`routing.ts:211–222` decides round-robin by checking whether the node **ID contains** `"load-balancer"`, `"lb"`, `"ingress"`, or `"reverse-proxy"`. A node renamed by a student silently changes routing behaviour. Replace with resolution from component type / trait list (the `resolveTraits` mapping is the single source of truth). Acceptance: a load balancer whose ID is `my-router-1` still round-robins; a plain service named `lb-ish-thing` does not.

---

## Workstream B — Number Provenance ("no number without a why")

Implements the missing pieces named in `specs/default-driven-simplification-layer.md`. Every number on screen must be traceable to: user input, a visible default, or a measured cause.

### B1 — Unified default resolver with provenance

**Priority:** P0 · **Effort:** L · **Depends on:** nothing (parallel with A)

Today defaults are applied at five uncoordinated sites (`engine.ts` `withNodeDefaults`, `validator.ts:616–631` duplicate, `useTopologySerializer.ts` edge defaults + workload merge, `ui.ts` scenario state, `componentSpecs.ts` catalog seeds). The validator and engine can diverge; programmatic topologies skip edge defaults entirely.

**What to build:**
- A single `resolveDefaults(topology)` module in the engine, used by **both** the validator and the engine at construction (delete the duplicated `withNodeDefaults` logic).
- Output: the resolved topology **plus a `DefaultResolutionTrace`** — for every parameter, `{ value, source: 'user' | 'catalog' | 'engine' | 'environment', rationale? }`. Catalog entries carry a one-line rationale string (e.g. `"8ms — typical Postgres OLTP query"`), sourced from the canonical catalogue.
- Edge defaults move into this resolver so JSON-authored/headless topologies get identical treatment to canvas-built ones.
- The trace serializes into `SimulationOutput` so the UI (B2) and the question grader (F) can consume it.

**Acceptance criteria:**
- Grep-level: exactly one place in the codebase defines node/edge default values.
- A topology JSON with zero config runs identically via canvas and via CLI (same seed → same output hash).
- `SimulationOutput` contains the resolution trace; a test asserts every parameter has a source tag.

---

### B2 — Defaulted-value badges in the properties panel

**Priority:** P0 · **Effort:** M · **Depends on:** B1

Make defaults visible and explainable at the point of configuration.

**What to build:**
- In `PropertiesPanel` / `ComputeForm` / `ServiceForm` / edge panel: parameters currently at their default render with a subtle "default" badge; hovering shows source + rationale from the trace ("catalog default for Relational DB — 8ms, typical OLTP query").
- User-modified values lose the badge; a "reset to default" affordance restores it.
- Node cards on the canvas stop rendering raw config (see C2) — the panel is where config lives, with provenance.

**Acceptance criteria:**
- Drop a fresh Primary DB: every field shows a badge with a sensible rationale on hover. Change workers 8 → 20: badge disappears on that field only; reset restores it.
- No default value anywhere in the panel is unexplained.

---

### B3 — Kill silent error-rate and jitter seeds

**Priority:** P0 · **Effort:** S–M · **Depends on:** B1 (do the palette change immediately; fold into resolver when B1 lands)

Verified live: an untouched 6-node topology reported **0.5% error rate (26 errors)**, a **0.15%** LB error chip, and **"jitter / 0.3% fail"** edge labels — all from seeded defaults the user never chose. Noise the student didn't cause is the worst kind of unexplained number.

**What to build:**
- Set default `nodeErrorRate`, edge `errorRate`, and edge `packetLoss` to **0** in `paletteTemplates.ts` / `componentSpecs.ts` for all components. Failure becomes something you *inject* (chaos/scenario config), never ambient.
- Keep realistic non-zero defaults only where the value is the component's identity (WAF `blockRate`, Firewall `droppedPackets`) — these already render as explicit config on the security nodes.
- Edge latency defaults: reduce to path-type-appropriate values per spec §5.2 (same-zone ≈ 0.5–1ms, not 10–15ms of invisible "internet" latency between adjacent tiers), and show the resolved edge latency in the edge panel with its provenance badge.

**Acceptance criteria:**
- Fresh default topology, 60s run: **0 errors, 0% error rate**, no fail% edge labels.
- End-to-end p50 for client → LB → server → DB is dominated by service times, and every ms of it is attributable in the latency breakdown (B4).

---

### B4 — "Why this number?" inspection (metric → cause)

**Priority:** P1 · **Effort:** L · **Depends on:** A1 (trait events), B1

The inverse of provenance for **measured** values: click any headline metric and see its decomposition.

**What to build:**
- **Latency breakdown:** end-to-end percentiles decompose into per-hop segments (edge latency + queue wait + service time per node), computed from the canonical event stream. Render as a horizontal stacked bar ("where did my 51ms go?") in the Overview tab and for any selected completed request in the Traffic tab.
- **Error/rejection breakdown:** error rate expands into reasons × nodes (`rate_limited @ gateway: 12`, `no_healthy_targets @ lb: 3`), each linking to a filtered event-log view.
- **Throughput accounting:** generated → completed (+ served-from-cache) → rejected → timed-out waterfall, reusing the existing conservation check data.

**Acceptance criteria:**
- From "Error Rate 0.5%", two clicks reach the individual events that failed, with reasons.
- The latency stacked bar's segments sum to the reported end-to-end value (within rounding).
- Every headline number in the Overview tab is clickable to a decomposition; none is a dead end.

---

## Workstream C — Display Altitude (structure, not clutter)

Three levels: **Canvas** (status + one number per node), **Selection** (full detail for one element), **Analysis** (results tray). Plus a metric lens so the canvas answers one question at a time. This is the Pinpole presentation lesson applied to a deeper engine.

### C1 — Metric lens switcher

**Priority:** P1 · **Effort:** M · **Depends on:** none (better after B3)

A single-select control (canvas toolbar or `ScenarioBar`): **Saturation · Latency · Errors · Throughput**. The active lens determines the one metric family shown on every node card and edge label. Default lens: Saturation (utilization/limit) — the question most runs are asking.

**Acceptance criteria:**
- Switching lenses swaps every node's displayed number and edge label instantly, post-run and live.
- No lens shows more than one metric family on the canvas at once.
- Lens choice persists per session; deep detail remains available via selection (C3) regardless of lens.

---

### C2 — Node cards: one number with limit context (`value / limit ✓⚠✕`)

**Priority:** P1 · **Effort:** M · **Depends on:** C1

Replace the current cards (pre-run: Workers/Capacity/Timeout grid; post-run: utilization bar + queue chip) with Pinpole-style capacity-context lines.

**What to build:**
- **Pre-run:** icon, editable label, type sublabel, status dot. **No config numbers** — config lives in the properties panel with provenance (B2). Optionally one identity chip where it defines the node (cache: "hit 80%"; source: "100 rps poisson").
- **Post-run/live:** one line for the active lens, always as value against its limit: Saturation `6.2 / 8 workers ⚠`, Throughput `96 rps (in) → 10 rps (out)` for caches/filters, Latency `p95 23ms`, Errors `0.4% (12) ✕`. Status glyph thresholds shared with the health-color logic in `nodePresentation.ts` (single source of truth).
- Fix the misleading inactive state (see G2) as part of this rewrite.

**Acceptance criteria:**
- A 20-node topology is readable at fit-to-view zoom: per node exactly one number, one glyph, one label.
- The card alone answers "is this node OK and how close to its limit is it" without opening anything.
- Cache nodes visibly show absorption under the Throughput lens (in ≫ out) once A3 lands.

---

### C3 — Selection detail panel (second altitude)

**Priority:** P1 · **Effort:** M · **Depends on:** C2

Selecting a node or edge post-run shows its full metric set in the side panel (where the config forms live pre-run): throughput in/out, utilization, queue depth over time (sparkline if available), latency percentiles, rejections by reason, trait-specific metrics (hit ratio, tokens exhausted, replication lag), each measured value linking into B4 decompositions. Acceptance: everything currently in the Nodes-table row for that node is reachable from selection, plus trait metrics; nothing of it is on the card.

---

### C4 — Results tray: verdict first, verification behind disclosure

**Priority:** P1 · **Effort:** M · **Depends on:** B4 helps but not required

Restructure `ResultsTray.tsx` ordering:

- **Open with findings** (Pinpole's ranked-recommendation pattern): severity-ordered cards — WARNING / ADVISORY / INFO — each naming the node, the measured problem, the likely consequence at scale, and a suggested change ("Primary DB is the first bottleneck: 10% util at 100 rps → saturation ≈ 1,000 rps. Add a read replica, or give the cache a hit rate."). Source these from the existing bottleneck/SLO/conservation analysis — reframed as sentences, not a checklist.
- **Then the summary strip** (requests, throughput, error rate, p50/p95/p99) — each value clickable per B4.
- **RUN CONTEXT** (source/pattern/RPS/duration/warmup/seed) collapses to a single one-line strip with an expander — it echoes what the user just entered and should never occupy the first screenful.
- **Nodes tab:** default columns Arrived · Done · Rejected · Util · p95. λ/W/L and Little's-Law columns move behind a "Verification" toggle with a one-line explainer of what they prove.

**Acceptance criteria:**
- The first screenful after a run states what's wrong (or that nothing is) in prose, before any table.
- Every finding names its evidence and links to the node/decomposition.
- λ/W/L hidden by default, one click away, explained.

---

### C5 — Canvas-level connection validation with teaching messages

**Priority:** P1 · **Effort:** M–L · **Depends on:** A4 for L4 rules; extensible thereafter

Pinpole blocks invalid wiring before save. Your version is better because the constraint is the curriculum (spec §5.3–5.8 compatibility matrices).

**What to build:**
- An `isValidConnection` layer on `FlowCanvas` backed by a declarative rule table (protocol/mode/type compatibility from spec §5). On an invalid attempt: block the edge and show a toast/popover with the *reason written as a lesson* ("Read Replicas can't receive writes — route writes to the Primary").
- Same rules enforced in `validator.ts` for imported JSON (shared rule table, not duplicated).
- Warnings (allowed-but-suspect) render as a yellow edge badge rather than a block.

**Acceptance criteria:**
- Conditional route on L4 LB: blocked with the L4/L7 message (A4).
- Client wired directly into a Read Replica for writes: warning badge with explanation.
- Rules are data (one table), consumed by both canvas and validator; a unit test iterates the table in both directions.

---

### C6 — Edge labels obey the lens

**Priority:** P1 · **Effort:** S · **Depends on:** C1

Edge labels currently stack rps + jitter + fail% (e.g. "48.3 rps · jitter / 0.3% fail"). Under the lens system an edge shows only the active family: Throughput → `48 rps`, Latency → `10ms`, Errors → `0.3%` (nothing when zero), Saturation → no label (edges don't saturate; hide). Full edge detail moves to edge selection (C3). Acceptance: at most one metric per edge label at any time; zero-valued labels render nothing.

---

## Workstream D — Flow Visualization (show the system moving)

### D1 — Packets reflect measured flow

**Priority:** P1 · **Effort:** M · **Depends on:** A3 (to be meaningful), C1

Packet animation exists (`PacketEdge.tsx`, recent commits). Tie it to truth:

- Packet emission rate per edge proportional to that edge's measured throughput (log-scaled; clamped for performance) — after A3, a 90%-hit cache visibly starves its downstream edge with **no extra code here**.
- Packet color by outcome: success neutral, rejected red (briefly emitted back toward source or flashed at the rejecting node), cache-hit distinct at the cache.
- Global toggle + automatic degradation above an edge-count/FPS threshold.

**Acceptance criteria:** with a 0.9-hit-rate cache, the cache→DB edge shows ~1/10th the packet density of the LB→cache edge; a rate-limited gateway visibly sheds red at itself; toggling packets off leaves lens labels intact.

---

### D2 — "Follow one request" replay mode

**Priority:** P1 · **Effort:** L · **Depends on:** nothing in the engine (the canonical event log already records every hop — verified: req-000001's generated→forwarded→arrived→processing→completed chain is all there)

The single most teachable animation: watch one request traverse the system.

**What to build:**
- From the Traffic tab (or a completed-request row), "Trace on canvas": animates that request hop-by-hop at adjustable speed (0.25×–4× of simulated time, with time-compression for long waits), highlighting the current node/edge and showing a running latency accumulator ("t=26.3ms — waiting in API Server queue").
- Sync the event-log table: rows highlight as the animation passes them.
- Request picker presets: "slowest request", "a rejected request", "a cache hit", "median request" — one click each.

**Acceptance criteria:** tracing the p99 request shows *where* the time went (the accumulator at each hop matches the B4 breakdown); tracing a rejection stops at the rejecting node with the reason; controls: play/pause/step.

---

## Workstream E — Teachability Content

### E1 — Scenario library (curated topologies + browser panel)

**Priority:** P1 · **Effort:** M · **Depends on:** A2–A4 for the scenarios to demonstrate truthfully; G1 so files keep loading

Per `meeting-feedback-analysis.md` §2.3:

- `scenarios/` directory of versioned topology JSONs with a manifest (title, description, concepts, difficulty, course/week tags).
- Sidebar tab "Scenarios" alongside the component library: browse, preview (name + description + thumbnail), one-click load (with unsaved-changes guard).
- Starter set, priority order: Single Server Basics · Load-Balanced Web App · **L4 vs L7 Comparison** (needs A4) · **Caching Impact** — same topology with/without cache (needs A3) · 3-Tier with Security · Event-Driven Pub/Sub (better after A6-d) · Observability Pipeline (A6-e) · Scale from Zero.
- Each scenario embeds a "what to look at" note shown on load ("Run this, then check the DB's arrival count. Now set the cache hit rate to 0 and re-run.").

**Acceptance criteria:** a first-time user reaches a meaningful completed run in under 2 minutes via a scenario; scenario JSONs are covered by a CI test that loads and runs each one headlessly (guards against the G1 class of rot).

---

### E2 — Component info cards

**Priority:** P1 · **Effort:** M · **Depends on:** none (content exists in the canonical catalogue CSVs)

Every palette entry and node gets an expandable info card: what it does in plain English, real-world equivalents ("This is your AWS ALB / NGINX"), when to use it, what the simulator models (and — honestly — what it doesn't, per node-behaviour spec gaps), and which config knobs matter first. Surface via palette hover and an ⓘ in the properties header. Acceptance: all ~67 palette entries have cards; the "what's simulated" section stays truthful as traits land (checklist per trait PR).

---

### E3 — Run history + A/B comparison

**Priority:** P1 · **Effort:** L · **Depends on:** C4 (comparison reuses its layout)

The fundamental teaching move is *compare*: with/without cache, before/after replica.

**What to build:**
- Session-scoped run history: each run stores topology snapshot, seed, workload, and `SimulationOutput` (persist to IndexedDB so reload survives; cap N).
- "Compare" view: pick two runs → side-by-side summary strips + per-node deltas (`DB arrivals: 5,312 → 531 (−90%)`), with green/red delta coloring and the topology diff summarized ("added: Redis Cache; changed: —").
- Deterministic seeds make this rigorous: same seed + same workload ⇒ deltas are attributable to the topology change alone. Say so in the UI.

**Acceptance criteria:** the Caching Impact scenario (E1) demo is: load → run → add hit rate → run → Compare, and the DB-arrivals delta headline is the first thing visible.

---

### E4 — First-run guided walkthrough

**Priority:** P2 · **Effort:** M · **Depends on:** E1

Tooltip-driven tour on first launch: place node → connect → configure (see the provenance badges) → run → read the findings → switch lens → trace a request. Skippable, re-launchable from Help. Per meeting feedback: without it, the first 30 minutes of class becomes tool orientation. Acceptance: completing the tour ends on a completed run with the findings panel open; total tour < 3 minutes.

---

## Workstream F — Question Creation & Simulator-Graded Assignments

Sequenced last deliberately: grading is only as credible as node behaviour (A) and number determinism (B). Full details in `specs/question-creation-feature-spec.md`; these tasks are its critical path.

### F1 — Simulation verdict contract + headless batch runner

**Priority:** P2 · **Effort:** L · **Depends on:** A2–A4, B1

- Freeze a versioned `SimulationVerdict` schema (spec Feature 1): pass/fail per scenario, measured metrics vs. thresholds, structural check results, engine + catalog versions, seed. Everything the grader consumes comes from this contract — never from raw output internals.
- Headless runner (spec Feature 2) building on the existing CLI: input = topology + scenario spec batch, output = verdict array; deterministic (same inputs ⇒ byte-identical verdicts); bounded runtime with per-scenario timeouts.

**Acceptance criteria:** golden-file tests: known topology + scenario batch ⇒ committed verdict JSON; runs identically on CI and locally; contract version bumps are explicit and tested.

---

### F2 — Scenario spec + rubric scoring for one question type end-to-end

**Priority:** P2 · **Effort:** XL · **Depends on:** F1

Ship **one** question type completely before generalizing to ten: **"Fix the bottleneck"** (student receives a broken topology; must modify it to meet SLOs under given scenarios).

- Scenario specification model (spec Feature 3): workload + injected failures + thresholds, authored as JSON.
- Rubric engine (spec Feature 4): weighted scenario results + structural rules (allowed/required components, spec Feature 5) → score + per-scenario feedback ("passed normal load; failed DB-failure scenario — no redundancy on the write path").
- Author flow: instructor builds the broken topology in the canvas, defines scenarios/rubric in a side form, exports a question package; student flow: load package (constraints enforced), edit, submit → verdicts → score + feedback.

**Acceptance criteria:** one real assignment authored, solved (well and badly) by test users, graded deterministically — identical submissions always score identically; feedback names the failing scenario and the reason.

---

### F3 — Remaining question types + LMS integration

**Priority:** P2 · **Effort:** XL · **Depends on:** F2

Generalize per the spec: question-type framework (Feature 6), topology diffing for fix/debug types (Feature 7), constraint enforcement (Feature 8), incremental evolution (Feature 9), Django/LMS submission pipeline. Gate each type on a real authored exemplar, as with F2.

---

## Workstream G — Bug Fixes (found during the July 2026 live review)

### G1 — Legacy topology migration failure is silent and fatal

**Priority:** P0 · **Effort:** S–M

Root-level `order-topology.json` fails to load: `Unable to migrate legacy node 'api-gw' — unknown template` thrown at `src/engine/catalog/legacyCanvasMigration.ts:106`, surfaced only in the console — the UI shows nothing and the canvas stays empty.

- Map missing legacy template IDs (`api-gw`, and audit for others) to current templates; where unmappable, import the node as a generic service with a per-node warning instead of aborting the entire file.
- Show a load-result toast: "Loaded 12 nodes · 2 migrated with warnings (view)".
- Add migration round-trip tests over every JSON checked into the repo and `scenarios/` (shared with E1's CI check).

**Acceptance criteria:** `order-topology.json` loads (fully migrated or with visible per-node warnings); no load failure is ever console-only.

### G2 — Source node renders as inactive after a successful run

**Priority:** P0 (fold into C2) · **Effort:** S

After a completed run, the Client App — which generated all 5,328 requests — renders grayed out with "No post-warmup traffic" (`isRuntimeNodeInactive` in `nodePresentation.ts:78` doesn't special-case sources, which have no *arrivals*). Sources should display generation stats ("100 rps · 5,328 sent") and never gray out while they emitted traffic. Acceptance: post-run source card shows sent count/rate; inactive styling reserved for nodes with zero post-warmup arrivals **and** zero generations.

### G3 — React Flow `nodeTypes`/`edgeTypes` recreated every render

**Priority:** P1 · **Effort:** S

Console repeats React Flow warning #002. Hoist `nodeTypes`/`edgeTypes` to module scope or memoize in `useFlowConfig`. Acceptance: warning gone; no re-render regressions (drag a node while a run animates).

---

## Suggested execution order

| Phase | Tasks | Outcome |
|---|---|---|
| **1 — Trust** (do first, in parallel) | A1+A8, A2, A3, A4, B3, G1, G2 | Nodes behave truthfully; no ambient noise; demos stop lying. This is the minimum bar before showing anyone the tool again. |
| **2 — Explainability** | B1, B2, A5, B4, G3 | Every number has a why: defaults badged, metrics decomposable, health checks real. |
| **3 — Structure** | C1, C2, C6, C3, C4, C5 | The canvas reads at a glance; the tray leads with a verdict; invalid wiring teaches. |
| **4 — Teaching** | E1, E2, D1, D2, E3, A6 | Scenarios, info cards, flow + trace, A/B comparison, async/rate-limit/DB traits. |
| **5 — Assessment** | F1, F2, E4, A7, F3 | Graded questions on a foundation that's now defensible. |

Rule of thumb throughout: **every task that adds a number to the screen must also add its "why"; every task that adds behaviour must add a scenario that demonstrates it.**

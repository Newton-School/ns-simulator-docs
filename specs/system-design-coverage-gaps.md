# System-design coverage map & gap register

> What the simulator can faithfully model for the four canonical interview designs
> (URL Shortener, Chat, News Feed, Google Docs), grounded in the engine's own
> **support ledger** (`src/engine/analysis/supportLedger.ts`) and the trait code — not
> guesses. Written to separate *real* functional gaps from things that are already
> modeled or correctly left to justification.

## 0. How to read this

Every capability is tagged with the ledger tier it actually has:
`first-class` (simulated + test-covered) · `guided` (modeled, with honest limits) ·
`structural-only` (topology/justify) · `presentational-only` (diagram box) ·
`deferred` (not a runtime surface — grade by justification).

The design principle for filling gaps (the doctrine from the builder spec §0.2 and the
overcoming notes): **fill a gap only by wiring it to something the engine consumes, or
by making the design *decision* observable via a measured metric.** Never fake a number;
correctness properties (convergence, exactly-once, linearizability) stay `deferred`.

## 1. Capability coverage (grounded in the ledger + traits)

| Capability | Tier | Notes / source |
|---|---|---|
| Cache the hot set (hit/miss, latency) | first-class | `cache.read-through`; TTL/eviction are topology intent only |
| Read/write split, read-only paths | first-class | `access.read-write-split` |
| Content-aware routing (by request `type`/`method`/`path`/`host`) | first-class | `routing.content-aware`; entity attributes are stamped as request `type` at the source |
| Key-based / partition-affine routing (sticky by key) | first-class | `routing.key-based`, `stream.partitioned-broker` — route-by-docId / conversation_id |
| DNS / health-aware / weighted routing | first-class | `routing.dns-policy`, `routing.health-aware` |
| Async decoupling via queues/workers | first-class | `queue.ack-and-release` (guided: visibility, redelivery, DLQ) |
| Stream broker (partitions, consumer groups, offsets, replay, lag, rebalance) | first-class | `stream.partitioned-broker` |
| Broadcast fan-out (one→many over **fixed** edges) | guided | `messaging.broadcast-fanout` |
| Op-log + snapshots + **replay cost** | first-class | `logReplay` trait on `event-sourcing-store` (`replayCostPerEventMs × events`) |
| Storage profiles (distinct read/write/scan/ingest latency) | first-class | `storage.profile` |
| Reservation / lock / idempotency / commit-outcome | guided | `storage.reservation-store` (first-class), `coordination.lock-lease`, `coordination.idempotency-dedup` |
| Replica quorum, **leader promotion / failover** | guided | `resilience` domain, `replication` trait (`replicationLeaderPromotions`) |
| Retry/backoff, circuit breaker, rate limiter | first-class | `resilience.*`, `control.rate-limiter` |
| Cold start, memory pressure / OOM | first-class | `performance.cold-start`, `capacity.memory-pressure` |
| Session lifecycle / L4-vs-L7 / HTTP acks / flow-control | guided | `protocol.session` trait (LB-L4/L7, api-gateway); markers + rejection |
| Per-edge connection limit (`connection_refused`) | guided | `edge.maxConcurrentRequests` + `protocolSupportsConnectionLimits` (engine.ts) |
| ID / sequence allocation (block vs central, contention) | first-class | `id-generator` node + `idAllocation` derivation (shipped) |
| Cost / budget | guided | topology cost + budget caps |
| **Node-level concurrent-connection capacity** | **deferred** | ledger: `connection-pool limits` deferred → **GAP 1** |
| **Fan-out amplification (1 event → N from a set)** | **deferred** | broadcast is fixed-edge only → **GAP 2** |
| Exactly-once, linearizability, OT/CRDT convergence | deferred / structural-only | grade by guarded paths + justification |

## 2. Per-design mapping

### URL Shortener — fully covered (except correctly-deferred edges)
Gateway routing ✓, request-source ✓, cache-aside ✓, **ID generator** ✓ (with block/central
contention). Deferred/justify: cache stampede single-flight, read-your-write staleness,
TTL eviction. **No open gap.**

### Chat — GAP 1 + GAP 2
- Connection servers (WS, stateful, heartbeats) → **GAP 1** (no node-level connection
  capacity, no placeable WS node).
- Presence/session registry ("which server holds recipient") → key-based routing +
  in-memory-cache (presence-TTL auto-expiry not simulated — minor/justify).
- Persist-before-ACK → sync chain (ack is the response after the durable write) ✓.
- Directed pub/sub to recipient's server → key-based routing ✓ (not broadcast).
- Offline inbox + drain-on-reconnect → queue ✓; "drain on reconnect" is
  connection-state-dependent → tied to **GAP 1**.
- Push notification → `push-notification-service` palette node ✓.
- Group fan-out (write storm vs read for large groups) → **GAP 2** + content-route on a
  group-size request type.
- Per-conversation ordering → `message-ordering` (per-partition) guided ✓.
- Thundering-herd reconnect → **GAP 1** + a burst/fault.

### News Feed — GAP 2 (+ hybrid is an authoring pattern, not a gap)
- Hybrid push/pull → **content-route on request `type`** (`celebrity-post` 1% vs
  `normal-post` 99% stamped at the source) ✓ — not a gap.
- Fan-out-on-write (1 post → ~300 feed-cache writes) → **GAP 2** (amplification). The
  *storm* is observable by authoring the fan-out rate; the amplification factor is not a
  primitive.
- Social graph store, feed cache, object store + CDN, read-time merge/hydration →
  structural + reads ✓.
- Analytics (OLAP) → `presentational-only` (sink) — acceptable.

### Google Docs — GAP 1 (rest covered; OT correctness deferred)
- WS layer routing by docId → **GAP 1** node; routing itself = key-based ✓.
- Doc Session (one owner per doc, assigns order, broadcast) → key-based routing (sticky
  by docId) + `leader-election` + failover ✓. **OT transform / convergence = deferred**
  (linearizability) → justify.
- Op-log + snapshots + replay → `logReplay` ✓.
- Doc metadata/permissions → structural (security `presentational-only`).
- Optimistic local apply → client-side (justify); sub-100ms remote-apply is a gradable
  latency NFR.
- Failover (replay log onto new owner) → `logReplay` + leader promotion ✓, but needs
  **fault-injection authoring** → GAP 3.

## 3. Gap register (the honest short list)

| # | Gap | Kind | Designs | Status |
|---|---|---|---|---|
| **1** | **Connection-server node + node-level `maxConnections` capacity** | node + capacity primitive | Chat, Google Docs | **V1 implemented** → `connection-tier-capacity.md` (Connection Server palette node + derived capacity) |
| **2** | Fan-out amplification (1 event → N writes from a set/social-graph) | behavior/primitive | News Feed, Chat | **V1 implemented** → edge `fanoutFactor` (see §3.2) |
| ~~**3**~~ | ~~Fault-injection authoring UI + datastore `replicas` field~~ | authoring surface | all four (failover) | **closed** — already shipped (see §3.1) |

### 3.1 GAP 3 correction — the failover authoring surface already exists

A closer read of the engine (not a grep) shows GAP 3 was mis-registered as open. Both
pieces are shipped and the availability/failover story runs end-to-end:

- **Fault-injection UI** — `SimulationTab.tsx` › *Chaos* section: target dropdown, four
  fault modes (`blackhole` / `hang` / `reject` / `degraded`), fail-at, recover-after.
  Faults flow scenario → `topologyCanvasAdapter` → `engine.scheduleConfiguredFaults`,
  which schedules `node-failure` / `node-recovery` events. The `degraded` mode's
  `fraction` and `serviceTimeMultiplier` are now **author-editable** (previously hardcoded
  `0.3` / `10×` — a hidden dial; fixed for honesty).
- **Datastore replication** — the `replicationCapabilityModule` (config §, on `relational-db`
  + `nosql-db`) exposes enable, topology, role, replica lag, write-ack policy
  (primary/quorum), failover window, replica members, consensus, and conflict resolution —
  richer than a bare `replicas` field. Rendered generically via `getNodeConfigSections`.
- **End-to-end failover** — a fault sets the node `failed`; `replicationTrait.beforeArrival`
  then calls `cluster.fail()` + `elect()`, emitting `replicationLeaderPromotions` and a
  bounded `replica_failover_in_progress` unavailability window.

Residual (optional, not a design-coverage gap): the Chaos UI authors a **single** fault
(`faults[0]`) while the engine loops over N — cascading/multi-node fault scenarios can't be
authored from the UI yet. Each of the four designs needs only one failover fault, which is
supported today.

### 3.2 GAP 2 — fan-out amplification (V1 implemented)

An **edge-level `fanoutFactor`** (`EdgeDefinition.fanoutFactor`) makes each request
delivered over that edge amplify into N recipient deliveries. The engine expands the route
into N copies (`expandFanoutRoutes`, capped at 5000/edge) and reuses the existing branch-fork
machinery, so the downstream target genuinely receives N× the write load and can saturate —
the honest write-storm model, not a faked number. The extra deliveries are recorded on the
source node as `fanoutAmplifiedWrites` (gradable). Authoring lives on the edge properties
panel ("Fan-out factor"); use an **asynchronous** edge so the caller does not block on all N
deliveries. Ledger: `routing.fanout-amplification` = `guided`.

- **News Feed** — fan-out-on-write: post → feed-cache edge with `fanoutFactor ≈ avg followers`.
  Combine with a content-route on request `type` (`celebrity` 1% vs `normal` 99%) so only the
  push path amplifies (hybrid push/pull).
- **Chat** — group fan-out: message → connection-tier/feed edge with `fanoutFactor = group size`.

Honesty boundary: the factor is a configured constant, not derived from a live
subscriber/follower set; per-recipient routing/filtering is not modeled (each delivery is an
identical branch to the same target). Deriving N from an actual social-graph store is V2.

## 4. Correctly deferred — do NOT build

OT/CRDT convergence, exactly-once, linearizability (ledger `deferred`/`structural-only`);
cache single-flight/stampede; read-your-write staleness; presence-TTL auto-expiry; cursor
pagination; ML feed ranking; media codec/jitter. Grade these by topology + justification.

## 5. Corrections to the first-pass analysis (for the record)

An earlier pass over-claimed four gaps that are actually covered — recorded so we don't
chase them:
- "Conditional routing by entity attribute" — covered by content-routing on request `type`.
- "Single-coordinator-per-key" — covered by key-based routing + leader-election + failover
  (only the OT/CRDT *convergence* is deferred).
- "Op-log + snapshots + replay" — covered by the `logReplay` trait.
- "No connection model" — sessions and per-edge connection limits are modeled; only
  *node-level* connection capacity is missing (GAP 1).

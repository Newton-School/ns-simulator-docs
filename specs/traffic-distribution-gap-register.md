# Traffic-Distribution Gap Register - What Distributes, What's Not Modeled, Fill/Fix Plan

> **Goal.** A single source of truth for **every node that distributes requests or
> traffic** in the simulator: which nodes distribute, *how* the engine models it,
> what is **not** modeled, whether the **input already exists** to close each gap,
> and the fix. The "input exists" column is the decider - a gap whose input is
> present is a *modeling-only* fix; a gap whose input is absent needs *schema +
> modeling*.
>
> **Status.** Audit complete (2026-09-11), grounded in specific files with nothing
> assumed. Nothing built yet - this is the fill/fix backlog.
>
> **Provenance.** Distilled from a session tracing how traffic flows across Load
> Balancer / API Gateway / Distributed Cache / Pub/Sub / API Server, then widened
> to the whole catalogue. The cache's derivation work is tracked separately in
> [`derived-cache-hit-rate-model.md`](./derived-cache-hit-rate-model.md); the
> cache is *not* a distributor (it absorbs, it does not route) and appears here
> only for contrast.

---

## 1. How the engine decides a node distributes

A node's routing behaviour comes from its component spec's `routingStrategy`
(or a trait's `routingStrategyHint`), resolved in `traits/resolveTraits.ts` (L42)
and executed per request in `routing.ts` `pickSyncRoute` (~L220). There is no
single "router" flag - distribution emerges from strategy + eligible edges, which
is why even plain compute nodes distribute on their out-edges (Tier 5).

## 2. Taxonomy - the five distribution forms

**Tier 1 - Load-balancers (spread across identical backends).**
Default `routingStrategy: 'round-robin'` ([componentSpecs.ts:1063]); real
round-robin / least-conn / weighted spread.
`load-balancer`, `load-balancer-l4`, `load-balancer-l7`, `ingress-controller`,
`reverse-proxy`.

**Tier 2 - Passthrough / rule routers (route by rule, forward first eligible).**
`routingStrategy: 'passthrough'`; select among *eligible* edges. The l7 subset
also does structured `type/method/path/host` matching via `contentRouting`.
`api-gateway`, `global-traffic-manager`, `service-mesh`, `cdn`, `edge-router`,
`routing-rule`, `routing-policy`, `nat-gateway`, `vpn-gateway`, `high-perf-nic`,
`internal-dns`, `firewall`, `waf`.

**Tier 3 - Broadcast fan-out (every subscriber gets every message).**
`routingStrategyHint: 'broadcast'` via `broadcastFanout` trait
([broadcastFanout.ts:5]).
`pub-sub`, `message-broker`, `event-bus`.

**Tier 4 - Key / partition-based (route on the key, not on load).**
- `sharding`, `hashing` - key-based routing (`traits/keyBasedRouting.ts`)
- `stream` - keyed partitions + consumer groups (`traits/streamBroker.ts`)
- `search-service`, `search-index` - scatter/gather fan-out (`traits/fanoutQuery.ts`)

**Tier 5 - Implicit (any node with ≥2 sync out-edges).**
The default `pickSyncRoute` case spreads outbound traffic - **weighted** if edges
carry weights, else **uniform random** ([routing.ts:236]). So `microservice`,
`api-endpoint`, `serverless-function`, etc. are consumers inbound but distributors
outbound, even though they are not "routers."

Where the five front-of-house components land:

| Component | Tier | Distribution |
|---|---|---|
| Load Balancer | 1 | round-robin / least-conn / weighted spread |
| API Gateway | 2 | passthrough + `contentRouting` (`type/method/path/host`) |
| Distributed Cache | - | **not a distributor** - hit/miss dial (absorbs, doesn't route) |
| Pub/Sub | 3 | broadcast fan-out |
| API Server | 5 | consumer inbound; weighted/random on multiple out-edges |

---

## 3. Gap register

Legend - Modeled: ✅ full · ⚠️ partial · ❌ none. Input: ✅ present · ◑ present but
metadata-only / not first-class · ❌ absent.

### Tier 1 - Load-balancers (`load-balancer`, `-l4`, `-l7`, `ingress-controller`, `reverse-proxy`)

Source: `routing.ts` `pickSyncRoute`, `traits/healthAwareRouting.ts`,
`traits/capabilityModules.ts` (LB module ~L350).

| Gap | Modeled | Input | Fix |
|---|---|---|---|
| round-robin / weighted / random / passthrough | ✅ | ✅ `routingStrategy` | - |
| least-connections (live in-flight) | ✅ | ✅ | degrades to RR when no in-flight signal - acceptable |
| ~~**least-response-time**~~ | ✅ **(shipped 2026-09-11)** | ✅ `least-response-time` strategy + `getResponseTimeMs` | `routing.ts` `pickLeastResponseTime`: score `(in-flight+1)×meanServiceTimeMs`; `NodeState.meanServiceTimeMs` exposed from `GGcKNode` (totalServiceTime/totalCompleted), fed via engine `getResponseTimeMs`; degrades to least-conn before any completion |
| ~~**sticky sessions / IP-hash / session affinity**~~ | ✅ **(shipped 2026-09-11; consistent-hash 2026-09-11)** | ✅ `routingStrategy: 'sticky' \| 'ip-hash'` + `stickyKeyField` | `pickSticky` now places keys on a **consistent-hash ring** (64 vnodes/target via `pickOnHashRing`), so ejecting a backend reassigns only ~1/N keys (survivor keys never move - tested). Degrades to round-robin when no key |
| ~~**power-of-two-choices**~~ | ✅ **(shipped 2026-09-11)** | ✅ `p2c` strategy | `pickPowerOfTwoChoices`: sample two distinct routes, take lower in-flight; degrades to round-robin without a signal |
| health-aware pool ejection | ⚠️ | ✅ `healthCheckEnabled` | probe interval / unhealthy threshold / recovery hysteresis unmodeled (`healthAwareRouting` notModeled) - add as config |
| protocol-specific balancing heuristics | ❌ | ❌ | low priority; leave declared-not-modeled |

### Tier 2 - Passthrough / rule routers (`api-gateway`, `service-mesh`, `global-traffic-manager`, `cdn`, `edge-router`, `routing-rule/-policy`, `firewall`, `waf`, `internal-dns`, …)

Source: `traits/contentRouting.ts`, `core/requestSemantics.ts`,
`traits/dnsRoutingPolicy.ts`, `traits/capabilityModules.ts`.

| Gap | Modeled | Input | Fix |
|---|---|---|---|
| rule routing on `type / method / path / host` | ✅ (l7-lb, api-gateway, ingress) | ✅ `routingRules` | - |
| per-request `path` / `host` values | ⚠️ | ◑ read from `request.metadata` only ([requestSemantics.ts:20]) | add first-class per-request-type `path`/`host`/`method` authoring (today metadata-only, no UI/schema) |
| generic edge condition grammar | ⚠️ | ✅ `edge.condition` | `matchesCondition` supports only `request.type ==/!=`; structured matching lives in `contentRouting`, not generic edges - unify the two |
| ~~header-based routing~~ | ✅ **(shipped 2026-09-11)** | ✅ `header` match field + `matchKey` + `metadata.headers` | `header` added to `REQUEST_MATCH_FIELDS`; case-insensitive lookup in `requestFieldValue`; rule carries `matchKey` (header name). Header *transforms/rewrites* still not modeled |
| ~~regex / prefix matching~~ | ✅ **(shipped 2026-09-11)** | ✅ `matchOperator` (`equals`/`prefix`/`regex`) | `requestFieldMatches` takes an operator; invalid regex fails closed. Wired through rule schema, both validators, and the UI editor |
| SSL termination overhead | ❌ | ❌ | model as fixed per-request cost on l7 nodes (compose with existing latency) |
| DNS recursive resolution / zone transfers | ❌ | ✅ `dnsRoutingPolicy`, `dnsGeoTargets`, `dnsCacheTtlSeconds` | policy/geo/ttl modeled; resolution-chain cost unmodeled - likely leave declared |
| firewall / waf IP-CIDR routing, rule sets | ❌ | ❌ | add CIDR match; rule-set eval cost as latency |
| service-registry registration / heartbeats / deregistration | ❌ | ❌ | out of scope for routing; note as separate capability |

### Tier 3 - Broadcast fan-out (`pub-sub`, `message-broker`, `event-bus`)

Source: `traits/broadcastFanout.ts` (reads **no config**), `traits/consumerLag.ts`,
`traits/ackAndRelease.ts`.

| Gap | Modeled | Input | Fix |
|---|---|---|---|
| fan-out to every eligible subscriber edge | ✅ | n/a | - |
| **subscription filters** (topic/type filtering) | ❌ | ❌ | per-edge `subscriptionFilter` reusing `REQUEST_MATCH_FIELDS` |
| ~~**consumer groups / competing consumers**~~ | ✅ **(shipped 2026-09-11)** | ✅ `consumerGroupMode` (broker) + `consumerGroup` (subscriber) | `broadcastFanout.filterRoutes` groups candidates by `consumerGroup`, delivers one per group + one competing member within (`hash(group:__key)`). Also **fixed a latent gap**: `consumerGroupMode`/`consumerGroup` were read by the engine but never serialized from canvas - now wired through the allowlist, so `stream`'s consumer groups work from the UI too. New `consumerGroupMembership` module surfaces the subscriber field |
| delivery guarantees (at-least / exactly-once) | ❌ | ❌ | add `deliveryGuarantee` enum; drives dedup/retry interaction |
| consumer-group rebalancing / offset commits | ⚠️ | ❌ | `consumerLag` declares these notModeled; unify with `streamBroker` semantics |

### Tier 4 - Key / partition routers (`sharding`, `hashing`, `stream`, `search-service`, `search-index`)

Source: `traits/keyBasedRouting.ts`, `traits/streamBroker.ts`,
`traits/fanoutQuery.ts`.

| Gap | Modeled | Input | Fix |
|---|---|---|---|
| key → partition (`hash(key) % N`) | ✅ | ✅ `routingKeyField` / `partitionKeyField` | - |
| stream partitions + consumer groups + offsets + retention | ✅ | ✅ `partitionCount`, `consumerGroup(Mode)`, `retentionMs` | - |
| ~~**consistent hashing** (vs modulo)~~ | ✅ **(2026-09-11)** | ✅ | `pickOnHashRing` (64 vnodes, MurmurHash3-finalized hash) in `core/hashRing.ts` (leaf module, no import cycle) backs `sticky`/`ip-hash` **and** `sharding`/`hashing` (`keyBasedRouting`). Ejecting a shard reassigns only ~1/N keys (tested). **`stream` partitioner intentionally stays modulo** - matches real Kafka (fixed partition count, repartition reshuffles) |
| ring rebalancing cost / virtual-node skew | ◑ | - | ring + vnodes now modeled (even spread); the **data-movement cost/time** of a rebalance is still declared-not-modeled |
| **per-key access skew** (hot partitions) | ✅ **(shipped 2026-09-11)** | ✅ `keyspace.skew` | Zipf draw landed in `workload.ts`; partition assignment already keys off the drawn key, so hot partitions now emerge. Remaining: surface/exploit in partition metrics |
| scatter/gather: true parallel dispatch, partial results, hedging | ⚠️ | ✅ `shardCount`, `perShardLatencyMs` | `fanoutQuery` sums shards; add max-of (parallel) + hedge/partial options |
| multi-broker replication across machines | ❌ | ❌ | `streamBroker` notModeled; compose with `replication` trait |

### Tier 5 - Implicit (any node with ≥2 sync out-edges: `microservice`, `api-endpoint`, `serverless-function`, …)

Source: `routing.ts` default case (~L236).

| Gap | Modeled | Input | Fix |
|---|---|---|---|
| weighted (if edge weights) else uniform random | ✅ | ✅ `edge.weight` | - |
| RR / least-conn on a *non-router* node's out-edges | ⚠️ | ✅ `config.routingStrategy` is read for **any** node ([routing.ts:123]) | mechanism exists; not surfaced in the properties UI for non-routers - expose it |

---

## 4. Priority ordering (recommended)

1. ✅ **`keyspace.skew` Zipf draw - SHIPPED (2026-09-11).** `core/types.ts` +
   `validation/validator.ts` + `workload.ts` (`drawZipfIndex`/`getZipfTable`,
   cached CDF + binary search), tests in `workload.test.ts`, full suite green.
   Unblocks the cache derivation (cache spec §4) *and* Tier-4 hot-partition skew;
   makes reservation/contention realistic. The remaining tiers can now build on a
   skewable keyspace.
2. ✅ **Sticky sessions / IP-hash - SHIPPED (2026-09-11).** `routing.ts`
   `pickSticky` + `hashString`, `sticky`/`ip-hash` strategies and `stickyKeyField`
   config wired through `nodeSpecTypes.ts`, `capabilityModules.ts` (UI options +
   field), `componentSpecs.ts` (allowlist), `topologyCanvasAdapter.ts` (round-trip
   + `asRoutingStrategy`), and the preview (`routingStrategyVisualization.ts`,
   toast, `PropertiesForm.tsx`). Tests in `routing.test.ts` (846 total green).
   Uses modulo over an id-sorted pool → consistent hashing (Tier 4, #5) is the
   natural follow-up so membership changes don't remap every session.
3. ✅ **Consumer groups on `message-broker`/`pub-sub` - SHIPPED (2026-09-11).**
   `broadcastFanout.filterRoutes` (one delivery per group, one competing member
   within, keyed on `hash(group:__key)`); `consumerGroupMode` + subscriber
   `consumerGroup` wired through `nodeSpecTypes` / `componentSpecs` allowlist /
   `topologyCanvasAdapter`; new `consumerGroupMembership` module for the
   subscriber field. Side-fix: the same wiring was missing for `stream`, so its
   consumer groups now work from the canvas too. Tests in
   `broadcastFanout.test.ts` + a `routing.test.ts` integration case (854 green).
   **Note:** other stream fields (`streamBrokerEnabled`, `partitionCount`, …)
   are still canvas-unserialized - a separate wiring gap, not part of #3.
4. ✅ **Header match + match operators - SHIPPED (2026-09-11).** `header` field +
   `matchKey` (case-insensitive header lookup) and `matchOperator`
   (`equals`/`prefix`/`regex`, invalid regex fails closed) in
   `core/requestSemantics.ts`; rule schema, `contentRouting` trait, both
   validators (`validator.ts` + `componentSpecs.ts`), and the
   `RoutingRulesEditor` UI. Tests across requestSemantics/contentRouting/validator
   (862 green). Still not modeled: header transforms/rewrites, SSL termination.
5. ✅ **least-response-time / P2C / consistent hashing - SHIPPED (2026-09-11).**
   `routing.ts`: `pickLeastResponseTime` (score `(in-flight+1)×meanServiceTimeMs`,
   new `NodeState.meanServiceTimeMs` + engine `getResponseTimeMs`),
   `pickPowerOfTwoChoices` (sample-two, lower-load), and `pickOnHashRing` (64
   vnodes) now backing `sticky`/`ip-hash` so pool changes reassign only ~1/N keys.
   Strategies wired through the type, LB options, adapter, and preview. Tests in
   `routing.test.ts` (866 green). Consistent hashing for `sharding`/`hashing`/
   `stream` partitioning is the remaining follow-up (reuse `pickOnHashRing`).

**All five register priorities are now shipped.** Everything else (SSL cost, DNS
resolution chains, multi-broker replication, service-registry lifecycle, header
transforms) stays **declared-not-modeled** - honest and low value for the teaching
goal. **Update (2026-09-11):** consistent hashing for Tier-4 key routers is **done** - `pickOnHashRing` extracted to `core/hashRing.ts` (with a MurmurHash3 avalanche
finalizer so sequential keys spread) and applied to `sharding`/`hashing` as well
as LB affinity; `stream` partitioning stays modulo by design (Kafka-accurate).

**Update (2026-09-11):** the `stream` broker canvas-serialization gap is **closed** - `streamBrokerEnabled`, `partitionCount`, `partitionKeyField`, `retentionMs`,
`streamReplayIntervalMs`, `brokerFailureAtMs`, `brokerRecoveryAtMs` now flow
canvas→engine through the `componentSpecs` allowlist and back via
`topologyCanvasAdapter` (round-trip tested both directions). `consumerGroupMode`/
`consumerGroup` were wired in #3. The stream broker's UI is now fully functional
from the canvas, not just from hand-written topology JSON.

**No open follow-ups remain in this register.**

---

## 5. Files touched (per fix, when scheduled)

- **Tier 1** - `src/engine/routing.ts` (new strategies, P2C, session key),
  `src/engine/traits/healthAwareRouting.ts`, LB module in
  `src/engine/traits/capabilityModules.ts`
- **Tier 2** - `src/engine/traits/contentRouting.ts`,
  `src/engine/core/requestSemantics.ts` (header field, match operators),
  request-type authoring in `src/engine/workload.ts` +
  `src/engine/validation/validator.ts`
- **Tier 3** - `src/engine/traits/broadcastFanout.ts`,
  `src/engine/traits/consumerLag.ts`, port from `src/engine/traits/streamBroker.ts`
- **Tier 4** - `src/engine/traits/keyBasedRouting.ts` (consistent hashing),
  `src/engine/traits/fanoutQuery.ts` (parallel/hedge), shared `workload.ts` Zipf
  draw
- **Tier 5** - surface `routingStrategy` in the properties UI for non-router nodes

## 6. Related

- [`derived-cache-hit-rate-model.md`](./derived-cache-hit-rate-model.md) - the
  cache is not a distributor; its hit-rate derivation shares the `keyspace.skew`
  Zipf work in priority #1.

# Connection tier — a stateful connection-server node with connection-count capacity

> Status: V1 implemented (GAP 1 in `system-design-coverage-gaps.md`). A **Connection
> Server** palette node (Network category, backed by `api-gateway`) now carries a
> derived `sim.connection` capacity model: fleet capacity, utilization, refused overflow,
> required instances, and heartbeat load. Runtime heartbeat-arrival injection and a
> dedicated `websockets-gateway` spec remain V2.
>
> Purpose: model the **persistent-connection tier** that stateful real-time systems
> need — the WebSocket/connection servers in Chat and the WS layer in Google Docs — by
> adding a placeable connection-server node whose capacity is measured in **concurrent
> held connections**, a dimension the engine does not model today.

## 1. The gap, precisely

The engine already models the *pieces* around connections but not the tier itself:

- **Sessions & lifecycle:** the `protocol.session` trait (`load-balancer-l4/l7`,
  `api-gateway`) marks sessions opened/closed, WebSocket/HTTP2/TCP protocols, L7
  rejection, and stream flow-control. But it is **per-arriving-request** — it counts
  `protocolSessionsOpened`, it does not model a *persistently held* connection.
- **Per-edge connection limit:** `edge.maxConcurrentRequests` +
  `protocolSupportsConnectionLimits` make the engine emit `connection_refused` when an
  edge's in-flight count is exceeded. That is a per-edge pool of *in-flight requests*,
  not a node holding N long-lived sessions.
- **What is missing (ledger: `connection-pool limits` = deferred):** a **node** whose
  capacity is *concurrent held connections* (e.g. "65K WebSockets per host"), that
  saturates and refuses new connections past that ceiling, and whose fleet size is
  derived from `total connections ÷ per-server capacity`. And `websockets-gateway` is a
  dead `ComponentType` with **no palette template**, so no such node is placeable.

Result: the canonical "10M concurrent connections → ~150–300 connection servers at
65K/host" reasoning has nowhere to live, and its bottleneck (a connection blip causing a
thundering-herd reconnect that exceeds capacity) cannot be shown.

## 2. Model — connection count as a held-capacity dimension (V1)

Model concurrent connections the way storage models GB: a **steady-state held capacity**,
distinct from request throughput (RPS). This matches how the design itself reasons
("10M connections → N servers") and avoids full per-connection lifecycle event
machinery.

### 2.1 The node

A new placeable palette node **Connection Server** (a.k.a. WebSocket Gateway):

- **V1 backing: `componentType: 'api-gateway'`** — the api-gateway already carries the
  `protocol.session` trait (WebSocket/TCP session lifecycle + flow-control), so it is the
  honest home for a connection front-door, and this avoids reviving the fully-dead
  `websockets-gateway` type (no spec/cost/resources → the ~10-site new-ComponentType
  risk). The connection *capacity* is added as a derived `sim.connection` block, gated on
  its presence (same pattern as `idAllocation`). A dedicated `websockets-gateway` spec is
  a clean V2 refinement.
- Presented in the palette as its own node ("Connection Server").
- It still processes per-request message traffic as a normal G/G/c/K node (sends,
  receipts, cursor updates flow as requests over the held connections).

### 2.2 Capacity config

```ts
sim.connection = {
  /** Concurrent held connections one instance can sustain (e.g. 65_000). */
  maxConnectionsPerInstance: number
  /** Steady-state offered concurrent connections this tier must hold. */
  offeredConnections: number
  /** Optional: keepalive traffic each held connection generates. */
  heartbeatIntervalMs?: number      // e.g. 30_000 → adds background RPS
  sessionProtocol?: 'websocket' | 'tcp' | 'http2'
}
```

`instanceCount` (from the existing instance model) multiplies capacity:
`fleetCapacity = maxConnectionsPerInstance × instanceCount`.

### 2.3 Behavior (what simulates)

1. **Connection admission / saturation.** If `offeredConnections > fleetCapacity`, the
   overflow is **refused** (`connection_refused`), exactly like the existing per-edge
   limit but at node scope. Connection utilization = `offeredConnections / fleetCapacity`
   (time-weighted, per the no-point-sampled-scalars rule).
2. **Heartbeat background load.** Held connections generate keepalive requests at
   `offeredConnections / heartbeatIntervalMs` RPS, added to the node's request load — so
   a large connection count costs CPU/RPS even when idle (the real reason connection
   servers are their own tier).
3. **Fleet sizing (derived, like the instance model).** Required instances =
   `ceil(offeredConnections / maxConnectionsPerInstance)`; surfaced as a derived hint and
   in cost. This is the "10M ÷ 65K → ~154 servers" calculation, made live.
4. **Thundering-herd (with a fault).** A connection blip (fault on the tier) drops held
   connections; on recovery they reconnect. If reconnects arrive faster than
   `fleetCapacity` allows, the excess is refused — the modeled thundering herd. (Requires
   GAP 3 fault authoring to trigger; the capacity math is here.)

### 2.4 Metrics

- `concurrentConnections` (time-weighted), `connectionUtilization`,
  `connectionsRefused`, derived `requiredInstances`.
- Reuses existing cost so a connection tier has a real \$/hr from its instance count.

## 3. What it does NOT model (honesty boundaries)

- **Per-connection lifecycle events** (individual connect/hold/disconnect over time).
  V1 treats connection count as a steady-state number, not a dynamic queue of long-lived
  occupants. Full lifecycle is a V2 (see §5).
- **Exact reconnect dynamics** beyond the capacity check — jittered-backoff *policy*
  correctness stays justification.
- **Presence semantics / message routing** — those remain the key-based routing +
  in-memory-cache story; this node is only the connection capacity front door.

## 4. Why a node (not a trait) and why a new capacity dimension

Per the node-vs-property doctrine (`custom-node-and-service-definition-spec.md`): a
connection server *is* a distinct deployable box with a capacity dimension no existing
node has (held connections ≠ RPS). It recurs in two designs. That clears the bar for a
new node. The capacity dimension is genuinely new — it is a *held* resource over time,
the connection analogue of storage GB — so it warrants a first-class `sim.connection`
block rather than being faked with RPS.

## 5. Deferred to V2

- Full per-connection lifecycle (connect/hold/disconnect events; connection duration
  distributions; graceful-reconnect modeling).
- Sticky session affinity to a specific instance across reconnects.
- Backpressure/flow-control interplay with the existing `protocol.session` window.

## 6. Registration sites (when implemented)

- `src/engine/core/types.ts` — `sim.connection` on the config; `websockets-gateway`
  already in the `ComponentType` union.
- `src/engine/catalog/componentSpecs.ts` — a real spec for `websockets-gateway`
  (default sim config, cost).
- `src/engine/catalog/paletteTemplates.ts` — a `connection-server` palette template.
- A capacity/admission trait (connection saturation + heartbeat load + derived fleet).
- `src/renderer/src/config/{catalogConfig,nodeRegistry,libraryInfo}.ts` — palette
  surfacing; `componentLibraryVisibility.ts` if it should be in the default set.
- A properties-panel **Connection capacity** section (`maxConnectionsPerInstance`,
  `offeredConnections`, `heartbeatIntervalMs`, `sessionProtocol`).
- `supportLedger.ts` — move `connection-pool limits` from `deferred` to `guided` once
  shipped.

## 7. Acceptance criteria

- A Connection Server node is placeable from the palette.
- Setting `offeredConnections > maxConnectionsPerInstance × instanceCount` produces a
  non-zero `connectionsRefused` and a connection utilization > 100% signal.
- A healthy tier shows connection utilization < 100%, a derived required-instance count,
  and heartbeat background RPS proportional to connection count.
- Existing topologies without a connection node are unchanged.
- The ledger entry for connection capacity is updated to `guided`.

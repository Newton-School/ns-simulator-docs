# Chat Application — Test-Case Rows (complete)

Every gradeable row for the Chat question, one **atomic** assertion per row. Follows
`specs/test-case-catalog.md`. Each `input` is pure JSON and parses as-is.

> **How learner nodes match:** by resolved `componentType`, never label. Note the two
> traps specific to this design: the **Connection Server** palette node resolves to
> `api-gateway` (it is backed by api-gateway + a `sim.connection` block), and the
> **Message Service** is a `microservice`. Grade the connection tier as `api-gateway`.

Design under test: `examples/chat/builder-walkthrough.md` (persist-before-ACK durability;
online delivery via Pub/Sub; offline via inbox + push; group fan-out amplification).

---

## 0 · Setup — `SIMULATOR_CONFIG`

Injects a message stream split into direct vs group sends (group drives fan-out).

```json
{
  "type": "SIMULATOR_CONFIG",
  "difficulty": "advanced",
  "workloadCategory": "write-heavy",
  "constraints": { "maxNodeCount": 14 },
  "suite": {
    "name": "chat-suite",
    "cases": [
      {
        "id": "peak",
        "description": "WebSocket client->server frame mix (SEND / ACK / TYPING / PRESENCE)",
        "workload": {
          "baseRps": 4000,
          "requestDistribution": [
            { "type": "send-direct", "weight": 0.35, "sizeBytes": 1024 },
            { "type": "send-group",  "weight": 0.15, "sizeBytes": 1024 },
            { "type": "ack",         "weight": 0.30, "sizeBytes": 128 },
            { "type": "typing",      "weight": 0.12, "sizeBytes": 64 },
            { "type": "presence",    "weight": 0.08, "sizeBytes": 64 }
          ]
        }
      }
    ]
  }
}
```
**What it does:** injects ~4,000 frames/s as the real WebSocket client→server frame mix —
`send-direct` / `send-group` (SEND), `ack` (ACK), `typing`, `presence`. The 15% `send-group`
slice drives the fan-out edge; server→client frames (MESSAGE/RECEIPT) are produced by the
topology, not injected. Types are free-text request classes (they match the walkthrough's
frame mapping); the transport (WebSocket) is set on the edge/connection tier, not here.

---

## 1 · Topology — `STRUCTURAL_RULE`

**1.1 single-source** — one sender faucet.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_single_source" }
```

**1.2 connected-graph** — no orphans.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_connected_graph" }
```

**1.3 has a connection tier** — the stateful WebSocket gateway (resolves to api-gateway).
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "api-gateway", "minCount": 1 }
```

**1.4 has a durable message store** — Cassandra-class store present.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "nosql-db", "minCount": 1 }
```

**1.5 has a pub/sub bus** — a one-to-many broker for online routing.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "pub-sub", "minCount": 1 }
```

**1.6 has an offline queue** — per-user store-and-forward inbox.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "queue", "minCount": 1 }
```

**1.7 has a push provider** — the offline notification handoff to APNs/FCM.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "third-party-api-connector", "minCount": 1 }
```
> The push tier is an external provider call. The canonical build uses the **External Service**
> tile (`third-party-api-connector`; external-call latency + `externalCalls`); the upgraded
> **Notification Service** node (`push-notification-service`) is an equally valid alternative.
> To accept either, grade the presence of the **async handoff edge** (1.9) rather than a single
> component type, since a `STRUCTURAL_RULE` can't express an accept-set. See
> [`../patterns/notifications.md`](../patterns/notifications.md).

**1.8 persist path exists** — the message service reaches the durable store.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_path", "fromType": "microservice", "toType": "nosql-db" }
```

**1.9 offline handoff is async** — the inbox → push-provider edge is asynchronous.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "queue", "toType": "third-party-api-connector", "mode": "asynchronous" }
```

---

## 2 · Component choice — `SEMANTIC_CRITERION`

**2.1 message store fits high-write append (the trap, `hardFail`)** — Cassandra/NoSQL for
100K writes/s append-ordered by conversation; a single relational primary can't absorb it.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "storageFit",
  "accessPattern": "append-only-ledger",
  "accept": [ "nosql-db" ],
  "partial": [ "kv-store" ],
  "antiPattern": [ "relational-db" ],
  "points": 3,
  "hardFail": true
}
```

**2.2 online delivery uses a fan-out broker, not a work queue** — pub/sub delivers to the
recipient's server; a single-consumer queue is the wrong primitive for delivery routing.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "fanout",
  "broker": "pub-sub",
  "minConsumers": 2,
  "forbiddenBroker": "queue",
  "points": 3
}
```

**2.3 pub/sub sits between the connection tier and the recipient** — the bus is on the
delivery path, not dangling.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "placement",
  "componentType": "pub-sub",
  "between": [ "api-gateway", "api-gateway" ],
  "points": 2
}
```

---

## 3 · Behavior under load — `RUBRIC_CHECK`

**3.1 sub-second delivery p95** — online end-to-end latency stays low.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.latency.p95", "op": "<", "value": 1000, "points": 3 }
```

**3.2 error rate < 2%** — accepted messages are not dropped.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.errorRate", "op": "<", "value": 0.02, "points": 2 }
```

**3.3 connection tier not saturated** — the busiest node is under 90% (fleet sized for the
held connections / message load).
```json
{ "type": "RUBRIC_CHECK", "metric": "perNode.maxUtilization", "op": "<", "value": 0.9, "points": 2 }
```

**3.4 WebSocket sessions actually opened** — the connection tier is doing session work
(protocol counter proves the stateful tier is exercised).
```json
{ "type": "RUBRIC_CHECK", "metric": "perNode.connection-servers.traitCounters.protocolSessionsOpened", "op": ">", "value": 0, "points": 1 }
```
> Replace `connection-servers` with the Connection Server node's id. If your build doesn't
> expose this counter, drop this row and rely on 3.3.

**3.5 no invariant violations** — physically consistent run.
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
```

**3.6 conservation holds** — no messages vanish (fan-out branches accounted for).
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "conservation.unbalanced", "op": "==", "value": 0, "points": 1 }
```

---

## Coverage map

| Design decision | Row(s) |
|---|---|
| Stateful WebSocket connection tier | 1.3, 3.3, 3.4 |
| Cassandra for append-ordered history (not RDBMS) | 1.4, 2.1 (hardFail) |
| Persist-before-ACK durability (sync chain) | 1.8, 3.1, 3.6 |
| Online delivery via pub/sub (not a queue) | 1.5, 2.2, 2.3 |
| Offline inbox + async push | 1.6, 1.7, 1.9 |
| Group fan-out doesn't break the tier | 3.2, 3.3 |
| Healthy, consistent run | 3.5, 3.6 |

**Still justification (no row):** presence-TTL auto-expiry, exactly-once / cross-device
dedupe (per-conversation sequence numbers), thundering-herd reconnect (needs a fault),
group fan-out amplification factor (`fanoutFactor` is measured as recipient load but the
`fanoutAmplifiedWrites` counter is not yet a first-class rubric metric — grade its effect
via 3.3).

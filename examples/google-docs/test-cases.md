# Google Docs — Test-Case Rows (complete)

Every gradeable row for the Collaborative Editor question, one **atomic** assertion per
row. Follows `specs/test-case-catalog.md`. Each `input` is pure JSON and parses as-is.

> **How learner nodes match:** by resolved `componentType`. The **WS Layer** (Connection
> Server) resolves to `api-gateway`; the **Session Server** is a `microservice`; the
> **Op Log** and **Doc Metadata** are `nosql-db` (or the op log is an `event-sourcing-store`
> if that palette node is used). Correctness of OT/CRDT convergence is **not** gradeable —
> it is a `justify` decision; these rows grade the *ordering path* and durability around it.

Design under test: `examples/google-docs/builder-walkthrough.md` (one session owner per
doc via key-based routing; append-only op log as source of truth; failover by replay).

---

## 0 · Setup — `SIMULATOR_CONFIG`

Injects a keystroke-level op stream spread across many docs (drives per-doc routing).

```json
{
  "type": "SIMULATOR_CONFIG",
  "difficulty": "advanced",
  "workloadCategory": "correctness-heavy",
  "constraints": { "maxNodeCount": 12 },
  "suite": {
    "name": "google-docs-suite",
    "cases": [
      {
        "id": "edit-stream",
        "description": "Keystroke-level ops across many docs",
        "workload": {
          "baseRps": 3000,
          "requestDistribution": [
            { "type": "op",     "weight": 0.9, "sizeBytes": 128 },
            { "type": "cursor", "weight": 0.1, "sizeBytes": 64 }
          ]
        }
      }
    ]
  }
}
```
**What it does:** ~3,000 tiny ops/s as the WebSocket client→server frame mix — `op` (OP,
90%) and `cursor` (CURSOR, 10%) — so the WS layer and per-doc session routing are exercised.
Server→client frames (OP broadcast / CURSOR / ACK) are produced by the topology, not injected.
Types are free-text request classes matching the walkthrough; transport is set on the edge.

---

## 1 · Topology — `STRUCTURAL_RULE`

**1.1 single-source** — one editor faucet.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_single_source" }
```

**1.2 connected-graph** — no orphans.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_connected_graph" }
```

**1.3 has a WS/connection layer** — the persistent low-latency channel (resolves to api-gateway).
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "api-gateway", "minCount": 1 }
```

**1.4 has a session/collaboration server** — the per-doc owner.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "microservice", "minCount": 1 }
```

**1.5 has a durable op-log store** — append-only source of truth.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "nosql-db", "minCount": 1 }
```

**1.6 WS layer routes to the session server** — direct edge exists.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "api-gateway", "toType": "microservice" }
```

**1.7 session server persists to the op log (sync)** — the ordered op is appended durably before ACK.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "microservice", "toType": "nosql-db", "mode": "synchronous" }
```

**1.8 op-log store is replicated** — a replica exists so an owner can fail over.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_redundancy", "componentType": "nosql-db", "minReplicas": 2 }
```

**1.9 lean graph** — at most 12 nodes (per-doc concurrency is tiny; don't over-build).
```json
{ "type": "STRUCTURAL_RULE", "kind": "max_node_count", "count": 12 }
```

---

## 2 · Component choice — `SEMANTIC_CRITERION`

**2.1 op log fits an append-only ledger (the trap, `hardFail`)** — an ordered append-only
log is the source of truth; an in-memory cache as the log loses durability + history.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "storageFit",
  "accessPattern": "append-only-ledger",
  "accept": [ "nosql-db", "event-sourcing-store", "relational-db" ],
  "antiPattern": [ "in-memory-cache" ],
  "points": 3,
  "hardFail": true
}
```

**2.2 op log sits between the session server and nothing downstream that bypasses it** —
every op reaches the durable log (the log is on the write path).
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "guardedPath",
  "from": "api-gateway",
  "guard": "nosql-db",
  "points": 3,
  "hardFail": true
}
```
> `guardedPath` here asserts every op path from the WS layer reaches the durable log (the
> guard); omit `to` so it only requires the guard is always traversed.

---

## 3 · Behavior under load — `RUBRIC_CHECK`

**3.1 op round-trip p95 < 100 ms** — remote edits appear within the latency NFR.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.latency.p95", "op": "<", "value": 100, "points": 3 }
```

**3.2 error rate < 1%** — no acknowledged op is lost.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.errorRate", "op": "<", "value": 0.01, "points": 2 }
```

**3.3 session server not saturated** — the single per-doc owner isn't a bottleneck at this scale.
```json
{ "type": "RUBRIC_CHECK", "metric": "perNode.maxUtilization", "op": "<", "value": 0.9, "points": 2 }
```

**3.4 no invariant violations** — physically consistent op stream.
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
```

**3.5 conservation holds** — no ops vanish (every op appended or rejected, never dropped).
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "conservation.unbalanced", "op": "==", "value": 0, "points": 1 }
```

**3.6 failover promotes a new leader** — under a fault on the op-log leader, a replica is
promoted (the "replay the log onto a new owner" recovery).
```json
{ "type": "RUBRIC_CHECK", "metric": "perNode.op-log.traitCounters.replicationLeaderPromotions", "op": ">", "value": 0, "points": 2 }
```
> Requires a fault on the op-log leader in the suite (Chaos). Replace `op-log` with the
> op-log node's id. Drop this row if the case injects no fault.

---

## Coverage map

| Design decision | Row(s) |
|---|---|
| Persistent WS/connection layer | 1.3, 1.6 |
| One session owner per doc (routing) | 1.4, 1.6, 3.3 |
| Append-only op log as source of truth | 1.5, 2.1 (hardFail), 2.2 (hardFail) |
| Persist-before-ACK (sync append) | 1.7, 3.2, 3.5 |
| Failover by replaying the log onto a new owner | 1.8, 3.6 |
| Meets the sub-100ms remote-apply NFR | 3.1 |
| Healthy, conserved run | 3.4, 3.5 |

**Still justification (no row):** OT/CRDT **convergence** correctness (the deferred core —
graded by `justify`), optimistic local apply, op-log **replay cost** (measured only with an
`event-sourcing-store` + `logReplay`; a plain NoSQL DB leaves it as justification), snapshot
cadence / GC of old ops.

# URL Shortener — Test-Case Rows (complete)

Every gradeable row for the URL-shortener question, one **atomic** assertion per row.
Rows follow `specs/test-case-catalog.md` (the four row types: `SIMULATOR_CONFIG`,
`STRUCTURAL_RULE`, `SEMANTIC_CRITERION`, `RUBRIC_CHECK`). Each `input` is pure JSON and
parses as-is in the Newton builder.

> **How learner nodes match:** every targeting key (`componentType`, `accept[]`,
> `fromType`…) matches a node by its **resolved `componentType`**, never by label or
> builder contract. A Service-Builder "Redirect Service" is a `microservice`; the
> ID Generator is a `microservice`; "Redis" is an `in-memory-cache`. Grade by shape,
> store choice, and measured behavior — not names.

Design under test: `examples/url-shortener/builder-walkthrough.md` (read path
Redirect → Redis → KV isolated from the write path; analytics fully async).

---

## 0 · Setup — `SIMULATOR_CONFIG` (one row, listed first)

Boots the sandbox and injects the read-heavy workload every `RUBRIC_CHECK` runs against.

```json
{
  "type": "SIMULATOR_CONFIG",
  "difficulty": "intermediate",
  "workloadCategory": "read-heavy",
  "constraints": { "maxNodeCount": 12 },
  "suite": {
    "name": "url-shortener-suite",
    "cases": [
      {
        "id": "peak",
        "description": "Read-heavy peak, 99:1 read:write",
        "workload": {
          "baseRps": 4000,
          "requestDistribution": [
            { "type": "read",  "weight": 0.99, "sizeBytes": 256 },
            { "type": "write", "weight": 0.01, "sizeBytes": 512 }
          ]
        }
      }
    ]
  }
}
```
**What it does:** injects ~4,000 rps at 99% GET / 1% POST so the read path is the thing
under load; caps the graph at 12 nodes (anti-kitchen-sink).

---

## 1 · Topology — `STRUCTURAL_RULE` (shape of the graph)

**1.1 single-source** — exactly one traffic faucet.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_single_source" }
```

**1.2 connected-graph** — no orphan nodes.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_connected_graph" }
```

**1.3 has a gateway/router** — a content-routing front door exists (reads vs writes split).
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "api-gateway", "minCount": 1 }
```

**1.4 has a durable store** — at least one storage-and-data node.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_category", "category": "storage-and-data", "minCount": 1 }
```

**1.5 has a cache** — the hot-set cache is present.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "in-memory-cache", "minCount": 1 }
```

**1.6 write path reaches the store** — a directed path from a service to the KV store.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_path", "fromType": "microservice", "toType": "nosql-db" }
```

**1.7 cache falls through to the store** — the cache has a downstream edge (misses have somewhere to go).
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "in-memory-cache", "toType": "nosql-db" }
```

**1.8 analytics is async** — the click-event edge to analytics is asynchronous (off the read path).
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "microservice", "toType": "data-warehouse", "mode": "asynchronous" }
```

**1.9 anti-kitchen-sink ceiling** — at most 12 total nodes.
```json
{ "type": "STRUCTURAL_RULE", "kind": "max_node_count", "count": 12 }
```

---

## 2 · Component choice — `SEMANTIC_CRITERION` (the right kind of node)

**2.1 store fits a point-lookup (the key trap, `hardFail`)** — the short_key→long_url
lookup is a get-by-key; a relational DB here zeroes the question.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "storageFit",
  "accessPattern": "point-lookup",
  "accept": [ "kv-store", "nosql-db" ],
  "partial": [ "in-memory-cache" ],
  "antiPattern": [ "relational-db" ],
  "points": 3,
  "hardFail": true
}
```

**2.2 cache is placed between the service and the store** — not dangling; it's inline on
the read path (this is what makes cache-aside real).
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "placement",
  "componentType": "in-memory-cache",
  "between": [ "microservice", "nosql-db" ],
  "points": 2
}
```

---

## 3 · Behavior under load — `RUBRIC_CHECK` (runs the sim)

**3.1 redirect p99 < 100 ms** — the core NFR (cache offload must keep the tail low).
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.latency.p99", "op": "<", "value": 100, "points": 3 }
```

**3.2 error rate < 1%** — the read path stays healthy at peak.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.errorRate", "op": "<", "value": 0.01, "points": 2 }
```

**3.3 no node pinned at capacity** — the busiest node is under 90% (KV isn't saturated → cache is working).
```json
{ "type": "RUBRIC_CHECK", "metric": "perNode.maxUtilization", "op": "<", "value": 0.9, "points": 2 }
```

**3.4 sustains throughput** — completions keep up with the offered read load.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.throughput", "op": ">=", "value": 3600, "points": 1 }
```

**3.5 no invariant violations** — no physically-impossible states.
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
```

**3.6 conservation holds** — no requests vanish (in == out + rejected at every node).
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "conservation.unbalanced", "op": "==", "value": 0, "points": 1 }
```

---

## Coverage map (what each row defends)

| Design decision (from the walkthrough) | Row(s) |
|---|---|
| KV store for O(1) point lookups (not RDBMS) | 2.1 (hardFail), 1.4, 1.6 |
| Cache-aside read path (Redis in front of KV) | 1.5, 1.7, 2.2, 3.1, 3.3 |
| Reads/writes split at a gateway | 1.3 |
| Analytics fully async (off click path) | 1.8 |
| Read path meets the latency NFR | 3.1, 3.4 |
| Healthy, bounded, physically-consistent run | 3.2, 3.5, 3.6 |

**Still justification (no row — graded by the `justify` prompt):** short-code generation /
collision handling (base62), 301 vs 302, read-your-write staleness, cache single-flight /
stampede, KV replication under fault.

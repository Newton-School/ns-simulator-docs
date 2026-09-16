# Instagram / News Feed — Test-Case Rows (complete)

Every gradeable row for the News Feed question, one **atomic** assertion per row. Follows
`specs/test-case-catalog.md`. Each `input` is pure JSON and parses as-is.

> **How learner nodes match:** by resolved `componentType`. Post/Fan-out/Feed services are
> all `microservice`; the feed cache is `in-memory-cache`; media store is `object-storage`;
> the social graph is `graph-db`; post metadata is `nosql-db`. Structural rules can't tell
> the three services apart by role — assert them by count + edges/paths.

Design under test: `examples/news-feed/builder-walkthrough.md` (hybrid fan-out: normal
authors pushed into feed caches, celebrity posts pulled & merged at read time; media on CDN).

---

## 0 · Setup — `SIMULATOR_CONFIG`

Two workload shapes matter: the write mix (normal vs celebrity) and the dominant read load.

```json
{
  "type": "SIMULATOR_CONFIG",
  "difficulty": "advanced",
  "workloadCategory": "read-heavy",
  "constraints": { "maxNodeCount": 14 },
  "suite": {
    "name": "news-feed-suite",
    "cases": [
      {
        "id": "read-peak",
        "description": "Read-dominated feed load with hybrid write mix",
        "workload": {
          "baseRps": 6000,
          "requestDistribution": [
            { "type": "get-feed",       "weight": 0.95, "sizeBytes": 512 },
            { "type": "normal-post",    "weight": 0.049, "sizeBytes": 1536 },
            { "type": "celebrity-post", "weight": 0.001, "sizeBytes": 1536 }
          ]
        }
      }
    ]
  }
}
```
**What it does:** ~6,000 rps dominated by feed reads; the tiny `celebrity-post` slice is
what the hybrid must treat differently (pull, not push).

---

## 1 · Topology — `STRUCTURAL_RULE`

**1.1 single-source** — one traffic faucet (feed reads + posts modeled as one mixed source, or split; keep one graded faucet).
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_single_source" }
```

**1.2 connected-graph** — no orphans.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_connected_graph" }
```

**1.3 has a feed cache** — the precomputed per-user timeline.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "in-memory-cache", "minCount": 1 }
```

**1.4 has an object store / CDN for media** — 150 TB/day never touches app servers.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "object-storage", "minCount": 1 }
```

**1.5 has a social graph store** — follower/followee edges.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "graph-db", "minCount": 1 }
```

**1.6 has enough services** — at least the post, fan-out, and feed services.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "microservice", "minCount": 3 }
```

**1.7 fan-out is async** — the new-post event edge into the fan-out service is asynchronous.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "microservice", "toType": "microservice", "mode": "asynchronous" }
```

**1.8 fan-out writes into the feed cache** — the push edge exists.
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_edge", "fromType": "microservice", "toType": "in-memory-cache" }
```

**1.9 read path reaches the social graph** — the feed service can answer "which celebs do I follow?".
```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_path", "fromType": "microservice", "toType": "graph-db" }
```

---

## 2 · Component choice — `SEMANTIC_CRITERION`

**2.1 media in a blob store (the trap, `hardFail`)** — 150 TB/day of images belongs in an
object store fronted by a CDN, never in a database.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "storageFit",
  "accessPattern": "blob",
  "accept": [ "object-storage" ],
  "antiPattern": [ "relational-db", "nosql-db" ],
  "points": 3,
  "hardFail": true
}
```

**2.2 feed cache sits between the read service and the metadata store** — reads hit the
cache first, then hydrate from the store.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "placement",
  "componentType": "in-memory-cache",
  "between": [ "microservice", "nosql-db" ],
  "points": 2
}
```

**2.3 post metadata fits a point/key lookup** — post_id → metadata is a get-by-key.
```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "storageFit",
  "accessPattern": "point-lookup",
  "accept": [ "nosql-db", "kv-store" ],
  "partial": [ "relational-db" ],
  "points": 2
}
```

---

## 3 · Behavior under load — `RUBRIC_CHECK`

**3.1 feed read p99 < 200 ms** — the read is an O(1) cache hit; the tail stays low.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.latency.p99", "op": "<", "value": 200, "points": 3 }
```

**3.2 error rate < 2%** — the read path stays healthy under the fan-out storm.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.errorRate", "op": "<", "value": 0.02, "points": 2 }
```

**3.3 metadata store not saturated** — the cache shields the DB; the busiest node is under 90%.
```json
{ "type": "RUBRIC_CHECK", "metric": "perNode.maxUtilization", "op": "<", "value": 0.9, "points": 2 }
```

**3.4 sustains read throughput** — completions keep up with the feed-read load.
```json
{ "type": "RUBRIC_CHECK", "metric": "summary.throughput", "op": ">=", "value": 5000, "points": 1 }
```

**3.5 no invariant violations** — physically consistent (fan-out branches conserved).
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
```

**3.6 conservation holds** — no requests vanish across the amplified fan-out.
```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "conservation.unbalanced", "op": "==", "value": 0, "points": 1 }
```

---

## Coverage map

| Design decision | Row(s) |
|---|---|
| Media on object store + CDN (not a DB) | 1.4, 2.1 (hardFail) |
| Precomputed feed cache for O(1) reads | 1.3, 2.2, 3.1, 3.3 |
| Fan-out-on-write is async and hits the feed cache | 1.7, 1.8 |
| Social graph store for follow edges | 1.5, 1.9 |
| Post metadata is a key lookup | 2.3 |
| Read path meets latency + throughput under fan-out | 3.1, 3.4 |
| Healthy, conserved run | 3.2, 3.5, 3.6 |

**Still justification (no row):** hybrid push/pull threshold (celebrity cutoff), ML feed
ranking, cursor pagination stability, feed-cache cold rebuild, celebrity thundering-herd.
The fan-out **amplification** is measured as N× feed-cache load (visible in 3.3 / node
metrics) but `fanoutAmplifiedWrites` is not yet a first-class rubric metric.

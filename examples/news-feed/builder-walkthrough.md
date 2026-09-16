# Instagram / News Feed — Builder Walkthrough (hybrid fan-out + feed cache + CDN)

A step-by-step runbook for building a read-dominated news feed in the simulator. The
defining trait is the **fan-out problem**: one post by a celebrity must reach tens of
millions of feeds, while the feed read must still be instant. Ends in an honest model
where normal-author posts are pushed into per-user feed caches (fan-out-on-write),
celebrity posts are pulled and merged at read time, media is offloaded to a CDN, and the
read path is an O(1) feed-cache hit.

> Source: `system-design-prep.pdf` §3 (Instagram / News Feed). Mirrors the format of
> `examples/url-shortener/builder-walkthrough.md`.

## The problem

> **Design a news feed (Instagram-style).** Post photos, follow users, and see a
> personalized, reverse-chronological-ish feed of posts from people you follow. The
> defining trait is the **fan-out problem**: one post by a celebrity must reach tens of
> millions of feeds, while the feed read must still be instant.
>
> **Functional**
> - Upload a post (image + caption).
> - Follow / unfollow users (asymmetric, directed graph).
> - View a personalized feed of recent posts from followed users.
> - Like / comment.
>
> **Non-functional**
> - Feed load must be fast (sub-second) — it's the core experience.
> - High availability; eventual consistency is acceptable (a post appearing a few seconds late is fine).
> - Read latency >> write latency in priority.
>
> **Scale to design against**
> - 500M DAU; ~100M posts/day → ~1,200 writes/sec avg.
> - 500M × 10 opens = ~5B feed reads/day → ~60K reads/sec avg, far higher peak.
> - Read:write ≈ 50:1 or more; highly skewed follower counts (a few accounts have 100M+ followers).
> - ~1.5MB/photo → 100M × 1.5MB = ~150 TB/day media → object store + CDN.

## Final topology

```
Poster ─(upload)→ Post Service ──► Object Store + CDN (media 150 TB/day)
                     │        └──► Posts DB (metadata)
                     └─(new-post event, async)→ Fan-out Service ──(normal: push post_id, fanout=300)──► Feed Cache
                                                     └── who follows author? ──► Social Graph

Viewer ─(GET /feed)→ Feed Service ──► Feed Cache (read precomputed timeline)
                        ├── pull celeb posts + hydrate ──► Posts DB
                        └── celeb I follow? ──► Social Graph
```

- **Normal authors (push):** Fan-out Service writes `post_id` into every follower's feed
  cache — a fan-out-on-write storm (amplification factor ≈ avg followers).
- **Celebrity authors (pull):** skip fan-out; Feed Service pulls their recent posts at read
  time and merges (bounded by how many celebrities a viewer follows).
- **Read path:** Feed Cache hit → O(1); media served from the CDN, never app servers.

---

## Part 1 — Place the nodes

| Diagram box | Search / palette node | componentType | Rename to |
|---|---|---|---|
| Poster | **Traffic Source** | source | Poster |
| Viewer | **Traffic Source** | source | Viewer |
| Post Service | **API Server** | microservice | Post Service |
| Fan-out Service | **API Server** | microservice | Fan-out Service |
| Feed Service | **API Server** | microservice | Feed Service |
| Object Store + CDN | **Object Storage** | object-storage | Object Store + CDN |
| Posts DB (metadata) | **NoSQL DB** | nosql-db | Posts DB |
| Social Graph | **Graph DB** | graph-db | Social Graph |
| Feed Cache | **Distributed Cache** | in-memory-cache | Feed Cache |

## Part 2 — Configure the sources (post mix + read traffic)

**Poster** (writes, with the celebrity split that drives the hybrid):
1. **CONFIG** → **Workload**: Pattern `constant`, Base RPS `1200` (≈1,200 posts/s avg).
2. **Request Templates** → **Requests**:
   - Row 1: type `normal-post`, weight **99** %, Method `POST`
   - **+ Add request** → Row 2: type `celebrity-post`, weight **1** %, Method `POST`
   - Total weight = 100.0%.

**Viewer** (reads — the dominant traffic):
1. **CONFIG** → **Workload**: Pattern `constant`, Base RPS `60000` (≈60K feed reads/s).
2. **Requests**: single type `get-feed`, Method `GET`.

## Part 3 — Configure the hybrid fan-out (the core of the design)

**Post Service → Fan-out Service** edge: **Mode = asynchronous** (the "new-post event" is
off the uploader's path).

**Fan-out Service content-routing (push vs pull):** Fan-out Service must only push for
normal authors. Give it routing that sends `normal-post` down the fan-out edge and drops
`celebrity-post`:
- Set Fan-out Service **routing strategy → content-aware**, rule: `type == normal-post`
  → **Feed Cache**. (Celebrity posts have no push edge — they are pulled at read time.)

**Fan-out amplification (GAP 2):** on the edge **Fan-out Service → Feed Cache**, open the
edge panel and set **Fan-out factor** = `300` (avg followers), **Mode = asynchronous**.
One normal post now amplifies into ~300 feed-cache writes — the fan-out-on-write storm,
measured as N× load on Feed Cache and `fanoutAmplifiedWrites` on the source.

**Feed Cache (read path):** **CONFIG** → **Caching** → **Cache hit rate** `0.95` — the
precomputed timeline is an O(1) hit for the 60K read rps.

## Part 4 — Wire the edges

```
Poster           → Post Service
Post Service     → Object Store + CDN          (media bytes)
Post Service     → Posts DB                     (metadata)
Post Service     → Fan-out Service              (new-post event, async)
Fan-out Service  → Social Graph                 (who follows author?)
Fan-out Service  → Feed Cache                   (normal: push post_id, fanoutFactor=300, async)
Viewer           → Feed Service
Feed Service     → Feed Cache                    (read precomputed timeline)
Feed Service     → Posts DB                      (pull celeb posts + hydrate)
Feed Service     → Social Graph                  (celeb I follow?)
```

## Part 5 — Run

Click **Run**.

### Expected result (what "correct" looks like)

| Metric | Where | Meaning |
|---|---|---|
| Feed Cache hit ratio ≈ 95% | Feed Cache | reads served from the precomputed timeline |
| `fanoutAmplifiedWrites` > 0 | Fan-out Service / source | fan-out-on-write is live |
| Feed Cache write load ≈ 300× normal-post rate | Feed Cache | the write storm is measured, not asserted |
| Fan-out Service downstream split: normal only | Fan-out Service | celebrity posts skip push (hybrid) |
| Posts DB read load ≪ 60K | Posts DB | reads are cache-shielded; DB only hydrates + celeb pulls |
| Object Store received ≈ upload rate | Object Store + CDN | media offloaded off app servers |

The tell-tale of a correct hybrid: **Feed Cache write amplification tracks only the
normal-post rate × 300** (celebrity posts do not fan out), while the read path stays a
~95% cache hit.

---

## Why it's built this way (gotchas)

- **Hybrid = content-routing on author type.** The push/pull split is a routing decision on
  request `type` (`normal-post` vs `celebrity-post`), authored on the Fan-out Service — not
  a hard-coded branch. Only nodes that can content-route (gateway/L7/service with
  content-aware strategy) can do it.
- **Fan-out must be async and on the write edge.** Put `fanoutFactor` on
  `Fan-out Service → Feed Cache` with **Mode = asynchronous** so the uploader never blocks
  on ~300 feed writes.
- **Cache hit rate needs the read to actually hit the cache.** Feed Service reads from Feed
  Cache first; Posts DB is only for hydration and celebrity pulls. If Feed Service reads
  Posts DB directly, you lose the O(1) read-path story.
- **Media never touches app servers.** Route media bytes straight to Object Store + CDN.

## Full reference topology (the canonical design)

### Nodes

| Node | Simulator component | Key config |
|---|---|---|
| Poster | **Traffic Source** | `normal-post` 99% / `celebrity-post` 1% |
| Viewer | **Traffic Source** | `get-feed` at ~60K rps |
| Post Service | **API Server** | thin upload; async new-post event |
| Fan-out Service | **API Server** | content-route `normal-post` → Feed Cache (push); celeb dropped (pull) |
| Feed Service | **API Server** | read Feed Cache + merge celeb pulls from Posts DB |
| Object Store + CDN | **Object Storage** | 150 TB/day media, edge-served |
| Posts DB | **NoSQL DB** | post metadata source of truth |
| Social Graph | **Graph DB** | follower/followee edges |
| Feed Cache | **Distributed Cache** | hit rate 0.95; per-user precomputed timeline |

### The design decisions this topology makes gradeable

- **Fan-out-on-write amplification (GAP 2, measured):** `fanoutFactor=300` on the push edge
  → Feed Cache sees ~300× the normal-post rate; `fanoutAmplifiedWrites` counts it.
- **Hybrid push/pull (measured):** content-routing on author `type` — the celebrity write
  blast radius is bounded because celebrity posts never fan out.
- **Read-path cache offload (measured):** Feed Cache hit ratio ~0.95 → Posts DB read load
  collapses; the 60K read path is an O(1) cache hit.

### Where the reference is still justification (not simulated)

- **ML feed ranking** — the feed here is chronological; ranking is an extension, not modeled.
- **Cursor (opaque) pagination** — a correctness/stability property, graded by justification.
- **Feed-cache cold/eviction rebuild for dormant users** — topology + justification.
- **Celebrity thundering-herd on post** — mitigate by caching the celebrity's recent posts
  hard (the read-time pull is itself a cache hit); needs a fault to demonstrate the herd.

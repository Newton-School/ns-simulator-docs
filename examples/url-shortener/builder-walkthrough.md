# URL Shortener — Service Builder Walkthrough (cache-aside + type-aware routing)

A step-by-step runbook for building a read-heavy URL shortening service in the
simulator using the **Service Builder**, a cache-aside path, and an **API Gateway**
that routes reads and writes differently. Ends in a fully honest model: reads are
cache-offloaded, writes bypass the cache and go straight to the DB.

> This is the interactive-builder walkthrough. The other files in this folder
> (`question.json`, `reference-topology.json`, …) are the authored-question version
> of the same scenario and are unrelated to these steps.

## Final topology

```
Input Source → API Server → URL Shortening Service → API Gateway
                                                        ├─(GET 99%)→ Distributed Cache → (miss ~5%) → SQL DB
                                                        └─(POST 1%)────────────────────────────────→ SQL DB
```

- Reads (99%, GET): ~95% served from cache, ~5% miss to the DB.
- Writes (1%, POST): always to the DB, **never cached**.

---

## Part 1 — Create the URL Shortening Service (Service Builder)

1. Library → **Templates** → click the **Service** tile → opens **Service Builder**.
2. **Basics** → **Name** = `URL Shortening Service`.
3. **Runtime** → click **Long-running service** (executes as `microservice`).
4. **Interface & operations** *(documentation only — does not affect the sim)*:
   - **Operation 1**: Method `GET` · Request name `resolve-short-url` · Response name `redirect` · Intent **Read**
   - **+ Add operation** → **Operation 2**: Method `POST` · Request name `create-short-url` · Response name `short-code` · Intent **Write**
5. **Traits** *(this is what actually simulates)* — keep **Capacity** + **Workload profile** enabled:
   - **Workload profile** → Service time ms = `25`
   - **Capacity** → Workload kind = `IO-bound`
6. *(optional)* right pane → tick **Save to My Services**.
7. Click **Create node**.

## Part 2 — Place the other nodes

Drag onto the canvas from the library:

- **Input Source** (Templates)
- **API Server** (Compute) — optional extra hop; can be omitted for a leaner path
- **API Gateway** (Network) — **not** a plain Load Balancer / L4
- **Distributed Cache** (Data Stores)
- **SQL DB** (Data Stores)

## Part 3 — Configure the Input Source (the request mix)

1. Select **Input Source** → **CONFIG**.
2. **Workload** → Pattern `constant`, Base RPS `100`.
3. **Request Templates** → **Requests**:
   - Row 1: type `resolve`, weight **99** %, Method `GET`, Path `/{code}`
   - **+ Add request** → Row 2: type `create`, weight **1** %, Method `POST`, Path `/url`
   - Confirm **Total weight = 100.0%**.

## Part 4 — Configure the Distributed Cache

1. Select **Distributed Cache** → **CONFIG** → **Caching**.
2. **Cache hit rate** = `0.95`.
3. *(optional)* **Cache hit latency** = `0.1` ms.

## Part 5 — Wire the edges

```
Input Source           → API Server
API Server             → URL Shortening Service
URL Shortening Service  → API Gateway
API Gateway            → Distributed Cache      (read path)
API Gateway            → SQL DB                 (write path)
Distributed Cache      → SQL DB                 (cache-miss fall-through)
```

## Part 6 — API Gateway routing rules

Select **API Gateway** → **CONFIG** → **Content Routing** → **Routing Rules** → **+ Add rule** (two rules):

- Match field **`method`**, value **`GET`** → target **Distributed Cache**
- Match field **`method`**, value **`POST`** → target **SQL DB**

## Part 7 — Run

Click **Run again**.

### Expected result (what "correct" looks like)

| Metric | Value | Meaning |
|---|---|---|
| API Gateway downstream split | Cache ~98.9% / SQL DB ~1.1% | 99% GET vs 1% POST |
| Cache received | ~5,439 (< gateway's ~5,501) | writes bypassed the cache |
| Cache hit ratio | ~95% | reads mostly served from cache |
| SQL DB received | ~343 | read-misses (~278) + writes (~65) |
| Availability / errors | 100% / 0% | healthy |

The tell-tale of a correct build: **Cache received is strictly less than the Gateway
received** — the gap is the writes that skipped the cache.

---

## Why it's built this way (gotchas we hit)

- **Operation intents on the service are documentation only.** The real read/write
  split comes from the **Input Source request mix** (Part 3), not the service's
  operations.
- **A plain service or API Server cannot route by request type.** Only an
  **API Gateway / L7 Load Balancer / Ingress Controller** can content-route, which is
  why the gateway does the GET/POST split.
- **Cache hit rate needs a downstream edge to express misses.** If the cache has no
  `Cache → SQL DB` edge, misses have nowhere to go and it behaves like a 100%-hit
  cache. Always keep the miss fall-through edge.
- **Parallel vs inline:** if the service fans out to Cache *and* DB as siblings with
  no routing, the engine splits ~50/50 (a default hit rate). Put the cache **in front
  of** the DB (inline) or route explicitly at a gateway.

## Simpler variants

- **(a) Cache-aside only, no type awareness:** drop the API Gateway; wire
  `Service → Cache → SQL DB` and set the cache hit rate. Writes get (wrongly) served
  from cache, but at 1% write volume the distortion is negligible.
- **Leaner path:** the API Server is an extra hop that only adds latency; route the
  source straight into the URL Shortening Service if you don't need it.

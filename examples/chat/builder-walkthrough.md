# Chat Application — Builder Walkthrough (connection tier + persist-before-ACK + fan-out)

A step-by-step runbook for building a WhatsApp/Messenger-style chat service in the
simulator. The defining trait is the opposite of the URL shortener: **stateful,
persistent connections and strict per-conversation ordering**. Ends in an honest model
where the connection tier saturates on held connections, the durability gate is a real
sync chain (persist *before* ACK), online delivery routes through a pub/sub bus, and
group fan-out amplifies one message into N deliveries.

> Source: `system-design-prep.pdf` §2 (Chat Application). This is the interactive-builder
> walkthrough; it mirrors the format of `examples/url-shortener/builder-walkthrough.md`.

## The problem

> **Design a chat application (WhatsApp / Messenger-style).** 1:1 and group chat,
> real-time delivery, online presence, delivery/read receipts, and message history. The
> defining trait is **stateful, persistent connections and strict per-conversation
> ordering** — the opposite of the stateless URL shortener.
>
> **Functional**
> - 1:1 messaging and group messaging.
> - Real-time delivery to online users; store-and-forward for offline users.
> - Delivery + read receipts; online/last-seen presence; typing indicators.
> - Persistent message history retrievable on any device.
>
> **Non-functional**
> - Low-latency delivery: sub-second end-to-end for online users.
> - Durability: an accepted message must never be lost, even if the recipient is offline for days.
> - Ordering: messages within a conversation appear in a consistent order for all participants.
> - Availability: favor availability; a brief delay is acceptable, a lost message is not.
>
> **Scale to design against**
> - 50M DAU; ~10M peak concurrent connections (drives the connection-tier sizing).
> - 50M users × 40 msgs = ~2B msgs/day → ~23K msgs/sec avg, ~100K/sec peak.
> - ~1KB avg message → ~2 TB/day raw → tiered storage.
> - ~10M connections at ~65K/host → ~150–300 connection servers.

## Final topology

```
Sender ─(WSS: send)→ Connection Servers ─1·deliver→ Presence/Session Registry
                          │                              ├─ ONLINE → Pub/Sub Bus → (recipient's) Connection Server → Recipient
                          │  2·persist                   └─ OFFLINE → Offline Inbox (queue) → APNs/FCM (external) → Recipient
                          ▼
                     Message Service ──► Cassandra (messages + history)
                     (persist BEFORE ack)
```

- **Durability:** the sender is ACKed only *after* Message Service persists to Cassandra.
- **Online delivery:** Presence Registry finds the recipient's server; Pub/Sub routes to it.
- **Offline delivery:** enqueue to the per-user Offline Inbox, then hand off to the external
  push provider (APNs/FCM) — a third-party call with real latency, fanning out to the user's N devices.
- **Group fan-out:** one group message amplifies into N member deliveries (fan-out factor).

---

> **Prerequisite — set Edge model = Network.** This build configures edges (async mode,
> WebSocket protocol, **Fan-out factor**). Those fields only exist when the edge model is
> **Network**. If your edge panel shows only *Label / Protocol / Interaction / Route
> appearance* and says "only change its canvas presentation," you're in **Connector** mode
> (dumb wires, no physics). Switch it at **Settings → Environments → Edge model → Network**,
> then reopen the edge to see Protocol (transport), Interaction (sync/async), Fan-out factor,
> bandwidth, and latency.

## Part 1 — Place the nodes

Search each term in the Component Library (left panel), drag onto the canvas, then rename:

| Diagram box | Search / palette node | componentType | Rename to |
|---|---|---|---|
| Sender | **Traffic Source** | source | Sender |
| Connection Servers | **Connection Server** | api-gateway (+`sim.connection`) | Connection Servers |
| Message Service | **API Server** | microservice | Message Service |
| Cassandra (messages + history) | **NoSQL DB** | nosql-db | Cassandra |
| Presence / Session Registry | **Distributed Cache** | in-memory-cache | Presence Registry |
| Pub/Sub Bus | **Pub/Sub** | pub-sub | Pub/Sub Bus |
| Offline Inbox | **Message Queue** | queue | Offline Inbox |
| Push provider (APNs/FCM) | **External Service** *(or **Notification Service**)* | third-party-api-connector *(or push-notification-service)* | APNs / FCM |
| Recipient's server | **Connection Server** | api-gateway (+`sim.connection`) | Recipient Conn Server |

## Part 2 — Configure the Sender (the message mix)

### The protocol → simulator mapping

The real chat API is a WebSocket with typed **frames** plus a REST side-channel for
history/setup. Each frame maps to a simulator **request `type`** — all multiplexed over the
one WebSocket connection (Method stays unset; the transport is the edge protocol, Part 3):

| Protocol element (from the API spec) | Direction | In the simulator |
|---|---|---|
| `SEND {convId, body, ts}` | client→server | source request **`type: send-direct`** / **`send-group`** (group = fan-out) |
| `ACK {convId, msgId}` | client→server | source request **`type: ack`** (delivered/read receipt) |
| `TYPING {convId}` | client→server | source request **`type: typing`** (light, presence-tier) |
| `PRESENCE {status}` | client→server | source request **`type: presence`** (light, presence-tier) |
| `MESSAGE {...}` | server→client | **delivery** — the downstream push (Pub/Sub → recipient's server), *not* a source row |
| `RECEIPT {state}` | server→client | **delivery** — the receipt flowing back, *not* a source row |
| `GET /conversations`, `GET /.../messages` | REST request/response | a **second edge** on **HTTPS** to the API Gateway → history read (see variant below) |

> **Only client→server frames are source request rows.** The server→client frames
> (`MESSAGE`, `RECEIPT`, presence push) are what the topology *produces* as deliveries —
> you don't author them as inputs; they emerge from the Pub/Sub → recipient path.

### Request rows

1. Select **Sender** → **CONFIG** → **Workload**: Pattern `constant`, Base RPS `23000`
   (≈23K msg/s average from the scale table; use `4000` for a quicker first run).
2. **Request Templates** → **Requests** — one row per client→server frame. The **type** field
   is the frame; **Method** is a fixed HTTP enum and these are WebSocket frames, so leave it unset:
   - Row 1: type `send-direct`, weight **35** % (1:1 message)
   - Row 2: type `send-group`, weight **15** % (group message → fan-out)
   - Row 3: type `ack`, weight **30** % (delivered/read receipts)
   - Row 4: type `typing`, weight **12** %
   - Row 5: type `presence`, weight **8** %
   - Confirm **Total weight = 100.0%**.

> **Note on Method vs Type vs Transport.** Three different things:
> - **`type`** (per request) = the app-level message class (`send-direct` / `send-group`) —
>   the simulator routes/grades on this. There is no "SEND" method.
> - **Method** (per request) = a fixed HTTP enum; leave it blank for WebSocket frames.
> - **Transport = WebSocket** is declared on the **edge protocol** and the connection tier's
>   **Protocol Session / Connection capacity** (Part 3), *not* on the request rows — because
>   one persistent socket carries many messages.

## Part 3 — Configure the Connection tier (held-connection capacity)

> **Transport decision (from the API spec):** *"a persistent WebSocket per device, not HTTP
> polling."* This is the reason the connection tier is a distinct, hard-to-scale box: every
> device holds one long-lived socket, so the tier's binding resource is **concurrent held
> connections**, not request throughput. **Offered connections ≈ concurrent devices** (≈10M
> at peak — more than DAU, since users have multiple devices). HTTP polling would instead
> mean millions of repeated handshakes/sec and seconds of delivery lag — which is what the
> WebSocket choice avoids.

The connection tier's capacity is measured in **concurrent held connections**, a
dimension distinct from RPS — this is GAP 1 (`specs/connection-tier-capacity.md`).

> **How the capacity math works.** The Connection Server ships with **offered = 0**, so it
> reads **0% used** until *you* declare a target held-connection count (it never claims a
> utilization for a load you never specified). Once you enter **Offered connections**, the
> readout is pure config-time arithmetic (no run needed):
>
> ```
> fleet capacity     = maxConnectionsPerInstance × instanceCount
> utilization        = offeredConnections ÷ fleet capacity     (>100% ⇒ saturated + refusals)
> required instances = ceil(offeredConnections ÷ maxConnectionsPerInstance)
> ```
>
> So if you set offered = 100,000 at 1 instance you'll see **154% used** (35K refused) —
> bump **Service Instances** to the **Required instances** the readout shows (2 here, ~154 for
> the 10M target) to go green. Dropping instances *below* required is how you deliberately
> demo saturation + `connectionsRefused`.

1. Select **Connection Servers** → **CONFIG** → **Connection capacity**:
   - **Max connections / instance** = `65000` (keep)
   - **Offered connections** = your target held connections. Use `10000000` for the full
     10M-concurrent scale, or a smaller number for a quick run.
   - **Heartbeat interval ms** = `30000`
   - **Session protocol** = `WebSocket`
2. Set **Resources → Service Instances** to the **Required instances** the readout shows
   (`ceil(offered ÷ 65000)`): **2** for the default 100K, **~154** for the 10M scale target.
   The badge turns green and `Held / refused` shows `… / 0` once fleet capacity ≥ offered.
   (Leave instances *below* the required count to deliberately demo saturation + refusals.)
3. **Declare the transport as WebSocket** (this is where "these are WebSocket connections"
   lives — *not* on the request rows):
   - **Connection Servers → CONFIG → Protocol Session → Protocol** = `websocket`. This drives
     the session-lifecycle model: `protocolSessionsOpened`, the flow-control window, and L7
     session policy.
   - On the **Sender → Connection Servers** edge, open the edge panel and set
     **Protocol = WebSocket**. The edge protocol is the transport of the persistent
     connection; individual `send-direct` / `send-group` messages then flow as typed
     requests *over* that one open socket (you don't re-handshake per message).

## Part 4 — Configure durability, delivery, and fan-out

**Message Service (persist-before-ACK):** leave as a stateless microservice. The
durability guarantee comes from the *edge order*: Message Service → Cassandra is a
**synchronous** edge, so the ACK only returns after the write commits.

**Content-route by frame type (so you don't persist/fan-out everything).** Not every frame
should hit Cassandra or Pub/Sub — persisting `typing`/`presence`/`ack` and fanning them out
inflates load massively (it's a big chunk of the failure cascade if you skip this).

There is **no "content-aware" strategy dropdown** — content routing on an api-gateway
(the Connection Server's backing type) is its **own section**: **Connection Servers → CONFIG
→ Content Routing → Routing Rules → + Add rule**.

**How it behaves (important):** a rule that *matches* a request **filters it to that single
target** (dropping the other outgoing edges); a request that matches **no** rule **forks to
all** outgoing edges as normal. So add rules **only for the frames you want to divert** —
leave `send-*` unmatched so they keep forking to both Message Service (persist) *and*
Presence (deliver):
- **Match field `type`, value `typing`** → target **Presence Registry**
- **`type` = `presence`** → target **Presence Registry**

Now `typing`/`presence` go **only** to Presence Registry (they skip Message Service →
Cassandra, so they're not persisted) while still flowing Presence → Pub/Sub → recipient
(delivered, not stored). Unmatched `send-direct` / `send-group` / `ack` fork normally to
persist + deliver. (Content routing is available on **api-gateway / load-balancer-l7 /
ingress-controller** only — a plain microservice can't do it.)

**Cassandra:** **CONFIG** → **Replication** → **Enable replication** ✓, role **leader**,
then set **Replica members** = `db-a, db-b, db-c`. That's the whole cluster — quorum,
leader promotion, and the failover window all live on **this one node's** config.
- **Do NOT** add a second "follower" NoSQL DB with a `leader → follower` request edge. The
  engine models replication *inside* a single datastore node (via Replica members), not by
  wiring two nodes. A physical leader→follower edge just **forwards client writes** into the
  second node, so it double-processes writes (both cards then show "⇉ replicated" and both
  take write load) — that's request forwarding, not replication.
- (Optional) set **Write acknowledgement** = `quorum` to make writes wait for the member
  quorum, and a **Failover window** to demo the bounded unavailability during promotion.

**Presence Registry (Distributed Cache):** **CONFIG** → **Caching** → **Cache hit rate**
`0.95` — most "which server holds the recipient?" lookups hit the in-memory registry.

**Group fan-out (the write storm):** on the edge **Pub/Sub Bus → Recipient Conn Server**
(the group-delivery edge), open the edge panel and set **Fan-out factor** = `50` (avg
group size), **Mode = asynchronous**. One `send-group` message now amplifies into 50
member deliveries — this is GAP 2 (`fanoutAmplifiedWrites` on the source, N× load on the
recipient tier).

**Push tier (APNs/FCM as a real external dependency):** the push provider is a third-party
call the caller does not control — model it as an external node, not a free sink. The
placeable external-call tile is **External Service** (backed by `third-party-api-connector`); the
upgraded **Notification Service** node works identically and reads more clearly on the canvas.
- Select **APNs / FCM** → **CONFIG** → **External Dependency** → **External call latency**
  = `120` ms (round-trip to the provider; pair with a retry/circuit-breaker to show blast radius).
- On the edge **Offline Inbox → APNs / FCM**, set **Mode = asynchronous** and **Fan-out
  factor** = `3` (a user's ~3 devices) — one notification fans out to each device.
- The `externalCalls` counter and the added latency make the push hop a *measured* external
  dependency, not a free hop.

> **This whole tier is a reusable pattern** — decouple (queue) → external provider call
> (External Service / Notification Service) → device fan-out. See
> [`../patterns/notifications.md`](../patterns/notifications.md) for the generic recipe and
> how to build it with or without a dedicated notification node.

## Part 5 — Wire the edges

```
Sender               → Connection Servers           (WSS: send · edge Protocol = WebSocket)
Connection Servers   → Message Service              1· deliver
Message Service      → Cassandra                    2· persist (sync = persist-before-ACK)
Connection Servers   → Presence Registry            recipient online?
Presence Registry    → Pub/Sub Bus                  ONLINE → route
Pub/Sub Bus          → Recipient Conn Server        push to recipient's server (fanoutFactor=50 for groups)
Presence Registry    → Offline Inbox                OFFLINE → enqueue
Offline Inbox        → APNs / FCM                    trigger (async · fanoutFactor = 3 devices)
```

## Part 6 — Run

Click **Run**.

### Expected result (what "correct" looks like)

| Metric | Where | Meaning |
|---|---|---|
| Connection utilization < 100% | Connection Servers | fleet sized for 10M held connections |
| `connectionsRefused` = 0 (healthy) / > 0 (under-provisioned) | Connection Servers | node-level held-connection ceiling |
| Required instances ≈ 154 | Connection Servers readout | 10M ÷ 65K/host |
| Cassandra received ≈ message rate | Cassandra | every accepted message persisted before ACK |
| `fanoutAmplifiedWrites` > 0 | Pub/Sub Bus / source | group fan-out amplification is live |
| Recipient Conn Server deliveries ≈ 50× group rate | Recipient Conn Server | the group write storm is measured |
| Availability / errors | all | healthy when provisioned |

---

## Variant — the REST history/setup channel (HTTPS, not real-time)

The API spec has a second, non-real-time surface: `GET /conversations` and
`GET /conversations/{id}/messages?before=…&limit=50`. This is **request/response over
HTTPS**, not a WebSocket frame — model it as a *separate edge and path* so both transports
coexist from one client:

1. Add an **API Gateway** node (distinct from the Connection Servers) → wire
   **Sender → API Gateway** on a **second edge** with **Protocol = HTTPS**.
2. Add request rows for the REST calls with a real **Method**:
   - type `get-conversations`, **Method `GET`**, Path `/conversations`
   - type `get-history`, **Method `GET`**, Path `/conversations/{id}/messages`
3. Route them to Cassandra for the history read: **API Gateway → Cassandra** (content-route
   `Method GET` / path). These reads never touch the WebSocket tier.

This is the concrete version of the earlier point: **one client, two request kinds over two
transports** — live frames over WebSocket to the Connection Servers, history over HTTPS to
the API Gateway. The `type` decides the path; the edge decides the transport.

## Advanced / realistic topology (refinements)

The core build above is faithful to the interview design. Three refinements make it match a
real production chat system more closely — each is buildable in the simulator.

### 1. Keep Connection Servers "dumb" — add a Chat Router Service
In the core build the Connection Servers orchestrate the fork (persist + presence + delivery),
which loads the stateful, hard-to-scale tier with business logic. Move that off:

- Place an **API Server** (`microservice`), rename **Chat Router**.
- Rewire: **Connection Servers → Chat Router**, then **Chat Router → Message Service**,
  **Chat Router → Presence Registry** (and the content-routing rules for `typing`/`presence`
  move onto the **Chat Router** if you keep it an api-gateway, or stay on the gateway tier).
- Now the Connection Servers only **hold sockets + forward**; the stateless Chat Router does
  the orchestration and scales freely.
- **Measured payoff:** the connection tier's utilization/errors drop (this is the honest fix
  for the "Connection Servers needs attention" signal); the Chat Router becomes the busy,
  horizontally-scalable node.

### 2. Media path — object store + CDN, never through Pub/Sub
Pushing 1.5 MB image/video payloads through the Pub/Sub Bus saturates it. Real systems upload
media out-of-band and pass only a URL through the real-time pipeline:

- Add an **Object Storage** node. Wire a **separate** media-upload edge (client →
  Object Storage) — set that edge's request **size** to the media bytes (e.g. `1500000`).
- On the messaging path, the `send-*` frame carries only the **metadata/URL** — keep its
  request **size** tiny (e.g. `512` B). Media bytes never touch Pub/Sub.
- **Measured payoff:** the Pub/Sub Bus stops saturating on payload size; bandwidth moves to
  the object store. (The pre-signed-URL handshake itself stays justification.)

### 3. History sync on reconnect — HTTP API Gateway → Message Service
When an offline user returns they **pull** missed messages (pagination), not via the push
pipeline. This is the **REST history/setup channel** above — a separate HTTPS API Gateway →
Cassandra path for `GET /conversations/{id}/messages?before=…&limit=50`. Keep it off the
WebSocket tier.

> **Latency note:** validate the *online* path (`Sender → … → Recipient Conn Server`, and the
> persist-ACK leg) against a **sub-second** SLA; the offline push (APNs/FCM) is explicitly
> outside that budget. See the split SLAs in `test-cases.md` (§3.1a / §3.1b).

## Why it's built this way (gotchas)

- **Persist-before-ACK is an edge-order property, not a checkbox.** Keep
  `Message Service → Cassandra` **synchronous** so the sender's ACK waits on the durable
  write. If you make it async, the sim (correctly) shows the ACK returning before the
  write — i.e. you broke the durability NFR.
- **Connection capacity ≠ RPS.** A connection tier can be at ~0% CPU utilization and still
  be saturated on *held connections*. Use the **Connection capacity** panel, not throughput,
  to size it.
- **Group fan-out belongs on the delivery edge, and must be async.** Put `fanoutFactor` on
  the Pub/Sub → recipient edge with **Mode = asynchronous** so the sender doesn't block on
  all N member deliveries.
- **Presence lookups are routing, not storage.** The registry is modeled as a cache/key
  lookup ("which server holds U?"), not a durable store.

## Full reference topology (the canonical design)

### Nodes

| Node | Simulator component | Key config |
|---|---|---|
| Sender | **Traffic Source** | msg mix: `send-direct` 80% / `send-group` 20% |
| Connection Servers | **Connection Server** | `sim.connection`: 65K/instance, 10M offered, 30s heartbeat, WebSocket; instances ≈154 |
| Message Service | **API Server** | stateless; sync edge to Cassandra = persist-before-ACK |
| Cassandra | **NoSQL DB** | replication on one node: leader + `Replica members` (quorum/failover live here); partition conv_id, clustering msg_id |
| Presence Registry | **Distributed Cache** | hit rate 0.95 (which server holds recipient) |
| Pub/Sub Bus | **Pub/Sub** | one-to-many routing to recipient's server |
| Offline Inbox | **Message Queue** | per-user store-and-forward (async) |
| APNs / FCM | **External Service** (or **Notification Service**) | external push provider: external-call latency + `externalCalls`; device `fanoutFactor` ≈ 3 |

### The design decisions this topology makes gradeable

- **Connection-tier capacity (GAP 1, measured):** held connections vs fleet size,
  `connectionsRefused` on overflow, derived required-instance count. The "10M ÷ 65K → ~154
  servers" reasoning is live.
- **Durability (measured):** persist-before-ACK as a synchronous chain — the ACK latency
  includes the Cassandra write.
- **Group fan-out amplification (GAP 2, measured):** `fanoutFactor` turns one group message
  into N deliveries; the recipient tier sees N× load and can saturate.
- **Offline push as an external dependency (measured):** the APNs/FCM hop carries a real
  external-call latency + `externalCalls` counter (**External Service**, or the upgraded
  **Notification Service** node), with a device `fanoutFactor` — not a free sink.

### Where the reference is still justification (not simulated)

- **Presence-TTL auto-expiry** (a dead server's sessions expiring) — the registry is a
  lookup, not a TTL simulator.
- **Exactly-once / dedupe across a user's devices** — per-conversation sequence numbers are
  a client concern; grade by justification.
- **Thundering-herd reconnect** — needs a fault on the connection tier (fault-injection UI)
  to trigger the reconnect storm; the capacity math for it is already here.
- **Global total order across conversations** — deliberately not provided; only
  per-conversation ordering matters (Cassandra clustering key).

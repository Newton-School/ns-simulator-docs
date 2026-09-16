# Google Docs — Builder Walkthrough (per-doc session owner + op-log + WS layer)

A step-by-step runbook for building a collaborative editor in the simulator. The defining
trait is not scale — it's **correctness when two people type at the same position at the
same instant**. Ends in an honest model where a persistent WS layer routes every
connection for a `docId` to that doc's single owning session server, the session server
assigns the authoritative order, and an append-only op log is the durable source of truth
(replay → state, version history, crash recovery).

> Source: `system-design-prep.pdf` §4 (Google Docs / Collaborative Editor). Mirrors the
> format of `examples/url-shortener/builder-walkthrough.md`.

## The problem

> **Design a collaborative editor (Google Docs).** Multiple users edit the same document
> simultaneously, seeing each other's changes in real time, with no lost edits and eventual
> convergence to an identical document. The defining trait is **concurrent conflict
> resolution** — the hard part is not scale, it's **correctness when two people type at the
> same position at the same instant**.
>
> **Functional**
> - Create / edit rich-text documents.
> - Real-time multi-user collaboration with live remote cursors / presence.
> - Concurrent edits converge — all clients end with the identical document.
> - Persistence + version history; offline edits that reconcile on reconnect.
>
> **Non-functional**
> - Convergence (strong eventual consistency): every client must converge to the same state — the non-negotiable correctness property.
> - Low latency: local edits feel instant (optimistic local apply); remote edits appear within ~100 ms.
> - Durability: no acknowledged edit is ever lost; full version history.
>
> **Scale to design against**
> - 100s of millions of documents → shard by `document_id`.
> - Typically 1–10 concurrent editors per doc (cap ~100) → per-doc coordination is cheap; correctness is the challenge.
> - Keystroke-level edit rate (many tiny ops/sec) → need tiny, frequent op messages, not full-doc saves.

## Final topology

```
Editor A ─(OP baseRevision · cursor)→ Connection / WS Layer ─(route by docId)→ Document Session / Collaboration Server
Editor B ─(OP baseRevision · cursor)→        (routes by docId)                     (ONE owner per active doc:
                                                                                     assigns revisions · OT transform · broadcast)
                                                                                        ├── append ordered op ──► Operation Log + Snapshots
                                                                                        └── authz check ─────────► Doc Metadata & Permissions
```

- **WS layer:** persistent low-latency channel; routes every connection for a `docId` to
  that doc's owning session server (key-based / sticky routing by docId).
- **Session server:** the single point that assigns the authoritative revision order and
  runs OT transforms before broadcasting — one owner per active doc.
- **Op log + snapshots:** durable ordered truth; replay → current state + version history;
  snapshots bound replay cost.

---

## Part 1 — Place the nodes

| Diagram box | Search / palette node | componentType | Rename to |
|---|---|---|---|
| Editor A / Editor B | **Traffic Source** | source | Editors |
| Connection / WS Layer | **Connection Server** | api-gateway (+`sim.connection`) | WS Layer |
| Document Session / Collaboration Server | **API Server** | microservice | Session Server |
| Operation Log + Snapshots | **NoSQL DB** | nosql-db | Op Log + Snapshots |
| Doc Metadata & Permissions | **NoSQL DB** | nosql-db | Doc Metadata |

## Part 2 — Configure the Editors (the op stream)

### The protocol → simulator mapping

The real editor API is a WebSocket of typed **frames** (`wss://docs/api/v1/docs/{docId}/connect`)
plus a REST side-channel for snapshot load / history. Each **client→server** frame maps to a
simulator request **`type`**, multiplexed over one socket per editor (Method stays unset —
the transport is the edge, Part 3):

| Protocol element (from the API spec) | Direction | In the simulator |
|---|---|---|
| `OP {docId, baseRevision, op:{insert\|delete,pos,…}}` | client→server | source request **`type: op`** (the edit; `baseRevision` is the correctness linchpin) |
| `CURSOR {docId, pos, selection}` | client→server | source request **`type: cursor`** (presence, light) |
| `OP {revision, transformedOp, authorId}` | server→client | **delivery** — the ordered/transformed broadcast, *not* a source row |
| `CURSOR {authorId, pos}` | server→client | **delivery** — remote cursor push, *not* a source row |
| `ACK {clientOpId, revision}` | server→client | **delivery** — the ack rebasing the client's pending ops, *not* a source row |
| `GET /docs/{id}`, `GET /docs/{id}/history` | REST request/response | a **second edge** on **HTTPS** → snapshot load / version history (see variant below) |

> **Only client→server frames are source request rows.** The server→client frames
> (`OP` broadcast, `CURSOR` push, `ACK`) are what the Session Server *produces* — you don't
> author them as inputs; they emerge from the transform-and-broadcast path.

### Request rows

1. Select **Editors** → **CONFIG** → **Workload**: Pattern `constant`, Base RPS `2000`
   (keystroke-level, many tiny ops/sec across active docs; scale as needed).
2. **Request Templates** → **Requests** — one row per client→server frame. The **type** field
   is the frame; **Method** is a fixed HTTP enum and these are WebSocket frames, so leave it unset:
   - Row 1: type `op`, weight **90** % (an edit carrying `baseRevision`; Method: leave unset)
   - Row 2: type `cursor`, weight **10** % (Method: leave unset)
   - Total weight = 100.0%.

> **Note on Method vs Type vs Transport.** Three different things:
> - **`type`** (per request) = the app-level op class (`op` / `cursor`) — routed/graded on this.
> - **Method** (per request) = a fixed HTTP enum; leave blank for WebSocket frames.
> - **Transport = WebSocket** is declared on the **edge protocol** and the WS Layer's
>   **Protocol Session / Connection capacity**, not on the request rows.
3. *(optional)* Under **Request metadata**, set a **keyspace** field `docId` (e.g. size
   1000 distinct docs) so ops spread across documents — this drives the per-doc routing.

## Part 3 — Configure the WS layer and per-doc ownership

**WS Layer (Connection Server):** **CONFIG** → **Connection capacity** — set
**Max connections / instance** `65000`, **Offered connections** to your active-editor
count, **Session protocol** `WebSocket`. Then declare the transport:
- **CONFIG → Protocol Session → Protocol** = `websocket` (session lifecycle:
  `protocolSessionsOpened`, flow-control window).
- On the **Editors → WS Layer** edge, set **Protocol = WebSocket**.
The op/cursor stream flows as typed requests over these held connections — one persistent
socket per editor, not a handshake per keystroke.

**Route by docId (single owner per doc):** the WS Layer → Session Server edge must be
**key-based / sticky by `docId`** so all connections for one doc land on that doc's owner.
Set the WS Layer **routing strategy → key-based (hash by `docId`)** (consistent-hash ring).
This is what makes "one owner per active doc" hold, which is what makes convergence
provable for the common case.

**Session Server:** stateless-looking microservice, but ownership is expressed by the
key-based routing above (sticky by docId). Optionally add a **leader-election** /
coordination node if you want to show owner election + failover explicitly.

## Part 4 — Configure durability (op log + snapshots)

**Op Log + Snapshots (NoSQL DB):** **CONFIG** → **Replication** → **Enable replication** ✓,
role **leader** (add a **follower** + leader→follower edge). The op log is append-only and
ordered; replication + failover is the "recover by replaying the log onto a new owner"
story. Keep **Session Server → Op Log** **synchronous** (append the ordered op before ACK).

> Note: full **op-log replay cost** (replay N ops since last snapshot) is modeled by the
> `logReplay` trait on the `event-sourcing-store` component type. If your palette build
> exposes an Event Sourcing store, use it here instead of NoSQL DB to get the measured
> replay-cost penalty; otherwise NoSQL DB is the honest durable-ordered-store stand-in and
> replay cost stays a justification point.

## Part 5 — Wire the edges

```
Editors          → WS Layer                    OP (baseRevision) · cursor · edge Protocol = WebSocket
WS Layer         → Session Server              route by docId (key-based, sticky)
Session Server   → Op Log + Snapshots          append ordered op (sync = durable before ACK)
Session Server   → Doc Metadata                authz check
Session Server   → WS Layer                    broadcast transformed op + ACK (return path)
```

## Part 6 — Run

Click **Run**.

### Expected result (what "correct" looks like)

| Metric | Where | Meaning |
|---|---|---|
| WS Layer connection utilization < 100% | WS Layer | connection tier sized for active editors |
| Session Server routing sticky by docId | WS Layer downstream split | all ops for a doc reach one owner |
| Op Log received ≈ op rate | Op Log + Snapshots | every op appended before ACK (durability) |
| `replicationLeaderPromotions` > 0 after a fault | Op Log | failover = replay log onto new owner |
| ACK latency includes the durable append | Session Server p95 | persist-before-ACK holds |
| Availability / errors | all | healthy |

To demonstrate **failover**: use the fault-injection UI (Settings → Chaos) to fail the
Op Log leader mid-run; the follower is promoted (`replicationLeaderPromotions`) and a
bounded `replica_failover_in_progress` window appears — "recover by replaying the log onto
a new owner."

---

## Variant — the REST snapshot/history channel (HTTPS, not real-time)

The API spec has a non-real-time surface: `GET /docs/{id}` (load snapshot + revision) and
`GET /docs/{id}/history` (version history). These are **request/response over HTTPS**, not
WebSocket frames — model them as a separate edge and path:

1. Wire **Editors → Session Server** (or an **API Gateway**) on a **second edge** with
   **Protocol = HTTPS**.
2. Add request rows with a real **Method**:
   - type `load-doc`, **Method `GET`**, Path `/docs/{id}` — reads the latest snapshot + replays the few ops since it.
   - type `get-history`, **Method `GET`**, Path `/docs/{id}/history`
3. Route them to **Op Log + Snapshots** for the read. These never touch the live op stream.

Same "one client, two transports" pattern as Chat: live ops over WebSocket to the WS Layer,
snapshot/history over HTTPS. The `type` decides the path; the edge decides the transport.

## Why it's built this way (gotchas)

- **One owner per doc is a routing property.** It comes from key-based / sticky routing by
  `docId` on the WS Layer, not from a single physical node. Sharding by docId keeps per-doc
  concurrency tiny, which is exactly why a single coordinating owner is cheap and makes
  "all clients converge" tractable.
- **Durability is an edge-order property.** Keep `Session Server → Op Log` **synchronous**
  so the op is appended before the author is ACKed.
- **Op log vs snapshot.** Snapshots bound replay cost; without them, opening a long-lived
  doc replays millions of ops. Model snapshots as the periodic materialized state (a
  justification point unless you use the `logReplay` event-sourcing store).
- **The connection tier is capacity-limited on held connections**, same as Chat — size it
  in the Connection capacity panel, not by RPS.

## Full reference topology (the canonical design)

### Nodes

| Node | Simulator component | Key config |
|---|---|---|
| Editors | **Traffic Source** | `op` 90% / `cursor` 10%; keyspace `docId` |
| WS Layer | **Connection Server** | `sim.connection` WebSocket; routing key-based by docId |
| Session Server | **API Server** | one owner per doc via sticky docId routing; OT transform (justify) |
| Op Log + Snapshots | **NoSQL DB** (or Event Sourcing store) | replication leader (+ follower); append-only, sync |
| Doc Metadata | **NoSQL DB** | owner/ACL/title; low-churn relational concern |

### The design decisions this topology makes gradeable

- **Per-doc single owner (measured):** key-based sticky routing by `docId` → every op for a
  doc reaches one owner; the downstream split shows the affinity.
- **Durable ordered op log (measured):** synchronous append before ACK; replication +
  **leader promotion on failover** (`replicationLeaderPromotions`) is the recovery story.
- **Connection tier (GAP 1, measured):** held-connection capacity for the WS layer.

### Where the reference is still justification (not simulated)

- **OT / CRDT convergence** — the correctness property (linearizability of concurrent edits)
  is deferred; the sim provides the *ordering path* (single owner + op log), and you argue
  the transform correctness. This is the one genuinely-deferred core of this design.
- **Sub-100ms remote-apply** is a latency NFR you can read off the broadcast path; the
  optimistic local apply is a client concern (justify).
- **Op-log replay cost** — measured only with the `logReplay` event-sourcing store; with a
  plain NoSQL DB it stays a justification point.

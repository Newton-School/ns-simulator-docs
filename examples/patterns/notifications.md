# Pattern — Notifications, generically (push / email / SMS)

A "notification service" is not a special primitive — it's a **composition of three
behaviors**, each of which the simulator already provides as a generic, placeable node. This
note is the reusable recipe: use it in Chat (offline push), News Feed ("X liked your post"),
or any design that fans a notification out to users through an external provider.

## The three behaviors → real palette nodes

| Behavior | Palette node(s) — exact search label | componentType | What it gives you |
|---|---|---|---|
| **Async decoupling** (buffer, fire-and-forget, off the hot path) | **Message Queue** · **Event Stream** | `queue` · `stream` | `asyncBoundary` — edges into it are forced async; the caller never blocks |
| **External provider call** (APNs / FCM / Twilio / SendGrid) | **External Service** *(or the upgraded **Notification Service**)* | `third-party-api-connector` *(or `push-notification-service`)* | **External Dependency** section: external-call latency + `externalCalls` counter; also a rate-limiter |
| **Fan-out to N recipients / devices** | edge **Fan-out factor** · or **Pub/Sub** / **Event Broker** | edge property · `pub-sub` / `message-broker` | 1 notification → N deliveries (`fanoutFactor`), or topic broadcast |
| *(optional)* **Provider resilience** | **API Server** (retry) · **Sidecar Proxy** / **Service Mesh** / **Circuit Breaker** | `microservice` · `sidecar` / `service-mesh` / `circuit-breaker-controller` | retry-backoff on the sender; circuit-break a flaky provider |

> **All of these exist in the simulator today.** Note two things: the external-call node's
> palette tile is **"External Service"** (subLabel "3rd Party API"), backed by
> `third-party-api-connector` — there is also an **"Output Sink"** tile on the same type, but
> "External Service" is the conventional label for an APNs/FCM/Twilio call. And `event-bus` /
> `webhook-gateway` / `payment-gateway` are *not* placeable, but their behavior is covered by
> **Pub/Sub** / **External Service** / **Event Broker**.

## Two equally-honest builds

**A · With the dedicated node (readable):**
```
… → Queue (buffer) → Notification Service          [External call latency + fanoutFactor = N devices]
```
The **Notification Service** node was upgraded to carry the External-Dependency latency, so
its name now matches what it simulates. Best when you want the diagram to literally say "push".

**B · Without the dedicated node (generic, more expressive):**
```
… → Message Queue → External Service (APNs/FCM)          [External call latency + rate-limit + fanoutFactor = N]
                     ▲
            (optional) Circuit Breaker / Sidecar in front for provider outages
```
Best when you want to show the mechanism — explicit buffering, external latency, rate limit,
retries, circuit breaking, and device fan-out — none of which are hidden inside a bundled box.

## How to wire it (either build)

1. **Decouple:** the upstream edge into the queue/notification node is **asynchronous**
   (auto-forced for `asyncBoundary` nodes, but set it explicitly for clarity).
2. **External latency:** select the push node → **CONFIG → External Dependency → External
   call latency** = `120` ms (round-trip to APNs/FCM). Watch the `externalCalls` counter.
3. **Device fan-out:** on the edge into the push node, set **Fan-out factor** = `3` (a user's
   devices) — one notification fans out to each device (`fanoutAmplifiedWrites`).
4. *(optional)* **Resilience:** front the provider with a **Circuit Breaker** /
   **Sidecar Proxy**, or make the sender an **API Server** with a retry trait, to model a
   slow/failing provider's blast radius.

## Reuse across designs

- **Chat — offline push:** `Offline Inbox (Message Queue) → External Service / Notification
  Service` with device `fanoutFactor`. (See `examples/chat/builder-walkthrough.md`.)
- **News Feed — "someone liked your post":** the same queue → provider → fan-out tier hangs
  off the write path.
- **Email / SMS:** identical shape; the provider is SendGrid / Twilio instead of APNs/FCM.
- **Topic broadcast to many subscribers:** put a **Pub/Sub** / **Event Broker** in front so
  one event fans out to every subscribed consumer, then the provider call.

## Honesty boundary

Measured: async decoupling, external-provider latency + `externalCalls`, device fan-out,
rate-limit, retries, circuit-breaking. **Not** modeled: real APNs/FCM token management,
provider-side quota/outage internals, or delivery receipts from the device — those stay
justification.

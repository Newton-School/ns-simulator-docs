# Production Embed Runtime & Origin Security

> **Theme:** Turn the iframe embed seam from a *preview/demo* handshake into a
> **host-controlled, origin-secured runtime** — so a real host (the Game
> Playground) can launch a question into the simulator and receive graded
> submissions without the simulator leaking data to, or trusting instructions
> from, any other page that happens to frame it.

This closes the security half of the "explicit, validated iframe origins"
follow-up from [doc 05](05-design-decisions-and-tradeoffs.md) (**D13**).

---

## 1. What this delivers

| Area | File | Change |
|------|------|--------|
| Outbound + origin logic | `src/renderer/src/utils/questionHostMessaging.ts` | Trusted-origin handshake, strict targeting, no `'*'` for sensitive messages |
| Inbound handling | `src/renderer/src/components/layout/WorkspaceLayout.tsx` | Validate `event.origin` before accepting a launch context; lock the trusted origin |

---

## 2. The two sides of the seam

An embedded question is a conversation between two windows over `postMessage`:

- **Host side** — `EmbeddedIframeQuestionPreview` (the embedder). It was already
  production-grade: it validates every inbound `event.origin` against the
  question's `allowedOrigins`, and it targets the iframe precisely when sending
  the launch context. Nothing needed to change here.
- **Iframe-app side** — `WorkspaceLayout` + `questionHostMessaging` (the
  simulator running inside the frame). This was the weak half and is what this
  work hardens.

```mermaid
sequenceDiagram
  participant Host as Host page (allowedOrigins)
  participant Sim as Simulator (iframe)
  Sim->>Host: ready  (bootstrap; content-less)
  Host->>Sim: launch-context @ sim origin  (QuestionPackage)
  Note over Sim: validate event.origin →<br/>lock trusted host origin
  Sim->>Host: submit / error @ trusted origin only
```

---

## 3. The problems that were fixed

1. **Outbound data leak.** `postQuestionHostMessage` used to target the referrer
   origin, or **`'*'`** when the referrer was unknown. Because `submit` carries
   the full grade (score, contract, attempt), a `'*'` target would broadcast a
   student's graded submission to *any* page framing the simulator.
2. **No inbound origin check.** `WorkspaceLayout` accepted a `launch-context` —
   i.e. an arbitrary `QuestionPackage` to load and grade — from **any** origin.
   Any page could inject content into the framed simulator.
3. **No notion of "who my host is."** The app never recorded the legitimate host,
   so it could not target replies or reject impostors.

---

## 4. The trusted-origin handshake

The fix introduces a **trusted host origin** that is established once and then
governs everything:

- The content-less `ready` bootstrap goes out first (the app doesn't yet know its
  host).
- When a **valid** `launch-context` arrives, its `event.origin` is validated (see
  §5) and then **locked in** as the trusted host origin
  (`rememberTrustedHostOrigin`).
- From that point on, **every inbound message must match** the trusted origin,
  and **every sensitive outbound message targets exactly it**.

Locking happens once (first write wins), so a later message from a different
origin can neither hijack the trust nor receive replies.

---

## 5. Origin trust policy — configured allowlist, else trust-on-first-use

How does the iframe decide which parent origin is a legitimate host? A **hybrid**
policy (the pure logic lives in `isHostOriginAllowed`):

- **Configured allowlist (strict).** If the host sets `?hostOrigin=<origin(s)>`
  on the iframe `src` (comma-separated), only those origins are ever accepted —
  a previously trusted origin cannot override it. This is the production posture.
- **Trust-on-first-use (fallback).** With no configuration, the origin of the
  first valid `launch-context` is trusted and locked; afterwards only that origin
  passes. This keeps the existing preview/demo flow working with zero config.

Why hybrid rather than strict-only: it is **backward compatible** (the preview
needs no config) while letting production deployments opt into the stricter,
declarative allowlist. Defense-in-depth: the host *also* validates the iframe's
origin on its end, so both directions are checked.

---

## 6. Message targeting policy

The target for each outbound message is computed by the pure
`computeHostTargetOrigin`:

| Message | Carries data? | Target |
|---------|---------------|--------|
| `submit` | **Yes** (grade + attempt) | Trusted origin **only** — dropped (with a warning) if none is established |
| `error` | Some (a message string) | Trusted origin **only** |
| `ready` | No (content-less bootstrap) | Trusted → single configured → referrer → `'*'` |

The crucial rule: **sensitive messages are never broadcast.** `'*'` survives
*only* for the `ready` bootstrap, which contains nothing but a handshake signal —
and even then only as the last resort so the initial connection can form. In
practice `submit`/`error` always follow a `launch-context`, so the trusted origin
is already set by the time they fire.

---

## 7. Why the logic is split into pure functions

`isHostOriginAllowed` and `computeHostTargetOrigin` take their inputs
(`configured`, `trusted`, `referrer`) as plain arguments rather than reading
`window`/`document` directly. That makes the security-critical decisions **unit
testable without a DOM** — the tests assert the allowlist/TOFU matrix and the
targeting matrix directly. The thin runtime wrappers (`isAllowedHostOrigin`,
`postQuestionHostMessage`) just gather the window state and delegate. Same
"push side effects to the edge, keep the decision pure" principle used elsewhere
in the platform.

---

## 8. What is intentionally *not* done yet

- **Host-driven lifecycle commands.** The host can launch and receive results,
  but there is no inbound `reset` / `lock` / `reveal` command set for the host to
  drive the attempt lifecycle mid-session. That pairs naturally with the
  still-unbuilt `EnvironmentProfile` layer.
- **Frame sandboxing / CSP.** Origin trust is enforced at the message layer;
  `sandbox` attributes and a `frame-ancestors` CSP on the host are complementary
  and out of scope here.
- **`referrerPolicy` coupling.** The `ready` bootstrap's referrer fallback
  depends on the referrer being present; a strict `referrerPolicy` on the host
  would force use of the `?hostOrigin=` param. Documented, not yet enforced.

---

## 9. Design decisions & trade-offs

Logged in [doc 05](05-design-decisions-and-tradeoffs.md) as **D20–D22**.

| # | Decision | Criteria | Trade-off |
|---|----------|----------|-----------|
| **D20** | Hybrid origin trust: configured allowlist, else TOFU | Isolation, Shippability | TOFU alone can be raced by a page that sends a launch-context first; the `?hostOrigin=` param removes that risk |
| **D21** | Never broadcast sensitive messages; `'*'` only for content-less `ready` | Isolation, Honesty | If no host origin is ever established, `submit`/`error` are dropped rather than leaked |
| **D22** | Lock the trusted origin once (first valid launch wins) | Isolation | A legitimate host-origin change mid-session would require a reload |

---

## 10. What to take away

1. **A framed app must know, and verify, who its host is** — before accepting
   instructions or sending data.
2. **`postMessage` `targetOrigin` is a security control, not a formality.** `'*'`
   on a message that carries data is a data leak.
3. **Validate both directions.** The host checks the iframe; the iframe checks the
   host.
4. **Keep security decisions pure and tested.** The allow/target matrices are
   plain functions with exhaustive unit tests.

**Related:** [doc 05 — Design Decisions](05-design-decisions-and-tradeoffs.md)
(D13, D20–D22), and [doc 01 §7](01-pr212-question-platform-foundation.md) for the
original embed seam.

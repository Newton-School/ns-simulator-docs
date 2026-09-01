# Rate-Limiter Lab Lesson

Date: 2026-09-01

Instructor/author-facing. This is the staged lab for "Design a Rate Limiter"
(Alex Xu vol. 1, ch. 4). It is a **lab, not a single graded question**, because
the chapter is a sequence of contrasts (five algorithms, each with a distinct
failure mode, plus a distributed bug) — that is a curriculum, not one verdict.
A lone graded question would promise "design a rate limiter" while the rubric
could only check "did you centralize the counter," which is under-constrained by
construction.

Each stage is one small beat: build → graded or justified → next. Stages 1–3
and the capstone are graded; stages 4–5 are simulate-and-justify.

## What is gradeable (settled)

Backed by the rate-limiter admission & breach model
(`specs/rate-limiter-admission-and-breach-model.md`):

- placement (limiter on the path) — **T**
- counter store is a shared in-memory store, not a per-instance local store and
  not a relational DB — **T / S**
- the store does not saturate under load — **Σ**
- the **synchronization bug** (uncoordinated local counters over-admit) →
  `rateLimit.breaches == 0` — **Σ**
- the **fixed-window edge-doubling bug** → same `rateLimit.breaches` metric under
  an edge-straddling burst — **Σ**
- no over-provisioning — **$**

## What stays justify/narrative (do not fake)

- which algorithm by *name* (token vs leaking vs sliding) — **J** (graded by
  consequence in stage 4, never by the name)
- the literal read-modify-write interleaving — **J/N** (insight is covered by the
  breach oracle; the byte-level race is not simulated — see the model doc §3)
- 429 status, `X-RateLimit-*` headers, Lyft rule format — **N**

Refuse the tempting proxy ("require a node named `lua-script`"). It grades
vocabulary, not design, and mis-grades a correct design that uses a different
mechanism.

---

## Stage 1 — Placement (graded T)

**Prompt.** Requests must pass a rate-limit check before reaching the API
servers. Build the path. Client-side limiting is rejected (forgeable).

**Build.** `client → rate-limiter → api-server` (or the limiter inside an
`api-gateway`).

**Graded.**
```
STRUCTURAL_RULE  requires_component  rate-limiter
STRUCTURAL_RULE  requires_single_source
SEMANTIC_CRITERION  guardedPath  { from: client, guard: rate-limiter, to: api-server }   # all traffic passes the limiter
```

Trivial on purpose — it builds confidence and establishes the spine.

## Stage 2 — Where the counter lives (graded S + Σ)

**Prompt.** The limiter needs a counter per client. Put it somewhere that
survives at 10K rps and is fast. A relational DB on the counter path is the
wrong answer.

**Build.** limiter → shared in-memory store (`kv-store` / `in-memory-cache`),
not a `relational-db`.

**Graded.**
```
SEMANTIC_CRITERION  storageFit  { accessPattern: point-lookup, accept: [in-memory-cache, kv-store], antiPattern: [relational-db], points: 3, hardFail: true }
RUBRIC_CHECK  simulation  metric: <counter-store>.utilization  op: <  value: 0.85   # store does not saturate
```

The Σ check lets you *show* the DB path's p99 blow up instead of asserting it —
more convincing than prose.

## Stage 3 — The synchronization bug (graded Σ, the capstone) 

**Prompt.** Two rate-limiter instances sit behind a stateless tier; a client can
hit either. High concurrency, one hot client. Design so the client cannot exceed
the global limit.

This is the deep, gradeable idea, and it is the **capstone** (see below). The
wrong answer (two limiters, each with a local counter) lets the client through
twice; the right answer funnels one key through one authority.

## Stage 4 — Algorithms, graded by consequence (Σ + justify)

**Prompt.** Pick an admission algorithm for a burst-tolerant endpoint (flash
sale). Then a second scenario demands a strict cap with no edge overshoot.

Do **not** grade the name. Configure the limiter with `limit` + `windowMs` +
`rateLimitKeyField`, and inject traffic that *exposes the consequence*:

- **Strict-cap scenario** — a burst straddling a window boundary. `fixed-window`
  admits up to 2× → `rateLimit.breaches > 0` → **fails**. `sliding-window` →
  `breaches == 0` → **passes**. The student learns *why* fixed-window is wrong by
  watching the number, not by memorizing it.
- **Burst-tolerant scenario** — a scenario where short bursts should pass;
  an over-strict config drops legitimate load (Σ throughput/drop check).

```
RUBRIC_CHECK  simulation  metric: rateLimit.breaches  op: ==  value: 0     # strict-cap case
```

**Justify (in-app, deterministic gate).** "Which algorithm and why; tie it to the
burst number in the prompt; state the tradeoff." Graph-consistency + number +
tradeoff gates apply.

## Stage 5 — The race condition (simulate-and-justify, ungraded)

**Prompt.** Reproduce the chapter's read-check-increment interleaving (Fig.
4-14): two requests read the same counter before either writes. What makes the
increment atomic (Lua script / Redis sorted set), and what does it cost?

The literal RMW is not simulated (model doc §3), so this stage is narrative +
justify. Its insight is already graded upstream by `rateLimit.breaches` in
stages 3–4; here the student names the atomicity mechanism and its tradeoff.

---

## The capstone question (stage 3, fully authored)

**Contract.** `limit` = N per client per `windowMs`; one hot client key; injected
burst above the limit.

**Reference topology (passes).** All traffic for a key funnels through a single
rate-limiter authority (sliding-window) backed by one shared counter store.
→ global rolling admits ≤ N → `rateLimit.breaches == 0`.

**Gamed topology 1 (must fail).** Two parallel rate-limiter nodes, each with its
own local counter, both receiving the hot key. Each is individually "correct"
(≤ N in its own state) but the global rolling count reaches 2N →
`rateLimit.breaches > 0`. This is the sticky-session / local-state anti-pattern.

**Gamed topology 2 (must fail).** One fixed-window limiter, edge-straddling
burst → 2× at the boundary → `rateLimit.breaches > 0`.

**Gamed topology 3 (must fail).** Counter in a relational DB → `storageFit`
hard-fail; and/or the store saturates → Σ.

**Rows.**
```
SIMULATOR_CONFIG    { budget: { unit: nodes, cap: 8 } }
STRUCTURAL_RULE     requires_component  rate-limiter
SEMANTIC_CRITERION  guardedPath  { from: client, guard: rate-limiter, to: api-server }
SEMANTIC_CRITERION  storageFit   { accessPattern: point-lookup, accept: [in-memory-cache, kv-store], antiPattern: [relational-db], hardFail: true }
RUBRIC_CHECK        simulation   metric: rateLimit.breaches  op: ==  value: 0   points: 4
RUBRIC_CHECK        simulation   metric: summary.latency.p99 op: <   value: <slo>
```

**Workload (the contended key).**
```
suite.cases[].workload.requestDistribution[] = [
  { type: "read", weight: 1, sizeBytes: 256, keyspace: { field: "clientId", size: 5 } }
]
```
with `rateLimitKeyField: "clientId"` on the limiter and `baseRps` set well above
`limit / windowMs` so the hot key is actually pushed past the cap. A small
`keyspace.size` concentrates traffic on few clients so contention is real.

**Dual-Topology check.** Reference `breaches == 0` PASS; all three gamed
topologies FAIL on their intended signal. This is the executable definition of a
valid question — do not ship the capstone until all four run this way.

## Delivery

- Engineers (full): stages 1–5 + capstone build.
- Content authors (fast): stages 1–3 + capstone; stages 4–5 as reading.
- The capstone (stage 3) can also stand alone as a single graded question for a
  quiz, at the cost of teaching only the synchronization idea.

## Code / spec map

- Engine model + metric: `specs/rate-limiter-admission-and-breach-model.md`
  (`rateLimit.breaches`, `src/engine/traits/rateLimiter.ts`)
- Contended-key workload primitive: `specs/contended-inventory-and-oversell-model.md`
- DSL row reference: `specs/evaluation-authoring-reference-manual.md`, `specs/test-case-catalog.md`
- Grading axes: `LECTURE-MASTERCLASS.md` §13, §16

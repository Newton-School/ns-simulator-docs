# ns-simulator - V1 Scope vs. Future Roadmap

> For the team. This is the line between what we are shipping in **stable-v1** and
> what is explicitly deferred. If a capability is not listed under "V1 ships", treat
> it as out of scope for launch.

## The one-sentence framing

**V1 is a discrete-event *physics* sandbox with a *deterministic* grading loop.** A
student places and sizes infrastructure, runs a simulation under an
instructor-defined load, reads the bottlenecks, and iterates until the design meets
measurable targets (latency, throughput, error rate) and structural rules. Anything
that requires *understanding prose* or *modeling application logic* is deferred.

---

## V1 ships

### Core physics engine
- Discrete-event simulation of a node/edge graph: queueing, worker pools, service
  time distributions, edge latency/bandwidth, packet loss, timeouts, retries.
- Per-node metrics: throughput, utilization, arrived/completed/rejected/timed-out,
  p50/p95/p99 latency, availability, error rate.
- Saturation and bottleneck surfacing in the Run Inspector.
- Deterministic seeds - the same topology + workload always produces the same result.

### Nodes & edges (the buildable graph)
- A component catalog spanning compute, network/edge, storage, messaging,
  coordination, and auxiliary types, each with `queue` (workers/capacity/discipline)
  and `processing` (distribution/timeout) config.
- Edges with `mode` (synchronous / asynchronous / streaming / conditional),
  protocol, latency profile, and **type-conditional routing**
  (`request.type === "read"`).
- **Traffic originates from a Client (source) node only.** Load balancers and other
  routers are not valid sources.

### Workload
- Instructor-owned injected load: `baseRps`, arrival pattern (constant / poisson /
  bursty / spike), and a typed `requestDistribution` (e.g. 99% read / 1% write).
- Tractable in-browser scale (~2,000-5,000 rps) that stands in for the real-world
  display scale in the prompt.

### Grading loop (question mode)
- **Structural rules** - required components, required edges, single source,
  connectivity, max counts.
- **Semantic criteria** - `storageFit`, `placement`, `guardedPath`, `fanout`,
  `forbidUnjustified` (all deterministic graph checks).
- **Simulation rubric** - checks over verdict metrics (`summary.latency.p99`,
  `summary.throughput`, `summary.errorRate`, `invariantViolations.count`).
- **Budget** - a live capacity-cost meter (anti-kitchen-sink), shown in the question
  brief with a per-node breakdown.
- **Dual-topology authoring** - every shipped question is validated so a reference
  design PASSES and a gamed design FAILS on the intended axis.

### Environment profiles
- `AUTHOR` (standalone / local / the public URL) - full UI, load a question and a
  solution topology side-by-side to test.
- `ASSIGNMENT` - graded, locked chrome, rubric hidden until submit.
- `PRACTICE` - self-paced with live rubric feedback.

### Delivery
- Runs client-side; the iframe posts pass/fail + topology to the host (Newton Game
  Playground). **No server-side grading in V1.**

---

## Deferred to future versions

| Area | V1 stance | Future (V2+) |
|------|-----------|--------------|
| **Justification / prose** | **Hidden.** The grader is a rigid keyword/number/tradeoff matcher, not an LLM, which produces confusing "inconsistent" feedback. Input boxes are hidden; `justify` is preserved as `_justify` in question files. | NLP/LLM-assisted grading of written design defenses (idempotency, 301 vs 302, base62, locking). |
| **Request model** | A request has `type`, `size`, `priority`, `path` only. | First-class request **body / endpoint / response codes**; richer payload semantics. |
| **Access patterns** | A grading-only concept on `storageFit`. | First-class access-pattern modeling on the canvas. |
| **Read/write mix** | JSON-only, injected by the question. | Editable on the canvas / source node; `readWriteRatio` auto-derivation. |
| **Advanced nodes** | Core physics nodes only. **Shipped since (October 2026):** telemetry sinks, held-connection fan-out on the Connection Server, change-stream ordering, cluster scheduling on a Kubernetes Cluster node, read consistency models. | Deep behavior for the rest of the long tail. |
| **Composite nodes** | Region/AZ/Subnet containment resolves edge path types. **Shipped since (October 2026):** fault domains - a fault on a Region / AZ / Subnet fails everything inside it, with an AZ outage chaos preset. | Partial zone degradation, partitions between live zones, cross-region replication lag. |
| **Cost model** | v1 capacity-cost heuristic (`1 + replicas + ⌈workers/50⌉` per node, +1/edge). | Real price-sheet cost model. |
| **Connection lint** | Structural errors surface on Run; no connect-time design lint. **Shipped since (October 2026):** drawing refuses traffic into a source, out of a sink and a second connection between the same pair (with the reason); a **Design checks** chip lists anti-patterns in the current topology (the same detector as `sim lint`). | Hints aimed at specific smells such as Client → DB directly. |
| **Grading location** | Client-only via iframe. | Optional server-side re-grade / anti-tamper. |

---

## What "done for V1" means
1. A student can build, run, read bottlenecks, and iterate to a passing design.
2. Every bank question discriminates (reference passes, gamed fails) - re-validated
   with `scripts/validate-question-dir.ts`.
3. No confusing dead-ends: the justification "guess-the-keyword" UX is hidden.
4. Structural errors are human-readable; Reset returns to a clean pre-run state.

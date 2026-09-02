# The Test-Case Authoring Handbook

*A ground-up guide to writing questions for the system-design simulator. Written
for someone seeing these terms for the first time — every word is defined before
it is used.*

Date: 2026-09-02

---

## How to read this handbook

This is a teaching document, not a reference card. It is meant to be read in
order the first time, like a textbook chapter. Each idea builds on the one
before it. When a new term appears in **bold**, that is its definition — the
place it is explained. Later sections assume you remember it.

There is a short reference table at the very end once you know the vocabulary.

---

# Part 1 — The mental model

## 1.1 What are we actually doing?

The simulator is a "LeetCode for system design." A student is given a problem
("design a URL shortener that stays fast under heavy read traffic"), and they
answer by **drawing a diagram** — boxes (databases, caches, servers) connected
by arrows. The simulator then decides whether that diagram is a good answer.

Your job as an **author** is to write the problem *and* the rules that decide
whether an answer is good. Those rules are what we call **test cases**.

Here is the key difference from LeetCode. In LeetCode, a test case is one input
and one expected output. Here, a "good answer" is not a single value — it is a
*shape* (the right components wired the right way) that also *behaves* correctly
when we push traffic through it. So our test cases come in a few different
flavors, one for each kind of thing we can check.

## 1.2 Two words you need immediately: topology and node

- A **node** is one box in the diagram — one component. A node has a **type**
  (like `relational-db`, `in-memory-cache`, `load-balancer`) which says what
  kind of component it is.
- A **topology** is the whole diagram: all the nodes plus all the arrows
  (**edges**) between them. When we say "the student's topology," we mean "the
  diagram they drew."

Almost every rule you write is a question about the topology ("is there a cache
between the service and the database?") or about what happens when traffic flows
through it ("does the p99 latency stay under 100ms?").

## 1.3 The one idea that makes grading honest

A diagram alone can't tell you if it's *fast*. So the simulator does two things:

1. **It looks at the shape** of the topology (pure inspection — no running).
2. **It runs a simulation** — it generates fake traffic, sends requests through
   the nodes, and measures what happens (latency, throughput, errors).

Some properties you can only judge by shape (#1). Some you can only judge by
running (#2). A good question knows which is which and never fakes one with the
other. This is the single most important principle in the whole system, and we
will come back to it constantly.

## 1.4 The five axes (and their symbols)

Everything you can grade falls into one of five **axes**. Think of an axis as a
"category of question you can ask about an answer." They have short symbols we
use throughout:

| Symbol | Axis | The question it asks | Judged by |
|:---:|---|---|---|
| **T** | **Topology** | Is the right *shape* present? (components, wiring) | Inspecting the diagram |
| **S** | **Scale-fit** | Did they pick components that *fit* the workload? | Inspecting the diagram + the stated scale |
| **Σ** | **Simulation** | Does it *behave* under load? (latency, throughput, correctness signals) | Running the simulation |
| **J** | **Justification** | Can they *explain* the choice in words? | Grading free text |
| **$** | **Budget** | Did they stay within a cost / size limit? | Inspecting the diagram |

(Σ is the Greek letter "sigma" — we use it as shorthand for the simulation axis.)

A strong question touches **more than one axis**. If you grade only one axis, a
student can usually "game" it — satisfy that one check while getting everything
else wrong. We'll see concrete examples later.

---

# Part 2 — The four kinds of test-case row

You author a question in a system called Newton, as a list of **rows**. Each row
is a small piece of JSON (a block of `{ "key": value }` data). Every row has a
`type` field that says which of four kinds it is:

| Row `type` | What it does | Axis |
|---|---|:---:|
| `SIMULATOR_CONFIG` | Sets up the whole question: the prompt, the traffic to run, budget, limits. One per question. | (setup) |
| `STRUCTURAL_RULE` | A hard requirement about the diagram's shape. | T |
| `SEMANTIC_CRITERION` | A *smarter* shape or behavior check (placement, storage-fit, runtime state). | T / S / Σ |
| `RUBRIC_CHECK` | A measurement from the simulation run compared to a target. | Σ / $ |

> **A note on JSON.** Each row is *pure JSON* — no comments, no trailing text.
> A stray `//` comment or a note after the closing brace makes the row invalid,
> and it will be silently dropped. If a rule "isn't showing up," this is the
> first thing to check.

We'll take these one at a time. But first, the vocabulary they all share.

---

# Part 3 — The universal vocabulary (shared keys)

These keys appear across many row types. Learn them once here.

### `id`
A short unique name for this rule, like `"has-cache"`. It's how results are
labelled. Make it human-readable.

### `description`
A plain-English sentence shown to the student (or author) describing what this
rule checks. "A load balancer fronts the service."

### Keys that name a component: `componentType`, `fromType`, `toType`
A **component type** is the `type` string of a node — the token from the
component vocabulary (Part 8), like `relational-db` or `kv-store`. Several keys
take one of these:

- `componentType` — names *one* kind of component ("there must be a
  `load-balancer`").
- `fromType` / `toType` — name the *two ends* of an arrow ("there must be an
  edge **from** a `microservice` **to** a `relational-db`").

> **How the engine checks a component type.** It is literally a string-match on
> each node's `type` field. To answer "is there a KV store?", the engine runs
> `topology.nodes.some(node => node.type === "kv-store")`. There is no fuzzy
> matching — the node's type is either in your list or it isn't. This is exactly
> how storage-fit (Part 5) decides whether the datastore is a `kv-store` versus
> a `nosql-db`: it checks which of those exact type-strings appear among the
> nodes.

### `category`
Every component type belongs to a **category** — a family like `storage`,
`network-and-edge`, `compute`. A `category` key lets you require "some storage
component" without naming a specific one. Checked by counting how many nodes
fall in that category.

### Count / number keys: `minCount`, `maxCount`, `count`, `minReplicas`, `maxNodeCount`
Numbers that set thresholds. "At least 1" (`minCount: 1`), "at most 8 nodes"
(`maxNodeCount: 8`), "at least 3 replicas" (`minReplicas: 3`). Each rule
documents which it accepts.

### `points`
How many points this check is worth. Grading is weighted: a check worth
`points: 4` matters more than one worth `points: 1`. (More on weighting in Part
6.)

### `hardFail`
A boolean. If `true`, failing this check **zeroes the entire question** — no
matter how many other points were earned. Use it for non-negotiables ("the
answer used a relational DB for a pure key-value lookup — that's just wrong").

---

# Part 4 — STRUCTURAL_RULE (the T axis)

A **structural rule** is a hard requirement about the *shape* of the diagram. It
is pure inspection — no simulation runs. Each rule has a `kind` that selects
*what* is being required. Here is every kind, what it means, and **how the
engine actually checks it**.

### `requires_component`
"A node of this type must exist." → passes if any node has
`type === "load-balancer"`.

```json
{
  "type": "STRUCTURAL_RULE",
  "kind": "requires_component",
  "componentType": "load-balancer"
}
```

### `forbids_component`
"A node of this type must **not** exist." The opposite of the above — passes
only if the count is exactly 0.

```json
{
  "type": "STRUCTURAL_RULE",
  "kind": "forbids_component",
  "componentType": "in-memory-cache"
}
```

### `requires_category`
"At least `minCount` nodes from this category must exist."
Useful for "some kind of cache/store" without pinning the exact type.

```json
{
  "type": "STRUCTURAL_RULE",
  "kind": "requires_category",
  "category": "storage-and-data",
  "minCount": 1
}
```

### `requires_single_source`
"There must be **exactly one** source of traffic" — one client / entry node. A
**source node** is where requests originate (the client app). Passes only if the
count of source nodes is exactly 1 (not 0, not 2). This stops a student drawing
two disconnected entry points.

```json
{
  "type": "STRUCTURAL_RULE",
  "kind": "requires_single_source"
}
```

### `requires_edge`
"There must be an arrow from a `fromType` node to a `toType` node." The engine
scans every edge, looks up the types of its two ends, and passes if any edge
goes from the right source type to the right target type. An optional `mode`
field can additionally require the edge be a `network` edge (real physics) vs a
`connector` (a plain wire).

```json
{
  "type": "STRUCTURAL_RULE",
  "kind": "requires_edge",
  "fromType": "rate-limiter",
  "toType": "in-memory-cache"
}
```

### `requires_path`
"Traffic from a `fromType` node can *reach* a `toType` node, following arrows in
their direction" — not necessarily directly, but through any chain of edges.
The engine builds a **directed adjacency** (who-points-to-whom) and does a
reachability search from all `fromType` nodes; passes if any `toType` node is
reachable. (Contrast with `requires_edge`, which demands a *direct* arrow.)

### `requires_connected_graph`
"The whole diagram is one connected piece — no island nodes." The engine treats
edges as undirected, starts from the first node, and walks everywhere it can
reach; if any node is left unvisited, it fails and names the disconnected ids.
*Careful:* a single node is trivially connected (passes). To force real wiring,
pair this with `min_node_count` or `requires_edge`.

### `requires_redundancy`
"Across all nodes of this type, there are at least `minReplicas` **instances**."
An instance is one running copy (a node can be configured to run N copies). This
checks resilience — "you need at least 3 copies of the API server."

### `min_node_count` / `max_node_count`
"The whole diagram has at least / at most N nodes total." A blunt size floor or
ceiling.

### `max_component_count`
"At most `maxCount` nodes of this specific type." E.g. "at most 1 database" to
force a shared store rather than one-DB-per-service.

---

# Part 5 — SEMANTIC_CRITERION (T, S, and Σ)

A **semantic criterion** is a *smarter* check. Where a structural rule asks "does
X exist?", a semantic criterion asks questions like "is X in the *right place*?"
or "did the right thing *happen at runtime*?" Each has a `kind`. There are two
groups: **graph-based** (inspect the shape) and **runtime** (read what happened
during the simulation).

## 5.1 Graph-based semantic criteria (T / S)

### `placement`
"Is this component in the correct *position* in the flow?" It has three optional
sub-checks:
- `between: [A, B]` — the component sits on a path *between* an A-type node and a
  B-type node. Checked by reachability: some A reaches it, and it reaches some B.
- `notBefore: X` — the component is **not** upstream of an X. (E.g. a cache must
  not sit before the load balancer.)
- `orderedPipeline: [T₁, T₂, T₃]` — traffic flows through these types *in order*;
  each stage must be able to reach the next.

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "placement",
  "componentType": "in-memory-cache",
  "between": ["microservice", "relational-db"],
  "points": 2
}
```

### `guardedPath` — the cleverest one
"**All** traffic from `from` to `to` must pass through a `guard`." Not "a path
exists through the guard" — *every* path. This is how you enforce "every write
must go through the lock" or "every request must pass the rate limiter."

> **How it checks (this is the trick).** First it confirms `to` is reachable
> from `from`. Then it **removes the guard nodes from the graph** and checks
> reachability again. If `to` is *still* reachable with the guard gone, that
> means a **bypass** exists — some path skips the guard — and the check
> **fails**. If removing the guard disconnects `from` from `to`, then every path
> must have gone through it, and the check **passes**.

Keys: `from` (a component type), `guard` (the component type that must be on
every path), `to` (optional target type).

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "guardedPath",
  "from": "api-endpoint",
  "guard": "idempotency-manager",
  "to": "relational-db",
  "points": 3,
  "hardFail": true
}
```

### `fanout`
"A **broker** hands each message to **N independent consumers**." Used for
pub/sub and event fan-out. The engine counts the distinct downstream targets of
each `broker`-type node and passes if any has at least `minConsumers`. An
optional `forbiddenBroker` catches the classic mistake of using a *queue* (which
delivers to *one* consumer) where a fan-out broadcast was needed.

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "fanout",
  "broker": "message-broker",
  "minConsumers": 2,
  "forbiddenBroker": "message-queue",
  "points": 3
}
```

### `storageFit` (the S axis) — "did they pick the right kind of store?"
This is the heart of scale-fit. The idea: different **access patterns** want
different databases. Keys:

- `accessPattern` — how the data is used. One of: `point-lookup` (get-by-key),
  `time-series` (append + range-by-time), `append-only-ledger` (immutable
  double-entry), `transactional-relational` (ACID + joins), `search-index`
  (full-text), `blob` (large objects).
- `accept` — a list of component types that are a **good** fit. Full points.
- `partial` — types that are a **defensible but suboptimal** fit. Half points.
- `antiPattern` — types that are the **wrong** tool. Fail (and usually
  `hardFail: true`).

> **How it checks.** It looks at which store types are present in the topology
> (again, exact `node.type` matching). If any `antiPattern` type is present → it
> fails immediately ("you used a `relational-db` for a pure key-value lookup").
> Else if any `accept` type is present → pass. Else if any `partial` type is
> present → partial. Else → fail (no suitable store at all). So the concrete
> answer to "how does it know if the DB is a KV store or a NoSQL DB?" — it reads
> each node's `type` string and checks list membership. Nothing more magical.

- `accept` = "good"  ·  `partial` = "okay"  ·  `antiPattern` = "wrong."

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "storageFit",
  "accessPattern": "point-lookup",
  "accept": ["kv-store", "nosql-db"],
  "partial": ["in-memory-cache"],
  "antiPattern": ["relational-db"],
  "points": 3,
  "hardFail": true
}
```

### `forbidUnjustified`
"This component may only be present if the student *defended* it in words." If
the component type is absent → pass. If present → it passes only if the bound
justification prompt (Part 7) was answered well. This stops "kitchen-sink"
designs where a student adds a fancy component with no reason.

## 5.2 Runtime semantic criteria (the Σ axis) — grading what *happened*

These read the **state timeline** — a record of the states each request passed
through while the simulation ran (see Part 9 on state machines). They let you
grade *behavior* that pure shape can't show, like "no seat was ever
double-booked."

### `stateTransition`
"Count how many times a particular runtime event happened, and require it be
within a range." Keys: `match` (which event, see below), `minCount` (at least),
`maxCount` (at most). The most powerful pattern is the **absence check**:
`minCount: 0, maxCount: 0` means "this must **never** happen."

Example — the no-double-book rule ("the `oversold` state must never occur"):

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "stateTransition",
  "match": { "scope": "reservation", "state": "oversold" },
  "maxCount": 0,
  "hardFail": true
}
```

### `stateSequence`
"A particular *ordered sequence* of events must appear within a single request's
timeline." E.g. a lock must go `acquired → released` in that order.

### The `match` object (used by both)
- `scope` — which subsystem's state machine. One of: `request`, `delivery`,
  `broker`, `replication`, `protocol`, `idempotency`, `commit-outcome`, `lock`,
  `reservation`.
- `state` — a specific state within that scope. (E.g. scope `reservation` has
  states `committed`, `sold-out`, `oversold`, `key-missing`.)
- Optional narrowing: `nodeId`, `nodeType`, `source`, `reasonCode`.

### The `where` filter (optional)
Restricts *which requests* are eligible before counting: `caseId` (only one test
scenario), `outcomeStatus`, `terminalNodeType`, etc.

Full scope→state tables live in `runtime-semantic-criteria.md`.

---

# Part 6 — RUBRIC_CHECK (Σ and $) and grading weight

A **rubric check** compares a **measurement from the simulation run** against a
target. This is the axis that proves the design actually *performs*.

Every rubric check is a little sentence: **metric `op` value**.

- `metric` — *what* to measure. A dotted path into the run's results (the
  **verdict**), like `summary.latency.p99`.
- `op` — the comparison: `<`, `<=`, `>`, `>=`, `==`, `!=`.
- `value` — the number to compare against.
- `points`, `hardFail` — as in Part 3.
- `kind` — `simulation` (a measured metric), `invariant` (a safety violation
  count), or `topology` (a shape count that needs no run).

Example — "p99 latency under 100ms, worth 3 points":

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 100,
  "points": 3
}
```

> **How a metric resolves.** The engine keeps a **verdict** object after each
> run. Some metric names are special (`invariantViolations.count`,
> `perNode.maxUtilization`), but most simply walk the dotted path into the
> verdict object — `getByPath(verdict, "summary.latency.p99")`. If the path
> doesn't resolve to a finite number, the check silently fails. So a typo like
> `summary.latencyP99Ms` grades as a fail — always use the exact keys.

### The metric catalog (the ones you'll use most)
- **Latency:** `summary.latency.p50` · `.p90` · `.p95` · `.p99` · `.mean` · `.max`
- **Throughput / errors:** `summary.throughput` · `summary.errorRate`
- **Per-node worst case:** `perNode.maxUtilization` · `perNode.maxLatencyP99`
- **Correctness (run-wide):** `reservations.oversells` · `locks.contentions` ·
  `rateLimit.breaches` · `retries.attempts`
- **Safety:** `invariantViolations.count` · `sloBreaches.count`
- **Shape (no run):** `topology.nodeCount` · `topology.componentCounts.<type>`

### Grading weight and `passThreshold`
Each check contributes its `points` if it passes (semantic criteria give half
points on a "partial"). The question's total score is
`earned ÷ possible`. The question **passes** if that fraction meets the
`passThreshold` (set in `SIMULATOR_CONFIG.rubric.passThreshold`). A threshold is
a *fraction* between 0 and 1 — `0.71` means "71% of the points." A single
`hardFail` failure zeroes everything regardless of the fraction.

---

# Part 7 — SIMULATOR_CONFIG (the setup row)

One special row sets up the whole question. Its important keys:

### `presentation` — the prompt the student reads
Contains the problem statement and the numbers. Sub-parts:
- **FR (Functional Requirements)** — *what the system must do.* "Create a short
  code; redirect a short code." Each FR should map to some structure you then
  require.
- **NFR (Non-Functional Requirements)** — *how well it must do it.* Measurable
  targets like "p99 redirect latency < 100ms." Each perf-NFR should map to a
  `RUBRIC_CHECK`.
- **scale** — the numbers that define the problem's size: users, requests per
  second (RPS), read:write ratio, data volume. Scale drives both the injected
  traffic and the storage-fit judgement.

### `scaffold` — the starting diagram
What the student begins with. `{ "type": "empty" }` = a blank canvas.
Alternatively a pre-placed partial diagram they extend.

### `constraints` — what the student may change
Booleans like `canModifyScaffold` and `canRemoveScaffoldNodes`, plus
`maxNodeCount`. These fence the answer space. (Both booleans are required
together.)

### `suite` — the traffic scenarios to run
A **suite** is a set of **cases**. Each **case** is one scenario with its own
**workload** (see Part 11). Running a case produces the measurements your rubric
checks read. A suite can have several cases (e.g. "normal load" and "peak
burst").

### `budget` (the $ axis)
A spending or size cap: `{ "unit": "cost", "cap": 5 }` (USD/hour), or `nodes`, or
`edges`. Going over fails the budget check. This is the anti-kitchen-sink lever —
it stops students from over-provisioning their way past a bottleneck.

### `rubric`
Holds `passThreshold` (Part 6) and an `id`.

### `environmentProfile` — the mode the question runs in
Controls *what the student sees and may do*: whether the prompt is visible,
whether metrics show live, whether they can trigger test runs, whether edges use
real network physics or plain connectors. Three broad modes exist (AUTHOR,
ASSIGNMENT, PRACTICE) with different **capabilities** (the knobs each mode sets).

### A whole SIMULATOR_CONFIG row, put together

```json
{
  "type": "SIMULATOR_CONFIG",
  "presentation": {
    "text": "Design a URL shortener that stays fast under a read-heavy load.",
    "scale": { "peakRps": 200000, "readWriteRatio": 99 }
  },
  "scaffold": { "type": "empty" },
  "constraints": {
    "canModifyScaffold": true,
    "canRemoveScaffoldNodes": true,
    "maxNodeCount": 12
  },
  "budget": { "unit": "nodes", "cap": 8 },
  "rubric": { "id": "url-shortener-rubric", "passThreshold": 0.71 },
  "suite": {
    "name": "url-shortener-suite",
    "visibleToStudent": false,
    "cases": [
      {
        "id": "peak",
        "workload": {
          "baseRps": 2000,
          "requestDistribution": [
            { "type": "read", "weight": 0.99, "sizeBytes": 256 },
            { "type": "write", "weight": 0.01, "sizeBytes": 512 }
          ]
        }
      }
    ]
  }
}
```

---

# Part 8 — The component vocabulary

The tokens you put in `componentType` / `fromType` / `accept` etc. are node
**type** strings. A few you'll reach for constantly:

- **Compute:** `microservice` (API server), `serverless-function`, `batch-worker`
- **Storage:** `relational-db`, `nosql-db`, `kv-store`, `in-memory-cache`,
  `object-storage`, `search-index`, `time-series-db`
- **Network & edge:** `load-balancer` (`load-balancer-l4` / `load-balancer-l7`),
  `api-gateway`, `cdn`, `reverse-proxy`
- **Messaging:** `queue`, `message-broker`, `pub-sub`, `stream`
- **Coordination:** `rate-limiter`, `distributed-lock`, `reservation-store`,
  `idempotency-manager`, `circuit-breaker-controller`

The full list lives in `test-case-catalog.md` §6.

## 8.1 Capability-carrying types

Some node types don't just sit there — placing them turns on a **capability**
(also called a **trait**): a little behavior that runs during simulation and
produces measurable signals. Examples:

- `reservation-store` → atomic per-key reserve; emits `reservations.oversells`.
- `rate-limiter` → keyed admission control; emits `rateLimit.breaches`.
- `relational-db` / `nosql-db` with replication enabled → quorum writes, leader
  failover; emits `replication`-scope states.
- `stream` → partitioned broker; consumer groups, offsets, retention.

This is what lets a *correctness* lesson (like "no double-booking") be graded by
a real runtime number instead of only by prose. Which brings us to the two ideas
that make that possible.

---

# Part 9 — Two concepts: the state machine and the distributed layer

### What is a state machine?
A **state machine** is a model of something that is always in exactly one of a
small, fixed set of **states**, and moves between them only through defined
**transitions**. A turnstile is `Locked ⇄ Unlocked`. Nothing in between.

In the simulator, every request walks a state machine as it's processed:
`generated → admitted → queued → processing → completed` (or `→ rejected`).
Special components add their own little state machines on top — a reservation is
`committed` / `sold-out` / `oversold`; a lock is `acquired → held → released` or
`contended`.

Why this matters to you: because behavior is a closed set of named states, you
can *grade* it. "The `oversold` state must never appear" is a precise, checkable
claim — that's exactly the `stateTransition` criterion from Part 5.

### What is the distributed(-systems) layer?
The simulator began by modelling one box under load (latency, throughput). The
**distributed layer** is the newer set of capabilities that model problems which
only exist *because multiple machines must coordinate*: replication and quorum,
streaming with consumer groups, protocol/session behavior, commit reconciliation.
These are built out of state machines that span several nodes, and their
transitions are what runtime criteria grade.

A worked trace of one such machine is in
`replication-quorum-state-machine-walkthrough.md`.

---

# Part 10 — Justification (the J axis)

Some things can't be simulated at all — *why* did you choose this? A
**justification** (`justify`) prompt asks the student to defend a decision in
free text, and grades it on three deterministic gates:

1. **Graph-consistency** — the answer must reference a component *actually in
   their diagram* (you can't write a great essay about a cache you never placed).
2. **Number-citation** — it must cite a real scale number from the prompt.
3. **Tradeoff** — it must name what is *given up* by the choice.

A prompt is **bound** to a decision via `boundTo` (a component type). An optional
LLM layer (Gemini / Claude / OpenAI) grades the same three gates with language
understanding, falling back to the deterministic version if unavailable.

```json
{
  "id": "why-store",
  "decision": "Why this store type for short-code lookups at 200K rps?",
  "boundTo": { "componentType": "kv-store" },
  "requires": { "choice": true, "number": true, "tradeoff": true }
}
```

> **The golden rule (the performance/correctness boundary).** *Performance* →
> the Σ axis (simulation). *Correctness* → topology + justification, **and**, only
> where a capability genuinely models it, a runtime criterion. **Never grade a
> correctness claim behind a latency number.** A fast p99 does not prove
> "exactly-once." Being honest about this boundary is what makes every green
> checkmark trustworthy.

---

# Part 11 — Workload: the traffic you run

A **workload** describes the fake traffic a case sends through the topology.

- **`workloadCategory`** — the dominant character: `read-heavy`, `write-heavy`,
  `connection-heavy`, `correctness-heavy`. An author-side label that helps pick
  the right axes.
- **`baseRps`** — requests per second to generate.
- **`requestDistribution`** — a list of request kinds with weights. E.g. 99%
  `read`, 1% `write`. This is how the read:write ratio *actually* changes where
  traffic goes (the mix only matters if edges route on it).
- **`keyspace`** — `{ "field": "seatId", "size": 40 }`. Stamps each request a key
  drawn from `size` distinct values. A **small** size under **high** RPS makes
  many requests fight over the same key — this is what creates the *contention*
  that reservation / lock / rate-limit questions need. Without it, there's no
  collision to detect.

A contended-key workload (the shape reservation / rate-limit questions need):

```json
{
  "baseRps": 1500,
  "requestDistribution": [
    {
      "type": "book",
      "weight": 1,
      "sizeBytes": 256,
      "keyspace": { "field": "seatId", "size": 40 }
    }
  ]
}
```

**Scale config** (in the prompt) sets the ambition; the **workload** (in the
suite case) is what actually runs. Keep them consistent: if the prompt says 200K
RPS but you inject 2K, grade against what you *inject*.

---

# Part 12 — How the pieces enforce good questions

### Anti-patterns and hard fails
An **anti-pattern** is a wrong choice you explicitly flag (in `storageFit`, or a
`forbids_component` rule). Mark the truly-wrong ones `hardFail: true` so a design
that makes that mistake scores zero regardless of the rest.

### Tradeoffs
Real design has no single right answer — it has tradeoffs. You handle them two
ways: `partial` lists in `storageFit` (defensible-but-suboptimal earns half
points), and `justify` prompts (the student must *name* the tradeoff).

### The Dual-Topology Rule (how you know a question is good)
A question is valid if and only if:
1. a **reference** (correct) topology **passes**, and
2. a known **gamed** (shortcut / wrong) topology **fails** — and fails on the
   axis you intended.

If both hold, your checks actually discriminate. If a gamed answer also passes,
your question is under-constrained — add a check on the axis it slipped through.
Build both diagrams and run them before shipping.

---

# Part 13 — Under the hood (for the curious)

### Schema validation
Before a question runs, it is validated against a strict schema (using a library
called zod). This catches missing required keys, bad enum values (e.g. an
`accessPattern` that isn't one of the six), pass-thresholds outside 0–1, and
dangling references (a criterion pointing at a `caseId` that doesn't exist).
Validation errors are reported with the exact path, like
`semanticCriteria[2].where.caseId`.

### Capabilities
"Capabilities" appear in two places: the `environmentProfile` capabilities (what
the *student* may do) and node capabilities/traits (what a *component* does at
runtime). Same word, two scopes — context tells you which.

### Verdict paths
The **verdict** is the structured result of a run. Rubric `metric` strings are
dotted paths into it (`summary.latency.p99`, `reservations.oversells`). If you
can name it in the metric catalog, it's a path in the verdict.

---

# Part 14 — Resources, concurrency, and cost

The last layer answers "how much machine did they buy, and does it hold up?"

- **Resources / instances** — a node can be sized: how much compute/RAM, and how
  many **instances** (running copies) it has. More instances = more parallelism
  and more cost.
- **Execution profile** — is the work `cpu-bound` (1 worker per core) or
  `io-bound` (many workers per core, waiting on I/O)? This changes how much
  concurrency each core gives.
- **Derived concurrency** — crucially, the number of parallel "servers" a node
  has is **derived** from its resources (vCPUs × instances × workers-per-core),
  *not* a free dial the student types. So you can't cheat a bottleneck by typing
  a big number — you have to buy the capacity, which costs money.
- **Service speed** — the instance family (bigger/faster machines) applies a
  speed multiplier to how fast each request is served.
- **Cost model** — each component has a price; the total is what the **budget**
  ($ axis) checks against. Only things the engine actually measures are billed,
  so cost stays honest.

The upshot for you: the **$ budget** and the **Σ simulation** axes work together.
A student can always make it fast by buying huge machines — until the budget
stops them. That tension is where the real design lesson lives.

---

# Part 15 — Putting it together (a tiny worked question)

**Problem:** a per-client rate limiter; each client capped at 100 req/s; two API
instances behind a stateless tier.

1. **SIMULATOR_CONFIG** — prompt (FR: limit per client; NFR: none strict; scale:
   1000 RPS, 100/client), `budget` 8 nodes, one suite case whose workload has
   `keyspace {field: clientId, size: 5}` and `baseRps: 1000`.
2. **STRUCTURAL_RULE** `requires_component` `rate-limiter` — the limiter exists (T).
3. **SEMANTIC_CRITERION** `guardedPath` `{from: client, guard: rate-limiter, to:
   api-server}` — *all* traffic passes it, no bypass (T).
4. **RUBRIC_CHECK** `simulation` `rateLimit.breaches == 0`, `hardFail: true` — the
   global limit is never exceeded (Σ).

The four rows, verbatim — this is the whole question:

```json
{
  "type": "SIMULATOR_CONFIG",
  "presentation": {
    "text": "Design a per-client rate limiter. Cap each client at 100 req/s. Two API instances sit behind a stateless tier.",
    "scale": { "peakRps": 1000, "perClientLimit": 100 }
  },
  "constraints": { "canModifyScaffold": true, "canRemoveScaffoldNodes": true, "maxNodeCount": 10 },
  "budget": { "unit": "nodes", "cap": 8 },
  "rubric": { "passThreshold": 1 },
  "suite": {
    "cases": [
      {
        "id": "hot-client-burst",
        "workload": {
          "baseRps": 1000,
          "requestDistribution": [
            { "type": "read", "weight": 1, "sizeBytes": 256, "keyspace": { "field": "clientId", "size": 5 } }
          ]
        }
      }
    ]
  }
}
```

```json
{
  "type": "STRUCTURAL_RULE",
  "kind": "requires_component",
  "componentType": "rate-limiter"
}
```

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "guardedPath",
  "from": "api-endpoint",
  "guard": "rate-limiter",
  "to": "microservice",
  "points": 2
}
```

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "metric": "rateLimit.breaches",
  "op": "==",
  "value": 0,
  "points": 4,
  "hardFail": true
}
```

**Reference** (one limiter, sliding-window, keyed on clientId) → 0 breaches →
passes. **Gamed** (two limiters each with a local counter) → the hot client gets
through both → breaches > 0 → fails. Dual-Topology satisfied. Ship it.

---

# Quick reference

| Row `type` | Key fields | Axis |
|---|---|:---:|
| `SIMULATOR_CONFIG` | presentation, scaffold, constraints, suite, budget, rubric, environmentProfile | setup |
| `STRUCTURAL_RULE` | kind, componentType/fromType/toType, count keys | T |
| `SEMANTIC_CRITERION` | kind (placement/guardedPath/fanout/storageFit/forbidUnjustified/stateTransition/stateSequence), points, hardFail | T/S/Σ |
| `RUBRIC_CHECK` | kind, metric, op, value, points, hardFail | Σ/$ |

**Axes:** T topology · S scale-fit · Σ simulation · J justification · $ budget.
**Golden rule:** performance→Σ, correctness→topology+justify (+runtime criteria
where modelled), never correctness behind a latency number.
**Ship test:** reference passes, gamed fails, on the intended axis.

*Deeper references: `evaluation-authoring-reference-manual.md` (the full DSL),
`test-case-catalog.md` (every row + component vocabulary),
`runtime-semantic-criteria.md` (scope→state tables),
`node-capability-matrix.md` (every trait).*

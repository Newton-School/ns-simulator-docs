# Test-Case Writing Exercise — Build a Question One Row at a Time

> **Audience.** Instructors authoring simulator questions.
> **Goal.** Learn the authoring method by growing one question from a single row to a
> full rubric, adding exactly one test case per step and seeing what each one buys.
> **Every row here is validated** — the final stacked package parses via
> `parseQuestionPackage`, a correct design passes, and a wrong design fails on the
> intended axis.

---

## The method

A question is not written in one pass. It is grown: **one row, one idea, one axis at
a time.** Each row is a *test case* — a single check. A question is done when a
correct design passes every row and every plausible cheat fails at least one.

Rows come in four kinds:

| Row kind | Graded on | Answers |
|----------|-----------|---------|
| `STRUCTURAL_RULE` | the graph shape (no sim) | is the right thing present / connected? |
| `SEMANTIC_CRITERION` | component *meaning* (no sim) | is it the right *kind* of thing? |
| `RUBRIC_CHECK` | verdict metrics (sim runs) | does it *behave* correctly under load? |
| `SIMULATOR_CONFIG` | — | boots the sandbox and injects the graded load |

Structural and semantic rows are cheap (they read the diagram). Rubric rows run the
simulation. Start with the cheap ones.

---

## Row 0 — the config (write once, then leave it)

Every question opens with one `SIMULATOR_CONFIG` row. It is boilerplate that boots a
locked sandbox and owns the injected load. Write it once; the exercise below only adds
grading rows after it.

```json
{
  "type": "SIMULATOR_CONFIG",
  "configVersion": "1.0",
  "questionId": "simple-web-service",
  "questionVersion": "1.0",
  "questionType": "open-build",
  "difficulty": "beginner",
  "workloadCategory": "read-heavy",
  "presentationMode": "raw-html",
  "promptSource": "question_text",
  "scaffold": { "type": "empty" },
  "constraints": {
    "canModifyScaffold": true,
    "canRemoveScaffoldNodes": true,
    "maxNodeCount": 12
  },
  "suite": {
    "name": "simple-web-service-suite",
    "visibleToStudent": false,
    "cases": [
      {
        "id": "peak",
        "description": "Read peak (injected)",
        "workload": {
          "baseRps": 1000,
          "requestDistribution": [
            { "type": "read", "weight": 1.0, "sizeBytes": 256 }
          ]
        }
      }
    ]
  },
  "rubric": { "id": "simple-web-service-rubric", "passThreshold": 1 },
  "environmentProfile": { "mode": "ASSIGNMENT", "graded": true }
}
```

> `suite.cases[].workload` is the load the question injects — the student cannot change
> it. You don't need to memorize the `constraints` booleans: if you write a partial
> `constraints` (or omit it), the simulator fills `canModifyScaffold` and
> `canRemoveScaffoldNodes` for you. Your values win where you set them.

### The smallest thing that loads

You only ever need **two rows** for a question to open: a `SIMULATOR_CONFIG` and **one**
`RUBRIC_CHECK`. If you're mid-authoring and haven't written a real rubric check yet, the
simulator injects a harmless always-passing one (`no-invariants`) automatically — so a
structural-only draft still opens. This is the minimum `SIMULATOR_CONFIG`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "my-question",
  "questionType": "open-build",
  "difficulty": "beginner",
  "scaffold": { "type": "empty" },
  "suite": {
    "name": "my-suite",
    "visibleToStudent": false,
    "cases": [ { "id": "smoke",
      "workload": { "baseRps": 100,
        "requestDistribution": [ { "type": "read", "weight": 1.0, "sizeBytes": 256 } ] } } ]
  },
  "rubric": { "id": "my-rubric", "passThreshold": 1 }
}
```

Add grading rows one at a time from there.

---

## Iteration 1 — one client

**Question text**

> Design a web service. Place the single client that sends all traffic into the system.

**The row**

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source",
  "description": "Exactly one client (traffic source)"
}
```

**Grades:** exactly one source node. Pass = one source. Fail = zero, or two+.
No simulation runs — this reads the diagram.

**Break it:** submit two clients → fails. Submit none → fails.

---

## Iteration 2 — traffic reaches a service

**Question text**

> The client sends read requests to a service that handles them. Add the service.

**The row**

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-service",
  "kind": "requires_component",
  "componentType": "microservice",
  "description": "A service must process requests"
}
```

**Grades:** at least one `microservice` node is present.

**Break it:** a client wired to nothing but a store, with no service → fails.

---

## Iteration 3 — the service reaches a durable store

**Question text**

> The service resolves each request from a durable store. Connect the service to a store.

**The row**

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "reaches-store",
  "kind": "requires_path",
  "fromType": "microservice",
  "toType": "kv-store",
  "description": "Requests must reach a durable store"
}
```

**Grades:** a directed path exists from a `microservice` to a `kv-store`.

**Break it:** a service that answers from memory with no store on the path → fails.

> Note: `requires_path` names concrete component types. If you want to accept several
> store types, either widen the lesson with a semantic row (Iteration 4) or add one
> `requires_path` per acceptable store.

---

## Iteration 4 — the *right kind* of store

**Question text**

> Requests are point lookups by key. Choose a store built for key lookups, not a
> relational database doing full scans.

**The row**

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "store-fit",
  "kind": "storageFit",
  "description": "Point lookup by key",
  "accessPattern": "point-lookup",
  "accept": ["kv-store", "nosql-db"],
  "antiPattern": ["relational-db"],
  "points": 3,
  "hardFail": true
}
```

**Grades:** the store type fits a point-lookup workload. `accept` = full credit,
`antiPattern` = zero, `hardFail: true` = picking the trap zeroes the whole question.

**Break it:** a `relational-db` as the store → hard-fails with
*"relational-db is an anti-pattern for a point-lookup workload."* This is the first row
that catches a design that is *structurally* fine but *semantically* wrong.

> `accessPattern` must be one of the shipped values: `point-lookup`, `time-series`,
> `append-only-ledger`, `transactional-relational`, `search-index`, `blob`. It labels
> the failure message; grading is decided by the `accept` / `antiPattern` type lists.

---

## Iteration 5 — it has to perform

**Question text**

> Read p99 latency must stay under 100 ms at peak load.

**The row**

```json
{
  "type": "RUBRIC_CHECK",
  "id": "p99",
  "kind": "simulation",
  "description": "Read p99 under 100 ms",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 100,
  "points": 3
}
```

**Grades:** the injected load runs, and the measured p99 must be `< 100`. This is the
first row that needs a simulation — under-size the store and the queue backs up, p99
climbs, the row goes red.

**Break it:** one tiny store instance serving 1000 rps → p99 blows past 100 → fails.

> Use exact verdict metric keys. `summary.latency.p99` is correct;
> `summary.latencyP99Ms` does not resolve and the check silently fails. The full metric
> list is in `evaluation-authoring-reference-manual.md`.

---

## The finished question (all rows stacked)

After Row 0, the grading rows are, in order:

1. `STRUCTURAL_RULE` single-source — one client
2. `STRUCTURAL_RULE` has-service — a service exists
3. `STRUCTURAL_RULE` reaches-store — service → store path
4. `SEMANTIC_CRITERION` store-fit — the right store, hard-fail on the trap
5. `RUBRIC_CHECK` p99 — performs under load

**Validated outcome** (graded through the engine):

| Design | structural | semantic | rubric | verdict |
|--------|-----------|----------|--------|---------|
| client → service → **kv-store**, sized for load | ✓ | ✓ | p99 ✓ | **PASS** |
| client → service → **relational-db** | ✓ | **hard-fail** | (zeroed) | **FAIL** |

The wrong design is structurally valid — it has a client, a service, and a path to a
store. It fails only because the store is the wrong *kind*. That is the point of
stacking axes: each row catches a class of mistake the others cannot.

---

## If the preview won't load — error → fix

The simulator now shows an author-actionable message instead of a raw validator error.
Common ones and their one-line fix:

| Message you see | What to do |
|-----------------|-----------|
| "…missing the SIMULATOR_CONFIG test-case row" | Add a row whose `input` starts with `"type": "SIMULATOR_CONFIG"`, wired as a **test case** (not in `initial_game_state`). |
| "Add at least one RUBRIC_CHECK test-case row…" | Add one `RUBRIC_CHECK` row (or rely on the auto-injected `no-invariants` default). |
| "…passThreshold must be a fraction between 0 and 1…" | Change `passThreshold` to a fraction, e.g. `0.71`, not a point total. |
| "…suite… needs at least one case… workload…" | Give the `SIMULATOR_CONFIG` a `suite.cases[0].workload` with `baseRps` + `requestDistribution`. |
| "…accessPattern must be one of…" | Use a valid `storageFit` access pattern: `point-lookup`, `time-series`, `append-only-ledger`, `transactional-relational`, `search-index`, `blob`. |
| "…metric is not a recognized verdict key…" | Use an exact key like `summary.latency.p99`, `summary.errorRate`, `reservations.oversells`. |

Each message also prints the raw validator detail in parentheses if you need it.

## The authoring loop

For every question, repeat until it discriminates:

1. Write the next requirement as **one row** of the cheapest kind that can grade it
   (structural < semantic < simulation).
2. Grade a **correct** design → expect pass.
3. Grade the **laziest cheat** you can think of → expect fail on the row you just added.
4. If the cheat passes, the question is under-constrained — tighten or add a row.

A question that has not been graded both ways is not authored.

**Next:** for correctness lessons that a diagram cannot assert (no double-book, retry
amplification, lock contention), see the run-wide simulation metrics
`reservations.oversells`, `retries.*`, `locks.*` in
`evaluation-authoring-reference-manual.md`, and the worked build in
`contended-inventory-and-oversell-model.md`.

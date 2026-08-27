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

**Write only the essence.** Every field the simulator can derive, it fills for you —
so the whole `SIMULATOR_CONFIG` you need to type is:

```json
{
  "type": "SIMULATOR_CONFIG",
  "suite": { "cases": [ { "workload": { "baseRps": 1000,
    "requestDistribution": [ { "type": "read" } ] } } ] }
}
```

That's it. The suite `workload` is the only thing worth stating — it's the load the
question injects, and the student can't change it.

**What gets filled in automatically (don't type these):**

| You can omit | Default the simulator applies |
|--------------|-------------------------------|
| `questionId` | derived from the question title |
| `questionType`, `difficulty` | `open-build`, `intermediate` |
| `scaffold` | `{ "type": "empty" }` |
| `constraints` (or a partial one) | `canModifyScaffold` + `canRemoveScaffoldNodes` filled |
| `suite.name`, `suite.visibleToStudent` | `<id>-suite`, `false` |
| `cases[].id`, `cases[].description` | `peak` (then `case-2`…), none |
| `requestDistribution[].weight` | `1.0` (split evenly if several classes) |
| `requestDistribution[].sizeBytes` | `256` |
| `rubric.passThreshold` | pass if the point total is met |
| a rubric check, if you have none yet | a harmless always-passing `no-invariants` check |

Set any of these only when you want to override the default — your value always wins.

Add grading rows one at a time from there.

---

## Iteration 1 — one client

**Question text**

> Design a web service. Place the single client that sends all traffic into the system.

**The row**

```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_single_source" }
```

That's the whole row. `id` (`requires-single-source`) and a human `description`
("Exactly one traffic source") are derived for you — set them only to override.

**Grades:** exactly one source node. Pass = one source. Fail = zero, or two+.
No simulation runs — this reads the diagram.

**Break it:** submit two clients → fails. Submit none → fails.

---

## Iteration 2 — traffic reaches a service

**Question text**

> The client sends read requests to a service that handles them. Add the service.

**The row**

```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_component", "componentType": "microservice" }
```

**Grades:** at least one `microservice` node is present.

**Break it:** a client wired to nothing but a store, with no service → fails.

---

## Iteration 3 — the service reaches a durable store

**Question text**

> The service resolves each request from a durable store. Connect the service to a store.

**The row**

```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_path", "fromType": "microservice", "toType": "kv-store" }
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
  "kind": "storageFit",
  "accessPattern": "point-lookup",
  "accept": ["kv-store", "nosql-db"],
  "antiPattern": ["relational-db"],
  "hardFail": true
}
```

**Grades:** the store type fits a point-lookup workload. `accept` = full credit,
`antiPattern` = zero, `hardFail: true` = picking the trap zeroes the whole question.
(`id`, `description`, and `points` are derived — `points` defaults to 1; set it only if
this criterion should be worth more.)

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
{ "type": "RUBRIC_CHECK", "metric": "summary.latency.p99", "op": "<", "value": 100 }
```

`id` (`p99`), `description`, and `kind` (`simulation`, inferred from the metric) are all
derived. `points` defaults to 1; set it to weight this check more heavily.

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

## The question text always shows

You can open the preview with **only the Django `question_text`** — before writing a
single test-case row. The brief renders immediately so you can iterate on wording and
rows independently. If the grading config is missing or invalid, the prompt still shows
and a **non-blocking amber "Preview — grading not configured yet" banner** tells you
what's left to fix. The question is only fully gradeable once that banner is gone.

## Preview warning → fix

The banner (or, if there is no prompt at all, the empty-state message) is
author-actionable. Common ones and their one-line fix:

| Message you see | What to do |
|-----------------|-----------|
| "Add a SIMULATOR_CONFIG test-case row…" | Add a row whose `input` starts with `"type": "SIMULATOR_CONFIG"`, wired as a **test case** (not in `initial_game_state`). |
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

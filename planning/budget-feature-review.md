# Budget Feature - Review & Plan (V1 decision)

> **Question on the table:** is the budget feature workable for V1, and do the easy
> V1 questions even need it? **Short answer: no - as configured it's a graded test
> that can't fail, and cost isn't the lesson in any V1 question.** This doc shows
> why, defines when budget *does* make sense, and gives the recipe for authoring a
> real budget question (V2).

## 1. How budget scores today

`evaluateBudget(topology, budget)` with `unit: 'cost'` sums a **v1 heuristic**:

```
nodeCost = 1 (base) + replicas(default 1) + ceil(workers / 50)
total    = Σ nodeCost + (1 per edge)
```

It's graded as one pass/fail row (`actual ≤ cap`) in the question contract, and the
live `BudgetMeter` shows it in the brief.

## 2. The V1 reality (measured)

| Question | Reference cost | Gamed cost | Cap | Reference uses |
|----------|---------------:|-----------:|----:|---------------:|
| `async-sla` | 36 | 21 | 600 | **6.0%** |
| `sensor-store` | 22 | 21 | 500 | **4.4%** |

Three things are wrong here:

1. **The cap can't bite.** A correct design uses ~5% of the cap. To *reach* 600 you'd
   need ~150 nodes, or workers in the tens-of-thousands. On an easy 4-6 node question
   that never happens - so the budget row **always passes**. A test that can't fail
   teaches nothing and gives false confidence.
2. **It's orthogonal to the discrimination.** The *gamed* design is **cheaper** than
   the reference (fewer nodes), so budget can't separate good from gamed - it points
   the opposite way from every other axis.
3. **Defaults are cheap (your observation).** With default node/edge/workload configs,
   a student's initial design sits far below the cap. There's no pressure in the
   initial state and no tradeoff to reason about - so the meter reads "6% ✓" and is
   ignored.

## 3. Why the mismatch exists

- **Scale mismatch.** The heuristic outputs values in the **tens**; the authored caps
  (`600`/`500`) are in the **hundreds** - off by ~15-25×. They were picked as round
  numbers, not derived from any design's cost.
- **The heuristic is coarse.** `ceil(workers/50)` barely moves: cranking a service
  from 80→400 workers adds only +6. Adding a replica adds +1. So even deliberate
  over-provisioning stays cheap. The knob that's *meant* to punish brute-forcing
  latency (workers/replicas) doesn't.
- **Pedagogical mismatch (the real one).** The V1 questions teach **placement,
  caching, fan-out, storage-fit, guarded paths** - *not* cost. Budget is bolted onto
  `async-sla` (lesson: async decoupling) and `sensor-store` (lesson: time-series
  storage-fit) where it isn't the point.

## 4. Does V1 need budget? - No

None of the 9 V1 questions is a **cost/performance tradeoff** question, which is the
only kind budget grades meaningfully. On easy questions, a budget row is either
non-binding (always ✓, noise) or, if we tightened the cap, it would fight the
structural rules that already require specific components. Either way it hurts more
than it helps.

## 5. When budget *does* make sense (the V2 home)

Budget is a real axis only for a question whose **lesson is the tradeoff**:

- **`build-budget` / `optimize` type** - "you cannot afford everything; choose."
- The classic tension: two valid fixes for a latency SLA - **add a cache** (cheap,
  fits budget) vs **add 5 DB replicas** (over budget). Both pass the latency check;
  only the affordable one passes budget. *That* is where a student feels the cost
  lesson.
- Anti-kitchen-sink: stop "add every node just in case" - but this is often better
  expressed as a **`unit: 'nodes'`** cap (a hard node count), which is intuitive and
  bites immediately, than as the fuzzy `cost` heuristic.

## 6. Budget-first authoring recipe (for V2)

A budget question must be designed **cap-last**, from a real design:

1. Confirm the lesson *is* cost/tradeoff (else don't add a budget).
2. Build the **reference** (minimal correct design). Measure its cost `C_ref`.
3. Set `cap = C_ref + small slack` (~10-20%) so the intended design **just fits**.
4. Build a plausible **over-budget** design that also *passes the other axes* - a
   kitchen-sink or a brute-force-provisioned variant - and verify its cost **> cap**.
   If you can't build one that exceeds, the budget isn't doing anything.
5. The two designs must be a genuine fork (cache vs replicas), not "obviously add a
   node." Validate both through `validate-question-dir.ts`: reference within budget +
   passing; over-provisioned design over budget (or failing latency), so the student
   is forced to choose the affordable-and-fast option.

## 7. Heuristic / unit improvements needed before V2 budget questions

- **Pick one scale.** Either lower caps into the heuristic's range (tens) or rescale
  the heuristic. Today they're incompatible.
- **Make over-provisioning cost.** Weight replicas/workers more, or add **per-type
  base costs** (a `relational-db` should cost more than an `in-memory-cache`; a `cdn`
  more than a `microservice`) so *component choice* - not just count - drives cost.
  Right now every node has the same base cost, so "pick the cheaper architecture" has
  no meaning.
- **Consider `unit: 'nodes'` for anti-kitchen-sink.** A hard node cap (e.g. ≤ 6) is
  predictable, intuitive, and bites the moment a student over-adds - a better V1-grade
  budget than the `cost` heuristic if we ever want a light version.

## 8. Recommendation

**For V1:**

- **Remove the graded `budget` from `async-sla` and `sensor-store`.** They don't need
  it and it's a can't-fail row. (Net effect: since `BudgetMeter` only renders when a
  question declares a budget, the meter also disappears from V1 - correct, because it
  was only ever attached to these two.)
- **Keep the engine budget code + `BudgetMeter` component in the repo, dormant.** No
  code deletion - just stop attaching `budget` to V1 questions. It's ready for V2.
- *(Optional, if we want cost-awareness in V1)* repurpose the meter as an **ungraded
  "system footprint"** readout (no cap, no pass/fail) shown on every question. This is
  a small, separate change and can equally wait for V2.

**For V2:**

- Introduce budget as a **dedicated `optimize`/`build-budget` question type**, authored
  cap-last per §6, after the heuristic/unit improvements in §7 - ideally alongside the
  `storageProfile` trait so "the cheap store is also slower" tradeoffs are real.

## 9. Open decision for the team

1. **Drop graded budget from the 2 questions for V1** (recommended), **and**
2. either **hide the meter entirely for V1** (simplest) **or** keep it as an **ungraded
   footprint display**.

Everything else about budget → V2.

## 10. Decision taken

**V1:** graded `budget` removed from `async-sla` and `sensor-store` (and their moot
`constraints.maxBudget`); the `BudgetMeter` auto-hides. Engine budget code kept
dormant. **V2:** full redesign planned in `budget-v2-design.md` (cost model v2 with
per-type base costs, cap-last calibration, two concretely-redesigned questions, and a
non-binding-budget validator guard so a decorative budget can't ship again).

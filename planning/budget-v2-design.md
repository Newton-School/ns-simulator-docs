# Budget V2 — Detailed Design (plan only, not implemented)

> Follows `budget-feature-review.md` (the "why V1 budget doesn't work"). This is the
> **how** for V2: a cost model that creates real tension, a cap-last authoring
> procedure, two concretely-redesigned questions, the guardrails that stop us
> shipping a non-binding budget again, and the UI/validator/engine dependencies.
>
> **Status: PLAN ONLY.** V1 ships with no graded budget (removed from `async-sla` /
> `sensor-store`; the meter auto-hides). Nothing here is built yet.

## 1. Goals & non-goals

**Goals**
- Budget grades a *decision*: a correct-but-expensive design should **fail** while a
  correct-and-affordable design **passes** — the "you can't afford everything" lesson.
- The cap **bites in the initial state**: a reasonable first attempt is already near
  the cap, so every added node / over-provision is felt.
- Component **choice** drives cost, not just node count (a DB costs more than a cache).

**Non-goals**
- Real cloud pricing. This stays a *pedagogical* cost model, not a billing estimator.
- Budget on every question. Budget is only for the `optimize` / `build-budget` type.

## 2. Why today's model can't create tension (recap, with the fix)

Today `nodeCost = 1 + replicas + ceil(workers/50)`, same base for every type. So:
- every node is ~equally cheap → "pick the cheaper architecture" is meaningless;
- over-provisioning barely costs (80→400 workers = +6);
- caps (600/500) are ~20× a real design → can't bite.

**Fix = two changes:** (a) **per-type base cost** so choice matters; (b) **cap-last
calibration** so the cap sits just above the intended design.

## 3. Cost model v2

```
nodeCost(node) = BASE[type] * replicas + ceil(workers / WORKER_UNIT)
total          = Σ nodeCost + EDGE_COST * edges
```

- `replicas` multiplies the **base** (5 DB replicas really is 5× a DB), so
  over-provisioning stateful components is what blows the budget.
- `WORKER_UNIT` stays coarse (throughput scaling is a minor cost); the dominant lever
  is **type × replicas**.

**Proposed base cost by role** (tune at implementation; relative order is the point):

| Base | Types |
|-----:|-------|
| 0 | `api-endpoint` (source is free) |
| 2 | `microservice`, `batch-worker`, `queue`, `in-memory-cache`, `load-balancer`, `object-storage` |
| 3 | `cdn`, `kv-store` |
| 4 | `message-broker`, `nosql-db`, `time-series-db`, `search-index`, `distributed-lock` |
| 5 | `event-sourcing-store` |
| 6 | `relational-db` (ACID + replication is the priciest) |

`WORKER_UNIT = 100`, `EDGE_COST = 1` (starting values).

**Why this makes the tradeoff real** — to fix a read-latency SLA:
- **add a cache**: `in-memory-cache` = 2 → cheap.
- **add 3 read replicas**: `relational-db` × 3 = 18 → expensive.

With a cap set just above the cache design, the replica design **exceeds** — so the
student is *forced* to discover caching, not brute-force with replicas. That's the aha.

## 4. Unit strategy — `cost` vs `nodes`

| Unit | Use it for | Why |
|------|------------|-----|
| `nodes` (hard count) | **anti-kitchen-sink** ("≤ 6 nodes") | Predictable, intuitive, bites the moment a student over-adds. Best for "don't add every component just in case." |
| `cost` (model above) | **cost/performance tradeoff** ("cache vs replicas") | Captures *choice* and over-provisioning, not just count. |

V2 should support **both**, and questions pick the one matching the lesson. `nodes` is
the low-risk first shipment (no heuristic needed); `cost` needs §3.

## 5. Cap-last calibration (the authoring procedure)

1. Confirm the lesson is cost/tradeoff. If not → **no budget**.
2. Build the **reference** (minimal correct + affordable) design. Measure `C_ref`.
3. Build the **over-budget foil**: a design that *passes the other axes* but is the
   expensive way (kitchen-sink, or brute-force replicas/workers). Measure `C_foil`.
4. Set `cap` so **`C_ref ≤ cap < C_foil`**, with slack:
   `cap = round(C_ref * 1.15)` — reference just fits; foil is clearly over.
5. Verify with `validate-question-dir.ts`:
   - reference: within budget **and** passing all axes;
   - foil (as the gamed topology): **over budget** (and ideally also failing perf, so
     the lesson is "the affordable design is also the correct one").
6. Assert **`C_foil > cap` and `C_ref < C_foil`** — if the foil is cheaper than the
   reference, the budget is meaningless (this is exactly the V1 bug).

## 6. Redesigned questions (concrete)

### 6a. `async-sla` → "Meet a 15s SLA on a budget"

- **Tension:** an async queue + modest workers is **cheap and meets the SLA**; a
  synchronous path brute-forced with a big DB + replicas + huge worker pools is
  **expensive and still spikes** under bursts.
- **Reference:** `client → svc(2) → queue(2) → worker(2) → relational-db(6)` +
  4 edges ≈ **C_ref ≈ 16**. `cap = 18`.
- **Over-budget foil:** `client → svc → relational-db(6 × 3 replicas = 18)` with large
  worker pools to chase the SLA ≈ **C_foil ≈ 24+** → over budget *and* still risks the
  15s SLA under spike.
- **Lesson:** decoupling is cheaper than scaling the datastore.

### 6b. `sensor-store` → "Ingest 200k writes/s on a budget"  *(needs `storageProfile`)*

- **Tension:** a **time-series DB** is *both cheaper and faster* for the workload; a
  **relational DB sharded with replicas** to brute-force write throughput is
  *expensive and still saturates*.
- **Reference:** `client → svc(2) → time-series-db(4)` + 2 edges ≈ **C_ref ≈ 8**.
  `cap = 10`.
- **Over-budget foil:** `client → svc → relational-db(6 × 3 = 18)` ≈ **C_foil ≈ 20**
  → over budget, and with `storageProfile` the relational write path also **fails
  throughput**.
- **Lesson:** the right storage engine is cheaper *and* faster — the single best
  budget question, but it **depends on the `storageProfile` trait** (see
  `node-capability-matrix.md`) to make the wrong store physically slower.

## 7. Guardrail — a non-binding-budget detector (authoring validator)

Add to `authoringValidator.ts` so this class of bug can't ship again. Given a budget
question with a reference + foil topology, emit warnings when:

- `budget.non_binding`: `C_ref / cap < 0.6` → the cap is too loose to ever bite.
- `budget.misaligned`: `C_foil ≤ C_ref` → the "wrong" design isn't more expensive.
- `budget.no_foil`: no over-budget foil supplied → budget can't be shown to discriminate.

(These would have flagged the V1 `async-sla` 36/600 and `sensor-store` 22/500 immediately.)

## 8. UI plan

- **Graded meter:** the existing `BudgetMeter` already shows cost/cap + breakdown and
  color states. Reuse as-is once questions declare a budget again.
- **Calibration hint (author mode only):** show `C_ref` and `C_ref/cap` when authoring,
  so the author sees at a glance whether the cap bites.
- **Per-type cost in the breakdown:** the breakdown table should show each node's base
  cost so students learn *which components are expensive* (`relational-db ×3 = 18`).

## 9. Dependencies & phasing

1. **`nodes`-unit budget** (no heuristic work) — could ship first as a light
   anti-kitchen-sink cap on one question.
2. **Cost model v2** (§3) — per-type base costs + replica multiplier in `budget.ts`
   + `budgetBreakdown`. Backward-compatible: default `BASE` = current behavior if a
   type is unlisted.
3. **`storageProfile` trait** — prerequisite for the *strong* `sensor-store` budget
   question (§6b), so the wrong store is physically slower, not just pricier.
4. **Validator guardrail** (§7) + calibration UI (§8).
5. **Re-attach budgets** to the redesigned `async-sla` / `sensor-store` (or new
   `optimize`-type questions) via the cap-last procedure (§5), and validate.

## 10. Test plan

- Unit: `budget.test.ts` — per-type base costs; replica multiplier; a foil costs more
  than its reference.
- Authoring: `authoringValidator.test.ts` — the three §7 warnings fire on non-binding /
  misaligned / no-foil budgets.
- E2E: `validate-question-dir.ts` on each redesigned question — reference within budget
  + passing; foil over budget (+ failing perf where applicable).

## 11. Definition of done (V2 budget)

1. Cost model v2 with per-type base costs shipped + tested.
2. At least one **real** budget question where the reference fits and a correct-but-
   expensive foil exceeds — proven by the harness.
3. The non-binding-budget validator warning is active (can't ship a decorative budget).
4. Meter + breakdown show per-type cost.

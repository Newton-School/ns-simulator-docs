# Question ↔ Simulation Alignment

> **The problem in one line.** A student reads *"Create a short code for a long
> URL"* and thinks *"where do I write the shorten function?"* — but this tool has
> no place to write it. The prompt is worded like application features; the
> simulator grades **architecture and performance**. Some requirements are
> directly simulated, some are narrative, and at least one (read/write mix) is
> printed but never actually run. This doc defines how a question's text becomes
> something the simulator can **drive and grade**, closes the concrete gaps, and
> says honestly where we are per question archetype.
>
> **Companions.** `question-grading-model-and-anti-gaming.md` (the grading axes +
> the PDF/​web questions), `request-type-model.md` (request identity), `rubric-engine-and-question-platform-architecture.md`, `worked-example-order-processing-question.md`. Memory: `honesty-redesign-roadmap`, `no-point-sampled-scalars`, `cache-aside-routing-split`.

---

## 0. What actually happened (the URL-shortener evidence)

Our authored URL-shortener question renders **"Read / Write 99:1"** and
**"Peak RPS 200000"**. When run in the simulator, the Run Inspector showed
**"REQUEST MIX: GET 100%"**. Digging in:

- `prompt.scale.peakRps` **is** wired — the suite's peak case sets
  `workload.baseRps = 200000`, so the design is genuinely stressed at 200K rps.
- `prompt.scale.readWriteRatio` is **display-only** — it is referenced *only* in
  `QuestionPanel.tsx` to render the "99:1" chip. Nothing converts it into the
  workload's `requestDistribution`. So the simulation ran 100% reads; the "99:1"
  was a label the engine never saw.
- The functional requirements ("create a short code", "redirect") map to **no
  gradeable mechanism as worded** — the engine models a *request hitting a store
  node*, not "did you implement shortening."

That is the alignment gap in miniature: **the prompt promises things the
simulation isn't told about, and asks for features the simulation can't check.**

---

## 1. The load-bearing distinction: performance vs correctness

The simulator is an **architecture + performance** simulator, not an
**application-logic** simulator. This is not a limitation to apologize for — it
is the design, and the grading model already depends on it
(grading-model §11 point 2):

- **Performance invariants are simulatable** — latency (p50/p99), throughput,
  utilization, drop/timeout rate, availability under load and faults. These are
  what the **`rubric` (simulation)** axis grades.
- **Correctness invariants are NOT simulatable** — "produces the right short
  code", mutual exclusion, exactly-once, no-double-book, dedup, immutability,
  ordering. The engine models *flow and capacity*, not *application semantics*.
  These are graded by **topology (`structural`/`guardedPath`/`placement`) +
  `justification`** — the ≥3-axis anti-gaming model doing its job precisely when
  the sim can't help.

**So a student never "implements" a feature.** "How do I shorten a URL?" →
*"place a store to hold the code→URL mapping, a service in front of it, and a
cache on the read path; size them to survive the load."* The functional
requirement is satisfied by the **shape of the architecture**, and graded there.

> **Authoring consequence:** never write a `simulation` rubric check for a
> correctness property (the sim can't measure it), and never leave a functional
> requirement without a structural/semantic obligation behind it.

---

## 2. The authoring contract — no orphan requirements

Every element of the prompt must bind to a simulator mechanism, or be explicitly
labeled context. This is the rule that makes a question **solvable and
gradeable**.

| Prompt element | Kind | Binds to | Axis |
|----------------|------|----------|------|
| **Functional requirement** (e.g. "redirect a short code") | architectural | a required node / sub-path exists (`structural`, `guardedPath`, `placement` ordered-pipeline) | T |
| **Functional requirement** that is pure app-logic ("generate a unique code") | narrative | a **structural proxy** (a store/service that would do it) **+** a `justify` prompt; label it context in the text | T + J |
| **NFR — latency / throughput / availability** | performance | `rubric` simulation check under the injected load | Σ |
| **NFR — consistency / exactly-once / ordering** | correctness | `semantic` (`storageFit`, `guardedPath`) + `justification` (NOT sim) | S + J |
| **Scale — RPS / traffic pattern** | load | `suite.workload` (`baseRps`, `pattern`) — question-injected | Σ |
| **Scale — read/write ratio** | load mix | `suite.workload.requestDistribution` (derived, §3) **+** "must cache when read-heavy" `guardedPath` | S + Σ |
| **Scale — object sizes / retention / storage** | load + fit | request `sizeBytes` + `storageFit` access pattern | S + Σ |
| **Budget / cost ceiling** | cost | `budget` axis | $ |

**The rule:** during authoring, walk the prompt top to bottom. Each FR/NFR/scale
number either (a) drives the workload, (b) is asserted by a check, or (c) is
marked *context*. A requirement that does none of the three is a bug — it will
read as solvable but grade nothing (the "99:1" trap).

---

## 3. Closing the read/write gap (the concrete engine work)

The engine **already supports** the pieces; they are just not wired from the
prompt:

- `WorkloadProfile.requestDistribution` — an array of `{ type, weight, sizeBytes }`
  (weights sum to 1). The engine infers GET/POST from the type
  (`requestSemantics.ts`) and can route by type (`RoutingTable` conditions).
- Cache hit-rate modeling exists (`traits/cache.ts`: `cacheHitRate`, cache-hit
  latency) — a cache genuinely absorbs load and lowers downstream pressure.

**What's missing** is the derivation + default routing:

1. **Derive the mix from `readWriteRatio` at grade time.** A read-heavy question
   injects, question-owned (grading-model §7.1):
   ```
   requestDistribution: [
     { type: 'read',  weight: 0.99 },
     { type: 'write', weight: 0.01 }
   ]
   ```
   This must be injected by the question (like `baseRps`), overriding any student
   value — a read-heavy question **must** run read-heavy or the cache is never
   stressed.
2. **Route by type.** Reads follow a cacheable path (client→…→cache→store);
   writes go to the store. Type-conditioned edges already exist; the default
   wiring for a read-heavy scaffold should encode it.
3. **The reinforcing loop.** With (1)+(2): a read-heavy load + a cache on the read
   path → the cache absorbs ~hit-rate of reads → store load drops → **p99 passes**.
   *Remove the cache* → the store takes 99% of 200K rps → saturates → **p99
   fails**. Now `guardedPath(reads → cache)` and the `p99` rubric **reinforce each
   other**: the semantic rule isn't decorative, and the metric isn't gameable by
   an un-cached design. This is the whole point of a read-heavy question.

> Per-type processing weights, per-type SLOs, and per-type metrics are **deferred**
> (see `request-type-model.md`). Read/write routing + the mix is enough for V1
> alignment; the deferred items refine fidelity later.

---

## 4. Archetype coverage — where the sim helps, where topology carries

From the two faculty PDFs (Labs 1–5, Exams 1–3) and the three web questions,
mapped to what the simulator can and cannot do. **Σ = simulation grades it;
T = topology/structure; S = scale-fit semantic; J = justification.**

| Archetype | Workload | Primary hard problem | Graded by | Sim helps? |
|-----------|----------|----------------------|-----------|------------|
| **URL Shortener** | read-heavy, point-lookup | fast reads at 200K, 99:1 | `structural`(store, LB) · `guardedPath`(reads→cache) · `storageFit`(KV) · `rubric`(p99) · `justify` | **Yes** (p99 under real read-heavy load) |
| **Feed / News** | read-heavy, 50:1 | fan-out read at scale | same shape as URL + `fanout` | Yes (read latency) |
| **Lab 4 — sensor store** | write-heavy, time-series | 200K writes, right DB | `storageFit`(wide-column, SQL=hardfail) · `justify` · `budget` | Partial (write throughput; *fit* is semantic) |
| **Lab 2 — cache placement** | read-heavy, 20:1 | cache *between* app & DB, not before LB | `placement` · `guardedPath` · `rubric`(p99) | Yes |
| **Lab 3 — messaging fan-out** | connection/event | broker→N consumers (queue→N = hardfail) | `fanout` | No — pure topology |
| **Lab 5 — cargo-cult CDN** | mixed | *omission*: don't add a wasteful CDN | `forbidUnjustified` + `justify` | No — topology + justification |
| **Exam 1 — ride/track/pay** | mixed, hot/cold | geospatial hot path vs SQL pay path | `placement`(hot/cold) · `guardedPath`(pay→SQL) · `rubric`(<3s match) · `justify` | Partial (match latency = Σ; pay correctness = S+J) |
| **Exam 2 — rate limiter** | connection | RL must hit a **shared** cache | `structural`+`guardedPath`(RL→shared cache) · `justify`(algorithm) | **No** — contention isn't modeled; topology + justification |
| **Exam 3 — async SLA** | write/spike | sync violates 15s SLA at 50K/min | `rubric`(SLA fails w/o async) · `structural`(queue+workers) · `budget`(autoscale) | **Yes** (async vs sync is a real sim difference) |
| **Ticketmaster** | correctness-under-contention | no double-booking | `guardedPath`(booking→lock-store) · `storageFit`(SQL + search-index) · `justify` | Mostly **No** (waiting-queue latency = Σ; no-double-book = T+J) |
| **Web Crawler** | batch / throughput | dedup + politeness + pipeline | ordered-pipeline `placement`(frontier→fetch→process) · `guardedPath`(enqueue→dedup) · `fanout` | Partial (aggregate throughput = Σ; dedup = T) |
| **Payment** | exactly-once + audit | idempotency + immutable ledger | `guardedPath`(write→idempotency-store) · `storageFit`(append-only ledger) · `justify` | **No** — exactly-once/immutability = T + S + J |

**The pattern:** performance-heavy questions (URL, Feed, Lab 2, Exam 3) lean on
the simulation; correctness-heavy questions (Exam 2, Ticketmaster, Payment) are
carried by topology + justification. **The simulation is one axis, never the
whole grade** — which is exactly why the anti-gaming model needs ≥3 orthogonal
axes.

---

## 5. What the question text must contain

To be solvable in *this* tool, a prompt needs:

1. **A framing line:** *"You are designing the system architecture — placing and
   connecting components and sizing them — not writing application code."*
2. **Functional requirements phrased as architectural obligations** (or with an
   explicit note that they map to required components), so "redirect a short code"
   reads as "there must be a read path to the store." Pure-logic FRs are marked
   *context*.
3. **NFRs as measurable targets** (p99 < 100ms, ≥99.9% availability) — these
   become `rubric` checks.
4. **Scale as the load the question injects** — RPS, read/write mix, pattern,
   object sizes — with the explicit **"the workload is [read-heavy / write-heavy /
   connection-heavy / correctness-heavy / batch-heavy]"** cue (grading-model §1).
5. **No orphan requirements** (§2).

---

## 6. UX changes in the simulator (question mode)

The tool must make the architecture-first contract obvious, and connect the
prompt to the grade:

- **A "design the architecture, not code" cue** in the question panel — resolves
  the "where do I shorten a URL?" confusion at first glance.
- **Show the injected workload** the student is being tested under (RPS, the
  read/write mix, pattern). Today the Run Inspector already shows a request mix —
  once §3 lands it will correctly read "read 99% / write 1%" instead of
  "GET 100%", so the student can see what stresses their design.
- **Per-requirement live check rows.** Surface each FR/NFR as a row in the Tests
  panel ("reads traverse a cache: pending/passed/failed", "p99 < 100ms: …") so the
  student traces every prompt line to a check — the strongest cure for
  "how is this being graded?".
- Keep the already-shipped question-mode gating (no scenario-loading, no
  topology-open; autosave on).

### 6.1 Three refinements (from review)

1. **Don't over-provide routing in the scaffold.** If a read-heavy scaffold ships
   with the read-through-cache path *pre-wired*, the student treats it as magic and
   never learns to route. For intermediate+ questions, provide the **nodes** but
   make the student **configure the edge routing** (e.g. set the edge condition
   `type == 'read'` to hit the cache) — this teaches the L4/L7 routing concept the
   question is really about. Reserve fully-wired scaffolds for beginner/`LEARN`.
2. **Make the justification hand-off explicit at submit.** When the sim can't test
   a correctness invariant, the student can feel cheated ("it never checked
   double-booking"). On submit, surface a modal that *names the credit already
   earned and then asks for the missing axis*: e.g. *"Your architecture handles
   50K rps within SLA. Now explain in 2–3 sentences how you guarantee exactly-once
   between checkout and the ledger to prevent double-booking."* This makes the
   evaluation feel complete, and the graph-consistent `justification` grader scores
   it deterministically (an LLM pass is optional, later).
3. **Pedagogical failure strings, not just booleans.** Every `structural` /
   `guardedPath` / `storageFit` failure must emit a *why*, not just `false`. The
   evaluators already produce a `detail` string (grading-model §4.1) — author/curate
   these to teach: e.g. a client→DB `guardedPath` fail should read *"Public traffic
   reaches the store without passing the cache — reads will saturate the DB at this
   scale; route reads through the cache first,"* not *"guardedPath failed."*

---

## 7. Are we there yet? — per-capability status

| Capability | Status |
|------------|--------|
| p99 / latency under load | ✅ simulated + graded |
| Peak RPS injection | ✅ wired (`suite.workload.baseRps`) |
| Availability / drop-rate under faults | ✅ simulated |
| **Read/write mix drives the sim** | ❌ **display-only** — biggest concrete gap (§3) |
| "Must cache when read-heavy" reinforcing loop | ⚠️ pieces exist (cache model, routing); derivation + default routing missing |
| FR → gradeable structure | ⚠️ **authoring discipline**, not automatic (§2) |
| Correctness invariants | ✅ **by design** via topology + justification (not sim) |
| Semantic criteria scoring | ✅ implemented (grading-model §4.1) |
| Justification grading | ✅ implemented (UI capture pending) |
| Budget / cost axis | ❌ not built |
| "Design the architecture" UX framing | ❌ not built |

**Verdict:** the grading **framework** is there (structure + sim + semantic +
justification all work). The **question ↔ simulation wiring** is not: the prompt's
scale numbers don't fully drive the run, functional requirements don't
automatically bind to checks, and the UX doesn't tell the student what kind of
tool this is. The V1 embed is a fine **ungraded practice sandbox**; for questions
to be **solvable and gradeable exactly as written**, this alignment is the next
body of work.

---

## 8. Phased plan

1. ✅ **Authoring contract + validator.** The recipe is §10; the validator is
   **built** — `authoringValidator.ts` `validateAuthoredQuestion(pkg)` (pure,
   tested) flags wrong metric keys, un-injected scale numbers, missing `sizeBytes`,
   orphan NFRs, correctness-questions-on-simulation, dangling justify bindings, and
   read/write `guardedPath` misuse. Run it in the Django admin `clean()` (errors
   block save) and in CI over the bank. The URL-shortener was re-authored correctly
   and the loop proven end-to-end (§9).
2. **Scale → workload derivation (engine).** Auto-derive `requestDistribution`
   from `scale.readWriteRatio`; give read-heavy scaffolds a default type-routed
   read-through-cache path; verify the cache reduces store load in the sim (§3).
3. **UX framing (renderer).** The "design the architecture" cue, the injected-
   workload display, and per-requirement live check rows (§6).
4. **Correctness-question authoring guide.** Document the performance-vs-
   correctness boundary (§1) so authors route correctness NFRs to
   `guardedPath`/`storageFit`/`justify` and never to a `simulation` check.
5. **Budget axis** (separate track, grading-model §4/§9).

Do 1 first — it needs no code, validates the whole thesis on a real question, and
tells us exactly how much of 2–3 is required before the platform can host
*graded* questions rather than practice.

---

## 9. Phase 1 result — the reinforcing loop is proven

Executed the tracer bullet: authored the URL-shortener with a **real** injected
99:1 read/write `requestDistribution` at 2000 rps, and graded two topologies that
differ **only** in whether reads pass through a cache. Same store sizing (kv-store,
3 workers, 3ms), same workload, type-conditional routing (reads → cache, writes →
store via `condition: request.type === "read"/"write"`), cache `cacheHitRate: 0.9`.

| Design | store util | p99 | grade (`p99 < 100ms`) |
|--------|-----------|-----|-----------------------|
| **Reads through cache** | ~0.2 | **8 ms** | ✅ `passed` 4/4 |
| **Reads hit the store** (no cache) | **1.0 (saturated)** | **1003 ms** (100% timeouts) | ❌ `failed` 1/4 — *"actual 1003.52 does not satisfy summary.latency.p99 < 100"* |

The cache absorbs 90% of the 99% reads → store load 2000 → ~218 rps. Remove it →
store saturates → everything times out → p99 explodes. **The grade follows the
physics; the read-heavy workload makes the cache mandatory without a rigid rule.**
Proven through the real `sim evaluate question` grading pipeline, not just a raw run.

### Findings from the tracer bullet (fix before authoring more)

1. **`readWriteRatio` really is inert until injected.** The mix only mattered once
   it was put in `suite.workload.requestDistribution` as typed traffic
   (`read`/`write`) **and** the topology routed on type. Both are required — a
   `requestDistribution` with no type-conditional edges leaves reads and writes on
   the same path, so the ratio still wouldn't matter. (Confirms §3; strengthens
   the §2 authoring contract.)
2. **Metric-key bug in the seed.** The correct rubric metric is
   **`summary.latency.p99`**, not `summary.latencyP99Ms` (which the earlier
   `system_design_simulator_seed` fixture used and which never resolves). Any
   authored NFR must use the real verdict paths (`summary.latency.p99`,
   `summary.errorRate`, `invariantViolations.count`, `perNode.<id>.utilization`).
   → **Add metric-name validation to the authoring contract (Phase 1).**
3. **`guardedPath(reads→cache)` does NOT fit this question.** Writes legitimately
   bypass the cache and go straight to the store, so a topology-only `guardedPath`
   from service→store (which can't see request types) would wrongly fail a correct
   design. Here the **simulation rubric is the enforcement** — exactly the "let the
   math force it" pedagogy. Reserve `guardedPath` for *all-traffic* guards
   (rate-limiter → shared cache, payment → idempotency store) where there is no
   legitimate bypass. This sharpens §1/§4: a "must cache" property under a
   read/write mix is a **Σ (simulation)** obligation, not a **T (topology)** one.

### Verdict on "are we there yet" (updated)
The reinforcing loop **works today** when the question is authored correctly — the
engine already has type-conditional routing + cache-load modeling. What's missing
is **automation and authoring safety** (Phase 2 derivation + Phase 1 metric/mix
validation), not core physics. The tracer bullet de-risks the whole plan.

---

## 10. The correct way to author a question (recipe)

"Authored correctly" means the question **discriminates**: a good design passes, a
gamed one fails on the intended axis. Follow this recipe (all steps validated
against the 12-question bank; see `question-bank-initial-game-states.md`).

1. **Name the workload character.** Set `workloadCategory` to one of
   read-/write-/connection-/correctness-/batch-heavy. This decides which axis
   carries the grade (§4).
2. **Map every FR to an obligation.** Each functional requirement →
   `requires_component` / `requires_path` / `guardedPath` / `placement`. A pure
   app-logic FR ("generate a unique code") → a **structural proxy** (a store that
   would do it) **+** a `justify` prompt, and label it context in the text. No FR
   left as prose only.
3. **Map every NFR by flavour.**
   - **Performance** (latency/throughput/availability) → a `simulation` rubric
     check with a **real verdict metric key**: `summary.latency.p99`,
     `summary.throughput`, `summary.errorRate`, `invariantViolations.count`,
     `perNode.<id>.utilization`. **Never** `summary.latencyP99Ms` — it doesn't
     resolve.
   - **Correctness** (consistency/exactly-once/ordering) → `storageFit` /
     `guardedPath` + `justify`. **Never** a `simulation` check — the sim can't
     measure correctness.
4. **Inject every scale number into `suite.workload`.**
   - `baseRps`: a **tractable** value (~2–5K) that still stresses the design (the
     browser can't run 200K rps); keep the real number in `prompt.scale` for
     display, and size nodes/thresholds to the tractable load.
   - **read/write ratio** → typed `requestDistribution`
     (`{ "type":"read","weight":0.99,"sizeBytes":256 }`, …). Include `sizeBytes`.
   - object sizes → `sizeBytes`.
5. **"Must cache when read-heavy" is a simulation obligation, not a topology rule.**
   Enforce it with the p99 `simulation` check (the store saturates without a
   cache — proven §9). Do **not** use `guardedPath(service→store)`: writes
   legitimately bypass the cache and would wrongly fail a correct design.
6. **Encode the defining architectural mistake as a `hardFail` semantic check.**
   storageFit anti-pattern, guardedPath bypass, fanout-via-queue — mark
   `"hardFail": true` so it zeroes the question.
7. **Add `justify` prompts** for tradeoffs/correctness: `requires` `choice` +
   (optionally `number`) + `tradeoff`, `boundTo` the real component.
8. **Add `budget`** (`{ "unit":"cost", "cap":N }`) to catch kitchen-sink designs.
9. **VALIDATE — mandatory.** (a) `parseQuestionPackage` (schema). (b) Grade a
   **reference** topology (expect pass) **and** a **gamed** topology (expect fail on
   the intended check) via `sim evaluate question`. If the gamed design passes, the
   question is under-constrained — tighten it. A question that hasn't been graded
   both ways is not "authored", only "written".

**Gotchas** (from bank validation): a full topology's `requestDistribution` needs
`sizeBytes`; `category` is a fixed enum, not the type name (`batch-worker`'s
category is `compute`); a `structuralRule` short-circuits later semantic checks;
`forbidUnjustified` fails a present component via the CLI (no justification capture)
but passes a *defended* one in-app.

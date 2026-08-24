# Why This Works - The Math, The Creative Solutions & The Skeptic's FAQ

> **Purpose.** The intellectual case for the simulator: why a *"LeetCode for system
> design"* - automated grading, test cases, and scaling exploration over an
> open-ended design space - is even possible. Written for a skeptical system-design
> instructor / interviewer and for anyone teaching the keynote.
>
> **The hard part.** System design has no compile/run, no single right answer, an
> unbounded design space, and its most valuable skill (capacity/scaling tradeoffs)
> looks un-gradeable. Below is how each of those is solved.
>
> **See also.** `CURRICULUM.md` Part III (this content in teaching context) and the
> deep specs: `resource-allocation-and-derived-concurrency.md`,
> `question-grading-model-and-anti-gaming.md`, `question-simulation-alignment.md`,
> `queue-depth-calculation.md`, `throughput-calculation.md`,
> `execution-profile-and-node-concurrency.md`.

---

## A. The math we actually run

1. **Discrete-event simulation (DES).** A priority queue of events in *simulated*
   time; the clock jumps event→event. The DEVS formalism used in real capacity
   planning - not an animation.
2. **Queueing theory - every node is a G/G/c/K station.** `c` servers, `K` capacity
   (in-service + waiting) before rejection, FIFO. **Little's Law** `L = λ·W` as an
   invariant check. **Utilization = time-weighted integral** `ρ = ∫busy dt / (c·T)`,
   never a point sample.
3. **Derived concurrency.** `effectiveC = vCPU × instanceCount × workersPerVcpu`
   (1 cpu-bound / 32 io-bound); `effectiveK = max(c, ⌊totalRAM/perRequestMemMb⌋)`
   (RAM sets the admission ceiling → `oom` when exceeded).
4. **Service-time tails.** For exponential service, `p99 ≈ mean × ln(100) ≈ 4.6×
   mean` - why a chain of small means still produces a large p99 even at low load.
   `serviceTimeMultiplier = 1/effectivePerf`; io-bound damping
   `effectivePerf = 1 + (perfFactor−1)×0.25` (a faster core barely helps an
   I/O-blocked request).
5. **Cache-aside as Bernoulli thinning.** A hit is served locally with probability
   `hitRate`; a miss continues downstream. We never model the cache's *contents* -
   only which backend a request routes to, which is all the metric depends on.
6. **Cost & egress.** `cost = pricePerHour × count × pricingMultiplier`; egress
   `= bytes/duration × 3600 × $/GB` - an upper-bound estimate pre-run, measured
   exactly post-run.
7. **Scale-invariance of discrimination.** We run ~2k rps, not 200k, because the
   thing that decides pass/fail is the **offered/capacity ratio**, preserved when
   rps and capacity downscale together.

## B. The creative mechanisms

1. **Grade the consequences, not the diagram.** Run load; measure whether it meets
   the SLO. **Physics is the impartial grader.**
2. **Five orthogonal axes** - Topology (T), Scale-fit (S), Simulation (Σ),
   Justification (J), Budget ($). Gaming one axis is caught by another.
3. **The Dual-Topology Rule** - an *executable definition of a good question*: a
   reference must PASS and a known gamed shortcut must FAIL on the intended axis.
   The architecture-world equivalent of hidden test cases. If the gamed design
   passes, the question is rejected as under-constrained.
4. **Derive-and-lock** - the killer move. If workers were a free number, every
   bottleneck vanishes for free and nothing discriminates. Deriving capacity from a
   *priced, capped* instance catalog makes "more capacity" cost money and hit
   quotas - so **scaling becomes a real, physical tradeoff** (this is how "company
   scale up/down exploration" is made gradeable).
5. **The performance/correctness boundary.** Simulate what queueing physics can
   decide; *refuse* to fake what it can't (exactly-once, ordering) - those go to
   topology structure + justification. Honesty about the boundary is a feature.
6. **Topology-as-proxy.** "Generate a unique code" isn't simulatable, but "a durable
   store must sit on the write path" is - a structural proxy + a justification
   prompt carries the nuance.
7. **Deterministic justification grading (no LLM).** The answer must name a
   component actually in the student's graph (anti-BS), cite a real scale number,
   and state a tradeoff. Fully reproducible.
8. **Question-owned injected workload.** The student can't lower the load, reseed,
   or change the mix - the graded suite is injected over *their* topology at grade
   time.

## C. Determinism & continuous distributions in JS - no floating-point drift

**Q. How do you sample continuous PDFs (arrival/service times) in a deterministic
JS environment without accumulating floating-point drift over millions of events?**

Three layers keep it exact:

**1. An integer-only PRNG.** `xmur3(seed)` → `sfc32(a,b,c,d)`; the state is four
32-bit unsigned integers evolved with `Math.imul`/shifts/XOR/`>>>0`. **No float ever
enters the recurrence**, so the stream is bit-identical across platforms and never
drifts; only the last step divides to `[0,1)` (`t / 2³²`). *(`stochastic/random.ts`.)*

**2. Standard transform sampling from that one uniform.** Exponential (arrival &
service) via inverse-CDF `−ln(1−U)/λ`; normal via Box-Muller and **log-normal** =
`exp(normal(μ,σ))`; Weibull via inverse-CDF; Gamma via Marsaglia-Tsang. Dispatched by
`distribution.type`. *(`stochastic/distribution.ts`.)*

**3. A BigInt-microsecond clock - floats never accumulate (the crux).** The
accumulating quantities - the event clock and every scheduled time - are **`bigint`
integer microseconds**. A sampled float duration is **quantized to whole µs the
instant it enters the timeline**:

```ts
const interArrivalUs = BigInt(Math.max(1, Math.round(interArrivalMs * 1000)))
this.scheduleRequestGeneratedAt(currentTime + interArrivalUs)   // BigInt + BigInt - exact
```

So floating-point math is confined to a single, **non-accumulating** leaf step
(drawing one duration). Once it joins the event queue it is an exact integer, and all
downstream arithmetic - ordering events, summing millions of durations, the
busy-area integral - is exact BigInt math. **There is no growing epsilon because
nothing floating-point is ever summed.**

- **Ordering** is exact (integer comparison) → reproducible event sequence.
- **Accumulation** is exact (BigInt) → no epsilon growth over long runs.
- **Sampling** floats affect only one duration's *value*, by ≤ sub-µs, and are erased
  by µs quantization.
- **Honest caveat:** transcendental funcs (`Math.log/sqrt/cos`) can differ in the last
  ULP across JS engines; because every result is rounded to a whole microsecond
  before use, those differences vanish. Reproducibility is guaranteed within an engine
  and effectively across engines. (A fixed-point `log` would give bit-identical
  cross-engine transcendentals if ever needed - not currently necessary.)

**Where it lives:** `stochastic/{random,distribution}.ts` (+ `__tests__`), the BigInt
clock in `engine.ts` / `core/types.ts`, quantization in `workload.ts`.
**Gap:** no spec states this determinism contract as a first-class invariant - it's
correct in code + unit-tested, but undocumented. Proposed: a short
`simulation-determinism-and-numerics.md` so "reproducible given a seed" is a
documented guarantee, not folklore.

## D. The skeptic's FAQ

> **"System design has no single right answer - you can't grade it."**
> We grade whether the design **satisfies the requirements under load**, not whether
> it matches a template. *Any* topology that meets the SLO with the store shielded
> passes. Multiple valid solutions is a feature.

> **"You can't simulate a real distributed system in a browser."**
> We don't. We simulate the **queueing physics that decide whether it meets its
> SLO**, on a tractable, proportionally-faithful slice. A calibrated instrument, not
> a cloud oracle.

> **"Correctness (exactly-once, no double-book) can't be simulated."**
> Correct - we **don't fake it.** Performance → simulation; correctness → the
> required guard on the topology + a justification prompt. Never a correctness claim
> behind a latency number.

> **"Students will just game it / get lucky."**
> Multi-axis grading + Dual-Topology validation. Each question is authored so a known
> gamed shortcut fails on a specific axis; if it passes, the question is rejected.
> **Gaming is a bug we test for** before ship.

> **"Anyone can crank the servers up to pass."**
> Not anymore. Concurrency is derived from a priced, capped catalog - cranking
> "workers" does nothing, buying capacity costs money and can breach a budget/quota,
> and over-provisioning fails the **$** axis.

> **"Latency from a toy sim is meaningless."**
> It's **relative and physically consistent**, not an absolute prediction. The
> threshold is co-authored with the sim's numbers and validated both ways.

> **"The real skill is the reasoning/tradeoffs - you can't grade that."**
> Deterministic justification grading: name-a-real-node + cite-a-number +
> state-a-tradeoff. No LLM, fully reproducible.

> **"Scaling up vs out, cost tradeoffs - you can't explore those in a toy."**
> That's exactly what the instance model exposes: up (bigger SKU) vs out (more
> instances), cpu- vs io-bound, on-demand/reserved/spot, RAM ceilings → OOM,
> per-region egress. The learner watches **cost and SLO move together** - the real
> capacity-planning loop.

---

## Known gaps we teach openly (credibility, not spin)

- **Utilization-display bug:** a saturated node can currently *report* low
  utilization while queueing heavily (util denominator vs the scheduler's derived
  `c`). Fix pending; teach it so authors trust p99 over the "HEALTHY" badge.
- **Dry-run vs graded-load trap:** the student's dry-run defaults to a low RPS while
  the graded suite injects the peak - a design can look healthy in dry-run yet fail
  the test. Size for the stated peak.
- **Graded cost is a v1 heuristic**, distinct from the instance-aware live cost chip.
- **Determinism contract is undocumented** (see §C gap).

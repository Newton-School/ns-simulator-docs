# Simulation Determinism & Numerics

> **Purpose.** State the simulator's determinism contract explicitly instead of
> making contributors reverse-engineer it from `random.ts`, `distribution.ts`,
> `workload.ts`, `GGcKNode.ts`, and the event scheduler.
>
> **Why this exists.** Determinism is load-bearing for:
>
> - grading fairness
> - A/B topology comparison
> - reproducible debugging
> - trustworthy golden tests
>
> This doc closes the gap called out in `LECTURE-MASTERCLASS.md` Part I §2.5.
>
> **Primary source of truth in code.**
>
> - `src/engine/stochastic/random.ts`
> - `src/engine/stochastic/distribution.ts`
> - `src/engine/core/time.ts`
> - `src/engine/workload.ts`
> - `src/engine/nodes/GGcKNode.ts`
> - `src/engine/scheduler/min-heap.ts`
> - `src/engine/engine.ts`
> - `src/engine/analysis/output.ts`

---

## 1. Executive Summary

The simulator's determinism model is:

1. one **seeded integer PRNG stream** per run
2. all sampled durations are **quantized to integer microseconds immediately**
3. the event loop, scheduler, clock, and accumulated totals operate on
   **`bigint` microseconds only**
4. event ordering is fully defined by:
   - timestamp
   - explicit priority
   - stable insertion sequence

That combination means:

> **Same topology + same workload + same seed + same engine build ⇒ the same run
> result.**

This is strong enough for:

- deterministic grading
- byte-stable golden tests within the same runtime
- trustworthy A/B comparisons where only one modeled change is introduced

It is also important to state what the contract is **not**:

- it is **not** a guarantee that different topologies preserving "semantic
  equivalence" consume identical random draws
- it is **not** a guarantee that changing topology shape leaves unrelated nodes'
  random samples untouched
- it is **not** a claim that JavaScript transcendental functions are bit-identical
  across all engines in the final ULP

The current contract is **run reproducibility**, not yet **substream-isolated
counterfactual invariance**.

---

## 2. Why Determinism Is A Product Requirement

Determinism is not a backend nicety. It is part of the product's teaching and
grading model.

### 2.1 Grading fairness

If a student's submission can pass or fail depending on random noise, the score is
not defensible.

The simulator therefore requires:

> the grade must be a deterministic function of:
>
> - topology
> - question-owned workload
> - question-owned seed
> - engine version

### 2.2 A/B comparison

The core lesson form is:

> "you changed X, therefore Y happened"

That only holds if the random process is held fixed.

Same seed + same workload + one topology change means:

- the comparison is a real experiment
- the delta is attributable

### 2.3 Anti-gaming

If the student controlled the seed, they could reroll until a lucky run passed.

The simulator avoids that by:

- fixing the seed at the question/scenario level for graded runs
- surfacing the actual seed in output
- marking the output `reproducible: true`

See `SimulationOutput.seed` and `SimulationOutput.reproducible` in
`src/engine/analysis/output.ts`.

---

## 3. The Determinism Contract

### 3.1 Contract statement

For the current engine, determinism means:

> **Given the same input topology JSON, the same global workload config, the same
> seed string, and the same code path, the simulator must produce the same event
> ordering and the same aggregate output.**

This includes:

- summary metrics
- per-node metrics
- per-edge metrics
- invariant results
- event counts
- request outcomes

### 3.2 Input surface covered by the contract

The contract applies to:

- `topology.nodes`
- `topology.edges`
- `topology.workload`
- `topology.global.seed`
- `topology.global.simulationDuration`
- `topology.global.warmupDuration`
- node/edge config and trait config

### 3.3 Surface intentionally outside the contract

The contract does **not** cover:

- the UI choosing a new seed string with `Math.random()` for convenience
- wall-clock timestamps around the run
- file ordering or display ordering unless explicitly stabilized
- renderer-only animations

Important nuance:

> generating a fresh seed for a new run is allowed outside the engine, but once
> the seed is chosen, the run itself must be deterministic and the exact seed used
> must be recorded.

This is why "randomize seed each run" in the UI is acceptable, while
`Math.random()` inside the engine is not.

---

## 4. Layer 1: Seeded Integer PRNG

### 4.1 Current implementation

The engine uses:

- `xmur3(seedString)` to hash a string seed into integer state
- `sfc32(a, b, c, d)` as the advancing generator

in `src/engine/stochastic/random.ts`.

### 4.2 Why this matters

The generator state evolves using only integer operations:

- `Math.imul`
- bit shifts
- XOR
- unsigned coercion via `>>> 0`

So:

- no floating-point value enters the state recurrence
- the random stream does not "drift"
- a long run does not accumulate PRNG error

### 4.3 The only float boundary

The final returned uniform is:

```ts
return t / 4294967296
```

That division is deterministic and non-accumulating.

It is a presentation of the current integer state into `[0, 1)`, not a source of
cumulative numerical drift.

### 4.4 Current guarantee

The PRNG guarantee today is:

> same seed string ⇒ same `rng.next()` sequence

inside the current JS runtime model.

---

## 5. Layer 2: Deterministic Distribution Sampling

### 5.1 Sampling model

All stochastic distributions are sampled from the seeded uniform source in
`src/engine/stochastic/distribution.ts`.

Current supported transforms include:

- constant / deterministic
- uniform
- exponential
- normal
- log-normal
- poisson
- weibull
- gamma
- beta
- pareto
- empirical
- mixture
- binomial

### 5.2 Why floating-point here does not break the contract

Yes, transforms use floating-point math:

- `Math.log`
- `Math.sqrt`
- `Math.pow`
- `Math.cos`
- `Math.sin`
- `Math.exp`

But that floating-point work is confined to:

> **one sampled duration at a time**

The result is not repeatedly re-added as a float into a long-running timeline.

That is the critical distinction.

### 5.3 Spare-state note

The normal sampler caches one spare normal variate (`spareNormal`) for Box-Muller.

This does not weaken determinism.

It is deterministic because:

- it is derived only from the seeded stream
- its usage order is deterministic
- it is local to the `Distributions` instance

---

## 6. Layer 3: BigInt Microsecond Timeline

### 6.1 The core rule

Once a sampled duration enters the engine timeline, it must become an integer
microsecond `bigint`.

This happens through helpers such as:

- `msToMicro(ms)` in `src/engine/core/time.ts`
- explicit `BigInt(Math.round(ms * 1000))` in hot paths such as:
  - `src/engine/workload.ts`
  - `src/engine/nodes/GGcKNode.ts`

### 6.2 Why this closes the drift worry

All accumulated simulation quantities are integer microseconds:

- event timestamps
- the main clock
- queue wait
- service time
- deadlines
- busy-area integrals
- retention windows

So:

- event ordering uses integer comparison
- accumulation uses exact integer arithmetic
- no long-run epsilon grows over millions of events

### 6.3 Current conversion helpers

`src/engine/core/time.ts` defines:

- `msToMicro(ms: number): bigint`
- `microToMs(us: bigint): number`
- `secToMicro(sec: number): bigint`
- `microToSec(us: bigint): number`

The determinism-critical direction is:

> **float duration -> integer microseconds**

The reverse direction is mainly for reporting and display.

### 6.4 Quantization policy

The engine currently uses:

```ts
BigInt(Math.round(ms * 1000))
```

and in some arrival paths enforces a minimum of `1µs`:

```ts
BigInt(Math.max(1, Math.round(interArrivalMs * 1000)))
```

This quantization policy is part of the determinism contract.

It means:

- sub-microsecond float differences are erased
- the event queue never receives float timestamps

---

## 7. Event Ordering Contract

Deterministic randomness is not enough. The scheduler order must also be fully
defined.

### 7.1 Current scheduler

`src/engine/scheduler/min-heap.ts` orders events by:

1. **timestamp**
2. **priority**
3. **per-heap insertion sequence**

### 7.2 Why the sequence counter matters

Two events can legitimately share:

- the same timestamp
- the same priority

Without a stable tertiary tie-breaker, equal-key events could be popped in an
implementation-dependent order.

The heap's monotonic `_counter` prevents that.

### 7.3 Practical implication

This means the engine defines a total order over all enqueued events, not just a
partial order.

That is necessary for:

- stable replay
- stable request traces
- stable metrics

---

## 8. Where Quantization Enters The Engine

The main determinism-sensitive conversion points today are:

| Surface | File | What happens |
|--------|------|--------------|
| Workload inter-arrivals | `src/engine/workload.ts` | sampled gap ms -> rounded µs BigInt |
| Node service time | `src/engine/nodes/GGcKNode.ts` | sampled service ms -> rounded µs BigInt |
| Time constants | `src/engine/core/time.ts` | configured ms/sec -> rounded µs BigInt |
| Trait latencies | trait modules | penalties or fixed costs -> µs or ms then quantized before scheduling |

Rule:

> sampled or configured durations may be born as numbers, but they may not live on
> the event timeline as floats.

---

## 9. Output Contract

The engine exposes reproducibility explicitly.

`SimulationOutput` includes:

- `seed: string`
- `reproducible: true`

in `src/engine/analysis/output.ts`.

This is not decorative metadata.

It means:

> the output is intended to be replayed, compared, and graded as a deterministic
> artifact.

Any future work that would weaken this must be treated as a design change, not an
implementation detail.

---

## 10. What Is Guaranteed Today vs What Is Not

### 10.1 Guaranteed today

| Property | Status | Notes |
|---------|--------|-------|
| Same seed ⇒ same PRNG stream | yes | `random.ts` |
| Same seed + same topology ⇒ same event ordering | yes | given current engine and scheduler |
| No float accumulation in the event timeline | yes | `bigint` µs clock and timestamps |
| Stable tie-breaking for identical timestamp/priority | yes | heap sequence counter |
| Reproducible aggregate metrics | yes | same input -> same output contract |

### 10.2 Not guaranteed today

| Property | Status | Why |
|---------|--------|-----|
| Bit-identical cross-engine transcendentals in the final ULP | no formal guarantee | JS `Math.*` may differ in the last bit |
| Structural-edit isolation of random draws | not guaranteed | one master seeded stream is currently shared through the run |
| "Add one node and unrelated nodes keep identical sampled service times" | not guaranteed | draw order can change when topology shape changes |
| Arbitrary plugin / UI code preserving determinism | not guaranteed | only engine and grading surfaces are covered |

### 10.3 The important interpretation

The simulator currently guarantees:

> **run reproducibility**

It does **not yet** guarantee:

> **counterfactual substream isolation**

That future hardening would require purpose-scoped or node-scoped RNG substreams.

---

## 11. Contributor Guardrails

These are mandatory rules, not style preferences.

### 11.1 Never call `Math.random()` in the engine, traits, routing, grading, or metrics

Allowed:

- external seed generation in UI convenience flows

Forbidden:

- request routing randomness
- trait stochastic behavior
- failure injection randomness
- grading randomness

Every stochastic path must draw from the seeded engine source.

### 11.2 Never schedule float timestamps

Forbidden:

- adding raw `number` milliseconds directly to a simulation timestamp

Required:

- quantize to integer microseconds first

### 11.3 Never rely on unspecified ordering

If behavior depends on order, that order must be explicit.

Examples:

- event ordering must use stable tie-breakers
- route choice must not depend on label text
- grading row flattening must be ordered once and reused

### 11.4 Keep determinism separate from correctness

A deterministic wrong model is still wrong.

Determinism guarantees:

- the same wrong answer repeats

It does not prove:

- the physics are truthful

This distinction matters in grading and in design reviews.

### 11.5 New traits must preserve the contract

Any new stochastic behavior must:

- use the seeded source passed by the engine
- avoid ambient process/global randomness
- quantize or otherwise stabilize any scheduled duration
- add regression tests proving repeatability

This is already called out in `specs/trait-integration-guide.md`.

---

## 12. Testing & Certification

Determinism must be certified by tests, not assumed from code review.

### 12.1 Existing evidence in the codebase

Current examples include:

- `src/engine/stochastic/__tests__/distribution.test.ts`
  - same seed -> same sampled distribution sequence
- `src/engine/failureModes.test.ts`
  - same seed + same failure config -> identical output twice

### 12.2 Recommended determinism test layers

| Layer | Test shape |
|------|------------|
| PRNG | same seed -> identical number sequence |
| Distribution sampling | same seed -> identical sample arrays |
| Node trait | same seed + same node config -> identical trait decisions |
| Engine | same topology + same seed -> identical summary + event counts |
| Grading | same submission + same question suite -> identical verdict |

### 12.3 Preferred assertion style

For deterministic engine-level tests, assert one of:

- exact structural equality on selected output
- exact JSON string equality on stable output fragments
- golden-file equality for canonical artifacts

Prefer not to assert only:

- "close enough"

unless the surface is intentionally statistical rather than deterministic.

---

## 13. Known Caveats

### 13.1 JavaScript transcendental functions

`Math.log`, `Math.sqrt`, `Math.pow`, `Math.cos`, and `Math.sin` are not specified
to be bit-identical in the last ULP across every engine implementation.

Why this is acceptable today:

- the sampled float is quantized to whole microseconds before joining the timeline
- sub-microsecond ULP differences are erased by that quantization in normal ranges

### 13.2 Number conversion for reporting

Reporting surfaces convert `bigint` microseconds back to `number` milliseconds.

This is acceptable because:

- reporting is downstream of the deterministic run
- the simulation state itself is not driven forward by those numbers

### 13.3 One master RNG stream

The engine currently seeds one master RNG per run and shares it across:

- distributions
- routing
- traits via engine-provided random callbacks

This is deterministic, but not topology-edit-isolated.

That is a real, honest limitation.

---

## 14. Future Hardening

If stricter determinism is needed later, the next steps are:

### 14.1 RNG substreams

Derive stable substreams by:

- node id
- trait name
- purpose

So that adding a cache does not perturb an unrelated DB's draw stream.

### 14.2 Golden determinism fixtures

Persist canonical run outputs and require:

- byte-identical output for the same seed and same topology

in CI.

### 14.3 Determinism audit checklist

Add a checklist for PRs touching:

- random sampling
- scheduling
- event ordering
- grading row ordering
- canonical serialization

### 14.4 If ever needed: fixed transcendental approximations

Only if cross-engine last-bit identity becomes necessary, replace `Math.*`
transcendentals used in simulation-critical paths with fixed approximations under
our control.

That is not currently justified.

---

## 15. Bottom Line

The simulator is deterministic today because it combines:

- a seeded integer PRNG
- deterministic transform sampling
- immediate microsecond quantization
- a `bigint` timeline
- fully specified event ordering

That is enough to support:

- fair grading
- reproducible debugging
- trustworthy A/B comparison

The important honest caveat is:

> we currently guarantee reproducible runs, not yet substream-isolated
> counterfactual invariance across topology edits.

That distinction should be taught openly, preserved in code review, and enforced by
tests.

# Video 2 — "How a system-design question is actually *graded*"

> **Series:** Reverse-Engineering the System Design Simulator
> **Style target:** Web Dev Simplified — one big promise, teach the *why* before the
> *how*, keep circling back to a single mental model, show the table on screen.
> **Runtime:** 14–18 min.
> **Format:** reverse-engineering — take one finished question and pull it apart to
> reveal the grading machine underneath.
> **Grounding:** `specs/evaluation-authoring-reference-manual.md` §1,
> `specs/question-grading-model-and-anti-gaming.md`.

---

## 0. The hook (0:00–1:00)

**[SCREEN: a finished, passing question — green checks everywhere.]**

> "This design just got a perfect score. And I could show you a *completely different*
> design that also gets a perfect score. Two different diagrams, both correct. So how
> on earth does the grader agree with both — but still fail the lazy student who
> cheats? That's the magic trick I'm going to expose in this video. By the end you'll
> be able to look at any question here and read the grading machine like an x-ray:
> what it measures, how it scores each dimension, and — the important part — *why it
> can't be gamed*. Let's reverse-engineer it."

**[Title card: HOW A QUESTION IS EVALUATED]**

---

## 1. The one idea everything hangs on: discrimination (1:00–3:00)

> "Forget 'grading' for a second. The real job of a question is **discrimination**.
> That's the word the authoring manual actually uses. A question is only *authored* —
> not just *written* — when it discriminates: a **good** design passes, and a
> **gamed** design fails, on the axis you actually care about."

**[SCREEN: two columns fill in as you talk — GOOD DESIGN ✓ / GAMED DESIGN ✗]**

> "What's 'gaming'? It's any way to pass *without* the skill you're testing.
> Over-provisioning one giant node. Tuning a single metric until it goes green.
> Using a wrong-but-tolerated database. Memorizing the buzzwords. If any of those
> pass your question, your question is broken — it's rewarding the cheat instead of
> the competence."

> "So how do you stop that? You don't. Not with one check. You stop it by grading
> **several checks that are independent of each other** — the manual says at least
> three orthogonal axes. Gaming one axis gets caught by another. *That's* the trick
> the intro promised. Let me show you the actual axes."

---

## 2. The core table: Axis → Graded by → Measures (3:00–6:30)

> "This is the single most important table in the whole platform. If you screenshot
> one thing from this video, screenshot this."

**[SCREEN: build this table row by row — reveal one row at a time, explain each.]**

| Axis | Symbol | Graded by | Measures |
|------|--------|-----------|----------|
| **Topology** | T | `structuralRules`, placement, guarded-path, fan-out | the *shape* of the graph |
| **Scale-fit semantics** | S | `storageFit`, scale-aware checks | the *right component* for the workload |
| **Simulation** | Σ | `rubric` checks over verdict metrics | *performance* under injected load |
| **Justification** | J | `justify` prompts (graph-consistent) | *reasoning* and tradeoffs |
| **Budget** | $ | `budget` | *cost* / anti-kitchen-sink |

> "Read it left to right, and read the last column as the *question it answers*."

> **Topology (T):** "'Did you build the right shape?' Is there one source? Does the
> write path actually reach a durable store? Are there two replicas? This is graded
> by structural rules — it looks at the *drawing*, not the behavior."

> **Scale-fit semantics (S):** "'Did you pick the right *kind* of component?' A
> point-lookup by key wants a key-value store, not a relational DB doing full scans.
> Same shape, different meaning. This is the one people underestimate."

> **Simulation (Σ):** "'Does it actually perform?' We inject load, run the
> discrete-event engine, and assert on the numbers it produces — p99 latency, error
> rate, throughput. You can't argue with a queue that's backed up."

> **Justification (J):** "'Can you *defend* it?' Some things the sim can't measure —
> like 301 vs 302, or why you chose fan-out-on-write. Those live as reasoning prompts.
> This carries the correctness a simulation physically can't."

> **Budget ($):** "'Did you solve it, or did you just throw hardware at it?' The
> anti-kitchen-sink axis. You can't pass by buying ten of everything."

> "And here's the punchline — look down the 'Measures' column. Shape, component,
> performance, reasoning, cost. **Five totally different questions.** A cheat that
> fakes one of them still fails the other four. *That's* how two different-but-correct
> designs both pass while the lazy design fails — correctness lives in the
> *intersection*, and there's no single lever that satisfies all five at once."

---

## 3. Reverse-engineer a real one: map rows → axes (6:30–9:30)

> "Let's prove it. Here's a real question — a URL shortener — and I'm going to take
> its grading rows and drop each one into the table."

**[SCREEN: rows on the left, the axis table on the right; draw an arrow from each row
to its axis as you go.]**

```json
{ "type": "STRUCTURAL_RULE", "kind": "requires_single_source" }        // → T
```
> "Structural rule → **Topology**. Shape of the graph. One faucet."

```json
{ "type": "SEMANTIC_CRITERION", "kind": "storageFit",
  "accessPattern": "point-lookup",
  "accept": ["kv-store", "nosql-db"],
  "antiPattern": ["relational-db"], "hardFail": true }                 // → S
```
> "Semantic criterion, storageFit → **Scale-fit semantics**. Look at this — it *names
> the right answers* (`accept`) and the *trap* (`antiPattern`). Pick a relational DB
> for a billion point lookups and this hard-fails you. Same shape, wrong component,
> caught."

```json
{ "type": "RUBRIC_CHECK", "kind": "simulation",
  "metric": "summary.latency.p99", "op": "<", "value": 100 }           // → Σ
```
> "Rubric check over a verdict metric → **Simulation**. p99 under 100ms or it's red."

```json
{ "type": "RUBRIC_CHECK", "kind": "invariant",
  "metric": "invariantViolations.count", "op": "==", "value": 0 }      // → Σ / correctness
```
> "And the invariant → nothing physically illegal happened."

> "See what happened? Four rows, three axes, and *every one of them fails for a
> different reason.* That's not an accident — that's the author deliberately covering
> orthogonal axes so the thing can't be gamed. When you author, you're not writing
> rules, you're *covering axes*."

---

## 4. Workload characterization: which axis dominates (9:30–12:30)

> "Now — one field decides the *personality* of the whole question. It's called
> `workloadCategory`, and it does two things: it picks what traffic we inject, and it
> decides which axis carries the lesson."

**[SCREEN: reveal this table one row at a time.]**

| `workloadCategory` | Injected load | Dominant axis | The hard problem it forces |
|--------------------|---------------|---------------|----------------------------|
| `read-heavy` | ~99% reads | Σ + S | caching is mandatory — the store saturates without it |
| `write-heavy` | high write mix | S + Σ | pick a store that survives write throughput |
| `connection-heavy` | fan-out / shared state | T | broker fan-out, shared counters |
| `correctness-heavy` | contended burst | **T + S + J**, and **Σ where the bug is simulable** | exactly-once, no double-book, ordering |
| `batch-heavy` | sustained throughput | Σ + T | ordered pipeline, dedup, aggregate throughput |

> "This is the part that surprises people, and it's the part that changed. For a long
> time the rule was: correctness lives in **structure and justification, not
> simulation** — because you can't measure 'we never double-booked' with a stopwatch.
> The *shape* still matters — is there a reservation authority, can you defend it — but
> here's the update: for the class of correctness bugs that come from **contention**,
> we now *can* simulate it. The engine has a reservation model that runs the burst
> forward and counts actual double-books as `reservations.oversells`. So a
> correctness-heavy question today leans on T + S + J for the shape **and** gets a real
> **Σ** signal when the bug is a race. What still can't be simulated — arbitrary
> exactly-once semantics, ordering guarantees with no contention model — stays on T + J.
> The simulator is honest about which is which, and that honesty is exactly what
> decides whether a correctness lesson gets a Σ row or not."

> "And a huge gotcha: this is an **author-side selector.** It's a hint for *you*, the
> author, about how to load and grade. You do NOT hand it to the student as the answer.
> The student is supposed to *infer* 'oh, 99:1 reads at 200K RPS — I need a cache'
> from the requirements and the scale numbers, and then get *forced* into it by the
> simulation. If you just tell them 'this is read-heavy,' you've given away the lesson."

---

## 5. How each dimension is actually scored (12:30–15:30)

> "Okay, last piece — mechanically, how does each axis turn into points? Because they
> don't all score the same way, and this trips authors up."

**[SCREEN: a simple scorecard graphic, one line per axis.]**

- **Topology (structural):** "Mostly **pass/fail gates.** Either the graph has one
  source or it doesn't. These are often *hard requirements* — fail one and the whole
  submission can be capped, because a broken shape means the rest of the grade is
  meaningless."

- **Semantics (storageFit):** "**Tiered.** Look back at that row — `accept` is full
  marks, `partial` is partial credit, `antiPattern` is zero, and `hardFail: true`
  means picking the trap doesn't just lose points, it *sinks* the submission. So
  semantics can be all-or-nothing *or* graded, author's choice."

- **Simulation (rubric):** "**Threshold assertions with points.** Each check is a
  metric, an operator, a value, and a point weight — `p99 < 100 → 3 points`. The sim
  runs, the number comes back, the comparison is mechanical. No opinion involved."

- **Justification:** "Reasoning prompts. Today they're prose shown at submission and
  may be human- or rubric-reviewed rather than auto-scored from runtime metrics —
  because the whole point is that the *engine shouldn't* decide these from numbers."

- **Budget:** "A cost ceiling. Sum the hardware cost of the design; over the cap loses
  points. This is what stops the 'buy ten of everything' cheat."

> "And then the whole thing rolls up against a `passThreshold`. Add the points, apply
> the hard fails and caps, compare to the threshold, done. Deterministic — same design,
> same seed, same score, every single time. That determinism is *why* this can be an
> exam and not a vibe."

---

## 6. Recap + tease (15:30–17:00)

> "Let's collapse the whole video into one breath. A question's job is
> **discrimination** — good passes, gamed fails. You get that by covering **orthogonal
> axes**: Topology, Scale-fit Semantics, Simulation, Justification, Budget — each
> measuring a *different* thing, each scored its own way, so no single cheat clears
> all of them. `workloadCategory` picks which axis dominates and what load you inject —
> and it's a hint for *you*, not a giveaway for the student. That's the grading
> machine. You can now x-ray any question on the platform."

> "Next video, I stop explaining and start *building* — I'm going to design a brand
> new question from a famous interview prompt we have NOT built yet, live, axis by
> axis, and validate it the honest way: grade a good design and a cheating design and
> prove the cheat fails. It's the fun one. Subscribe and I'll see you there."

**[End card.]**

---

## Author notes / B-roll shot list

- The **Axis → Graded by → Measures** table is the star. Reveal it row-by-row, leave
  it up as the "home base" you keep returning to.
- In §3, literally draw arrows from JSON rows to table axes — that arrow is the whole
  lesson of the video made visual.
- §4's `correctness-heavy` line is the "smart" moment — pause on it. The nuance is
  "structure + justification for the shape, **and** a real Σ oversell signal when the
  bug is contention" — not the old "never Σ". (The engine now simulates double-booking;
  see Video 3 and `contended-inventory-and-oversell-model.md`.)
- Keep saying the sentence: *"you're not writing rules, you're covering axes."*
- Tables and field semantics are lifted from
  `evaluation-authoring-reference-manual.md` §1.1–1.3 so they stay authoritative.

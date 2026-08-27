# Video 1 — "How to turn a single test case into a real simulator question"

> **Series:** Reverse-Engineering the System Design Simulator
> **Style target:** Web Dev Simplified (Kyle) — friendly, fast, "let me show you why",
> constant tiny recaps, one clear promise up front, zero fluff, build it live.
> **Runtime:** 12–15 min.
> **Format:** reverse-engineering — start from the tiniest thing that can be graded
> (one source, one test case) and grow it, on screen, into a full question.
> **Grounding:** `url-shortener/django-admin-assignment.md`,
> `specs/interview-question-to-django-assignment-translation.md`.

---

## 0. The hook (0:00–0:45)

**[SCREEN: a blank simulator canvas, one lonely "Source" node blinking.]**

> "So here's a question that sounds impossible: how do you *grade* a system design?
> Not a multiple-choice quiz about system design — an actual diagram someone drags
> onto a canvas. There's no single right answer, right? Well, in this video I'm
> going to show you that a gradeable question isn't something you *write* — it's
> something you *grow*. And we're going to grow one from scratch, starting from the
> single most boring thing on this screen: one source node. By the end you'll
> understand the exact round-trip — Django to the simulator, back to Django — that
> every question in this platform lives in. Let's get into it."

**[On-screen title card: FROM ONE TEST CASE → A REAL QUESTION]**

---

## 1. The mental model first: the round-trip (0:45–2:30)

> "Before we build anything, I want you to hold one picture in your head, because
> everything else hangs off it."

**[DIAGRAM builds piece by piece as you narrate — draw these three boxes:]**

```
   DJANGO (Newton admin)            THE SIMULATOR                DJANGO again
   ┌───────────────────┐          ┌────────────────┐          ┌───────────────┐
   │ question_text HTML │  ──────▶ │  student builds │ ──────▶ │  grade + score │
   │ test-case rows     │  config  │  a topology,    │ verdict │  stored on the │
   │ (the contract)     │          │  sim runs load  │         │  submission    │
   └───────────────────┘          └────────────────┘          └───────────────┘
```

> "Django is where the question *lives*. Not the drawing — the **contract**. A title,
> some HTML for the prompt, and then a stack of rows that say what 'correct' means.
> The simulator reads those rows, locks the environment, lets the student build a
> diagram, injects traffic, and runs a real discrete-event simulation. Then it hands
> a verdict *back* to Django, which turns it into a score. Django → simulator →
> Django. That's the whole loop, and we're going to walk every arrow."

> "Here's the important bit, and it's the thing people always get backwards: **you
> don't start by drawing the answer.** You start by deciding what you're able to
> *check*. So let's start with the smallest checkable thing that exists."

---

## 2. The smallest possible test case: "there must be exactly one source" (2:30–5:00)

**[SCREEN: canvas with one Source node.]**

> "Every request in this simulator has to come from somewhere. A source node is the
> faucet — it's what emits traffic. And the most rudimentary rule you can possibly
> grade is: *this design must have exactly one faucet.* Not zero, not three. One."

> "Why does that even matter? Because if a student has two sources, the workload we
> inject gets ambiguous — which faucet gets the traffic? So 'exactly one source' is
> our very first grading row. Watch how small it is."

**[SCREEN: paste this into a Django test-case row's `input` field.]**

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source",
  "description": "Exactly one traffic source"
}
```

> "That's it. That's a real, shippable grading rule. `type` tells the platform what
> family of check this is — a **STRUCTURAL_RULE**, meaning it's about the *shape* of
> the graph. `kind` is the specific check. And notice — I didn't say anything about
> caches or databases yet. I'm literally just asserting the graph has one faucet."

> "I've written `id` and `description` here so you can see the full shape — but you
> can drop both. The simulator derives them (`requires-single-source`, 'Exactly one
> traffic source'). In practice this row is just
> `{ \"type\": \"STRUCTURAL_RULE\", \"kind\": \"requires_single_source\" }`. Write only
> the fields that carry meaning; everything else fills itself in."

> "This is the whole philosophy in miniature: **a question is a pile of small,
> orthogonal checks.** Each one is dumb on its own. Together, they're a rubric."

**[Recap beat — say it out loud:]**

> "So far: one row, one rule, one axis — *topology*. Let's give that faucet somewhere
> to send water."

---

## 3. Grow it: add a target and a simulation check (5:00–8:00)

> "A source with nowhere to go is useless. The student needs to build a path — source
> to *something* — and that something has to actually keep up under load. So now I
> add a second kind of row: a **simulation** check."

**[SCREEN: add row.]**

```json
{ "type": "RUBRIC_CHECK", "metric": "summary.latency.p99", "op": "<", "value": 100, "points": 3 }
```

> "Look at what this is. It's an *assertion over a number the simulator produces.*
> After the sim runs, it hands back a verdict object, and inside it is
> `summary.latency.p99`. This row says: that number has to be **less than 100**.
> If the student under-builds — one tiny instance trying to serve everything — the
> queue backs up, p99 explodes, and this check goes red. They *feel* the bottleneck.
> I didn't have to describe the bottleneck in words — the physics did."

> "And here's the key difference from the first row. The structural rule looked at
> the *drawing*. This one looks at the *behavior*. That's a completely different axis,
> and that's on purpose — I'll come back to why in a second."

> "One more freebie while we're here — correctness. The engine tracks invariant
> violations, things that should physically never happen. Let's assert there are
> zero."

```json
{ "type": "RUBRIC_CHECK", "kind": "invariant", "metric": "invariantViolations.count", "op": "==", "value": 0 }
```

**[Recap:]**

> "Three rows now. One says *the shape is right*. One says *it's fast enough*. One
> says *nothing illegal happened*. Different axes. Remember that word, axes — it's
> the whole reason this works."

---

## 4. The 'aha': why you need *different kinds* of checks (8:00–9:30)

**[SCREEN: split view — a 'good' design on the left, a 'gamed' design on the right.]**

> "Here's the trap. If all my rows were the *same kind* of check, a student could
> game it. Say I only graded latency. What does a lazy student do? They slap one
> gigantic instance on the source, no real design, and — technically — it's fast.
> They passed without learning anything. That's called gaming."

> "The fix is not a better single check. The fix is **orthogonal checks** — checks
> that fail for *different reasons*. A structural rule catches 'you didn't build the
> right shape.' A semantic rule — which we'll add in the next video — catches 'you
> used the wrong component.' A simulation check catches 'it doesn't perform.' To pass,
> you have to satisfy *all* of them at once, and there's no single cheat that does
> that."

> "That's the one sentence to tattoo on your brain: **a question is only real when a
> good design passes and a cheating design fails.** We even validate every question by
> grading it twice — once with a correct topology, once with a deliberately broken
> one — and if the broken one passes, the question isn't done."

---

## 5. Wire the round-trip: what Django actually sends (9:30–12:30)

> "Okay — we have three grading rows. But rows floating in space don't do anything.
> They need to be wrapped in the thing that boots the whole environment. That's
> **row zero**: the SIMULATOR_CONFIG. This is the one that goes from Django *into*
> the simulator and sets up the entire sandbox."

**[SCREEN: type this short SIMULATOR_CONFIG, highlighting the workload as you talk.]**

```json
{
  "type": "SIMULATOR_CONFIG",
  "workloadCategory": "read-heavy",
  "suite": {
    "cases": [
      { "workload": { "baseRps": 2000, "requestDistribution": [
        { "type": "read",  "weight": 0.99 },
        { "type": "write", "weight": 0.01, "sizeBytes": 512 }
      ] } }
    ]
  }
}
```

> "That's the *whole* config. And here's the thing people brace for — they expect a
> giant block of settings — but almost everything defaults. Empty canvas, blank
> constraints, the lock — all filled in for you. The **one** thing worth writing is
> the workload, because it's the traffic *we* inject and the student can't touch it."

> "Look at it. `baseRps` is 2000, not 200,000 — the browser can't run two hundred
> thousand requests a second, so we run a **representative** load that still stresses
> the same path. `requestDistribution` is 99% reads — that's us declaring a
> read-heavy world, which is what makes a cache mandatory later. I only wrote the two
> weights; `sizeBytes` on the reads defaults to 256, so I dropped it."

> "And the anti-gaming lock is automatic. A Newton assignment runs in **ASSIGNMENT**
> mode by default: the student can't open the settings, can't lower our traffic,
> can't reseed for a lucky run. The question *owns* the load — they change the
> diagram, never the exam. You didn't have to write that; you got it for free."

**[SCREEN: back to the three-box round-trip diagram, animate the arrows lighting up.]**

> "So here's the full trip, live: Django holds row zero plus our three grading rows.
> The student opens the iframe, the simulator reads row zero, builds the locked
> sandbox, they drag nodes, we fire 2000 rps of 99%-reads at it, the discrete-event
> engine produces a verdict with `latency.p99` and `invariantViolations.count`, our
> rows assert against those numbers, and a pass/fail score flows **back** to the
> Django submission. That's the loop. That's every question on the platform."

---

## 6. Recap + tease (12:30–14:00)

> "Let's rewind the whole thing in ten seconds. We did NOT start by drawing an answer.
> We started with the smallest gradeable fact — one source — as a structural row.
> We grew it with a simulation row and an invariant row, on *different axes* so it
> can't be gamed. Then we wrapped it in the SIMULATOR_CONFIG that boots a locked
> sandbox and injects our own traffic. Django in, simulator runs, verdict back to
> Django. You now understand the skeleton of every question here."

> "But I skipped something on purpose. I kept saying 'axes' and 'the right *kind* of
> check' — and there's a whole discipline to choosing them so the question actually
> teaches the lesson you intend. That's the next video: how a question is *evaluated*
> — discriminatory authoring, the Axis–Graded-by–Measures table, workload
> characterization, all of it. If that sounds like your thing, subscribe, and I'll
> see you in the next one."

**[End card.]**

---

## Author notes / B-roll shot list

- **Cold open** on the blinking single source node — it's the visual hook.
- Every JSON block should be **typed or pasted on screen live**, not just narrated —
  WDS always shows the code appearing.
- Keep the three-box round-trip diagram as a recurring "home base"; return to it at
  §1, §5, and §6.
- The good-vs-gamed split screen in §4 is the emotional peak — spend the animation
  budget there.
- Real row shapes are copied verbatim from `url-shortener/django-admin-assignment.md`
  so they will actually validate if a viewer pastes them.
- **Accuracy caveat on the invariant row (§3).** The narration ("the engine tracks
  invariant violations… things that should physically never happen") is a beginner
  simplification. In fact invariants are *author-defined* `<metric> <op> <number>`
  assertions, and in the current question-grading path they are **not question-owned**
  (`mergeTopologyWithOverrides` does not inject them), so `invariantViolations.count`
  on an empty student topology is effectively a no-op. It's kept because it's a real
  row in the shipped url-shortener package. If you want a *genuinely* enforced
  correctness signal, grade a real verdict aggregate instead — e.g.
  `reservations.oversells == 0` (see Video 3). Don't over-promise the invariant row on
  camera.

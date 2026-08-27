# Video 3 — "Reverse-engineering the Ticketmaster interview question into a simulator question"

> **Series:** Reverse-Engineering the System Design Simulator
> **Style target:** Web Dev Simplified — take a famous prompt everyone's seen, tear it
> down, rebuild it live, validate it, ship it.
> **Runtime:** 16–20 min.
> **Format:** reverse-engineering — start from the classic "Design Ticketmaster"
> interview question, extract the *one* lesson, and author it end-to-end as Django rows.
> **Why this question:** it is **correctness-heavy** — the hardest and most
> interesting family, where the lesson is "**never double-book a seat**." That can't
> be graded by latency; it is graded by a **simulated oversell metric**
> (`reservations.oversells`) produced by a real contention model, backed by the
> **Topology + Semantics + Justification** axes.
> **Status:** BUILT and validated (2026-08-27). The `reservation-store` component,
> the `keyspace` workload, and the `reservations.oversells` verdict metric all ship
> in the engine; the question lives at
> `system-design-simulator-questions/questions/flash-sale-booking/`. Every row
> below is copied from the validated `question.json`.
> **Grounding:** `contended-inventory-and-oversell-model.md` (the build),
> `evaluation-authoring-reference-manual.md` §1.3 (`correctness-heavy`).

---

## 0. The hook (0:00–1:00)

**[SCREEN: news clip vibe — "TICKETS SOLD OUT IN 4 MINUTES" / a seat map going red.]**

> "You've all seen this interview question: *design Ticketmaster.* A hot concert drops,
> fifty thousand people slam the buy button for the same seat in the same second, and
> the one thing you absolutely cannot do — ever — is sell that seat twice. Now here's
> what makes this a *nasty* one to put in a simulator: you can't measure 'we didn't
> double-book' with a stopwatch. Latency won't catch it. So in this video I'm going to
> take this famous prompt and reverse-engineer it into a real, gradeable simulator
> question — and I'll show you how you grade *correctness* when the clock can't help
> you. Let's build it."

**[Title card: BUILDING THE TICKETMASTER QUESTION]**

---

## 1. Don't transcribe the prompt — extract the lesson (1:00–3:00)

> "Rule number one of authoring, straight from the translation guide: **you translate
> the lesson, not the wording.** The real Ticketmaster interview covers ten things —
> seat maps, waiting rooms, payments, search, CDN. If I try to grade all of it, I grade
> none of it well. So I pick *one dominant lesson.*"

**[SCREEN: cross out sub-problems one by one, circle the survivor.]**

> "Search? Cut. CDN? Cut. Payment processing? That's its own question. Waiting room?
> Tempting, but cut. What's left — the thing that makes this question *this* question —
> is: **two people cannot buy the same seat.** No oversell. That's our lesson. One
> lesson, one question. Everything else is either narrative flavor or a different
> assignment."

> "And notice the *character* of this lesson. It's not 'go fast.' It's 'be correct
> under contention.' That single observation decides everything about how we grade it."

---

## 2. Classify every requirement into a bucket (3:00–5:30)

> "The translation worksheet makes you sort every requirement into one of five buckets
> *before* you write a single row. Let's do it live."

**[SCREEN: fill this table in real time.]**

| Requirement | Bucket | Becomes |
|-------------|--------|---------|
| One traffic source (the buyers) | Structural | `STRUCTURAL_RULE` (single-source) |
| A **reservation authority** must exist and feed the ledger | Structural | `STRUCTURAL_RULE` (requires_component + requires_path) |
| The booking must reach the ledger **only through** that authority | Semantic | `SEMANTIC_CRITERION` (guardedPath) |
| The ledger is a **transactional store**, not a cache | Semantic | `SEMANTIC_CRITERION` (storageFit) |
| **No seat is ever sold twice** under a burst | Simulation | `RUBRIC_CHECK` (simulation) on `reservations.oversells` |
| It still has to serve the burst without collapsing | Simulation | `RUBRIC_CHECK` (simulation) on `summary.errorRate` |
| Explain your reservation strategy (single authority, optimistic vs pessimistic lock) | Justification | prompt prose |
| "It's like Ticketmaster, tickets sell out fast" | Narrative | `question_text` only |

> "Look at where the *weight* landed — Structural, Semantic, and Justification carry
> the *shape* of a correct design, and then the **Simulation** row is the one that
> actually catches the bug. That's the correctness-heavy signature: the diagram checks
> tell you the design *looks* right, and the simulated oversell count tells you whether
> it *behaves* right under contention. You need both — a design can pass every diagram
> check and still double-book, and that's the whole point of the question."

---

## 3. Choose the workload — and why it's *low* (5:30–7:30)

> "Here's the counter-intuitive move. Every instinct says 'flash sale = crank the RPS
> to a million.' Wrong. For correctness, I don't need crushing sustained load — I need
> **contention**: a burst of writes fighting over the *same* seats. Modest total RPS,
> spiky, write-flavored."

**[SCREEN: type the config.]**

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "flash-sale-booking",
  "questionType": "open-build",
  "domains": ["storage", "correctness"],
  "concepts": ["idempotency", "reservation-lock", "store-fit"],
  "difficulty": "advanced",
  "workloadCategory": "correctness-heavy",
  "scaffold": { "type": "empty" },
  "constraints": { "canModifyScaffold": true, "maxNodeCount": 12 },
  "suite": {
    "name": "flash-sale-suite",
    "visibleToStudent": false,
    "cases": [
      {
        "id": "on-sale-burst",
        "description": "Contended booking burst on a small seat inventory",
        "workload": {
          "baseRps": 1500,
          "requestDistribution": [
            { "type": "book",   "weight": 0.9, "sizeBytes": 512 },
            { "type": "browse", "weight": 0.1, "sizeBytes": 256 }
          ]
        }
      }
    ]
  },
  "rubric": { "id": "flash-sale-rubric", "passThreshold": 8 },
  "environmentProfile": { "mode": "ASSIGNMENT", "graded": true, "chromeDensity": "minimal" }
}
```

> "`workloadCategory: correctness-heavy` — that's us declaring the personality.
> `baseRps: 1500`, ninety percent `book` writes — a tight, contended burst, not a
> marathon. And remember, this is the *tractable* load; the prompt will still show the
> real-world 'sold out in 4 minutes' scale. We compress runtime, we preserve
> character."

---

## 4. Author the axes as rows (7:30–12:00)

> "Now the fun part — turning that bucket table into actual rows. I'm going to author
> them axis by axis, exactly the discipline from the last video."

### T — one source

```json
{ "type": "STRUCTURAL_RULE", "id": "single-source",
  "kind": "requires_single_source", "description": "Exactly one buyer source" }
```

### T — a reservation authority must exist and feed the ledger

> "First, structurally, the design must actually contain a reservation authority, and
> that authority must reach the durable ledger. Two small structural rows."

```json
{ "type": "STRUCTURAL_RULE", "id": "has-reservation-authority",
  "kind": "requires_component", "componentType": "reservation-store",
  "description": "A reservation authority must commit seats atomically" }
```
```json
{ "type": "STRUCTURAL_RULE", "id": "reservation-feeds-ledger",
  "kind": "requires_path", "fromType": "reservation-store", "toType": "relational-db",
  "description": "Reserved bookings must be persisted to the durable ledger" }
```

### S — the guarded path (the heart of the question)

> "This is the row that makes it Ticketmaster. The booking write is not allowed to
> reach the ledger *except* through the reservation authority — and crucially, **no
> path may bypass it.** The `guardedPath` semantic check enforces exactly that: a
> path from the source to the ledger must exist, and there must be no way around the
> guard. Wire buyers straight to the database and this hard-fails."

```json
{ "type": "SEMANTIC_CRITERION", "id": "booking-passes-through-reservation",
  "kind": "guardedPath",
  "description": "Every booking must reach the ledger only through the reservation authority",
  "from": "api-endpoint", "guard": "reservation-store", "to": "relational-db",
  "points": 3, "hardFail": true }
```

### S — the right store for contended seat state

> "Seats are contended, money-adjacent state. That wants a **transactional** store —
> not an eventually-consistent cache pretending to be the source of truth. The trap
> here is the opposite of the URL shortener: reaching for a plain cache as the system
> of record is the anti-pattern. Note the `accessPattern` value the engine ships for
> exactly this: `transactional-relational`."

```json
{ "type": "SEMANTIC_CRITERION", "id": "ledger-is-transactional",
  "kind": "storageFit",
  "description": "Seat inventory is contended, money-adjacent state needing a transactional store",
  "accessPattern": "transactional-relational",
  "accept": ["relational-db"],
  "partial": ["nosql-db"],
  "antiPattern": ["in-memory-cache"],
  "points": 3, "hardFail": true }
```

### Σ — the simulated no-double-book check (the star)

> "Here's how we grade correctness with a machine — and this is the part the engine
> now actually does. The reservation store performs an atomic per-seat reserve, and
> the simulation counts an **oversell** whenever a seat is committed by *two
> independent authorities*. That count surfaces in the verdict as
> `reservations.oversells`. We assert it's zero. A single reservation authority yields
> zero; a design that naively runs two uncoordinated reservation stores double-books,
> the engine counts it, and this goes red. The stopwatch couldn't catch it — the
> contention model can."

```json
{ "type": "RUBRIC_CHECK", "id": "no-double-book",
  "kind": "simulation",
  "description": "No seat is committed by more than one reservation authority",
  "metric": "reservations.oversells", "op": "==", "value": 0,
  "points": 5 }
```

> "Five points, the biggest weight in the question — because this *is* the question.
> And the workload that creates the contention is question-owned: the injected suite
> stamps every `book` request a `seatId` drawn from a tiny 40-seat keyspace, so tens
> of requests fight over each seat — the student can't lower it."

```json
"workload": {
  "baseRps": 1200,
  "requestDistribution": [
    { "type": "book", "weight": 1.0, "sizeBytes": 512,
      "keyspace": { "field": "seatId", "size": 40 } }
  ]
}
```

### Σ — still has to survive the burst

```json
{ "type": "RUBRIC_CHECK", "id": "burst-error-rate",
  "kind": "simulation",
  "description": "Booking error rate stays bounded under the burst",
  "metric": "summary.errorRate", "op": "<", "value": 0.05,
  "points": 2 }
```

> "Note I'm grading *error rate*, not p99. For a correctness question, 'did it fall
> over' matters more than raw speed. A design that guarantees no-double-book by
> *rejecting everyone* would ace the oversell check but tank here — so these two Σ rows
> keep each other honest. (Sold-out responses are modeled as fast successes, not
> errors, so a healthy design keeps error rate near zero.)"

### J — defend the strategy (prompt prose)

> "And the justification lives in the prompt: at submission, explain hold-and-confirm
> vs. direct write, optimistic vs. pessimistic locking, and what happens to a
> reservation that's never paid for. Not auto-scored from metrics — because a *number*
> shouldn't decide whether their reasoning is sound. That's the J axis doing the work
> the sim can't."

---

## 5. The honesty test: grade it twice (12:00–15:30)

> "A question you haven't tried to *break* is not finished. The manual calls this the
> **dual-topology rule**: grade a good design, expect a pass; grade a gamed design,
> expect a fail *on the intended axis.* Let's actually do both."

**[SCREEN: build the reference topology.]**

> "Reference design: buyers → booking service → **one reservation authority** →
> **relational ledger**, sized to absorb the burst."

```text
reference:  api-endpoint → microservice → reservation-store → relational-db
grade →  structural ✓   semantic ✓   rubric 7/7   →  PASS
         reservations.oversells = 0   (40 seats, each sold exactly once)
```

**[SCREEN: now the subtle cheat — the interesting one.]**

> "Here's the cheat I actually want to show, because it's the one that fools a naive
> question. The student *does* use a reservation store — but to 'scale' it, they run
> **two** of them behind a round-robin, each with its own state. It has a reservation
> authority. It feeds the ledger. It uses a transactional store. Structurally and
> semantically it looks **correct**."

```text
gamed:  api-endpoint → microservice → ⟨round-robin⟩ → reservation-store A ┐
                                                     → reservation-store B ┴→ relational-db
grade →  structural ✓   semantic ✓   BUT rubric 2/7   →  FAIL
         reservations.oversells = 40   (every seat sold twice — once per authority)
```

> "Look at that. Structure passes. Store-fit passes. It fails on **one** thing and one
> thing only — the simulation watched the two authorities each sell all 40 seats and
> counted **40 oversells**. No structural rule could catch this; no store-fit check
> could catch this. Only running the contention forward catches it. *That's* the
> correctness grade that didn't exist before we built the reservation model."

> "And the *other* cheat — buyers wired straight to an in-memory cache with no
> reservation store — fails earlier and louder: `requires_component` says no authority,
> `guardedPath` says the ledger is reachable without a guard, and `storageFit`
> hard-fails on the cache. Different cheat, different axes. To pass, a design has to be
> right on *all* of them at once."

---

## 6. Ship it + recap (15:30–18:30)

> "Let's zoom out. We took the famous Ticketmaster prompt and we did NOT transcribe it.
> We extracted **one lesson** — never double-book. We saw the weight land on
> **Topology + Semantics + Justification**, the correctness-heavy signature. We injected
> a **contended 40-seat burst**, not a marathon. We authored the axes as rows — a
> reservation authority, a guarded path to the ledger, a transactional store, and the
> star: a *simulated* `reservations.oversells == 0`. And we proved it discriminates by
> grading a good design *and* a plausible-looking cheat, and watching the cheat fail on
> exactly the axis that matters."

> "That's the entire craft: pick the lesson, cover orthogonal axes, let the simulation
> carry the correctness a diagram can't assert, and break your own question before a
> student can. This one is live in the bank at `questions/flash-sale-booking/`."

> "If this series helped the mental model click, that's the whole trilogy — from one
> test case, to how grading works, to a full build. Like, subscribe, and tell me which
> famous interview question I should reverse-engineer next. See you around."

**[End card.]**

---

## Author notes (build complete)

- Every row above is copied from the validated
  `system-design-simulator-questions/questions/flash-sale-booking/question.json`.
- The engine build (reservation-store component, `keyspace` workload,
  `reservations.oversells` verdict metric, run-scoped shared trait state) is documented
  in `specs/contended-inventory-and-oversell-model.md` §6.
- **Validated numbers** (injected 1200 rps `book`, 40-seat keyspace): reference →
  oversells 0, PASS 7/7; two-authority gamed → oversells 40, FAIL 2/7.
- `passThreshold` is a **fraction** (0–1), not points. `0.71` makes the 5-pt oversell
  check mandatory: error-rate alone (2/7 ≈ 0.29) cannot clear the bar.
- **B-roll:** the sold-out news clip cold open; the seat map flashing red; the payoff
  shot is the two-authority design passing structure + semantics and then the single
  red `oversells = 40` line — hold on it.
- Keep the prompt HTML showing **real scale** ("sold out in minutes", tens of thousands
  of concurrent buyers) while the suite runs the compressed 1500 rps burst.
- **B-roll:** the sold-out news clip cold open; the seat map flashing red on a
  double-book; the three-way failure of the gamed design is the payoff shot — hold on it.

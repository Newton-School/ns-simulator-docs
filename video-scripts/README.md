# Video Scripts — "Reverse-Engineering the System Design Simulator"

Three tutorial/explainer video scripts in a reverse-engineering format, written in the
**Web Dev Simplified** teaching style (one clear promise up front, teach the *why*
before the *how*, constant small recaps, build it live on screen, no fluff).

Each script is shot-ready: spoken narration, `[SCREEN]` / `[DIAGRAM]` / `[B-ROLL]` cues,
timestamps, and JSON/rows copied from the real authoring format so anything shown on
screen actually validates.

| # | Script | Reverse-engineering angle | Core idea taught |
|---|--------|---------------------------|------------------|
| 1 | [From a test case to a question](01-from-a-testcase-to-a-question.md) | grow a question from one source node up | the Django → simulator → Django round-trip; a question is a pile of small orthogonal checks |
| 2 | [How a question is evaluated](02-how-a-question-is-evaluated.md) | pull a finished question apart to expose the grader | discriminatory authoring; **Axis → Graded by → Measures**; workload characterization; how each dimension is scored |
| 3 | [Building the Ticketmaster question](03-building-the-ticketmaster-question.md) | take the famous "Design Ticketmaster" prompt and author it end-to-end | correctness-heavy authoring (T + J, not Σ); grading correctness with an invariant; the dual-topology honesty test |

## Suggested viewing order
1 → 2 → 3. Video 1 establishes the loop and the "checks, not answers" mindset,
Video 2 gives the grading vocabulary (axes), Video 3 applies both to build something new.

## Grounding sources (source of truth)
- `specs/evaluation-authoring-reference-manual.md` — axes table, workload table,
  dual-topology rule (§1.1–1.3).
- `specs/interview-question-to-django-assignment-translation.md` — the translation
  workflow and requirement-bucket model.
- `examples/question-bank/url-shortener/django-admin-assignment.md`
  — the real row shapes used verbatim in Video 1 and referenced throughout.

## Note on Video 3
The Ticketmaster / flash-sale booking question is **built and in the bank** at
`examples/question-bank/flash-sale-booking/` (question.json +
reference-topology.json + gamed-topology.json). Building it required new engine
capability — a `reservation-store` component with an atomic per-key reserve, a
contended `keyspace` workload, and a `reservations.oversells` verdict metric —
documented in `specs/contended-inventory-and-oversell-model.md`. Every row in the
script is copied from the validated question package; the dual-topology grade is
real (reference PASS 7/7 with 0 oversells; two-authority gamed FAIL 2/7 with 40).

# The Presentation Layer — EnvironmentProfile

> **Theme:** The fourth layer of the platform. An **EnvironmentProfile** is a
> *visibility + capability lens* applied over one shared `QuestionPackage`, so the
> same question runs — unchanged, graded by the same pipeline — as a full
> authoring surface, a locked-down graded contest, or a relaxed learning
> exercise.

This builds the "EnvironmentProfile" follow-up from the mental model
([README](README.md)) and [doc 05](05-design-decisions-and-tradeoffs.md).

---

## 1. Why a separate layer

Recall the governing invariant: **`QuestionPackage` = WHAT**, **`AttemptState` =
the student's work**, and now **`EnvironmentProfile` = HOW MUCH IS SHOWN**. The
grading pipeline is shared by all of them. A question about a URL shortener is one
piece of content; whether the student sees the rubric live, gets three test runs,
or edits the scaffold is *presentation*, not content — and must not require
forking the question or the grader.

```
QuestionPackage("Design a URL shortener")
  + EnvironmentProfile(AUTHOR)    → authoring / testing surface
  + EnvironmentProfile(INTERVIEW) → graded contest, rubric hidden until submit
  + EnvironmentProfile(LEARN)     → self-paced practice, live feedback, ungraded
```

---

## 2. The contract

`src/engine/analysis/environmentProfile.ts`:

```ts
interface EnvironmentProfile {
  mode: 'AUTHOR' | 'INTERVIEW' | 'LEARN'
  visibility: {
    prompt: boolean
    scaffoldSourceNodes: boolean
    gradingSuiteDetails: boolean
    liveMetrics: boolean
    rubricChecks: 'HIDDEN' | 'LIVE_DURING_BUILD' | 'POST_SUBMIT_ONLY'
  }
  capabilities: {
    editPaletteList: string[] | null   // null = all, [] = none
    canEditScaffoldNodes: boolean
    canTriggerTestRuns: boolean
    maxTestRuns?: number               // undefined = unlimited
  }
  graded: boolean
  chromeDensity: 'full' | 'minimal'
}
```

Two axes — **visibility** (what the student can *see*) and **capabilities** (what
they can *do*) — plus `graded` and `chromeDensity`.

---

## 3. The three presets

| Field | AUTHOR | INTERVIEW | LEARN |
|-------|--------|-----------|-------|
| `visibility.rubricChecks` | LIVE_DURING_BUILD | **POST_SUBMIT_ONLY** | LIVE_DURING_BUILD |
| `visibility.gradingSuiteDetails` | true | **false** | true |
| `capabilities.canEditScaffoldNodes` | true | **false** | true |
| `capabilities.maxTestRuns` | unlimited | **3** | unlimited |
| `graded` | true | true | **false** |
| `chromeDensity` | full | minimal | minimal |

**Note on AUTHOR + `graded`.** The spec matrix lists AUTHOR as *ungraded*; here
AUTHOR is set `graded: true`. AUTHOR doubles as the standalone dev/testing mode,
where exercising the grade → seal → archive path (docs 06) is exactly what you
want. This is a deliberate, documented deviation.

---

## 4. Resolving a profile — total and safe

Hosts send either a mode string (`"INTERVIEW"`) or a partial override
(`{ mode: 'INTERVIEW', capabilities: { maxTestRuns: 1 } }`). `resolveEnvironmentProfile`
turns *anything* — including `unknown` / malformed input — into a complete
profile:

```ts
resolveEnvironmentProfile()                              // → AUTHOR (default)
resolveEnvironmentProfile('LEARN')                       // → LEARN preset
resolveEnvironmentProfile({ mode: 'LEARN', graded: true })// → LEARN, graded flipped
resolveEnvironmentProfile(42)                            // → AUTHOR (safe fallback)
```

It is **total and never throws**: a malformed launch payload falls back to the
default profile rather than breaking question mode (same "absence is never
success, but never crash the student" posture as the rest of the platform). Unknown
keys are stripped, so a richer future host payload still resolves.

---

## 5. Where the profile lives and how it flows

```mermaid
flowchart LR
  Host["Host launch-context<br/>environmentProfile: 'INTERVIEW'"] --> WL[WorkspaceLayout]
  WL -->|resolveEnvironmentProfile| Store[(store.environmentProfile)]
  Store --> QP[QuestionPanel gates]
```

- The **store** holds the *resolved* profile, defaulting to AUTHOR (so the
  standalone app is unaffected).
- **WorkspaceLayout** resolves the launch payload's `environmentProfile` on a
  valid launch-context and sets it; it resets to AUTHOR when the question closes.
- **QuestionPanel** reads it and applies the gates.

---

## 6. The gates applied in this slice

Two pure helpers make the decisions (unit-tested, DOM-free):

- `shouldShowRubricResults(profile, { hasSubmittedGrade })` — HIDDEN → never;
  LIVE_DURING_BUILD → always; POST_SUBMIT_ONLY → only once a *submitted* grade
  exists.
- `canTriggerTestRun(profile, { testRunCount })` — false if disabled, or once
  `testRunCount` reaches `maxTestRuns`.

Applied in `QuestionPanel`:

| Gate | Behaviour |
|------|-----------|
| **Rubric timing** | In INTERVIEW the checklist + summary are masked ("revealed after you submit") until a submission exists; HIDDEN hides them entirely; LIVE shows them as before. |
| **Test-run limit** | The Test button disables at the cap and shows "N left"; unlimited modes show no suffix. |
| **Graded submit** | The Submit button only renders when `graded` — LEARN has no submit-for-grade, and only graded modes seal + archive an envelope. |
| **Prompt visibility** | When `visibility.prompt` is false the Brief tab and its content are hidden and the panel shows Tests only. |
| **Palette allowlist** | `capabilities.editPaletteList` filters the component library (`LibrarySidebar`) to the allowed node types/ids; `null` = all. Curates the palette for INTERVIEW. |
| **Chrome density** | `chromeDensity: 'minimal'` drops the authoring file operations (Open/Save/Auto-Layout + file status) from the header for a cleaner INTERVIEW/LEARN surface. |

---

## 7. What is intentionally *not* applied yet

These fields exist in the contract but their UI application is still deferred:

- **`capabilities.canEditScaffoldNodes` + `visibility.scaffoldSourceNodes`** —
  require a new *node-provenance* mechanism (tag which nodes came from the
  scaffold) before they can lock/badge those nodes on the canvas.
- **`visibility.liveMetrics`** — entangled with the metric-lens/canvas overlay
  system.
- **`visibility.gradingSuiteDetails`** — no suite-scenario surface is shown in the
  student panel yet, so there is nothing to gate.
- **Host-driven lifecycle commands** (`reset` / `lock` / `reveal`) — the profile
  covers reveal-timing; explicit host commands are still open (doc 07 §8).

The contract is complete, so these become "apply an existing flag" follow-ups
(once their prerequisite exists), not redesigns.

> **Applied in a later slice:** `editPaletteList` (palette allowlist) and
> `chromeDensity` (minimal header) are now wired — see §6.

---

## 8. Design decisions & trade-offs

Logged in [doc 05](05-design-decisions-and-tradeoffs.md) as **D23–D25**.

| # | Decision | Criteria | Trade-off |
|---|----------|----------|-----------|
| **D23** | A profile is a lens over one QuestionPackage, not a question variant | Isolation, Evolvability | Every gated surface must consult the profile rather than hardcoding a mode |
| **D24** | `resolveEnvironmentProfile` is total & safe (bad input → default) | Honesty, Shippability | A malformed profile silently degrades to AUTHOR rather than erroring |
| **D25** | AUTHOR is `graded: true` (deviates from the spec matrix) | Shippability | AUTHOR/standalone can exercise the graded path; differs from the spec's "AUTHOR ungraded" |

---

## 9. What to take away

1. **Presentation is a lens, not a fork.** One question, one grader, three
   experiences — selected by a profile.
2. **Resolve untrusted config totally and safely** — a bad profile must never
   break the student's session.
3. **Keep the gate decisions pure** (`shouldShowRubricResults`,
   `canTriggerTestRun`) so they're testable away from the UI.
4. **A complete contract lets you ship gates incrementally** — the unapplied
   fields are follow-ups, not blockers.

**Related:** [doc 05 — Design Decisions](05-design-decisions-and-tradeoffs.md)
(D23–D25), [doc 06](06-grading-safe-persistence-and-the-evaluation-envelope.md)
(the graded path AUTHOR exercises), and the architecture spec's Layer 3.

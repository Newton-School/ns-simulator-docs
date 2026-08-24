# DOC-PROMPTS - Reusable Prompts for Generating Project Docs

> Project-agnostic prompt templates for generating three complementary documents:
> an **ADR** (why), a **Spec** (what), and an **Implementation doc** (how). Drop this
> file into any repo. Fill the `{{PLACEHOLDERS}}`, point the model at your codebase,
> and run them in order - **ADR → Spec → Implementation** - so each doc builds on the
> one before it.

## How to use

1. **ADR first** - decide *whether/why*. Get it reviewed before writing more.
2. **Spec next** - define *what*, citing the approved ADR.
3. **Implementation last** - describe *how*, citing both.

Optional clauses you can paste into any of the three prompts:

- **House style:** `Match the tone, headings, and formatting of {{EXAMPLE_DOC_PATH}}.`
- **Length control:** `Target {{N}} pages; prefer tables and code blocks over prose.`
- **Audience:** `Write for {{AUDIENCE - e.g. new engineers / reviewers / a skeptical stakeholder}}.`

---

## 1) ADR prompt - record the decision

```
You are a staff engineer writing an Architecture Decision Record (ADR).

GROUND YOURSELF FIRST (do not invent - cite specifics):
- Read the relevant code/config for {{AREA}} and any prior ADRs or design docs.
- List the real constraints already in play (existing patterns, dependencies, SLAs,
  team conventions).

THE DECISION TO RECORD:
{{ONE_SENTENCE_DECISION - e.g. "Adopt X for Y", "Replace A with B"}}

WRITE THE ADR WITH THIS STRUCTURE:
1. Title + Status (Proposed | Accepted | Superseded) + Date + Deciders.
2. Context - the problem/forces driving this decision; what's painful today; who is
   affected. Tie it to a concrete example.
3. Options considered (>=3), each with honest pros/cons and a "when this would be the
   right choice." Include the do-nothing / status-quo option.
4. Decision - the chosen option in one clear paragraph, and the single most important
   reason it beat the runner-up.
5. Consequences - what becomes easier, what new cost/maintenance/risk appears, what can
   drift over time, and how you'll know if this decision was wrong (the trigger to
   revisit).
6. (Optional) Boundaries - what this decision explicitly does NOT cover.

RULES: decision-oriented, not a tutorial; every claim maps to a real file/constraint;
name the runner-up and why it lost; <= 2 pages; no hedging - commit to the call.
```

---

## 2) Spec prompt - define the contract

```
You are writing a technical specification for {{FEATURE_OR_COMPONENT}}.

GROUND YOURSELF FIRST:
- Read the approved ADR (if any) and the existing code/interfaces this touches.
- Capture every unknown as an explicit Assumptions list - never leave a field implicit.

WRITE THE SPEC WITH THIS STRUCTURE:
1. Title + one-paragraph intro (what it is, who uses it, when).
2. Problem Context - the need, and why the current state is insufficient.
3. Goals & Non-Goals - bullet lists; be explicit about what's out of scope.
4. How it works - the mechanism/behavior, precisely enough to implement from. Include
   data shapes, state transitions, and the "happy path" plus key edge cases.
5. Interface / Contract - inputs, outputs, error modes, and invariants. Use concrete
   types/schemas/signatures, not prose.
6. Dependencies & Integration - what it requires, what calls it, and the seams.
7. Failure modes & Guardrails - what must never happen; validation performed.
8. Acceptance criteria - testable statements ("given X, produces Y with Z holding").
9. Open questions / Assumptions.
10. Source map - for each requirement, the file/module that will (or does) own it, so
    there are no orphan requirements.

RULES: define each term once; every requirement is backed by a check (no orphans);
prefer concrete examples over adjectives; it's a contract, not marketing.
```

---

## 3) Implementation doc prompt - describe how it's built

```
You are documenting the implementation of {{FEATURE_OR_COMPONENT}} for the engineers
who will build, review, and maintain it.

GROUND YOURSELF FIRST:
- Read the approved Spec and ADR (link them) and the actual code as it stands.
- Do not restate the Spec as prose - this doc is about the HOW, mapped to real code.

WRITE THE IMPLEMENTATION DOC WITH THIS STRUCTURE:
1. Title + links to the Spec and ADR it realizes.
2. Overview - the shape of the solution in 3-5 sentences.
3. Architecture / Components - each module/file created or changed, and its single
   responsibility. A small diagram or call-flow if it helps.
4. Key implementation details - the non-obvious decisions, algorithms, data
   structures, and any tradeoffs made during coding (with the reason).
5. Step-by-step build plan - the ordered changes (PR-sized), each with its acceptance
   criterion, so someone could reproduce the work.
6. Testing & verification - unit/integration/e2e coverage, how to run it, and the
   evidence that it meets the Spec's acceptance criteria.
7. Rollout / migration / config - flags, backward-compat, data migration, and the
   rollback plan.
8. Gotchas & maintenance - known limitations, drift risks (what upstream changes would
   break this), and where to look first when it fails.

RULES: reference real files/functions by path; state what was NOT done and why; show
verification evidence (commands + expected output), don't just claim it works.
```

---

## Why three docs (the split)

| Doc | Answers | Audience | Lifespan |
|-----|---------|----------|----------|
| **ADR** | *Why* this choice, over what alternatives | future maintainers, reviewers | permanent (immutable record) |
| **Spec** | *What* it must do - the contract | implementers, testers, integrators | until superseded |
| **Implementation** | *How* it was built, and how to run/verify | builders, on-call, code reviewers | living (updated with the code) |

Keeping them separate prevents the common failure where a single doc mixes a
half-committed decision, a fuzzy contract, and stale build notes. Cross-link all
three so a reader can trace *why → what → how* in one hop each direction.

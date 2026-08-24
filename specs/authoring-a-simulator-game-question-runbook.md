# Runbook - Authoring a System Design Simulator Question

> **Audience:** faculty / content authors adding a system-design simulator
> question to the platform. **No engineering needed** - it's a normal GAME
> question on the existing Game Playground rails.
>
> **Mental model:** the simulator is a **game at a URL**. newton-api stores the
> question (`game_url` + the QuestionPackage in `initial_game_state`); newton-web
> embeds it in an iframe and relays state; the browser grades and posts pass/fail;
> newton-api stores that verbatim. **This version does no server-side grading.**

---

## 0. What lives where (one glance)

| Repo | Its job for a simulator question | Do you touch it? |
|------|----------------------------------|------------------|
| **newton-api** | Stores the GAME `AssignmentQuestion` (`game_url`, `initial_game_state`), the learner's `GamePlayground.game_json`, the pass snapshot | **Only authoring** - no code |
| **newton-web** | Renders the iframe, relays postMessage, PATCHes each save | No - generic host, unchanged |
| **ns-simulator** | Runs the design, grades it in the browser, posts the result | No - deployed once; you point `game_url` at it |

---

## 1. Prerequisites

- The **simulator is deployed** at a stable HTTPS URL (or, for local testing, a
  dev server - see §6). The embed URL must include **`?host=newton`**.
- You can reach the **Django admin** (with a user that has
  `assignments.can_preview_assignment_question` - superusers have it).
- You have a **QuestionPackage JSON** ready (§3).

---

## 2. Create the question (Django admin)

1. **Admin → Assignment questions → Add.**
2. **Question type = `Game`.**
3. **Question title** + (optional) question text.
4. **Game url** = the simulator embed URL **with `?host=newton`**:
   - prod: `https://<deployed-simulator>/?host=newton&hostOrigin=https://my.newtonschool.co`
   - local: `http://localhost:5173/?host=newton` (match your dev port)
   - `hostOrigin=` makes the simulator's origin check strict (recommended in prod).
5. **Initial game state** = paste the **QuestionPackage JSON** (§3). This is the
   whole question - prompt, scale, scaffold, rules, rubric.
6. **Save.**
7. **Preview Question** (top-right, next to History) → opens a real playground in
   newton-web. Actually play it - there are no automated checks for games.
8. **Peer review** (someone other than the author solves it once). ⚠️ After peer
   review, **`game_url` and `initial_game_state` freeze** - iterate on a
   throwaway staging question first.
9. **Deliver:** create a **Game** row + **Course structure game mapping** (the
   games tab, the usual path) and/or map into an assignment.

---

## 3. The QuestionPackage (what goes in `initial_game_state`)

Paste the full package. The simulator grades itself from it. Minimum viable
skeleton (see the engine's `QuestionPackage` schema for all fields):

```json
{
  "version": "1.0",
  "id": "url-shortener-v1",
  "title": "Design a URL shortener",
  "difficulty": "intermediate",
  "type": "open-build",
  "prompt": {
    "text": "One-paragraph problem statement (markdown).",
    "functionalRequirements": ["...", "..."],
    "nonFunctionalRequirements": [
      { "metric": "latency_p99", "operator": "<", "value": 100, "unit": "ms", "description": "p99 < 100ms" }
    ],
    "scale": { "dau": 50000000, "peakRps": 200000, "readWriteRatio": 99 }
  },
  "scaffold": { "type": "empty" },
  "constraints": { "canModifyScaffold": true, "canRemoveScaffoldNodes": true, "maxNodeCount": 12 },
  "structuralRules": [
    { "id": "has-lb", "kind": "requires_component", "componentType": "load-balancer", "description": "..." },
    { "id": "single-source", "kind": "requires_single_source", "description": "..." }
  ],
  "semanticCriteria": [
    { "id": "reads-through-cache", "kind": "guardedPath",
      "from": "microservice", "guard": "in-memory-cache", "to": "kv-store", "points": 3,
      "description": "Reads must traverse a cache before the store" }
  ],
  "suite": {
    "name": "url-shortener-suite",
    "visibleToStudent": false,
    "cases": [
      { "id": "baseline", "description": "Nominal load." },
      { "id": "peak", "global": { "seed": "peak-seed" }, "workload": { "baseRps": 200000 }, "description": "Peak." }
    ]
  },
  "rubric": {
    "id": "url-shortener-rubric",
    "passThreshold": 1,
    "checks": [
      { "id": "p99", "kind": "simulation", "metric": "summary.latencyP99Ms", "op": "<", "value": 100, "points": 2, "description": "p99 < 100ms" },
      { "id": "no-invariants", "kind": "invariant", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1, "description": "No invariant violations" }
    ]
  }
}
```

**The three grading axes you author** (all graded in the browser):
- **`structuralRules`** - graph facts (has a load balancer, single source, a path exists). Runs first; if these fail, simulation is skipped.
- **`semanticCriteria`** - architecture invariants (`guardedPath`, `storageFit`, `fanout`, `placement`, `forbidUnjustified`). See `question-grading-model-and-anti-gaming.md` §4/§4.1.
- **`rubric`** - runtime metrics after simulating under the hidden `suite` load (p99, error rate, invariants).

> **Note on `description`:** it's a human label - never parsed. The `kind` +
> typed fields are what actually grade. Verify a boundary by testing, not by the
> prose (§4).

---

## 4. Verify the question before you ship it

Grade a **reference** (correct) design and a **deliberately-wrong** design so you
know the rubric actually discriminates. Two ways:

- **In-app:** open Preview Question, build a correct design → should pass; build a
  gamed one (e.g. no cache, or a `relational-db` at a point-lookup) → should fail
  the relevant axis.
- **CLI (authoring):**
  ```bash
  sim evaluate question package.json reference-topology.json   # expect full marks
  sim evaluate question package.json gamed-topology.json       # expect a failure
  ```

**Rule of thumb:** every gamed design must lose at least one axis. If a gamed
design passes, tighten `semanticCriteria`/`rubric`.

---

## 5. Confirm a submission persisted (sanity check)

After a learner (or you) submits, the result lands in `GamePlayground.game_json`:

```bash
python manage.py shell -c "from playgrounds.models import GamePlayground; g=GamePlayground.objects.get(hash='<HASH>').game_json; print('passed:', g.get('test_cases_passed'), '| all:', g.get('all_test_cases_passed'), '| has topology:', 'topology' in g)"
```
Expect the two score keys + `has topology: True`. The backend **stores this
verbatim and trusts it** - it does not re-grade.

---

## 6. Local testing (without deploying)

1. Run the simulator dev server (`npm run dev:web`) - note its port (Vite default
   `5173`).
2. Set `game_url = http://localhost:<port>/?host=newton`.
3. Run **newton-web** locally (its origin allow-list already includes
   `localhost:3000/3001`) and **newton-api** locally.
4. Preview Question → the iframe loads your local simulator → build → Submit →
   check §5.

If the iframe is blank: confirm the simulator dev server is on the exact port in
`game_url`, and that newton-web actually compiled (a missing `content_platform`
alias will fail the whole playground route - that's a newton-web env issue, not
the question).

---

## 7. Gotchas

- **Freezing:** `game_url` + `initial_game_state` are immutable after peer review;
  test-case rows freeze at verified. No sanctioned unfreeze - fix a frozen
  question by creating a fresh one. Iterate on staging first.
- **No server grading (this version):** scores are client-computed and trusted.
  Fine for practice; a real graded assessment needs the deferred server-side
  re-grade (see `newton-api-backend-integration.md` §6).
- **`initial_game_state` size:** no hard cap; the ~2-4 KB package is fine (the
  "tiny in prod" norm is convention).
- **Semantic axis is graded now**, but `forbidUnjustified` needs a justification
  answer to defend a present component - until justification capture is wired, a
  present-but-undefended component fails (grading-model spec §4.1).
- **Score-key meaning:** the simulator reports `test_cases_passed` = passed-check
  count and `all_test_cases_passed` = overall pass. The platform treats
  `test_cases_passed`'s magnitude as a free per-game semantic (no marks depend on
  it for this game type).

---

## 8. Where the code actually is (for engineers)

- **newton-api / newton-web:** unchanged - the simulator question is pure
  authoring on the existing Game Playground rails.
- **ns-simulator:** the Newton wire adapter (`engine/analysis/newtonGamePlayground.ts`
  + `renderer/utils/newtonHostMessaging.ts`), wired into `WorkspaceLayout.tsx`
  (handshake + seed) and `QuestionPanel.tsx` (submit). Selected by `?host=newton`.
- Full design: `newton-api-backend-integration.md`.

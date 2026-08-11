# System Design Simulator — newton-api Integration (Game Playground)

> **Purpose.** Define how the ns-simulator plugs into `newton-api`. The simulator
> is a **GAME question on the existing Game Playground rails** — *not* a custom
> stack. This supersedes an earlier draft of this doc that invented dedicated
> models/endpoints; see §7.
>
> **This version (V1) is client-computed. There is no server-side / Django
> grading.** The simulator calculates everything in the browser (the iframe);
> the iframe posts pass/fail + topology + scores over the Game Playground
> `postMessage` contract; `newton-web` PATCHes that blob into
> `GamePlayground.game_json`; `newton-api` **stores it verbatim and trusts it**.
> The backend never runs the engine, never simulates, never re-grades. See §0.
>
> **Scope note.** Standalone from the existing subjective System Design playground
> (`AssignmentQuestionType.SYSTEM_DESIGN` → `SubjectiveSubmission`, LLM-graded).
> Different question type, different rails; the two coexist.
>
> **Companion docs.** *Game Playground — End-to-End Documentation* (the
> authoritative platform contract across newton-api / newton-web / game bundles).
> The simulator-side embed contract is in `docs/question-platform-hardening/`
> (02/07); the grading engine axes in `question-grading-model-and-anti-gaming.md`.

---

## 0. This version: everything is computed in the frontend

```
ns-simulator (iframe)                 newton-web (host)            newton-api (Django)
  runs the engine in the browser
  (structural + rubric + semantic
   + justification → pass/fail)
        │ postMessage(state) ───────►  PATCH game_json ──────────►  store game_json verbatim
        │  { topology, test_cases_passed,                            read test_cases_passed +
        │    all_test_cases_passed, ... }                            all_test_cases_passed  ✓ trust
        ◄─ seed (initial_game_state) ─  push seed into iframe
```

- **All grading happens in the iframe.** The simulator already grades a whole
  `QuestionPackage` client-side (`gradeAttempt`) and collapses it to a host
  contract of pass/fail rows.
- **The iframe posts a JSON blob** containing the topology, the two required
  score keys, and whatever else it needs to restore itself.
- **`newton-api` does not grade.** It persists `game_json` and trusts
  `test_cases_passed` / `all_test_cases_passed` verbatim — exactly as it does for
  every other game (block games, math games, packet-tracer).
- **Server-authoritative grading is explicitly out of scope for this version.**
  It is the future anti-gaming lever (§6), not built now — the Game Playground
  model itself does no server evaluation (packet-tracer "plans but has not built"
  it either).

Because grading is client-side, **scores are client-reported and therefore
gameable** — acceptable for an ungraded/practice ship, not for a real graded
assessment. That trade is deliberate for V1 (§6).

---

## 1. The correction: use the existing Game Playground rails

A game question is **not** a new set of tables — it is an `AssignmentQuestion`
with a `game_url`. Do **not** build parallel models/endpoints.

| Concern                 | ❌ Don't build                         | ✅ Existing rail                                                                                                                                |
| ----------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| The question            | a custom `SystemDesignQuestion` model | **`AssignmentQuestion`**, `question_type = GAME (5)`, with `game_url` + `initial_game_state` (`assignments/models.py`)                         |
| The "test cases"        | a `question_package` field of checks  | authored **inside the package** (V1) — or `AssignmentQuestionTestCaseMapping` rows if we ever go flavor-c (§2)                                 |
| Learner workspace/state | a custom submission model             | **`GamePlayground.game_json`** — auto-created on first question GET; opaque to the backend except the two score keys                           |
| Submit / persist        | a custom `POST …/submit/` → 202       | **`PATCH /api/v1/playground/game/h/{hash}/`** — persists `game_json`, reads the two flags (`playgrounds/views.py`)                             |
| Pass snapshot           | a custom row                          | **`GamePlaygroundSubmission`** — created once on `all_test_cases_passed` False→True                                                            |
| Embed / launch          | a custom `…/launch/` endpoint         | `newton-web` renders `<iframe src=game_url>` and pushes the seed; the playground is auto-created by the course/arena flow. No launch endpoint. |
| Grading trigger         | a Celery task calling the engine      | **none in V1** — the iframe grades and reports; the backend trusts it                                                                          |

The backend "cannot tell the flavors apart" — a game is identified by its
`game_url`, not by a subtype or a bespoke model.

---

## 2. The ns-simulator as a GAME question (flavor a/b)

The simulator is a **self-contained** game: it owns the whole `QuestionPackage`
and grades itself from it. That makes it **flavor (a/b)** in the platform's
taxonomy (in-built logic, seed carries config), *not* flavor-(c) (rubric rows
the host forwards to a game that doesn't own its checks — the packet-tracer case).

**Authoring shape:**

- **`game_url`** = the deployed ns-simulator embed URL (its exact origin becomes
  the host's inbound guard, `game_url.startsWith(event.origin)`).
- **`initial_game_state`** = the **`QuestionPackage` JSON** (Strategy A). The
  field is a `JSONField` with no size cap — the "≤70 chars in prod" is convention,
  not a limit; our ~2–4 KB package fits fine.

**Why the package goes in the seed (not test-case rows):** our engine grades a
*whole* interdependent package — the structural gate short-circuits the
simulation, justification feeds `forbidUnjustified`, the rubric runs a full
simulation suite. Those axes don't decompose into the independent per-row checks
that flavor-(c) rows model. Putting the package in `initial_game_state` fits the
engine with zero decomposition. (Revisit flavor-c only if faculty later need
per-check *admin-row* editing.)

**Carry-forward (important):** after the first save the host sends `game_json`
instead of `initial_game_state` as the seed base. So the simulator must **echo
the `QuestionPackage` back inside `game_json` on every save** — the same way
packet-tracer carries `topology_xml` forward. ~4 KB per save, harmless.

---

## 3. The real work: the simulator's iframe contract

Almost all of V1 is **simulator-side**, building on the existing Game Playground
adapter (`feat(embed): adopt Game Playground host payloads`,
`feat(host): add Game Playground payload adapter`). The iframe must:

1. **Handshake** — register a message listener, then post the raw string
   `'ready-event'` to `window.parent`. Expect the seed twice (onLoad + ready).
2. **Parse the seed** — a JSON string = the last `game_json` **or**
   `initial_game_state` on first open, plus host metadata (`playgroundHash`,
   `read_only`, …). Extract the `QuestionPackage` from it. Tolerate unknown keys.
3. **Grade client-side** — run `gradeAttempt(package, topology)` in the browser;
   collapse to the host contract (pass/fail).
4. **Post state** — `JSON.stringify` a blob and post it to the parent. It **must**
   include:
   - `topology` — the student's design (so it persists / restores),
   - `test_cases_passed` (int) — map from the host contract (e.g. passed check
     count, or points earned),
   - `all_test_cases_passed` (bool) — the overall pass,
   - the `QuestionPackage` carried forward (§2),
   - any advisory verdict/rubric detail needed to restore the UI on reload.
     Post on meaningful progress and in reply to the raw `'save'` command.
5. **Origin discipline** — allow-list inbound origins, or TOFU-pin the first
   valid parent (packet-tracer's approach); never post to `'*'` once pinned.
6. **`read_only`** — honor it (no edits/submit in mentor view); **standalone** —
   degrade to `localStorage` when there is no parent frame.

**Score-key mapping** is the one design choice: decide what `test_cases_passed`
counts for the simulator (passed-check count vs points earned) — the platform
treats it as a free per-game semantic (only the NST-Samurai invoice path
hard-codes a threshold, which is irrelevant here). `all_test_cases_passed` = the
simulator's overall pass. **Send real booleans** (a missing `all_test_cases_passed`
is silently coerced to `False`; a missing `test_cases_passed` on a mapped save is
a 400).

---

## 4. Authoring a question (no backend code)

In the existing Django admin — the standard GAME flow, no new admin:

1. **Assignment Question → type Game.** Fill title/text (the simulator can render
   the prompt from the package; the host doesn't show `question_text` for
   non-packet-tracer games).
2. **Set `game_url`** = the deployed ns-simulator embed.
3. **Set `initial_game_state`** = the `QuestionPackage` JSON (§2, §8 example).
4. **Verify** (there are no automated checks for games — actually play it via
   "Preview Question", which opens a real milestone playground).
5. **Peer review** (solve-before-review applies). After this, `game_url` and
   `initial_game_state` are **immutable** — iterate on a throwaway staging
   question first.
6. **Deliver** — create a `Game` row + `CourseStructureGameMapping` (the games
   tab, the dominant path) and/or map into an assignment.

---

## 5. Persistence & scoring (the existing PATCH — we add nothing)

`PATCH /api/v1/playground/game/h/{hash}/` (`playgrounds/views.py`):

- Permission `IsPlaygroundOwner`; a locked playground rejects with 400.
- Persists the posted blob as `game_json` **verbatim** (last-write-wins, no merge).
- When an assignment/milestone mapping exists: reads `test_cases_passed`
  (int-coerced) and `all_test_cases_passed` (bool/`strtobool`), raises
  `max_test_case_passed` monotonically, and flips `all_test_case_passed` only
  False→True — on that transition it creates the `GamePlaygroundSubmission`
  snapshot and fires completion (marks/XP).
- **No grading, no engine, no simulation on the server.** The two flags are taken
  verbatim.

There is nothing for us to add to the backend for V1.

---

## 6. Explicitly deferred (later versions)

- **Server-authoritative grading** — the future anti-gaming lever: a backend
  re-run of the engine (`sim evaluate` / an `ns-grading` service) from the
  server's package, ignoring the client's claim. This is the *one* genuinely new
  backend piece and is **out of scope for this version**. The Game Playground
  model does no server eval today; packet-tracer plans-but-hasn't-built the same.
- **Flavor-c rubric rows** — only if faculty need per-check admin-row editing.
- **Durable cross-device autosave** beyond `game_json`.

Anti-gaming honesty: under client-only V1 the score is whatever the iframe posts
and is forgeable. Fine for ungraded/practice; the server re-grade above is what
makes it real, and it's deliberately later.

---

## 7. Custom code to remove (superseded)

An earlier pass added a **parallel stack** to `playgrounds/` that this design
replaces. It should be backed out (unapply the migration first, since it was
applied locally):

```
python manage.py migrate playgrounds 0159_external_playground
```

then remove: the `SystemDesignQuestion` + `SystemDesignSimulatorSubmission`
models, `SystemDesignSimulatorMode` / `GamePlaygroundSubType.SYSTEM_DESIGN_SIMULATOR`
enums, their serializers/views/urls/admin, migration `0160_system_design_simulator`,
and `fixtures/system_design_simulator_seed.json`. None of it is needed under the
Game Playground rails.

---

## 8. Concrete example — a QuestionPackage as `initial_game_state`

The value pasted into a GAME question's `initial_game_state`. (Valid engine
types; the simulator self-grades from this. The `semanticCriteria` axis is now
implemented — see the grading-model spec §4.1.)

```json
{
  "version": "1.0",
  "id": "url-shortener-v1",
  "title": "Design a URL shortener",
  "difficulty": "intermediate",
  "type": "open-build",
  "workloadCategory": "read-heavy",
  "prompt": {
    "text": "Design a URL shortener that stays fast and available under a read-heavy load. Reads dominate writes ~100:1.",
    "functionalRequirements": ["Create a short code for a long URL", "Redirect a short code to its long URL"],
    "nonFunctionalRequirements": [
      { "metric": "latency_p99", "operator": "<", "value": 100, "unit": "ms", "description": "p99 redirect latency under 100ms" }
    ],
    "scale": { "dau": 50000000, "peakRps": 200000, "readWriteRatio": 99 }
  },
  "scaffold": { "type": "empty" },
  "constraints": { "canModifyScaffold": true, "canRemoveScaffoldNodes": true, "maxNodeCount": 12 },
  "structuralRules": [
    { "id": "has-lb", "kind": "requires_component", "componentType": "load-balancer", "description": "A load balancer must front the service" },
    { "id": "single-source", "kind": "requires_single_source", "description": "Exactly one client/source of traffic" }
  ],
  "semanticCriteria": [
    { "id": "reads-through-cache", "kind": "guardedPath", "description": "Redirect reads must traverse a cache before the store",
      "from": "microservice", "guard": "in-memory-cache", "to": "kv-store", "points": 3 }
  ],
  "suite": {
    "name": "url-shortener-suite",
    "visibleToStudent": false,
    "cases": [
      { "id": "baseline", "description": "Nominal read-heavy load." },
      { "id": "peak", "description": "Peak redirect storm, fresh seed.", "global": { "seed": "url-shortener-peak" }, "workload": { "baseRps": 200000 } }
    ]
  },
  "rubric": {
    "id": "url-shortener-rubric",
    "passThreshold": 1,
    "checks": [
      { "id": "p99-latency", "kind": "simulation", "description": "p99 redirect latency under 100ms", "metric": "summary.latencyP99Ms", "op": "<", "value": 100, "points": 2 },
      { "id": "no-invariants", "kind": "invariant", "description": "No invariant violations", "metric": "invariantViolations.count", "op": "==", "value": 0, "points": 1 }
    ]
  },
  "author": "faculty@newtonschool.co"
}
```

On submit, the iframe grades this in the browser and posts, e.g.:

```json
{
  "topology": { "nodes": [ /* … student design … */ ], "edges": [ /* … */ ] },
  "questionPackage": { /* carried forward, §2 */ },
  "test_cases_passed": 3,
  "test_cases_total": 4,
  "all_test_cases_passed": false,
  "rubric_results": [ /* advisory per-check detail for UI restore */ ]
}
```

`newton-api` stores that blob as `game_json` and records
`test_cases_passed = 3`, `all_test_cases_passed = false`. It does **not** verify
any of it — that is this version's defining constraint.

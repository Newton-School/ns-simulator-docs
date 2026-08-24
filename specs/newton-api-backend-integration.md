# System Design Simulator - newton-api Integration (Game Playground)

> Purpose: define how the ns-simulator should integrate with `newton-api` and
> the generic Newton Game Playground host.
>
> This document replaces the earlier "Strategy A" recommendation that stored the
> full authored `QuestionPackage` inside `initial_game_state`. That approach is
> wrong for graded content because `initial_game_state` is copied into
> `GamePlayground.game_json`, and `game_json` is learner-mutable.

## 0. Core rule

Split question data into two classes:

- Immutable authored question definition:
  - student-visible prompt text
  - scaffold / suite / constraints
  - structural rules
  - semantic criteria
  - rubric checks
  - justification prompts
- Mutable learner state:
  - current topology
  - attempt metadata
  - saved run results
  - `test_cases_passed`
  - `all_test_cases_passed`

Only the second class belongs in `initial_game_state` / `game_json`.

## 1. What already exists on the platform

The generic GAME rails already give the simulator everything packet-tracer uses:

- `AssignmentQuestion.question_title`
- `AssignmentQuestion.question_text`
- `AssignmentQuestion.initial_game_state`
- `AssignmentQuestion.assignment_question_test_case_mappings`
- `GamePlayground.game_json`

`newton-web`'s generic game host already pushes the iframe a JSON seed shaped like:

```json
{
  "...game_json_or_initial_game_state": "...",
  "playgroundHash": "abc123",
  "question_title": "Design a URL shortener",
  "question_text": "<p>...</p>",
  "read_only": false,
  "rubric": [
    {
      "hash": "rowhash",
      "title": "Check title",
      "hidden": false,
      "spec": { "...parsed row.input JSON..." }
    }
  ]
}
```

This is already enough for packet-tracer-style authoring. No new `newton-api`
model or endpoint is required.

## 2. Recommended authoring model

Treat the simulator as a normal GAME question, but author it like packet tracer:

- `question_title`:
  - the display title
- `question_text`:
  - the learner-facing statement
- `initial_game_state`:
  - only mutable learner seed
- `assignment_question_test_case_mappings`:
  - immutable simulator config and immutable grading specs

The simulator frontend reconstructs its internal `QuestionPackage` from:

1. host metadata:
   - `question_title`
   - `question_text`
2. parsed test-case rows:
   - `rubric[].spec`
3. mutable seed:
   - `game_json` or `initial_game_state`

### 2.1 What belongs in `initial_game_state`

Only the learner seed. Examples:

- empty build:

```json
{}
```

- scaffolded build:

```json
{
  "topology": {
    "version": "2.0.0",
    "nodes": [],
    "edges": [],
    "scenario": {
      "sourceNodeId": null,
      "durationMs": 60000,
      "warmupMs": 5000,
      "seed": "default"
    }
  }
}
```

Do not put any of these in `initial_game_state`:

- problem statement
- FR / NFR / scale metadata
- rubric checks
- suite definitions
- semantic criteria
- structural rules

### 2.2 What belongs in test-case rows

Use `AssignmentQuestionTestCaseMapping.input` as the immutable machine-readable
carrier, just like packet tracer does.

Recommended split:

- one config row
- many grading rows

#### Config row

Use one row whose `spec.type` is `SIMULATOR_CONFIG`.

Example:

```json
{
  "type": "SIMULATOR_CONFIG",
  "configVersion": "1.0",
  "questionId": "url-shortener",
  "questionType": "open-build",
  "workloadCategory": "read-heavy",
  "scaffold": { "type": "empty" },
  "constraints": {
    "maxNodeCount": 12,
    "canModifyScaffold": true,
    "canRemoveScaffoldNodes": true
  },
  "suite": {
    "name": "url-shortener-suite",
    "visibleToStudent": false,
    "cases": [
      {
        "id": "peak",
        "description": "Read-heavy peak (injected 99:1)",
        "workload": {
          "baseRps": 2000,
          "requestDistribution": [
            { "type": "read", "weight": 0.99, "sizeBytes": 256 },
            { "type": "write", "weight": 0.01, "sizeBytes": 512 }
          ]
        }
      }
    ]
  },
  "justify": [
    {
      "id": "why-store",
      "boundTo": { "componentType": "kv-store" },
      "decision": "Which storage engine did you choose and why?",
      "requires": { "choice": true, "number": true, "tradeoff": true }
    }
  ]
}
```

#### Grading rows

Use one row per immutable rule/check. The simulator frontend groups them by
`spec.type` and builds the internal authored model.

Examples:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source",
  "description": "Exactly one traffic source"
}
```

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "store-fits-point-lookup",
  "kind": "storageFit",
  "accept": ["kv-store", "nosql-db"],
  "partial": ["in-memory-cache"],
  "antiPattern": ["relational-db"],
  "hardFail": true,
  "points": 3,
  "description": "Short-code lookup is a point-lookup",
  "accessPattern": "point-lookup"
}
```

```json
{
  "type": "RUBRIC_CHECK",
  "id": "p99",
  "kind": "simulation",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 100,
  "points": 3,
  "description": "p99 under 100ms"
}
```

## 3. Two presentation modes

There are two clean ways to show the learner-facing prompt.

### Option 1: raw Django HTML only

How it works:

- `question_title` is the heading
- `question_text` is the complete learner-visible prompt
- the simulator frontend sanitizes and renders that HTML directly
- FR / NFR / scale are not special data structures to the UI; they are just part
  of the authored HTML

What you need to do:

1. Write the whole problem statement in Django's `question_text`.
2. Format FR / NFR / scale as HTML lists / tables / sections manually.
3. Put only machine-readable grading/config data in test-case rows.
4. Update the simulator frontend to render `question_text` in Newton host mode.

Pros:

- fastest to ship
- easiest for content authors
- no extra prompt schema beyond plain HTML

Cons:

- the simulator loses its richer structured prompt cards
- the frontend cannot reliably extract FR / NFR / scale from free-form HTML
- consistency across questions depends on author discipline

Recommendation:

- use this if speed matters more than UI consistency

### Option 2: structured FR/NFR/scale cards preserved

How it works:

- `question_title` remains the heading
- `question_text` is optional supporting prose or fallback HTML
- the config row carries a `presentation` object with structured prompt metadata
- the simulator frontend renders the same FR / NFR / scale cards it uses today

Where the metadata lives:

inside the `SIMULATOR_CONFIG` row in `AssignmentQuestionTestCaseMapping.input`

Example:

```json
{
  "type": "SIMULATOR_CONFIG",
  "configVersion": "1.0",
  "questionId": "url-shortener",
  "questionType": "open-build",
  "presentationMode": "structured",
  "presentation": {
    "prompt": "Design a URL shortener that stays fast and available under a read-heavy load.",
    "functionalRequirements": [
      "Write path: accept a long URL and persist a short-code to long-URL mapping.",
      "Read path: resolve a short code and return an HTTP redirect."
    ],
    "nonFunctionalRequirements": [
      {
        "metric": "latency_p99",
        "operator": "<",
        "value": 100,
        "unit": "ms",
        "description": "Redirect p99 under 100ms at peak."
      }
    ],
    "scale": {
      "dau": 50000000,
      "peakRps": 200000,
      "readWriteRatio": 99
    }
  },
  "scaffold": { "type": "empty" },
  "constraints": { "maxNodeCount": 12, "canModifyScaffold": true, "canRemoveScaffoldNodes": true },
  "suite": { "name": "url-shortener-suite", "visibleToStudent": false, "cases": [] }
}
```

What you need to do:

1. Keep `question_text` for any long-form copy you still want in Django.
2. Add structured prompt metadata under `presentation` in the config row.
3. Update the simulator frontend to prefer `presentation` over raw HTML when
   `presentationMode === "structured"`.
4. Render `question_text` as an optional intro / notes block, not as the source
   of truth for the cards.

Pros:

- preserves the simulator's richer UI
- keeps FR / NFR / scale machine-readable
- consistent layout across all Newton-authored simulator questions

Cons:

- slightly heavier authoring
- requires one simulator-specific config schema and translator

Recommendation:

- this is the better long-term model

## 4. What changes are required

### 4.1 Simulator frontend

Required.

The Newton adapter must stop assuming the full `QuestionPackage` lives in the
seed. Instead it must:

1. read mutable learner state from `game_json` / `initial_game_state`
2. read immutable question metadata from:
   - `question_title`
   - `question_text`
   - `rubric[].spec`
3. translate those inputs into the simulator's internal `QuestionPackage`
4. save only mutable learner state back to `game_json`

Specifically:

- replace the current "seed itself is `QuestionPackage`" fallback
- stop carrying `questionPackage` forward inside every Newton save blob
- keep saving:
  - topology
  - attemptState
  - rubric_results
  - justification_answers
  - `test_cases_passed`
  - `all_test_cases_passed`

### 4.2 Django content authoring

Required.

Questions must be re-authored so immutable content leaves `initial_game_state`.

For each simulator question:

1. move visible statement into `question_text`
2. create one `SIMULATOR_CONFIG` test-case row
3. create one row per structural / semantic / rubric rule
4. reduce `initial_game_state` to mutable seed only

### 4.3 `newton-api`

Not required for the recommended path.

Reason:

- the generic GAME payload already exposes `question_text`
- it already exposes ordered test-case rows
- it already persists mutable learner state

Only build backend changes if you want a dedicated immutable config field instead
of encoding simulator config in test-case rows.

## 5. Authoring examples

### 5.1 Raw HTML mode

Django fields:

- `question_title`:
  - `URL Shortener`
- `question_text`:
  - full prompt HTML, including FR / NFR / scale
- `initial_game_state`:
  - `{}`
- test-case rows:
  - one `SIMULATOR_CONFIG`
  - several `STRUCTURAL_RULE` / `SEMANTIC_CRITERION` / `RUBRIC_CHECK`

### 5.2 Structured cards mode

Django fields:

- `question_title`:
  - `URL Shortener`
- `question_text`:
  - optional intro / supporting notes
- `initial_game_state`:
  - `{}`
- test-case rows:
  - one `SIMULATOR_CONFIG` with `presentation`
  - several `STRUCTURAL_RULE` / `SEMANTIC_CRITERION` / `RUBRIC_CHECK`

## 6. Persistence and trust model

Nothing changes in the backend trust model:

- the iframe still computes grading client-side
- `newton-web` still PATCHes `game_json`
- `newton-api` still trusts `test_cases_passed` and `all_test_cases_passed`

The fix here is narrower:

- authored prompt / rubric config becomes immutable-from-student-view
- mutable learner state stays mutable

This does not make grading server-authoritative. That remains future work.

## 7. Explicitly deferred

- server-side re-grade
- dedicated `newton-api` config field for simulator questions
- migration away from test-case rows to a cleaner question-config model

## 8. Recommendation

If the goal is fastest cleanup, choose:

- Option 1: raw Django HTML only

If the goal is the right long-term product shape, choose:

- Option 2: structured FR / NFR / scale cards preserved

Recommended long-term path:

1. implement the frontend translator
2. support both modes
3. migrate the first question in raw HTML mode if needed for speed
4. standardize future questions on structured mode

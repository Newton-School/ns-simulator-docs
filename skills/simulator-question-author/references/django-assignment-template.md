# Django Assignment Template

Use this template when the user wants the final deliverable in `django-admin-assignment.md` form.

## Skeleton

~~~~md
# Django Admin Setup: <Question title>

This authoring shape is for Newton assignment mode only.

## Frontend contract

- GAME iframe URL: `https://systems-simulator.newtonschool.co/?host=newton`
- Render `question_text` as raw Django HTML.
- Rebuild immutable simulator config from the test-case rows, not from `initial_game_state`.
- Keep `initial_game_state` mutable-only learner state.
- Hide topology open/save actions in Newton-hosted assignment mode.
- Keep scaffold locks and editing capabilities explicit in `SIMULATOR_CONFIG`.

## Django fields

- `question_type`: `GAME`
- `question_title`: `<Question title>`
- `question_text`:

```html
<p><Scenario paragraph></p>
<p><Required path paragraph></p>
<p><Target paragraph></p>
<p><Modeling disclaimer, if needed></p>
<p><Traffic paragraph></p>
<p><Submission explanation paragraph></p>
<h3>Functional Requirements</h3>
<ul>
  <li><Functional requirement 1></li>
  <li><Functional requirement 2></li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li><NFR 1></li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>DAU:</strong> <display number></li>
  <li><strong>Peak RPS:</strong> <display number></li>
  <li><strong>Read / Write:</strong> <display ratio></li>
</ul>
```

- `initial_game_state`:

```json
{}
```

## Test-case mapping rules

- Create rows in the exact order shown below.
- For every row: `hidden = false`, `output = ""`, `output_file = empty`.
- Paste each JSON block into Django `input` exactly.

## Row 1

- `title`: `SIMULATOR_CONFIG: <question-id>`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "configVersion": "1.0",
  "questionId": "<question-id>",
  "questionVersion": "1.0",
  "questionType": "<open-build|fix|optimize|build-budget|scaling|ha-chaos|tradeoff>",
  "entryFormat": "<blank-canvas|requirements-first|partial-scaffold|broken-scaffold|baseline-optimize|locked-lab>",
  "domains": ["<domain-1>", "<domain-2>"],
  "concepts": ["<concept-1>", "<concept-2>"],
  "difficulty": "<beginner|intermediate|advanced|expert>",
  "workloadCategory": "<read-heavy|write-heavy|connection-heavy|correctness-heavy|batch-heavy>",
  "presentationMode": "raw-html",
  "promptSource": "question_text",
  "scaffold": {
    "type": "<empty|partial|complete>"
  },
  "constraints": {
    "canModifyScaffold": true,
    "canRemoveScaffoldNodes": true,
    "maxNodeCount": 12
  },
  "suite": {
    "name": "<suite-name>",
    "visibleToStudent": false,
    "cases": [
      {
        "id": "<case-id>",
        "description": "<case description>",
        "workload": {
          "baseRps": 2000,
          "requestDistribution": [
            {
              "type": "read",
              "weight": 0.99,
              "sizeBytes": 256
            },
            {
              "type": "write",
              "weight": 0.01,
              "sizeBytes": 512
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "<rubric-id>",
    "passThreshold": 1
  },
  "environmentProfile": {
    "mode": "ASSIGNMENT",
    "visibility": {
      "prompt": true,
      "scaffoldSourceNodes": true,
      "gradingSuiteDetails": false,
      "liveMetrics": true,
      "rubricChecks": "LIVE_DURING_BUILD"
    },
    "capabilities": {
      "editPaletteList": null,
      "canEditScaffoldNodes": false,
      "canTriggerTestRuns": true,
      "edgeModel": "connector",
      "canEditEdges": false,
      "canEditResources": false,
      "canEditExecutionProfile": false
    },
    "graded": true,
    "chromeDensity": "minimal"
  }
}
```

## Row 2

- `title`: `STRUCTURAL_RULE: <rule-id>`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "<rule-id>",
  "kind": "<requires_component|requires_path|requires_single_source|...>",
  "description": "<why this shape is required>"
}
```

## Row 3

- `title`: `SEMANTIC_CRITERION: <criterion-id>`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "<criterion-id>",
  "kind": "storageFit",
  "description": "<meaning-level expectation>",
  "accessPattern": "<point-lookup|append-only|time-series|...>",
  "accept": ["<accepted-type-1>", "<accepted-type-2>"],
  "partial": ["<partial-type>"],
  "antiPattern": ["<anti-pattern-type>"],
  "points": 3,
  "hardFail": true
}
```

## Row 4

- `title`: `RUBRIC_CHECK: <check-id>`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "id": "<check-id>",
  "kind": "simulation",
  "description": "<runtime target>",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 100,
  "points": 3
}
```
~~~~

## Mini example

Use this shape for a URL shortener:

- `question_title`: `Design a URL shortener`
- `entryFormat`: `requirements-first`
- `domains`: `compute`, `storage`
- `concepts`: `read-cache`, `store-fit`
- `workloadCategory`: `read-heavy`
- semantic row: accept `kv-store` or `nosql-db` for point lookup
- rubric row: require `summary.latency.p99 < 100`

If multiple parts are needed, repeat the same file pattern once per assignment part instead of forcing unrelated lessons into one oversized package.

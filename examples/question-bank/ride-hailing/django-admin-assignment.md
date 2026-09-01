# Django Admin Setup: Design a ride-hailing match & payment backend

This authoring shape is for Newton assignment mode only.
Use it when the simulator is embedded through the generic GAME iframe with `?host=newton`.
Do not use this shape for standalone/local authoring at `https://systems-simulator.newtonschool.co/`; standalone/local must keep topology open/save available.

Justification prompts are currently hidden in the Newton assignment UI and are not graded, so do not include `justify` in the test-case rows for this flow.

## Frontend contract

- GAME iframe URL: `https://systems-simulator.newtonschool.co/?host=newton`
- Newton-hosted assignment mode must render `question_text` as raw Django HTML.
- The frontend translator must rebuild immutable simulator config from the test-case rows below, not from `initial_game_state`.
- `initial_game_state` stays mutable-only learner state. Do not paste the full `question.json` there.
- Newton-hosted assignment mode must hide topology `Open` / `Save` actions and disable `Ctrl/Cmd+O` and `Ctrl/Cmd+S`.
- Newton-hosted assignment mode must hide the header settings entry point.
- The authored assignment environment should stay explicit in `SIMULATOR_CONFIG`.
- Scaffold nodes stay locked.
- Edges stay in `connector` mode, so there is no edge properties panel.
- Node resource editing stays locked.
- Execution-profile editing stays locked.
- Domain overlays still apply when a lesson needs them.
- `network` domains upgrade edges to `network` and unlock edge editing.
- `cost` domains unlock resource editing.

## Django fields

- `question_type`: `GAME`
- `question_title`: `Design a ride-hailing match & payment backend`
- `question_text`:

```html
<p>You are the lead infrastructure architect at a ride-hailing company preparing for a national-holiday surge. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design a matching path that keeps nearby-driver lookups on a fast in-memory layer positioned between the service and the payment database, and a separate payment path that commits to a strongly consistent transactional database. Keep the hot matching path off the payment database.</p>
<p>Target: rider-to-driver match p99 latency under 3 s.</p>
<p>Traffic: 40,000 peak RPS at an 80:20 read-to-write ratio.</p>
<p>At submission you will explain why the nearby-driver hot path is separated from the payment store and how payments stay ACID-consistent.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Serve rider-to-driver matching from a fast in-memory layer positioned between the service and the payment database.</li>
  <li>Commit payments to a strongly consistent transactional database, isolated from the matching path.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>Rider-to-driver match p99 latency under 3 s at peak.</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 40,000</li>
  <li><strong>Read / Write:</strong> 80:20</li>
</ul>
```

- `initial_game_state`:

```json
{}
```

- `initial_game_state` must stay mutable-only. Do not paste the full `question.json` here.

## Test-case mapping rules

- Create the rows in the exact order shown below.
- For every row: `hidden = false`, `output = ""`, `output_file = empty`.
- Paste each JSON block into the Django `input` field exactly as shown.

## Row 1

- `title`: `SIMULATOR_CONFIG: ride-hailing`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "ride-hailing",
  "domains": [
    "compute",
    "storage"
  ],
  "concepts": [
    "store-fit",
    "geo-cache-placement"
  ],
  "difficulty": "advanced",
  "workloadCategory": "read-heavy",
  "constraints": {
    "maxNodeCount": 16
  },
  "suite": {
    "name": "ride-suite",
    "cases": [
      {
        "description": "Match-heavy peak",
        "workload": {
          "baseRps": 3000,
          "requestDistribution": [
            {
              "type": "read",
              "weight": 0.8
            },
            {
              "type": "write",
              "weight": 0.2,
              "sizeBytes": 512
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "ride-rubric",
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

- `title`: `STRUCTURAL_RULE: has-payment-db`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-payment-db",
  "kind": "requires_component",
  "componentType": "relational-db",
  "description": "A strongly consistent database for payments"
}
```

## Row 3

- `title`: `STRUCTURAL_RULE: single-source`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source"
}
```

## Row 4

- `title`: `SEMANTIC_CRITERION: pay-fits-relational`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "pay-fits-relational",
  "kind": "storageFit",
  "description": "Payment is transactional-relational (ACID), not KV",
  "accessPattern": "transactional-relational",
  "accept": [
    "relational-db"
  ],
  "antiPattern": [
    "kv-store",
    "nosql-db"
  ],
  "points": 3,
  "hardFail": false
}
```

## Row 5

- `title`: `SEMANTIC_CRITERION: geo-hot-path`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "geo-hot-path",
  "kind": "placement",
  "description": "Nearby-driver matching uses a cache/index, not the payment database",
  "componentType": "in-memory-cache",
  "between": [
    "microservice",
    "relational-db"
  ],
  "points": 2
}
```

## Row 6

- `title`: `RUBRIC_CHECK: match-latency`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "id": "match-latency",
  "kind": "simulation",
  "description": "p99 match under 3 s",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 3000,
  "points": 3
}
```

## Row 7

- `title`: `RUBRIC_CHECK: no-invariants`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "id": "no-invariants",
  "kind": "invariant",
  "description": "No invariant violations",
  "metric": "invariantViolations.count",
  "op": "==",
  "value": 0,
  "points": 1
}
```

# Django Admin Setup: Ingest a large IoT sensor fleet

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
- `question_title`: `Ingest a large IoT sensor fleet`
- `question_text`:

```html
<p>You are designing the ingestion backend for a large IoT fleet that keeps sending time-stamped readings. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design an ingest path that sustains a very high write rate where new readings are only added, and supports range queries over recent time windows per sensor. Choose a storage engine whose access pattern matches time-series data.</p>
<p>Target: sustain the injected write throughput without dropping events.</p>
<p>Traffic: 200,000 writes/sec, with about 5% reads for recent-window range queries.</p>
<p>At submission you will explain your storage-engine choice for time-series data at this write rate.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Ingest time-stamped readings at a sustained high write rate.</li>
  <li>Support range queries over recent time windows per sensor.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>Sustain the injected write throughput (>= 2,000 RPS in-sim) without dropped events.</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 200,000</li>
  <li><strong>Read / Write:</strong> 5:95</li>
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

- `title`: `SIMULATOR_CONFIG: sensor-store`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "sensor-store",
  "domains": [
    "storage"
  ],
  "concepts": [
    "store-fit"
  ],
  "workloadCategory": "write-heavy",
  "constraints": {
    "maxNodeCount": 10
  },
  "suite": {
    "name": "sensor-suite",
    "cases": [
      {
        "id": "ingest",
        "description": "Write-heavy ingest",
        "workload": {
          "baseRps": 3000,
          "requestDistribution": [
            {
              "type": "write",
              "weight": 0.95
            },
            {
              "type": "read",
              "weight": 0.05
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "sensor-rubric",
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

- `title`: `STRUCTURAL_RULE: single-source`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source"
}
```

## Row 3

- `title`: `SEMANTIC_CRITERION: store-fits-time-series`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "store-fits-time-series",
  "kind": "storageFit",
  "description": "200K writes/s time-series data should use wide-column, time-series, or suitable NoSQL storage - not relational",
  "accessPattern": "time-series",
  "accept": [
    "time-series-db",
    "columnar-db",
    "nosql-db"
  ],
  "antiPattern": [
    "relational-db"
  ],
  "points": 6,
  "hardFail": true
}
```

## Row 4

- `title`: `RUBRIC_CHECK: throughput`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "description": "Sustains write throughput",
  "metric": "summary.throughput",
  "op": ">=",
  "value": 2000,
  "points": 2
}
```

## Row 5

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

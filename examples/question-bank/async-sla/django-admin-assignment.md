# Django Admin Setup: Job-processing backend for a 15s SLA

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
- `question_title`: `Job-processing backend for a 15s SLA`
- `question_text`:

```html
<p>You are decoupling a synchronous request path that fails under spikes. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Accept jobs quickly at ingest, hand them to an asynchronous queue, and process them with a pool of scalable workers within the SLA. Ingest must not block on processing.</p>
<p>Target: p99 job completion under 15 s during spike load.</p>
<p>Traffic: 50,000 jobs/min with bursty spikes (mostly writes).</p>
<p>At submission you will explain why using a queue meets the SLA better than a synchronous path, and what consistency trade-off you accept.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Accept jobs at ingest without waiting for downstream processing.</li>
  <li>Buffer jobs in an asynchronous queue and process them with scalable workers within the 15 s SLA.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>p99 job-completion latency under 15 s during spike load.</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 3,000</li>
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

- `title`: `SIMULATOR_CONFIG: async-sla`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "async-sla",
  "domains": [
    "compute"
  ],
  "concepts": [
    "async-decoupling"
  ],
  "difficulty": "advanced",
  "workloadCategory": "write-heavy",
  "constraints": {
    "maxNodeCount": 12
  },
  "suite": {
    "name": "async-suite",
    "cases": [
      {
        "id": "spike",
        "description": "Spike load",
        "workload": {
          "baseRps": 3000,
          "requestDistribution": [
            {
              "type": "write",
              "sizeBytes": 1024
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "async-rubric",
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

- `title`: `STRUCTURAL_RULE: has-queue`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-queue",
  "kind": "requires_component",
  "componentType": "queue",
  "description": "An async queue separates ingest from processing"
}
```

## Row 3

- `title`: `STRUCTURAL_RULE: has-workers`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-workers",
  "kind": "requires_component",
  "componentType": "batch-worker",
  "description": "Scalable workers process the queue"
}
```

## Row 4

- `title`: `STRUCTURAL_RULE: single-source`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source"
}
```

## Row 5

- `title`: `SEMANTIC_CRITERION: ingest-through-queue`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "ingest-through-queue",
  "kind": "guardedPath",
  "description": "Jobs must enter the queue before they reach workers",
  "from": "microservice",
  "guard": "queue",
  "to": "batch-worker",
  "points": 3,
  "hardFail": false
}
```

## Row 6

- `title`: `RUBRIC_CHECK: sla`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "id": "sla",
  "kind": "simulation",
  "description": "p99 job completion under 15 s",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 15000,
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

# Django Admin Setup: Design a distributed web crawler

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
- `question_title`: `Design a distributed web crawler`
- `question_text`:

```html
<p>You are building a distributed crawler that must fetch billions of pages without crawling the same URL again. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design a pipeline: URLs are checked against a dedup index before entering the frontier (crawl) queue, the frontier fans work out to many fetchers, and fetched pages flow through processors in order into object storage.</p>
<p>Target: sustain the injected aggregate crawl throughput.</p>
<p>Traffic: about 23,000 URLs/sec steady, mostly writes.</p>
<p>At submission you will explain your dedup mechanism (for example, Bloom filter vs exact index) before enqueue.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Check URLs against a dedup index before enqueueing them into the frontier (crawl) queue.</li>
  <li>Fan the frontier out to many fetch workers.</li>
  <li>Flow fetched pages through processors in an ordered pipeline into object storage.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>Sustain the injected aggregate crawl throughput (>= 2,000 RPS in-sim).</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 23,000</li>
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

- `title`: `SIMULATOR_CONFIG: web-crawler`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "web-crawler",
  "domains": [
    "compute"
  ],
  "concepts": [
    "dedup-gate"
  ],
  "difficulty": "expert",
  "workloadCategory": "batch-heavy",
  "constraints": {
    "maxNodeCount": 16
  },
  "suite": {
    "name": "crawler-suite",
    "cases": [
      {
        "id": "steady",
        "description": "Steady crawl",
        "workload": {
          "baseRps": 3000,
          "requestDistribution": [
            {
              "type": "write",
              "sizeBytes": 2048
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "crawler-rubric",
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

- `title`: `STRUCTURAL_RULE: has-frontier`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-frontier",
  "kind": "requires_component",
  "componentType": "queue",
  "description": "A frontier (crawl) queue"
}
```

## Row 3

- `title`: `STRUCTURAL_RULE: has-dedup`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-dedup",
  "kind": "requires_component",
  "componentType": "kv-store",
  "description": "A dedup index"
}
```

## Row 4

- `title`: `STRUCTURAL_RULE: single-source`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source",
  "description": "Exactly one seed source"
}
```

## Row 5

- `title`: `SEMANTIC_CRITERION: enqueue-through-dedup`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "enqueue-through-dedup",
  "kind": "guardedPath",
  "description": "URLs pass the dedup index before the frontier queue",
  "from": "microservice",
  "guard": "kv-store",
  "to": "queue",
  "points": 4,
  "hardFail": false
}
```

## Row 6

- `title`: `SEMANTIC_CRITERION: crawl-pipeline`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "crawl-pipeline",
  "kind": "placement",
  "description": "Ordered pipeline frontier -> fetchers -> processors",
  "componentType": "batch-worker",
  "orderedPipeline": [
    "queue",
    "batch-worker",
    "microservice"
  ],
  "points": 3
}
```

## Row 7

- `title`: `RUBRIC_CHECK: throughput`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "description": "aggregate throughput sustained",
  "metric": "summary.throughput",
  "op": ">=",
  "value": 2000,
  "points": 2
}
```

## Row 8

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

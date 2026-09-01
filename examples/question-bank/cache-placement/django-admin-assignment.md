# Django Admin Setup: Scale a read-hot product API

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
- `question_title`: `Scale a read-hot product API`
- `question_text`:

```html
<p>You are an SRE hardening a product-catalog API that has started to struggle under read traffic. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>All traffic must enter through a load balancer, reach the application service, and read from the primary database. Introduce and place a cache layer so reads are shielded from the database - it must sit on the path between the service and the database, never in front of the load balancer.</p>
<p>Target: read p99 latency under 120 ms at peak.</p>
<p>Traffic: 20,000 peak RPS at a 95:5 read-to-write ratio. Without the cache, reads will overwhelm the database.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Route all traffic through the load balancer before it reaches the service.</li>
  <li>Serve reads through a cache layer positioned between the service and the database (not before the load balancer).</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>Read p99 latency under 120 ms at peak load.</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 20,000</li>
  <li><strong>Read / Write:</strong> 95:5</li>
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

- `title`: `SIMULATOR_CONFIG: cache-placement`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "cache-placement",
  "domains": [
    "compute"
  ],
  "concepts": [
    "cache-placement"
  ],
  "difficulty": "beginner",
  "workloadCategory": "read-heavy",
  "constraints": {
    "maxNodeCount": 10
  },
  "suite": {
    "name": "cache-suite",
    "cases": [
      {
        "description": "Read-heavy",
        "workload": {
          "baseRps": 2000,
          "requestDistribution": [
            {
              "type": "read",
              "weight": 0.95
            },
            {
              "type": "write",
              "weight": 0.05,
              "sizeBytes": 512
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "cache-rubric",
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

- `title`: `STRUCTURAL_RULE: has-lb`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-lb",
  "kind": "requires_component",
  "componentType": "load-balancer",
  "description": "A load balancer fronts the system"
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

- `title`: `SEMANTIC_CRITERION: cache-between`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "cache-between",
  "kind": "placement",
  "description": "Cache sits between the service and the database, not before the load balancer",
  "componentType": "in-memory-cache",
  "between": [
    "microservice",
    "relational-db"
  ],
  "notBefore": "load-balancer",
  "points": 4,
  "hardFail": false
}
```

## Row 5

- `title`: `RUBRIC_CHECK: p99`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "description": "p99 under 120 ms",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 120,
  "points": 3
}
```

## Row 6

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

# Django Admin Setup: Design a dynamic per-user API

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
- `question_title`: `Design a dynamic per-user API`
- `question_text`:

```html
<p>You are reviewing an architecture for an API that serves dynamic, per-user responses (personalized and not cacheable). You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design the request path from the edge to the service and its data store. Add only components that earn their place - a CDN in front of content that cannot be cached is unnecessary.</p>
<p>Traffic: 8,000 peak RPS of personalized responses.</p>
<p>If you include a CDN, you will need to explain at submission what it actually speeds up here. Otherwise, leave it out.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Serve dynamic, per-user responses from the service and its data store.</li>
  <li>Do not add infrastructure that gives no benefit for traffic that cannot be cached.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>

</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 8,000</li>
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

- `title`: `SIMULATOR_CONFIG: cargo-cult-cdn`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "cargo-cult-cdn",
  "domains": [
    "compute"
  ],
  "concepts": [
    "justified-omission"
  ],
  "workloadCategory": "read-heavy",
  "constraints": {
    "maxNodeCount": 10
  },
  "suite": {
    "name": "cdn-suite",
    "cases": [
      {
        "id": "baseline",
        "description": "Nominal",
        "workload": {
          "baseRps": 1000
        }
      }
    ]
  },
  "rubric": {
    "id": "cdn-rubric",
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

- `title`: `SEMANTIC_CRITERION: cdn-justified`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "cdn-justified",
  "kind": "forbidUnjustified",
  "description": "CDN must be absent, or supported by a valid justification",
  "componentType": "cdn",
  "points": 4,
  "hardFail": false
}
```

## Row 4

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

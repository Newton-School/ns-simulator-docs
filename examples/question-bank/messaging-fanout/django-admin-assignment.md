# Django Admin Setup: Design an event-notification backbone

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
- `question_title`: `Design an event-notification backbone`
- `question_text`:

```html
<p>You are designing the notification backbone that delivers every domain event to several independent downstream services (analytics, search indexer, email). You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>One producer publishes each event once. Each of the three downstream consumers must receive every event independently.</p>
<p>Traffic: 5,000 events/sec from a single producer.</p>
<p>At submission you will explain your choice of messaging primitive and its delivery guarantee trade-off.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Publish each event once from a single producer.</li>
  <li>Deliver every event to all three independent consumers so each consumer sees the full stream.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>

</ul>
<h3>Scale</h3>
<ul>
  <li><strong>Peak RPS:</strong> 5,000</li>
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

- `title`: `SIMULATOR_CONFIG: messaging-fanout`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "messaging-fanout",
  "domains": [
    "storage"
  ],
  "concepts": [
    "pubsub-fanout"
  ],
  "difficulty": "beginner",
  "workloadCategory": "connection-heavy",
  "constraints": {
    "maxNodeCount": 10
  },
  "suite": {
    "name": "fanout-suite",
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
    "id": "fanout-rubric",
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

- `title`: `STRUCTURAL_RULE: has-broker`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "has-broker",
  "kind": "requires_component",
  "componentType": "message-broker",
  "description": "A broadcast broker is present"
}
```

## Row 3

- `title`: `STRUCTURAL_RULE: single-source`
- `input`:

```json
{
  "type": "STRUCTURAL_RULE",
  "id": "single-source",
  "kind": "requires_single_source",
  "description": "Exactly one producer"
}
```

## Row 4

- `title`: `SEMANTIC_CRITERION: fanout`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "kind": "fanout",
  "description": "A broker fans out to 3 or more independent consumers; a single queue is wrong",
  "broker": "message-broker",
  "minConsumers": 3,
  "forbiddenBroker": "queue",
  "points": 5,
  "hardFail": true
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

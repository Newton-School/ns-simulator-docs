# Django Admin Setup: Design a social news feed

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
- `question_title`: `Design a social news feed`
- `question_text`:

```html
<p>You are the architect for a social app's home feed. You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design a write path where posting an item fans it out to followers' timelines via a broadcast component to independent timeline builders, and a read path where a user loads their prebuilt timeline by direct lookup.</p>
<p>Target: feed-load (read-path) p99 latency under 200 ms.</p>
<p>Traffic: 50,000 peak RPS at a 98:2 read-to-write ratio. Timeline reads that hit the backing store directly will saturate it.</p>
<p>At submission you will explain your fan-out-on-write versus fan-out-on-read decision for this read ratio.</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Write path: on a new post, fan the item out to follower timelines via a broadcast component to independent timeline builders.</li>
  <li>Read path: load a user's prebuilt timeline by direct lookup within the p99 target.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>Feed-load (read-path) p99 latency under 200 ms at peak.</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>DAU:</strong> 10,000,000</li>
  <li><strong>Peak RPS:</strong> 50,000</li>
  <li><strong>Read / Write:</strong> 98:2</li>
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

- `title`: `SIMULATOR_CONFIG: news-feed`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "news-feed",
  "domains": [
    "compute",
    "storage"
  ],
  "concepts": [
    "fan-out-on-write",
    "read-cache"
  ],
  "workloadCategory": "read-heavy",
  "constraints": {
    "maxNodeCount": 14
  },
  "suite": {
    "name": "feed-suite",
    "cases": [
      {
        "description": "Read-heavy feed peak",
        "workload": {
          "baseRps": 3000,
          "requestDistribution": [
            {
              "type": "read",
              "weight": 0.98,
              "sizeBytes": 512
            },
            {
              "type": "write",
              "weight": 0.02,
              "sizeBytes": 1024
            }
          ]
        }
      }
    ]
  },
  "rubric": {
    "id": "feed-rubric",
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

- `title`: `SEMANTIC_CRITERION: fanout-timelines`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "fanout-timelines",
  "kind": "fanout",
  "description": "A broker fans posts out to independent timeline builders",
  "broker": "message-broker",
  "minConsumers": 2,
  "forbiddenBroker": "queue",
  "points": 3,
  "hardFail": false
}
```

## Row 4

- `title`: `SEMANTIC_CRITERION: feed-store-fit`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "feed-store-fit",
  "kind": "storageFit",
  "description": "Timeline reads are direct lookups by user",
  "accessPattern": "point-lookup",
  "accept": [
    "kv-store",
    "nosql-db"
  ],
  "partial": [
    "in-memory-cache"
  ],
  "antiPattern": [
    "relational-db"
  ],
  "points": 2
}
```

## Row 5

- `title`: `RUBRIC_CHECK: p99`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "description": "feed p99 under 200 ms",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 200,
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

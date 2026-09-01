# Django Admin Setup: Design a URL shortener

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
- This assignment uses connector edges. Grading should depend on topology and node choices, not on edge-property tuning.
- Domain overlays still apply when a lesson needs them.
- `network` domains upgrade edges to `network` and unlock edge editing.
- `cost` domains unlock resource editing.

## Django fields

- `question_type`: `GAME`
- `question_title`: `Design a URL shortener`
- `question_text`:

```html
<p>You are the lead infrastructure architect for a new URL-shortening service (like bit.ly). You are designing the system architecture - placing, connecting, and sizing infrastructure components, not writing application code.</p>
<p>Design a write path that accepts a long URL and stores a short-code -> long-URL mapping in a durable store, and a read path that resolves a short code and issues an HTTP redirect.</p>
<p>Target: redirect (read-path) p99 latency under 100 ms at peak.</p>
<p>In this assignment, links are simple connectors. Focus on which components should connect, not on tuning per-link network properties.</p>
<p>Traffic: 200,000 peak RPS at a 99:1 read-to-write ratio. Reads that fall through to the primary store will saturate it.</p>
<p>At submission you will explain your storage-engine choice for short-code lookups at this scale, your short-code generation and collision-handling strategy (for example, base62), and your redirect status code (301 vs 302).</p>
<h3>Functional Requirements</h3>
<ul>
  <li>Write path: accept a long URL and store a short-code -> long-URL mapping in a durable store.</li>
  <li>Read path: resolve a short code to its long URL and return a redirect within the p99 target.</li>
</ul>
<h3>Non-Functional Targets</h3>
<ul>
  <li>Redirect (read-path) p99 latency under 100 ms at peak load.</li>
</ul>
<h3>Scale</h3>
<ul>
  <li><strong>DAU:</strong> 50,000,000</li>
  <li><strong>Peak RPS:</strong> 200,000</li>
  <li><strong>Read / Write:</strong> 99:1</li>
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
- This question uses connector edges. Do not author grading expectations that depend on edge latency, bandwidth, or per-edge concurrency tuning.

## Row 1

- `title`: `SIMULATOR_CONFIG: url-shortener`
- `input`:

```json
{
  "type": "SIMULATOR_CONFIG",
  "questionId": "url-shortener",
  "domains": [
    "compute",
    "storage"
  ],
  "concepts": [
    "read-cache",
    "store-fit"
  ],
  "workloadCategory": "read-heavy",
  "constraints": {
    "maxNodeCount": 12
  },
  "suite": {
    "cases": [
      {
        "description": "Read-heavy peak (injected 99:1)",
        "workload": {
          "baseRps": 2000,
          "requestDistribution": [
            {
              "type": "read",
              "weight": 0.99
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
    "id": "url-rubric",
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

- `title`: `SEMANTIC_CRITERION: store-fits-point-lookup`
- `input`:

```json
{
  "type": "SEMANTIC_CRITERION",
  "id": "store-fits-point-lookup",
  "kind": "storageFit",
  "description": "Short-code lookup is a direct lookup by key",
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
  "points": 3,
  "hardFail": true
}
```

## Row 4

- `title`: `RUBRIC_CHECK: p99`
- `input`:

```json
{
  "type": "RUBRIC_CHECK",
  "kind": "simulation",
  "description": "p99 under 100 ms",
  "metric": "summary.latency.p99",
  "op": "<",
  "value": 100,
  "points": 3
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

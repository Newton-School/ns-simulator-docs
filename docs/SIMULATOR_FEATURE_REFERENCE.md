# Simulator Feature Reference

This document defines the current simulator feature set in this repository as of July 27, 2026.

It answers two questions for each major feature:

1. What does it do?
2. How does it do it in the current codebase?

This is a code-grounded reference, not a product pitch. When the UI, engine, and docs disagree, this file is intended to describe the code that actually runs today.

## 1. Simulator Overview

The simulator has four layers:

1. Authoring UI
   What it does: lets a user build or load a system topology on a canvas.
   How it does it: React + React Flow components in `src/renderer/src/components`, backed by Zustand state in `src/renderer/src/store/useStore.ts`.

2. Topology normalization and validation
   What it does: converts canvas state or imported JSON into a valid `TopologyJSON` model and blocks invalid runs.
   How it does it: `src/renderer/src/hooks/useTopologySerializer.ts`, `src/renderer/src/utils/topologyCanvasAdapter.ts`, and `src/engine/validation/validator.ts`.

3. Simulation engine
   What it does: executes a seeded discrete-event simulation of request flow, queueing, routing, latency, failures, and outcomes.
   How it does it: the engine in `src/engine`, run in a worker via `src/renderer/src/hooks/useSimulation.ts` and `src/engine/worker/simulation.worker.ts`.

4. Analysis surfaces
   What it does: turns raw run artifacts into summary metrics, bottleneck checks, per-node and per-edge metrics, traffic rollups, and run inspector drill-downs.
   How it does it: `src/engine/analysis/output.ts`, `src/engine/metrics.ts`, `src/renderer/src/components/simulation/ResultsTray.tsx`, and `src/renderer/src/components/properties/PropertiesPanel.tsx`.

## 2. End-to-End Workflow Features

| Feature | What it does | How it works today |
| --- | --- | --- |
| Workspace shell | Gives the simulator a left rail, canvas, results tray, and right inspector. | `WorkspaceLayout.tsx` uses resizable panels from `react-resizable-panels`. |
| Left and right sidebar toggles | Opens and closes the library rail and the properties/run inspector rail. | `Header.tsx` toggles panel visibility through layout state. |
| Theme toggle | Switches the visual theme. | `ThemeToggle` in the header updates the renderer theme state and CSS variables. |
| File status | Shows the current scenario file name and unsaved state. | `FileStatus` reads `fileName` and `isUnsaved` from the shared store. |
| Open / Save | Loads or saves simulator files. | `useFlowPersistence.ts` plus `FileService.web.ts` or `FileService.electron.ts`. |
| Keyboard shortcuts | Supports `Ctrl/Cmd+S` and `Ctrl/Cmd+O`. | Registered in `useFlowPersistence.ts`. |
| Unsaved-change detection | Marks the workspace dirty when nodes, edges, or scenario state change after the last save/load. | `useFlowPersistence.ts` snapshots serialized content and compares it against the last persisted value. |
| Sample loading | Replaces the current canvas with a guided example system. | Scenarios are defined in `sampleScenarios.ts` and loaded through the sidebar or sample picker. |
| Browser and Electron targets | Runs as a web app or desktop app. | Vite serves the web build; Electron uses `electron-vite`; scripts are defined in `package.json`. |

## 3. Left Sidebar Features

### 3.1 Question Text

What it does:
- Stores the prompt or assignment text that explains the system-design task.
- Can render an embedded assignment app if the text is a valid `embedded-iframe` JSON payload.

How it works:
- `LibrarySidebar.tsx` exposes a `Question Text` tab.
- `embeddedIframeQuestionSchema.ts` parses a JSON blob of the form:
  - `type: "embedded-iframe"`
  - `url`
  - optional `title`, `prompt`, `height`, `allowFullscreen`, `launchParameters`, `allowedOrigins`
- `EmbeddedIframeQuestion.tsx` loads the iframe, performs a `postMessage` handshake, and can launch it in fullscreen.

### 3.2 Component Library

What it does:
- Lets the user drag infrastructure, network, compute, storage, security, messaging, AI, and observability components onto the canvas.
- Supports search and a `Common` vs `All` filter.

How it works:
- `LibrarySidebar.tsx` renders categories from `CATALOG_CONFIG`.
- `LibraryItem.tsx` provides tooltip-backed cards.
- Drag/drop creates nodes through `useFlowDnD.ts` using `instantiateTemplate(...)`.

### 3.3 Scenarios

What it does:
- Gives guided starter systems with an explanation of what each one demonstrates.

How it works:
- `sampleScenarios.ts` defines the catalog.
- `LibrarySidebar.tsx` renders expandable scenario cards.
- `SampleScenarioPicker.tsx` provides a modal picker for sample systems.

## 4. Canvas Authoring Features

| Feature | What it does | How it works today |
| --- | --- | --- |
| Drag-and-drop node creation | Adds a palette item to the canvas. | `useFlowDnD.ts` instantiates a palette template and inserts a React Flow node. |
| Nested composite containers | Lets regions, AZs, subnets, and other composites contain child nodes. | Containment is represented through node parentage and recomputed from geometry in `canvasUtils.ts`. |
| Geometry-driven containment | Reassigns a node to the right composite when the node is moved. | `recomputeContainment(...)` runs on drag stop and uses world-space bounds. |
| Edge creation | Connects nodes through configurable edges. | React Flow connections are handled by the shared store and rendered through `PacketEdge.tsx`. |
| Edge rewire | Lets an existing edge be reconnected. | `FlowCanvas.tsx` uses `updateEdge(...)`. |
| Edge selection | Opens edge properties or edge results in the right panel. | `onEdgeClick` writes selected edge ID into the Zustand store. |
| Node selection | Opens node properties or node results in the right panel. | Selection is stored globally in `useStore.ts`. |
| Pane deselect | Clears the current selection. | `FlowCanvas.tsx` handles pane clicks. |
| Fit-on-bulk-load | Auto-fits the camera after opening a larger scenario. | `FlowCanvas.tsx` detects bulk node-count changes and calls `fitView()`. |
| MiniMap | Shows a small topology overview. | React Flow `MiniMap`. |
| Zoom and pan controls | Provides built-in navigation controls. | React Flow `Controls`. |
| Background grid | Gives a dotted graph-paper background. | React Flow `Background` with a dot variant. |
| Empty state | Shows a placeholder when the canvas is empty. | `EmptyFlowState.tsx`. |
| Magnetic connection snap | Helps connect edges to nearby handles. | `useMagneticSnap.ts`, `useHandleProximity.ts`, and `MagneticConnectionLine.tsx` use proximity scoring and visual snap rings. |
| Metric lens switcher | Changes what node cards and edge labels emphasize. | `MetricLensSwitcher.tsx` swaps between pre-run lenses and runtime lenses. |
| Canvas legend | Explains active canvas indicators. | `CanvasLegend` is shown when metric lenses are visible. |

## 5. File, Import, Export, and Persistence Features

### 5.1 Saved Canvas Format

What it does:
- Saves the current workspace as a nested canvas document.

How it works:
- `useFlowPersistence.ts` serializes:
  - `version`
  - nested `nodes`
  - `edges`
  - `scenario`
- Nested node trees are produced by `convertFlatToNested(...)` in `nodeTransformers.ts`.

### 5.2 TopologyJSON Import

What it does:
- Lets the simulator open a standard `TopologyJSON` file, not just a saved canvas file.

How it works:
- `isTopologyJsonLike(...)` in `topologyCanvasAdapter.ts` detects topology-shaped input.
- `topologyToCanvasFileData(...)` maps engine nodes and edges back into canvas nodes and scenario state.
- Imported topologies are mapped onto the closest available UI template through `pickTemplateForNode(...)`.

### 5.3 Web Save / Load Behavior

What it does:
- Uses browser-native file pickers when possible and falls back to downloads or file inputs otherwise.

How it works:
- `FileService.web.ts` prefers `showSaveFilePicker` and `showOpenFilePicker`.
- If unavailable, it falls back to Blob download for save and `<input type="file">` for load.

### 5.4 Electron Save / Load Behavior

What it does:
- Uses the Electron bridge when running as a desktop app.

How it works:
- `FileService.electron.ts` calls functions exposed on `window.nssimulator`.

### 5.5 Legacy Migration

What it does:
- Upgrades older canvas node shapes to the current schema.

How it works:
- `migrateCanvasNodes(...)` in `legacyCanvasMigration`.

## 6. Topology Modeling Features

### 6.1 Structural Roles

The model distinguishes these roles:

- `source`
- `processor`
- `storage`
- `router`
- `sink`
- `composite`

What it does:
- Changes how a node is simulated and how its metrics are interpreted.

How it works:
- Structural role lives on node data and is used by serializer, renderer, metrics, and analysis code.
- Example: source nodes emit traffic; they do not behave like runtime processors.

### 6.2 Node Template System

What it does:
- Gives every palette item a default label, icon, behavior profile, and default simulation config.

How it works:
- `PALETTE_TEMPLATES` and `instantiateTemplate(...)` create node instances.
- `nodeRegistry.ts` and `libraryInfo.ts` define presentation metadata.
- `componentSpecs.ts` normalizes simulator-facing configuration.

### 6.3 Composite Location Modeling

What it does:
- Lets the user place nodes inside region, AZ, and subnet containers and derive locality from placement.

How it works:
- `buildLocationTopology(...)` and related helpers in `locationTopology.ts` build the containment ancestry.
- Path classes and locality rollups are then derived from that ancestry.

## 7. Node Capability and Trait Features

These are the major node behavior modules currently wired into the simulator.

| Capability / Trait | What it does | How it works today |
| --- | --- | --- |
| `source.workload` | Defines offered traffic from a source node. | Source nodes can carry `defaultWorkload` and `requestDistribution`; the run context can override them. |
| `routing.strategy` | Controls how a router or gateway chooses downstream targets. | Supports strategy enums in node config; implemented in `routing.ts`. |
| `composite.location` | Attaches placement metadata to composites such as regions or subnets. | Used by location topology and auto edge locality inference. |
| `base.queue` | Models worker count, queue capacity, and queue discipline. | Serialized into node queue config and executed by the queueing node implementation. |
| `base.processing` | Models service-time distribution and timeouts. | Stored as distribution config plus timeout on the node. |
| `chaos.node-failure` | Injects explicit node-level chaos windows. | UI creates `FaultSpec` objects; engine opens failure windows and records them in `statusTimeline`. |
| `slo.targets` | Attaches latency and availability targets to a node. | Analyzed after the run in `output.ts` as `sloBreaches`. |
| `security.policy` | Simulates policy-driven blocks and drops. | Uses `blockRate` and `droppedPackets` style config on supported nodes. |
| `service-registry.honesty` | Models health/registry-driven routing truthfulness. | Exposed as a capability module for service-discovery style components. |
| Cache | Simulates cache hit/miss behavior and hit latency. | `cache.ts` applies hit probability and faster hit latency. |
| Circuit breaker | Simulates closed/open/half-open fail-fast behavior. | `circuitBreaker.ts` tracks breaker state and rejects when open. |
| Cold start | Simulates startup latency after idle periods and optional concurrency pressure. | `coldStart.ts` adds penalty after idle windows. |
| Consumer lag | Models stream backlog. | `consumerLag.ts` reports broker lag when producers outrun consumers. |
| Content routing | Routes by request metadata such as method, path, host, or type. | `contentRouting.ts` matches request metadata against configured rules. |
| DNS routing | Simulates DNS answer selection and resolver caching. | `dnsRoutingPolicy.ts` implements policy choice and TTL behavior. |
| Health-aware routing | Filters unhealthy downstream targets. | `healthAwareRouting.ts` drops unhealthy candidates before route selection. |
| Key-based routing | Keeps the same key on the same downstream shard. | `keyBasedRouting.ts` hashes the configured request field. |
| Rate limiting | Simulates a token-bucket admission controller. | `rateLimiter.ts` uses `maxTokens` and `refillRatePerSecond`. |
| Read-only replica behavior | Rejects writes on replicas. | `readOnly.ts` checks replication role. |
| Read/write split latency | Lets reads and writes have different service times. | `readWriteSplit.ts` uses `readLatency` and `writeLatency`. |
| Ack-and-release queueing | Acknowledges upstream work at enqueue and drains asynchronously. | `ackAndRelease.ts` decouples enqueue acknowledgment from downstream completion. |

## 8. Edge and Network Modeling Features

| Feature | What it does | How it works today |
| --- | --- | --- |
| Protocol selection | Describes the transport flavor of the edge. | `EdgeDefinition.protocol` supports `https`, `grpc`, `tcp`, `udp`, `websocket`, `amqp`, `kafka`. |
| Mode selection | Describes how requests travel across the edge. | `EdgeDefinition.mode` supports `synchronous`, `asynchronous`, `streaming`, `conditional`. |
| Manual or auto path type | Lets a link use an explicit locality class or derive one automatically. | `EdgePropertiesPanel.tsx` and serializer logic use placement-aware or fallback default inference. |
| Path classes | Represents expected physical distance class for the hop. | Supported classes are `same-rack`, `same-dc`, `cross-zone`, `cross-region`, `internet`. |
| Auto path type from placement | Infers path class from composite node placement. | `pathTypeFromContainers(...)` maps same subnet to `same-rack`, same AZ to `same-dc`, same region to `cross-zone`, different regions to `cross-region`. |
| Auto path type from defaults | Uses node-type heuristics when placement is not enough. | `inferEdgeDefaults(...)` looks at source and target types, such as external/source or DB/cache patterns. |
| Manual latency | Lets a link use an explicit constant or log-normal latency model. | Serializer turns edge panel values into a `DistributionConfig`. |
| Auto latency | Derives latency from the resolved path type. | `edgeDefaults.ts` provides path-type latency profiles; serializer uses them if no manual latency is set. |
| Protocol overhead | Adds a small protocol-specific latency overhead. | `edgeDefaults.ts` defines overhead by protocol. |
| Bandwidth | Models link bandwidth in Mbps. | Stored on the edge and used in edge/default calculations and result presentation. |
| Max concurrent | Caps in-flight requests on the link. | Stored on the edge and used by edge saturation logic. |
| Packet loss | Randomly drops a share of packets. | Stored as `packetLossRate` on the edge and surfaced in edge failures. |
| Edge error rate | Injects edge-local errors. | Stored as `edgeErrorRate` and reported as edge failures. |
| Conditional edges | Allows route conditions for conditional mode. | `routing.ts` requires a non-empty condition for conditional routing. |
| Edge labels | Supports a display label such as `HTTP` or `gRPC`. | Editable in `EdgePropertiesPanel.tsx`. |
| Edge locality details | Shows where a path actually travels, such as `us-east-1a -> us-east-1b`. | Built by `describeEdgeLocality(...)` and locality rollup utilities. |
| Lens-aware edge display | Changes edge labels and colors based on the active metric lens. | `edgeLensPresentation.ts` and `PacketEdge.tsx` compute label headline, severity, and receding behavior. |
| Live edge traffic animation | Shows motion on links while a run is active. | `PacketEdge.tsx` renders animated packets from recent edge-flow events. |
| Routing preview visualization | Can highlight how traffic would split across downstream routes during routing visualization. | `routingStrategyPreview.ts` computes preview counts and `PacketEdge.tsx` renders them. |

## 9. Edge Default Profiles

### 9.1 Path-Type Latency Defaults

Current path-type defaults are log-normal profiles:

- `same-rack`
- `same-dc`
- `cross-zone`
- `cross-region`
- `internet`

What they do:
- Give a reasonable transport-latency starting point when the user keeps an edge on `Auto`.

How they work:
- `edgeDefaults.ts` maps each path type to a log-normal profile and default bandwidth.

### 9.2 Path-Type Bandwidth Defaults

Current default bandwidth tiers are:

- `same-rack`: 10000 Mbps
- `same-dc`: 5000 Mbps
- `cross-zone`: 2500 Mbps
- `cross-region`: 1000 Mbps
- `internet`: 100 Mbps

### 9.3 Heuristic Path Inference

Current heuristics include:

- source or external facing edges tend toward `internet`
- DB or cache targets tend toward `same-rack`
- messaging or stream targets tend toward `same-dc`
- primary-to-replica database traffic tends toward `cross-zone`

## 10. Workload Modeling Features

| Feature | What it does | How it works today |
| --- | --- | --- |
| Source selection | Chooses which source node drives the run. | Scenario state tracks `selectedSourceNodeId`. |
| Global duration | Sets total simulation runtime in milliseconds. | Serialized into `GlobalConfig.simulationDuration`. |
| Warmup duration | Excludes startup transients from most reported metrics. | Stored in `GlobalConfig.warmupDuration` and enforced throughout `metrics.ts`. |
| Default timeout | Sets the fallback request timeout. | Stored in `GlobalConfig.defaultTimeout`. |
| Seed | Makes runs reproducible. | Stored in `GlobalConfig.seed` and propagated to the engine. |
| Time resolution | Chooses microsecond or millisecond simulation resolution. | Stored in `GlobalConfig.timeResolution`. |
| Trace sampling | Controls optional trace retention. | `GlobalConfig.traceSampleRate`. |
| Request mix | Lets a source emit different request classes with weights and metadata. | `requestDistribution` entries contain `type`, `weight`, `sizeBytes`, and optional metadata. |
| Workload override | Temporarily overrides the source node's default workload for the current run. | `mergeWorkloadDefaults(...)` merges source defaults with scenario overrides. |
| Live phase view | Shows how the chosen workload pattern behaves over the run. | `resultsTrayWorkload` and traffic timeline helpers compute phase labels and bins. |

### 10.1 Supported Workload Patterns

The current workload pattern enum is:

- `constant`
- `poisson`
- `bursty`
- `diurnal`
- `spike`
- `sawtooth`
- `replay`

What each does:

- `constant`
  What it does: emits evenly spaced arrivals.
  How it works: uses a fixed effective rate.

- `poisson`
  What it does: emits arrivals with random inter-arrival gaps.
  How it works: uses a Poisson-style stochastic process and surfaces arrival variation in the results.

- `bursty`
  What it does: alternates between normal and burst phases.
  How it works: uses `burstRps`, `burstDuration`, and `normalDuration`.

- `diurnal`
  What it does: varies demand by hour-of-day shape.
  How it works: uses hourly multipliers.

- `spike`
  What it does: creates a short high-load event at a chosen time.
  How it works: uses `spikeRps`, `spikeTime`, and `spikeDuration`.

- `sawtooth`
  What it does: ramps from low to high repeatedly.
  How it works: uses `peakRps` and `rampDuration`.

- `replay`
  What it does: replays a pre-recorded or externally defined arrival shape.
  How it works: the type exists in the core model and flows through workload handling.

## 11. Distribution Modeling Features

The simulator accepts these distribution types for service times, latencies, and related random variables:

- `constant`
- `deterministic`
- `log-normal`
- `exponential`
- `normal`
- `uniform`
- `weibull`
- `poisson`
- `binomial`
- `gamma`
- `beta`
- `pareto`
- `empirical`
- `mixture`

What it does:
- Lets the user describe realistic variability instead of forcing a single fixed number.

How it works:
- `validator.ts` defines the full Zod schema.
- `useTopologySerializer.ts` converts edge-panel settings and node config into `DistributionConfig`.
- The engine consumes those distributions during simulation.

## 12. Queueing, Service, and Runtime Execution Features

### 12.1 Core Queueing Model

What it does:
- Models service nodes as finite-capacity multi-worker queueing systems.

How it works:
- The project describes the runtime as a G/G/c/K-style simulator.
- Queue workers, queue capacity, and service distributions are configured per node.

### 12.2 Queue Disciplines

Supported queue disciplines:

- `fifo`
- `lifo`
- `priority`
- `wfq`

### 12.3 Pause, Resume, Stop, Reset

What it does:
- Allows the user to control a run while it is active.

How it works:
- `useSimulation.ts` sends worker messages:
  - `run`
  - `pause`
  - `resume`
  - `stop`
  - `step`
- The main UI prominently exposes `run`, `pause`, `resume`, `stop`, and `reset`.

### 12.4 Worker-Based Execution

What it does:
- Keeps the UI responsive while simulation is running.

How it works:
- Runs the engine in a Web Worker and streams:
  - progress updates
  - time-series snapshots
  - edge-flow batches
  - final results

### 12.5 Warmup-Aware Metrics

What it does:
- Prevents early transient activity from polluting steady-state metrics.

How it works:
- `metrics.ts` applies warmup gates to terminal metrics, per-node arrival-based counters, Little's Law inputs, and time-window charts.

## 13. Chaos, Failure, and Resilience Features

### 13.1 UI Fault Injection

Current fault modes exposed by the run controls:

- `blackhole`
- `hang`
- `reject`
- `degraded`

What it does:
- Injects a temporary failure window on one selected node during the run.

How it works:
- `SimulationControls.tsx` builds `FaultSpec` entries from UI state.
- The engine records those windows into `statusTimeline`.

### 13.2 Node-Level Error Injection

What it does:
- Adds probabilistic node-local failures.

How it works:
- `nodeErrorRate` is stored in node simulation config and reported in per-node error metrics.

### 13.3 Security Policy Drops and Blocks

What it does:
- Simulates security layers that block or drop some requests.

How it works:
- `securityPolicy` fields on supported nodes carry rates such as `blockRate` and dropped-packet style behavior.

### 13.4 Circuit Breaker

What it does:
- Trips open after enough downstream failures and then rejects quickly.

How it works:
- Breaker state and thresholds are modeled by `circuitBreaker.ts`.

### 13.5 Rate Limiting

What it does:
- Rejects or throttles requests beyond a token-bucket budget.

How it works:
- Uses `maxTokens` plus `refillRatePerSecond`.

### 13.6 Health-Aware Routing

What it does:
- Avoids unhealthy downstream targets when health checks are enabled.

How it works:
- Health-aware routing filters candidates before the strategy selection step.

## 14. Routing Features

### 14.1 Supported Routing Strategies

The current routing strategy enum is:

- `round-robin`
- `weighted`
- `random`
- `least-conn`
- `broadcast`
- `conditional`
- `passthrough`

What they do:

- `round-robin`
  Cycles across candidates in order.

- `weighted`
  Sends traffic according to configured weights.

- `random`
  Picks a random candidate.

- `least-conn`
  Prefers the candidate with lower active pressure.

- `broadcast`
  Represents fan-out style semantics in the model taxonomy.

- `conditional`
  Requires explicit conditions and only uses matching routes.

- `passthrough`
  Preserves a direct path without balancing behavior.

How routing works today:
- `routing.ts` applies strategy selection to synchronous candidates.
- If weights exist, weighted routing is the preferred fallback; otherwise the fallback is random.
- Async routes can be emitted alongside the selected sync route.

### 14.2 Content-Based Routing

What it does:
- Routes based on request metadata like host, method, path, or request type.

How it works:
- `contentRouting.ts` evaluates rule match fields.
- Validation blocks incompatible combinations, including L4-only contexts.

### 14.3 DNS Routing Policies

Current DNS policy enum:

- `simple`
- `weighted`
- `failover`
- `latency-based`
- `geolocation`

What it does:
- Simulates resolver answer choice and cache behavior.

How it works:
- `dnsRoutingPolicy.ts` resolves answers from configured policy and TTL fields.

### 14.4 Key-Based Routing

What it does:
- Ensures repeated requests with the same key land on the same shard.

How it works:
- Uses a configured request metadata field such as `shardKey`.

## 15. Run Control and Scenario Features

| Feature | What it does | How it works today |
| --- | --- | --- |
| Run / Run again | Starts a fresh simulation from the current topology. | Serializes the topology, validates it, and posts it to the worker. |
| Reset | Clears runtime state and edge-flow playback. | `useSimulation.ts` resets local state and clears shared edge-flow state. |
| Pause / Resume | Freezes and restarts the worker simulation clock. | Worker messages control execution state. |
| Stop | Halts the active run early. | Posts `stop`; final output marks the run as stopped. |
| Run context selection | Chooses source and injected fault target. | Scenario state carries source and fault selection. |
| Reproducible seeds | Makes repeated runs comparable. | Seed is serialized into `GlobalConfig` and returned in the output. |
| Sample scenarios | Gives guided, prebuilt systems. | Defined in `sampleScenarios.ts` and backed by sample JSON files in `src/engine/__samples__`. |

## 16. Validation Features

| Feature | What it does | How it works today |
| --- | --- | --- |
| Topology schema validation | Blocks malformed topologies before simulation. | `validator.ts` uses Zod schemas. |
| Component category validation | Accepts only supported engine categories. | `COMPONENT_CATEGORIES` list in `validator.ts`. |
| Component type validation | Accepts only supported engine component types. | `COMPONENT_TYPES` list in `validator.ts`. |
| Distribution validation | Ensures distributions have valid parameters. | Zod discriminated unions and refinements. |
| Workload pattern validation | Ensures pattern config is structurally valid. | `validator.ts` validates `WorkloadProfile`. |
| Request-mix weight validation | Ensures request distribution weights sum to `1.0`. | Explicit validator rule. |
| Global timing validation | Ensures `simulationDuration > warmupDuration`. | Explicit validator rule. |
| SLO validation | Ensures an SLO object has at least one target. | `SLOConfigSchema` refinement. |
| Content-routing validation | Ensures valid content-routing fields and combinations. | Uses `CONTENT_ROUTING_MATCH_FIELDS` and related guards. |
| Edge-constraint validation | Prevents invalid edge-configuration combinations. | `validateEdgeConstraintSelection(...)`. |
| Fault and invariant validation | Ensures optional faults and invariants are structurally valid. | Zod schemas in `validator.ts`. |

## 17. Serialization Features

### 17.1 Canvas to Engine Serialization

What it does:
- Converts UI state into engine-ready `TopologyJSON`.

How it works:
- `useTopologySerializer.ts` serializes:
  - nodes
  - edges
  - global config
  - workload
  - faults
  - invariants
  - scenarios

### 17.2 Source Workload Merge

What it does:
- Combines a source node's default workload with the run-time override.

How it works:
- `mergeWorkloadDefaults(...)` merges the two configurations before run.

### 17.3 Auto Edge Resolution

What it does:
- Makes `Auto` edge settings deterministic and reversible.

How it works:
- Serializer resolves:
  - effective path type
  - effective latency distribution
  - normalized protocol and mode
- Manual settings remain explicit; auto settings are derived from current placement or defaults.

## 18. Results Tray Features

The bottom analysis tray currently has four tabs:

- `Overview`
- `Bottlenecks`
- `Node Metrics`
- `Traffic`

### 18.1 Overview

What it does:
- Summarizes run context and the main system-level results.

How it works today:
- `ResultsTray.tsx` shows:
  - run context
  - post-warmup request totals
  - success and error summaries
  - success-latency percentiles
  - time-to-error panels
  - composite locality rollups
  - traffic locality
  - windowed system charts
  - request mix
  - outcome classes

### 18.2 Bottlenecks

What it does:
- Highlights whether the run looks healthy, balanced, and consistent.

How it works today:
- Uses post-run artifacts from `output.ts`:
  - SLO breaches
  - Little's Law checks
  - conservation checks
  - warmup adequacy
  - error-heavy nodes

### 18.3 Node Metrics

What it does:
- Lists runtime nodes that actually processed post-warmup traffic, plus source drivers separately.

How it works today:
- `ResultsTray.tsx` separates source emitters from runtime nodes.
- This is why a source such as `Checkout Web` can show source-only context instead of arrival-based node metrics.

### 18.4 Traffic

What it does:
- Shows request flow and event-level traffic information.

How it works today:
- Uses edge-flow playback, canonical events, debug event logs, and request outcome data.
- Supports event-status filtering for:
  - `All`
  - `Success`
  - `Timeout`
  - `Edge Error`
  - `Packet Loss`

## 19. Run Inspector and Right Panel Features

The right panel has two different jobs:

1. Design-time properties for a selected node or edge
2. Post-run inspection when no specific element is selected or when a runtime element is selected

### 19.1 Node Properties

What it does:
- Lets the user edit node config.

How it works:
- `PropertiesForm.tsx` renders fields based on `fieldConfig.ts`.
- Nested updates are applied by field-path patching in `PropertiesPanel.tsx`.

### 19.2 Edge Properties

What it does:
- Lets the user edit edge config.

How it works:
- `EdgePropertiesPanel.tsx` exposes label, protocol, mode, path type, latency, bandwidth, max concurrent, packet loss, edge error, and condition fields.

### 19.3 Results vs Config Tabs

What it does:
- Shows runtime results on elements that were part of the run while still allowing config editing.

How it works:
- `PropertiesPanel.tsx` switches between `metrics` and `config`.

### 19.4 Run Inspector Summary

What it does:
- Gives a compact, always-available summary of the latest run.

How it works:
- `PropertiesPanel.tsx` computes:
  - runtime throughput
  - worst p95
  - nodes in run
  - traffic links
  - watch-first recommendation
  - request mix preview
  - outcome split

### 19.5 Run Inspector Tabs

The current Run Inspector tabs are:

- `Nodes`
- `Links`
- `Locality`

What they do:

- `Nodes`
  Shows runtime node cards and health summaries.

- `Links`
  Shows runtime traffic-link cards and health summaries.

- `Locality`
  Shows deployment and traffic locality in its own inspector tab rather than burying it inside the summary.

How they work:
- The tab state is defined in `PropertiesPanel.tsx`.
- Node and edge runtime cards use live metrics and edge-flow state.
- Locality uses `LocationRollupsPanel` plus configured placement summaries.

### 19.6 Deployment and Locality

What it does:
- Separates physical placement from logical service behavior.
- Shows results grouped by:
  - regions
  - availability zones
  - subnets
  - traffic locality paths

How it works:
- `LocationRollupsPanel.tsx` groups runtime node and edge results by container ancestry.
- `PropertiesPanel.tsx` also computes configured placement groups and configured traffic paths for the locality tab.
- Composite containers are grouping metadata only; they do not add extra simulated hops by themselves.

## 20. Node Card and Lens Features

### 20.1 Pre-Run Lenses

Before a run, node cards and edges can emphasize config-oriented lenses:

- `concurrency`
- `queueCapacity`
- `timeout`

What they do:
- Explain static capacity knobs before there are runtime metrics.

How they work:
- `MetricLensSwitcher.tsx` switches to `PRE_RUN_LENSES`.
- `nodePresentation.ts` and `edgeLensPresentation.ts` produce pre-run summaries.

### 20.2 Runtime Lenses

After a run, the active lens switches to:

- `traffic`
- `saturation`
- `latency`
- `errors`
- `throughput`

What they do:
- Reinterpret the same node cards and edges around one measured concern at a time.

How they work:
- `nodePresentation.ts` builds lens-specific copy, values, symbols, and explanation tooltips.
- `edgeLensPresentation.ts` does the same for links.

### 20.3 Lens Glyphs and Tooltips

What they do:
- Show a small status symbol such as:
  - check
  - warning
  - cross / X
- Explain what that symbol means for the currently selected lens.

How they work:
- `nodePresentation.ts` builds lens-specific tooltip text.
- The meaning changes by lens:
  - latency lens: success latency, survivor bias, and SLO-aware context
  - errors lens: node-local rejects, timeouts, or resets
  - saturation lens: utilization and queue pressure
  - throughput lens: delivered rate

## 21. Runtime Output and Analysis Artifact Features

The engine produces a rich `SimulationOutput`.

### 21.1 Core Summary Artifacts

Included artifacts:

- summary metrics
- per-node metrics
- per-edge metrics
- time-series snapshots
- status timeline
- traces
- causal graph
- SLO breach list
- invariant violation list
- Little's Law results
- warmup adequacy
- conservation check
- canonical event stream
- event counts by type
- request outcome ledger
- request outcome family breakdown

How they work:
- `generateSimulationOutput(...)` in `output.ts` assembles them from the metrics collector, tracer, event stream, and debug data.

### 21.2 Request Outcome Families

The current request outcome family model includes:

- `success_2xx`
- `client_error_4xx`
- `server_error_5xx`
- `network_timeout`
- `network_drop`
- `connection_reset`
- `in_flight`

What it does:
- Gives the UI a user-facing outcome taxonomy instead of a raw event stream only.

How it works:
- `requestOutcomeSemantics.ts` defines the families and helper logic.

### 21.3 Canonical Event Stream

What it does:
- Preserves replayable run events for UI inspection and debugging.

How it works:
- The engine emits canonical event records and aggregate counts.

### 21.4 Status Timeline

What it does:
- Records explicit failure windows such as a node being degraded or blackholed.

How it works:
- The engine opens a `StatusWindow` when a fault starts and closes it at recovery or cutoff.

### 21.5 Traces and Debug Lifecycle

What it does:
- Tracks individual request lifecycles and debug-focused lifecycle assembly.

How it works:
- `RequestTracer` retains trace artifacts.
- `SimulationOutput` can carry `debuggedLifecycle` and `eventLog`.

## 22. Bottleneck and Correctness Check Features

### 22.1 SLO Breach Detection

What it does:
- Flags nodes whose measured p99 latency or availability violates configured targets.

How it works:
- `output.ts` inspects node metrics against node metadata SLO fields.

### 22.2 Little's Law Check

What it does:
- Compares measured `L` against `lambda x W` on each node.

How it works:
- `output.ts` computes:
  - observed `L`
  - expected `L`
  - relative error
  - tolerance result
- All values are measured over the same post-warmup window.

### 22.3 Warmup Adequacy

What it does:
- Warns when the warmup period is probably too short.

How it works:
- `output.ts` recommends `10 x max per-node p99 latency` as a heuristic minimum.

### 22.4 Conservation Check

What it does:
- Verifies that arrivals equal completions plus failures plus in-flight work at cutoff.

How it works:
- `output.ts` computes:
  - `postWarmupArrived`
  - `postWarmupProcessed`
  - `postWarmupRejected`
  - `postWarmupTimedOut`
  - `postWarmupConnectionReset`
  - `inFlight`
- The run is balanced when in-flight is below a small tolerance share of arrivals.

### 22.5 Invariant Violations

What it does:
- Captures explicitly defined invariant failures.

How it works:
- `SimulationOutput` carries invariant violations collected during execution.

## 23. CLI and Developer Features

### 23.1 CLI Simulation Entry Point

What it does:
- Runs a topology file from the command line without the UI.

How it works:
- `npm run simulate -- <topology.json> [--json] [--output <file>]`
- Implemented in `src/cli/index.ts`.

### 23.2 CLI Output

What it does:
- Prints a readable text summary or JSON output.

How it works:
- The CLI validates the topology, runs the engine, and prints:
  - summary
  - end-to-end latency
  - latency decomposition
  - failure locus
  - per-node metrics
  - SLO breaches
  - Little's Law violations
  - seed and events processed

### 23.3 Test Surfaces

What it does:
- Verifies engine behavior, validation, samples, and UI-specific logic.

How it works:
- `vitest` is configured through the `test` script.
- The repo has tests for routing, engine behavior, metrics, validator, serializer, and node presentation logic.

## 24. Current Sample Scenario Catalog

| Scenario | What it demonstrates | How the sample is set up |
| --- | --- | --- |
| Bare Metal Baseline | Single-instance saturation and baseline network behavior. | Direct client to API server. |
| Even Arrivals (D/D/1) | Clean constant-arrival baseline with no jitter. | Constant source plus constant edge. |
| Jittered Arrivals | Arrival bunching caused by edge variance. | Same server as the clean baseline, but a jittery log-normal edge. |
| Multi-AZ Auto Latency | Placement-driven cross-zone latency. | Source and target in different AZ containers within one region. |
| Cross-Region Auto Latency | Placement-driven cross-region latency and auto/manual reversibility. | Source and target in different region containers. |
| Endpoint Routing Mix | Endpoint-aware request mix and path-based gateway routing. | Storefront through gateway to catalog, checkout, and fraud branches. |
| Monolith Core | Compute plus DB bottlenecks in a simple stack. | Client to API to primary DB. |
| Proxy Edge Shield | Edge proxy or WAF effects before compute. | Client through proxy to API. |
| L7 Scale-Out | Horizontal stateless scale with an L7 balancer. | Client to L7 balancer to two API nodes and DB. |
| Cache-Aside Read Path | Cache hit ratio versus DB fallback. | Client to API to Redis cache and primary DB. |
| Replica Read Split | Read-heavy systems with separate read/write paths. | Client to API to primary DB and read replica. |
| Serverless Cold Start | Cold-start spikes and concurrency pressure. | Bursty client to serverless function. |
| Key-Based Sharding | Deterministic shard affinity. | Source through shard router to multiple shards. |
| Stream Consumer Lag | Producer backlog in streaming systems. | Producer publishing faster than downstream consumption. |
| DNS Weighted Routing | Weighted DNS resolution and TTL effects. | Client through resolver to stable and canary APIs. |
| Circuit Breaker Fail-Fast | Sidecar breaker opening after repeated downstream failures. | Client through sidecar to payment service. |

## 25. Current User-Facing Component Library Catalog

These are the current palette categories exposed in `CATALOG_CONFIG`.

### Infrastructure

- VPC Region
- Availability Zone
- Subnet
- DNS Server
- Discovery Service

### Clients and Edge

- User Client
- DNS
- CDN

### Network

- API Gateway
- Load Balancer L4
- Load Balancer L7
- Ingress Controller
- Reverse Proxy
- Service Mesh
- NAT Gateway
- VPN Gateway
- Edge Router
- Network Interface
- Routing Rule
- Routing Policy

### Security

- WAF
- Firewall Rule
- Security Group

### Compute

- Backend Server
- Lambda Function
- Async Worker
- Cron Job
- Auth Service
- Search Service
- Sidecar Proxy

### Messaging

- Message Queue
- Message Broker
- Pub/Sub
- Stream

### Data Stores

- Primary DB
- Read Replica
- Redis Cache
- NoSQL DB
- Object Storage
- Search Index
- Time-Series DB
- Graph DB
- Vector DB
- Data Warehouse
- Data Lake
- KV Store

### App Services

- Push Notification Service
- Streaming Analytics

### External

- External Service

### Templates

- Generic Service
- My Service
- Input Source
- Output Sink

### AI and Agents

- LLM Gateway
- Tool Registry
- Memory Fabric
- Agent Orchestrator
- Safety Observability Mesh

### Control Plane

- Config Store
- Secrets Manager
- Feature Flag Service

### Scaling and Partitioning

- Sharding
- Hashing
- Shard Node
- Partition Node

### Observability

- Metrics Collector Agent
- Log Collector Agent
- Log Aggregation Service
- Distributed Tracing Collector
- Alerting Engine
- Health Check Monitor

## 26. Current Engine-Level Component Type Taxonomy

The validator currently recognizes a broader engine taxonomy than the palette alone. That includes categories such as:

- compute
- network and edge
- storage and data
- messaging and streaming
- orchestration and infra
- security and identity
- observability
- devops and delivery
- data infra and analytics
- real-time and media
- external and integration
- DNS and certs
- consensus and coordination
- auxiliary

Examples of engine-recognized component types include:

- `microservice`
- `serverless-function`
- `load-balancer-l7`
- `api-gateway`
- `service-mesh`
- `relational-db`
- `in-memory-cache`
- `stream`
- `message-broker`
- `container-registry`
- `identity-provider`
- `distributed-tracing`
- `llm-gateway`
- `sharding`
- `rate-limiter`
- `throttler`

This matters because imported `TopologyJSON` can contain engine-valid component types even if the current palette does not expose each one as a first-class tile.

## 27. Known Limits and Partial-Fidelity Notes

These are important to understand when using the simulator.

1. Composite containers are locality metadata, not extra hops.
   Regions, AZs, and subnets help derive placement and rollups, but they do not themselves add transport latency unless an actual edge crosses runtime nodes.

2. Source nodes emit traffic; they do not behave like runtime processors.
   That is why source nodes can show source-only context instead of full arrival-based node metrics.

3. Auto edge latency is profile-based, not geography-precise.
   `Auto` chooses from modeled path classes such as `cross-zone` or `cross-region`; it is not a live cloud-provider latency lookup.

4. Cache TTL is currently metadata-oriented rather than a full time-evolving cache-expiry simulation.
   The cache trait models hit rate and hit latency directly.

5. Some engine artifacts are richer than the default UI surface.
   The engine retains traces, causal graph data, debug lifecycle data, and outcome ledgers that are not all presented equally in every default panel.

6. The palette is narrower than the validator taxonomy.
   Import can support more engine component types than the drag-and-drop library currently exposes.

7. This document describes current code, not every planned feature in `ns-simulator-docs`.
   The docs submodule contains future-looking specs and design notes, but this file intentionally documents what is implemented now.

## 28. Code Map

If you need to trace a feature deeper, these are the most important entry points:

- Authoring shell: `src/renderer/src/components/layout/WorkspaceLayout.tsx`
- Header and run controls: `src/renderer/src/components/layout/Header.tsx`, `src/renderer/src/components/simulation/SimulationControls.tsx`
- Library and samples: `src/renderer/src/components/library/LibrarySidebar.tsx`, `src/renderer/src/config/sampleScenarios.ts`
- Canvas: `src/renderer/src/components/canvas/FlowCanvas.tsx`
- Edge rendering: `src/renderer/src/components/canvas/PacketEdge.tsx`
- Node lens logic: `src/renderer/src/components/nodes/nodePresentation.ts`
- Properties and Run Inspector: `src/renderer/src/components/properties/PropertiesPanel.tsx`
- Results tray: `src/renderer/src/components/simulation/ResultsTray.tsx`
- Locality logic: `src/renderer/src/utils/locationTopology.ts`
- Serialization: `src/renderer/src/hooks/useTopologySerializer.ts`
- Import adaptation: `src/renderer/src/utils/topologyCanvasAdapter.ts`
- Validation: `src/engine/validation/validator.ts`
- Defaults: `src/engine/defaults/edgeDefaults.ts`
- Routing: `src/engine/routing.ts`
- Capability modules: `src/engine/traits/capabilityModules.ts`
- Output assembly: `src/engine/analysis/output.ts`
- CLI: `src/cli/index.ts`


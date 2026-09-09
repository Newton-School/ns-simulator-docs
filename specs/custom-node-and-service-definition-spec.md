# Service Builder and Custom Node Builder

> Status: Partially implemented (V1 shipped on `custom-node-definitions`); this
> spec is the corrected target.
>
> Owner: Simulator product and engine
>
> Purpose: Turn generic palette placeholders such as `Service` and `My Service`
> into builders for user-defined services and user-defined components, without
> adding arbitrary user code or non-deterministic simulation behavior.

## 0. Implementation Status and Honesty Contract (authoritative)

Sections 1–20 describe the target design. This section describes **what is actually
wired today** and the **non-negotiable honesty contract** that every part of the
builder must obey. Where §1–20 and §0 disagree, §0 wins.

### 0.1 What actually reaches the simulator

The engine simulates a node **only** from its `componentType` plus `data.sim.*`. It
never reads `customDefinition.capabilities`, `customDefinition.operations`,
`customDefinition.*.dependencies`, or trait packs beyond the fields explicitly
mapped in `applyDefinitionTraits`. Concretely, today only these definition inputs
change simulation output:

| Trait pack | Field | Maps to | Editable in builder? |
|---|---|---|---|
| capacity | `workloadKind` | `sim.resources.workloadKind` | yes |
| capacity | `workersPerInstance` | `sim.resources.workersPerInstance` | yes |
| capacity | `instanceCount` | `sim.resources.instanceCount` | **no (gap)** |
| capacity | `queueSlots` | `sim.resources.queueSlots` | **no (gap)** |
| workload-profile | `serviceTimeMs` | `sim.processing.distribution` | yes |
| serverless-lifecycle | `coldStartLatencyMs` | `sim.coldStartLatencyMs` | yes |
| serverless-lifecycle | `idleTimeoutMs` | `sim.idleTimeoutMs` | **no (gap)** |
| serverless-lifecycle | `maxConcurrency` | `sim.maxConcurrency` | yes |
| retry-timeout | `timeoutMs` | `sim.processing.timeout` | yes |
| retry-timeout | `maxRetries` | `sim.retry.maxAttempts` | **no (gap)** |
| rate-limiting | `limitPerSecond` | `sim.maxTokens` + `sim.refillRatePerSecond` | yes |
| external-dependency | `errorRate` | `sim.nodeErrorRate` | yes |

Everything else the builder collects — **all capabilities**, **all operations and
their input/output fields**, **all per-operation dependencies**, and the
`circuit-breaker`, `idempotency`, `async-emission` trait packs — is **contract /
documentation only**. It is stored on the node and used (at most) for validation and
future grading; it does not change a single simulated number.

### 0.2 The honesty contract (hard rules)

1. **No silent decorative dials.** Any input that does not change simulation output
   must be visibly labeled `contract` (documentation) in the UI, never presented as
   if it tunes behavior. This extends [[no-point-sampled-scalars]] and
   [[question-simulation-alignment]] to the builder.
2. **Editor ⇄ mapping parity.** A trait field is either (a) editable in the builder
   **and** mapped in `applyDefinitionTraits`, or (b) absent from both. No field may
   be mapped-but-unreachable or reachable-but-ignored.
3. **No dead trait packs.** A trait pack is shown only if it has both a field editor
   and a runtime mapping. Packs without a mapping are removed from
   `RUNTIME_TEMPLATES[*].traitPacks` until implemented.
4. **Definition ⇄ sim stay in sync.** Editing a definition after placement must
   re-apply its runtime traits to `sim.*` (or the definition edit must be disabled).
   The stored definition may never claim behavior the live `sim.*` does not have.
5. **The review pane tells the truth per definition**, not per template: it must
   state which of the user's own selections are simulated vs. documentation-only.

### 0.3 Correction milestones (supersede §17 ordering)

- **C0 — Honesty relabel: DONE.** Capabilities and operations carry explicit
  "documentation only, not simulated" notes; the review pane shows a per-definition
  "Your selections" split (simulated traits vs. documentation-only
  capabilities/operations); the properties-panel subtitle no longer promises absent
  traits.
- **C1 — Trait round-trip: DONE.** `applyDefinitionTraits` now lives in the engine
  module and re-runs on every properties-panel definition edit, keeping the stored
  definition and live `sim.*` in sync.
- **C2 — Editor/mapping parity: DONE.** `instanceCount`, `queueSlots`, `maxRetries`,
  and `idleTimeoutMs` are now editable in the builder trait cards. No mapped field is
  unreachable and no editor field is ignored.
- **C3 — Kill dead traits: DONE.** `circuit-breaker`, `idempotency`, and
  `async-emission` removed from `TraitPackId`, labels, and `background-worker`.
  (`circuit-breaker-controller` / `idempotency-manager` engine component types are
  unrelated and untouched.)
- **C4 — Runtime guard: DONE (no code).** Subsumed by `isCustomNodeDefinition`,
  which rejects any definition whose `kind` is not in
  `runtimeTemplate.allowedDefinitionKinds`.
- **C3b — Dependency parity, runtime-switch preservation, real section nav: DONE.**
  Both dependency editors render the canonical `DEPENDENCY_ACTIONS` (8),
  `DEPENDENCY_TARGET_ROLES` (11), and `DEPENDENCY_CONDITIONS` (5) plus call mode, so a
  stored value never lands on an editor that cannot show it. Switching runtime
  intersects existing capability selections with the new template instead of wiping
  them. The builder side rail is a working section navigator, not a fake wizard.
- **C5+ — Deferred.** Only one item needs a genuinely new engine primitive; the rest
  are adapter/wiring work on capabilities the engine already has. Anything not yet
  wired stays `contract` (rule 0.2.1) until it maps to something the engine consumes.
  - **Operation→edge materialization — NEEDS NEW ENGINE PRIMITIVE.** The engine routes
    along edges via `routingStrategy` / `routingRules`; it has no "operation" as a
    routing unit. A request carries a `requestType` but nodes never branch on which
    operation it is. Making the declared per-operation dependency graph drive traffic
    requires operation-scoped edges plus a router that dispatches by operation.
  - **Per-dependency latency — ADAPTER ONLY.** Edges already carry latency
    (`engine.ts` `propagationMs` + transmission + protocol overhead, `edgeLatencyMs`
    span). Missing only because a builder dependency is not yet tied to an edge; falls
    out of the operation→edge work above.
  - **Storage / messaging runtime templates — ADAPTER ONLY (doing now, #3).** The
    engine already simulates `relational-db`, `kv-store`, `in-memory-cache`,
    `search-index`, `object-store`, queues, and streams. Gap is that
    `RUNTIME_TEMPLATES` only defines compute/external entries. Fix = add template
    entries pointing at those existing component types + extend `applyDefinitionTraits`
    for their knobs.
  - **Request-mix binding — ADAPTER ONLY (doing now, #4).** Requests already carry
    `requestType` and the source/input node consumes an emission mix. Gap is that a
    service's declared operations are not seeded into that mix. Fix = project declared
    operations onto the source's request-mix distribution.
  - **Topology-scoped persistence — NO ENGINE INVOLVEMENT.** Definitions live in
    `localStorage` (service-kind only). Moving them onto the topology document is
    renderer/store/serialization work.

## 1. Core Correction

The `Service` and `My Service` tiles in the palette should not represent fixed
system-design concepts. They are not URL shorteners, auth services, search services,
or any other specific service by themselves.

They should behave as creation entry points:

| Palette surface | Correct role | What opens |
|---|---|---|
| `Service` | Create a new application service definition. | Service Builder modal |
| `My Service` | Browse, reuse, edit, or fork saved service definitions. | My Services library modal |
| `Custom Node` or `My Node` | Create or reuse a missing component type. | Custom Node Builder modal |

If the current UI has only `Service` and `My Service`, `My Service` should mean
"my saved service definitions", not a separate runtime node. A separate `Custom
Node` or `My Node` entry should be added for user-created infrastructure/component
definitions. This avoids confusing application services with arbitrary nodes.

The user flow should be:

```text
click Service
  -> open modal
  -> define what this service is made of
  -> choose required fields, operations, traits, dependencies, runtime profile
  -> create a concrete node on canvas
  -> optionally save definition into My Services
```

The UI should not list `URL Shortener`, `Auth`, `Payment`, or other domain examples
as mandatory built-in choices. Those are examples of what users may create.

## 2. Product Model

The system has two builder types.

### 2.1 Service Builder

The Service Builder creates an application service. A service is a business or
product capability that receives requests, does work, and calls other components.

Examples a user may define:

- `URL Shortening Service`
- `Auth Service`
- `Inventory Service`
- `Feed Ranking Service`
- `Notification Service`
- `Billing Service`

These examples must not be hard-coded as the only options. The user creates the
service by composing blocks.

The service definition is mainly about:

- Public interface: what requests it accepts.
- Operations: what actions it performs at HLD level.
- Dependencies: what other nodes it needs.
- Runtime: how it is deployed and simulated.
- Traits: deterministic behavior knobs such as capacity, latency, retry, and rate
  limits.

### 2.2 Custom Node Builder

The Custom Node Builder creates a missing component or infrastructure node when the
palette does not expose the exact thing the user wants.

Examples a user may define:

- `Lambda Function`
- `Cron Job`
- `Partner Fraud Check API`
- `Webhook Receiver`
- `Edge Worker`
- `Custom Cache`
- `Object Store`
- `Search Index`

A custom node is less about business operations and more about component behavior.
It asks: "What class of system component is this, and which deterministic simulator
capabilities should it have?"

## 3. Difference Between Service and Custom Node

| Dimension | Service Builder | Custom Node Builder |
|---|---|---|
| Main question | "What application capability am I building?" | "What missing component do I need?" |
| User mental model | Business/domain service | Infrastructure, runtime, external dependency, or specialized component |
| Primary configuration | Operations, request types, downstream dependencies | Component class, capabilities, runtime traits |
| Typical backing type | `microservice`, `serverless-function`, `batch-worker` | Any allowed `ComponentType` template |
| Graph role | Receives product traffic and orchestrates calls | Provides storage, routing, compute, messaging, external API, etc. |
| Required contract | Usually yes | Depends on class; storage/cache may not need operations |
| Saved library | My Services | My Nodes |
| Example | A user-defined `URL Shortening Service` | A user-defined `Lambda Function` or `Partner API` |

Important distinction:

- A service can be deployed on different runtimes.
- A custom node can represent non-service things.

For example, a user may create a `Redirect Service` and choose `serverless-function`
as its runtime. That is still an application service. Separately, a user may create
a generic `Lambda Function` node as a reusable component template. That is a custom
node.

## 4. Architecture Overview

The feature should be built as a definition layer above the existing simulator
catalog.

```text
Palette tile
  -> Builder modal
  -> Definition object
  -> Canvas node instance
  -> Existing engine ComponentType
  -> Existing traits and graph execution
```

The definition layer captures user intent. The existing engine component type and
traits provide deterministic execution.

```text
definition = user-editable identity + interface + selected blocks
node.type  = known simulator component type
traits     = deterministic runtime behavior
edges      = actual request flow
```

No builder should create a new arbitrary engine primitive at runtime. If a user
creates `My Redis`, it should resolve to the existing cache/storage behavior that
the engine already knows how to simulate.

## 5. Builder Block System

The modal should be powered by reusable blocks. The user "pulls and selects" from
these blocks to assemble a service or node.

### 5.1 Block categories

| Block category | Used by services | Used by custom nodes | Purpose |
|---|---:|---:|---|
| Identity | Yes | Yes | Name, description, icon, tags |
| Node class | No | Yes | Compute, storage, network, queue, external, observability |
| Service interface | Yes | Optional | Request types, methods, paths, response types |
| Operations | Yes | Optional | HLD-level actions the node accepts |
| Data fields | Yes | Optional | Structured request/response field names |
| Dependency requirements | Yes | Optional | Required downstream calls |
| Runtime template | Yes | Yes | How the node executes |
| Traits | Yes | Yes | Deterministic behavior knobs |
| Validation rules | Yes | Yes | Required/optional blocks and graph checks |
| Grading hooks | Yes | Yes | Rubric facts and justification prompts |
| Saved templates | Yes | Yes | Start from a reusable pattern |

### 5.2 Field classes

Every selectable field must be classified so the user understands its effect.

| Class | Meaning | Example | Runtime effect |
|---|---|---|---|
| `info` | Documents intent only. | Description, icon, tag. | None |
| `contract` | Must match graph or question rules. | Request type, required dependency. | Validation/grading |
| `runtime` | Changes simulation behavior. | Workers, queue size, cold start, error rate. | Simulation output |

The UI should surface this classification through small labels, not through long
instructional text.

## 6. Service Builder Modal

The Service Builder is a modal opened from the `Service` tile.

### 6.1 Modal structure

Recommended modal tabs:

| Tab | Purpose |
|---|---|
| Basics | Service name, description, icon, tags |
| Interface | Accepted request types, method/path, request and response fields |
| Operations | HLD-level operations and whether each is read/write/read-write |
| Dependencies | Required downstream roles and exact target nodes when known |
| Runtime | Deployment style and backing component type |
| Traits | Capacity, latency, resilience, rate limit, storage/cache behavior where applicable |
| Validate | Shows what will be created and unresolved graph requirements |

The modal should support draft state, cancel, create, and save-as-template.

### 6.2 Service fields

```ts
interface ServiceDefinition {
  id: string
  kind: 'service'
  name: string
  description?: string
  iconKey?: string
  tags: string[]
  version: 1
  interface: ServiceInterface
  runtime: ServiceRuntimeSelection
  traits: TraitSelection[]
  dependencyRequirements: DependencyRequirement[]
  validationPolicy: DefinitionValidationPolicy
  gradingHooks?: DefinitionGradingHooks
}
```

### 6.3 Service interface

```ts
interface ServiceInterface {
  requests: ServiceRequestContract[]
  operations: ServiceOperation[]
}

interface ServiceRequestContract {
  id: string
  requestType: string
  label: string
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  path?: string
  required: boolean
  inputFields: ContractField[]
  outputFields: ContractField[]
}

interface ContractField {
  name: string
  type: 'string' | 'number' | 'boolean' | 'object' | 'array'
  required: boolean
  description?: string
}

interface ServiceOperation {
  id: string
  label: string
  requestRef: string
  intent: 'read' | 'write' | 'read-write' | 'compute' | 'side-effect'
  dependencies: string[]
}
```

### 6.4 Service runtime selection

A service should not always mean only `microservice`. It is an application
capability that can run on one of a bounded set of runtimes.

```ts
interface ServiceRuntimeSelection {
  runtimeTemplateId:
    | 'long-running-service'
    | 'serverless-handler'
    | 'background-worker-service'
  backingComponentType: 'microservice' | 'serverless-function' | 'batch-worker'
}
```

Allowed service runtimes:

| Runtime option | Backing component type | When user chooses it |
|---|---|---|
| Long-running service | `microservice` | Normal online service with steady request handling |
| Serverless handler | `serverless-function` | Event/request handler with cold starts and concurrency limits |
| Background worker service | `batch-worker` | Async service that consumes queue jobs |

The service builder should default to `long-running-service`, but the user may
change it when the question policy allows.

### 6.5 Service traits

The Service Builder should offer trait packs, not raw JSON.

Legend: **exec** = mapped to `sim.*` and changes simulation output; **contract** =
documentation/validation only (per §0.2 rule 1 it must be labeled as such in the UI).

| Trait pack | Executable fields (mapped) | Contract-only fields | Applies when |
|---|---|---|---|
| Capacity | `workloadKind`, `workersPerInstance`, `instanceCount`, `queueSlots` | `instanceType` | Long-running and worker services |
| Workload profile | `serviceTimeMs` | `payloadSizeClass` | All service runtimes |
| Serverless lifecycle | `coldStartLatencyMs`, `idleTimeoutMs`, `maxConcurrency` | — | Serverless runtime |
| Retry and timeout | `timeoutMs`, `maxRetries` | `backoffMs` | Services that call dependencies |
| Rate limiting | `limitPerSecond` | `burst`, `rejectPolicy` | Public-facing or abuse-sensitive services |
| Async emission | — (not yet mapped) | all | Services that enqueue/publish events |

`circuit-breaker` and `idempotency` are **removed** from V1 (no engine mapping); do
not reintroduce them as toggles until they map to `sim.*`. A field is shown in the
builder only if it is executable **or** explicitly rendered under a "contract" label
(§0.2 rules 2–3).

## 7. Custom Node Builder Modal

The Custom Node Builder is opened from `Custom Node` or `My Node`, not from
`Service`. If the product keeps the existing `My Service` label, it should be
reserved for saved services, not arbitrary nodes.

### 7.1 Modal structure

Recommended modal tabs:

| Tab | Purpose |
|---|---|
| Basics | Name, description, icon, tags |
| Class | Choose component class: compute, storage, network, messaging, external, observability, auxiliary |
| Template | Choose closest runtime/component template |
| Capabilities | Select what the node can do: route, store, cache, enqueue, invoke, throttle, observe |
| Interface | Optional request/event interface if this node receives traffic |
| Traits | Runtime knobs exposed by the selected template |
| Validate | Shows backing type, allowed edges, required fields, and unsupported behavior |

### 7.2 Custom node fields

```ts
interface CustomNodeDefinition {
  id: string
  kind: 'custom-node'
  name: string
  description?: string
  iconKey?: string
  tags: string[]
  version: 1
  nodeClass: NodeClass
  runtimeTemplateId: RuntimeTemplateId
  backingComponentType: ComponentType
  capabilities: CapabilitySelection[]
  interface?: NodeInterface
  traits: TraitSelection[]
  validationPolicy: DefinitionValidationPolicy
  gradingHooks?: DefinitionGradingHooks
}
```

### 7.3 Node classes

```ts
type NodeClass =
  | 'compute'
  | 'storage'
  | 'network'
  | 'messaging'
  | 'external'
  | 'security'
  | 'observability'
  | 'coordination'
  | 'auxiliary'
```

Node class narrows the templates and capabilities the user can select.

| Node class | Example templates | Common capabilities |
|---|---|---|
| Compute | Serverless function, batch worker, container, VM | Process, invoke, scale, throttle |
| Storage | Relational DB, KV store, object store, search index | Read, write, persist, replicate |
| Network | API gateway, load balancer, CDN, edge router | Route, balance, cache at edge, reject |
| Messaging | Queue, pub/sub, stream, event bus | Enqueue, publish, subscribe, buffer |
| External | Third-party API, payment gateway, external auth | Invoke, fail, rate-limit, add latency |
| Security | WAF, IAM, firewall, secrets manager | Allow, deny, inspect, authorize |
| Observability | Logging, metrics, tracing, alerting | Collect, sample, retain, alert |
| Coordination | Lock, leader election, service registry | Coordinate, lock, elect, discover |
| Auxiliary | Rate limiter, circuit breaker, idempotency manager | Protect, throttle, dedupe, shed load |

### 7.4 Runtime templates

```ts
interface RuntimeTemplate {
  id: RuntimeTemplateId
  label: string
  nodeClass: NodeClass
  backingComponentType: ComponentType
  allowedDefinitionKinds: Array<'service' | 'custom-node'>
  capabilities: CapabilityId[]
  traitPacks: TraitPackId[]
  allowedIncomingRoles: EdgeRole[]
  allowedOutgoingRoles: EdgeRole[]
  simulates: string[]
  doesNotSimulate: string[]
}
```

The backing component type must be one known engine type. A custom node named
`My Lambda` should execute as `serverless-function`; a custom node named `My Cache`
should execute as `in-memory-cache`, `kv-store`, or another allowed existing type.

### 7.5 Capability selections

Capabilities describe what the node is allowed to do in the HLD and what edge types
make sense.

```ts
type CapabilityId =
  | 'accept-requests'
  | 'process-requests'
  | 'route-requests'
  | 'read-data'
  | 'write-data'
  | 'cache-data'
  | 'enqueue-messages'
  | 'publish-events'
  | 'subscribe-events'
  | 'invoke-external-api'
  | 'rate-limit'
  | 'authenticate'
  | 'observe'
  | 'coordinate'
```

Capabilities are mostly structural. They affect validation and grading. They become
runtime behavior only when mapped to implemented traits.

## 8. Shared Definition Primitives

Both builders should use the same primitives where possible.

### 8.1 Trait selection

```ts
interface TraitSelection {
  traitId: TraitPackId
  enabled: boolean
  required: boolean
  values: Record<string, unknown>
  fieldClasses: Record<string, 'info' | 'contract' | 'runtime'>
}
```

### 8.2 Dependency requirement

```ts
interface DependencyRequirement {
  id: string
  operationRef?: string
  targetRole:
    | 'service'
    | 'cache'
    | 'database'
    | 'queue'
    | 'stream'
    | 'object-store'
    | 'search-index'
    | 'external-api'
    | 'auth-provider'
    | 'observability'
    | 'any'
  targetNodeId?: string
  action:
    | 'read'
    | 'write'
    | 'invoke'
    | 'enqueue'
    | 'publish'
    | 'subscribe'
    | 'route'
    | 'observe'
  callMode: 'sync' | 'async'
  required: boolean
  condition?: 'always' | 'success' | 'failure' | 'cache-hit' | 'cache-miss'
}
```

### 8.3 Validation policy

```ts
interface DefinitionValidationPolicy {
  requireInterface: boolean
  requireAtLeastOneRuntimeTrait: boolean
  requireAllDependenciesToHaveEdges: boolean
  allowUndeclaredIncomingRequests: boolean
  allowUndeclaredOutgoingEdges: boolean
  lockAfterFirstRun: boolean
}
```

## 9. Canvas and Library Behavior

### 9.1 Creating a service

```text
User clicks Service tile
  -> Service Builder modal opens
  -> User composes service definition
  -> User clicks Create
  -> A concrete canvas node is placed
  -> Node label becomes the user-defined service name
  -> Node type becomes selected backing component type
  -> Node config references the service definition
```

### 9.2 Reusing a service

```text
User clicks My Service
  -> My Services modal opens
  -> User chooses saved definition
  -> User can drag it, fork it, or edit it
  -> Canvas node is created from that saved definition
```

### 9.3 Creating a custom node

```text
User clicks Custom Node / My Node
  -> Custom Node Builder modal opens
  -> User chooses node class
  -> User chooses runtime template
  -> User selects capabilities and traits
  -> User clicks Create
  -> Concrete canvas node is placed
  -> Node type is the template backing component type
```

### 9.4 Editing after creation

Clicking the placed node opens the normal properties panel. That panel should show:

- Definition summary.
- Edit definition button.
- Runtime/backing type.
- Interface and dependency contract.
- Trait controls.
- Validation messages.

Deep edits can reopen the builder modal. Lightweight edits can happen inline in the
properties panel.

## 10. Topology Data Model

Definitions should live at topology scope. Canvas nodes should reference them.

```ts
interface TopologyJSON {
  nodes: ComponentNode[]
  edges: ComponentEdge[]
  definitions?: Array<ServiceDefinition | CustomNodeDefinition>
}

interface ComponentNode {
  id: string
  type: ComponentType
  label: string
  config?: Record<string, unknown> & {
    definitionId?: string
    definitionKind?: 'service' | 'custom-node'
  }
}
```

The actual runtime still uses `ComponentNode.type`. The definition does not replace
the engine's component taxonomy.

Precedence for settings:

```text
node instance override
  > definition selected trait values
  > runtime template defaults
  > component type defaults
```

## 11. Execution Semantics

At simulation time:

1. The source emits requests using configured request distributions.
2. Edges and routing rules decide where requests can travel.
3. A service or custom node receives a request only when the graph routes traffic to
   it.
4. Runtime traits on that node determine queueing, capacity, latency, errors,
   throttling, retries, and timeouts.
5. The node can send traffic onward only through visible outgoing edges.
6. Definitions are used for validation, grading, display, and serialization.

Definitions do not execute code. They do not inspect arbitrary payloads. They do
not create hidden reads/writes. They do not route around missing edges.

## 12. Example Architecture: User-Defined URL Shortening Service

This is only an example of what a user can create; it should not be hard-coded as a
UI choice.

Correct HLD:

```text
Input Source
  -> API Gateway
  -> user-created service: URL Shortening Service
  -> Cache
  -> Mapping Database

URL Shortening Service
  -> Analytics Queue
  -> Analytics Worker
```

The service definition might contain:

| Block | Example value |
|---|---|
| Identity | `URL Shortening Service` |
| Runtime | Long-running service backed by `microservice` |
| Requests | `create-short-url`, `resolve-short-url`, `delete-short-url` |
| Fields | `longUrl`, `shortCode`, `tenantId` |
| Dependencies | Cache read/write, database read/write, analytics enqueue |
| Traits | IO-bound workload, worker count, queue slots, timeout, retry |

Request flow:

```text
Input Source sends resolve-short-url
API Gateway routes request
URL Shortening Service receives request
Service applies runtime traits
Service sends cache read through visible edge
Cache returns modeled hit or miss
Service sends database read on modeled miss path
Service returns redirect response
Service optionally enqueues analytics asynchronously
```

The service is not special because it is a URL shortener. It is special because the
user defined its interface, dependencies, and traits.

## 13. Example Architecture: User-Defined Lambda Node

This is a custom node example because the user wants a missing component, not a
business service.

The custom node definition might contain:

| Block | Example value |
|---|---|
| Identity | `Lambda Function` |
| Node class | Compute |
| Runtime template | Serverless function |
| Backing type | `serverless-function` |
| Capabilities | Accept requests, process requests, invoke dependencies |
| Traits | Cold start latency, idle timeout, max concurrency, service time |

Possible request flow:

```text
Input Source
  -> API Gateway
  -> Lambda Function
  -> Database or external API
```

The user can label it `Thumbnail Lambda`, `Redirect Lambda`, or `Fraud Check
Lambda`. The runtime remains the same until the user changes traits or topology.

## 14. Validation Rules

Validation should run in the builder modal, properties panel, import flow, pre-run,
and submission flow.

### 14.1 Definition validation

- Definition IDs are unique.
- Definition kind is valid.
- Service definitions include at least one request when policy requires an
  interface.
- Custom nodes include a node class and runtime template.
- Runtime template resolves to exactly one known backing component type.
- Required trait fields are present.
- Contract fields use allowed scalar types.
- User-entered names do not become engine component types.

### 14.2 Node validation

- `config.definitionId` resolves to a topology definition.
- Node `type` matches the definition's backing component type.
- Node instance overrides stay within trait bounds.
- Saved definition edits either update all instances or fork, based on user choice.

### 14.3 Graph validation

- Required dependency requirements have matching visible edges.
- Edge direction matches the declared action.
- Request types entering a service are declared by the service interface when
  strict mode is enabled.
- Async dependencies point to async-capable nodes.
- Storage/cache requirements point to compatible storage/cache nodes.
- Custom node capabilities are compatible with incoming and outgoing edges.

## 15. Question Policy

> **Status: NOT IMPLEMENTED.** The `BuilderPolicy` below is the target design. Today
> there is **no builder-specific gating**. See §15.1 for how grading and authoring
> actually behave against created nodes right now.

Question authors need explicit control.

```ts
interface BuilderPolicy {
  allowServiceBuilder: boolean
  allowMyServices: boolean
  allowCustomNodeBuilder: boolean
  allowMyNodes: boolean
  allowedNodeClasses: NodeClass[]
  allowedRuntimeTemplates: RuntimeTemplateId[]
  allowedTraitPacks: TraitPackId[]
  maxDefinitions: number
  maxOperationsPerService: number
  requireContracts: boolean
  lockDefinitionsAfterFirstRun: boolean
}
```

Recommended defaults (once `BuilderPolicy` ships):

- Open build: allow Service Builder, My Services, Custom Node Builder, and My Nodes.
- Graded assignment: opt in per question.
- Palette-learning assignment: disable Custom Node Builder and optionally allow only
  service labels/contracts.

### 15.1 Grading and authoring against created nodes (current reality)

This is how creation interacts with evaluation **today**, and what test-case authors
must do until `BuilderPolicy` exists.

**Creation is transparent to the grader.** Every grading criterion
(`placement`, `guardedPath`, `fanout`, `storageFit`, `forbidUnjustified`,
`stateTransition`, …) matches on **`componentType`** (plus `nodeId`, `accessPattern`,
and runtime transitions). It never reads labels or `customDefinition`. A created
service serializes as its backing type (`microservice` / `serverless-function` /
`batch-worker`); a created custom node serializes as its backing type
(`in-memory-cache`, `relational-db`, `queue`, `api-endpoint`, …). So a learner's
"URL Shortening Service" is graded **as a `microservice`** and existing rubrics match
it with no change.

**What authors must adjust:**

1. **Accept a *set* of component types, not one.** The Service Builder lets the
   runtime be a free choice, so pinning a single `componentType` fails valid
   alternatives. Use `storageFit.accept[]` / `partial[]`; for single-type criteria
   (`placement`, `guardedPath`) either broaden intent or constrain the runtime with
   the node-type gates below. (Extends [[multiple-valid-solutions-grading]].)
2. **Gate creation with the existing `allowedNodeTypes` / `forbiddenNodeTypes`.**
   These question constraints operate on the **resolved componentType**, so they
   already apply to created nodes — a created cache counts as `in-memory-cache`. Use
   them so a learner can't simply conjure the exact node the question is testing.
3. **Never grade the declared contract.** Operations, capabilities, and per-operation
   dependencies from the builder are **documentation-only and invisible to grading**
   (`src/engine/analysis/*` never reads `customDefinition`). A `guardedPath` needs the
   learner's **actual edge** through the guard, not a *declared* dependency. This is
   the same honesty boundary as §0.2.
4. **Label-independence is a feature.** A `microservice` mislabeled "Redis Cache"
   still fails cache criteria; authors need not defend against naming.

**Current limitation.** Because `BuilderPolicy` is unimplemented, you can only gate at
the **componentType** level. You cannot yet author "service builder allowed, but only
the long-running runtime" or "custom-node creation forbidden while service creation is
allowed." That finer control requires shipping §15's `BuilderPolicy`.

## 16. Builder UX Requirements

- The builder is a modal, because creation is a focused multi-step composition task.
- The existing right properties panel remains the editor for selected canvas nodes.
- Builder choices are searchable and filterable.
- Templates and traits should be selected with chips/cards, then configured with
  forms.
- Required fields are marked clearly.
- Validation runs before create.
- The final review step shows:

```text
Will create: <user label>
As engine type: <ComponentType>
With runtime: <RuntimeTemplate>
Required edges still missing: <count/list>
Runtime traits enabled: <list>
```

- Cancel closes without placing a node.
- Create places a node and selects it.
- Save to My Services or My Nodes stores the definition for reuse.
- Fork creates a new definition ID.

## 17. Implementation Plan

### Milestone 0: Registry and schema

- Define service and custom node schemas.
- Define runtime template registry.
- Define trait pack metadata.
- Add topology-level `definitions`.
- Add validation for definition-to-node matching.
- Round-trip existing topologies unchanged.

### Milestone 1: Service Builder

- Convert `Service` tile into a modal entry point.
- Add service definition draft state.
- Add tabs for basics, interface, operations, dependencies, runtime, traits, and
  validation.
- Create canvas node from the selected runtime.
- Save definitions into `My Services`.

### Milestone 2: My Services

- Convert `My Service` tile into a saved-definition library.
- Support reuse, edit, duplicate, fork, delete, and drag-to-canvas.
- Show which canvas instances use each definition.

### Milestone 3: Custom Node Builder

- Add `Custom Node` or `My Node` entry.
- Add node class selection.
- Add runtime template and capability selection.
- Reuse trait pack controls.
- Create canvas node from the backing component type.

### Milestone 4: Contract-to-graph validation

- Validate dependencies against edges.
- Validate request types against request distributions and edge filters.
- Validate capabilities against edge roles.
- Surface issues in both modal and properties panel.

### Milestone 5: Authoring and grading

- Add builder policy to question configuration.
- Add rubric facts for definitions, traits, capabilities, and dependency edges.
- Ensure grading never relies on labels alone.

## 18. Acceptance Criteria

- Clicking `Service` opens the Service Builder modal instead of placing an unnamed
  generic final node.
- A user can create any named application service through the modal without choosing
  from hard-coded domain examples.
- `My Service` opens saved service definitions and supports reuse/fork/edit.
- A custom node flow exists separately from service creation.
- Custom nodes require node class, runtime template, capabilities, and traits.
- Every created canvas node still has a known engine `ComponentType`.
- The UI shows which fields are info, contract, and runtime.
- Required dependencies are validated against visible graph edges.
- Existing simulation remains deterministic.
- Existing topologies without definitions continue to work.

## 19. Open Product Decisions

1. Should the existing `My Service` tile be renamed to `My Services`?
   Recommended: yes.
2. Should there be a separate `Custom Node` tile or should it live inside a generic
   `Create` modal?
   Recommended: separate tile or clear tab, because the mental model differs from
   services.
3. Should users save definitions globally or only inside the current topology in
   V1?
   Recommended: topology-local first, then global library.
4. Should a service be allowed to use `serverless-function` runtime in V1?
   Recommended: yes, if the UI makes clear that the service is the application
   contract and serverless is only the deployment/runtime.
5. Should fields/classes/traits be author-extensible?
   Recommended: not in V1. Keep the block library platform-owned until validation
   and grading are stable.

## 20. Source Alignment

- Component types are defined in `src/engine/core/types.ts`.
- Component specs and canvas serialization are owned by
  `src/engine/catalog/componentSpecs.ts` and
  `src/engine/catalog/nodeSpecTypes.ts`.
- Palette templates map UI choices to known component types in
  `src/engine/catalog/paletteTemplates.ts`.
- Runtime traits should reuse existing trait/capability modules rather than adding
  duplicate forms.
- Request flow must align with
  `ns-simulator-docs/specs/request-flow-direction-and-topology-rules.md`.
- Resource behavior must align with
  `ns-simulator-docs/specs/resource-allocation-and-derived-concurrency.md`.

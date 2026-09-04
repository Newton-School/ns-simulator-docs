# Custom Services and Custom Nodes

> Status: Proposed
>
> Purpose: Let learners describe missing application and infrastructure components
> while keeping simulation deterministic and gradeable.

## 1. Decision

The canvas supports two creation flows:

| Flow | Learner creates | Bound runtime | Examples |
|---|---|---|---|
| **Define service** | An application responsibility | `microservice` | Auth, URL Shortener, Search, Orders |
| **Define custom node** | A component not exposed by the palette | A selected supported template | Lambda, batch worker, partner API |

Both are user-defined *definitions*, but neither introduces user-executable code.
The learner owns the name, interface, dependencies, configuration, and topology. The
platform owns execution semantics through a known runtime template.

```text
user-defined contract + platform runtime template = deterministic simulation
user-defined executable code                        = unsupported
```

This is intentionally different from assigning a new arbitrary component type. A
custom Lambda must resolve to the existing `serverless-function` component type; a
URL Shortener service resolves to `microservice`. The user-visible definition says
what the node represents. The known component type says how the engine executes it.

## 2. Goals and Boundaries

### Goals

- Model application services that do not warrant a separate palette item.
- Let a learner create a missing component by selecting a supported runtime template.
- Capture a readable HLD contract: requests, operations, dependencies, outputs, and
  physical/runtime configuration.
- Validate that the graph agrees with the declared contract.
- Preserve seed reproducibility, validation, and deterministic grading.
- Keep definitions topology-local in V1.

### Non-goals

- User-written JavaScript, scripts, SQL, or arbitrary expressions.
- Inferring a correct system design from a service name.
- Treating labels or descriptions as executable semantics.
- Automatically creating hidden dependencies or edges from a contract.
- Reproducing every cloud provider's exact implementation, quota, or billing model.

## 3. Terminology

### Service definition

A **service definition** models a business responsibility on a long-running
`microservice` runtime. Recipes can help learners start from common concepts but do
not change engine physics.

### Custom-node definition

A **custom-node definition** models a component whose runtime behavior differs from
an ordinary service. It must choose a platform-supplied runtime template.

### Runtime template

A **runtime template** maps to an existing component type, its traits, defaults,
allowed configuration, metrics, and validation rules.

The initial allowed templates should be deliberately bounded:

| Runtime template | Component type | Modeled behavior | Typical use |
|---|---|---|---|
| Long-running service | `microservice` | Queueing, resources, processing, timeout, retry | Auth, URL shortening |
| Serverless function | `serverless-function` | Cold start, idle window, concurrency throttle | Lambda-like handler |
| Background worker | `batch-worker` | Async processing and queueing | Import, notification, ETL |
| External dependency | `third-party-api-connector` | External latency/error behavior | Payment or partner API |

The platform adds a template only when it has a deterministic behavior contract,
metrics, configuration UI, and tests.

### Service contract

A **service contract** is a structured HLD description attached to a definition. It
records allowed inputs, operations, outputs, and downstream intents. It is not
application code.

## 4. UX Specification

The existing right-side inspector is the editing surface. It preserves canvas context
while learners verify the topology. A small wizard is used only to create a
definition; ongoing changes happen in the inspector.

### 4.1 Entry points

Add a **Create** group at the top of the Component Library:

```text
Create
  + Define service
  + Define custom node
```

Question policy controls visibility and availability of both actions.

### 4.2 Define service workflow

1. Learner selects **Define service**.
2. They enter a name and optional description.
3. They select `Blank`, `Authentication`, `URL Shortener`, `CRUD API`, or `Search`.
4. The recipe supplies editable operation/dependency suggestions only.
5. The canvas receives a selected `microservice` node with a definition reference.
6. The inspector exposes Identity, Interface, Dependencies, Resources, Runtime, and
   Validation sections.
7. The learner draws all required edges; validation highlights contract drift.

### 4.3 Define custom node workflow

1. Learner selects **Define custom node**.
2. They enter a name and description.
3. They choose a permitted runtime template.
4. The picker shows the template's `Simulates` and `Does not simulate` statements.
5. They declare request types, outputs, dependencies, and template configuration.
6. The canvas receives a node of the selected existing component type.

The template picker must say what will actually execute. It must never imply that
typing an operation name creates an arbitrary new simulation behavior.

### 4.4 Inspector sections

| Section | Description |
|---|---|
| Identity | Name, description, badge, recipe/template provenance |
| Interface | Accepted request types, optional HTTP method/path, response type |
| Dependencies | Expected target and action: read, write, invoke, enqueue, publish |
| Resources | Existing sizing and execution-profile controls |
| Runtime | Existing template traits, such as cold-start configuration |
| Validation | Contract-to-canvas errors/warnings and suggested fixes |

Accessibility requirements:

- All creation and edit controls are keyboard reachable with explicit labels.
- The first invalid wizard field receives focus after submit.
- Creation selects the new node and announces its selected runtime template.
- Undo restores both a newly placed node and its definition; delete warns when a
  definition has instances.

## 5. Data Contract

Definitions live at topology scope. Node `type` stays a normal `ComponentType`, so
the engine does not need to dynamically load untrusted user types.

```ts
type DefinitionKind = 'service' | 'custom-node'

type RuntimeTemplateId =
  | 'long-running-service'
  | 'serverless-function'
  | 'background-worker'
  | 'external-dependency'

interface NodeDefinition {
  id: string
  kind: DefinitionKind
  name: string
  description?: string
  runtimeTemplate: RuntimeTemplateId
  version: 1
  interface: { operations: OperationContract[] }
}

interface OperationContract {
  id: string
  requestType: string
  request?: { method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'; path?: string }
  responseType: string
  dependencyIntents: DependencyIntent[]
}

interface DependencyIntent {
  targetNodeId?: string
  targetRole: 'cache' | 'database' | 'service' | 'external-api' | 'queue' | 'any'
  action: 'read' | 'write' | 'publish' | 'invoke' | 'enqueue'
  required: boolean
  condition?: 'always' | 'cache-miss'
}

interface TopologyJSON {
  // Existing fields remain unchanged.
  definitions?: NodeDefinition[]
}

interface ComponentNode {
  // Existing fields remain unchanged.
  config?: Record<string, unknown> & { definitionId?: string }
}
```

The runtime template registry is platform-owned:

```ts
interface RuntimeTemplate {
  id: RuntimeTemplateId
  componentType: ComponentType
  label: string
  allowsDefinitionKind: readonly DefinitionKind[]
  simulates: readonly string[]
  notModeled: readonly string[]
}
```

No definition contains a user-provided `ComponentType`. The registry resolves:

```text
long-running-service -> microservice
serverless-function  -> serverless-function
background-worker    -> batch-worker
external-dependency  -> third-party-api-connector
```

## 6. Contract Semantics

### 6.1 Request vocabulary

The request type is the linking key across the HLD:

```text
source requestDistribution[].type
    -> service operation.requestType
        -> supported conditional edge condition
```

Example vocabulary for a URL shortener:

```text
create-short-url
resolve-short-url
update-short-url
delete-short-url
```

The new UI uses structured filters. It serializes only to the existing supported
edge-condition grammar; it does not accept new free-form JavaScript.

### 6.2 Three field classes

| Class | Example | Effect |
|---|---|---|
| Informational | Operation name `generate-short-code` | Readable HLD only |
| Structural | `resolve-short-url` requires a cache read | Checked against graph edges |
| Executable | Lambda cold-start latency, cache hit rate | Alters the simulation |

The inspector must label these classes visibly. This prevents a learner from
believing an explanatory domain verb changed simulation physics.

### 6.3 Execution authority

In V1, graph edges and runtime traits remain the execution authority. Definitions
are used for presentation, validation, serialization, and grading. They do not
generate hidden calls.

An optional later `operation-contract` trait may execute a finite declarative action
set (`read`, `write`, `invoke`, `publish`, `enqueue`) only after its response,
fan-out/fan-in, cache-miss, retry, timeout, tracing, metrics, and seeded tests are
specified. Arbitrary code remains out of scope.

## 7. Worked HLD: URL Shortener Service

The learner chooses **Define service -> URL Shortener**. The recipe creates a
topology-local definition and a `microservice` instance.

```json
{
  "definitions": [
    {
      "id": "def.url-shortener",
      "kind": "service",
      "name": "URL Shortener",
      "description": "Creates short links and resolves redirects.",
      "runtimeTemplate": "long-running-service",
      "version": 1,
      "interface": {
        "operations": [
          {
            "id": "create",
            "requestType": "create-short-url",
            "request": { "method": "POST", "path": "/shorten" },
            "responseType": "short-url-created",
            "dependencyIntents": [
              { "targetNodeId": "url-mapping-db", "targetRole": "database", "action": "write", "required": true, "condition": "always" }
            ]
          },
          {
            "id": "resolve",
            "requestType": "resolve-short-url",
            "request": { "method": "GET", "path": "/:code" },
            "responseType": "redirect",
            "dependencyIntents": [
              { "targetNodeId": "url-cache", "targetRole": "cache", "action": "read", "required": true, "condition": "always" },
              { "targetNodeId": "url-mapping-db", "targetRole": "database", "action": "read", "required": true, "condition": "cache-miss" }
            ]
          }
        ]
      }
    }
  ],
  "nodes": [
    {
      "id": "url-shortener",
      "type": "microservice",
      "label": "URL Shortener",
      "config": { "definitionId": "def.url-shortener" },
      "resources": { "workloadKind": "io-bound" }
    }
  ]
}
```

Expected HLD:

```text
Client -> API Gateway -> URL Shortener -> URL Cache
                                         -> URL Mapping DB
```

Request paths:

```text
create-short-url:  Client -> Gateway -> URL Shortener -> Mapping DB
resolve-short-url: Client -> Gateway -> URL Shortener -> Cache -> Mapping DB on miss
```

The `microservice` runtime supplies queueing, capacity, latency, timeout, retry, and
failure behavior. The contract describes the service's domain role and verifies the
HLD; it does not execute a URL encoding algorithm.

## 8. Worked HLD: URL Redirect Lambda Custom Node

The learner chooses **Define custom node -> Serverless function**.

```json
{
  "definitions": [
    {
      "id": "def.redirect-lambda",
      "kind": "custom-node",
      "name": "URL Redirect Lambda",
      "runtimeTemplate": "serverless-function",
      "version": 1,
      "interface": {
        "operations": [
          {
            "id": "resolve",
            "requestType": "resolve-short-url",
            "responseType": "redirect",
            "dependencyIntents": [
              { "targetNodeId": "url-cache", "targetRole": "cache", "action": "read", "required": true, "condition": "always" },
              { "targetNodeId": "url-mapping-db", "targetRole": "database", "action": "read", "required": true, "condition": "cache-miss" }
            ]
          }
        ]
      }
    }
  ],
  "nodes": [
    {
      "id": "url-redirect-lambda",
      "type": "serverless-function",
      "label": "URL Redirect Lambda",
      "config": {
        "definitionId": "def.redirect-lambda",
        "coldStartLatencyMs": 150,
        "idleTimeoutMs": 30000,
        "maxConcurrency": 100
      }
    }
  ]
}
```

Unlike a service label, this template selection changes execution. The node incurs a
cold-start delay after idle periods and throttles when active work reaches its
configured concurrency ceiling. AWS defines Lambda concurrency as the number of
in-flight requests and explains that execution environments initialize as functions
scale; those are the real-world concepts represented by this bounded model.
[AWS Lambda scaling](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html)

The V1 model does not claim provider-exact quotas, provisioned concurrency pools,
container image pulls, billing, or networking behavior.

## 9. Validation and Policy

Validation runs during edit, import, pre-run, and submission.

### Definition integrity

- Definition IDs are unique within a topology.
- A runtime template must be platform-registered and policy-allowed.
- A service definition uses `long-running-service` in V1.
- Operation IDs and request types are non-empty and unique per definition.
- Optional method/path values use the finite method enum and a `/`-prefixed path.

### Node integrity

- `config.definitionId` resolves to an existing definition.
- Node `type` matches the definition's resolved template component type.
- Deleting an in-use definition is rejected; users must remove or detach instances.
- Cloning creates a new node instance; per-instance runtime settings do not mutate the
  reusable definition.

### HLD integrity

- Every required dependency intent has a matching outgoing edge to its named target
  or compatible target role.
- A source may use an undeclared request type, but receives a warning until an
  operation accepts it.
- Undeclared outbound edges are warnings in Open Build and errors in locked
  assignments.
- L7 routing limits still apply. A service declaration cannot make an L4 component
  capable of path/header routing.
- Existing graph cycle and timeout safeguards continue to apply.

### Question policy

```ts
interface CustomDefinitionPolicy {
  allowServiceDefinitions: boolean
  allowCustomNodeDefinitions: boolean
  allowedRuntimeTemplates: RuntimeTemplateId[]
  maxDefinitions: number
  requireContracts: boolean
  allowDefinitionEditsAfterFirstRun: boolean
}
```

Default graded-assignment policy is explicit opt-in. Open Build enables both flows
with a bounded template list. This preserves the ability to teach a constrained
palette when component selection is the learning objective.

## 10. Implementation Mapping

This feature extends existing ownership boundaries rather than adding a parallel
node/editor system.

| Area | Target | Required change |
|---|---|---|
| Types | `src/engine/core/types.ts` | Add definitions and optional `TopologyJSON.definitions` |
| Validation | `src/engine/validation/validator.ts` | Strict definition schemas and cross-reference validation |
| Runtime registry | New `src/engine/catalog/runtimeTemplates.ts` | Template -> existing component type, labels, allowed kinds, honesty metadata |
| Canvas data | `src/engine/catalog/nodeSpecTypes.ts` | Preserve `definitionId` through canvas state |
| Serialization | `src/renderer/src/utils/topologyCanvasAdapter.ts`, `src/renderer/src/hooks/useTopologySerializer.ts` | Round-trip definitions and node links |
| Library | `src/renderer/src/components/library/ComponentLibrarySidebarPanel.tsx` | Add policy-aware Create actions |
| Inspector | `src/renderer/src/components/properties/PropertiesPanel.tsx` | Host definition sections alongside generic fields |
| Form UI | New definition wizard/editor components | Create and edit contracts without raw JSON |
| Trait UI | `src/engine/traits/capabilityModules.ts` | Reuse existing template trait controls; no duplicate Lambda form |
| Grading | Structural criteria/verdict projection | Check definition/template/operation/dependency facts, not labels |

The existing `serverless-function` component and cold-start trait are reused. This is
important: custom-node creation makes existing semantics discoverable; it is not a
new engine fork.

## 11. Delivery Plan

### Milestone 0: Safe schema foundation

- Add topology-local definition types, template registry, schema validation, and
  import/export round-trips.
- Guarantee absence of definitions leaves old topology behavior unchanged.
- No UI entry point yet.

### Milestone 1: Define service

- Deliver Define Service wizard and recipes.
- Bind services to `microservice`.
- Add contract editor, edge validation, inspector summary, and URL Shortener sample.

### Milestone 2: Define custom node

- Deliver template picker for serverless function, background worker, and external
  dependency.
- Reuse existing trait fields in the inspector.
- Add assignment capability controls and the URL Redirect Lambda sample.

### Milestone 3: Assessment integration

- Add structural rubric criteria for definition kind, template, operation, request
  vocabulary, and required dependencies.
- Let question authors scaffold and optionally lock definitions.

### Milestone 4: Optional executable operation plans

- Ship a finite operation-contract trait only when a concrete question requires it.
- Include trace events, metrics, verdict projection, and seed-equality tests.

## 12. Acceptance Criteria

### Services

- Learners can create, edit, clone, and delete topology-local services.
- A service serializes as `type: "microservice"` plus `definitionId`.
- The URL Shortener recipe supplies editable create/resolve operations and never
  creates hidden edges.
- Missing cache/database edges are shown before a run.

### Custom nodes

- Learners select only policy-allowed templates.
- A Lambda custom node serializes as `type: "serverless-function"` and retains the
  existing cold-start/throttle behavior and metrics.
- Fabricated component types and unregistered behavior are rejected.
- Template/type mismatches block simulation with an actionable message.

### Compatibility, grading, and determinism

- Legacy topologies validate, serialize, and simulate unchanged.
- Definitions round-trip between canvas and TopologyJSON without loss.
- Same topology, scenario, and seed produce identical results, except for explicit
  existing deterministic traits.
- Grading checks structural contracts and simulation output, never label text alone.
- No definition field can execute code or issue a network request.

## 13. Test and QA Checklist

- Schema: duplicates, malformed operations, unknown definition IDs, wrong template
  type, legacy no-definition topology.
- Serializer: canvas -> topology -> canvas retains all definition fields and links.
- Validator: missing dependency edge, unsupported routing condition, locked-policy
  violation, L4/L7 capability violation.
- Traits: cold starts and max-concurrency throttles remain identical when the Lambda
  is definition-backed.
- UI: keyboard wizard flow, focus-to-error, cancellation, undo/redo, deletion, and
  question policy behavior.
- E2E: URL Shortener HLD validates; bypassing a required cache produces the expected
  structural or scenario failure.
- Regression: run all existing question packages and compare deterministic verdicts
  after each enabled milestone.

## 14. Open Product Decisions

1. Enable custom definitions by default in graded assignments, or only when a
   question opts in? Recommended: question opt-in.
2. Keep definitions topology-local in V1? Recommended: yes.
3. Release structural contracts before executable operation plans? Recommended: yes.
4. Initial custom templates? Recommended: serverless function, background worker,
   and external dependency after long-running service.

## 15. Source Alignment

- Component types and `ComponentNode.config` are defined in
  `src/engine/core/types.ts`.
- Schema validation is in `src/engine/validation/validator.ts`.
- `lambda-function` already maps to `serverless-function` in
  `src/engine/catalog/paletteTemplates.ts`.
- Serverless cold-start/concurrency behavior is in `src/engine/traits/coldStart.ts`.
- Trait config already flows to the properties UI through
  `src/engine/traits/capabilityModules.ts` and the existing form system.
- The persistent right inspector is hosted by
  `src/renderer/src/components/layout/WorkspaceLayout.tsx`.


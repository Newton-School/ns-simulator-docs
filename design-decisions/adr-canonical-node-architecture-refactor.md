# ADR: Canonical Node Architecture Refactor (Engine-First + Discriminated Unions)

## Status
Proposed

## Date
March 17, 2026

## Context
The current system has a semantic split between what the product is (a distributed-systems simulator) and how the code is named/organized:

1. Renderer code treats domain entities as generic UI nodes (`serviceNode`, `computeNode`) while the engine defines canonical simulation entities (`ComponentNode`, `ComponentType`).
2. The same concept is named differently across layers (`node`, `component`, `type`, `computeType`) and some unions drift from runtime values.
3. Data fields mix naming styles (`snake_case` and `camelCase`) and weakly-typed boundaries (`any`) hide contract violations.
4. Folder structure in renderer is mostly UI-composition oriented (`atoms`, `molecules`, `organisms`) rather than domain boundaries (`topology`, `simulation`, `adapters`, `validation`).
5. Persistence currently favors React Flow shape snapshots instead of canonical topology documents.

This creates semantic ambiguity, weak type guarantees, and scaling risk for both contributors and product evolution.

## Decision
Adopt an engine-first canonical architecture and enforce production-grade naming semantics across code and docs.

1. Canonical topology state (`TopologyJSON`) is the only simulation source of truth.
2. `Component*` vocabulary is canonical for domain entities; `Node*` is reserved for renderer/React Flow view models.
3. Renderer data uses strict discriminated unions projected from canonical state.
4. VPC/AZ/Subnet remain UI-only containers and are excluded from engine-exported `TopologyJSON.nodes`.
5. Persistence uses versioned workspace documents that include canonical topology + UI metadata.
6. Naming conventions are formalized and enforceable (field style, type style, module naming, bounded-context folders).

## Semantic Naming Standard (Authoritative)
### Vocabulary Contract
1. `Component` means simulation-domain element (`ComponentNode`, `ComponentType`, `ComponentTemplate`).
2. `Node` means renderer graph element (`RendererNode`, React Flow `Node`).
3. `Topology` means canonical model consumed by engine.
4. `Workspace` means user-editable document (`topology + ui metadata + view state`).
5. `Template` means palette definition used to create domain components.

### Naming Rules
1. Types/interfaces/enums: `PascalCase`.
2. Variables/functions/properties: `camelCase`.
3. Constants: `UPPER_SNAKE_CASE`.
4. File naming:
   1. React components: `PascalCase.tsx`.
   2. Non-component modules: `camelCase.ts`.
   3. ADR/docs: `kebab-case.md`.
5. No `snake_case` in application model fields.
6. No ambiguous store names (`useStore`) in domain code; stores must be bounded (`useTopologyStore`, `useSimulationStore`, `useWorkspaceStore`).

### Rename Matrix (Target)
1. `NodeType` (UI union) -> `RendererNodeKind`.
2. `AnyNodeData` -> `RendererNodeData`.
3. `ServiceNodeData` -> `ServiceNodeVisualState`.
4. `ComputeNodeData` -> `ComputeNodeVisualState`.
5. `VpcNodeData` -> `ContainerNodeVisualState`.
6. `useStore` -> `useTopologyStore` (or split: `useWorkspaceStore` + `useTopologyStore`).
7. `useFlowPersistence` -> `useWorkspacePersistence`.
8. `FileService` -> `WorkspaceFileService`.
9. `cpu_usage` -> `cpuUsage`; `queue_depth` -> `queueDepth`; `is_overloaded` -> `isOverloaded`.

## Public Interfaces and Types
The refactor introduces and formalizes:

1. `WorkspaceFileV2`:
   1. `version: "2.0"`.
   2. `topology: TopologyJSON`.
   3. `ui: { containers; nodeUiState; layout }`.
2. Template contracts:
   1. `ComponentTemplate` for engine-exported components.
   2. `ContainerTemplate` for UI-only grouping containers.
3. Renderer projection union:
   1. `RenderNodeDataBase`.
   2. `ComputeRenderNodeData`.
   3. `ServiceRenderNodeData`.
   4. `SecurityRenderNodeData`.
   5. `ContainerRenderNodeData`.
4. Explicit actions replacing untyped mutation:
   1. `updateComponentNode(id, patch: DeepPartial<ComponentNode>)`.
   2. `updateNodeUiState(id, patch: Partial<NodeUiState>)`.
   3. `updateContainer(id, patch: Partial<UiContainerNode>)`.
5. Render/engine separation:
   1. React Flow `node.type` remains renderer-kind key.
   2. Canonical component kind remains `ComponentType`.

## Production-Grade Folder Structure (Target)
This ADR standardizes the target project layout to domain-first boundaries:

```text
src/
  engine/
    model/
    events/
    validation/
    runtime/
    mocks/
  main/
  preload/
  renderer/src/
    app/
    domains/
      topology/
        model/
        registry/
        adapters/
        store/
        validation/
      simulation/
        model/
        worker-client/
        store/
      workspace/
        persistence/
        schema/
        store/
    features/
      canvas/
      inspector/
      palette/
      validation-panel/
    ui/
      primitives/
      composites/
    shared/
      types/
      constants/
      utils/
```

### Folder Governance Rules
1. `domains/*` can import `shared/*`; cross-domain imports go through domain public index.
2. `features/*` orchestrate UI behavior and call domain APIs; no raw persistence logic inside components.
3. `ui/*` contains reusable visual building blocks only.
4. Direct engine-type imports in renderer go through topology domain boundary (`domains/topology/model`).

## Migration Plan
### Phase 0: Naming Baseline
1. Freeze vocabulary contract in docs and lint config.
2. Add naming lint rules (`@typescript-eslint/naming-convention`).
3. Add glossary in docs (`Component` vs `Node` vs `Workspace`).

### Phase 1: Types and Registry
1. Replace untyped registry defaults with strict template contracts.
2. Remove drifting unions and align runtime/template values.
3. Normalize field names to camelCase with compatibility adapters.

### Phase 2: Canonical Store
1. Introduce domain-bounded topology/workspace stores.
2. Keep UI-only container and UI-state maps separate from canonical topology.
3. Run topology validation on every mutation.

### Phase 3: Adapter and Feature Boundaries
1. Route palette creation through template IDs only.
2. Derive React Flow nodes from canonical topology via adapters.
3. Move persistence and drag payload parsing out of component layer into domain services.

### Phase 4: Folder Realignment
1. Move renderer logic from composition-oriented folders to domain-first modules.
2. Keep UI composition folders as presentation-only (`ui/primitives`, `ui/composites`).
3. Enforce import boundaries.

### Phase 5: Persistence and Legacy Compatibility
1. Add `WorkspaceFileV2` export/import.
2. Migrate legacy nested React Flow files into canonical workspace shape.
3. Always save in v2 format after any successful load.

## Default Mapping Decisions (Current Palette)
These defaults remain valid for migration and template normalization:

1. `backend-server` -> `microservice` (`compute`).
2. `lambda-function` -> `serverless-function` (`compute`).
3. `async-worker` -> `batch-worker` (`compute`).
4. `cron-job` -> `faas-background` (`compute`).
5. `auth-service` -> `auth-service` (`compute`).
6. `search-service` -> `search-service` (`compute`).
7. `primary-db` -> `relational-db` (`storage-and-data`).
8. `read-replica` -> `relational-db` (`storage-and-data`, with replica role in config).
9. `redis-cache` -> `in-memory-cache` (`storage-and-data`).
10. `nosql-db` -> `nosql-db` (`storage-and-data`).
11. `object-storage` -> `object-storage` (`storage-and-data`).
12. `search-index` -> `search-index` (`storage-and-data`).
13. `load-balancer` -> `load-balancer` (`network-and-edge`).
14. `api-gateway` -> `api-gateway` (`network-and-edge`).
15. `ingress-controller` -> `ingress-controller` (`network-and-edge`).
16. `reverse-proxy` -> `reverse-proxy` (`network-and-edge`).
17. `nat-gateway` -> `nat-gateway` (`network-and-edge`).
18. `vpn-gateway` -> `vpn-gateway` (`network-and-edge`).
19. `cdn` -> `cdn` (`network-and-edge`).
20. `dns` -> `internal-dns` (`dns-and-certs`).
21. `message-queue` -> `queue` (`messaging-and-streaming`).
22. `message-broker` -> `message-broker` (`messaging-and-streaming`).
23. `waf` -> `waf` (`security-and-identity`).
24. `firewall-rule` -> `firewall` (`security-and-identity`).
25. `external-service` -> `third-party-api-connector` (`external-and-integration`).
26. `client-user` -> `api-endpoint` (`compute`, default assumption).
27. `vpc-region`, `availability-zone`, `subnet` -> UI-only containers.

## Validation, Testing, and Acceptance Scenarios
1. Template drop creates correctly typed canonical component/container.
2. Store mutation updates canonical topology and triggers live validation.
3. Adapter emits correct renderer node kind and union variant.
4. VPC grouping remains functional as layout metadata while excluded from topology export.
5. Legacy file import succeeds and re-saves as `WorkspaceFileV2`.
6. Inspector edits preserve type safety and no longer depend on untyped patches.
7. No `snake_case` fields remain in renderer domain state.
8. Folder boundaries and naming rules are enforced by lint/import constraints.

## Consequences
### Positive
1. Shared product vocabulary across engine, renderer, and docs.
2. Strong compile-time guarantees across template, store, adapters, and inspector.
3. Scalable folder boundaries suitable for multi-team development.
4. Lower onboarding cost due to explicit domain naming.

### Tradeoffs
1. Refactor touches many files and import paths.
2. Transitional adapters are required for legacy payloads/files.
3. Initial velocity dip while renaming and boundary rules stabilize.

## Assumptions and Defaults
1. Engine schema (`TopologyJSON`) remains the domain contract source.
2. Full taxonomy expansion is out of scope for this phase.
3. Live validation on every mutation is preferred over save-only validation.
4. Backward compatibility means load old format, save new format.

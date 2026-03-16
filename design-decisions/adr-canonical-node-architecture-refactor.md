# ADR: Canonical Node Architecture Refactor (Engine-First + Discriminated Unions)

## Status
Proposed

## Date
March 16, 2026

## Context
The current renderer and engine modeling layers are not aligned:

1. The renderer stores mutable React Flow `Node[]`/`Edge[]` directly, with permissive `any` updates in node data.
2. The engine expects a strict canonical contract (`TopologyJSON`, `ComponentNode`, `EdgeDefinition`) as defined in `src/engine/types.ts`.
3. Node creation is registry-driven but default payloads are untyped (`Record<string, any>`), which allows drift from declared TypeScript unions.
4. Persistence currently saves a nested React Flow structure instead of canonical topology, making renderer format the source of truth.
5. VPC/AZ/Subnet currently act as visual grouping containers, but their semantics are mixed with component modeling concerns.

This creates schema drift risk, weak compile-time guarantees, and fragile UI-to-engine conversion.

## Decision
Adopt an engine-first canonical node architecture with discriminated unions in the renderer projection layer.

1. Canonical topology state (`TopologyJSON`) becomes the single source of truth for simulation-relevant entities.
2. React Flow nodes/edges become derived view models from canonical state.
3. Renderer node payloads use strict discriminated unions, not untyped bags.
4. VPC/AZ/Subnet remain UI-only containers and are excluded from engine-exported `TopologyJSON.nodes`.
5. Persistence moves to a versioned workspace envelope that contains canonical topology plus UI metadata.
6. Legacy nested React Flow files remain loadable via migration, but all future saves use the new format.

## Public Interfaces and Types
The refactor introduces or formalizes the following interfaces.

1. `WorkspaceFileV2`:
   1. `version: "2.0"`
   2. `topology: TopologyJSON`
   3. `ui: { containers; nodeUiState; layout }`
2. Template contracts:
   1. `ComponentTemplate` for engine-exported nodes
   2. `ContainerTemplate` for UI-only grouping nodes
3. Renderer projection union:
   1. `RenderNodeDataBase`
   2. `ComputeRenderNodeData`
   3. `ServiceRenderNodeData`
   4. `SecurityRenderNodeData`
   5. `ContainerRenderNodeData`
4. Explicit store actions replacing untyped mutation:
   1. `updateComponentNode(id, patch: DeepPartial<ComponentNode>)`
   2. `updateNodeUiState(id, patch: Partial<NodeUiState>)`
   3. `updateContainer(id, patch: Partial<UiContainerNode>)`
5. Render/engine type separation:
   1. React Flow `node.type` remains renderer component key
   2. Canonical component type remains `ComponentType` in canonical state

## Migration Plan
### Phase 1: Types and Registry
1. Replace untyped node defaults in the registry with strict template contracts.
2. Ensure every template has explicit category/type metadata for canonical node creation.
3. Eliminate `Record<string, any>` from palette template definitions.

### Phase 2: Canonical Store
1. Introduce a topology store centered on `Map<string, ComponentNode>` and `Map<string, EdgeDefinition>`.
2. Keep UI-only container and UI-state maps separate from canonical topology.
3. Re-run topology validation on every mutation and persist validation state.

### Phase 3: Adapter Pipeline
1. Update drag-drop to pass template identity only.
2. Create canonical nodes via template factory actions.
3. Derive React Flow nodes from canonical + UI metadata through selectors/adapters.

### Phase 4: Inspector and Component Integration
1. Move inspector updates from generic key/value mutation to typed store actions.
2. Keep existing node visuals but feed them typed `RenderNodeData` unions.
3. Remove runtime assumptions that rely on undeclared keys.

### Phase 5: Persistence and Legacy Compatibility
1. Add `WorkspaceFileV2` export/import path.
2. Detect legacy nested React Flow files and migrate them into canonical topology + UI metadata.
3. Always save as `WorkspaceFileV2` after successful load/migration.

### Phase 6: Cleanup and Hardening
1. Remove stale node config artifacts and deprecated untyped APIs.
2. Add compile-time exhaustiveness checks for template-to-canonical and canonical-to-render mappings.
3. Keep engine schema as the canonical contract boundary.

## Default Mapping Decisions (Current Palette)
These defaults are used during migration and template normalization.

1. `backend-server` -> `microservice` (`compute`)
2. `lambda-function` -> `serverless-function` (`compute`)
3. `async-worker` -> `batch-worker` (`compute`)
4. `cron-job` -> `faas-background` (`compute`)
5. `auth-service` -> `auth-service` (`compute`)
6. `search-service` -> `search-service` (`compute`)
7. `primary-db` -> `relational-db` (`storage-and-data`)
8. `read-replica` -> `relational-db` (`storage-and-data`, with replica role in config)
9. `redis-cache` -> `in-memory-cache` (`storage-and-data`)
10. `nosql-db` -> `nosql-db` (`storage-and-data`)
11. `object-storage` -> `object-storage` (`storage-and-data`)
12. `search-index` -> `search-index` (`storage-and-data`)
13. `load-balancer` -> `load-balancer` (`network-and-edge`)
14. `api-gateway` -> `api-gateway` (`network-and-edge`)
15. `ingress-controller` -> `ingress-controller` (`network-and-edge`)
16. `reverse-proxy` -> `reverse-proxy` (`network-and-edge`)
17. `nat-gateway` -> `nat-gateway` (`network-and-edge`)
18. `vpn-gateway` -> `vpn-gateway` (`network-and-edge`)
19. `cdn` -> `cdn` (`network-and-edge`)
20. `dns` -> `internal-dns` (`dns-and-certs`)
21. `message-queue` -> `queue` (`messaging-and-streaming`)
22. `message-broker` -> `message-broker` (`messaging-and-streaming`)
23. `waf` -> `waf` (`security-and-identity`)
24. `firewall-rule` -> `firewall` (`security-and-identity`)
25. `external-service` -> `third-party-api-connector` (`external-and-integration`)
26. `client-user` -> `api-endpoint` (`compute`, default assumption)
27. `vpc-region`, `availability-zone`, `subnet` -> UI-only containers (not canonical component nodes)

## Validation, Testing, and Acceptance Scenarios
1. Template drop creates correctly typed canonical node/container.
2. Store mutation updates canonical topology and triggers live validation.
3. Adapter emits correct renderer node type and payload union variant.
4. VPC grouping remains functional as layout metadata while excluded from topology export.
5. Legacy file import succeeds and writes back as `WorkspaceFileV2`.
6. Inspector edits preserve type safety and no longer depend on untyped patches.
7. `exportTopology()` remains valid against schema validator.

## Consequences
### Positive
1. Strong compile-time guarantees across palette, store, inspector, and renderer.
2. Clear contract boundary between UI representation and engine input.
3. Safer long-term migration path toward full topology store architecture.

### Tradeoffs
1. Initial refactor touches multiple layers (registry, store, adapters, inspector, persistence).
2. Requires explicit mapping maintenance for palette templates.
3. Needs migration logic for old files until legacy format is retired.

## Assumptions and Defaults
1. Canonical engine schema remains the contract source (`TopologyJSON` in `src/engine/types.ts`).
2. Full taxonomy expansion is out of scope for this step; current palette coverage is retained.
3. Live validation on every mutation is preferred over save-only validation.
4. Backward compatibility means load old format, save new format.

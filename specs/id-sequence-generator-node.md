# ID / Sequence Generator palette node

> Status: implemented in V1.
>
> Purpose: give the "ID Range Allocator / sequence generator" component from the URL
> shortener (and any counter/ticket/Snowflake-style design) a first-class home in the
> palette. Today the only options are `distributed-lock` (wrong semantics — it's a
> lock) or a generic `microservice`, so the component has no honest, self-describing
> node.

## 1. What it is

A small, stateful coordination service that hands out unique, monotonically increasing
identifiers — a global counter (DB sequence), a ZooKeeper sequence, a Snowflake service,
or a pre-allocated ID-range allocator.

## 2. Simulation backing (honest)

It is a **preset over the existing `microservice` component type**, not a new engine
primitive. An ID generator *is* a small compute service, so it simulates as a
`microservice`: queueing (G/G/c/K), resource-derived concurrency, timeouts. No new
`ComponentType`, spec, cost row, or trait is added.

Its **specific feature** is that the service time is not a generic constant — it is
**derived from the allocation model** (`sim.idAllocation` → `processing.distribution`,
`src/engine/catalog/idAllocation.ts`), so the node's defining design decision actually
changes simulated latency and throughput.

Consequence for grading (consistent with §15.1 of the builder spec): it resolves to
`microservice`, so rubric criteria match it as a microservice — the same
label-independence that applies to every node.

## 3. Config — kind + allocation model (the specific feature)

The node carries `sim.idAllocation = { kind, mode, blockSize }`, edited in a dedicated
**ID allocation** properties-panel section. Each choice changes the derived service-time
distribution:

**Kind** (which real generator this models):

| Kind | Simulated coordination model |
|---|---|
| Range allocator (default) | block allocation — off the hot path |
| DB sequence | central-capable (central by default; gap-free is a justify point) |
| ZooKeeper sequence | central-capable, same tradeoff as a DB sequence |
| Snowflake | **decentralized** — IDs generated locally from time + machine id, **no coordination ever** → always fast, never contends (mode is not applicable) |

**Allocation mode** (for the central-capable kinds):

- **Block / range allocation:** a server grabs `blockSize` IDs per coordination
  round-trip, then serves the rest from memory. Modeled as a **mixture**:
  `(blockSize−1)/blockSize` of requests are ~instant local serves
  (`ID_LOCAL_SERVE_MS ≈ 0.05 ms`), `1/blockSize` pay a coordination hit
  (`ID_COORDINATION_MS ≈ 2 ms`). Mean ≈ `coord/blockSize` → off the hot path.
- **Central counter (per request):** every request pays the full coordination cost, so
  the node's throughput ceiling is `concurrency / coord` and its p99 spikes under a
  write burst — the classic bottleneck. (`blockSize ≤ 1` collapses block to this.)

So the "block allocation avoids contention" tradeoff is a **measured** difference in the
node's own latency/throughput, not a justification — flip mode from block to central and
watch the allocator saturate under the write spike.

## 4. Not modeled

- Cross-node call-rate reduction (a downstream store isn't hit less just because the
  allocator batches) — the mixture models the *allocator's own* amortized cost, which is
  the point of interest.
- Exactly-once / gap-free guarantees of the ID space (justification, not simulated).
- Snowflake clock-skew / machine-id exhaustion (justification).

## 6. Source / registration sites

- `src/engine/catalog/idAllocation.ts` — the allocation model + service-time derivation
  (`deriveIdAllocationDistribution`, `idAllocationMeanMs`).
- `src/engine/catalog/nodeSpecTypes.ts` — `sim.idAllocation` field.
- `src/renderer/src/components/properties/IdAllocationSection.tsx` — the config UI.
- `src/engine/catalog/paletteTemplates.ts` — the `id-generator` template (backing
  `microservice`), seeding `idAllocation` + the derived `processing.distribution`.
- `src/renderer/src/config/catalogConfig.ts` — listed under the Compute category.
- `src/renderer/src/config/nodeRegistry.ts` — icon.
- `src/renderer/src/config/themeConfig.ts` — color.
- `src/renderer/src/config/libraryInfo.ts` — tooltip (represents / real-world / config),
  including the two-mode contention guidance.
- Visibility: its `componentType` (`microservice`) is already in the default library
  set, so it shows in the curated ("Common") palette with no extra change.

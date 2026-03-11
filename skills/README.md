# DSDS Skills Index

This directory contains reusable Codex skills for working on the DSDS simulator docs, schema, scenarios, and implementation workflow.

## Quick Use

- Mention a skill by name in your prompt (example: `$topology-json-author`).
- Use the skill when your request matches its scope; each skill has detailed instructions in its `SKILL.md`.

## Recommended Flow

1. `component-taxonomy-selector`
2. `topology-json-author`
3. `scenario-composer` or `chaos-experiment-designer`
4. `simulation-output-analyst`
5. `failure-propagation-analyzer`
6. `resilience-pattern-tuner`
7. `invariant-policy-checker`
8. `cost-and-provider-mapper`
9. `schema-catalog-sync-guard`
10. `ticket-implementation-copilot`
11. `dsds-ui-spec-to-component`

## Skill Catalog

| Skill | Primary Use | Path |
|---|---|---|
| `component-taxonomy-selector` | Map requirements to valid DSDS component types and categories. | `skills/component-taxonomy-selector/SKILL.md` |
| `topology-json-author` | Produce and validate simulator-ready `TopologyJSON`. | `skills/topology-json-author/SKILL.md` |
| `scenario-composer` | Build deterministic workload/fault/invariant scenario bundles. | `skills/scenario-composer/SKILL.md` |
| `chaos-experiment-designer` | Design hypothesis-driven chaos experiments with pass/fail rules. | `skills/chaos-experiment-designer/SKILL.md` |
| `simulation-output-analyst` | Analyze run outputs (metrics, traces, causal graph, breaches). | `skills/simulation-output-analyst/SKILL.md` |
| `failure-propagation-analyzer` | Model and explain cascade paths and blast radius. | `skills/failure-propagation-analyzer/SKILL.md` |
| `resilience-pattern-tuner` | Tune retries, deadlines, breakers, bulkheads, and shedding. | `skills/resilience-pattern-tuner/SKILL.md` |
| `invariant-policy-checker` | Define and evaluate simulation invariants and policy checks. | `skills/invariant-policy-checker/SKILL.md` |
| `cost-and-provider-mapper` | Compare AWS/GCP/Azure mappings and cost/performance tradeoffs. | `skills/cost-and-provider-mapper/SKILL.md` |
| `schema-catalog-sync-guard` | Detect drift between schema types and canonical catalogue CSVs. | `skills/schema-catalog-sync-guard/SKILL.md` |
| `ticket-implementation-copilot` | Execute unblocked tickets AC-first with verification evidence. | `skills/ticket-implementation-copilot/SKILL.md` |
| `dsds-ui-spec-to-component` | Convert UI specs/mocks into frontend implementation tasks. | `skills/dsds-ui-spec-to-component/SKILL.md` |

## Notes

- Every skill includes `agents/openai.yaml` and a focused `references/` guide.
- All skills in this directory passed `quick_validate.py`.

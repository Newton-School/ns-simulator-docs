---
title: "M13 - Environment Profiles & Capabilities"
type: module
duration: 0.5 lecture
tags: [module]
---
## Objectives
Explain the three modes and the capability lens that locks/unlocks edits per question.

## Concepts (atomic notes)
- [[concepts/network/connector-edges-carry-no-physics|Connector edges carry no physics or cost]]
- [[concepts/compute/derive-and-lock-prices-concurrency|Derive-and-lock prices concurrency]]

## Key ideas
- Modes AUTHOR / ASSIGNMENT / PRACTICE; deployed default = PRACTICE + connector.
- Capabilities: editPaletteList, canEditResources, canEditExecutionProfile, edgeModel, budgets, visibility.
- Domain overrides: `network` → editable edges, `cost` → editable resources.

## Teaching vehicle
[[p12-ps5-restock|P12 - PS5 Restock]] - turn `canEditResources` off so students can't
brute-force the hot-key lock and must solve it architecturally.

## Source of truth (specs)
- [[environment-definition-and-configuration-model|environment-definition-and-configuration-model.md]] · [[system-design-leetcode-environment-model|system-design-leetcode-environment-model.md]]

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m12-grading-dsl|M12]] · Next [[m14-frontend|M14]]

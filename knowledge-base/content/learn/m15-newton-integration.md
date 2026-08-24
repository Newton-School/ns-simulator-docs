---
title: "M15 - Newton Integration & Authoring Workflow"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Convert a `question.json` into Newton Django rows and run the author's validation loop.

## Key ideas
- Two shapes: standalone `question.json` vs Django rows (SIMULATOR_CONFIG + STRUCTURAL_RULE/SEMANTIC_CRITERION/RUBRIC_CHECK).
- Bridge: `newtonGamePlayground.ts` (`parseNewtonSeed`, `buildQuestionPackageFromRows`), `environmentProfile` passthrough.
- Loop: author → validate (`parseQuestionPackage` + `validateAuthoredQuestion`) → dual-topology grade → ship rows.

## Teaching vehicle
General - package the url-shortener JSON artifacts into the 5 Django rows.

## Source of truth (specs)
- [[evaluation-authoring-reference-manual|evaluation-authoring-reference-manual.md]] §11 · [[newton-api-backend-integration|newton-api-backend-integration.md]]

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m14-frontend|M14]] · Next [[capstone|Capstone]]

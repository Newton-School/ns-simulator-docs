# Question Studio MVP — Small Checkpoints

**Status:** Active

**Rule:** every checkpoint must be independently testable, reviewable, and
revertible. Do not begin the next checkpoint while the current checkpoint's
automated acceptance test is red.

## Milestone 0 — Authoring Contract Foundation

This milestone is useful even if no UI ships.

| Checkpoint | Small deliverable                                          | How to test                                                     | Status |
| ---------- | ---------------------------------------------------------- | --------------------------------------------------------------- | ------ |
| 0.1        | Read-only canonical-bank coverage audit                    | `npm run audit:question-authoring`; focused Vitest suite        | Built  |
| 0.2        | Typed `SIMULATOR_CONFIG` row and package → config compiler | Unit test one minimal package                                   | Built  |
| 0.3        | Structural-rule row export                                 | One test per supported structural kind                          | Built  |
| 0.4        | Semantic-criterion row export                              | One test per supported semantic kind                            | Built  |
| 0.5        | Rubric-check row export and deterministic ordering         | Golden row-order test                                           | Built  |
| 0.6        | Shared rows → package parser extracted from Newton runtime | Existing Newton adapter tests + focused parser tests            | Built  |
| 0.7        | Package → rows → normalized package for all 14 questions   | Canonical-bank golden test                                      | Built  |
| 0.8        | Reference/gamed grading parity after round-trip            | Canonical reference/gamed contract parity test                  | Built  |
| 0.9        | Engine-owned authoring capability registry v1              | Exhaustiveness test for kinds, metrics, components, and support | Built  |

### Milestone 0 demo

Run one command and receive an honest report showing:

- supported package shapes
- source-only fields
- row round-trip status
- grading-parity status
- exact blockers per canonical question

## Milestone 1 — Smallest Usable No-JSON Editor

This milestone deliberately excludes canvas-based proof. It proves that the form,
compiler, and exports fit together.

| Checkpoint | Small deliverable                                            | How to test                                      | Status |
| ---------- | ------------------------------------------------------------ | ------------------------------------------------ | ------ |
| 1.1        | Feature-gated `/question-studio` shell with seven-stage rail | Render test; normal simulator route unchanged    | Built  |
| 1.2        | Question title and derived stable ID                         | Pure derivation test + component test            | Built  |
| 1.3        | Save/open `.dsds-question-project.json`                      | File-service round-trip test                     | Built  |
| 1.4        | Problem statement editor with learner preview                | Escaping and preview component tests             | Built  |
| 1.5        | Add, edit, reorder, and remove FR cards                      | Keyboard and state-reducer tests                 | Built  |
| 1.6        | Add one typed NFR card                                       | Unit/operator conversion tests                   | Built  |
| 1.7        | Add one deterministic scenario card                          | Scenario schema and workload normalization tests | Built  |
| 1.8        | Add “exactly one source” sentence-style test                 | Compiler test for `requires_single_source`       | Built  |
| 1.9        | Add one metric sentence-style test                           | Compiler test for p99/error/throughput selector  | Built  |
| 1.10       | Live read-only generated package/row preview                 | Snapshot and invalid-draft tests                 | Built  |
| 1.11       | Copy/download Django artifacts                               | Export bundle round-trip test                    | Built  |

### Milestone 1 demo

An author creates a small question without typing JSON:

```text
Title → brief → one scenario → one structural check → one metric check → export
```

The output loads through the same Newton parser used in production.

## Milestone 2 — Visual Topology and Proof MVP

This milestone completes the “proof, not plausibility” promise.

**Next:** checkpoint 2.2 — add the reference-design canvas tab and preserve snapshots while switching.

| Checkpoint | Small deliverable                                          | How to test                                 | Status |
| ---------- | ---------------------------------------------------------- | ------------------------------------------- | ------ |
| 2.1        | Scaffold canvas tab stores one topology snapshot           | Canvas serialize/load test                  | Built  |
| 2.2        | Reference-design tab                                       | Snapshot switching test                     |        |
| 2.3        | One gamed-design tab with misconception and expected check | Authoring-project schema test               |        |
| 2.4        | Verification preflight computes design × case run plan     | Discrete/analytic routing tests             |        |
| 2.5        | Run and display reference result                           | Worker success/error/cancel tests           |        |
| 2.6        | Run and display gamed result                               | Intended-discriminator matching test        |        |
| 2.7        | Stale-proof invalidation                                   | Hash/version mutation tests                 |        |
| 2.8        | Publish-readiness gate                                     | End-to-end reference-pass + gamed-fail test |        |

### Milestone 2 demo

The author visually builds a reference and a plausible wrong design, runs both, and
cannot export a publish-ready question until the intended check rejects the wrong
design.

## Milestone 3 — MVP Coverage Expansion

Add one primitive at a time, each driven by the coverage audit:

1. `requires_component`
2. `requires_path`
3. `storageFit`
4. `guardedPath`
5. `placement`
6. `fanout`
7. `forbidUnjustified`
8. `stateTransition`
9. multi-scenario editing
10. fault timeline

Each addition requires:

- an engine registry entry
- compile and decompile tests
- sentence-editor component test
- import/export golden fixture
- evidence-mode declaration

## Checkpoint completion template

For every checkpoint, report:

1. behavior added
2. exact files changed
3. acceptance checks passed
4. manual action the user can try
5. known limitation intentionally left for the next checkpoint

---
title: "Reference Specs (source of truth)"
tags: [reference]
---
> The **107 canonical specs are now wired into this vault** at `reference/specs/` (a
> symlink to `../../specs/`), and the ADRs at `decisions/adrs/`. They are searchable and
> linkable by filename - but remain the *source of truth*; the learning
> layer points *into* them, never duplicates them.

Link a spec from any note by its basename, e.g.
`[[queue-depth-calculation]]`, `[[resource-allocation-and-derived-concurrency]]`,
`[[evaluation-authoring-reference-manual]]`.

Key specs by area:
- **Engine:** [[queue-depth-calculation]] · [[throughput-calculation]] · [[arrival-departure-and-request-lifecycle-semantics]]
- **Sizing:** [[resource-allocation-and-derived-concurrency]] · [[execution-profile-and-node-concurrency]]
- **Edges/traits:** [[edge-properties-and-defaults]] · [[trait-integration-guide]]
- **Cost:** [[cost-calculation-and-budgeting]]
- **Grading:** [[evaluation-authoring-reference-manual]] · [[question-grading-model-and-anti-gaming]] · [[test-case-catalog]]
- **Authoring (start here):** [[test-case-authoring-handbook]] - ground-up teaching handbook for writing questions
- **Runtime / V2 semantics:** [[runtime-semantic-criteria]] · [[support-ledger-and-runtime-semantics]] · [[replication-quorum-state-machine-walkthrough]] · [[rate-limiter-admission-and-breach-model]] · [[llm-backed-justification-grading]]
- **Why it works:** [[why-this-works-math-tricks-and-skeptics-faq]]

Full annotated index: [[curriculum|CURRICULUM.md]].

# Examples

Worked examples for building and grading system-design questions in the simulator.

There are two kinds of asset here:

- **Design walkthroughs** — step-by-step runbooks that build a canonical interview design
  on the canvas (place nodes → configure → wire edges → run → verify), plus the complete
  set of gradeable test-case rows for that design.
- **[Canonical question bank](question-bank/README.md)** — executable authoring packs
  (`question.json` + reference/gamed topologies) validated by
  `npm run validate:question-bank`.

## The four canonical designs (from `system-design-prep.pdf`)

Each design has a **builder walkthrough** (how to build it) and a **test-cases** file
(every atomic gradeable row, per `specs/test-case-catalog.md`).

| Design | Defining trait | Walkthrough | Test cases |
|---|---|---|---|
| **URL Shortener** | Extreme read-heavy over immutable data; cache-aside + type-aware routing | [builder-walkthrough](url-shortener/builder-walkthrough.md) | [test-cases](url-shortener/test-cases.md) |
| **Chat Application** | Stateful persistent connections; persist-before-ACK; fan-out delivery | [builder-walkthrough](chat/builder-walkthrough.md) | [test-cases](chat/test-cases.md) |
| **Instagram / News Feed** | The fan-out problem; hybrid push/pull; feed cache + CDN | [builder-walkthrough](news-feed/builder-walkthrough.md) | [test-cases](news-feed/test-cases.md) |
| **Google Docs** | Concurrent-edit correctness; per-doc session owner; op-log + failover | [builder-walkthrough](google-docs/builder-walkthrough.md) | [test-cases](google-docs/test-cases.md) |

The URL Shortener folder additionally carries the full authoring pack (`question.json`,
`reference-topology.json`, `gamed-topology.json`) — see its [README](url-shortener/README.md).

## Question Studio walkthrough

- **QuickCart Flash Sale** — [author the complete question in Question Studio](quickcart-flash-sale/question-studio-walkthrough.md), including the blank-canvas contract, 1,000,000 req/s scenario, 80% headroom invariant, grading rules, preview, and Django export.

## How the two files per design fit together

- The **walkthrough** ends in a *"gradeable decisions (measured)"* vs *"still justification
  (not simulated)"* split — grounded in the engine's support ledger
  (`src/engine/analysis/supportLedger.ts`), not guesses.
- The **test cases** turn each *measured* decision into atomic rows across the four row
  types (`SIMULATOR_CONFIG` · `STRUCTURAL_RULE` · `SEMANTIC_CRITERION` · `RUBRIC_CHECK`),
  and leave the *justification* decisions to the question's `justify` prompt (no row).

> **Grading is by resolved `componentType`, edges, and runtime evidence — never by label
> or builder contract.** A Service-Builder node grades as its backing type (e.g. a
> "Redirect Service" is a `microservice`; a "Connection Server" is an `api-gateway`). The
> walkthroughs and test-case files call out each design's specific matching traps.

## Reusable patterns

Cross-cutting recipes that recur across designs — build them from generic palette nodes:

- [**Notifications, generically**](patterns/notifications.md) — push / email / SMS as a
  composition of *async decoupling (Queue/Stream) → external provider call (External Service /
  Notification Service) → device fan-out (`fanoutFactor`)*, with or without a dedicated
  notification node. Used by Chat (offline push); reusable for News Feed, etc.

## Related references

- Test-case vocabulary and every row/kind/metric: [`specs/test-case-catalog.md`](../specs/test-case-catalog.md)
- Authoring handbook: [`specs/test-case-authoring-handbook.md`](../specs/test-case-authoring-handbook.md)
- Coverage map / honest gap register for these four designs: [`specs/system-design-coverage-gaps.md`](../specs/system-design-coverage-gaps.md)

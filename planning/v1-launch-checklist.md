# V1 Launch Checklist (priority-ordered)

> Scope: ship a **workable V1** - 9 questions, a clean node palette of working
> components, hidden justification, cohesive UI, nothing broken. **Everything trait /
> node-modeling related is V2** (see `node-capability-matrix.md` +
> `trait-integration-guide.md`). This list is only V1.
>
> `[x]` = done this cycle · `[ ]` = open · `[~]` = needs a verification pass.

---

## P0 - Shipping blockers (must be right or students hit them immediately)

- [x] **Palette shows only working nodes.** `V1_PALETTE_NODE_TYPES` allowlist in
  `LibrarySidebar.tsx` (13 componentTypes, resolved via `PALETTE_TEMPLATES[id].componentType`).
  Empty-library regression (matching `item.type`=rendererType) fixed.
- [x] **Load Balancer available + labelled.** Added `load-balancer` to the Network
  catalog; relabelled "Load Balancer (Legacy)" → "Load Balancer". All 9 questions buildable.
- [x] **Justification hidden for V1.** UI inputs/logic hidden; `justify` stored as
  `_justify` (not graded) in question files.
- [x] **9 questions validate** (reference PASSES, gamed FAILS on intended axis) via
  `scripts/validate-question-dir.ts`. 3 questions requiring un-modeled nodes deferred
  to `deferred-v2/` (payment-system, ticketmaster, rate-limiter).
- [x] **LB/source model consistent.** Reference/gamed topologies use a **`client`**
  (api-endpoint) source; the Workload Source picker only offers `structuralRole:'source'`
  nodes (`isSourceComponentData`), so an LB can't be picked as a source.
- [x] **PRs merged into `stable-v1`** (#221 toolbar, #224 undo/redo, #227 readable
  errors) + test-copy fixup; full suite green (506 pass).
- [~] **End-to-end UI QA of the 9 questions.** Validated via CLI/harness; still do a
  **by-hand pass in the running app**: load each question, build the reference on the
  canvas → Test passes; build an obviously-gamed design → fails on the intended check.
  This is the main remaining confidence gate.
- [~] **Structural error messages readable.** #227 landed the copy
  (`validationCopy.ts`). Spot-check the common student mistakes surface a clear message:
  Client→DB directly, no source, conditional edge without a condition, disconnected node.
- [~] **Reset Canvas works flawlessly.** Wired (`FlowCanvas.resetCanvas` →
  toolbar `onResetCanvas`). Confirm it clears nodes/edges/metrics and does **not** break
  question mode (question stays loaded; attempt state sane).
- [ ] **Commit & push `stable-v1`.** All V1 work is uncommitted (main repo + docs
  submodule + questions repo). Owner: you (git handled by user).

## P1 - Polish & correctness (done this cycle unless noted)

- [x] **Em-dashes → hyphens** across `src/renderer/src` (re-swept after the merge).
- [x] **Test-row truncation + hover tooltip** (single line + `title`, centered rows).
- [x] **Dark-mode border fix.** `--nss-border-rgb` channels + `rgb(var(... ) / <alpha>)`
  token, so `nss-border/NN` opacities render instead of falling back to white.
- [x] **Budget dropped for V1.** Graded `budget` removed from `async-sla` /
  `sensor-store` (it was non-binding - reference used ~5% of cap, and gamed was cheaper
  than reference). `BudgetMeter` auto-hides (renders only when a question has a budget).
  Engine budget code stays dormant. V2 redesign fully planned in
  `budget-feature-review.md` + `budget-v2-design.md` (cap-last calibration, per-type
  cost model, non-binding-budget validator guard).
- [x] **Open topology + question at once in AUTHOR/standalone mode** (test question and
  solution side by side; gated so real assignments stay locked).
- [~] **Guides reflect final V1.** `guides/student-guide.md` + `guides/teacher-manual.md`
  exist - re-read to confirm they match the shipped V1: 9 questions, hidden justification,
  the 13-node palette, and the deferred set.

## P2 - Launch collateral

- [ ] **One-page "V1 scope" for the team.** A short in/out summary (9 questions, node
  palette, hidden justification, generic-node physics) distinct from the full V2 roadmap
  matrix. Can be a trimmed intro section pointing at `node-capability-matrix.md`.
- [x] **V2 roadmap docs authored** (`node-capability-matrix.md`,
  `trait-integration-guide.md`) - reference, not V1 work.

---

## Explicitly deferred to V2 (do NOT do for V1)

- **All trait / node-physics work.** Priority order when V2 starts:
  1. `➕` extend existing traits' `appliesTo` (no new code).
  2. `storageProfile` (stores are physically identical today).
  3. `broadcastFanout` (`message-broker` doesn't actually broadcast).
  4. Failure-mode set: `connectionPool`, `gcJitter`, `cacheStampede`, `dataSkew`, `replicationCost`.
  5. Coordination set: `lockLease`, `idempotencyDedup`, wire `rate-limiter`→`rateLimiter`,
     `circuit-breaker-controller`→`circuitBreaker`.
- **Un-defer the 3 questions** (`payment-system`, `ticketmaster`, `rate-limiter`) -
  blocked on the coordination traits + un-hiding their palette nodes.
- **Wire `healthProber`** into `health-check-manager`; wire the fault system into
  `chaos-engineering-framework`.
- **Richer request model** (endpoint/body/status codes) and on-source-node workload UI.
- **Justification UX redesign** (LLM-graded, not rigid regex) - the reason it's hidden in V1.

---

## Definition of done for V1

1. All P0 boxes checked (incl. the three `[~]` verification passes).
2. Full test suite green + web/node typecheck clean.
3. `stable-v1` committed and pushed.
4. Guides match the shipped feature set.

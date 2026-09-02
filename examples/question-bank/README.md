# Canonical Question Bank

These directories are the repo-local canonical authoring packs. Each contains a
question, a passing reference topology, a plausible gamed topology, and an
explanation of what the pair discriminates.

Start with [Fresh Author Start Here](../../guides/fresh-author-start-here.md).

Current packs cover cache placement, async decoupling, messaging fanout,
stream lifecycle semantics, replicated-log quorum writes, protocol/session
semantics, modeled external reconciliation, storage-fit, workload routing,
correctness/concurrency, and cargo-cult component selection. They are
executable assets: run `npm run
validate:question-bank` from the product repository before relying on any pack
as an example or template.

The support ledger, not this directory name, determines whether a concept is
first-class, guided, structural-only, or deferred.

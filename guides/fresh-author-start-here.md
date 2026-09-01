# Fresh Author Start Here

This checkout contains the complete portable authoring path. Do not use a
personal notes directory or another repository as an authoring dependency.

1. Choose the closest trio in `examples/question-bank/`.
2. Copy its directory, including `question.json`, `reference-topology.json`,
   `gamed-topology.json`, and its README.
3. State which requirements are simulated, structurally inferred, and deferred.
   Use `specs/support-ledger-and-runtime-semantics.md` for the current boundary.
4. Make the reference topology pass and the gamed topology fail for the intended
   reason:

```bash
npm run validate:question-bank
```

For an individual question while iterating:

```bash
npx tsx scripts/validate-question-dir.ts \
  ns-simulator-docs/examples/question-bank/<question-id>
```

The validator runs schema and authoring checks, then grades both topologies. A
question is ready only when its reference passes every checkable requirement and
its gamed topology fails at least one intended check.

`requirements-first` and locked-lab contracts are available in the schema and
validator, but their product UI remains deliberately disabled. Author them only
when the package itself declares its fixed topology, permitted edits, expected
observations, and pass/fail checks.

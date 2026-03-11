# Drift Check Rules

## What to compare
- Component taxonomy values
- Event type names
- Failure mode names
- Invariant and policy categories
- Built-in scenario names

## Drift classes
- Missing in schema
- Missing in catalogue
- Name mismatch
- Behavior mismatch (same name, different semantics)

## Prioritization
- Critical: breaks parsing, validation, or simulation semantics.
- High: causes incorrect feature coverage.
- Medium: causes confusion but not execution failure.
- Low: wording or documentation mismatch.

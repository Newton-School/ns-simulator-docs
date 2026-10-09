# Builder Policy - A Guide for Question Authors

Learners can make their own components with the **Service builder** and the **Custom Node
builder**. A created node is graded by the component type it is built on, so the usual
`allowedNodeTypes` / `forbiddenNodeTypes` checks cannot tell "a microservice from the
palette" from "a microservice built in the Service builder". A **builder policy** gives you
that control per question: whether the builders are available, what they may create, how
many definitions a learner may make, and whether definitions lock once the attempt has run.

The reference is `specs/custom-node-and-service-definition-spec.md` §15 and §15.1. This guide
is the practical version.

---

## Where to set it

In **Question Studio**, stage **Start**, under the learner starting state and the question
constraints: the **Builder policy** editor. The policy is saved in the question project file
and carried through the compiled question package (`QuestionPackage.builderPolicy`), the export
bundle and the Django `SIMULATOR_CONFIG` row, so what you set is what the platform enforces.

## The fields

Every field is optional. **No policy, or an absent field, means today's open behaviour**: both
builders on, every runtime, class and trait pack allowed, no cap, no lock. Existing questions
grade exactly as before.

| Field | Effect |
|---|---|
| `allowServiceBuilder` | Service builder on or off (default on). |
| `allowMyServices` | Re-placing saved service definitions from My Services; also needs the Service builder. |
| `allowCustomNodeBuilder` | Custom Node builder on or off (default on). |
| `allowedNodeClasses` | Node classes a created definition may have (`compute`, `storage`, `network`, `messaging`, `external`, `security`, `observability`, `coordination`, `auxiliary`). Omit for all. |
| `allowedRuntimeTemplates` | Runtimes a created definition may use (for example `long-running-service`, `serverless-function`, `background-worker`, `relational-datastore`, `distributed-cache`, `message-queue`, `event-stream`, ...). Omit for all. |
| `allowedTraitPacks` | Trait packs a definition may enable (`capacity`, `workload-profile`, `serverless-lifecycle`, `retry-timeout`, `rate-limiting`, `external-dependency`, `cache`, `arrival`). Omit for all. |
| `maxDefinitions` | Most created definitions on the canvas. Each placement counts, because each placement forks its own copy. |
| `maxOperationsPerService` | Most operations one created service may declare. |
| `lockDefinitionsAfterFirstRun` | Definitions (and their trait-backed settings) become read-only once the attempt has a graded test run, or a simulation has started for the question in this session. |

`allowMyNodes` and `requireContracts` from the spec are **not implemented** (there is no My
Nodes library, and contracts are documentation only). The schema is strict, so writing either is
a validation error rather than a silent no-op.

Example: "services are allowed, but only long-running ones, at most two, and they lock after
the first run":

```json
"builderPolicy": {
  "allowServiceBuilder": true,
  "allowMyServices": false,
  "allowCustomNodeBuilder": false,
  "allowedRuntimeTemplates": ["long-running-service"],
  "maxDefinitions": 2,
  "lockDefinitionsAfterFirstRun": true
}
```

## What the learner sees

- Builder tiles in the palette are disabled, with the reason shown.
- The builders offer only the allowed runtimes and classes, and lock disallowed trait packs.
- `maxDefinitions` and `maxOperationsPerService` are enforced in the builders, My Services,
  paste and every other way of adding a node. The contextual "Add connected..." picker never
  offers the builders.
- Trait-backed fields of a disallowed trait pack are read-only on created nodes, in the
  properties panel and in the in-app terminal's config mode.
- A design that breaks the policy (loaded, imported or pasted) is **kept as it is**. The
  import dialog, the question panel and the run warnings list each finding with its fix, for
  example "made with the Custom Node builder, which this question does not allow. Fix: delete it
  and use a palette component".
- A policy violation **never blocks a run**. It fails grading instead.

Nodes that come from your scaffold are yours and are exempt.

## How it is graded

A restrictive policy adds **one constraint row**, `builder-policy` ("Follow the question's
builder policy (...)"), beside the existing checks; it never replaces them. Every other
criterion still matches on component type, so a created node is graded exactly like a palette
node of the same type. No policy means no row.

## Checks the authoring validator runs

The validator warns when your settings cancel each other out:

- a builder is allowed but no runtime is left for it;
- an allowed runtime's class is excluded by `allowedNodeClasses`;
- `maxDefinitions: 0` while a builder is on;
- an `allowedNodeTypes` allow-list that hides the builder tiles anyway.

## Known limits

- A definition is any node carrying a `customDefinition`; there is no separate library count.
- The lock counter is not persisted: after a page reload, only a recorded test run or grade
  keeps the lock on.
- The lock also covers matching panel and terminal settings for trait packs the runtime offers.

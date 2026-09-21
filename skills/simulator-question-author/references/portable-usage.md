# Portable Usage for Any LLM

This skill is a Markdown protocol. Automatic skill discovery is optional. Any LLM
that can read the files can use it.

## 1. Share through Git

Commit and share the complete directory:

```text
skills/simulator-question-author/
├── SKILL.md
├── agents/openai.yaml                 # optional metadata
├── assets/
│   ├── builder-walkthrough.template.md
│   └── question-studio-walkthrough.template.md
└── references/
```

The core workflow must not depend on `agents/openai.yaml` or an installed plugin.

## 2. Invocation when the LLM can read the repository

Use a prompt like:

```text
Read skills/simulator-question-author/SKILL.md and follow it as the controlling
workflow. Use its linked references and templates. Here is the system-design
question: <paste question>. Create exactly builder-walkthrough.md and
question-studio-walkthrough.md under <target directory>. Inspect the current
simulator source before asserting support or UI labels.
```

## 3. Invocation when uploading files to a chat

Upload or paste:

1. `SKILL.md`;
2. the five references it marks for the core workflow;
3. both templates;
4. the source question;
5. current simulator source/docs if implementation validation is expected.

Then ask the LLM to return two separately labeled Markdown artifacts. Save each
artifact with its required filename.

## 4. Minimum offline context

If the full repository cannot be shared, provide:

- the complete skill folder;
- current component label/type catalog;
- current support ledger;
- current structural/semantic/rubric capability lists;
- current Question Studio stage/control list.

Without current source, the LLM may draft the guides but must label component,
metric, and UI details as requiring repo validation.

## 5. Expected response contract

The LLM should:

- create only the two requested files by default;
- state the feasibility decision and assumptions;
- report validation actually performed;
- distinguish compile/schema validation from behavioral simulation validation;
- not claim it installed or registered the skill in a product unless that product
  actually supports the operation.

## 6. Portability limits

Different LLM products use different “skill,” “project,” or “custom instruction”
formats. This directory guarantees content portability, not automatic
installation everywhere. `SKILL.md` remains the canonical entrypoint; adapt only
the optional discovery metadata for a particular product.

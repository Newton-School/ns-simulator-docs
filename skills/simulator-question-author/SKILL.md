---
name: simulator-question-author
description: Translate interview-style or prep-style system design prompts into DSDS simulator assignments. Use when converting a written system design question into one or more simulator parts, deciding what the engine can honestly grade, writing `question_text` HTML, and emitting `SIMULATOR_CONFIG`, `STRUCTURAL_RULE`, `SEMANTIC_CRITERION`, and `RUBRIC_CHECK` rows in `django-admin-assignment.md` format.
---

# Simulator Question Author

## Overview

Turn a human-style system design prompt into a bounded, gradeable DSDS assignment. Produce the thinking layer first, then emit the final Django authoring rows in the exact simulator-facing shape.

## Workflow

1. Capture the source question
- Copy the raw prompt, source URL or author, explicit scale, and interviewer hints.
- State missing assumptions explicitly instead of burying them inside the output.

2. Extract atomic statements
- Break the prompt into single-idea statements.
- Classify each statement as `Structural`, `Semantic`, `Simulation`, `Justification`, `Narrative`, or `Split Trigger`.
- Drop, defer, or downgrade anything the simulator cannot grade honestly.

3. Decide whether to split
- Keep one assignment part when there is one dominant lesson, one dominant path, and one dominant bottleneck.
- Split when the prompt mixes independent lessons such as hot-path serving, analytics, abuse prevention, policy, or background pipelines.
- Name each part by the lesson it teaches, not by the original giant prompt.

4. Define the grading contract
- Choose `questionType`, `difficulty`, `domains`, `concepts`, and `workloadCategory`.
- Decide whether the lesson uses `connector` edges or `network` edges.
- Map every kept requirement into exactly one grading surface:
- topology shape -> `STRUCTURAL_RULE`
- architectural meaning -> `SEMANTIC_CRITERION`
- measurable runtime target -> `RUBRIC_CHECK`
- explanation-only expectation -> prompt prose or justification note

5. Compress display scale into tractable scale
- Keep real-world numbers in the prompt.
- Keep the simulated load small enough for deterministic browser execution unless the assignment explicitly teaches higher-scale saturation behavior.
- Preserve the dominant traffic ratio, stressed path, and expected failure mode.

6. Write the student-facing prompt
- Emit raw HTML for `question_text`.
- Include scenario, required path, target, traffic character, scale, and any modeling disclaimer.
- Tell the student what the engine is not modeling when that prevents false expectations.

7. Emit the Django rows
- Always produce `SIMULATOR_CONFIG` first.
- Follow with `STRUCTURAL_RULE`, `SEMANTIC_CRITERION`, and `RUBRIC_CHECK` rows in authored order.
- Keep `initial_game_state` as `{}` for Newton assignment mode.
- Keep every row `hidden = false`, `output = ""`, and `output_file` empty unless the host workflow explicitly says otherwise.

8. Validate the authored solution space
- Prove one intended good design passes.
- Prove one plausible gamed design fails on the intended axis.
- If multiple solution families should pass, author common gates plus family-specific acceptance logic instead of exact-matching one reference graph.

## Guardrails

- Do not promise grading for concerns the engine does not model.
- Do not encode correctness properties such as exactly-once or strict consistency as fake latency checks.
- Default to `connector` edges unless network physics are part of the lesson.
- Do not paste a full `question.json` into `initial_game_state`.
- Do not require one exact topology when several equivalent topologies should pass.
- Do not leave an important requirement as vague prose if it should actually be structural, semantic, or measurable.

## Output format

Return this order unless the user asks for another format:

1. `Translation worksheet`
2. `Part-by-part assignment design`
3. `question_text` HTML per part
4. `django-admin-assignment.md` rows per part
5. `Validation notes`

## References

- Read `references/question-translation-playbook.md` for split heuristics, bucket definitions, scale compression, workload mapping, and multiple-solution handling.
- Read `references/django-assignment-template.md` for the exact `django-admin-assignment.md` skeleton and a worked mini-example.
- Pair with `component-taxonomy-selector` when component-type choice is ambiguous.
- Pair with `topology-json-author` when the author also needs a reference topology or gamed topology artifact.
- If this repo is available, treat these deeper docs as source material:
- `../../specs/interview-question-to-django-assignment-translation.md`
- `../../specs/interview-question-translation-worksheet-template.md`
- `../../specs/interview-question-translation-reference-pack.md`
- `../../specs/multiple-valid-solutions-grading.md`

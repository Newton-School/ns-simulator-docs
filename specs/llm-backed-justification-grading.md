# LLM-Backed Justification Grading

Date: 2026-09-01

## 1. Why this exists

Justifications are free text. Students explain *why* they placed a component
("I put Redis in front of Postgres because 200K reads/sec would melt the DB").
The deterministic grader in `src/engine/analysis/justification.ts` scores these
by keyword and token matching: it looks for graph-consistency signals, a cited
scale number, and tradeoff vocabulary.

Keyword matching is brittle. It misses paraphrasing ("what we give up" instead
of the literal word "tradeoff"), synonyms, abbreviations (`200K` vs `200,000`),
and natural phrasing that a human grader would clearly accept.

This layer adds a **semantic** grader backed by a large language model that
evaluates the same three criteria with language understanding, while keeping the
deterministic grader as a guaranteed fallback so a student is never blocked by a
network failure or a missing key.

## 2. Provider-agnostic by design

The grader is **not tied to one vendor**. It supports:

| Provider id | Back-end | Default model |
| --- | --- | --- |
| `gemini` | Google Gemini (`generateContent`) | `gemini-3.6-flash` |
| `anthropic` | Anthropic Claude (Messages API) | `claude-sonnet-5` |
| `openai` | OpenAI (Chat Completions, JSON mode) | `gpt-4o-mini` |

The prompt and the structured JSON response contract are **identical** across
providers. Each provider is a thin adapter that only knows how to call its API
and pull the model's text out of the response envelope; the shared core builds
the prompt, parses the JSON, and maps it into the engine's result type.

Adding a provider is one entry in the `PROVIDERS` registry — the IPC handler,
renderer, prompt, and result mapping are untouched.

## 3. Architecture

```
Renderer  →  IPC (llm:gradeJustification)  →  Main process  →  <selected provider> API
```

- The renderer builds an `LlmGradeRequest` and invokes the IPC channel.
- The **main process** resolves the provider + key and makes the outbound HTTPS
  call.
- The renderer **never sees the key** and never knows which provider ran.
- Any failure — no provider configured, network error, non-2xx, unparseable
  body — returns an `{ error }` object. The caller falls back to the
  deterministic grader.

### 3.1 Privacy / secret boundary

Keys live only in the main process (`src/main/index.ts`, via
`resolveProviderConfig(process.env)`). They are never forwarded to the renderer,
never logged, and never serialized into a grading result. Only the student
answer, decision text, the actual placed component type, and the question's
scale numbers cross the IPC boundary outward.

## 4. Configuration

Selection happens at app-ready from the environment:

| Variable | Purpose |
| --- | --- |
| `LLM_GRADER_PROVIDER` (alias `LLM_PROVIDER`) | Force a provider: `gemini` / `google`, `anthropic` / `claude`, `openai` / `chatgpt` / `gpt`. |
| `LLM_GRADER_MODEL` (alias `LLM_MODEL`) | Override the model id for the chosen provider. |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | Gemini key. |
| `ANTHROPIC_API_KEY` / `CLAUDE_API_KEY` | Claude key. |
| `OPENAI_API_KEY` | OpenAI key. |

**Resolution order** (`resolveProviderConfig`):

1. If `LLM_GRADER_PROVIDER` names a provider, use it and read its key from that
   provider's env keys. If that key is missing → no LLM grading (fallback).
2. Otherwise auto-detect: the first provider in order `gemini → anthropic →
   openai` that has any key set wins.

If nothing resolves, the renderer silently falls back to deterministic grading.
Switching from Gemini to your Claude key is therefore a **config change**
(`LLM_GRADER_PROVIDER=claude` + `ANTHROPIC_API_KEY=…`), not a code change.

## 5. The grading contract

### 5.1 Request (`LlmGradeRequest`)

| Field | Meaning |
| --- | --- |
| `prompt` | The `JustifyPrompt` (decision text, `boundTo`, `requires`, etc.). |
| `studentAnswer` | The student's free-text answer. |
| `actualComponentType` | The component type the student actually placed; `undefined` ⇒ the bound component is absent. |
| `scaleNumbers` | Scale numbers from the question, used for number-citation evaluation. |

### 5.2 Response (`LlmGradeResponse`)

Every provider is called at `temperature: 0.1` for reproducibility and must
return exactly:

```json
{
  "outcome": "passed" | "partial" | "failed",
  "graphConsistent": true,
  "numberCitation": true,
  "tradeoffMentioned": true,
  "feedback": "1-2 sentence constructive note",
  "confidence": 0.0
}
```

`parseLlmGradeResponse` validates the `outcome` field and tolerates accidental
markdown fencing (```` ```json ````) that some models emit. `mapLlmResponseToResult`
folds the response into the engine's existing `JustificationResult`
(`checks.graphConsistent`, `checks.number`, `checks.tradeoff`, `detail`), so the
UI and downstream grading consume it **unchanged** — deterministic and LLM paths
are interchangeable.

## 6. Grading criteria (identical to the deterministic grader)

1. **Graph consistency — the anti-stuffing gate.** The answer must reference the
   component the student *actually placed*. If the bound component is missing,
   this criterion MUST fail regardless of answer content. This stops a student
   pasting a beautiful essay about a component they never put on the canvas.
2. **Number citation.** The answer should cite a relevant scale number.
   Reasonable rounding and abbreviation are accepted (`200K` = `200,000`).
3. **Tradeoff awareness.** The answer should acknowledge what is sacrificed.
   Synonyms and paraphrasing count — the literal token "tradeoff" is not
   required.

### 6.1 Scoring rules given to the model

- `passed` = graph-consistent **and** at least one of (number, tradeoff), or all
  three.
- `partial` = graph-consistent but **neither** number **nor** tradeoff.
- `failed` = not graph-consistent, or empty/nonsensical/irrelevant answer. A
  blank answer is always `failed`.

## 7. Live grading in the renderer

`QuestionPanel` grades justifications as the student types:

- Deterministic grades render immediately.
- After a 1.5s debounce, answers longer than 10 characters are sent to the LLM
  via IPC; the result replaces the deterministic grade.
- Answers ≤10 chars, IPC unavailability, or any error keep the deterministic
  grade. Grading availability never depends on network reachability or a key.

## 8. What this does not do

- It does not replace the deterministic grader; it sits alongside it as an
  enhancement and a fallback.
- It does not award points per prompt — `pointsEarned`/`pointsPossible` are `0`
  in the mapped result; the batch grader allocates points.
- It does not persist or cache responses; each grade is a fresh call.
- It is not a general-purpose free-text grader — it evaluates exactly the three
  justification criteria above.

## 9. Code map

- Provider-agnostic core + provider registry + config resolution:
  - `src/engine/analysis/llmGrader.ts`
    (`LlmGradeRequest`, `LlmGradeResponse`, `buildGradingPrompt`,
    `parseLlmGradeResponse`, `mapLlmResponseToResult`, `PROVIDERS`,
    `resolveProviderConfig`, `callLlmGradeAPI`)
- Deterministic grader it complements / falls back to:
  - `src/engine/analysis/justification.ts`
- IPC handler + provider/key resolution (main process only):
  - `src/main/index.ts` (`llm:gradeJustification`)
- Renderer bridge:
  - `src/preload/index.ts`, `src/preload/index.d.ts`, `src/renderer/src/env.d.ts`
    (`gradeJustification`)
- Renderer consumption / fallback / debounce:
  - `src/renderer/src/components/question/QuestionPanel.tsx`
- Analysis barrel export:
  - `src/engine/analysis/index.ts`

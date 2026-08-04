# System Design Simulator — newton-api Backend Integration

> **Purpose.** Define how the HLD System Design Simulator plugs into the
> `newton-api` (Django) backend for authoring, embedding, submission, and
> **server-authoritative deterministic grading** — following the exact pattern
> `newton-api` already uses for **Cisco Packet Tracer**, swapping Packet Tracer's
> `pka2xml`/CI grading for our deterministic Node grading engine.
>
> **Scope note.** This is a **separate, standalone** playground / tech type. It is
> *not* a replacement for — and does not modify — the existing subjective
> System Design playground (`AssignmentQuestionType.SYSTEM_DESIGN` →
> `SubjectiveSubmission`, LLM-graded). The two coexist independently; this spec
> only concerns the new simulator integration.
>
> **Companion docs.** The simulator side of this boundary is specified in
> `docs/question-platform-hardening/` (the Game Playground embed contract in
> doc 02/07, the `EvaluationEnvelope` in doc 06, the `EnvironmentProfile` in
> doc 08) and the grading model in `question-grading-model-and-anti-gaming.md`.

---

## 0. The non-negotiable: grading is server-authoritative

The iframe's `ns-simulator:submit` result is **advisory feedback only** — a
student can edit the iframe/postMessage to send `allPassed: true`. `newton-api`
**must re-grade on the server** from the submitted topology, exactly as the
Packet Tracer flow re-parses the student's `.pka` server-side rather than
trusting a client claim. Everything below assumes this.

---

## 1. The `newton-api` patterns we mirror (Packet Tracer)

Observed in the codebase:

| Concern | Packet Tracer today | Our simulator (mirror) |
|---------|---------------------|------------------------|
| Tech type | `BoilerplateTech.PACKET_TRACER = 15` (`assignments/utils.py`) | **add `SYSTEM_DESIGN_SIMULATOR = 17`** |
| Question definition | `AssignmentQuestionGitRepoMapping` (boilerplate / solution / test-case git repos) | a **`QuestionPackage` JSON** (self-contained; no build repos needed) |
| Student workspace | `ProjectPlayground` (`boilerplate_tech_type`, `code_link`, `cloned_by`) | `ProjectPlayground` with the simulator tech type; the topology JSON as the artifact |
| Submission record | `ProjectPlaygroundSubmission` (`build_status`, `error_json`, `build_completed_at`) | same model + our result fields |
| Grading trigger | `@celery_app.task evaluate_packet_tracer_project_playground` | **`evaluate_system_design_simulator_submission`** (same shape) |
| Grader | `pka2xml` subprocess (`common/external_integrations/packet_tracer/ptxml_parser.py`) | our **Node grading engine** (`sim evaluate` CLI or an HTTP wrapper) |
| External compute call | `newton_ds_request('/api/v1/openai/…')` for subjective SD | `newton_grading_request('/grade', …)` to the Node grading service |
| Status enum | `BuildStatus` (`INTERNAL_ERROR`, …) | reuse `BuildStatus`; map our CLI exit codes onto it |

A separate subjective System Design playground already exists
(`AssignmentQuestionType.SYSTEM_DESIGN` → `SubjectiveSubmission` →
`evaluate_system_design_subjective_submission` → LLM on
`["correctness", "completeness"]`, min score 4). **This integration is
independent of it** — a new, standalone simulator tech type with its own
deterministic grading path. It neither replaces nor modifies the subjective
playground; the two run side by side. (The subjective flow is referenced here
only as a pattern example for calling an external grader — see §2.)

---

## 2. The one architectural decision: a Node grading service, not a Python re-impl

The grader is the Node/TS discrete-event engine + the pure semantic/justification
graders. **Do not port it to Python** (drift + the whole simulator). Instead,
`newton-api` calls a **Node grading service**, mirroring how it already shells out
to `pka2xml` and calls `newton_ds`:

- **v1 (simplest):** a subprocess call to the existing CLI
  `sim evaluate question <question.json> <topology.json> [--attempt-id --submission-id --evaluated-at]`
  → prints the `QuestionEvaluationContract` JSON to stdout, exit code in
  `{0 pass, 1 usage, 2 failed, 3 invalid_submission, 4 eval_error}`.
- **Recommended:** a thin **`ns-grading` HTTP microservice** wrapping the same
  engine (`POST /grade { questionPackage, topology, justificationAnswers } →
  { contract, score, envelope }`). Same engine, no drift, isolates the heavy CPU
  from Django/Celery workers, horizontally scalable. `newton-api` calls it like
  `newton_ds_request`.

This service also builds the **`EvaluationEnvelope`** (topology snapshot +
verdicts + digest + contract + checksum) so the backend persists an immutable,
tamper-evident record for audit/appeals.

---

## 3. Data model changes (Django)

Additive; reuse the Packet Tracer models where possible.

1. **`BoilerplateTech.SYSTEM_DESIGN_SIMULATOR = 17`** + a `CHOICES` label
   (`assignments/utils.py`). No `TestCaseTech` needed (grading is engine-driven,
   not a test-runner tech).

2. **Question package storage.** The `QuestionPackage` is self-contained JSON, so
   avoid the git-repo mapping ceremony. Two options:
   - **(Recommended)** a JSON field on the SD assignment question (or a
     `SystemDesignQuestion` model): `question_package = JSONField()`. Validate on
     save by calling the Node service's `/validate` (which runs our Zod
     `parseQuestionPackage`). Store `version`, `mode`, `total_points`.
   - Reuse `AssignmentQuestionGitRepoMapping` only if authors want git-versioned
     packages; then `boilerplate_git_template` holds the package repo. Heavier;
     not needed for v1.

3. **Submission.** Reuse `ProjectPlaygroundSubmission` (it already has
   `build_status`, `error_json`, `build_completed_at`). Add simulator result
   fields (or a JSON result blob):
   - `topology_json` — the graded topology (server's copy of truth).
   - `justification_answers` — `[{ promptId, text }]` (Phase 2b).
   - `evaluation_contract` — the authoritative `QuestionEvaluationContract`.
   - `evaluation_envelope` — the immutable sealed record + `checksum`.
   - `score`, `passed`, `hard_fail_reason`.
   The submission is **immutable** once graded (appeals/audit) — never overwritten.

4. **Attempt autosave (durable).** The simulator autosaves `AttemptState` to
   `localStorage` (best-effort). For cross-device durability, persist it against
   the `ProjectPlayground` (a JSON `attempt_state`), returned as `priorAttempt`
   on the next launch.

---

## 4. The embed / Game Playground contract (frontend ↔ iframe)

The `newton-api` **playground frontend** is the *Game Playground host*. It embeds
the simulator iframe and speaks our message contract (doc 02/07):

```
Host (playground UI)                         Simulator (iframe)
  serve iframe with ?hostOrigin=<origin>  ─────────────────────►
                            ◄──────────────  ns-simulator:ready
  ns-simulator:launch-context ─────────────►  { questionPackage, priorAttempt?,
    (targeted at iframe origin)                  environmentProfile: mode }
  … student builds & tests …
                            ◄──────────────  ns-simulator:submit
                                              { attemptState(topology), result(advisory) }
  ns-simulator:command {reset|lock|reveal} ─►  (host-driven lifecycle)
```

- **`environmentProfile.mode`** is one of `PRACTICE` / `ASSIGNMENT` / `AUTHOR`.
  `ASSIGNMENT` is the graded state (rubric hidden until submit, test-run cap,
  scaffold locked, minimal chrome); `PRACTICE` is ungraded self-paced (live
  rubric, free editing); `AUTHOR` is the setter/dev state.
- **Origin hardening:** always set `?hostOrigin=<newton-api playground origin>` so
  the simulator enforces the strict allowlist; sensitive messages are never
  broadcast (doc 07).
- On `ns-simulator:submit`, the frontend POSTs `{ topology, justificationAnswers }`
  to `newton-api`, which grades authoritatively (§5). The client `result` is
  **not** persisted as the score.

---

## 5. The submit → authoritative grade flow (Celery)

Mirror `evaluate_packet_tracer_project_playground`:

```python
@celery_app.task(name="evaluate_system_design_simulator_submission", acks_late=True)
def evaluate_system_design_simulator_submission(submission_id):
    sub = ProjectPlaygroundSubmission.objects.get(pk=submission_id)
    question = sub.project_playground.assignment_question           # server's QuestionPackage
    package = question.question_package                             # authored suite/workload/seed
    topology = sub.topology_json                                    # student's design

    # 1. Authoritative grade via the Node service (NOT the client result)
    resp = newton_grading_request('/grade', 'POST', {
        'questionPackage': package,          # server owns the test conditions
        'topology': topology,
        'justificationAnswers': sub.justification_answers,          # Phase 2b
    })
    #    → { contract, score, passed, hardFailReason, envelope }  (exit-code mapped)

    # 2. Persist immutable, tamper-evident record
    sub.evaluation_contract = resp['contract']
    sub.evaluation_envelope = resp['envelope']       # + checksum, re-verifiable
    sub.score, sub.passed = resp['score'], resp['passed']
    sub.hard_fail_reason = resp.get('hardFailReason')
    sub.build_status = BuildStatus.SUCCESS if resp['ok'] else BuildStatus.INTERNAL_ERROR
    sub.build_completed_at = now()
    sub.save(...)
    # 3. Update gradebook / milestone (as PT/subjective flows do)
```

The Node service injects the question's authored `suite` (`global`/`workload`/
`faults` + seed) onto the student topology via the engine's
`mergeTopologyWithOverrides` — the student never supplies the load or seed.

---

## 6. Anti-gaming — the server-side checklist

Same defense-in-depth as the grading-model spec, enforced by `newton-api`:

1. **Server-authoritative grade** (§0, §5). The single biggest hole; PT already
   does the equivalent.
2. **Question owns the test conditions** — the server holds the `QuestionPackage`;
   grade with its authored suite/workload/seed, never the student's.
3. **Fixed seed, single authoritative run** — no client seed-farming; exam
   `maxTestRuns` is profile-enforced; the recorded grade runs once server-side.
4. **Immutable submission** — persist the `EvaluationEnvelope` + `checksum`,
   re-verify on read, never overwrite.
5. **Exam controls host-side** — the playground frontend starts the timer and
   sends `ns-simulator:command {lock}` at expiry (freezes canvas + disables submit
   — already built); reveal results post-submit via the results API / `reveal`.
6. **Origin allowlist** — serve with `?hostOrigin=`.

---

## 7. Build order

| Phase | Backend work | Depends on |
|-------|--------------|------------|
| **B1 (v1)** | tech type `17`; `question_package` JSON field + `/validate`; embed the iframe (Game Playground contract, `hostOrigin`); `ProjectPlaygroundSubmission` + `evaluate_system_design_simulator_submission` Celery task calling the Node service for **structural + simulation** grading; persist envelope + score | Node grading service (CLI or HTTP) — engine already built |
| **B2** | durable `attempt_state` autosave ⇄ `priorAttempt` | B1 |
| **B3** | `justification_answers` capture + grading (the Node service already has the grader — Phase 2 engine) | simulator Phase 2b (answer field + UI) |
| **B4** | semantic-check + budget grading surfaced (engine Phases 3–4) — **no backend redesign**, the Node service just returns more criteria | engine Phases 3–4 |

Because grading is a Node-service call, later anti-gaming axes arrive as engine
updates the backend simply consumes — the Django surface barely changes after B1.

---

## 8. The Django architecture (MVC/S) — where each function lives

`newton-api` is a Django + Django REST Framework (DRF) app. Django's own name for
the pattern is **MVT** (Model–View–Template), but because the frontend is a SPA
that talks JSON, the "Template" slot is replaced by a **Serializer**, and the
heavy work is pushed into **Celery tasks** and **service/util functions**. So the
"MVC/S" layering you'll actually write is:

| Layer | File (per Django app, e.g. `playgrounds/`, `assignments/`) | Responsibility for our feature | Key functions you write |
|-------|------------------------------------------------------------|--------------------------------|-------------------------|
| **Model** (M) | `models.py` | Persistent tables + row-level invariants. The `QuestionPackage` JSON, the submission, the sealed envelope. | `class SystemDesignQuestion(models.Model)`, `def clean(self)`, `def save(self, *args, **kwargs)` |
| **Enums / constants** | `utils.py`, `constants.py` | The tech-type choice (`BoilerplateTech.SYSTEM_DESIGN_SIMULATOR = 17`) and status labels. | add the enum member + `CHOICES` label |
| **Serializer** (S) | `serializers.py` | Validate the request body, shape the JSON response. This is the "view template" for an API. | `class SubmitSimulatorSerializer(serializers.Serializer)`, `def validate(self, attrs)`; `class SimulatorSubmissionResultSerializer(ModelSerializer)` |
| **View / Controller** (V/C) | `views.py` (DRF `APIView`/`generics`) | HTTP entry points: auth, permissions, read the serializer, create the submission row, **enqueue** the Celery grade, return `202`. Thin — no grading logic here. | `class SimulatorSubmitView(APIView)`, `def post(self, request, playground_hash)`; `class SimulatorSubmissionResultView(RetrieveAPIView)` |
| **Service / Controller** (C/S) | `tasks.py` (Celery) + `utils.py` (helpers) + `common/external_integrations/…` | The actual grading orchestration, off the request thread. Calls the Node engine, maps exit codes, persists the immutable record. **All authoritative logic lives here.** | `@celery_app.task evaluate_system_design_simulator_submission(submission_id)`; `def newton_grading_request(path, method, body)` |
| **Routing** | `urls.py` | Map URL → view. | `re_path(r'^system_design_simulator/h/(?P<playground_hash>[0-9a-zA-Z]+)/submit/$', views.SimulatorSubmitView.as_view())` |
| **Admin** | `admin.py` | The authoring UI faculty use to create questions (see §10). | `class SystemDesignQuestionAdmin(admin.ModelAdmin)` + `admin.site.register(...)` |

The one rule that makes this safe: **the View never grades and never trusts the
client `result`.** The View only records "a submission happened" and hands the
`submission_id` to the Celery task; the **task** is the single place that produces
an authoritative score (mirrors `evaluate_packet_tracer_project_playground`, which
is dispatched from `playgrounds/views.py:1538` via `.apply_async(..., queue='project')`).

**Request lifecycle, end to end:**

```
Browser (iframe host)                Django                          Celery worker
  POST …/submit/  ───────────────►  SimulatorSubmitView.post
   {topology, justificationAnswers}   ├─ SubmitSimulatorSerializer.validate()   (shape only)
                                      ├─ ProjectPlaygroundSubmission.objects.create(build_status=QUEUED)
                                      ├─ transaction.on_commit(lambda:
                                      │     evaluate_…_submission.apply_async(
                                      │        args=(sub.id,), queue='project'))
                                      └─ return 202 {submission_hash}
  ◄─── 202 ──────────────────────────┘                              ┌───────────────────────────
  … client polls result …                                          │ evaluate_…_submission(sub.id)
  GET …/submission/<hash>/  ──────►  SimulatorSubmissionResultView  │  ├─ newton_grading_request('/grade', … server's QuestionPackage …)
                                      └─ SimulatorSubmissionResult   │  ├─ map exit code → BuildStatus
                                          Serializer(sub).data       │  ├─ sub.evaluation_envelope = …  (immutable)
  ◄─── 200 {score, passed, contract} ─┘                             │  └─ sub.save()
                                                                    └───────────────────────────
```

---

## 9. Implementation tasks in chunks (newton-api)

Each chunk is a self-contained PR-sized unit, mapped to the B1–B4 build order in
§7. File paths assume the `playgrounds/` and `assignments/` apps (adjust if you
create a dedicated `system_design/` app — recommended if you want isolation).

### Chunk 0 — Node grading service (prerequisite, not Django)
- [ ] Decide transport: subprocess CLI (`sim evaluate …`, v1) **or** the
      `ns-grading` HTTP microservice (recommended). The engine already exists.
- [ ] If HTTP: stand up `POST /grade` and `POST /validate` returning
      `{ contract, score, passed, hardFailReason, envelope, ok }`.
- [ ] Add the service URL + timeout to Django settings
      (`SYSTEM_DESIGN_GRADING_URL`, `..._TIMEOUT`).

### Chunk 1 — Model + enum foundation (B1)
- [ ] `assignments/utils.py`: add `BoilerplateTech.SYSTEM_DESIGN_SIMULATOR = 17`
      and its `CHOICES` label. (No `TestCaseTech` — grading is engine-driven.)
- [ ] `models.py`: add `SystemDesignQuestion` (or a `question_package` JSONField
      on the existing SD question model) with `version`, `mode`, `total_points`,
      `question_package = models.JSONField()`.
- [ ] `models.py`: extend `ProjectPlaygroundSubmission` (or subclass) with
      `topology_json`, `justification_answers`, `evaluation_contract`,
      `evaluation_envelope`, `score`, `passed`, `hard_fail_reason`.
- [ ] `SystemDesignQuestion.clean()` → call the Node `/validate` and raise
      `ValidationError` on a bad package (this is what makes the admin form safe).
- [ ] `makemigrations` + `migrate`.

### Chunk 2 — Service / grading task (B1)
- [ ] `common/external_integrations/…`: `newton_grading_request(path, method, body)`
      (mirror `newton_ds_request`) — POST JSON to the Node service, timeouts,
      retries, structured error.
- [ ] `tasks.py`: `@celery_app.task(acks_late=True) evaluate_system_design_simulator_submission(submission_id)`
      — load submission → call `newton_grading_request('/grade', …)` with the
      **server's** `question_package` → map exit code to `BuildStatus` → persist
      envelope/score/contract immutably → update gradebook.
- [ ] Unit-test the exit-code → `BuildStatus` mapping and the "never trust client
      result" path.

### Chunk 3 — Serializer + View + routing (B1)
- [ ] `serializers.py`: `SubmitSimulatorSerializer` (validates `topology`,
      `justificationAnswers` shape only — **not** grading);
      `SimulatorSubmissionResultSerializer` (read-side: `score`, `passed`,
      `contract`, `build_status`).
- [ ] `views.py`: `SimulatorSubmitView.post()` → create submission (status
      `QUEUED`) → `transaction.on_commit` enqueue the task → `202`.
      `SimulatorSubmissionResultView` → poll result.
- [ ] `urls.py`: wire both endpoints.
- [ ] Permission/auth: reuse the playground permission classes.

### Chunk 4 — Embed / host wiring (B1)
- [ ] Serve the simulator iframe from the playground frontend with
      `?hostOrigin=<origin>`; implement the Game Playground message contract (§4):
      `launch-context` (send server's `questionPackage` + `mode`), receive
      `submit`, POST to the submit endpoint.
- [ ] Exam lifecycle: host starts the timer, sends `command {lock}` at expiry,
      `reveal` post-submit.

### Chunk 5 — Admin authoring (B1, see §10)
- [ ] `admin.py`: `SystemDesignQuestionAdmin` with a JSON widget, validation on
      save, and a "Validate package" admin action.

### Chunk 6 — Durable attempt autosave (B2)
- [ ] `attempt_state` JSONField on `ProjectPlayground`; save-on-autosave endpoint;
      return as `priorAttempt` in `launch-context`.

### Chunk 7 — Justification capture (B3)
- [ ] Persist `justification_answers` on submit; pass through to `/grade`
      (the engine's justification grader already exists).

### Chunk 8 — Semantic + budget surfacing (B4)
- [ ] No backend redesign — the Node service returns more criteria in `contract`;
      confirm the result serializer passes them through untouched.

---

## 10. Creating a question in the Django admin

**Do we need it?** Yes — faculty author questions in the Django admin, exactly as
they author `AssignmentQuestion`s today (`assignments/admin.py:956`
`AssignmentQuestionAdmin`, registered at line 2045). The difference: a Packet
Tracer question points at **git repos** via an inline
(`AssignmentQuestionGitRepoMappingInline`, `assignments/admin.py:428`), whereas
our question is **one self-contained `QuestionPackage` JSON** — so there is no
inline, just a validated JSON field on a `ModelAdmin`.

### 10.1 The model (what the admin edits)

```python
# system_design/models.py  (or assignments/models.py)
class SystemDesignQuestion(models.Model):
    hash = models.CharField(max_length=32, unique=True, default=get_random_unique_hash)
    title = models.CharField(max_length=255)
    mode = models.PositiveSmallIntegerField(choices=EnvironmentMode.CHOICES)  # PRACTICE/ASSIGNMENT/AUTHOR
    total_points = models.PositiveIntegerField(default=0)
    question_package = models.JSONField()   # the full QuestionPackage (suite, rubric, semanticCriteria, justify, budget)
    version = models.CharField(max_length=16, default="1.0")

    def clean(self):
        # Server-side validation = call the Node engine's parseQuestionPackage.
        # This is what stops a malformed package from ever being saved.
        resp = newton_grading_request('/validate', 'POST', {'questionPackage': self.question_package})
        if not resp.get('ok'):
            raise ValidationError({'question_package': resp.get('errors', 'Invalid QuestionPackage')})
        # Denormalize for list display / gradebook.
        self.total_points = resp['totalPoints']
        self.version = resp['version']

    def save(self, *args, **kwargs):
        self.full_clean()          # runs clean() → validation happens on every admin save
        super().save(*args, **kwargs)
```

### 10.2 The admin registration (the authoring UI)

```python
# system_design/admin.py
from django.contrib import admin
from django_json_widget.widgets import JSONEditorWidget   # nice JSON editor; falls back to Textarea
from django.db.models import JSONField

@admin.register(SystemDesignQuestion)
class SystemDesignQuestionAdmin(admin.ModelAdmin):
    list_display = ('title', 'hash', 'mode', 'total_points', 'version')
    readonly_fields = ('hash', 'total_points', 'version')     # derived by clean(), not hand-edited
    formfield_overrides = {JSONField: {'widget': JSONEditorWidget}}
    actions = ['validate_package']

    @admin.action(description="Validate QuestionPackage against the grading engine")
    def validate_package(self, request, queryset):
        for q in queryset:
            resp = newton_grading_request('/validate', 'POST', {'questionPackage': q.question_package})
            level = messages.SUCCESS if resp.get('ok') else messages.ERROR
            self.message_user(request, f"{q.title}: {resp.get('errors', 'valid')}", level=level)
```

### 10.3 The authoring workflow (what a faculty member does)

1. Admin → **System Design Questions → Add**.
2. Fill `title`, pick `mode` (graded ⇒ `ASSIGNMENT`).
3. Paste the **QuestionPackage JSON** into the `question_package` editor. This JSON
   holds *everything the grader needs*: the prompt, the scenario, the **test
   conditions** (`suite`: `global`/`workload`/`faults` + `seed`), the **rubric**
   (simulation-metric checks), the **structural rules**, the **semanticCriteria**
   (`placement`/`guardedPath`/`fanout`/`storageFit`/`forbidUnjustified`), the
   **justify** prompts, and the **budget** — see the schema in
   `question-grading-model-and-anti-gaming.md` §2.
4. **Save.** `clean()` calls the Node `/validate`; a malformed package is rejected
   with the Zod error inline — the author cannot save a broken question.
5. Optionally run the **"Validate package"** action to re-check without editing.

> Authoring the JSON by hand is fine for v1 (it mirrors how PT authors hand-wire
> git repos). A guided form per field is a later nicety, not required — the JSON
> field + `/validate` gives you a safe authoring loop today.

---

## 11. Writing test cases

**Key mental model:** for this simulator, "test cases" are **not** a separate
git repo of unit tests (as Packet Tracer / coding questions use). The test cases
**are fields inside the `QuestionPackage` JSON** — they travel with the question
and are executed by the deterministic grading engine. There is no `TestCaseTech`,
no test-runner boilerplate. A student's design is "tested" by being graded against
these authored conditions on the server.

The four "test-case" surfaces an author writes inside `question_package`:

| Surface | JSON field | What it asserts | Anti-gaming role |
|---------|-----------|-----------------|------------------|
| **Test conditions** | `suite` (`global`, `workload`, `faults`, `seed`) | the load/fault scenario the design is run under | **question-owned** — injected via `mergeTopologyWithOverrides`; the student never supplies load or seed |
| **Simulation rubric** | `rubric[]` | metric thresholds after the run (p99 latency, availability, drop rate) | grades *performance*, not correctness |
| **Structural rules** | structural rules / `semanticCriteria[]` | topology facts (guardedPath, fanout, storageFit, placement, forbidUnjustified) | grades *architecture* — catches gaming the metrics |
| **Justification prompts** | `justify[]` (+ paired `semanticCriteria` points) | the design's reasoning is graph-consistent, cites a number, states a tradeoff | catches memorized prose / stuffing |

### 11.1 How an author writes and verifies a "test case"

This mirrors how PT authors verify test cases against a **solution** and a
**boilerplate** (`assignments/admin.py:473`, solution fields gated to solution-admins):

1. **Write** the four surfaces into `question_package` (§10 step 3).
2. **Author a reference/solution topology** and a **deliberately-wrong topology**.
3. **Run both through the grader** — the same call the server uses at submit:
   ```bash
   sim evaluate question question_package.json solution_topology.json
   # expect exit 0 (pass) and score == total_points
   sim evaluate question question_package.json gamed_topology.json
   # expect a hard-fail or a low score — the anti-gaming axis should catch it
   ```
   (Or `POST /grade` to the `ns-grading` service.) This is the authoring
   equivalent of PT running the test repo against the solution repo.
4. **Assert orthogonality** — for each gaming surface (node/edge/workload/config),
   confirm a topology that games *one* axis still fails another (the defense-in-depth
   check from the grading-model spec §7). If a gamed design passes, the test cases
   are too weak — tighten `semanticCriteria`/`rubric`.
5. Commit the reference + gamed fixtures alongside the question (recommended) so
   the assertion in step 3–4 can run in CI, exactly like the engine's own
   fixtures under `src/engine/**/__fixtures__`.

### 11.2 Where this runs on the server (no separate test infra)

At submit time the **same** engine executes these authored conditions
(§5 Celery flow): the server merges the question's `suite` onto the student
topology, runs the simulation, evaluates rubric + structural + semantic +
justification, and returns the `contract`. The "test cases" are therefore
executed **once, authoritatively, server-side** — there is nothing extra to
provision beyond the Node grading service from Chunk 0.

---

## 12. Concrete examples (what these actually look like)

A worked end-to-end example for a **"Design a URL shortener"** question. Every
value is real (valid `ComponentType`s, valid schema fields) so you can copy it.

### 12.1 The `SystemDesignQuestion` row (Django model + admin list)

In the admin changelist (`SystemDesignQuestionAdmin.list_display`) a saved
question appears as one row:

| title | hash | mode | total_points | version |
|-------|------|------|--------------|---------|
| Design a URL shortener | `f3a9c1b2…` | ASSIGNMENT | 10 | 1.0 |

Backed by this row (columns = model fields from §10.1):

```python
SystemDesignQuestion(
    hash="f3a9c1b2e7d04a15",
    title="Design a URL shortener",
    mode=EnvironmentMode.ASSIGNMENT,   # graded
    total_points=10,                  # DERIVED by clean() from the package, read-only
    version="1.0",                    # DERIVED, read-only
    question_package={...},           # the JSON in §12.2 — the only field authored by hand
)
```

`total_points` and `version` are **not typed by the author** — `clean()` fills
them from the Node `/validate` response, so the changelist always reflects the
real package.

### 12.2 The `question_package` JSON (pasted into the admin JSON field)

This is a full, valid `QuestionPackage`. Beyond the baseline (prompt / scaffold /
constraints / suite / rubric) it carries the three anti-gaming axes —
`semanticCriteria`, `justify`, `budget` — so all four gaming surfaces are covered:

```json
{
  "version": "1.0",
  "id": "url-shortener-v1",
  "title": "Design a URL shortener",
  "difficulty": "intermediate",
  "type": "open-build",
  "workloadCategory": "read-heavy",
  "prompt": {
    "text": "Design a URL shortener that stays fast and available under a read-heavy load. Reads (redirects) dominate writes ~100:1.",
    "functionalRequirements": [
      "Create a short code for a long URL",
      "Redirect a short code to its long URL"
    ],
    "nonFunctionalRequirements": [
      {
        "metric": "latency_p99",
        "operator": "<",
        "value": 100,
        "unit": "ms",
        "description": "p99 redirect latency under 100ms"
      },
      {
        "metric": "availability",
        "operator": ">=",
        "value": 99.9,
        "unit": "percent",
        "description": "At least 99.9% availability"
      }
    ],
    "scale": {
      "dau": 50000000,
      "peakRps": 200000,
      "readWriteRatio": 99
    }
  },
  "scaffold": { "type": "empty" },
  "constraints": {
    "canModifyScaffold": true,
    "canRemoveScaffoldNodes": true,
    "maxNodeCount": 12,
    "maxBudget": 500
  },
  "structuralRules": [
    {
      "id": "has-lb",
      "kind": "requires_component",
      "componentType": "load-balancer",
      "description": "A load balancer must front the service"
    },
    {
      "id": "single-source",
      "kind": "requires_single_source",
      "description": "Exactly one client/source of traffic"
    }
  ],
  "semanticCriteria": [
    {
      "id": "reads-through-cache",
      "kind": "guardedPath",
      "description": "Redirect reads must traverse a cache before the store",
      "from": "microservice",
      "guard": "in-memory-cache",
      "to": "kv-store",
      "points": 3,
      "hardFail": false
    },
    {
      "id": "store-fits-point-lookup",
      "kind": "storageFit",
      "description": "Short-code lookup is a point-lookup at 200K rps",
      "accessPattern": "point-lookup",
      "accept": ["kv-store", "nosql-db"],
      "partial": ["in-memory-cache"],
      "antiPattern": ["relational-db"],
      "points": 3,
      "hardFail": true
    }
  ],
  "justify": [
    {
      "id": "why-store",
      "decision": "Why this store type for short-code lookups at this scale?",
      "boundTo": { "componentType": "kv-store" },
      "requires": { "choice": true, "number": true, "tradeoff": true }
    }
  ],
  "budget": {
    "unit": "cost",
    "cap": 500
  },
  "suite": {
    "name": "url-shortener-suite",
    "visibleToStudent": false,
    "cases": [
      { "id": "baseline", "description": "Nominal read-heavy load." },
      {
        "id": "peak",
        "description": "Peak redirect storm, fresh seed.",
        "global": { "seed": "url-shortener-peak" },
        "workload": { "baseRps": 200000 }
      }
    ]
  },
  "rubric": {
    "id": "url-shortener-rubric",
    "passThreshold": 1,
    "checks": [
      {
        "id": "has-cache",
        "kind": "topology",
        "description": "Includes an in-memory cache",
        "metric": "topology.componentCounts.in-memory-cache",
        "op": ">=",
        "value": 1,
        "points": 1
      },
      {
        "id": "p99-latency",
        "kind": "simulation",
        "description": "p99 redirect latency under 100ms",
        "metric": "summary.latencyP99Ms",
        "op": "<",
        "value": 100,
        "points": 2
      },
      {
        "id": "no-invariants",
        "kind": "invariant",
        "description": "No invariant violations",
        "metric": "invariantViolations.count",
        "op": "==",
        "value": 0,
        "points": 1
      }
    ]
  },
  "author": "faculty@newtonschool.co"
}
```

> **Why the split matters (anti-gaming):** the `rubric` grades *performance*
> (p99, invariants), `semanticCriteria` grade *architecture* (reads go through a
> cache; the store fits a point-lookup — a `relational-db` hard-fails), `justify`
> grades *reasoning* (the answer must name the `kv-store` actually in the graph
> and cite one of this question's numbers), and `budget` caps *cost*. Gaming one
> axis is caught by another. The student never sees or supplies `suite` — the
> server injects it.

### 12.3 How each rule is actually evaluated (and how the author knows)

**The `description` field is a pure label.** The grader never parses it — it is
echoed back into results for humans. Only the `kind` + typed fields are computed.
So "A load balancer must front the service" grades *nothing*; `kind:
"requires_component"` + `componentType: "load-balancer"` is the real boundary.

Every rule reduces to a deterministic graph computation over the submitted
topology (from `src/engine/analysis/structural.ts` — `evaluateRule`). The author
confirms a boundary not by trusting the prose but by running the grader and
reading the generated `detail`:

| Rule kind | What the engine computes | `detail` on failure (machine-generated) |
|-----------|--------------------------|------------------------------------------|
| `requires_component` | `countNodesOfType(topo, type) >= (minCount ?? 1)` | `expected at least 1 load-balancer component, found 0.` |
| `requires_single_source` | `sourceNodeIds(topo).length === 1` (nodes with no inbound edge) | `expected exactly 1 source node, found 2: client, mobile.` |
| `requires_edge` | any edge whose endpoints match `fromType→toType` (and `mode`) | `no edge from microservice to kv-store found.` |
| `requires_path` | directed BFS from all `fromType` nodes reaches a `toType` node | `no directed path found from microservice to kv-store.` |
| `requires_connected_graph` | undirected BFS from node 0 visits every node | `disconnected node ids: cache-2.` |
| `max_node_count` / `min_node_count` | `topo.nodes.length` vs `count` | `expected at most 12 total nodes, found 14.` |
| `requires_redundancy` | replica count of `componentType` ≥ `minReplicas` | `expected 2 replicas of kv-store, found 1.` |

Rubric checks are the same idea but numeric: `metric` is resolved to a number
(`resolveMetric`/`resolveTopologyMetric`) and compared with `op`/`value` — e.g.
`summary.latencyP99Ms < 100`. If a metric name doesn't resolve, the check reports
an "unresolved metric" detail (another author-time signal that a key is wrong).

> **Author feedback loop:** run `sim evaluate` (§12.4). Each rule returns
> `{ id, passed, detail }`; a mis-set boundary shows up as either the wrong
> pass/fail on your reference/gamed fixtures, or an "unresolved metric" detail.
> That is the ground truth — not the `description` text.

> ⚠️ **Semantic criteria are not graded yet.** `guardedPath`, `storageFit`,
> `placement`, `fanout`, `forbidUnjustified` are currently **typed contracts
> only** — they `parse`/`validate` on save (so the package is well-formed), but
> the engine has **no evaluator for them yet** (grep `src/engine`: none). They
> begin scoring in the engine's Phase 3 (grading-model spec §9). Until then:
> a package may *declare* `store-fits-point-lookup`, but a submission is **not
> actually scored** against it. Author with this in mind — put the boundaries you
> need enforced *today* into `structuralRules` + `rubric` (both fully evaluated),
> and treat `semanticCriteria`/`justify`/`budget` as forward-declared axes that
> light up as the engine phases land (§7 B3–B4). `justify` grading *does* exist
> (`justification.ts`); it's wired end-to-end in B3.

### 12.4 Test cases (author-side verification)

The "test cases" are the fields above; you verify them by grading a **reference**
design and a **deliberately-gamed** design with the same call the server runs.

**Reference (correct) topology — expect full marks.** `client → load-balancer →
microservice → in-memory-cache → kv-store`:

```bash
sim evaluate question url-shortener.question.json reference-topology.json
# → exit 0, score 10/10 (rubric + guardedPath + storageFit + justify all pass)
```

**Gamed topology #1 — right metrics, wrong architecture.** A `relational-db`
tuned to *pass* p99 in the sim, no cache on the read path:

```bash
sim evaluate question url-shortener.question.json gamed-relational.json
# → HARD FAIL: storageFit.antiPattern (relational-db at point-lookup 200K) zeroes the question,
#   even though the simulation rubric alone might have passed.
```

**Gamed topology #2 — memorized justification.** Correct graph, but the
`why-store` answer describes a SQL database:

```json
{ "promptId": "why-store", "text": "I used a SQL database for 200K reads/sec, but lose ad-hoc joins." }
```
```bash
# → justify.why-store FAILS the graph-consistency gate (names a store not in the graph) → 0 for that axis.
```

The author's acceptance check: **every gamed design loses at least one axis.** If
a gamed design scores full marks, the test cases are too weak — tighten
`semanticCriteria`/`rubric`. Commit `reference-topology.json` +
`gamed-*.json` next to the question so this runs in CI (mirrors the engine's own
`src/engine/**/fixtures`).

### 12.5 The process of creating a question (end to end)

1. **Draft the package.** Author the `QuestionPackage` JSON (§12.2) in an editor.
   Start from an existing one (e.g. `fixtures/rubric-check-hardening.question.json`).
2. **Validate locally.** Run `sim evaluate question <pkg> <reference-topology>` to
   confirm it parses and your reference design scores full marks (§12.3).
3. **Adversarially test.** Grade 1–2 gamed topologies; confirm each loses an axis.
4. **Open the admin.** Django admin → **System Design Questions → Add**.
5. **Fill the form.** `title`, `mode` (graded ⇒ `ASSIGNMENT`), paste the JSON into
   `question_package`. Leave `hash`/`total_points`/`version` blank — derived.
6. **Save.** `SystemDesignQuestion.clean()` calls the Node `/validate`; a bad
   package is rejected inline with the Zod error. On success the row shows
   `total_points` and `version` (§12.1).
7. **(Optional) Re-validate** any time via the **"Validate package"** admin action.
8. **Attach to an assignment / playground** the same way a Packet Tracer question
   is attached, so students launch it in the Game Playground iframe (§4).

Once saved, submissions flow through §5: the server grades authoritatively with
*this* stored `question_package`, never the client's claim.

---

## 13. Open decisions

- **Question storage:** JSON field (recommended) vs `AssignmentQuestionGitRepoMapping`
  (git-versioned packages). v1 = JSON field.
- **Submission model:** extend `ProjectPlaygroundSubmission` (recommended, mirrors
  the Packet Tracer path) or add a dedicated simulator submission model. Do **not**
  reuse `SubjectiveSubmission` — that belongs to the separate subjective SD
  playground. Recommend `ProjectPlaygroundSubmission` since grading is
  deterministic/build-like.
- **Node grading service transport:** subprocess CLI (v1) vs `ns-grading` HTTP
  microservice (recommended at scale). Same engine either way.

_(No relationship to the existing subjective SD playground — this is a separate
tech type; see the scope note at the top.)_

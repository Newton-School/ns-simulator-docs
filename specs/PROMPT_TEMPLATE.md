# Prompt Template — Feature Specification Document

Use this prompt to generate a technical feature specification document for any feature domain. Replace the bracketed placeholders with your specifics. Feed the source material (PDFs, prototypes, PRDs, screenshots) as attachments alongside this prompt.

---

## The Prompt

```
You are writing a technical feature specification document for a software project. The document must be written from a FEATURE perspective — what each capability does, why it exists, how it works internally at the code level, what data it consumes, and what components it requires. It is NOT a UI spec, NOT a PRD, and NOT a user story collection.

## Context

Project: [PROJECT_NAME]
Repository: [REPO_URL or local path]
Feature domain: [FEATURE_DOMAIN — e.g., "In-app Terminal", "Real-time Collaboration", "Plugin System"]
Source material: [describe what you're attaching — e.g., "4 HTML prototypes", "a PRD PDF", "design mockups", "research notes"]

## Before writing, do this

1. Read all the attached source material completely.
2. Explore the project's codebase to understand:
   - The existing architecture (what layers exist, how data flows)
   - The relevant types, interfaces, and data structures
   - The existing file organization and naming conventions
   - What already exists vs what's new
   - Any other technical docs in the project (match their style and depth)
3. Identify every distinct FEATURE in the source material. A feature is a capability — not a UI panel, not a button, not a layout option. Group related UI elements into the single feature they serve.

## Document structure

Write the document with this exact structure:

### Title & intro paragraph
- One-line description of what the document covers.
- 2-3 sentences on what source material it consolidates and why this document exists.

### Table of Contents
- Numbered list of all sections including every feature.

### Problem Context
Three subsections:
- **What exists today**: Walk through the current architecture as it relates to this feature domain. Reference actual files, types, and data flows in the codebase. Be specific — file paths, type names, function signatures.
- **What's missing**: Enumerate the specific gaps. Each gap should be a concrete technical absence, not a vague wish. Tie each gap to why users or developers can't do something today.
- **What the source material explores**: One paragraph summarizing the scope of the source material without duplicating the feature sections.

### Feature sections (one per feature)
Each feature section has exactly these subsections:

#### What it does
2-4 sentences. Describe the capability in concrete terms. No marketing language.

#### Why it exists
Explain the problem this feature solves. Connect it to the specific gap from Problem Context. Explain what question the user is trying to answer or what workflow they're trying to complete.

#### How it works internally
This is the core of each feature section. It must include:
- **Data source**: What existing types/data this feature reads from. Use actual type names and file paths from the codebase. Show the relevant type definition or interface as a code block.
- **Processing/logic**: How the feature transforms, filters, derives, or computes from the source data. Include algorithms, state machines, formulas, or decision trees where applicable.
- **New types**: If the feature introduces new types or interfaces, define them as TypeScript (or the project's language) code blocks with JSDoc comments explaining each field. Explain WHY each field exists and WHERE its value comes from.
- **Integration points**: How this feature connects to existing code — which hooks it calls, which store slices it reads/writes, which protocols it uses.

If the feature has sub-capabilities, use a table:
| Sub-capability | Data source | Output |
|---|---|---|

If the feature has multiple states or modes, use a table:
| State | Condition | Behavior |
|---|---|---|

#### What components it requires
Bullet list split by layer:
- **Engine-side**: What changes to the core logic/backend
- **Shared layer** (if applicable): What's reusable across contexts
- **Renderer/frontend-side**: What UI components, hooks, or state

#### Explored in
Which source material items cover this feature (e.g., "Prototype 2, Prototype 4", "PRD Section 3.2", "Design doc pages 4-7").

### Relationship section (if the feature domain relates to other feature domains)
A section explaining how this feature domain intersects with adjacent domains in the same project. Include:
- A shared data source table showing what data is consumed by both domains
- What this domain adds that the other doesn't need
- Implementation order implications

### Integration Requirements
What changes the feature domain requires from the existing codebase, organized by layer. For each change, specify:
- What file or module is affected
- What the change is
- Why it's needed
- How large it is (rough line count or complexity)

### Source-to-Feature Map
A table mapping each feature to which source material items cover it.

## Writing rules

1. **Ground everything in code.** Every claim about "how it works" must reference an actual type, file, function, or data flow in the codebase. If a type doesn't exist yet, define it as a code block and say where it would live.

2. **Explain WHY, not just WHAT.** For every new type field, every design choice, every architectural decision — explain why it exists, what alternative was rejected, or what problem it prevents.

3. **Use the project's own vocabulary.** Don't invent new terms when the codebase already has names for things. Use the actual type names, the actual file names, the actual enum values.

4. **Show the data lineage.** For every piece of data the feature displays or uses, trace it back to its origin in the engine/backend. "This field shows X" is incomplete. "This field shows X, which comes from Y.getZ() in file F, computed as A + B" is complete.

5. **Distinguish existing from new.** Clearly mark what already exists ("The engine currently does X") vs what needs to be built ("The engine would need to Y").

6. **No UI/CSS specifics.** Do not describe pixel dimensions, CSS classes, color hex codes, font sizes, or layout grids. Describe what information is shown and how it's structured, not how it's styled. The reader should be able to build any visual representation from your feature description.

7. **No marketing or aspirational language.** No "powerful", "seamless", "elegant", "robust". Describe what the feature does mechanically.

8. **Code blocks for all type definitions.** Every new interface, type, enum, or function signature must be in a fenced code block with the language tag. Inline code (backticks) for field names, type names, and file paths.

9. **Tables for structured comparisons.** Use markdown tables whenever comparing options, listing states, mapping data sources, or showing feature coverage.

10. **Cross-reference other features.** When one feature depends on or shares data with another, link to it: "see [Feature N](#feature-n--name)".
```

---

## How to use this prompt

### Step 1 — Prepare your inputs

Gather your source material. This can be any combination of:
- HTML/interactive prototypes
- PDF design docs, PRDs, or ideation documents
- Screenshots or mockups
- Research notes or brainstorm outputs
- Existing issue tickets or feature requests

### Step 2 — Feed it to the LLM

Attach the source material and paste the prompt above with your placeholders filled in. The LLM should have access to the codebase (either via tool access, or paste relevant files inline).

### Step 3 — Iterate on the first draft

The first pass typically gets the structure right but may:
- Be too UI-focused (if source material is mockup-heavy) — push back with "rewrite from feature perspective, not UI perspective"
- Miss codebase grounding — push back with "explore the repo first, then rewrite with actual type names and file paths"
- Over-generalize — push back with "show the actual TypeScript interface, not a prose description"

### Step 4 — Use the output

The resulting document serves as:
- **Implementation spec** for developers — they know exactly what types to create, where files go, what data flows look like
- **Issue creation source** — each feature section maps to one or more GitHub issues
- **Schema/data model input** — the type definitions can be extracted into a companion schema document
- **Dependency graph input** — the "What components it requires" and cross-references reveal the implementation order

---

## Examples of documents generated with this pattern

| Document | Feature domain | Features covered | Source material |
|---|---|---|---|
| `event-debugger-prototypes.md` | Event debugging & request lifecycle inspection | 13 features | 5 HTML prototypes |
| `event-debugger-schema.md` | Event debugger data model | 7 engine types, 4 worker messages, 5 renderer types | The prototypes doc + codebase exploration |
| `terminal-feature-spec.md` | In-app Cisco Packet Tracer-style terminal | 11 features | 2 PDF design docs |
| `question-creation-feature-spec.md` | Simulator-based grading & question authoring | 10 features | 1 PDF design doc |

---

## Adapting the prompt

**For a schema/data model document** (like `event-debugger-schema.md`):
Replace "feature perspective" with "data model perspective" and change the feature section structure to:
- Type name and definition (code block)
- Why this type exists (what feature needs it, why existing types don't suffice)
- Where it lives (file path)
- How it connects to existing types (what it wraps, extends, or projects from)
- Where it's populated (which function/handler creates instances of it)

**For a backend-heavy system** (like `question-creation-feature-spec.md`):
Add a section for "Architecture Boundary" that explicitly draws the line between what lives in which codebase. Use a diagram showing the contract surface.

**For a system with cross-cutting concerns**:
Add a "Shared Data Sources" table early in the document and reference it from each feature section instead of repeating the same data lineage.

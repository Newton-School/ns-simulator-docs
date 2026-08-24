---
title: "How this vault works"
tags: [meta]
---
A **learning garden**: atomic concepts (`[[wikilinked]]`), maps of content (MOCs), a
module curriculum, and teaching-vehicle problems - with backlinks and a graph. The
canonical `specs/` (wired in at `reference/specs/`) remain the source of truth; this
vault is the *learning layer* that links into them.

## Folders
| Folder | What lives here | Note type |
|--------|-----------------|-----------|
| `index` | Home + the 3 learning paths | landing |
| `learn/` | Curriculum - M00-M15 + capstone | **module** |
| `problems/` | Teaching vehicles - P01-P13 | **problem** |
| `concepts/` | Atomic ideas, one per note, by cluster | **concept (zettel)** |
| `maps/` | MOCs - the entry hubs | **moc** |
| `roadmap/` | The execution plan (5 phases, 7 workstreams) | roadmap |
| `reference/specs/` | The 107 canonical specs (source of truth) | reference |
| `decisions/adrs/` | ADRs | reference |
| `meta/` | Templates + this guide | meta |

## The linking model
- A **module** links down to the concepts it teaches, sideways to its **problem**, and out to its **reference spec**.
- A **problem** links to the concepts it exercises + the modules that use it.
- A **concept** is atomic, chains to other concepts (`[[A]] → [[B]]`), and rolls up to a **MOC**.
- A **MOC** is a curated hub of `[[links]]`.

## Authoring rules
1. **One idea per concept note.** If it needs "and", split it.
2. **Link, don't repeat.** Point at the canonical spec; never copy engine details.
3. **Every note earns a link** - at least one MOC + one neighbour.
4. **Titles are claims,** not topics.
5. Start new notes from [[meta/templates/concept|a template]]. **Quote any title with a `:`** in it (YAML).

Reusable doc-writing prompts: [[doc-prompts|DOC-PROMPTS]]. Setup/deploy lives in `../README.md` and `../deploy/` (outside the published vault).

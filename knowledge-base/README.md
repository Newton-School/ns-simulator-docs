# Simulator Knowledge Base (Quartz vault)

A **learning garden** for the NS-Simulator: atomic concepts (`[[wikilinked]]`),
maps of content (MOCs), a module-by-module curriculum, and teaching-vehicle
problems - with backlinks and an interactive graph. The canonical `specs/` remain
the source of truth; this KB is the *learning layer* that links into them.

The markdown lives in `content/`. That folder **is** the Quartz vault - open it in
Obsidian to author (you get `[[ ]]` autocomplete + a local graph), and publish it
with Quartz.

## First-time setup (~15 min)

```bash
# 1. Get Quartz (a separate clone; keep it outside this repo or as a sibling)
git clone https://github.com/jackyzha0/quartz.git ~/simulator-quartz
cd ~/simulator-quartz && npm i

# 2. Point Quartz at THIS vault (symlink content/ → this repo's content)
rm -rf content && ln -s "$(git -C /path/to/ns-simulator-prod/ns-simulator-prod/ns-simulator-docs rev-parse --show-toplevel)/ns-simulator-docs/knowledge-base/content" content
#   (or just copy: cp -R .../knowledge-base/content/* content/)

# 3. Preview locally
npx quartz build --serve      # http://localhost:8080

# 4. Deploy free to GitHub Pages
#   Follow https://quartz.jzhao.xyz/hosting - add the GitHub Action, enable Pages.
#   Every push rebuilds the site.
```

In `quartz.config.ts` keep the defaults on (Wikilinks, Backlinks, Graph, Explorer,
full-text Search, dark mode). That's all the graph/`[[ ]]` behavior sketched in the
notes - no extra config needed.

> Prefer authoring in **Obsidian**: open `content/` as a vault. Use the "Templates"
> core plugin pointed at `content/meta/templates/` so a new note starts from the
> right shape.

## How the vault is organized

| Folder | What lives here | Note type |
|--------|-----------------|-----------|
| `content/index.md` | Home + the 3 learning paths | landing |
| `content/learn/` | The curriculum - `M00…M15` + capstone | **module** |
| `content/problems/` | Teaching vehicles - `P01…P13` | **problem** |
| `content/concepts/` | Atomic ideas, one per note, by cluster | **concept (zettel)** |
| `content/maps/` | MOCs - the entry hubs / concept trees | **moc** |
| `content/reference/` | Pointers into the canonical `specs/` (don't duplicate) | reference |
| `content/decisions/` | Pointers into `design-decisions/` (ADRs) | reference |
| `content/meta/` | Templates + this contribution guide | meta |

## The linking model (what makes the graph useful)

- A **module** links *down* to the [[concepts]] it teaches, *sideways* to its
  **problem**, and *out* to the **reference spec**.
- A **problem** links to the concepts it exercises + the modules that use it.
- A **concept** is atomic, links to other concepts in **dependency chains**
  (`[[A]] → [[B]]`), and rolls *up* to a **MOC**.
- A **MOC** is a curated hub of `[[links]]` - the front door for a topic.

## Authoring rules

1. **One idea per concept note.** If a note needs "and", split it.
2. **Link, don't repeat.** Point at the canonical spec; never copy engine details.
3. **Every note earns a link.** New notes must connect to at least one MOC + one
   neighbour, or they get lost in the graph.
4. **Titles are claims,** not topics: "Queue saturation precedes CPU saturation",
   not "Queues".
5. Start new notes from `content/meta/templates/`.

See `content/meta/templates/*` for the four note shapes.

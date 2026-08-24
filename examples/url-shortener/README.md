# URL Shortener - testable example

Three files that form a complete, validated question you can grade yourself:

| File | What it is |
|------|-----------|
| `question.json` | The **QuestionPackage** (paste into `initial_game_state`, or load locally). |
| `reference-topology.json` | A **correct** design (reads through a cache) - should **pass**. |
| `gamed-topology.json` | A **gamed** design (no cache; reads hit the store) - should **fail p99**. |

The question grades on 5 axes: **structural** (has LB, single source), **semantic**
(`storageFit` point-lookup - a `relational-db` hard-fails), **simulation**
(`p99 < 100ms` under an injected 99:1 read/write load), **justification**
(`why-store`), and **budget** (`nodes ≤ 8`).

---

## Test it in the app (full pass, incl. justification)

1. `npm run dev:web` → open `http://localhost:5173`.
2. Question tab → **"Load question (.json)…"** → pick `question.json`.
3. Build the reference design on the canvas: **client/LB → service → cache → KV store**,
   with reads routed through the cache. (Or, to just verify grading, the reference
   topology is `reference-topology.json`.)
4. In the brief, answer **"Why this store type…"** - e.g.
   *"A KV store handles the 200000 rps point-lookups in O(1), but we lose ad-hoc joins."*
   (names the placed `kv-store` ✓, cites `200000` ✓, states a tradeoff ✓ → **consistent**.)
5. **Submit** → all rows green.

Remove the cache and re-run → the **p99 row fails** (the store saturates) - the
reinforcing loop.

---

## Test it via the CLI

`sim` is an npm script (`"sim": "tsx src/cli/index.ts"`), not a global binary -
run it from the **repo root** via `npx tsx` (or `npm run sim -- …`):

```bash
# from the repo root (ns-simulator-prod/ns-simulator-prod)
npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/url-shortener/question.json \
  ns-simulator-docs/examples/url-shortener/reference-topology.json

npx tsx src/cli/index.ts evaluate question \
  ns-simulator-docs/examples/url-shortener/question.json \
  ns-simulator-docs/examples/url-shortener/gamed-topology.json
```

> Optional global alias: `alias sim='npx tsx /ABSOLUTE/PATH/TO/src/cli/index.ts'`
> (then pass absolute paths to the JSON files).

### Expected results

**Reference** - every auto-gradeable row passes:
```
PASS  structural.has-lb
PASS  structural.single-source
PASS  semantic.store-fits-point-lookup
FAIL  justify.why-store        ← expected: the CLI captures no answers (answer it in-app)
PASS  budget                   ← 4 nodes ≤ cap 8
PASS  case.peak.simulation.p99 ← ~8 ms
PASS  case.peak.invariant.no-invariants
```

**Gamed (no cache)** - additionally fails p99:
```
FAIL  case.peak.simulation.p99  → "actual 1003.52 does not satisfy summary.latency.p99 < 100"
FAIL  justify.why-store         ← same CLI caveat
```

> **CLI caveat.** `justify` prompts are answered **in-app**; the CLI passes no
> answers, so `justify.why-store` always shows *"No justification provided"* and the
> status reads `failed` even for a perfect topology. Ignore that one row for
> CLI **topology** testing - the reference passes all structural/semantic/budget/
> simulation checks; the gamed design additionally fails p99. (This is the
> documented CLI-vs-in-app behavior - see the reference manual §6.3.)

---

## Try the hard-fails yourself

- **Swap the KV store for a `relational-db`** in `reference-topology.json` →
  `storageFit` **hard-fails** (*"relational-db is an anti-pattern for a point-lookup workload"*), zeroing the design.
- **Add 6 more nodes** → the **budget** row fails (`nodes budget exceeded: … > cap 8`).
- **Route reads to the store instead of the cache** (delete the cache) → **p99** fails.

Each is a different axis catching a different way to game the question.

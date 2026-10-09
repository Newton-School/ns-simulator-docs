# TopologyJSON - Import, Export and the JSON Viewer

**TopologyJSON** is the simulator's design document: every component, connection, location
box, workload and global setting as one JSON file. It is the format the engine runs, the
format the [sim cli](sim-cli.md) reads, and a lossless view of the canvas: exporting a design
and importing it again gives back the same design.

Everything lives in the header's **JSON** menu (next to Open / Save, which still handle the
app's own canvas file):

| Menu item | What it does |
|---|---|
| **Show JSON viewer** / **Hide JSON viewer** | Opens the viewer in the right panel (the **JSON** tab beside the Inspector) |
| **Import JSON (file or paste)...** | Loads a TopologyJSON (or a canvas file) from a file or pasted text |
| **Download TopologyJSON** | Saves the current design as a `.json` file |
| **Copy TopologyJSON** | Copies it to the clipboard |

Import is hidden where loading another design is not allowed, and export where exporting is
not allowed (for example a graded assignment).

---

## Exporting

Download or Copy writes the design as the engine will see it: nodes with their resolved
configuration, edges with their properties, `locations` for Region / AZ / Subnet boxes and
each node's `placement`, the workload and `global`. Canvas positions are included so a
re-import keeps your layout.

Practice (connector) mode is the one place the export and the run differ on purpose: the file
keeps your edges' settings as you set them, while the run uses a copy with edge physics
stripped (no latency, protocol overhead, bandwidth limit or loss). That keeps export, then
import, lossless.

Use an exported file with the sim cli:

```bash
sim validate my-design.json
sim run my-design.json --live
sim compare before.json after.json
```

## Importing

Choose a file or paste JSON, then **Import**. Loading asks before discarding unsaved changes.

- **Hard errors** stop the import and nothing changes on the canvas: text that is not JSON,
  the wrong shape, duplicate node ids, connections to nodes that do not exist. Each error is
  listed with its location in the document.
- **Problems that would block a Run** do not stop the import (a missing traffic source, a
  synchronous cycle, ...). The design is loaded and the dialog lists them under **Fix these
  before running**, so a work-in-progress export can always be re-imported and fixed on the
  canvas.
- **Warnings** (advice; the design runs) are listed too.
- **No positions?** A hand-written or generated document without node positions is laid out
  automatically (a layered layout, sources first, inside each container), and the summary says
  so.
- **Builder policy.** On a question with a builder policy, anything the import brings in that
  breaks the policy is kept on the canvas and listed with its fix; grading will fail the
  builder-policy check until it is fixed.

## The JSON viewer

The viewer shows the whole design as a searchable tree (nodes, edges, workload and global
expanded by default).

- **Selection is linked both ways.** Selecting a node or connection on the canvas reveals it in
  the tree; selecting a component or connection row selects it on the canvas.
- **Simple values edit in place.** Edit a number, string or switch and the change is applied
  to the canvas, then the tree is rebuilt from it. A value the design cannot take is refused
  with a message (for example "Enter a number.").
- **Derived values are read-only.** On nodes sized by an instance type, `queue.workers` and
  `queue.capacity` (and `resources.workersPerInstance` / `queueSlots`) are derived from the
  instance, so the viewer shows them read-only with the reason. Change the instance type or
  count instead.
- The viewer also has Import, Download and Copy shortcuts.

## What TopologyJSON does not store

- Edge routing geometry (bends, waypoints): edges are drawn between their endpoints.
- Run results: export a run's output with `sim run --json` instead.

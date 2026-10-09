# Student Guide - Solving a System Design Question

This guide walks you through one full loop: read the brief, build a graph, run the
simulation, read the bottlenecks, tune, and iterate until you pass. **You are
designing an architecture - placing, connecting, and sizing components - not writing
code.**

---

## 1. Read the constraints (the brief)

The brief has five parts. Read them in this order:

1. **Scenario** - the domain and role (e.g. "you are the architect for a URL
   shortener").
2. **Functional requirements** - the *paths* traffic must take (a write path to a
   store, a read path that returns fast). Each one usually maps to a component or a
   connection you must place.
3. **Non-functional targets** - the *numbers* you will be graded on (`p99 < 100 ms`,
   `error rate < 10%`, `throughput >= 2000`). These are the rubric.
4. **Scale** - the real-world size (e.g. 200,000 RPS at 99:1 read/write). The
   simulation runs a smaller, representative load, but the **ratio** is what forces
   your design.
5. **Budget** (if shown) - a cost cap. Over-provisioning to brute-force a metric will
   blow the budget.

> Tip: the workload character is *shown, not told*. A 99:1 read ratio with a p99
> latency target is the engine telling you "uncached reads will saturate your store -
> add a cache."

## 2. Build the initial graph

1. Open the **Component Library** (left rail) and drag nodes onto the canvas.
2. Start with a **Client** (the traffic source), then the entry point (usually a
   **Load Balancer**), your **service**, and your **data stores**.
3. Connect them by dragging from one node's handle to the next.
4. For read/write questions, use **conditional edges** so reads and writes take
   different paths (e.g. reads → cache, writes → store).

## 3. Run the simulation

1. Click **Run**. The Workload popover shows the **Source** (must be your Client),
   pattern, and base RPS.
2. Click **Start Simulation**. Watch traffic flow along the edges. The **Speed** control
   next to Run paces the run (0.5x to 10x of simulated time, or Max, the default); speed never
   changes the results.
3. Open the **Run Inspector** (right panel) to see per-node metrics, and the Results tray
   for the run as a whole.

To see what happened to one request, open **Traces > Debug request**, or search the
**Event Log** tab (see [Request debugger and Event Log](request-debugger-and-event-log.md)). To
ask the same questions by typing, open the terminal with Ctrl+\` (see
[The in-app terminal](in-app-terminal.md)).

## 4. Read the bottlenecks

Look for the node that is the constraint:

- **Utilization near 100%** → that node is saturated; it cannot keep up.
- **Rejected / Timed-out > 0** → requests are being dropped there.
- **p99 spiking** → a queue is backing up somewhere upstream of the metric.

The classic pattern: your **store** shows 100% utilization and high rejects while the
service is fine → the store is your bottleneck.

## 5. Tune node & edge configs

Select a node → **Config** tab. Common levers:

- **Workers** - concurrency of the node's pool. More workers = more parallel
  requests, but higher cost.
- **Processing time** - service time per request.
- **Replicas** - horizontal scale.
- On edges: latency, bandwidth, and the **routing condition**.

Two ways to fix a saturated store:
- **Scale it** (more workers/replicas) - fast, but costs budget and often isn't the
  intended lesson.
- **Shield it** (add a cache on the read path) - the usually-correct answer for
  read-heavy workloads.

## 6. Iterate to the solution

Re-run after each change. Repeat until:
- All **non-functional targets** are green in the rubric,
- All **structural rules** and **semantic criteria** pass,
- You are **within budget**.

Then **Submit**.

---

## Known rough edges in V1 (and how we'll smooth them)

These are real friction points a student may hit. Where a fix ships in V1 it's marked
**[fixed in V1]**; otherwise it's a documented workaround with a V2 plan.

1. **"Why did selecting a Load Balancer as the source give me zero traffic?"**
   Load balancers are **not** valid traffic sources. **[fixed in V1]** the Source
   dropdown now only lists **Client** nodes. Always start your graph with a Client.

2. **"The rubric won't pass even though my latency looks fine."**
   The injected workload (RPS, read/write mix, seed) is **owned by the question**, not
   your canvas scenario. Your local dry-run settings don't change the grade. Build for
   the ratio in the brief, not the number in your Run popover.

3. **"I connected my Client straight to the database and nothing warned me."**
   Drawing refuses only connections that can never work (traffic into a source, out of a
   sink, a second connection between the same pair) and says why. The **Design checks** chip
   in the header lists architectural anti-patterns in your current design (single points of
   failure, missing load balancers, shared databases, ...). Hard structural errors still
   surface when you Run, as readable messages. Treat the brief's functional requirements as
   your checklist.

4. **"p99 shows ~1000 ms no matter how bad my design is."**
   Under heavy saturation the measured p99 plateaus near the request timeout. If your
   design is clearly saturated (high rejects, ~100% utilization), trust the
   **utilization / rejected / throughput** numbers, not just p99.

5. **"There's no box to explain my choices."**
   Correct - the written **justification** feature is **hidden in V1**. You are graded
   purely on the graph and its measured behavior. *V2 will reintroduce a defense step
   with better (non-keyword) grading.*

6. **"I want to compare my design to a known-good one."**
   In standalone/local mode you can load a question and then **Open** a topology from
   the top bar without losing the question - build and test side by side. Outside a graded
   attempt you can also export both as TopologyJSON and run `sim compare a.json b.json` on the
   same seed (see [The sim cli](sim-cli.md)).

### What to fix *now* so V1 is workable
- Always begin with a **Client** source (prevents the #1 zero-traffic confusion).
- Read the **Run Inspector**, not just the pass/fail chip - it tells you *where* the
  bottleneck is.
- If a metric won't move, check whether you're **scaling the wrong node** (fix the
  bottleneck the inspector points at, not the one you assume).

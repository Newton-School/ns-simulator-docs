# The Request Debugger and the Event Log

Aggregate results tell you *that* something went wrong; these two tools tell you *what
happened to one request* and *what the engine did, event by event*. Both open from the
Results tray after a run, and both read what the run actually recorded. Values the run did
not record are shown as "not recorded", never estimated.

---

## The request debugger

**Open it:** Results tray > **Traces** tab > pick a request > **Debug request**. You can also
reach it from an event in the Event Log (event detail > **Debug request**).

The debugger steps through the recorded lifecycle of one traced request: each hop's edge
transit, queue wait, service and the admission decision at every node it visited. Controls:
**First step**, previous, next, **Play** / **Pause**, and **Jump to rejection** (or timeout)
for a request that failed. The step counter shows where you are.

**Lifecycle views** (the same steps, drawn five ways; the debugger remembers your choice):

| View | Best for |
|---|---|
| **Rail** | The request as a line of stops, one per hop |
| **Sequence** | A sequence diagram between nodes |
| **Stack Trace** | Nested calls, like a program's stack |
| **State Machine** | The request's state transitions (queued, processing, forwarded, ...) |
| **Filmstrip** | One frame per step |

**Analysis views:**

- **Intake Lens** - at the selected node, the admission checks in the order the engine runs
  them (security, admission traits such as rate limiting, bulkheads and load shedding, then the
  G/G/c/K check), with the recorded numbers: busy workers out of c, queued, in system out of K,
  and which check decided.
- **Path Diff** - the path the request actually took against the path the design would be
  expected to send it on. The expected path is walked on the *current* canvas, so if you edited
  the design after the run you get a warning that it changed.

**On the canvas** the debugger dims nodes off the request's path, rings the current node (and
the rejecting one), and moves a packet dot along the path as you step. A mini-map shows the
request's hop trail.

### Which requests are traced

Only a sample of requests is traced: **1% by default** (`global.traceSampleRate` in the
TopologyJSON). For sampled requests the tracer also keeps one admission record per node visit,
which is what the Intake Lens and the terminal's `why-rejected` read. At the default rate this
has no measurable cost; at 100% a run is about 6-12% slower. Short or low-traffic runs may trace
nothing, and the Traces tab says so.

## The Event Log

**Open it:** Results tray > **Event Log** tab. It replaces the old basic paged list in the
Traffic tab.

The Event Log shows the engine's canonical event stream: arrivals, admissions, completions,
rejections, timeouts, faults and so on, in sequence order. Five views:

| View | What it shows |
|---|---|
| **Table** | Every event in sequence order |
| **Requests** | Events grouped by request, with its hop trail |
| **Nodes** | Events grouped by node, with sortable per-node columns |
| **Incidents** | Failures, rejections and timeouts, worst first |
| **Waterfall** | One swim lane per node over simulated time |

Lists are windowed, so 25,000 rows stay responsive. Selecting an event opens its detail, with
**Show on canvas** and (for a traced request) **Debug request**.

### The coverage line

A normal run keeps the **first 25,000 events**. The line above the views says either that the
log holds all the events the run produced, or that it is partial (the first N of M events, up
to a given simulated time). When it is partial, every view, filter and count covers only that
part of the run; the aggregate metrics in the other tabs still cover the whole run.

### The query filter

The filter bar takes a small query language (the terminal's `show events --where` uses the
same one):

| Term | Matches |
|---|---|
| `request:<id>` (or `req:`) | One request |
| `node:<id or label>` | Events at a node; quote labels with spaces: `node:"Payment API"` |
| `edge:<id>` | Events on an edge |
| `status:<level>` | `info`, `success`, `timeout`, `rejected` or `failure` (aliases: `ok`, `failed`, ...) |
| `type:<event-type>` | An event type; also prefix-matches on its own (`type:request` matches every `request-*` type) |
| `reason:<code>` | A rejection or failure reason, e.g. `reason:connection_refused` |
| a bare word | Substring of the message, ids, node label or reason |

Combine terms with `AND` (or just a space), `OR` and `NOT` (or a leading `-`), and group with
parentheses. `AND` binds tighter than `OR`. A trailing `*` makes a value a prefix match.

```
status:rejected OR status:timeout
node:orders-db AND reason:capacity*
(node:api OR node:gateway) -status:success
```

## Related tools

- The [in-app terminal](in-app-terminal.md) answers the same questions as text:
  `show trace <id>`, `why-rejected [<id>]`, `show events --where "..."`, `diagnose <node>`.
- The **Failures** tab groups failures by cause and location, and names the zone when a
  Region / AZ / Subnet outage caused them.

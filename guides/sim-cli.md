# The sim cli - Running the Simulator from a Terminal

The **sim cli** runs the same discrete-event engine the app uses, from a terminal, on a
TopologyJSON file. Use it to run a design without opening the app, to check a design in
CI, to compare two designs on the same seed, and to grade a question headlessly.

The executable is `sim`. In a checkout of the simulator repo:

```bash
npm link                      # once: puts `sim` on your PATH (bin/sim.mjs)
sim --help                    # the command list
npm run sim -- run file.json  # the same thing without linking
```

`sim` runs the TypeScript entry through `tsx`, so there is no build step. Every command that
prints a report also accepts `--json`. `sim <command> --help` prints the exact options; this
guide covers what each command is for.

Where do topology files come from? Export one from the app with **JSON > Download
TopologyJSON** (see [TopologyJSON import and export](topology-json-import-export.md)), or write one
by hand.

---

## The commands

| Command | What it does |
|---|---|
| `sim run <topology.json>` | Simulates the topology and prints a summary, latency percentiles and decomposition, the failure locus, per-node metrics, SLO breaches and Little's Law checks. |
| `sim validate <topology.json>` | Checks the file against the schema and semantic rules; prints each error with its JSON path and each warning. |
| `sim lint <topology.json>` | Runs the anti-pattern detector (single points of failure, sync calls to slow dependencies, shared databases, missing load balancers, cache in front of a load balancer, queues without consumers, excessive retries). No simulation. |
| `sim cost <topology.json>` | Infrastructure cost in USD per hour, per component and in total. |
| `sim compare <a.json> <b.json>` | Simulates both designs with the same seed and prints a metric-by-metric diff. |
| `sim shell <topology.json>` | The in-app terminal's commands over a file (interactive, or `--exec` for a script). |
| `sim evaluate ...` / `sim grade <question> <topology>` | Headless suites, scenario batches and question grading (the evaluation contracts). |

`sim <topology.json>` on its own is shorthand for `sim run <topology.json>`.

### sim run

```bash
sim run order-topology.json
sim run order-topology.json --live
sim run order-topology.json --json | jq '.summary'
sim run order-topology.json --verdict --seed 7 --duration-ms 30000
```

- `--live` draws a live per-node table while the engine runs. Press `q` to stop early and
  print the results so far, `p` to pause and resume. When stderr is not a terminal it falls
  back to plain progress lines.
- `--json` prints the full `SimulationOutput`; `--verdict` prints the `SimulationVerdict`;
  `--output <file>` writes either to a file.
- `--seed` and `--duration-ms` override `global.seed` and `global.simulationDuration`. A run
  is deterministic for a given seed, so re-running with the same seed reproduces it exactly.

### sim validate and sim lint

```bash
sim validate design.json          # exit 0 valid, 2 errors, 1 unreadable file
sim lint design.json              # exit 2 on a critical finding, 0 otherwise
```

Lint findings name the nodes and edges involved and suggest a fix. Warnings alone pass, so
`sim lint` can gate a CI job on critical findings only.

### sim cost

```bash
sim cost design.json              # pre-run: traffic-dependent lines are estimates, marked ~
sim cost design.json --run        # simulate first, then price consumption and egress from the run
```

Provisioned lines come from the instance catalog, consumption lines from per-request
pricing, egress from per-GB pricing. Nodes without an instance type show as unpriced. There
is one built-in price catalog (AWS-proportional), so there is no per-cloud switch.

### sim compare

```bash
sim compare naive.json fixed.json
sim compare naive.json fixed.json --seed 42 --json
```

Both designs run on the same seed (design A's `global.seed` unless `--seed` is given). The
report covers latency percentiles, throughput, error rate, successful requests and cost, then
per-component utilization for components the two designs share, and a one-line summary.
Differences within 1% are reported as ties; deltas are B relative to A. `--mode auto` (the
default) switches to the analytic model for very heavy load; `--mode discrete` forces the
event simulation.

### sim shell

```bash
sim shell design.json
sim shell design.json --exec "show nodes; select lb; show interfaces"
sim shell design.json --exec "run; show bottleneck; why-rejected"
```

The same command registry, modes and output as the app's terminal (see
[The in-app terminal](in-app-terminal.md)). The file is never rewritten, so config mode and
the live run controls (pause, step, speed) are app-only: `run` simulates to completion and
the show commands then read its output. With `--exec`, the exit code is 2 if any command
failed.

### sim evaluate and sim grade

```bash
sim grade question.json student-topology.json
sim evaluate suite.json --rubric rubric.json
sim evaluate topology.json --scenarios scenarios.json
sim evaluate question-batch batch.json --require-pass
```

These print the versioned evaluation contracts the platform consumes. Invalid student input
becomes an `invalid_submission` contract rather than a crash. See the
[Fresh Author Start Here](fresh-author-start-here.md) guide for the question-bank workflow.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (lint: no critical findings; question: passed) |
| 1 | Usage or input error (unknown flag, missing or unreadable file, invalid topology) |
| 2 | Check failed (lint found a critical issue, validate found errors, grading failed, a `shell --exec` command failed) |
| 3 | Invalid submission contract (`evaluate question` / `question-batch`) |
| 4 | Evaluation error contract (`evaluate question` / `question-batch`) |

## What the sim cli does not do

- There is no `sim show` or `sim inspect` command; `sim shell <file> --exec "show topology"`
  and `--exec "show config running <node>"` print the same information.
- Chaos experiments run in the app's Run dialog, not from a `sim` command (see
  [Chaos experiments](chaos-experiments.md)).
- The cli never edits the topology file.

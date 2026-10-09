# The In-App Terminal

The terminal is a command line inside the app for inspecting a design, changing settings
and controlling a run without clicking through panels. It reads the same data as the
canvas and the Results tray, and every edit goes through the same validation and undo
history as the properties panel.

**Open it:** press **Ctrl+\`** (or use the Terminal tab in the bottom dock, next to
Results). Type `help` for the commands available where you are, `<command> ?` for help on
one family, and press **Tab** to complete commands, node ids and field names.

The same commands also run outside the app, over a topology file, with
`sim shell <topology.json>` (see [The sim cli](sim-cli.md)).

---

## Modes

The prompt tells you where you are. Each mode offers different commands.

| Prompt | Mode | How you get there |
|---|---|---|
| `sim>` | The whole design | The starting mode; `end` returns here from anywhere |
| `node(api)>` | One node | `select api` |
| `node(api)(config)#` | Editing that node | `configure terminal` (or `conf t`) in node mode |
| `node(api)(config-port:1)#` | Editing one of its connections | `interface port 1` in config mode |
| `sim(runtime)#` | A run in progress or just finished | `run` (enters it automatically) or `runtime` |

`exit` (or `back`) goes up one level.

## Looking at the design

```
sim> show topology          # summary and node table
sim> show nodes             # every node with type, derived c/K and live status
sim> show edges             # protocol, path type, latency, bandwidth, measured throughput
sim> show config running    # the full engine config (optionally: show config running <node>)
sim> show config diff       # what changed since the design was loaded or saved
sim> ping lb orders-db      # is orders-db reachable from lb? hop count and configured latency
sim> traceroute lb orders-db
sim> validate               # same validator as Run and `sim validate`
sim> lint                   # same report as `sim lint`
sim> cost                   # same report as `sim cost` (measured after a run)
```

In node mode, `show queue`, `show config`, `show ports`, `show interfaces` and `show metrics`
describe the selected node. Some node types also answer familiar commands as aliases over the
simulator's real data: `psql`-style `\conninfo` and `select *` on databases, `redis-cli`-style
`info`, `slowlog` and `client list` on caches, IOS-style `show ip interface brief` on
networking nodes, and `kafka-topics --list | --describe` on brokers. When a command asks about
something the simulator does not model (for example `\dt`, SQL tables), it says so and points
at what is modelled instead.

## Changing settings

```
sim> select email-svc
node(email-svc)> configure terminal
node(email-svc)(config)# set <field> <value>
node(email-svc)(config)# no <field>          # back to the default
node(email-svc)(config)# interface port 1     # edit its first connection like the edge inspector
node(email-svc)(config-port:1)# set protocol grpc
sim> undo                                     # same history as Ctrl+Z
```

A few things the terminal deliberately does not do:

- `set workers` and `set capacity` explain how c and K are derived from the instance instead of
  setting anything (concurrency is derived, not a free dial).
- "Port N" is the node's Nth connection, not engine port state. `shutdown`, per-port
  `rate-limit` and per-port `health-check` are not simulated and say what to use instead.
- Builder policy is enforced here too: on a question that locks created definitions, the
  locked fields are read-only in `config` mode as well.

## Running and diagnosing

```
sim> run                     # starts a simulation of the current design, enters runtime mode
sim(runtime)# pause | resume | stop
sim(runtime)# step 50        # while paused: process 50 more events
sim(runtime)# speed 2        # playback speed: 0.5, 1, 2, 5, 10, 100 or max
sim(runtime)# show status    # every node: status, occupancy, queue, RPS, error rate
sim(runtime)# show bottleneck
sim(runtime)# show throughput
sim(runtime)# diagnose orders-db      # saturation, queue, failures, upstream pressure, likely cause
sim(runtime)# why-rejected            # the admission check (c, queue, K) that rejected the latest rejected request
sim(runtime)# explain capacity orders-db
sim(runtime)# show cascade            # the causal failure graph as an indented tree
sim(runtime)# compare api-1 api-2     # two nodes side by side
```

`stop` keeps the partial results, measured over the simulated time the run covered.

`why-rejected` uses the request debugger's exact traced admission record when one exists. If
the request was not traced and its events were not retained, it falls back to the nearest
snapshot and says that the answer is approximate.

## Events and traces

```
sim(runtime)# show events --last 20
sim(runtime)# show events --where "status:rejected OR node:api"
sim(runtime)# show trace <requestId>      # one request as a text waterfall: network, queue, service per hop
sim(runtime)# show rejected
sim(runtime)# show timeouts
```

`--where` takes the same query language as the Event Log filter bar (see
[Request debugger and Event Log](request-debugger-and-event-log.md)). A normal run keeps the first
25,000 events, and the command tells you when the log it searched is partial.

## Pipes, watch and history

- `|` pipes output through `grep [-v] [-i] <text>`, `head [N]`, `tail [N]` and `count`, for
  example `show nodes | grep cache`.
- `watch show status` re-runs a show command every interval (default 2 s, `--interval 5s`) and
  updates in place; Ctrl+C stops. `watch` is app-only; in a shell use `sim run --live`.
- `history` lists the commands entered this session; `clear` clears the screen.

# In-App Terminal — Feature Specification

This document describes the features required for the NS Simulator's in-app terminal: a Cisco Packet Tracer-inspired contextual CLI embedded inside the simulator's bottom panel. It is written from a feature perspective: what each capability does, why it exists, how it works internally, what engine data it consumes, and what components it requires to be built.

The terminal was designed through two reference documents: a high-level design document with annotated CLI examples across multiple node types (`hld-simulator-terminal-examples`), and an implementation plan document covering architecture layers, phasing, and the shared CLI strategy (`In-app_Terminal_for_ns-simulator`). This specification consolidates both into feature-level requirements grounded in the current codebase.

---

## Table of Contents

1. [Problem Context](#problem-context)
2. [Feature 1 — Context Mode System](#feature-1--context-mode-system)
3. [Feature 2 — Command Registry & Parser](#feature-2--command-registry--parser)
4. [Feature 3 — Show Commands (Node Inspection)](#feature-3--show-commands-node-inspection)
5. [Feature 4 — Config Mutation Commands](#feature-4--config-mutation-commands)
6. [Feature 5 — Port-Level State Model](#feature-5--port-level-state-model)
7. [Feature 6 — Per-Type Idiomatic CLI](#feature-6--per-type-idiomatic-cli)
8. [Feature 7 — Runtime Simulation Control](#feature-7--runtime-simulation-control)
9. [Feature 8 — Trace & Event Inspection Commands](#feature-8--trace--event-inspection-commands)
10. [Feature 9 — Diagnostic & Pedagogy Commands](#feature-9--diagnostic--pedagogy-commands)
11. [Feature 10 — xterm.js Integration & Terminal Tab](#feature-10--xtermjs-integration--terminal-tab)
12. [Feature 11 — Shared CLI Architecture](#feature-11--shared-cli-architecture)
13. [Relationship to Event Debugger](#relationship-to-event-debugger)
14. [Engine Integration Requirements](#engine-integration-requirements)
15. [Source-to-Feature Map](#source-to-feature-map)

---

## Problem Context

### What exists today

The simulator's interaction model today is entirely graphical:

1. Users drag nodes from the `LibrarySidebar` onto the React Flow canvas.
2. Configuration happens through the right-side `PropertiesPanel` / `PropertiesForm`, which exposes node fields from `fieldConfig`.
3. Simulation is controlled via `SimulationControls` (Run/Pause/Resume/Stop buttons) and the `ScenarioBar`.
4. Results appear in `ResultsTray` as aggregate tables — summary metrics, per-node metrics, health checks.
5. A headless CLI exists at `src/cli/index.ts`: it reads a `TopologyJSON` file, validates it, runs the engine synchronously, streams a progress bar to stderr, and prints formatted results. It supports `--json` and `--output <file>`.

### What's missing

- **No text-based inspection.** The GUI shows aggregate numbers in tables, but there is no way to interrogate a specific node's state in natural system-admin language ("show me the queue depth at payment-svc", "what's the utilization on the gateway"). The `PropertiesPanel` shows configuration, not runtime state.

- **No text-based configuration.** Changing a node's capacity means clicking it, finding the queue section in the properties form, editing the number. There is no way to say `set capacity 200` or `set workers 16` — the kind of interaction that network engineers and backend developers are accustomed to from `psql`, `redis-cli`, `mysql`, or Cisco IOS.

- **No contextual scoping.** The GUI is flat: you click a node to see its properties, click another to see another's. There is no sense of "I'm inside this node, exploring its internals." The terminal's mode system (`sim>` → `node(gateway)>` → `node(gateway)(config)#`) creates a spatial mental model that mirrors how real systems are administered.

- **No live control from text.** During a simulation, the only controls are GUI buttons. There is no way to type `pause`, `speed 2x`, `step 100`, or `show status` while the simulation is running. For users who think in commands rather than clicks, this is a significant gap.

- **No port-level visibility.** The engine models nodes as single-endpoint entities (`GGcKNode` with one queue and one worker pool). Real networking components (load balancers, firewalls, routers) operate on multiple ports with independent connection limits, protocols, and health checks. The terminal introduces the need for port-level state, which doesn't exist in the engine today.

- **No CLI reuse.** The headless CLI (`src/cli/index.ts`) and the in-app terminal should share commands. Today the CLI is a monolithic `main()` function — there is no command registry, no shared parser, no way to reuse `printResults` formatting from the renderer.

### What the reference documents explore

The two reference documents collectively specify 5 architectural layers (Model, Scenario, Runtime, Trace, Pedagogy), 6 context modes, per-type idiomatic command sets for 4+ node families, a shared CLI registry, and a 5-phase implementation plan. Each feature is documented below independently of which source introduced it.

---

## Feature 1 — Context Mode System

### What it does

A hierarchical mode state machine that determines what prompt the user sees, what commands are available, and what entity is in scope. When the user types a command, the terminal resolves it against the current mode's command set. Modes form a stack — entering a deeper mode pushes the stack, exiting pops it.

### Why it exists

Real system administration is contextual. In Cisco IOS, you `enable` to enter privileged mode, then `configure terminal` to enter global config, then `interface GigabitEthernet0/1` to configure a specific port. In `psql`, connecting to a database scopes all subsequent queries to that database. The terminal mirrors this pattern so users build the mental model of "I am inside this node, looking at its internals" rather than "I clicked a row in a table."

### How it works internally

**Modes:**

| Mode | Prompt | Available commands | Scope |
|---|---|---|---|
| Simulation root | `sim>` | `show topology`, `show nodes`, `show edges`, `select <nodeId>`, `run`, `validate`, `help` | Global — entire topology |
| Node context | `node(gateway)>` | `show status`, `show queue`, `show connections`, `show config`, `show ports`, `show metrics`, `configure terminal`, `exit`, `help` | Single node — reads runtime state and config |
| Node config | `node(gateway)(config)#` | `set capacity`, `set workers`, `set queue-discipline`, `set timeout`, `set distribution`, `no <setting>`, `interface port <N>`, `exit`, `end` | Single node — writes to topology store |
| Port config | `node(gateway)(config-port:443)#` | `set protocol`, `set max-connections`, `set rate-limit`, `health-check`, `shutdown`, `no shutdown`, `exit` | Single port on a node |
| Runtime | `sim(runtime)#` | `pause`, `resume`, `step`, `speed`, `stop`, `status`, `show status`, `show events`, `show trace`, `show rejected`, `diagnose`, `exit` | Active simulation |

**State representation:**

```typescript
interface TerminalContext {
  mode: 'sim' | 'node' | 'node-config' | 'port-config' | 'runtime';
  nodeId?: string;        // set in node, node-config, port-config modes
  portIndex?: number;     // set in port-config mode only
  history: TerminalContext[];  // stack of previous contexts for back/exit
}
```

**Transitions:**

```
sim> ──select gateway──→ node(gateway)>
                             │
                    configure terminal
                             │
                             ▼
                    node(gateway)(config)#
                             │
                    interface port 443
                             │
                             ▼
                    node(gateway)(config-port:443)#
```

`exit` pops one level (port-config → node-config → node → sim). `end` returns directly to `sim>` from any depth, clearing the stack. `back` is an alias for `exit`.

**Runtime mode entry:** When a simulation starts (via `run` from `sim>` or via the GUI Run button), the terminal auto-transitions to `sim(runtime)#`. When the simulation completes or is stopped, the terminal returns to `sim>`. If the user manually types `exit` during a running simulation, the terminal returns to `sim>` but the simulation keeps running — the mode change only affects what commands are available, not the simulation lifecycle.

**Invalid transitions:** Typing a mode-specific command in the wrong mode prints an error: `"Command 'set capacity' is only available in config mode. Type 'configure terminal' to enter config mode."` The error is contextual — it doesn't just say "unknown command" but tells the user how to reach the right mode.

### What components it requires

- **Renderer-side:** A `TerminalContext` class or hook that manages the mode stack, validates transitions, and provides the current prompt string. Must be serializable (for persistence across panel collapse/expand) and observable (for React re-renders when the prompt changes).

### Explored in

HLD examples doc (all walkthrough sections), Implementation plan doc (Model layer, Phase 1).

---

## Feature 2 — Command Registry & Parser

### What it does

A shared registry where commands are defined once and resolved at runtime based on the current mode. The registry provides tab completion, help text generation, and mode-aware command resolution. A parser tokenizes user input, matches it against registered commands, and dispatches execution.

### Why it exists

The terminal has 50+ commands across 5 modes. Without a registry, command resolution would be a giant switch statement. The registry also enables the shared CLI architecture ([Feature 11](#feature-11--shared-cli-architecture)) — the same command definitions used in the in-app terminal are imported by the headless `nssim` CLI.

### How it works internally

**Command definition:**

```typescript
interface CommandDefinition {
  /** Primary command name, e.g., 'show status'. */
  name: string;

  /** Alternative names, e.g., ['sh status'] for Cisco-style abbreviation. */
  aliases: string[];

  /** Which modes this command is available in. */
  modes: TerminalContext['mode'][];

  /** Argument specification for parsing and validation. */
  args: ArgSpec[];

  /** Execute the command. Returns structured output. */
  execute: (
    ctx: TerminalContext,
    args: ParsedArgs,
    deps: CommandDeps
  ) => CommandResult;

  /** Tab completion provider. */
  completions?: (
    partial: string,
    ctx: TerminalContext,
    deps: CommandDeps
  ) => string[];

  /** One-line description for help output. */
  description: string;

  /** Detailed help text shown by 'help <command>'. */
  helpText?: string;
}
```

**Dependency injection:**

```typescript
interface CommandDeps {
  /** Read/write access to the topology in the Zustand store. */
  topology: {
    getNodes: () => ComponentNode[];
    getEdges: () => EdgeDefinition[];
    getNode: (id: string) => ComponentNode | null;
    updateNode: (id: string, patch: Partial<ComponentNode>) => void;
    markDirty: () => void;
  };

  /** Simulation state and controls from useSimulation hook. */
  simulation: {
    state: SimulationState;
    controls: SimulationControls;
  };

  /** Debug event data (when available from #38). */
  debug: {
    events: DebugEvent[];
    lifecycle: RequestLifecycle | null;
    snapshots: TimeSeriesSnapshot[];
  };

  /** Terminal context for mode transitions. */
  terminal: {
    context: TerminalContext;
    pushMode: (mode: TerminalContext) => void;
    popMode: () => void;
    resetToRoot: () => void;
  };
}
```

This interface is the key to portability. In the renderer, `CommandDeps` is wired to the Zustand store, `useSimulation` hook, and React context. In the headless CLI, `CommandDeps` wraps direct engine access and file I/O. The commands themselves don't care which environment they're in.

**Registry:**

```typescript
interface CommandRegistry {
  register(cmd: CommandDefinition): void;
  registerBatch(cmds: CommandDefinition[]): void;

  /** Resolve input string to a command in the current mode. */
  resolve(input: string, mode: TerminalContext['mode']): {
    command: CommandDefinition;
    args: ParsedArgs;
  } | null;

  /** Get all commands available in a mode (for help output). */
  commandsForMode(mode: TerminalContext['mode']): CommandDefinition[];

  /** Get tab completions for partial input. */
  completionsFor(
    partial: string,
    mode: TerminalContext['mode'],
    deps: CommandDeps
  ): string[];
}
```

**Parser behavior:**

The parser is intentionally simple — not a full shell:

1. Split input on whitespace. First token(s) are the command name (supports multi-word commands like `show status`).
2. Remaining tokens are positional or flag arguments, matched against `ArgSpec[]`.
3. `?` suffix on any partial input triggers inline help: `show ?` lists all `show` subcommands in the current mode.
4. `|` pipes output to a simple filter: `show events | grep rejected` filters output lines containing "rejected". Only `grep` and `head` are supported as pipe targets.
5. Up/down arrow navigates command history (stored per session, not persisted).
6. Tab triggers completion from the registry.

**Command result:**

```typescript
type CommandResult =
  | { type: 'text'; content: string }        // Plain text or ANSI-colored output
  | { type: 'table'; headers: string[]; rows: string[][] }  // Tabular data
  | { type: 'error'; message: string }       // Error message
  | { type: 'mode-change'; newContext: TerminalContext }     // Triggers mode transition
  | { type: 'silent' }                       // No output (e.g., 'clear')
```

### What components it requires

- **Shared layer:** A `CommandRegistry` class and `CommandDefinition` interface in `src/shared/commands/`. Must be environment-agnostic — no React imports, no DOM access, no Node.js-specific APIs.
- **Renderer-side:** A `useCommandParser` hook that connects the registry to the xterm.js input stream.
- **CLI-side:** An adapter in `src/cli/` that creates `CommandDeps` from direct engine access.

### Explored in

Implementation plan doc (Architecture — Command Registry, Phase 1), HLD doc (command syntax throughout).

---

## Feature 3 — Show Commands (Node Inspection)

### What it does

A family of read-only commands that inspect a node's runtime state, configuration, and relationships. Available in `node>` mode (scoped to the selected node) and partially in `sim>` mode (topology-wide views).

### Why it exists

The `PropertiesPanel` shows editable configuration. The `ResultsTray` shows aggregate post-run metrics. Neither answers real-time questions like "how full is the queue at payment-svc right now?" or "what's the utilization trending at?" Show commands fill this gap with on-demand, node-scoped state inspection.

### How it works internally

**Node-scoped commands (in `node>` mode):**

| Command | Data source | Output |
|---|---|---|
| `show status` | `TimeSeriesSnapshot.perNode[nodeId]` | Status indicator (idle/busy/saturated/failed), uptime, utilization %, queue depth |
| `show queue` | `GGcKNode.getState()` via snapshot | Queue depth, discipline (`fifo`/`lifo`/`priority`/`wfq` from `QueueConfig.discipline`), capacity, current waiters, max observed depth from `NodeMetrics.maxQueueLength` |
| `show connections` | `TimeSeriesSnapshot.perEdge` filtered to edges involving this node | Per-edge active connections, throughput (req/s), latency p50 |
| `show config` | `ComponentNode` from topology store | Full config dump: queue (workers, capacity, discipline), processing (distribution, timeout), resources (cpu, memory, replicas), resilience (circuit breaker, retry, rate limiter, bulkhead), SLO targets, scaling config |
| `show ports` | `PortConfig[]` from `ComponentNode.config.ports` (new, see [Feature 5](#feature-5--port-level-state-model)) | Port table: number, protocol, max connections, active connections, status, health check path |
| `show metrics` | `PerNodeMetrics` from `SimulationOutput` (post-run) or `TimeSeriesSnapshot` (during run) | Throughput, latency percentiles (p50/p90/p95/p99), error rate, total arrivals, total completed, total rejected, total timed out |
| `show interfaces` | `RoutingTable.getOutgoingEdges(nodeId)` + edge configs | IOS-style interface table: edge label, protocol, target node, latency distribution, bandwidth, max concurrent, packet loss rate |

**Topology-scoped commands (in `sim>` mode):**

| Command | Data source | Output |
|---|---|---|
| `show topology` | `TopologyJSON` from store | Summary: node count, edge count, workload source, duration, seed |
| `show nodes` | `TopologyJSON.nodes` | Table: node ID, label, type, category, workers, capacity |
| `show edges` | `TopologyJSON.edges` | Table: edge ID, source → target, protocol, mode, latency type, bandwidth |
| `show config running` | Full `TopologyJSON` | Formatted multi-section config dump (like `show running-config` in IOS) |
| `show config diff` | Current topology vs last-saved topology | Diff output highlighting changed fields (additions in green, removals in red) |

**How `show status` renders:**

```
node(payment-svc)> show status

  Status        : ◉ HOT (utilization 97.2%)
  Active Workers: 8 / 8
  Queue Depth   : 92 / 92 (FULL)
  Total In System: 100 / 100
  Error Rate    : 2.1%
  Throughput    : 487 req/s
  Uptime        : 14.8s / 15.0s sim-time
```

The status indicator uses the same thresholds as the CLI `--live` mode (#84):
- `●` OK: utilization < 60%
- `◐` WARM: 60–85%
- `◉` HOT: 85–95%
- `✗` FAIL: > 95% or status === `'failed'`

**How data flows:** Show commands in `node>` mode read from `TimeSeriesSnapshot` during a running simulation (the latest snapshot from `useSimulation.state.snapshot`) and from `SimulationOutput.perNode` after completion. If no simulation has run, they fall back to static config data (e.g., `show config` always works; `show status` returns "No simulation data — run a simulation first").

### What components it requires

- **Engine-side:** Access to `TimeSeriesSnapshot` (already emitted via `onSnapshot`) and `PerNodeMetrics` (already in `SimulationOutput`). No new engine changes for basic show commands.
- **Shared layer:** Command definitions in `src/shared/commands/show/` with ANSI formatters for table output.
- **Renderer-side:** Connection from `CommandDeps.simulation.state.snapshot` to the show commands.

### Explored in

HLD doc (Model layer — all `show` examples), Implementation plan doc (Phase 2 — Show commands).

---

## Feature 4 — Config Mutation Commands

### What it does

A family of write commands that modify a node's configuration through text, available in `node(config)#` and `node(config-port:N)#` modes. Changes are applied to the Zustand topology store and mark the canvas as dirty (unsaved).

### Why it exists

Graphical configuration through the `PropertiesPanel` requires click-navigate-edit-confirm for every field. Text-based configuration is faster for users who know what they want to change: `set capacity 200` is one command versus 4 clicks. It also enables scriptable topology creation — a sequence of terminal commands can build a topology from scratch, which is valuable for testing and reproducibility.

### How it works internally

**Node config commands (in `node(config)#` mode):**

| Command | Target field | Validation |
|---|---|---|
| `set capacity <N>` | `ComponentNode.queue.capacity` | Must be positive integer, must be ≥ `queue.workers` |
| `set workers <N>` | `ComponentNode.queue.workers` | Must be positive integer, must be ≤ `queue.capacity` |
| `set queue-discipline <fifo\|lifo\|priority\|wfq>` | `ComponentNode.queue.discipline` | Must be one of the 4 valid values |
| `set timeout <ms>` | `ComponentNode.processing.timeout` | Must be positive number |
| `set distribution <type> [params...]` | `ComponentNode.processing.distribution` | Validated against `DistributionConfig` union type |
| `no timeout` | `ComponentNode.processing.timeout` | Resets to `GlobalConfig.defaultTimeout` |
| `no distribution` | `ComponentNode.processing.distribution` | Resets to `{ type: 'constant', value: 10 }` |

**The `no` prefix convention** comes from Cisco IOS — `no shutdown` re-enables an interface, `no ip route` removes a static route. In the simulator, `no <setting>` resets that setting to its default value. This is documented in the help text for each command.

**The `set distribution` command** handles the full `DistributionConfig` union from `src/engine/core/types.ts`:

```
set distribution constant 10
set distribution exponential lambda=0.5
set distribution normal mean=50 stdDev=10
set distribution log-normal mu=3.5 sigma=0.8
set distribution uniform min=5 max=15
```

The parser maps positional and key=value arguments to the corresponding distribution type's parameters. Validation ensures required parameters are present and numeric.

**How mutations are applied:**

```typescript
// Inside the 'set capacity' command's execute function:
execute: (ctx, args, deps) => {
  const capacity = parseInt(args.positional[0], 10);
  const node = deps.topology.getNode(ctx.nodeId!);
  if (!node?.queue) return { type: 'error', message: 'Node has no queue config.' };
  if (capacity < node.queue.workers) {
    return { type: 'error', message: `Capacity (${capacity}) must be >= workers (${node.queue.workers}).` };
  }
  deps.topology.updateNode(ctx.nodeId!, {
    queue: { ...node.queue, capacity }
  });
  deps.topology.markDirty();
  return { type: 'text', content: `Capacity set to ${capacity}.` };
}
```

The mutation path is: command → `CommandDeps.topology.updateNode()` → Zustand store `setNodes()` → React Flow re-render → canvas shows updated config. This is the same data path as editing through the `PropertiesPanel`, ensuring consistency.

**Port config commands (in `node(config-port:N)#` mode):**

See [Feature 5 — Port-Level State Model](#feature-5--port-level-state-model) for the port config commands.

**Post-mutation validation:** After any `set` command, the terminal runs the topology validator (`validateTopology` from `src/engine/validation/validator.ts`) on the modified topology and prints warnings if the change introduces issues (e.g., capacity < workers after a `set workers` command on a different node).

### What components it requires

- **Shared layer:** Command definitions in `src/shared/commands/config/` with argument parsing and validation.
- **Renderer-side:** `CommandDeps.topology.updateNode()` mapped to the Zustand store's node update action. The `isUnsaved` flag in the store must be set (same path as `PropertiesForm` edits).
- **Validation:** Reuse of `validateTopology` for post-mutation checks.

### Explored in

HLD doc (Scenario layer — all `set` and `no` examples), Implementation plan doc (Phase 2 — Config mutation).

---

## Feature 5 — Port-Level State Model

### What it does

Extends the engine's node model with port-level granularity. A node can have multiple ports, each with its own protocol, connection limit, health check, and rate limit. Port state is tracked at runtime and included in snapshots.

### Why it exists

The current engine models every node as a single-endpoint `GGcKNode` with one queue and one worker pool. This is sufficient for application-layer services (a microservice has one processing pipeline), but networking components operate on multiple ports:

- A **load balancer** listens on port 443 (HTTPS) and port 80 (HTTP redirect), each with different connection limits.
- A **firewall** has rules per port/protocol combination.
- A **router** has multiple interfaces, each connected to a different network segment.
- A **database** may expose port 5432 (client connections) and port 5433 (replication).

Without port-level state, the terminal's `show ports`, `show interfaces`, and port config mode (`node(config-port:N)#`) have nothing to operate on.

### How it works internally

**New types (engine addition):**

```typescript
// Proposed location: src/engine/core/types.ts

interface PortConfig {
  /** Port number (e.g., 443, 80, 5432). */
  portNumber: number;

  /** Protocol handled by this port. */
  protocol: 'tcp' | 'udp' | 'http' | 'https' | 'grpc' | 'amqp' | 'kafka';

  /** Maximum concurrent connections on this port. */
  maxConnections: number;

  /** Optional health check configuration. */
  healthCheck?: {
    path: string;         // e.g., '/healthz'
    intervalMs: number;   // how often to check
  };

  /** Optional rate limiting on this port. */
  rateLimit?: {
    rps: number;          // requests per second
    burstSize: number;    // burst allowance
  };

  /** Whether the port is administratively enabled. */
  enabled: boolean;
}
```

```typescript
interface PortState {
  portNumber: number;
  activeConnections: number;
  totalRequests: bigint;
  status: 'up' | 'down' | 'rate-limited';
}
```

```typescript
interface PortSnapshot {
  portNumber: number;
  protocol: string;
  activeConnections: number;
  maxConnections: number;
  rps: number;
  status: 'up' | 'down' | 'rate-limited';
}
```

**Where port config lives:** On `ComponentNode.config`, which is typed as `Record<string, unknown>`. Nodes that support ports would have `config.ports: PortConfig[]`. The engine's `GGcKNode` constructor would read this if present:

```typescript
// In GGcKNode constructor:
const portConfigs = (config.config?.ports as PortConfig[] | undefined) ?? [];
this.ports = portConfigs.map(pc => ({
  config: pc,
  state: { portNumber: pc.portNumber, activeConnections: 0, totalRequests: 0n, status: pc.enabled ? 'up' : 'down' }
}));
```

**Runtime behavior:** Port state is primarily cosmetic in the initial implementation — the G/G/c/K admission check still operates at the node level (total `activeWorkers + queueLength >= capacity`). Port-level connection tracking is an accounting layer: when a request arrives at a node, the engine increments the connection count on the port matching the incoming edge's protocol. If the port's `maxConnections` is exceeded, the request is rejected with reason `'port_connection_limit'` — this is a new rejection reason alongside the existing `'capacity_exceeded'` and `'node_failed'`.

**Snapshot inclusion:** `TimeSeriesSnapshot.perNode[nodeId]` gains an optional `ports: PortSnapshot[]` field. The snapshot emitter reads port state from `GGcKNode.getPortStates()`.

**Which node types support ports:** Determined by `ComponentCategory`:
- `'network-and-edge'` — load balancers, routers, gateways, CDN, API gateway, ingress controller
- `'security-and-identity'` — firewalls, WAF, bastion host
- `'storage-and-data'` — databases (client + replication ports)

Application-layer nodes (`'compute'`, `'messaging-and-streaming'`) don't expose ports — their single-endpoint model remains.

### What components it requires

- **Engine-side:** `PortConfig`, `PortState`, `PortSnapshot` types. `GGcKNode` gains optional port tracking. `TimeSeriesSnapshot` gains optional port data. New rejection reason `'port_connection_limit'`.
- **Shared layer:** Port-related show and config commands.
- **Renderer-side:** Port state visualization in the terminal (table formatting).

### Explored in

HLD doc (per-type examples — load balancer port listing, router interface listing), Implementation plan doc (Phase 2 — Port-level extension).

---

## Feature 6 — Per-Type Idiomatic CLI

### What it does

When the user selects a node, the terminal activates a type-specific command set that mimics the real-world CLI for that technology. Selecting a Postgres node makes `psql`-style commands available. Selecting a Redis node activates `redis-cli` syntax. Selecting a router activates Cisco IOS commands.

### Why it exists

This is the feature that gives the terminal its Packet Tracer identity. The educational value is not just in the simulator's own commands — it's in exposing students to the actual administrative interfaces of the technologies they're designing with. A student configuring a Postgres node should learn that `\dt` lists tables and `\d <table>` describes a table's schema, even though in the simulator context these map to viewing the node's configuration.

### How it works internally

**Activation:** When the user enters node context via `select <nodeId>`, the registry checks the node's `ComponentType` (from `ComponentNode.type` in `src/engine/core/types.ts`) and activates the corresponding command set. The base show/config commands are always available; per-type commands are additive.

**Type → CLI mapping:**

| Node type(s) | Idiom | Activated commands |
|---|---|---|
| `relational-db` (Postgres) | psql | `\dt` → show config tables, `\d <table>` → describe table schema, `SELECT ... FROM pg_stat_activity` → show connections, `\conninfo` → show connection info, `\l` → list databases |
| `relational-db` (MySQL) | mysql | `SHOW DATABASES`, `SHOW TABLES`, `SHOW PROCESSLIST`, `SHOW STATUS`, `SHOW VARIABLES` |
| `in-memory-cache`, `kv-store` (Redis) | redis-cli | `INFO` → show config + metrics, `INFO server` / `INFO memory` / `INFO stats` → filtered sections, `DBSIZE` → queue depth, `SLOWLOG` → recent slow events, `CLIENT LIST` → active connections, `CONFIG GET <param>` → show config value |
| `load-balancer`, `load-balancer-l4`, `load-balancer-l7`, `api-gateway`, `ingress-controller`, `reverse-proxy`, `edge-router`, `transit-gateway` | Cisco IOS | `show ip route` → show routing table, `show interfaces` → interface/port table, `show running-config` → full config dump, `show ip interface brief` → compact interface summary |
| `queue`, `pub-sub`, `stream`, `event-bus`, `message-broker` (Kafka) | kafka-topics | `--list` → list topics (mapped to connected edges), `--describe --topic <name>` → topic details, consumer group simulation |
| All others | Standard | Base `show` and `configure` commands only |

**How psql commands map to simulator data:**

| psql command | Simulator data | Output |
|---|---|---|
| `\dt` | `ComponentNode.config` — hypothetical table definitions if configured, otherwise node edges as "tables" | Table listing |
| `\d <table>` | Edge schema or config section detail | Column-like field listing |
| `SELECT * FROM pg_stat_activity` | `TimeSeriesSnapshot.perNode[nodeId]` — active workers mapped to "active connections" | Process list table |
| `\conninfo` | `ComponentNode.label`, node type, edge protocol | Connection summary string |

**How redis-cli commands map:**

| redis-cli command | Simulator data | Output |
|---|---|---|
| `INFO` | `ComponentNode` config + `TimeSeriesSnapshot` metrics | Multi-section info dump (server, memory, stats, keyspace) |
| `INFO stats` | `PerNodeMetrics` — throughput, latency, error rate | Stats section only |
| `DBSIZE` | `GGcKNode.getState().queueLength` | Integer (queue depth as "key count") |
| `SLOWLOG` | `DebugEvent[]` filtered to this node, sorted by duration desc | Slow event entries |
| `CLIENT LIST` | Active workers mapped to "clients", with per-worker metadata | Client list table |
| `CONFIG GET maxmemory` | `ComponentNode.queue.capacity` | Config key-value |

**Registration pattern:**

```typescript
// src/shared/commands/per-type/postgres.ts
export const postgresCommands: CommandDefinition[] = [
  {
    name: '\\dt',
    aliases: [],
    modes: ['node'],
    args: [],
    description: 'List tables (node edge connections)',
    execute: (ctx, _args, deps) => {
      const node = deps.topology.getNode(ctx.nodeId!);
      const edges = deps.topology.getEdges().filter(
        e => e.source === ctx.nodeId || e.target === ctx.nodeId
      );
      // Format as psql-style table listing
      return { type: 'table', headers: ['Schema', 'Name', 'Type', 'Owner'], rows: ... };
    }
  },
  // ...
];
```

**Type detection:**

```typescript
function getCliProfile(node: ComponentNode): 'postgres' | 'mysql' | 'redis' | 'cisco' | 'kafka' | 'standard' {
  switch (node.type) {
    case 'relational-db':
      // Check config or label for Postgres vs MySQL hint
      const label = node.label.toLowerCase();
      if (label.includes('postgres') || label.includes('pg')) return 'postgres';
      if (label.includes('mysql') || label.includes('maria')) return 'mysql';
      return 'postgres'; // default for relational-db
    case 'in-memory-cache':
    case 'kv-store':
      return 'redis';
    case 'load-balancer':
    case 'load-balancer-l4':
    case 'load-balancer-l7':
    case 'api-gateway':
    case 'ingress-controller':
    case 'reverse-proxy':
    case 'edge-router':
    case 'transit-gateway':
      return 'cisco';
    case 'queue':
    case 'pub-sub':
    case 'stream':
    case 'event-bus':
    case 'message-broker':
      return 'kafka';
    default:
      return 'standard';
  }
}
```

### What components it requires

- **Shared layer:** Per-type command files in `src/shared/commands/per-type/`. Each exports a `CommandDefinition[]` that the registry activates conditionally.
- **Registry:** `CommandRegistry.activateProfile(profile)` that adds/removes commands dynamically when the node context changes.
- **Engine-side:** No changes — per-type commands read existing data through different lenses.

### Explored in

HLD doc (all per-type walkthrough sections — Postgres, Redis, Load Balancer, Router, Kafka examples).

---

## Feature 7 — Runtime Simulation Control

### What it does

Text-based simulation control during a running simulation. The user types `pause`, `resume`, `speed 2x`, `step 100`, or `stop` instead of clicking GUI buttons. Also provides on-demand status queries (`status`, `show status`).

### Why it exists

The GUI's `SimulationControls` component exposes Run/Pause/Resume/Stop buttons. Adding step-through and speed control to the GUI is tracked in #77 (Scenario Bar). The terminal provides the same controls in text form, which serves two purposes:

1. **Preference:** Some users (especially those with sysadmin or backend backgrounds) prefer typing commands to clicking buttons. The terminal gives them a native interaction model.
2. **Scriptability:** A sequence of terminal commands can be composed into a scenario: "run, wait until t=5s, pause, show status, step 1000, show queue at payment-svc, resume." This is more expressive than GUI button clicks.

### How it works internally

**Commands:**

| Command | Effect | Worker message sent | Source |
|---|---|---|---|
| `pause` | Pause simulation | `{ type: 'pause' }` | `WorkerInboundMessage` — already exists in `protocols.ts` |
| `resume` | Resume simulation | `{ type: 'resume' }` | Already exists |
| `step [N]` | Step N events (default: 1) | `{ type: 'step', payload: { count: N } }` | Already exists |
| `speed <multiplier>` | Set playback speed | `{ type: 'set-speed', payload: { speed: multiplier } }` | New — added by #68 |
| `stop` | Stop simulation | `{ type: 'stop' }` | Already exists |
| `status` | Print current state | — (reads from `SimulationState`) | No message needed |

**How commands reach the worker:**

```
Terminal input → CommandRegistry.resolve() → command.execute()
  → deps.simulation.controls.pause()
    → useSimulation.pause()
      → postToWorker({ type: 'pause' })
        → simulation.worker.ts: paused = true
```

The terminal does not communicate with the worker directly. It goes through the same `useSimulation` hook that the GUI buttons use. This guarantees that the terminal and GUI always agree on simulation state.

**`status` command output:**

```
sim(runtime)# status

  Simulation: RUNNING
  Progress  : 72% (14,382 of ~20,000 events)
  Sim Time  : 10.8s / 15.0s
  Speed     : 1.0x
  Wall Time : 3.2s elapsed
```

This reads directly from `SimulationState.status`, `SimulationState.progress`, `SimulationState.eventsProcessed`, and `SimulationState.snapshot.currentTime`.

**Runtime show commands:** In `sim(runtime)#` mode, show commands read from the *latest snapshot* rather than post-run data. This means `show status` in runtime mode shows live-ish data (updated every snapshot interval — 1 second of sim-time by default). It is not continuously updating; each invocation reads the most recent snapshot.

For live-updating display, see the `watch` command (stretch goal) and the CLI `--live` mode (#84).

### What components it requires

- **Shared layer:** Runtime command definitions in `src/shared/commands/runtime/`.
- **Renderer-side:** `CommandDeps.simulation.controls` mapped to `useSimulation` hook methods.
- **Engine-side:** `SET_SPEED` message support (from #68). All other messages already exist.

### Explored in

Implementation plan doc (Runtime layer — Phase 3), HLD doc (runtime control examples).

---

## Feature 8 — Trace & Event Inspection Commands

### What it does

Text-based inspection of the simulation's event stream, request traces, and failure records. These commands consume the same `DebugEvent[]`, `RequestLifecycle`, and `CausalGraph` data as the event debugger, but render it as formatted text in the terminal instead of as visual UI components.

### Why it exists

The event debugger's visual views (event log table, lifecycle rail, waterfall, cascade view) are powerful for exploration but require mouse interaction. The terminal's trace commands serve users who want specific answers fast: "show me the last 10 rejection events", "trace request req-9148 through the topology", "why was req-5001 rejected?"

These commands also work in headless mode (via the shared CLI) where there is no GUI at all — making them essential for automated testing and CI pipelines.

### How it works internally

**Event inspection commands (in `sim(runtime)#` mode):**

| Command | Data source | Output |
|---|---|---|
| `show events [--last N]` | `DebugEvent[]` from the event debugger's event stream (#38) | Formatted table: timestamp, type, node, requestId, status, reason |
| `show events --node <id>` | `DebugEvent[].filter(e => e.nodeId === id)` | Same table, filtered |
| `show events --request <id>` | `DebugEvent[].filter(e => e.requestId === id)` | Same table, filtered |
| `show events --type <type>` | `DebugEvent[].filter(e => e.type === type)` | Filtered by event type |
| `show rejected [--last N]` | `DebugEvent[].filter(e => e.status === 'danger')` | Rejection events with reason codes |
| `show timeouts [--last N]` | `DebugEvent[].filter(e => e.type === 'request-timeout')` | Timeout events |

**Trace inspection commands:**

| Command | Data source | Output |
|---|---|---|
| `show trace <requestId>` | `RequestLifecycle` assembled from `DebugEvent[]` + `RequestTraceSpan[]` | Text waterfall: each hop as an indented line with timing breakdown |
| `show trace <requestId> --detail` | Same, with `NodeSnapshot` at each hop | Extended output including node state per hop |

**How `show trace` renders:**

```
sim(runtime)# show trace req-9148

  Request req-9148  ─  REJECTED at payment-svc-v2  ─  Total: 71.9ms

  ───────────────────────────────────────────────────────
  1. api-gw            ● 2.1ms   [edge: 0.3ms  queue: 0.0ms  proc: 1.8ms]
  2. auth-svc          ● 5.4ms   [edge: 1.2ms  queue: 0.8ms  proc: 3.4ms]
  3. lb                ● 0.9ms   [edge: 0.4ms  queue: 0.0ms  proc: 0.5ms]
  4. order-svc-b       ● 12.3ms  [edge: 2.1ms  queue: 5.6ms  proc: 4.6ms]
  5. inventory-svc     ● 8.7ms   [edge: 1.5ms  queue: 2.2ms  proc: 5.0ms]
  6. redis             ● 3.2ms   [edge: 0.8ms  queue: 0.0ms  proc: 2.4ms]
  7. payment-svc-v2    ✗ REJECTED  [reason: capacity_exceeded]
     Workers: 8/8  Queue: 92/92  Capacity: 100/100
  ───────────────────────────────────────────────────────
```

Each hop line reads from `LifecyclePhase.timing` (`PhaseTiming.edgeLatencyMs`, `queueWaitMs`, `serviceTimeMs`). The rejection line reads from `LifecyclePhase.event.nodeState` (`NodeSnapshot.activeWorkers`, `maxWorkers`, `queueLength`, `capacity`).

**Cascade command:**

| Command | Data source | Output |
|---|---|---|
| `show cascade [--from <eventId>]` | `CausalGraph` from #35 | Indented text tree showing failure propagation |

```
sim(runtime)# show cascade

  ✗ payment-svc-v2 SATURATED (t=12.4s)
    ├── ✗ order-svc-b queue overflow (92 rejected)
    │   └── ✗ api-gw error rate spike (4.2%)
    └── ✗ inventory-svc timeout (12 requests > 5000ms)
```

### What components it requires

- **Shared layer:** Trace and event command definitions in `src/shared/commands/trace/`.
- **Engine-side:** Requires #38 (canonical event stream) to be complete — `DebugEvent[]` is the data source. Requires #35 for cascade commands.
- **Renderer-side:** `CommandDeps.debug.events` mapped to `SimulationState.debugEvents` from the `useSimulation` hook.

### Explored in

Implementation plan doc (Trace layer — Phase 3), HLD doc (trace examples in runtime walkthrough).

---

## Feature 9 — Diagnostic & Pedagogy Commands

### What it does

Higher-level analysis commands that synthesize data from multiple sources to produce educational explanations. Instead of showing raw state, they answer "why" questions: "why was this request rejected?", "what's wrong with this node?", "how does the G/G/c/K admission check work for this node?"

### Why it exists

This is the feature that differentiates the simulator terminal from a real system's CLI. A real `psql` shows connection counts; it doesn't explain *why* connections are being refused in plain English. The simulator's diagnostic commands bridge the gap between "what is happening" and "why is it happening" — which is the core value proposition for a learning tool.

### How it works internally

**Diagnostic commands:**

| Command | Mode | Data source | Output |
|---|---|---|---|
| `diagnose <nodeId>` | `sim(runtime)#` | `TimeSeriesSnapshot`, `PerNodeMetrics`, edge metrics, `DebugEvent[]` | Multi-line health analysis |
| `why-rejected <requestId>` | `sim(runtime)#` | `AdmissionDecision` from event debugger schema, `NodeSnapshot`, `LifecyclePhase` | Step-by-step rejection explanation |
| `compare <nodeA> <nodeB>` | `sim(runtime)#` | `TimeSeriesSnapshot.perNode[A]` + `perNode[B]` | Side-by-side metrics comparison table |
| `explain capacity <nodeId>` | `node>` or `sim(runtime)#` | `ComponentNode.queue`, `GGcKNode.getState()` | Plain-text G/G/c/K parameter explanation |
| `ping <nodeA> <nodeB>` | `sim>` | `RoutingTable`, `EdgeDefinition[]` | Topology path trace with hop count and accumulated latency |
| `traceroute <nodeA> <nodeB>` | `sim>` | Same as `ping`, with per-hop detail | Detailed path with per-hop latency breakdown |

**How `diagnose` works:**

The `diagnose` command runs a series of checks against the node's state and produces a structured report:

```
sim(runtime)# diagnose payment-svc-v2

  ┌─────────────────────────────────────────────┐
  │  DIAGNOSIS: payment-svc-v2                  │
  │  Status: ◉ HOT (97.2% utilization)          │
  ├─────────────────────────────────────────────┤
  │                                             │
  │  ⚠ Queue Saturation                        │
  │    Queue is at 92/92 (100.0% full).         │
  │    Workers are fully occupied (8/8).         │
  │    Incoming requests are being rejected.     │
  │                                             │
  │  ⚠ Upstream Pressure                       │
  │    Node receives traffic from 3 upstream     │
  │    edges with combined throughput of 980/s.  │
  │    Node can only process ~500/s.             │
  │    Recommendation: increase workers or add   │
  │    a load balancer upstream.                 │
  │                                             │
  │  ✓ Error Rate                               │
  │    Error rate (2.1%) is within configured    │
  │    SLO target (5.0%).                        │
  │                                             │
  │  ✗ SLO Breach                               │
  │    P99 latency: 142ms (target: 100ms)       │
  │    Action: reduce queue depth or add workers │
  └─────────────────────────────────────────────┘
```

The diagnostic engine runs these checks:

1. **Queue saturation:** Is `queueLength / (capacity - maxWorkers)` > 80%? If so, explain the bottleneck.
2. **Worker saturation:** Is `activeWorkers === maxWorkers`? If so, note that all workers are busy.
3. **Upstream pressure:** Sum incoming edge throughput and compare to node's processing capacity (`maxWorkers / avgServiceTime`). If inflow > capacity, identify the pressure.
4. **Error rate:** Compare observed error rate to SLO target from `ComponentNode.slo.errorBudget`.
5. **Latency breach:** Compare observed P99 to `ComponentNode.slo.latencyP99`.
6. **Downstream impact:** Check if this node's saturation is causing rejections at downstream nodes.

**How `why-rejected` works:**

This command consumes the `AdmissionDecision` type from the event debugger schema. It maps directly to the Node Intake Lens feature (#157), but renders as text instead of gauges and slot grids:

```
sim(runtime)# why-rejected req-9148

  Request req-9148 was REJECTED at payment-svc-v2

  Admission check: activeWorkers + queueLength >= capacity
                    8            + 92          >= 100
                    100 >= 100  →  TRUE  →  REJECTED

  Breakdown:
    Active workers : 8 / 8   (all workers occupied)
    Queue length   : 92 / 92  (queue full)
    System capacity: 100      (workers + queue slots)

  The request could not enter the node because all 100 positions
  (8 worker slots + 92 queue slots) were occupied. To fix this:
    • Increase capacity: set capacity 200
    • Add workers: set workers 16
    • Add upstream load balancing to distribute traffic
```

The data comes from `AdmissionDecision.nodeState`, `AdmissionDecision.equation`, and `AdmissionDecision.slots` — the same types used by the Node Intake Lens visual component.

**How `ping` and `traceroute` work:**

These traverse the topology graph using `RoutingTable`:

```
sim> traceroute api-gw orders-db

  Tracing route from api-gw to orders-db...

  1  api-gw           0.0ms
  2  auth-svc         2.3ms  (edge: api-gw→auth-svc, protocol: https, latency: normal μ=2.3ms)
  3  lb               0.5ms  (edge: auth-svc→lb, protocol: grpc, latency: constant 0.5ms)
  4  order-svc-b      3.1ms  (edge: lb→order-svc-b, protocol: https, latency: log-normal μ=1.2)
  5  orders-db        1.8ms  (edge: order-svc-b→orders-db, protocol: tcp, latency: constant 1.8ms)

  Total hops: 5
  Estimated total latency: 7.7ms (sum of mean edge latencies)
```

The path is computed by walking `RoutingTable.getOutgoingEdges()` from source, picking the first sync edge at each hop (or weighted-random for load balancers), until the target is reached or no more edges exist. Edge latency is the mean of the configured distribution (computed from `DistributionConfig` parameters).

### What components it requires

- **Shared layer:** Diagnostic command definitions in `src/shared/commands/diagnose/`.
- **Engine-side:** Requires `AdmissionDecision` type (from event debugger schema), `TimeSeriesSnapshot`, `PerNodeMetrics`, `RoutingTable` access.
- **Renderer-side:** `CommandDeps` provides all required data sources.

### Explored in

Implementation plan doc (Pedagogy layer — Phase 5), HLD doc (diagnostic examples in runtime walkthrough).

---

## Feature 10 — xterm.js Integration & Terminal Tab

### What it does

Renders the terminal as a tab in the Results Tray bottom panel using xterm.js — a full terminal emulator in the browser. Handles input capture, output rendering, ANSI color/formatting, panel resize, and theme synchronization.

### Why it exists

A `<textarea>` or custom input field would look like a text box, not a terminal. xterm.js provides the full terminal experience: cursor positioning, ANSI escape sequences, scrollback buffer, selection/copy, proper monospace rendering, and ligature support. It's the same library used by VS Code's integrated terminal, so it's proven at scale.

### How it works internally

**Tab placement:** The terminal tab lives in the Results Tray tab bar alongside Event Log, Traces, Failures, Summary, and Per-Node tabs. It's added by the terminal feature after #78 (Results Tray tabs) establishes the tab system.

**xterm.js setup:**

```typescript
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';

const terminal = new Terminal({
  cursorBlink: true,
  fontSize: 13,
  fontFamily: 'JetBrains Mono, Menlo, Monaco, Consolas, monospace',
  theme: isDarkMode ? darkTheme : lightTheme,
  scrollback: 5000,
  convertEol: true,
});

const fitAddon = new FitAddon();
terminal.loadAddon(fitAddon);
terminal.loadAddon(new WebLinksAddon());

terminal.open(containerRef.current);
fitAddon.fit();
```

**Input handling:** xterm.js's `terminal.onData(data)` callback receives raw keystroke data. The terminal component:

1. Buffers keystrokes into a line buffer.
2. On Enter, sends the complete line to the command parser.
3. On Tab, triggers completion from the registry and writes the completion into the line buffer.
4. On Up/Down arrow, navigates command history.
5. On Ctrl+C, cancels the current input line.
6. On Ctrl+L, clears the screen.

**Output rendering:** Command results are formatted as ANSI strings and written via `terminal.write(ansiString)`. The formatters use ANSI escape codes:

```typescript
const ANSI = {
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  reset: '\x1b[0m',
};
```

Tables are rendered using Unicode box-drawing characters (`─`, `│`, `┌`, `┐`, `└`, `┘`, `├`, `┤`) with column alignment computed from content widths.

**Resize handling:** The Results Tray is vertically resizable (the user drags the divider). On resize, the component calls `fitAddon.fit()` to recompute the terminal's column and row counts. A `ResizeObserver` on the container element triggers this automatically.

**Theme synchronization:** The terminal theme (background, foreground, cursor, selection colors) is derived from the app's dark/light mode setting. When the theme changes, `terminal.options.theme` is updated.

**State persistence across collapse/expand:** When the Results Tray is collapsed and re-expanded, the terminal tab must preserve:
- Scrollback buffer (xterm.js handles this natively — the `Terminal` instance survives in memory)
- Command history (stored in a ref, not in DOM state)
- Current mode/prompt (stored in `TerminalContext`)

This requires the `Terminal` instance to be created once and attached/detached from the DOM on collapse/expand, rather than destroyed and recreated.

### What components it requires

- **Dependencies:** `xterm` + `xterm-addon-fit` + `xterm-addon-web-links` npm packages.
- **Renderer-side:** A `TerminalTab.tsx` component that creates and manages the xterm.js instance. A `useTerminal` hook that bridges the xterm.js instance with the command registry and mode system.
- **Integration:** The Results Tray tab system (#78) must support a tab whose content is a raw DOM element (the xterm canvas) rather than a React component tree.

### Explored in

Implementation plan doc (UI Architecture — xterm.js, Bottom Panel Tab, Phase 1).

---

## Feature 11 — Shared CLI Architecture

### What it does

A shared command layer that allows the same command definitions to run in both the in-app terminal (React renderer context) and the headless CLI (`src/cli/index.ts`). Commands are defined once in a shared location and adapted to their runtime environment through dependency injection.

### Why it exists

The headless CLI at `src/cli/index.ts` already validates topologies, runs simulations, and prints results. As the terminal grows, it would be wasteful and divergent to maintain two separate implementations of the same commands. The shared architecture means:

1. A command like `show nodes` is defined once, tested once, and works in both contexts.
2. New terminal commands are automatically available in the CLI.
3. The CLI can evolve from a single `run` command into a full `nssim` command suite (#83) by importing from the shared registry.

### How it works internally

**File structure:**

```
src/
├── shared/
│   └── commands/
│       ├── registry.ts          # CommandRegistry class
│       ├── types.ts             # CommandDefinition, CommandDeps, CommandResult, etc.
│       ├── show/
│       │   ├── showTopology.ts  # 'show topology' command
│       │   ├── showNodes.ts     # 'show nodes' command
│       │   ├── showStatus.ts    # 'show status' command
│       │   ├── showQueue.ts     # 'show queue' command
│       │   └── ...
│       ├── config/
│       │   ├── setCapacity.ts   # 'set capacity' command
│       │   ├── setWorkers.ts    # 'set workers' command
│       │   └── ...
│       ├── runtime/
│       │   ├── pause.ts
│       │   ├── resume.ts
│       │   ├── step.ts
│       │   ├── speed.ts
│       │   └── status.ts
│       ├── trace/
│       │   ├── showEvents.ts
│       │   ├── showTrace.ts
│       │   └── showCascade.ts
│       ├── diagnose/
│       │   ├── diagnose.ts
│       │   ├── whyRejected.ts
│       │   └── explainCapacity.ts
│       └── per-type/
│           ├── postgres.ts
│           ├── redis.ts
│           ├── cisco.ts
│           └── kafka.ts
├── renderer/
│   └── src/
│       └── components/
│           └── terminal/
│               ├── TerminalTab.tsx       # xterm.js integration
│               ├── TerminalContext.ts    # Mode state machine
│               ├── useTerminal.ts       # Hook: connects registry to xterm.js
│               ├── useCommandDeps.ts    # Hook: builds CommandDeps from React context
│               └── formatters/
│                   └── ansi.ts          # ANSI table/color formatters
└── cli/
    ├── index.ts                 # Current CLI entrypoint (to be refactored)
    ├── adapter.ts               # Builds CommandDeps from direct engine access
    └── commands/
        └── run.ts               # 'nssim run' wrapping the registry
```

**Adaptation pattern:**

The renderer builds `CommandDeps` from React hooks and the Zustand store:

```typescript
// src/renderer/src/components/terminal/useCommandDeps.ts
function useCommandDeps(): CommandDeps {
  const nodes = useFlowStore(s => s.nodes);
  const edges = useFlowStore(s => s.edges);
  const { run, pause, resume, stop, step, ...simState } = useSimulation();

  return {
    topology: {
      getNodes: () => convertToComponentNodes(nodes),
      getEdges: () => convertToEdgeDefinitions(edges),
      getNode: (id) => findNode(nodes, id),
      updateNode: (id, patch) => useFlowStore.getState().updateNodeData(id, patch),
      markDirty: () => useFlowStore.getState().setIsUnsaved(true),
    },
    simulation: {
      state: simState,
      controls: { run, pause, resume, stop, step },
    },
    debug: {
      events: simState.debugEvents ?? [],
      lifecycle: simState.debugLifecycle ?? null,
      snapshots: simState.snapshot ? [simState.snapshot] : [],
    },
    terminal: { /* ... */ },
  };
}
```

The CLI builds `CommandDeps` from direct engine access:

```typescript
// src/cli/adapter.ts
function buildCliDeps(topology: TopologyJSON, engine: SimulationEngine): CommandDeps {
  return {
    topology: {
      getNodes: () => topology.nodes,
      getEdges: () => topology.edges,
      getNode: (id) => topology.nodes.find(n => n.id === id) ?? null,
      updateNode: (id, patch) => {
        const idx = topology.nodes.findIndex(n => n.id === id);
        if (idx >= 0) topology.nodes[idx] = { ...topology.nodes[idx], ...patch };
      },
      markDirty: () => { /* no-op in CLI — file not watched */ },
    },
    simulation: {
      state: { status: 'idle', progress: 0, /* ... */ },
      controls: { run: () => engine.run(), /* ... */ },
    },
    debug: { events: [], lifecycle: null, snapshots: [] },
    terminal: { /* CLI has no mode system — commands run directly */ },
  };
}
```

**What this enables for the `nssim` CLI (#83):**

```
nssim run topology.json                    # existing behavior
nssim validate topology.json               # shared: uses validateTopology
nssim show topology.json --nodes           # shared: uses showNodes command
nssim inspect topology.json --node api-gw  # shared: uses showStatus command
nssim run topology.json --live             # #84: live mode using shared formatters
```

The `nssim` CLI becomes a thin adapter that creates `CommandDeps` from file-based topology access and delegates to the shared command registry.

### What components it requires

- **Shared layer:** The entire `src/shared/commands/` directory. `CommandRegistry`, `CommandDeps` interface, all command definitions.
- **Renderer-side:** `useCommandDeps` hook that adapts the Zustand store and hooks to `CommandDeps`.
- **CLI-side:** `adapter.ts` that adapts direct engine/file access to `CommandDeps`.
- **Build:** The `src/shared/` directory must be importable from both the Vite renderer build and the Node.js CLI build. This requires careful TypeScript path configuration — no browser APIs in shared code, no Node.js APIs in shared code.

### Explored in

Implementation plan doc (Architecture — Shared command layer, CLI integration, Phase 4).

---

## Relationship to Event Debugger

The terminal and event debugger are not independent features — they share the same data pipeline and live in the same UI container. Understanding their relationship is critical for implementation ordering.

### Shared data sources

| Data type | Engine origin | Event Debugger consumer | Terminal consumer |
|---|---|---|---|
| `DebugEvent[]` | #38 — canonical event stream | Event Log tab, all display variants | `show events`, `show rejected`, `show timeouts` |
| `RequestLifecycle` | #38 — assembled from events + trace spans | Lifecycle Rail, Sequence Diagram, Stack Trace, State Machine, Filmstrip | `show trace <requestId>` |
| `NodeSnapshot` | `GGcKNode.getState()` + config limits | Request Detail Inspector, Intake Lens | `show status`, `show queue`, `why-rejected` |
| `AdmissionDecision` | `GGcKNode.handleArrival()` | Node Intake Lens (#157) | `why-rejected <requestId>` |
| `TimeSeriesSnapshot` | #33 — periodic snapshots | Canvas debug overlay (#158), filmstrip | `show status`, `diagnose`, runtime `show` commands |
| `CausalGraph` | #35 — causal failure graph | Failure Cascade view (#80) | `show cascade` |
| Worker protocol | #68 — `PAUSE`, `RESUME`, `STEP`, `SET_SPEED` | Playback controls via `DebugControls` | `pause`, `resume`, `step`, `speed` commands |
| `SimulationState` | `useSimulation` hook (#69) | All debugger UI components | `status` command, all runtime show commands |

### Shared UI container

Both the terminal and the event debugger live in the Results Tray bottom panel (#78). The terminal is a tab alongside Event Log, Traces, Failures, Summary, and Per-Node. They share:

- The tab bar and tab switching mechanism
- Collapse/expand behavior
- The vertical resize handle
- The "row-to-canvas linking" interaction (clicking a node name in terminal output could select it on canvas)

### What the terminal adds that the debugger doesn't need

| Concept | Why the debugger doesn't need it |
|---|---|
| Context modes (sim/node/config/port/runtime) | The debugger operates on events, not on node contexts |
| Config mutation (`set capacity`, `set workers`) | The debugger is read-only — it doesn't change topology |
| Port-level state (`PortConfig`, `PortState`) | The debugger operates at the request/event level, not port level |
| Per-type CLI commands (psql, redis-cli) | The debugger has a uniform event schema regardless of node type |
| Command registry and parser | The debugger uses visual UI controls, not text input |
| xterm.js | The debugger uses standard React components |
| Shared CLI architecture | The debugger is renderer-only |

---

## Engine Integration Requirements

The terminal requires changes to the engine beyond what the event debugger already specifies. The event debugger's requirements (documented in `event-debugger-schema.md`) are prerequisites; the terminal adds:

### 1. Port-level state tracking

New types: `PortConfig`, `PortState`, `PortSnapshot`. New admission rejection reason: `'port_connection_limit'`. New field on `TimeSeriesSnapshot.perNode`: `ports?: PortSnapshot[]`.

This is the only significant engine-side addition. All other terminal features consume existing data through the shared command layer.

### 2. Node config mutation path

The terminal writes to `ComponentNode` fields through the Zustand store (same path as `PropertiesPanel`). The engine itself is not modified — config changes affect the *next* simulation run, not a running simulation. If "live config modification during simulation" is desired later, the worker would need a new inbound message type (`UpdateNodeConfig`), but this is out of scope for the initial terminal implementation.

### 3. Expected path computation utility

The `ping` and `traceroute` commands need a utility that walks the topology's edges from node A to node B. The event debugger's `ExpectedPath` type (from `event-debugger-schema.md`) describes this, but the actual implementation — walking `RoutingTable.getOutgoingEdges()` recursively — doesn't exist yet. This utility should be shared between the debugger (for the Actual vs Expected Path Diff view) and the terminal (for `ping`/`traceroute`).

### 4. Diagnostic analysis functions

The `diagnose` command runs checks (queue saturation, upstream pressure, SLO breach) that don't exist as standalone functions. These should be extracted into a shared analysis module (`src/engine/analysis/diagnostics.ts`) so they can be tested independently and reused by both the terminal and potential future automated health-check features.

---

## Source-to-Feature Map

| Feature | HLD Examples Doc | Implementation Plan Doc |
|---|---|---|
| 1. Context Mode System | All walkthrough sections (prompt examples) | Phase 1 — Model layer |
| 2. Command Registry & Parser | Implicit (command syntax throughout) | Architecture — Command Registry |
| 3. Show Commands | Model layer examples (show status, show queue, etc.) | Phase 2 — Show commands |
| 4. Config Mutation Commands | Scenario layer examples (set, no) | Phase 2 — Config mutation |
| 5. Port-Level State Model | Per-type examples (LB ports, router interfaces) | Phase 2 — Port-level extension |
| 6. Per-Type Idiomatic CLI | All per-type sections (psql, redis, IOS, kafka) | Phase 4 — Per-type extensions |
| 7. Runtime Simulation Control | Runtime layer examples (pause, resume, speed) | Phase 3 — Runtime layer |
| 8. Trace & Event Inspection | Trace layer examples (show events, show trace) | Phase 3 — Trace layer |
| 9. Diagnostic Commands | Pedagogy layer examples (diagnose, why-rejected) | Phase 5 — Pedagogy layer |
| 10. xterm.js Integration | Implicit (terminal UI assumed) | Architecture — UI placement |
| 11. Shared CLI Architecture | CLI reuse references | Architecture — Shared command layer |

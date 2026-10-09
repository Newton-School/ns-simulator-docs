# Chaos Experiments

A chaos experiment asks one question of a design: **does it keep its steady state while
something goes wrong?** The simulator runs it as an ordinary, deterministic simulation:
the experiment is compiled into scheduled faults (plus a traffic spike, if it has one), the
engine runs once, and the checks are evaluated over the run's one-second windows. The same
experiment on the same design and seed always gives the same verdict.

---

## Running one

1. Click **Run**. The Workload panel opens.
2. In the **Chaos experiment** section, pick an experiment from the list. The panel shows a
   one-line summary, the timeline (when each step happens) and the steady-state checks.
3. Optional: **Compose another experiment** to run a second preset in the same simulation,
   starting **After (s)** seconds into the first (for example a cache stampede 5 s into a
   traffic spike).
4. Click **Start Experiment**. The experiment sets its own duration and warmup, overriding
   the ones above. While an experiment is selected, the single **Chaos - inject a failure**
   setting below it is not used.

The verdict appears at the top of the Results **Overview** tab, with every check, its
measured value and the window it covered. **What this experiment models** lists, in plain
words, what the engine does and does not model for that experiment, so a pass is never read
as more than it is.

## How an experiment is structured

| Phase | What happens |
|---|---|
| Warmup | Discarded transient, as in any run. |
| Steady state (baseline) | The steady-state checks must hold before anything is injected (defaults: error rate below 1% and p99 below 500 ms). |
| Steps | `inject` a fault, `restore` it, `traffic` (multiply the base RPS for a while), `wait`, and `verify` (checks over the window since the previous step). |
| Final check | The steady state must hold again at the end (recovery). |

A check is a metric (error rate, p50 / p95 / p99 latency, throughput), an operator and a
value, either system-wide or for one node. A check with no operator is an **observation**:
reported, never failing (for example "load on the origin during the flush").

**Verdicts:**

- **Passed** - every check held.
- **Failed** - at least one check did not hold (each one is listed).
- **Not stable** - the steady state did not hold before the first fault, so the experiment
  stopped there. Fix the design under normal load first.
- **Inconclusive** - the load was heavy enough that the run used the analytic (fluid) model,
  which does not inject faults.

## The presets

| Preset | What it does | What it needs from the design |
|---|---|---|
| **Cache stampede** | Empties a cache (the `cache-flush` fault) and checks its origin absorbs the misses while it re-warms. | A cache (cdn, in-memory cache or reverse proxy) with an origin behind it. A derived (LRU) cache loses its contents and re-warms from traffic; a declared-rate cache misses every request for 5 s and then returns at once. With **Request collapsing** on, the origin sees about one call per hot key instead of one per request. |
| **Database failover** | Crashes the primary database and checks the replica keeps requests succeeding. | A second database as the replica, and a health-aware router (load balancer, gateway, ingress or reverse proxy) that routes to both. The engine has no replica-promotion action here: "failover" means traffic stops going to the failed primary. |
| **Traffic spike** | Multiplies the base traffic for a while and checks the system degrades gracefully and recovers. | Headroom, autoscaling or admission control (rate limiting, load shedding). Autoscaling reacts once per cooldown, so capacity lags the spike. |
| **AZ outage** | Fails every component inside one Availability Zone for 10 s and checks the error rate stays within a 5% budget. | Region / AZ boxes on the canvas, a replica of every tier in another zone, and a health-aware load balancer outside the failed zone that routes to both. The surviving zone carries the whole load, so size it for that. |

When a design cannot run a preset (no cache, no second database, no zones), the panel says
why instead of running it. When a design can run it but cannot pass, the notes say so
up front (for example "All traffic enters through zone A, so nothing can route around it").

## Fault domains (Region / AZ / Subnet)

A fault can target a **Region, Availability Zone or Subnet** box as well as a single component,
both in the AZ outage preset and in the **Chaos - inject a failure** setting. A container fault
fails every component placed inside it, including nested boxes, for the fault's window. The
traffic source is never failed (it stands for the client population). If two outages overlap,
members stay down until both have recovered. The Failures tab, the Event Log, the causal graph
and the terminal name the zone that caused each failure.

## Composing experiments

When several experiments run together, the rules are deterministic and are listed in the
composed experiment's notes:

- Warmup and baseline are the longest of the inputs; each experiment's first step starts its
  offset after the shared baseline.
- The steady state is the union of all steady-state checks.
- Two faults on the same node: the later one wins and cuts the earlier one short.
- Only one traffic spike runs per simulation: the one that starts last wins.

## Stepping through a run

While a run is paused, **Step** advances it by a small batch of events, so you can watch an
injected fault take effect. The in-app terminal has the same controls (`pause`, `step 50`,
`resume`).

## What is not modelled

- Outages that start on their own: a component or zone fails only when a fault targets it.
- A zone that is slow or lossy rather than down, and network partitions between zones that are
  both up.
- Clients holding a cached DNS answer that still points at a failed region, and cross-region
  replication lag.
- Health-check detection delay, unless a health-check manager is configured: load balancers
  otherwise see a failed node at once.
- Clients backing off on their own during a traffic spike. On a Poisson workload, a spike runs
  with evenly spaced arrivals.
- Running a preset from the sim cli. Also note that the same preset can pass in the app and
  fail headlessly, because loading a design onto the canvas fills in default resources.

# Replication Quorum — State Machine Walkthrough

Date: 2026-09-02

A worked trace of one request moving through the replication capability, from the
cluster state machine down to the entries stamped on the request's
`stateTimeline`. Read this alongside `support-ledger-and-runtime-semantics.md`
(what the timeline is) and `runtime-semantic-criteria.md` (how to grade it).

## 1. Two state machines, one request

Replication involves **two** state machines working together:

1. **The cluster** (`ReplicaCluster` in `src/engine/semantics/v2StateMachines.ts`)
   — long-lived, shared across the run. Each replica member is in one role:

   ```
   [leader] ──fail()──> [failed] ──recover()──> [follower]
   [follower] ──elect() (leader gone)──> [leader]
   ```

   The cluster remembers membership, each member's `role`/`term`/`appliedIndex`/
   `durableIndex`, the consensus protocol (`raft`/`none`), and quorum size
   (`floor(n/2)+1`). It lives in run-scoped `sharedState`, so every request in
   the run sees the *same* cluster — that is what makes leader election and
   quorum loss observable across requests.

2. **The request** — short-lived. Each request that hits a replicating datastore
   asks the cluster to do something (a write, a replica read) and the *result*
   of that interaction is stamped onto the request's own `stateTimeline` under
   the `replication` scope. This is the per-request state machine that grading
   reads.

The trait that connects them is `replicationTrait`
(`src/engine/traits/replication.ts`), on `relational-db` / `nosql-db` nodes with
`replicationEnabled: true`.

## 2. The `replication` timeline states

A request can pick up any of these `replication`-scope transitions
(`REPLICATION_TIMELINE_STATES`):

| state | meaning |
| --- | --- |
| `quorum-committed` | a write was acknowledged by a quorum of healthy replicas |
| `quorum-unavailable` | a write could not reach quorum (too few healthy replicas) |
| `replica-read` | a read was served from a follower replica |
| `stale-read-possible` | that replica has non-zero lag, so the read may be stale |
| `leader-promoted` | a follower was elected leader (records the new leader id) |
| `failover-in-progress` | traffic was rejected while promotion was underway |

These are emitted by `deriveTraitStateTransitions` from the payload fields the
trait returns — the trait produces `replicationWriteAck`,
`replicationQuorumUnavailable`, `replicationLeader`, etc., and the engine
translates each into a timeline transition. All are matchable in a
`stateTransition` / `stateSequence` criterion (`scope: "replication"`).

## 3. Trace A — a healthy quorum write (the happy path)

Setup: `db-a, db-b, db-c` (quorum size = 2), `writeAckPolicy: quorum`,
`replicationLagMs: 8`, `replicationEnabled: true`. A `write` request arrives at
the leader `db-a`.

Step by step inside `replicationTrait.beforeArrival`:

1. `replicationEnabled` is true → continue into the model.
2. `failoverUntilMs` is 0 → not in a failover window.
3. Role is `primary`, request type is `write` → do a quorum write.
4. `requiredAcks = cluster.quorumSize()` = 2. Call `cluster.write(2)`.
5. Inside the cluster: leader `db-a` exists, healthy replicas = 3 ≥ 2 → commit.
   `appliedIndex` advances 0→1 on all healthy members; returns
   `{ committed: true, acknowledgements: 3, quorumSize: 2 }`.
6. Back in the trait: `ackPolicy === 'quorum'` and `lagMs > 0`, so it sets the
   request's service time to the 8ms quorum latency and returns:

   ```json
   {
     "action": "continue",
     "payload": {
       "replicationWriteAck": "quorum",
       "replicationLeader": "db-a",
       "replicationConsensusProtocol": "raft",
       "replicationLagMs": 8,
       "metricCounters": { "replicationQuorumWrites": 1 }
     }
   }
   ```

**Resulting request `stateTimeline`** (request scope + replication scope
interleaved by the engine):

```
request      generated
request      admitted
replication  quorum-committed      (from replicationWriteAck: "quorum")
replication  stale-read-possible   (from replicationLagMs: 8 > 0)
replication  leader-promoted db-a  (records the acting leader id)
request      processing            (8ms quorum latency applied)
request      completed
```

Run-wide the verdict shows `traitCounters.replicationQuorumWrites` summed across
the run. The request ends `completed`.

## 4. Trace B — quorum lost (two of three replicas down)

Same cluster, but `db-b` and `db-c` have failed (only the leader is healthy). A
`write` arrives.

1–4. As before, `requiredAcks = 2`, call `cluster.write(2)`.
5. Inside the cluster: healthy replicas = 1 `< 2` → **not committed**. Returns
   `{ committed: false, acknowledgements: 1, quorumSize: 2, leaderId: "db-a" }`.
6. The trait rejects:

   ```json
   {
     "action": "rejected",
     "reason": "quorum_unavailable",
     "payload": {
       "replicationQuorumUnavailable": true,
       "replicationLeader": "db-a",
       "replicationAcknowledgements": 1,
       "replicationRequiredAcks": 2,
       "metricCounters": { "replicationQuorumFailures": 1 }
     }
   }
   ```

**Resulting `stateTimeline`:**

```
request      generated
request      admitted
replication  quorum-unavailable    (from replicationQuorumUnavailable: true)
replication  leader-promoted db-a
request      rejected              (terminal: reason "quorum_unavailable")
```

The distributed failure is now a first-class, gradeable fact — not a latency
number and not prose. This is the honesty payoff: a design that under-replicates
(cannot form a quorum under one failure) *fails a runtime check*, not a
reviewer's opinion.

## 5. Trace C — failover (leader dead, follower elected)

The leader node's `nodeState.status` is `failed` when a write arrives.

1. The trait sees `nodeState.status === 'failed'`.
2. It calls `cluster.fail(node.id)` — the dead member's role becomes `failed`.
3. It calls `cluster.elect()` — among healthy members, the one with the highest
   `appliedIndex` (ties broken by id) is promoted to `leader`, and the term is
   bumped. Returns the promoted member.
4. The trait rejects the in-flight request during the promotion:

   ```json
   {
     "action": "rejected",
     "reason": "replica_failover_in_progress",
     "payload": {
       "replicationLeader": "db-b",
       "metricCounters": {
         "replicationFailoverRejects": 1,
         "replicationLeaderPromotions": 1
       }
     }
   }
   ```

**Resulting `stateTimeline`:**

```
request      generated
request      admitted
replication  failover-in-progress
replication  leader-promoted db-b   (the newly elected leader)
request      rejected               (reason "replica_failover_in_progress")
```

Because the cluster lives in `sharedState`, the *next* request in the run sees
`db-b` as leader and can commit normally — the promotion persisted. That
cross-request continuity is exactly what a single-node model cannot express.

## 6. Trace D — a stale replica read

A `read` request, on a node with `replicationRole: replica` and
`replicationLagMs: 40`.

The trait short-circuits at the read branch: returns `continue` with
`replicationRead: "replica"` and, because lag > 0, `replicationStaleReadsPossible`.

**Resulting `stateTimeline`:**

```
request      generated
request      admitted
replication  replica-read
replication  stale-read-possible
request      processing
request      completed
```

The read succeeds, but the timeline honestly flags that it *may* be stale — so a
question that forbids stale reads can assert
`stateTransition {scope:"replication", state:"stale-read-possible"}` with
`maxCount: 0`.

## 7. Grading these timelines

Author against the `replication` scope with the runtime semantic criteria
(`runtime-semantic-criteria.md`). Examples as `SEMANTIC_CRITERION` rows:

```json
{ "type": "SEMANTIC_CRITERION", "id": "no-quorum-loss", "kind": "stateTransition",
  "match": { "scope": "replication", "state": "quorum-unavailable" },
  "maxCount": 0, "points": 4, "hardFail": true,
  "description": "The write path never loses quorum under the injected failure" }
```

```json
{ "type": "SEMANTIC_CRITERION", "id": "durable-writes", "kind": "stateTransition",
  "match": { "scope": "replication", "state": "quorum-committed" },
  "minCount": 1, "points": 2,
  "description": "At least one write commits via quorum" }
```

```json
{ "type": "SEMANTIC_CRITERION", "id": "no-stale-reads", "kind": "stateTransition",
  "match": { "scope": "replication", "state": "stale-read-possible" },
  "maxCount": 0, "points": 2,
  "description": "Reads must not be served from a lagging replica" }
```

Dual-Topology check: a 3-replica quorum design records `quorum-committed` and 0
`quorum-unavailable` under a one-node failure (PASS); a 2-replica or
primary-only design loses quorum on the same failure → `quorum-unavailable > 0`
(FAIL).

## 8. What is not modeled (the honest boundary)

From the trait's `honesty.notModeled`: **packet-level log replication, real Raft
election timing, and Byzantine consensus** are not simulated. The cluster is a
deterministic bookkeeping model — roles, indices, quorum arithmetic, and a
configured failover window — not a wire-level consensus implementation. It is
enough to make quorum loss, leader promotion, and stale reads *observable and
gradeable*, which is the goal; it is not a Raft implementation.

## 9. Code map

- Cluster state machine: `src/engine/semantics/v2StateMachines.ts` (`ReplicaCluster`)
- Trait: `src/engine/traits/replication.ts` (`replicationTrait`)
- Timeline states + derivation: `src/engine/core/simulationSemantics.ts`
  (`REPLICATION_TIMELINE_STATES`, `deriveTraitStateTransitions`)
- Matcher schema: `src/engine/analysis/gradingCriteria.ts` (`ReplicationStateTransitionMatcher`)
- Run-wide counters: `src/engine/analysis/verdict.ts`
- Tests: `src/engine/semantics/v2StateMachines.test.ts`, `src/engine/traits/*replication*`

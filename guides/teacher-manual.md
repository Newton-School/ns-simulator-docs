# Teacher Manual - Using the ns-simulator in Teaching

A reference for instructors: how to use the simulator live in lectures, how to reason
about flow and capacity, and how to author assignments that actually discriminate.
The last section separates **V1 capabilities** from the **roadmap** so you set student
expectations correctly.

---

## 1. Using the simulator in a lecture

The simulator is a **reactive physics sandbox** - change the graph, re-run, watch the
numbers move. That live feedback is the teaching tool.

Suggested live flow:
1. Start from a **Client → Service → Database** graph. Run it. Show it's healthy at
   low load.
2. Raise the injected RPS (or load a read-heavy scenario) until the **database
   saturates** - utilization hits 100%, rejects climb, p99 explodes.
3. Ask the room: "scale the DB, or shield it?" Add a **cache** on the read path,
   re-run, and show the store load collapse and p99 recover.
4. Break it deliberately (remove the cache, undersize the workers) to show the
   failure mode. This *is* the lesson.

Good built-in scenarios to teach from live: the D/D/1 vs jittered-arrival pair (queue
theory), the monolith-core bottleneck trace, and the proxy-edge shield.

## 2. Reasoning about flow & capacity (what to point at)

- **Utilization** is the headline capacity signal. A node at ~100% is the bottleneck;
  everything upstream queues behind it.
- **Throughput (req/s)** is what the system actually sustains - compare it to the
  arrival rate. If throughput << arrivals, work is being dropped.
- **Rejected / Timed-out** localize *where* the drop happens.
- **p50 vs p99** shows tail behavior. Note for students: under heavy saturation p99
  plateaus near the timeout, so read it together with utilization/throughput.
- **Little's Law intuition**: concurrency ≈ arrival rate × service time. If a node's
  worker pool is smaller than that, it saturates. This is the single most useful
  back-of-envelope check to teach.

## 3. Designing an assignment

Author questions as a **QuestionPackage** (JSON). The workflow:

1. **Write the brief** in the 5-part shape (scenario, functional requirements as
   *paths*, measurable NFRs, scale/ratio cue, budget). Show the ratio; don't name the
   answer.
2. **Map every requirement to a check** - no orphan requirements:
   - shape/topology → `structuralRules` + `semanticCriteria`
     (`storageFit`, `placement`, `guardedPath`, `fanout`);
   - performance → `rubric` checks over `summary.*` metrics;
   - narrative → prose only.
3. **Keep the load tractable** - `baseRps` ~2,000-5,000 with a typed
   `requestDistribution`; put the real number in `prompt.scale` for display.
4. **Set `hardFail: true`** on architecturally naive mistakes (e.g. a relational DB
   for 200K time-series writes).
5. **Run the Dual-Topology test** before shipping:
   ```bash
   npx tsx scripts/validate-question-dir.ts \
     ../system-design-simulator-questions/questions/<id>
   ```
   Expect: the **reference** design PASSES all checks; the **gamed** design FAILS on
   the intended axis. A question that hasn't been graded both ways isn't authored.

The 12 bank questions under `system-design-simulator-questions/questions/` are worked
examples - each ships with a `question.json`, a passing `reference-topology.json`, a
failing `gamed-topology.json`, and a README explaining the discriminator.

### Choosing what a question grades on
Match the discriminator to the threshold:
- Latency thresholds **below ~1000 ms** discriminate well via `summary.latency.p99`.
- **Higher** thresholds (multi-second) should discriminate on a
  structural/semantic axis or on `summary.throughput` / `summary.errorRate`, because
  saturated p99 plateaus near the timeout.

## 4. Environment profiles

- **AUTHOR** - your standalone/authoring view. Load a question and Open a solution
  topology side-by-side to test your rubric.
- **ASSIGNMENT** - what students get in a graded assignment: locked chrome, rubric
  hidden until submit.
- **PRACTICE** - self-paced, live rubric feedback.

---

## 5. V1 capabilities vs. roadmap (set expectations)

| Capability | V1 | Roadmap |
|-----------|----|---------|
| Physics (latency/throughput/utilization/errors, queueing, saturation) | ✅ | tuning & more distributions |
| Structural + semantic grading | ✅ | more criteria kinds |
| Simulation rubric grading | ✅ | - |
| Live budget meter (v1 cost heuristic) | ✅ | real price-sheet cost model |
| Dual-topology authoring + validator | ✅ | authoring UI in-app |
| **Written justification grading** | ❌ **hidden** (deterministic keyword matcher was confusing) | LLM-assisted defense grading |
| Request **body / endpoint / status codes** | ❌ (type/size/path only) | first-class payload model |
| Editable read/write mix on canvas | ❌ (question-owned JSON) | on-canvas mix + auto-derivation |
| Connect-time design lint (Client→DB) | ❌ (errors surface on Run) | live design-smell hints |
| Server-side grading | ❌ (client-only via iframe) | optional server re-grade |
| Advanced/long-tail node behaviors, composite fault domains | partial | deeper modeling |

**Teaching note for V1:** grade and discuss **architecture and measured behavior**.
Correctness properties the physics can't measure (exactly-once, no-double-booking,
encoding choices) should be discussed verbally in class for now - the in-app written
defense returns in V2.

# Replication V2 Quorum

Canonical pack for the replicated-log state machine.

- `reference-topology.json` enables a quorum-replicated relational store with durable member state.
- `gamed-topology.json` keeps the same visible database shape but disables runtime replication, so it cannot emit `replication:quorum-committed`.
- The discriminator is runtime evidence, not the presence of replica labels.

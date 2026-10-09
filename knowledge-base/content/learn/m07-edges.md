---
title: "M07 - Edges: Network Physics vs Connectors"
type: module
duration: 1 lecture
tags: [module]
---
## Objectives
Explain edge properties, path-type latency, conditional routing, and the network vs
connector edge model.

## Concepts (atomic notes)
- [[concepts/network/latency-is-dominated-by-path-type|Edge latency is dominated by path type]]
- [[concepts/network/edge-concurrency-caps-inflight-requests|Edge concurrency caps in-flight requests]]
- [[concepts/network/connector-edges-carry-no-physics|Connector edges carry no physics or cost]]
- [[concepts/network/bandwidth-adds-transmission-and-link-queueing-delay|Edge bandwidth adds transmission time and link queueing]]
- [[concepts/network/tls-1-3-saves-a-round-trip-on-a-new-connection|TLS 1.3 saves a round trip on every new connection]]
- [[concepts/network/http2-multiplexing-removes-head-of-line-waits-at-the-pool|HTTP/2 multiplexing removes head-of-line waits at the connection pool]]
- [[concepts/network/producer-batching-trades-latency-for-throughput|Producer batching trades latency for throughput]]

## Teaching vehicle
[[p01-static-image-board|P01 - Image Board]] (cross-ocean internet hop) and
[[p07-live-sports-scoreboard|P07 - Live Scoreboard]] (edge concurrency limit → WebSocket proxies).

## Source of truth (specs)
- [[edge-properties-and-defaults|edge-properties-and-defaults.md]] · [[request-flow-direction-and-topology-rules|request-flow-direction-and-topology-rules.md]]

## Demo
Same topology under network vs connector edges; egress cost appears/vanishes. Then turn
on the connection model on one edge (Per request vs Keep-alive, TLS 1.2 vs 1.3) and compare
the handshake and connection-wait rows of the edge's latency breakdown.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m06-execution-profiles|M06]] · Next [[m08-traits|M08]]

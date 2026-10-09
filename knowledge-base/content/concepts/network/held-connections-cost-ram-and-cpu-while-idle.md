---
title: "Held connections cost RAM and CPU even when idle"
cluster: network
tags: [concept, network]
---
A WebSocket or push gateway keeps every client's connection open. An idle connection is
not a request, but it pins memory (buffers, TLS state) and needs keepalive heartbeats. So a
connection tier is bounded by connections, not requests per second: each box holds at most
its per-instance limit and as many as fit in RAM, the rest are refused, the pinned RAM leaves
less room for request work, and heartbeats take CPU from it. A push then costs one write per
connected recipient. The simulator models this on the Connection Server node.

**Because:** [[compute/derive-and-lock-prices-concurrency|Derive-and-lock makes concurrency cost money]]
**Contrast:** [[network/edge-concurrency-caps-inflight-requests|Edge maxConcurrentRequests caps in-flight requests]]
**Seen in:** [[p07-live-sports-scoreboard|Problem 7 - Live Scoreboard]]
**Spec:** [[connection-tier-capacity|connection-tier-capacity.md]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

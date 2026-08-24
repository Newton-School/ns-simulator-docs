---
title: "Edge maxConcurrentRequests caps in-flight requests"
cluster: network
tags: [concept, network]
---
An edge has a finite concurrent-request ceiling (a TCP/connection analogue). Hit it
and new requests block or drop, independent of the nodes at either end - which forces
patterns like localized WebSocket proxies.

**Seen in:** [[p07-live-sports-scoreboard|Problem 7 - Live Sports Scoreboard]]
**Taught in:** [[m07-edges|M07 - Edges]]

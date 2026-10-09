---
title: "Edge maxConcurrentRequests caps in-flight requests"
cluster: network
tags: [concept, network]
---
An edge has a finite concurrent-request ceiling (a TCP/connection analogue). Hit it
and new requests are refused (`connection_refused`), independent of the nodes at either end -
which forces patterns like localized WebSocket proxies. As the cap fills, the engine also
stretches each transfer's latency (by up to 50x), so slots are held longer and a saturated
small cap collapses rather than levelling off.

**Seen in:** [[p07-live-sports-scoreboard|Problem 7 - Live Sports Scoreboard]]
**Taught in:** [[m07-edges|M07 - Edges]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

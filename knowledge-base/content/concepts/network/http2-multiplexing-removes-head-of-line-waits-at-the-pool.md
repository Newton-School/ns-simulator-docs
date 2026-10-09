---
title: "HTTP/2 multiplexing removes head-of-line waits at the connection pool"
cluster: network
tags: [concept, network]
---
An HTTP/1.1 connection carries one request at a time, so when every connection in a
capped pool is busy the next request waits for one to free up (head-of-line blocking at the
pool). HTTP/2 (gRPC) carries many concurrent streams on one connection, 100 by default, so the
same small pool keeps serving. In the simulator, with the edge connection model on, the wait
is reported as **connection wait** and a waiter whose deadline passes times out.

**Because:** [[network/tls-1-3-saves-a-round-trip-on-a-new-connection|TLS 1.3 saves a round trip on every new connection]] (fewer connections means fewer handshakes)
**Leads to:** [[network/synchronous-blocking-exhausts-connection-pools|Synchronous blocking exhausts connection pools]]
**Taught in:** [[m07-edges|M07 - Edges]]
**Spec:** [[edge-properties-and-defaults|edge-properties-and-defaults.md]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

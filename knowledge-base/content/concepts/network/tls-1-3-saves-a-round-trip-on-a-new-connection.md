---
title: "TLS 1.3 saves a round trip on every new connection"
cluster: network
tags: [concept, network]
---
Opening a connection costs round trips before the first byte of the request: TCP
takes 1, then TLS 1.2 takes 2 more, TLS 1.3 only 1 more. So a fresh HTTPS connection costs
3 round trips on TLS 1.2 and 2 on TLS 1.3, and on a cross-region edge each round trip is
tens of milliseconds. Session resumption shortens later handshakes (TLS 1.2: 1 round trip,
TLS 1.3: none), and keep-alive avoids them entirely by reusing the warm connection. In the
simulator this is the opt-in edge connection model; one round trip is one sample of the
edge's latency, and the cost appears as **handshake** time.

**Leads to:** [[network/http2-multiplexing-removes-head-of-line-waits-at-the-pool|HTTP/2 multiplexing removes head-of-line waits at the connection pool]]
**Contrast:** [[network/connector-edges-carry-no-physics|Connector edges carry no physics or cost]]
**Taught in:** [[m07-edges|M07 - Edges]]
**Spec:** [[edge-properties-and-defaults|edge-properties-and-defaults.md]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

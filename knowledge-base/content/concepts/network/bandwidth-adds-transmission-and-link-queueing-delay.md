---
title: "Edge bandwidth adds transmission time and link queueing"
cluster: network
tags: [concept, network]
---
An edge is one pipe of `bandwidth` Mbps. A payload of S bytes holds it for
S / (bandwidth x 125) ms, and a transfer that arrives while the pipe is still sending an
earlier payload waits its turn (first come, first served). So big payloads on a thin link
cost latency twice: once to send, and again waiting behind each other. The wait shows up as
**link queue** in the edge's latency breakdown. Only the request direction is modelled
(responses do not cross edges).

**Because:** [[network/latency-is-dominated-by-path-type|Edge latency is dominated by path type]] (the path type also sets the default bandwidth)
**Leads to:** [[network/producer-batching-trades-latency-for-throughput|Producer batching trades latency for throughput]]
**Seen in:** [[p01-static-image-board|Problem 1 - Image Board]]
**Taught in:** [[m07-edges|M07 - Edges]]
**Spec:** [[edge-properties-and-defaults|edge-properties-and-defaults.md]]
**Map:** [[maps/simulator-physics|Simulator Physics]]

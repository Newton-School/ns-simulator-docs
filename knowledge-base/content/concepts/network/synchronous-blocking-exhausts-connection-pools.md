---
title: "Synchronous blocking exhausts connection pools"
cluster: network
tags: [concept, network]
---
A request that blocks synchronously on a slow downstream holds its worker/connection
the whole time. Enough slow calls exhaust the pool and cause timeouts - even while CPU
sits near 1%. The fix is async decoupling.

**Because:** [[network/edge-concurrency-caps-inflight-requests|Edge concurrency caps in-flight requests]]
**Seen in:** [[p06-notification-gateway|Problem 6 - Notification Gateway]]
**Taught in:** [[m02-request-lifecycle|M02 - Request Lifecycle]]

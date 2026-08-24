---
title: "A closed terminal taxonomy enables honest error accounting"
cluster: simulation
tags: [concept, simulation]
---
Every request ends in exactly one terminal: success, timeout, capacity_exceeded,
oom, connection_reset, or an edge failure. A closed set means every failure is
attributed to a cause - no silent losses, no double counting.

**Seen in:** [[p06-notification-gateway|Problem 6 - Notification Gateway]]
**Taught in:** [[m02-request-lifecycle|M02 - Request Lifecycle]]
**Spec:** [[arrival-departure-and-request-lifecycle-semantics|arrival-departure-and-request-lifecycle-semantics.md]]

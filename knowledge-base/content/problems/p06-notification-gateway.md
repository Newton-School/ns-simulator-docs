---
title: "Problem 6 - Notification Gateway"
type: problem
cluster: Request lifecycle + blocking
tags: [problem]
---
**Purpose:** a slow 3rd-party banking/email API makes synchronous calls exhaust the
connection pool - timeouts and connection resets while CPU sits near 1%.

## Teaches (concepts)
- [[concepts/network/synchronous-blocking-exhausts-connection-pools|Synchronous blocking exhausts connection pools]]
- [[concepts/simulation/closed-terminal-taxonomy-enables-honest-errors|A closed terminal taxonomy enables honest errors]]

## Related modules
- [[m02-request-lifecycle|M02 - Request Lifecycle]]

## Related problems
- [[p13-taylor-swift-news-feed|P13 - News Feed]] (async decoupling)

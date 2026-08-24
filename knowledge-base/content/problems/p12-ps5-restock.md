---
title: "Problem 12 - PS5 Restock"
type: problem
cluster: Lock contention + effective concurrency
tags: [problem]
---
**Purpose:** a row lock pins effectiveC to 1 on the hot key, so hardware scaling is
useless - and locking the resource capability forces the architectural fix.

## Teaches (concepts)
- [[concepts/storage/row-locks-serialize-writes|Row locks serialize writes]]
- [[concepts/compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]

## Related modules
- [[m05-instance-model|M05 - Instance Model]] · [[m13-environment-profiles|M13 - Environment Profiles]]

## Related problems
- [[p02-video-transcoder|P02 - Transcoder]] (where scaling *does* work) · [[p08-flash-sale|P08 - Flash Sale]]

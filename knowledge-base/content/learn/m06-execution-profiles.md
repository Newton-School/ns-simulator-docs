---
title: "M06 - Execution Profiles: CPU vs IO-bound"
type: module
duration: 0.5 lecture
tags: [module]
---
## Objectives
Explain why datastores show 64-128 "workers" while services show 2 - and how to flip a
store into a bottleneck.

## Concepts (atomic notes)
- [[concepts/compute/cpu-bound-is-one-worker-per-vcpu|CPU-bound gets one worker per vCPU]]
- [[concepts/compute/io-bound-multiplexes-many-per-vcpu|IO-bound multiplexes many per vCPU]]

## Teaching vehicle
[[p02-video-transcoder|Problem 2 - Video Transcoder]] - toggle a worker io→cpu-bound and
watch it choke on heavy compute (multiplexing doesn't help CPU work).

## Source of truth (specs)
- [[execution-profile-and-node-concurrency|execution-profile-and-node-concurrency.md]]

## Demo
A DB reading 128 "connections" - derive it live, then flip to cpu-bound and watch it
collapse. ## Exercise: pick a profile+instance that makes a store the intended bottleneck.

---
Curriculum map → [[learn/_moc|Modules]] · Prev [[m05-instance-model|M05]] · Next [[m07-edges|M07]]

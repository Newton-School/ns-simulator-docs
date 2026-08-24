---
title: "Simulator Physics"
type: moc
tags: [moc]
---
> The mathematical reality of the engine: time, requests, queues, compute, network,
> and cost. Every claim here is enforced by the simulation, not decoration.

## Time
- [[concepts/simulation/discrete-event-simulation-advances-time-through-events|Discrete-event simulation advances time through events]]
- [[concepts/simulation/warmup-removes-transient-behavior|Warmup removes transient behavior]]
- [[concepts/simulation/steady-state-differs-from-transient|Steady-state behavior differs from transient behavior]]

## Requests
- Request lifecycle · terminal states · timeout · connection reset - see [[m02-request-lifecycle|M02]]

## Queues
- [[concepts/queueing/ggck-models-finite-capacity-queues|G/G/c/K models finite-capacity queues]]
- [[concepts/queueing/queue-saturation-precedes-cpu-saturation|Queue saturation precedes CPU saturation]]
- [[concepts/queueing/queue-depth-is-a-leading-indicator-of-latency|Queue depth is a leading indicator of latency]]

## Compute
- [[concepts/compute/effective-concurrency-determines-service-capacity|Effective concurrency determines service capacity]]
- cpu-bound vs io-bound · vCPU · service time - see [[m06-execution-profiles|M06]]

## Network
- latency · bandwidth · path types · concurrent connections - see [[m07-edges|M07]]

## Cost
- compute cost · egress · budget constraints - see [[m09-cost-model|M09]]

## Modules that cover this
- [[m01-discrete-event-simulation|M01]] · [[m03-queueing-model|M03]] · [[m05-instance-model|M05]] · [[m06-execution-profiles|M06]]

## Problems that exercise this
- [[p04-iot-ingestion|P04 IoT Ingestion]] · [[p05-live-voting|P05 Live Voting]] · [[p02-video-transcoder|P02 Transcoder]]

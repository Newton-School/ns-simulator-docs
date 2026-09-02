# Protocol V2 Session

Canonical pack for protocol/session runtime semantics.

- `reference-topology.json` routes allowed order traffic through an open HTTP/2 API gateway.
- `gamed-topology.json` keeps the API gateway shape but closes the session, so it cannot emit gateway-level `protocol:session-open` or `protocol:http-acknowledged`.
- The discriminator is node-bound runtime evidence, not merely selecting an API gateway.

# GraphX Connect roadmap

Contract: see [contract.md](contract.md).

## Finish now

1. Make `graphx_connect` the small common core.
2. Move WebRTC into `graphx_connect_webrtc`.
3. Move Nearby into `graphx_connect_nearby`.
4. Add `graphx_connect_socket` with WebSocket first, then TCP/UDP.
5. Keep one shared `GSession`/message/lifecycle implementation in core.
6. Migrate Pixel Retro Games to the optional packages and use it as realtime
   acceptance coverage.

## Required validation

- WebRTC: web/native combinations, direct path, TURN fallback, disconnect/rejoin.
- Nearby: real iOS <-> Android discovery, pair, bytes, disconnect/rejoin,
  permissions, background/resume behavior.
- WebSocket: web + native client against a normal server.
- TCP/UDP: native targets only; explicit unsupported behavior on web.
- No transport SDK types visible in application code.
- Raw binary hot path has no GraphX per-packet envelope unless explicitly chosen.

## Then

- shared `GIdentity` and small common options if real usage needs them;
- typed transport-specific option objects for advanced configuration;
- normalized errors/timeouts;
- connection diagnostics/capabilities for advanced callers;
- byte streams with backpressure;
- SSE receive-only source;
- media only when a concrete product requires it.

## Do not add

- game/player/match semantics to Connect;
- automatic transport negotiation without a real requirement;
- giant universal option objects;
- fake common behavior for transports that fundamentally differ;
- dependencies in core merely because a transport might be used.

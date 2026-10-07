# GraphX Connect contract

Connect is generic networking infrastructure, not a game API.

## Goal

Make common networking feel like GraphX: small, reliable, obvious defaults,
with advanced transport configuration available only when needed.

Normal code should think in:

```text
GConnect -> GConnection/GSession -> GPeer/GMessage
```

Never in ICE candidates, BLE, Bonjour, Nearby SDK objects, sockets, etc.

## Package shape

```text
graphx_connect
  common identity, lifecycle, messages, session protocol, SPI

graphx_connect_webrtc
  WebRTC + signaling + ICE/STUN/TURN

graphx_connect_socket
  WebSocket + TCP + UDP where supported

graphx_connect_nearby
  Google Nearby Connections for Android/iOS

graphx_connect_sse
  later; receive-only server events
```

Apps only pay for transports they import.

Optional packages add ergonomic `GConnect` extension methods:

```dart
const connect = GConnect(name: 'Device');

final session = await connect.webRtc(...);
// connect.nearby(...)
// connect.webSocket(...)
// connect.tcp(...)
```

Successful bidirectional transports converge on the same `GSession`.

## Core concepts

- identity is generic user/device/endpoint identity, never "player";
- session is generic, never "match";
- peer is a remote endpoint/participant, never "opponent";
- room/service/pairing are convenience inputs owned by the transport or app;
- raw bytes stay a fast path;
- protocol/capability negotiation happens once per connection;
- unsupported capabilities fail explicitly; never silently change transport.

## SPI rule

Transports provide I/O. Core owns GraphX behavior.

Core owns handshake, identity, protocol compatibility, normalized lifecycle,
errors, peer identity, message delivery and common reconnect semantics.

Transport packages own only their native/network machinery and typed advanced
options.

## Future capabilities

Messages are the first primitive. Do not turn `send()` into everything.

```text
messages       small packets / commands
byte streams   large or continuous bytes, with backpressure
media          audio/video only if a real use case needs it
sources        receive-only feeds such as SSE
```

Add streams only with bounded buffering, cancellation and measured backpressure.

## Application layers

Game-specific concepts belong above Connect, for example in Pixel Retro Games:

```text
GSession -> GameConnect/DuelSession -> players, match, ready, seed, rollback
```

The same Connect core must also fit remotes, tools, device control,
collaboration, server clients, file transfer and media.

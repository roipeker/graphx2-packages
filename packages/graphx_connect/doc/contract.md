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
final connect = GConnect(name: 'Device');

final socket = await connect.webSocket(...); // raw GConnection
final session = await socket.session(id: 'main'); // optional GraphX protocol

// Peer-oriented transports may expose sessions directly:
// connect.webRtc(...)
// connect.nearby(...)
```

Raw transports converge on `GConnection`. The GraphX peer/session protocol is
an optional layer, not a requirement for talking to arbitrary network services.

## Core concepts

- identity is generic user/device/endpoint identity, never "player";
- session is generic, never "match";
- peer is a remote endpoint/participant, never "opponent";
- room/service/pairing are convenience inputs owned by the transport or app;
- raw bytes stay a fast path;
- GraphX protocol/capability negotiation happens only when a `GSession` is used;
- unsupported capabilities fail explicitly; never silently change transport.

## SPI rule

Transports provide I/O. Core owns GraphX behavior.

Core owns raw connection lifecycle and the optional session layer. When a
`GSession` is used, core owns handshake, identity, protocol compatibility,
peer identity, message delivery and common reconnect semantics.

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

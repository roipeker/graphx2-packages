# graphx_connect direction

## Public contract

Keep the normal API to:

```text
GConnect
GSession
GPeer
GMessage
```

`GConnect` is the namespace for connection modes:

```dart
GConnect.local(...)
GConnect.remote(...)
```

Planned only after an implementation exists:

```dart
GConnect.nearby(...)
GConnect.server(...)
```

The returned mode object handles discovery or rendezvous. All successful modes
converge on `GSession`.

## Design rules

1. Session code never exposes WebRTC, Bluetooth, Bonjour, socket or ICE types.
2. Unsupported capabilities are explicit; do not silently change transport.
3. No automatic transport negotiation until a real product needs it.
4. Messages stay the primitive for games and control traffic.
5. Do not add streaming until backpressure, cancellation and bounded buffering
   have a measured contract.
6. Do not split the package merely for architectural symmetry. Split only when
   a backend creates a measurable build, dependency or platform problem.
7. Application protocols own meaning. GraphX Connect owns delivery and lifecycle.

## Current

- `local`: Bonjour/mDNS discovery + direct local WebSocket.
- `remote`: short-code rendezvous + ordered WebRTC DataChannel.
- multiple peers on hosted sessions;
- stable peer identity across explicit reconnects;
- structured messages and raw/sequenced binary packets;
- handshake-level protocol/binary-mode compatibility;
- RTT measurement.

## Nearby

Goal: offline mobile discovery + connection for iOS <-> Android.

Use Google Nearby Connections on both platforms so cross-platform pairing is a
hard requirement rather than an accidental platform-specific feature. The
public shape should stay small:

```dart
final nearby = GConnect.nearby(
  service: 'bit-arcade',
  name: 'Player',
);

final discovery = await nearby.discover();
final session = await nearby.join(found.session);
```

Do not expose BLE, Wi-Fi Direct, hotspot or Nearby SDK objects.

## Server sessions

A future `GConnect.server(...)` should connect intentionally to an application
server (WebSocket/TCP where supported) and still return `GSession`.

Do not confuse application-server traffic with WebRTC rendezvous/signaling.

## Streams

A future stream primitive is a sibling capability of messages, not a larger
`send()` API. Requirements before implementation:

- bounded buffering;
- backpressure;
- cancellation;
- measured chunk sizing;
- slow receiver behavior;
- allocation/copy measurements.

Realtime media should remain a separate capability if it is ever required.

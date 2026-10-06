# graphx_connect

Small peer sessions for games, remotes, tools, LAN devices and browser peers.

The package owns discovery, rendezvous, transport, peer identity and connection
lifecycle. It deliberately does **not** own game state, rollback, replication,
RPC schemas or UI.

## Remote / WebRTC

Host:

```dart
final connect = GRemoteConnect(
  Uri.parse('wss://connect.example.com/v1/connect'),
  name: 'Player 1',
);

final session = await connect.host('Air Hockey');

session.messages.listen((message) {
  final bytes = message.bytes;
  if (bytes != null) {
    game.onPacket(bytes);
  }
});

session.sendBytes(packet);
```

Join:

```dart
final connect = GRemoteConnect(
  Uri.parse('wss://connect.example.com/v1/connect'),
  name: 'Player 2',
);

final session = await connect.joinCode('K7P4DX');
```

A host may supply its own short code when the product already has one:

```dart
final session = await connect.host('Jumping Jack', code: '4821');
```

The signaling server only introduces peers. Application traffic travels over
an ordered WebRTC DataChannel.

### ICE / TURN

By default `serverIce: true`. A rendezvous server may include standard
`iceServers` in its `joined` or `config` message. This is the preferred
production setup because TURN credentials can be short-lived and permanent
provider secrets stay server-side.

Static ICE remains available as a fallback:

```dart
final connect = GRemoteConnect(
  rendezvous,
  serverIce: false,
  iceServers: const <GIceServer>[
    GIceServer(
      <String>['turn:turn.example.com:3478'],
      username: 'user',
      credential: 'temporary-secret',
    ),
  ],
);
```

## LAN

Native devices can advertise/discover a session through Bonjour/mDNS and then
talk over a direct WebSocket:

```dart
final hostConnect = GConnect(name: 'Living Room');
final host = await hostConnect.host('Remote Control');

final clientConnect = GConnect(name: 'Phone');
final discovery = await clientConnect.discover();
final found = await discovery.events.firstWhere(
  (event) => event.type == GDiscoveryEventType.found,
);
final client = await clientConnect.join(found.session);
```

LAN and WebRTC converge on the same `GSession`, `GPeer` and `GMessage`
API.

## Binary packets

Raw bytes are the default:

```dart
final connect = GRemoteConnect(
  rendezvous,
  binaryMode: GBinaryMode.raw,
);

session.sendBytes(packet);
```

`GBinaryMode.raw` adds **zero GraphX Connect bytes per packet**. Protocol
version and binary-mode compatibility are checked once during the session
handshake.

When sender sequencing is useful:

```dart
final connect = GRemoteConnect(
  rendezvous,
  binaryMode: GBinaryMode.sequenced,
);
```

`sequenced` prefixes a 4-byte unsigned sequence. No protocol version is
repeated on every packet.

Structured JSON-compatible messages remain available for infrequent control
traffic:

```dart
session.send(<String, Object?>{
  'type': 'ready',
  'seed': 1234,
});
```

## Peers and reconnect

Hosts can have multiple peers, broadcast, or target one:

```dart
session.sendBytes(packet);
session.sendBytes(packet, to: playerTwo);
```

`session.peerEvents` reports connect/reconnect/disconnect and `GPeer.latency`
contains the measured RTT. Joined clients may explicitly call
`session.reconnect()`; GraphX Connect does not hide an infinite retry policy
inside the transport.

## Native LAN setup

Android applications need internet and multicast access.

iOS/macOS applications using LAN discovery must declare local-network usage
and `_graphx._tcp` under `NSBonjourServices`. Sandboxed macOS apps also need
client/server networking entitlements.

## Current boundary

Good fits today:

- deterministic or rollback multiplayer games;
- phone/browser remote controls;
- LAN companion apps and tools;
- small structured messages;
- low-latency binary packets.

Not implemented yet:

- bounded/backpressured `sendStream`;
- file-transfer convenience;
- authoritative/server-backed application sessions;
- path diagnostics distinguishing direct LAN / direct WAN / TURN relay.

Large streaming is intentionally deferred until buffering, cancellation and
backpressure have a measured contract.

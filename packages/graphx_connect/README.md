# graphx_connect

Development contract: [doc/contract.md](doc/contract.md) · [roadmap](doc/roadmap.md)

Small peer sessions for games, remotes, tools and device-to-device features.

The public model is intentionally narrow:

```text
GConnect -> GSession -> GPeer / GMessage
```

Applications choose how peers become reachable. Once a `GSession` exists, game
and tool code does not depend on WebRTC, Bonjour, sockets, ICE, TURN or platform
radio APIs.

## Remote peers

```dart
final connect = GConnect.remote(
  Uri.parse('wss://connect.example.com/v1/connect'),
  name: 'Player 1',
);

final session = await connect.host(
  'Air Hockey',
  code: '4821',
);

session.messages.listen((message) {
  final bytes = message.bytes;
  if (bytes != null) game.onPacket(bytes);
});

session.sendBytes(packet);
```

Joining uses the same connector:

```dart
final connect = GConnect.remote(
  Uri.parse('wss://connect.example.com/v1/connect'),
  name: 'Player 2',
);

final session = await connect.join('4821');
```

The rendezvous server introduces peers and may provide short-lived ICE/TURN
configuration. Application traffic travels over an ordered WebRTC DataChannel.

## Local peers

```dart
final hostConnect = GConnect.local(name: 'Living Room');
final host = await hostConnect.host('Remote Control');

final clientConnect = GConnect.local(name: 'Phone');
final discovery = await clientConnect.discover();

final found = await discovery.events.firstWhere(
  (event) => event.type == GDiscoveryEventType.found,
);

final client = await clientConnect.join(found.session);
```

The current local backend uses Bonjour/mDNS for discovery and a direct local
WebSocket for the session.

## Session API

Remote and local connections converge on the same object:

```dart
session.send(<String, Object?>{
  'type': 'ready',
  'seed': 1234,
});

session.sendBytes(packet);

session.messages.listen(onMessage);
session.peerEvents.listen(onPeerEvent);

await session.disconnect(); // joined clients
await session.reconnect();  // one explicit attempt
await session.dispose();
```

Hosts may broadcast or target one peer:

```dart
session.sendBytes(packet);
session.sendBytes(packet, to: playerTwo);
```

Raw binary mode is the default and adds zero GraphX Connect bytes per packet.
`GBinaryMode.sequenced` adds a 4-byte sender sequence when that is useful.

## Platform capability

A connector reports whether its backend is available:

```dart
final local = GConnect.local();

if (local.supported) {
  final discovery = await local.discover();
}
```

Unsupported connection modes fail explicitly. GraphX Connect does not silently
replace one transport with another.

Current intent:

| Mode | Web | iOS | Android | macOS | Windows | Linux |
| --- | --- | --- | --- | --- | --- | --- |
| `remote` | yes | yes | yes | yes | yes | yes* |
| `local` | no | yes | yes | yes | yes | later |
| `nearby` | later | planned | planned | no | no | no |
| `server` | later | later | later | later | later | later |

`*` Subject to the underlying WebRTC backend supported by the application build.

`nearby` is intentionally not exposed until the iOS/Android implementation is
real and cross-platform. The target backend is Google Nearby Connections on
both mobile platforms rather than two incompatible discovery systems.

## Boundary

GraphX Connect owns:

- peer/session lifecycle;
- discovery/rendezvous adapters;
- stable peer identity;
- protocol compatibility;
- structured and binary messages;
- measured peer RTT.

Applications own:

- game state and simulation;
- rollback/prediction;
- RPC schemas;
- accounts and persistence;
- UI;
- reconnect policy beyond an explicit attempt.

Future streams, server sessions and nearby radio connections must converge on
`GSession`; they should not expand the ordinary game-facing API unless their
semantics cannot be represented cleanly.

## Native local setup

Android applications need internet and multicast access.

iOS/macOS applications using local discovery must declare local-network usage
and `_graphx._tcp` under `NSBonjourServices`. Sandboxed macOS apps also need
client/server networking entitlements.

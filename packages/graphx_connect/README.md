# graphx_connect

Transport-neutral connection core for the GraphX ecosystem.

It owns stable identity, raw `GConnection` lifecycle, the optional GraphX
`GSession` peer protocol, peers/messages/reconnect behavior, and the transport
SPI. Core has no Flutter, WebRTC, Nearby, mDNS or socket runtime dependency.

```dart
final connect = GConnect(name: 'My device');
```

Optional transport packages add methods to the same object.

A transport may expose a normal raw connection:

```dart
final socket = await connect.webSocket(uri);

socket.messages.listen(onRawMessage);
socket.sendText('hello');
socket.sendBytes(bytes);
```

When both ends speak the GraphX session protocol, the same connection can be
upgraded before raw use:

```dart
final socket = await connect.webSocket(graphxEndpoint);
final session = await socket.session(id: 'main');

session.messages.listen(onMessage);
session.sendBytes(packet);
session.peers;
```

Peer-oriented transports such as WebRTC/Nearby can expose `GSession`
directly when host/join semantics are intrinsic to that transport.

Package family:

- `graphx_connect_webrtc` — remote P2P WebRTC + signaling/ICE/TURN.
- `graphx_connect_nearby` — Google Nearby on Android/iOS.
- `graphx_connect_socket` — arbitrary WebSocket and native TCP connections,
  with optional GraphX sessions.
- SSE, UDP and byte streams are later capabilities.

Normal application code should stay around `GConnect`, `GConnection`,
`GSession`, `GPeer` and `GMessage`. Transport packages use
`graphx_connect_spi.dart`; applications normally should not.

See `doc/contract.md` and `doc/roadmap.md` for the implementation rules.

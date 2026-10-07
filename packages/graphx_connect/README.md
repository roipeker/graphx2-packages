# graphx_connect

Transport-neutral GraphX connection core. It owns identity, session handshake, peers, messages, reconnect lifecycle and the transport SPI. It has no runtime Flutter, WebRTC, Nearby, mDNS or socket dependency.

```dart
final connect = GConnect(name: 'My device');
```

Optional packages add connection methods to the same object:

```dart
final remote = connect.webRtc(signalServer);
final session = await remote.join('4821');

session.messages.listen(onMessage);
session.sendBytes(packet);
```

Package family:

- `graphx_connect_webrtc` — remote P2P WebRTC + signaling/ICE/TURN.
- `graphx_connect_nearby` — Google Nearby on Android/iOS.
- `graphx_connect_socket` — WebSocket and native TCP.
- SSE, UDP and byte streams are later capabilities.

The normal app API should stay around `GConnect`, `GSession`, `GPeer` and `GMessage`. Transport packages use `graphx_connect_spi.dart`; applications normally should not.

See `doc/contract.md` and `doc/roadmap.md` for the implementation rules.

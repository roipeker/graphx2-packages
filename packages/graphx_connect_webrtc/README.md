# graphx_connect_webrtc

WebRTC transport for `graphx_connect`.

```dart
import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_webrtc/graphx_connect_webrtc.dart';

final connect = GConnect(name: 'Player');
final remote = connect.webRtc(
  Uri.parse('wss://connect.example.com/ws'),
);

final session = await remote.join('4821');
session.sendBytes(packet);
```

Host with:

```dart
final session = await remote.host('My session', code: '4821');
```

The WebSocket server is rendezvous/signaling only. Peer traffic uses a WebRTC DataChannel. ICE/TURN remains internal; `GIceServer` is available only when static ICE configuration is needed. Server-provided short-lived ICE remains the preferred setup.

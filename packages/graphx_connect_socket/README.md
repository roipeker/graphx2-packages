# graphx_connect_socket

Socket transports for `graphx_connect`.

```dart
import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_socket/graphx_connect_socket.dart';

final connect = GConnect(name: 'Client');

final ws = await connect.webSocket(
  Uri.parse('wss://example.com/connect'),
  session: 'main',
);

final tcp = await connect.tcp(
  '192.168.1.20',
  port: 9000,
  session: 'main',
);
```

WebSocket works on web and native platforms. TCP is native-only and uses a small length-prefixed framing layer because TCP itself has no message boundaries. The remote endpoint must speak the GraphX Connect session protocol.

UDP is intentionally not exposed yet; datagram semantics will get their own contract rather than pretending UDP is a reliable stream.

## Acceptance test

The package includes a small GraphX-aware socket server and a public-API client.
It verifies the full session handshake, structured messages, raw bytes, RTT,
disconnect and reconnect over both TCP and WebSocket.

Terminal 1:

```bash
cd packages/graphx_connect_socket
dart run tool/acceptance_server.dart
```

Terminal 2:

```bash
cd packages/graphx_connect_socket
dart run tool/acceptance_client.dart --all-local
```

To test another device against the server, keep the server bound to `0.0.0.0`
and point the client at the Mac's reachable LAN/Tailscale address:

```bash
dart run tool/acceptance_client.dart \
  --tcp-host <host> \
  --ws ws://<host>:46002/connect
```

TCP is native-only. WebSocket can also be exercised from web clients.

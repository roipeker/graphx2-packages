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

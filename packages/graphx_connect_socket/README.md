# graphx_connect_socket

General WebSocket and native TCP connections for `graphx_connect`.

The raw connection layer does **not** speak the GraphX session protocol. It can
connect to ordinary WebSocket/TCP services that know nothing about GraphX.

## Raw connections

```dart
import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_socket/graphx_connect_socket.dart';

final connect = GConnect(name: 'Client');

final ws = await connect.webSocket(
  Uri.parse('wss://echo.websocket.org'),
);

ws.messages.listen(print);
ws.sendText('hello');
ws.sendBytes(Uint8List.fromList([1, 2, 3]));

final tcp = await connect.tcp(
  '192.168.1.20',
  port: 9000,
);

// TCP is a real byte stream: no GraphX framing is added.
tcp.messages.listen(print); // Uint8List chunks
tcp.sendBytes(Uint8List.fromList([0x01, 0x02]));
```

WebSocket works on web and native platforms. Raw TCP is native-only.

## Optional GraphX session

A raw connection can be upgraded once, before raw messages/sends are consumed:

```dart
final raw = await connect.webSocket(
  Uri.parse('wss://example.com/graphx'),
);

final session = await raw.session(
  id: 'main',
);

session.send({'x': 10});
session.sendBytes(bytes);
session.messages.listen(...);
session.peers;
```

The upgrade keeps the same live transport connection. For TCP, GraphX message
framing is layered onto the already-open byte stream at upgrade time.

Convenience shortcuts are also available when the remote endpoint already
speaks the GraphX session protocol:

```dart
final wsSession = await connect.webSocketSession(
  Uri.parse('wss://example.com/graphx'),
  session: 'main',
);

final tcpSession = await connect.tcpSession(
  '192.168.1.20',
  port: 9000,
  session: 'main',
);
```

## Acceptance tests

The package includes permanent local/public acceptance tools.

Start the server:

```bash
cd packages/graphx_connect_socket
dart run tool/acceptance_server.dart
```

It exposes:

```text
46001                 GraphX framed TCP session endpoint
46003                 raw byte-for-byte TCP echo
ws://HOST:46002/connect   GraphX WebSocket session endpoint
ws://HOST:46002/raw       raw WebSocket echo
```

GraphX session acceptance:

```bash
dart run tool/acceptance_client.dart --all-local
```

Raw + in-place upgrade acceptance:

```bash
dart run tool/raw_acceptance_client.dart --all-local
```

Public arbitrary-WSS acceptance, with no GraphX-aware server:

```bash
dart run tool/raw_acceptance_client.dart --public
```

The current public probe uses `wss://echo.websocket.org` and verifies both
text and binary frames.

To test from another device, keep the server bound to `0.0.0.0` and use the
Mac's LAN or Tailscale address.

UDP is intentionally not exposed yet; datagram semantics will get their own
contract rather than pretending UDP is a reliable stream.

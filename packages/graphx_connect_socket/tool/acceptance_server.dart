import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphx_connect/src/protocol.dart';

const _serverId = 'socket-acceptance-server';
const _serverName = 'Socket Acceptance Server';

Future<void> main(List<String> args) async {
  final config = _Config.parse(args);
  final tcp = await ServerSocket.bind(config.host, config.tcpPort);
  final rawTcp = await ServerSocket.bind(config.host, config.rawTcpPort);
  final http = await HttpServer.bind(config.host, config.wsPort);

  stdout.writeln(
    'GRAPHX_SOCKET_ACCEPTANCE_READY '
    'tcp=${tcp.address.address}:${tcp.port} '
    'raw_tcp=${rawTcp.address.address}:${rawTcp.port} '
    'ws=ws://${http.address.address}:${http.port}/connect '
    'raw_ws=ws://${http.address.address}:${http.port}/raw',
  );

  tcp.listen((socket) {
    final wire = _TcpWire(socket);
    unawaited(
      _serve(
        wire,
        'tcp ${socket.remoteAddress.address}:${socket.remotePort}',
      ),
    );
  });

  rawTcp.listen((socket) {
    final label = 'raw-tcp ${socket.remoteAddress.address}:${socket.remotePort}';
    stdout.writeln('CONNECTED $label');
    socket.listen(
      socket.add,
      onError: (Object error, StackTrace stack) {
        stderr.writeln('ERROR $label $error');
      },
      onDone: () {
        stdout.writeln('DISCONNECTED $label');
      },
      cancelOnError: false,
    );
  });

  http.listen((request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('GraphX Connect socket acceptance server')
        ..close();
      return;
    }

    if (request.uri.path == '/raw') {
      final socket = await WebSocketTransformer.upgrade(request);
      final label = 'raw-ws ${request.connectionInfo?.remoteAddress.address ?? '?'}';
      stdout.writeln('CONNECTED $label');
      socket.listen(
        socket.add,
        onError: (Object error, StackTrace stack) {
          stderr.writeln('ERROR $label $error');
        },
        onDone: () {
          stdout.writeln('DISCONNECTED $label');
        },
        cancelOnError: false,
      );
      return;
    }

    if (request.uri.path != '/connect') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('GraphX Connect socket acceptance server')
        ..close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    unawaited(
      _serve(
        _WebSocketWire(socket),
        'ws ${request.connectionInfo?.remoteAddress.address ?? '?'}',
      ),
    );
  });

  await Completer<void>().future;
}

Future<void> _serve(_Wire wire, String label) async {
  String? sessionId;
  String? binaryMode;
  var serverSequence = 0;

  stdout.writeln('CONNECTED $label');

  try {
    await for (final encoded in wire.messages) {
      if (encoded is Uint8List) {
        if (sessionId == null) {
          throw const FormatException('Binary frame before GraphX handshake.');
        }
        wire.send(encoded);
        continue;
      }

      if (encoded is! String) {
        throw FormatException('Unsupported frame: ${encoded.runtimeType}');
      }

      final frame = GConnectProtocol.decode(encoded);

      if (sessionId == null) {
        if (frame.type != 'hello') {
          throw const FormatException('Expected GraphX hello.');
        }
        sessionId = frame.sessionId;
        binaryMode = frame.binaryMode;
        if (frame.peerId == null || frame.peerName == null || binaryMode == null) {
          throw const FormatException('Incomplete GraphX hello.');
        }

        wire.send(
          GConnectProtocol.welcome(
            sessionId: sessionId,
            peerId: _serverId,
            peerName: _serverName,
            binaryMode: binaryMode,
          ),
        );
        stdout.writeln(
          'HANDSHAKE $label session=$sessionId '
          'peer=${frame.peerName} binary=$binaryMode',
        );
        continue;
      }

      if (frame.sessionId != sessionId) {
        throw const FormatException('Session id changed.');
      }

      switch (frame.type) {
        case 'data':
          wire.send(
            GConnectProtocol.data(
              sessionId: sessionId,
              peerId: _serverId,
              sequence: serverSequence++,
              payload: frame.payload,
            ),
          );
        case 'ping':
          final ping = frame.pingId;
          if (ping == null) throw const FormatException('Missing ping id.');
          wire.send(
            GConnectProtocol.pong(
              sessionId: sessionId,
              peerId: _serverId,
              pingId: ping,
            ),
          );
        case 'pong':
          break;
        default:
          throw FormatException('Unexpected GraphX frame ${frame.type}.');
      }
    }
  } catch (error) {
    stderr.writeln('ERROR $label $error');
  } finally {
    await wire.close();
    stdout.writeln('DISCONNECTED $label');
  }
}

abstract interface class _Wire {
  Stream<Object> get messages;
  void send(Object value);
  Future<void> close();
}

final class _WebSocketWire implements _Wire {
  _WebSocketWire(this.socket);

  final WebSocket socket;

  @override
  Stream<Object> get messages => socket.map<Object>((event) {
    if (event is String) return event;
    if (event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    throw FormatException('Unsupported WebSocket frame ${event.runtimeType}.');
  });

  @override
  void send(Object value) => socket.add(value);

  @override
  Future<void> close() => socket.close();
}

final class _TcpWire implements _Wire {
  _TcpWire(this.socket) {
    _subscription = socket.listen(
      _onData,
      onError: _messages.addError,
      onDone: _messages.close,
    );
  }

  final Socket socket;
  final _messages = StreamController<Object>();
  final _buffer = <int>[];
  late final StreamSubscription<Uint8List> _subscription;

  @override
  Stream<Object> get messages => _messages.stream;

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    while (_buffer.length >= 5) {
      final bytes = Uint8List.fromList(_buffer);
      final header = ByteData.sublistView(bytes, 0, 5);
      final type = header.getUint8(0);
      final length = header.getUint32(1, Endian.big);
      if (_buffer.length < 5 + length) return;

      final payload = Uint8List.fromList(_buffer.sublist(5, 5 + length));
      _buffer.removeRange(0, 5 + length);

      switch (type) {
        case 0:
          _messages.add(utf8.decode(payload));
        case 1:
          _messages.add(payload);
        default:
          _messages.addError(FormatException('Invalid TCP frame type $type.'));
      }
    }
  }

  @override
  void send(Object value) {
    final int type;
    final Uint8List payload;
    if (value is String) {
      type = 0;
      payload = Uint8List.fromList(utf8.encode(value));
    } else if (value is Uint8List) {
      type = 1;
      payload = value;
    } else {
      throw ArgumentError.value(value, 'value', 'Expected String or Uint8List.');
    }

    final framed = Uint8List(5 + payload.length);
    final header = ByteData.sublistView(framed, 0, 5);
    header.setUint8(0, type);
    header.setUint32(1, payload.length, Endian.big);
    framed.setRange(5, framed.length, payload);
    socket.add(framed);
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    if (!_messages.isClosed) await _messages.close();
    await socket.close();
  }
}

final class _Config {
  const _Config({
    required this.host,
    required this.tcpPort,
    required this.rawTcpPort,
    required this.wsPort,
  });

  final String host;
  final int tcpPort;
  final int rawTcpPort;
  final int wsPort;

  static _Config parse(List<String> args) {
    var host = InternetAddress.anyIPv4.address;
    var tcpPort = 46001;
    var rawTcpPort = 46003;
    var wsPort = 46002;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--host':
          host = args[++i];
        case '--tcp':
          tcpPort = int.parse(args[++i]);
        case '--raw-tcp':
          rawTcpPort = int.parse(args[++i]);
        case '--ws':
          wsPort = int.parse(args[++i]);
        case '--help':
          stdout.writeln(
            'dart run tool/acceptance_server.dart '
            '[--host 0.0.0.0] [--tcp 46001] '
            '[--raw-tcp 46003] [--ws 46002]',
          );
          exit(0);
        default:
          throw ArgumentError('Unknown argument ${args[i]}');
      }
    }

    return _Config(
      host: host,
      tcpPort: tcpPort,
      rawTcpPort: rawTcpPort,
      wsPort: wsPort,
    );
  }
}

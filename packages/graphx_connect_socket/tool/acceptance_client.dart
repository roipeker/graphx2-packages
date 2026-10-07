import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_socket/graphx_connect_socket.dart';

Future<void> main(List<String> args) async {
  final config = _Config.parse(args);
  var failures = 0;

  if (config.tcpHost != null) {
    failures += await _run(
      'tcp',
      () => GConnect(name: 'Socket TCP client').tcpSession(
        config.tcpHost!,
        port: config.tcpPort,
        session: config.session,
      ),
    );
  }

  if (config.ws != null) {
    failures += await _run(
      'websocket',
      () => GConnect(name: 'Socket WS client').webSocketSession(
        config.ws!,
        session: config.session,
      ),
    );
  }

  if (failures != 0) {
    stderr.writeln('GRAPHX_SOCKET_ACCEPTANCE_FAIL failures=$failures');
    exitCode = 1;
    return;
  }

  stdout.writeln('GRAPHX_SOCKET_ACCEPTANCE_PASS');
}

Future<int> _run(
  String label,
  Future<GSession> Function() connect,
) async {
  stdout.writeln('[$label] CONNECTING');

  GSession? session;
  try {
    session = await connect().timeout(const Duration(seconds: 5));
    stdout.writeln(
      '[$label] CONNECTED peer=${session.peers.firstOrNull?.name ?? '?'}',
    );

    await _verifyStructured(label, session, 1);
    await _verifyBinary(label, session, <int>[1, 2, 3, 4, 255]);
    await _waitForLatency(label, session);

    await session.disconnect();
    await _waitUntil(() => !session!.connected);
    stdout.writeln('[$label] DISCONNECTED');

    await session.reconnect().timeout(const Duration(seconds: 5));
    stdout.writeln('[$label] RECONNECTED');

    await _verifyStructured(label, session, 2);
    await _verifyBinary(label, session, <int>[9, 8, 7, 6]);

    stdout.writeln('[$label] PASS');
    return 0;
  } catch (error, stack) {
    stderr.writeln('[$label] FAIL $error');
    stderr.writeln(stack);
    return 1;
  } finally {
    await session?.dispose();
  }
}

Future<void> _verifyStructured(
  String label,
  GSession session,
  int round,
) async {
  final expected = <String, Object?>{
    'kind': 'structured',
    'round': round,
    'value': 42,
  };

  final response = session.messages
      .firstWhere((message) => !message.isBinary)
      .timeout(const Duration(seconds: 3));

  session.send(expected);

  final message = await response;
  final data = message.data;
  if (data is! Map ||
      data['kind'] != expected['kind'] ||
      data['round'] != expected['round'] ||
      data['value'] != expected['value']) {
    throw StateError('Structured echo mismatch: $data');
  }

  stdout.writeln('[$label] STRUCTURED_OK round=$round');
}

Future<void> _verifyBinary(
  String label,
  GSession session,
  List<int> payload,
) async {
  final response = session.messages
      .firstWhere((message) => message.isBinary)
      .timeout(const Duration(seconds: 3));

  session.sendBytes(Uint8List.fromList(payload));

  final bytes = (await response).bytes;
  if (bytes == null || bytes.length != payload.length || !_sameBytes(bytes, payload)) {
    throw StateError('Binary echo mismatch: $bytes');
  }

  stdout.writeln('[$label] BINARY_OK bytes=${payload.length}');
}

Future<void> _waitForLatency(String label, GSession session) async {
  await _waitUntil(
    () => session.peers.isNotEmpty && session.peers.first.latency != null,
    timeout: const Duration(seconds: 3),
  );
  stdout.writeln(
    '[$label] RTT ${session.peers.first.latency!.inMilliseconds}ms',
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= timeout) {
      throw TimeoutException('Condition timed out after $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

bool _sameBytes(Uint8List bytes, List<int> expected) {
  if (bytes.length != expected.length) return false;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != expected[i]) return false;
  }
  return true;
}

final class _Config {
  const _Config({
    required this.tcpHost,
    required this.tcpPort,
    required this.ws,
    required this.session,
  });

  final String? tcpHost;
  final int tcpPort;
  final Uri? ws;
  final String session;

  static _Config parse(List<String> args) {
    String? tcpHost;
    var tcpPort = 46001;
    Uri? ws;
    var session = 'acceptance';

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--tcp-host':
          tcpHost = args[++i];
        case '--tcp-port':
          tcpPort = int.parse(args[++i]);
        case '--ws':
          ws = Uri.parse(args[++i]);
        case '--session':
          session = args[++i];
        case '--all-local':
          tcpHost = InternetAddress.loopbackIPv4.address;
          ws = Uri.parse('ws://127.0.0.1:46002/connect');
        case '--help':
          stdout.writeln(
            'dart run tool/acceptance_client.dart '
            '[--all-local] [--tcp-host HOST] [--tcp-port 46001] '
            '[--ws ws://HOST:46002/connect] [--session acceptance]',
          );
          exit(0);
        default:
          throw ArgumentError('Unknown argument ${args[i]}');
      }
    }

    if (tcpHost == null && ws == null) {
      throw ArgumentError('Choose --all-local, --tcp-host, or --ws.');
    }

    return _Config(
      tcpHost: tcpHost,
      tcpPort: tcpPort,
      ws: ws,
      session: session,
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

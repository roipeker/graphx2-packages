import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_socket/graphx_connect_socket.dart';

Future<void> main(List<String> args) async {
  final config = _Config.parse(args);
  var failures = 0;

  if (config.host != null) {
    failures += await _rawTcp(config.host!);
    failures += await _rawWebSocket(
      Uri.parse('ws://${config.host}:${config.wsPort}/raw'),
      'local-ws',
    );
    failures += await _upgradeTcp(config.host!);
    failures += await _upgradeWebSocket(
      Uri.parse('ws://${config.host}:${config.wsPort}/connect'),
    );
  }

  if (config.publicWs != null) {
    failures += await _rawWebSocket(config.publicWs!, 'public-wss');
  }

  if (failures != 0) {
    stderr.writeln('GRAPHX_RAW_ACCEPTANCE_FAIL failures=$failures');
    exitCode = 1;
    return;
  }
  stdout.writeln('GRAPHX_RAW_ACCEPTANCE_PASS');
}

Future<int> _rawTcp(String host) async {
  GConnection? connection;
  try {
    stdout.writeln('[raw-tcp] CONNECTING');
    connection = await GConnect(name: 'Raw TCP').tcp(
      host,
      port: 46003,
    );

    final expected = Uint8List.fromList(<int>[0, 1, 2, 3, 254, 255]);
    final echo = connection.messages.first.timeout(const Duration(seconds: 3));
    connection.sendBytes(expected);
    final message = await echo;

    if (message is! Uint8List || !_same(message, expected)) {
      throw StateError('raw TCP echo mismatch: $message');
    }

    stdout.writeln('[raw-tcp] PASS bytes=${expected.length}');
    return 0;
  } catch (error, stack) {
    stderr.writeln('[raw-tcp] FAIL $error');
    stderr.writeln(stack);
    return 1;
  } finally {
    await connection?.close();
  }
}

Future<int> _rawWebSocket(Uri uri, String label) async {
  GConnection? connection;
  StreamIterator<Object>? iterator;
  try {
    stdout.writeln('[$label] CONNECTING $uri');
    connection = await GConnect(name: 'Raw WS').webSocket(uri);
    iterator = StreamIterator<Object>(connection.messages);

    final token = 'graphx-raw-${DateTime.now().microsecondsSinceEpoch}';
    connection.sendText(token);
    await _nextMatching(
      iterator,
      (message) => message == token,
      timeout: const Duration(seconds: 8),
    );
    stdout.writeln('[$label] TEXT_OK');

    final expected = Uint8List.fromList(<int>[9, 8, 7, 6, 255]);
    connection.sendBytes(expected);
    await _nextMatching(
      iterator,
      (message) => message is Uint8List && _same(message, expected),
      timeout: const Duration(seconds: 8),
    );
    stdout.writeln('[$label] BINARY_OK');
    stdout.writeln('[$label] PASS');
    return 0;
  } catch (error, stack) {
    stderr.writeln('[$label] FAIL $error');
    stderr.writeln(stack);
    return 1;
  } finally {
    await iterator?.cancel();
    await connection?.close();
  }
}

Future<Object> _nextMatching(
  StreamIterator<Object> iterator,
  bool Function(Object message) matches, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('No matching message within $timeout.');
    }
    final hasNext = await iterator.moveNext().timeout(remaining);
    if (!hasNext) throw StateError('Connection closed before expected echo.');
    final current = iterator.current;
    if (matches(current)) return current;
  }
}

Future<int> _upgradeTcp(String host) async {
  GSession? session;
  try {
    stdout.writeln('[tcp-upgrade] CONNECTING RAW');
    final raw = await GConnect(name: 'TCP upgrade').tcp(
      host,
      port: 46001,
    );
    session = await raw.session(id: 'acceptance');
    await _sessionRoundTrip('tcp-upgrade', session);
    stdout.writeln('[tcp-upgrade] PASS');
    return 0;
  } catch (error, stack) {
    stderr.writeln('[tcp-upgrade] FAIL $error');
    stderr.writeln(stack);
    return 1;
  } finally {
    await session?.dispose();
  }
}

Future<int> _upgradeWebSocket(Uri uri) async {
  GSession? session;
  try {
    stdout.writeln('[ws-upgrade] CONNECTING RAW');
    final raw = await GConnect(name: 'WS upgrade').webSocket(uri);
    session = await raw.session(id: 'acceptance');
    await _sessionRoundTrip('ws-upgrade', session);
    stdout.writeln('[ws-upgrade] PASS');
    return 0;
  } catch (error, stack) {
    stderr.writeln('[ws-upgrade] FAIL $error');
    stderr.writeln(stack);
    return 1;
  } finally {
    await session?.dispose();
  }
}

Future<void> _sessionRoundTrip(String label, GSession session) async {
  final response = session.messages
      .firstWhere((message) => !message.isBinary)
      .timeout(const Duration(seconds: 3));
  session.send(<String, Object?>{'kind': label, 'ok': true});
  final data = (await response).data;
  if (data is! Map || data['kind'] != label || data['ok'] != true) {
    throw StateError('session echo mismatch: $data');
  }

  await session.disconnect();
  await _waitUntil(() => !session.connected);
  await session.reconnect().timeout(const Duration(seconds: 5));

  final second = session.messages
      .firstWhere((message) => !message.isBinary)
      .timeout(const Duration(seconds: 3));
  session.send(<String, Object?>{'kind': label, 'reconnect': true});
  final afterReconnect = (await second).data;
  if (afterReconnect is! Map || afterReconnect['reconnect'] != true) {
    throw StateError('reconnect echo mismatch: $afterReconnect');
  }
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

bool _same(Uint8List bytes, List<int> expected) {
  if (bytes.length != expected.length) return false;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != expected[i]) return false;
  }
  return true;
}

final class _Config {
  const _Config({
    required this.host,
    required this.wsPort,
    required this.publicWs,
  });

  final String? host;
  final int wsPort;
  final Uri? publicWs;

  static _Config parse(List<String> args) {
    String? host;
    var wsPort = 46002;
    Uri? publicWs;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--all-local':
          host = '127.0.0.1';
        case '--host':
          host = args[++i];
        case '--ws-port':
          wsPort = int.parse(args[++i]);
        case '--public':
          publicWs = Uri.parse('wss://echo.websocket.org');
        case '--public-ws':
          publicWs = Uri.parse(args[++i]);
        case '--help':
          stdout.writeln(
            'dart run tool/raw_acceptance_client.dart '
            '[--all-local|--host HOST] [--public] [--public-ws URI]',
          );
          exit(0);
        default:
          throw ArgumentError('Unknown argument ${args[i]}');
      }
    }

    if (host == null && publicWs == null) {
      throw ArgumentError('Choose --all-local, --host, or --public.');
    }

    return _Config(host: host, wsPort: wsPort, publicWs: publicWs);
  }
}

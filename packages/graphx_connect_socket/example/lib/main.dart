import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_socket/graphx_connect_socket.dart';

const defaultHost = String.fromEnvironment(
  'SOCKET_HOST',
  defaultValue: '192.168.0.170',
);

void main() => runApp(const SocketAcceptanceApp());

class SocketAcceptanceApp extends StatelessWidget {
  const SocketAcceptanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SocketAcceptanceScreen(),
    );
  }
}

class SocketAcceptanceScreen extends StatefulWidget {
  const SocketAcceptanceScreen({super.key});

  @override
  State<SocketAcceptanceScreen> createState() => _SocketAcceptanceScreenState();
}

class _SocketAcceptanceScreenState extends State<SocketAcceptanceScreen> {
  final _host = TextEditingController(text: defaultHost);
  final _lines = <String>[];
  bool _running = false;

  void _log(String value) {
    if (!mounted) return;
    setState(() {
      _lines.add(value);
      if (_lines.length > 40) _lines.removeAt(0);
    });
  }

  Future<void> _runRawTcp() async {
    if (kIsWeb) {
      _log('TCP unsupported on web');
      return;
    }
    await _runRaw(
      'RAW TCP',
      () => GConnect(
        name: 'Socket device raw TCP',
      ).tcp(_host.text.trim(), port: 46003),
    );
  }

  Future<void> _runRawWs() {
    return _runRaw(
      'RAW WS',
      () => GConnect(
        name: 'Socket device raw WS',
      ).webSocket(Uri.parse('ws://${_host.text.trim()}:46002/raw')),
    );
  }

  Future<void> _runRaw(
    String label,
    Future<GConnection> Function() open,
  ) async {
    if (_running) return;
    setState(() => _running = true);
    GConnection? connection;

    try {
      _log('$label connecting…');
      connection = await open().timeout(const Duration(seconds: 6));
      final expected = Uint8List.fromList(<int>[1, 2, 3, 4, 255]);
      final response = connection.messages.first.timeout(
        const Duration(seconds: 3),
      );
      connection.sendBytes(expected);
      final message = await response;
      if (message is! Uint8List || !_same(message, expected)) {
        throw StateError('raw echo mismatch');
      }
      _log('$label binary echo ✓');
      _log('$label PASS');
    } on Object catch (error) {
      _log('$label FAIL: $error');
    } finally {
      await connection?.close();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runSessionTcp() async {
    if (kIsWeb) {
      _log('TCP unsupported on web');
      return;
    }
    await _run(
      'SESSION TCP',
      () => GConnect(
        name: 'Socket device TCP',
      ).tcpSession(_host.text.trim(), port: 46001, session: 'acceptance'),
    );
  }

  Future<void> _runSessionWs() {
    return _run(
      'SESSION WS',
      () => GConnect(name: 'Socket device WS').webSocketSession(
        Uri.parse('ws://${_host.text.trim()}:46002/connect'),
        session: 'acceptance',
      ),
    );
  }

  Future<void> _runAll() async {
    if (!kIsWeb) await _runRawTcp();
    await _runRawWs();
    if (!kIsWeb) await _runSessionTcp();
    await _runSessionWs();
  }

  Future<void> _run(String label, Future<GSession> Function() open) async {
    if (_running) return;
    setState(() => _running = true);
    GSession? session;

    try {
      _log('$label connecting…');
      session = await open().timeout(const Duration(seconds: 6));
      _log('$label connected: ${session.peers.first.name}');

      await _structured(label, session, 1);
      await _binary(label, session, <int>[1, 2, 3, 4, 255]);
      await _latency(label, session);

      await session.disconnect();
      await _waitUntil(() => !session!.connected);
      _log('$label disconnected');

      await session.reconnect().timeout(const Duration(seconds: 6));
      _log('$label reconnected');

      await _structured(label, session, 2);
      await _binary(label, session, <int>[9, 8, 7, 6]);
      _log('$label PASS');
    } on Object catch (error) {
      _log('$label FAIL: $error');
    } finally {
      await session?.dispose();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _structured(String label, GSession session, int round) async {
    final future = session.messages
        .firstWhere((message) => !message.isBinary)
        .timeout(const Duration(seconds: 3));
    final payload = <String, Object?>{
      'kind': 'structured',
      'round': round,
      'value': 42,
    };
    session.send(payload);

    final data = (await future).data;
    if (data is! Map ||
        data['kind'] != 'structured' ||
        data['round'] != round ||
        data['value'] != 42) {
      throw StateError('structured echo mismatch');
    }
    _log('$label structured round $round ✓');
  }

  Future<void> _binary(
    String label,
    GSession session,
    List<int> payload,
  ) async {
    final future = session.messages
        .firstWhere((message) => message.isBinary)
        .timeout(const Duration(seconds: 3));
    session.sendBytes(Uint8List.fromList(payload));

    final bytes = (await future).bytes;
    if (bytes == null || !_same(bytes, payload)) {
      throw StateError('binary echo mismatch');
    }
    _log('$label binary ${payload.length} bytes ✓');
  }

  Future<void> _latency(String label, GSession session) async {
    await _waitUntil(
      () => session.peers.first.latency != null,
      timeout: const Duration(seconds: 3),
    );
    _log('$label RTT ${session.peers.first.latency!.inMilliseconds} ms');
  }

  Future<void> _waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final watch = Stopwatch()..start();
    while (!condition()) {
      if (watch.elapsed > timeout) {
        throw TimeoutException('condition timed out');
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

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GraphX Socket Acceptance')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Server host',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                if (!kIsWeb)
                  FilledButton(
                    onPressed: _running ? null : _runRawTcp,
                    child: const Text('RAW TCP'),
                  ),
                FilledButton(
                  onPressed: _running ? null : _runRawWs,
                  child: const Text('RAW WS'),
                ),
                if (!kIsWeb)
                  FilledButton.tonal(
                    onPressed: _running ? null : _runSessionTcp,
                    child: const Text('SESSION TCP'),
                  ),
                FilledButton.tonal(
                  onPressed: _running ? null : _runSessionWs,
                  child: const Text('SESSION WS'),
                ),
                OutlinedButton(
                  onPressed: _running ? null : _runAll,
                  child: const Text('RUN ALL'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) => Text(_lines[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

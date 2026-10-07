import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect_nearby/graphx_connect_nearby.dart';

const serviceId = 'com.roipeker.graphx.connect.nearby.example';
const sessionName = 'GraphX Nearby Example';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ExampleScreen(),
    );
  }
}

class ExampleScreen extends StatefulWidget {
  const ExampleScreen({super.key});

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  GSession? _session;
  GDiscovery? _discovery;
  StreamSubscription<GMessage>? _messages;
  String _status = 'IDLE';
  int _rx = 0;

  Future<void> _close() async {
    await _messages?.cancel();
    _messages = null;
    await _discovery?.dispose();
    _discovery = null;
    await _session?.dispose();
    _session = null;
  }

  void _bind(GSession session) {
    _session = session;
    _messages = session.messages.listen((message) {
      final bytes = message.bytes;
      if (bytes == null) return;
      setState(() {
        _rx++;
        _status = 'RX ${bytes.join(',')}';
      });
    });
  }

  Future<void> _host() async {
    await _close();
    setState(() => _status = 'HOSTING');
    try {
      final connect = GConnect(
        name: 'Nearby host',
        binaryMode: GBinaryMode.raw,
      );
      final session = await connect
          .nearby(service: serviceId)
          .host(sessionName);
      _bind(session);
      setState(() => _status = 'WAITING FOR PEER');
    } on Object catch (error) {
      setState(() => _status = 'ERROR $error');
    }
  }

  Future<void> _join() async {
    await _close();
    setState(() => _status = 'SEARCHING');
    try {
      final connect = GConnect(
        name: 'Nearby client',
        binaryMode: GBinaryMode.raw,
      );
      final nearby = connect.nearby(service: serviceId);
      final discovery = await nearby.discover();
      _discovery = discovery;
      final found = await discovery.events
          .firstWhere(
            (event) =>
                event.type == GDiscoveryEventType.found &&
                event.session.name == sessionName,
          )
          .timeout(const Duration(seconds: 30));
      await discovery.dispose();
      _discovery = null;
      final session = await nearby.join(found.session);
      _bind(session);
      setState(() => _status = 'CONNECTED');
    } on Object catch (error) {
      setState(() => _status = 'ERROR $error');
    }
  }

  void _send() {
    final session = _session;
    if (session == null || !session.connected) {
      setState(() => _status = 'NOT CONNECTED');
      return;
    }
    session.sendBytes(Uint8List.fromList(<int>[1, 2, 3, 4]));
    setState(() => _status = 'TX 1,2,3,4');
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GraphX Nearby')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('received: $_rx'),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  FilledButton(onPressed: _host, child: const Text('HOST')),
                  FilledButton(onPressed: _join, child: const Text('JOIN')),
                  OutlinedButton(onPressed: _send, child: const Text('SEND')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

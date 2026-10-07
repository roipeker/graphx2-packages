import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect/graphx_connect_spi.dart';

void main() {
  test('host/join/message/disconnect/reconnect keeps peer identity', () async {
    final transport = _MemoryTransport();
    final hostConnect = _MemoryConnect(
      transport: transport,
      name: 'TV',
      peerId: 'host-peer',
    );
    final clientConnect = _MemoryConnect(
      transport: transport,
      name: 'Phone',
      peerId: 'phone-peer',
    );

    final host = await hostConnect.host('Living Room');
    final discovery = await clientConnect.discover();
    final found = await discovery.events.firstWhere(
      (event) => event.type == GDiscoveryEventType.found,
    );

    final hostEvents = <GPeerEvent>[];
    final hostEventSubscription = host.peerEvents.listen(hostEvents.add);
    final client = await clientConnect.join(found.session);
    await Future<void>.delayed(Duration.zero);

    expect(client.state, GSessionState.connected);
    expect(host.peers, hasLength(1));
    final hostPeer = host.peers.single;
    expect(hostPeer.id, 'phone-peer');
    expect(hostPeer.name, 'Phone');
    expect(hostPeer.connected, isTrue);
    expect(hostEvents.single.type, GPeerEventType.connected);

    final hostMessage = host.messages.first;
    client.send(<String, Object?>{'action': 'jump'});
    final receivedByHost = await hostMessage;
    expect(receivedByHost.peer, same(hostPeer));
    expect(receivedByHost.sequence, 0);
    expect(receivedByHost.data, <String, Object?>{'action': 'jump'});
    expect(receivedByHost.isBinary, isFalse);

    final clientMessage = client.messages.first;
    host.send(<String, Object?>{'accepted': true}, to: hostPeer);
    final receivedByClient = await clientMessage;
    expect(receivedByClient.peer.name, 'TV');
    expect(receivedByClient.data, <String, Object?>{'accepted': true});

    await client.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(client.state, GSessionState.disconnected);
    expect(hostPeer.connected, isFalse);
    expect(hostEvents.last.type, GPeerEventType.disconnected);

    final reconnectEvent = host.peerEvents.firstWhere(
      (event) => event.type == GPeerEventType.reconnected,
    );
    await client.reconnect();
    final reconnected = await reconnectEvent;
    expect(reconnected.peer, same(hostPeer));
    expect(host.peers.single, same(hostPeer));
    expect(hostPeer.connected, isTrue);
    expect(client.state, GSessionState.connected);

    await client.dispose();
    await discovery.dispose();
    await host.dispose();
    await hostEventSubscription.cancel();
  });

  test('host supports multiple peers, broadcast, and targeted send', () async {
    final transport = _MemoryTransport();
    final hostConnect = _MemoryConnect(
      transport: transport,
      name: 'TV',
      peerId: 'host-peer',
    );
    final clientAConnect = _MemoryConnect(
      transport: transport,
      name: 'Phone A',
      peerId: 'phone-a',
    );
    final clientBConnect = _MemoryConnect(
      transport: transport,
      name: 'Phone B',
      peerId: 'phone-b',
    );

    final host = await hostConnect.host('Living Room');
    final discovery = await clientAConnect.discover();
    final found = await discovery.events.firstWhere(
      (event) => event.type == GDiscoveryEventType.found,
    );

    final clientA = await clientAConnect.join(found.session);
    final clientB = await clientBConnect.join(found.session);
    await Future<void>.delayed(Duration.zero);

    expect(host.peers, hasLength(2));
    expect(host.peers.map((peer) => peer.id).toSet(), <String>{
      'phone-a',
      'phone-b',
    });
    expect(host.peers.every((peer) => peer.connected), isTrue);

    final broadcastA = clientA.messages.first;
    final broadcastB = clientB.messages.first;
    host.send(<String, Object?>{'kind': 'broadcast'});

    expect((await broadcastA).data, <String, Object?>{'kind': 'broadcast'});
    expect((await broadcastB).data, <String, Object?>{'kind': 'broadcast'});

    final peerA = host.peers.singleWhere((peer) => peer.id == 'phone-a');
    final targetedA = clientA.messages.first;
    final clientBTargetedMessages = <GMessage>[];
    final clientBSubscription = clientB.messages.listen(
      clientBTargetedMessages.add,
    );

    host.send(<String, Object?>{'kind': 'targeted'}, to: peerA);

    expect((await targetedA).data, <String, Object?>{'kind': 'targeted'});
    await Future<void>.delayed(Duration.zero);
    expect(clientBTargetedMessages, isEmpty);

    await clientBSubscription.cancel();
    await clientB.dispose();
    await clientA.dispose();
    await discovery.dispose();
    await host.dispose();
  });

  test('binary messages share ordering and peer routing with data', () async {
    final transport = _MemoryTransport();
    final hostConnect = _MemoryConnect(
      transport: transport,
      name: 'TV',
      peerId: 'host-peer',
    );
    final clientConnect = _MemoryConnect(
      transport: transport,
      name: 'Phone',
      peerId: 'phone-peer',
    );

    final host = await hostConnect.host('Binary Room');
    final discovery = await clientConnect.discover();
    final found = await discovery.events.firstWhere(
      (event) => event.type == GDiscoveryEventType.found,
    );
    final client = await clientConnect.join(found.session);
    await Future<void>.delayed(Duration.zero);

    final received = host.messages.take(2).toList();
    client.send(<String, Object?>{'kind': 'data'});
    final bytes = Uint8List.fromList(<int>[0, 1, 127, 128, 254, 255]);
    client.sendBytes(bytes);

    final messages = await received;
    expect(messages[0].sequence, 0);
    expect(messages[0].data, <String, Object?>{'kind': 'data'});
    expect(messages[0].isBinary, isFalse);
    expect(messages[1].sequence, isNull);
    expect(messages[1].data, isNull);
    expect(messages[1].isBinary, isTrue);
    expect(messages[1].bytes, orderedEquals(bytes));

    final hostPeer = host.peers.single;
    final clientBinary = client.messages.first;
    final response = Uint8List.fromList(<int>[9, 8, 7, 6]);
    host.sendBytes(response, to: hostPeer);
    final receivedByClient = await clientBinary;
    expect(receivedByClient.peer.id, 'host-peer');
    expect(receivedByClient.sequence, isNull);
    expect(receivedByClient.isBinary, isTrue);
    expect(receivedByClient.bytes, orderedEquals(response));

    await client.dispose();
    await discovery.dispose();
    await host.dispose();
  });

  test('binary mode mismatch is rejected during handshake', () async {
    final transport = _MemoryTransport();
    final hostConnect = _MemoryConnect(
      transport: transport,
      name: 'Host',
      peerId: 'host-peer',
      binaryMode: GBinaryMode.raw,
    );
    final clientConnect = _MemoryConnect(
      transport: transport,
      name: 'Client',
      peerId: 'client-peer',
      binaryMode: GBinaryMode.sequenced,
    );

    final host = await hostConnect.host('Mode Room');
    final discovery = await clientConnect.discover();
    final found = await discovery.events.firstWhere(
      (event) => event.type == GDiscoveryEventType.found,
    );

    await expectLater(
      clientConnect.join(found.session),
      throwsA(isA<StateError>()),
    );

    await discovery.dispose();
    await host.dispose();
  });

  test(
    'join rejects incompatible discovered protocol before connecting',
    () async {
      final transport = _MemoryTransport(protocolVersion: 99);
      final hostConnect = _MemoryConnect(
        transport: transport,
        name: 'TV',
        peerId: 'host-peer',
      );
      final clientConnect = _MemoryConnect(
        transport: transport,
        name: 'Phone',
        peerId: 'phone-peer',
      );

      final host = await hostConnect.host('Old Room');
      final discovery = await clientConnect.discover();
      final found = await discovery.events.firstWhere(
        (event) => event.type == GDiscoveryEventType.found,
      );

      expect(found.session.compatible, isFalse);
      await expectLater(
        clientConnect.join(found.session),
        throwsA(isA<StateError>()),
      );
      expect(transport.connectCount, 0);

      await discovery.dispose();
      await host.dispose();
    },
  );
}

final class _MemoryConnect {
  _MemoryConnect({
    required this.transport,
    required String name,
    required String peerId,
    GBinaryMode binaryMode = GBinaryMode.raw,
  }) : connect = GConnect(name: name, id: peerId, binaryMode: binaryMode);

  final _MemoryTransport transport;
  final GConnect connect;

  Future<GSession> host(String sessionName) async {
    const sessionId = 'memory-session';
    final host = await transport.host(
      sessionId: sessionId,
      sessionName: sessionName,
      protocolVersion: GConnect.protocolVersion,
    );
    return GConnectSpi.host(
      connect: connect,
      host: host,
      sessionId: sessionId,
      sessionName: sessionName,
    );
  }

  Future<GDiscovery> discover() async {
    return GConnectSpi.discovery(await transport.discover());
  }

  Future<GSession> join(GSessionInfo info) {
    return GConnectSpi.joinDiscovered(
      connect: connect,
      transport: transport,
      session: info,
    );
  }
}

final class _MemoryTransport implements GConnectTransport {
  _MemoryTransport({this.protocolVersion});

  final int? protocolVersion;
  final List<_MemoryDiscovery> _discoveries = <_MemoryDiscovery>[];
  _MemoryHost? _host;
  GTransportService? _service;
  int connectCount = 0;

  @override
  bool get supported => true;

  @override
  String get name => 'memory';

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) async {
    final host = _MemoryHost(_hostDisposed);
    _host = host;
    final service = GTransportService(
      id: sessionId,
      name: sessionName,
      protocolVersion: this.protocolVersion ?? protocolVersion,
      endpoint: host,
    );
    _service = service;
    for (final discovery in _discoveries) {
      discovery.found(service);
    }
    return host;
  }

  @override
  Future<GTransportDiscovery> discover() async {
    late final _MemoryDiscovery discovery;
    discovery = _MemoryDiscovery(() => _discoveries.remove(discovery));
    _discoveries.add(discovery);
    final service = _service;
    if (service != null) {
      Timer.run(() => discovery.found(service));
    }
    return discovery;
  }

  @override
  Future<GTransportConnection> connect(Object endpoint) async {
    connectCount++;
    if (endpoint is! _MemoryHost || endpoint.disposed) {
      throw StateError('Host is unavailable.');
    }
    final pair = _MemoryConnection.pair();
    endpoint.accept(pair.server);
    return pair.client;
  }

  void _hostDisposed(_MemoryHost host) {
    if (!identical(_host, host)) return;
    final service = _service;
    _host = null;
    _service = null;
    if (service != null) {
      for (final discovery in _discoveries) {
        discovery.lost(service);
      }
    }
  }
}

final class _MemoryHost implements GTransportHost {
  _MemoryHost(this._onDispose);

  final void Function(_MemoryHost host) _onDispose;
  final _connections = StreamController<GTransportConnection>.broadcast(
    sync: true,
  );
  bool disposed = false;

  @override
  Stream<GTransportConnection> get connections => _connections.stream;

  void accept(GTransportConnection connection) {
    if (disposed) throw StateError('Host is disposed.');
    _connections.add(connection);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    _onDispose(this);
    await _connections.close();
  }
}

final class _MemoryDiscovery implements GTransportDiscovery {
  _MemoryDiscovery(this._onDispose);

  final void Function() _onDispose;
  final _events = StreamController<GTransportDiscoveryEvent>.broadcast(
    sync: true,
  );
  bool disposed = false;

  @override
  Stream<GTransportDiscoveryEvent> get events => _events.stream;

  void found(GTransportService service) {
    if (disposed) return;
    _events.add(
      GTransportDiscoveryEvent(GTransportDiscoveryKind.found, service),
    );
  }

  void lost(GTransportService service) {
    if (disposed) return;
    _events.add(
      GTransportDiscoveryEvent(GTransportDiscoveryKind.lost, service),
    );
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    _onDispose();
    await _events.close();
  }
}

final class _MemoryConnectionPair {
  const _MemoryConnectionPair(this.client, this.server);

  final _MemoryConnection client;
  final _MemoryConnection server;
}

final class _MemoryConnection implements GTransportConnection {
  _MemoryConnection._();

  final _messages = StreamController<Object>();
  _MemoryConnection? _other;
  bool _closed = false;

  static _MemoryConnectionPair pair() {
    final client = _MemoryConnection._();
    final server = _MemoryConnection._();
    client._other = server;
    server._other = client;
    return _MemoryConnectionPair(client, server);
  }

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  void send(Object message) {
    if (_closed) throw StateError('Connection is closed.');
    final other = _other;
    if (other == null || other._closed) {
      throw StateError('Remote connection is closed.');
    }
    other._messages.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    await _messages.close();
    final other = _other;
    if (other != null && !other._closed) {
      other._closed = true;
      await other._messages.close();
    }
  }
}

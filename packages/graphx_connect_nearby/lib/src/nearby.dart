import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect/graphx_connect_spi.dart';

import 'nearby_support_stub.dart' if (dart.library.io) 'nearby_support_io.dart' as platform;

const _nearbyMethodChannel = 'graphx_connect/nearby/methods';
const _nearbyEventChannel = 'graphx_connect/nearby/events';
const _wireControl = 0;
const _wireBinary = 1;
const _nearbyMaxWireBytes = 1047552;

extension GNearbyConnectExtension on GConnect {
  /// Creates an offline/proximity connector using this identity and defaults.
  GNearby nearby({required String service}) {
    return GNearby._(this, service: _validService(service));
  }
}

/// Google Nearby Connections facade for Android and iOS.
final class GNearby {
  GNearby._(
    this.connect, {
    required this.service,
  }) : _transport = _NearbyTransport(
         serviceId: service,
         endpointName: connect.name,
       );

  final GConnect connect;
  final String service;
  final _NearbyTransport _transport;

  bool get supported => _transport.supported;
  String get transport => _transport.name;

  Future<GSession> host(String sessionName) async {
    _ensureSupported();
    final normalized = _validName(sessionName, 'sessionName');
    final sessionId = _randomId();
    final host = await _transport.host(
      sessionId: sessionId,
      sessionName: normalized,
      protocolVersion: GConnect.protocolVersion,
    );
    return GConnectSpi.host(
      connect: connect,
      host: host,
      transport: _transport,
      sessionId: sessionId,
      sessionName: normalized,
    );
  }

  Future<GDiscovery> discover() async {
    _ensureSupported();
    return GConnectSpi.discovery(await _transport.discover());
  }

  Future<GSession> join(GSessionInfo info) {
    _ensureSupported();
    return GConnectSpi.joinDiscovered(
      connect: connect,
      transport: _transport,
      session: info,
    );
  }

  /// Releases native/runtime resources when this connector was used only for
  /// discovery and no [GSession] was created. Connected sessions own and
  /// dispose the transport themselves.
  Future<void> dispose() => _transport.dispose();

  void _ensureSupported() {
    if (!supported) {
      throw UnsupportedError(
        'GraphX Connect Nearby is available only on Android and iOS.',
      );
    }
  }
}

final class _NearbyTransport implements GConnectTransport, GDisposableTransport {
  _NearbyTransport({required this.serviceId, required this.endpointName})
    : instanceId = _randomId();

  final String serviceId;
  final String endpointName;
  final String instanceId;

  bool _created = false;
  bool _disposed = false;

  @override
  bool get supported => platform.nearbyPlatformSupported;

  @override
  String get name => 'nearby';

  Future<void> _prepare() async {
    if (_disposed) {
      throw StateError('GConnect.nearby connector is disposed.');
    }
    if (!supported) {
      throw UnsupportedError(
        'GraphX Connect nearby is available only on Android and iOS.',
      );
    }
    if (!_created) {
      await _NearbyBridge.instance.create(
        instanceId: instanceId,
        serviceId: serviceId,
        endpointName: endpointName,
      );
      _created = true;
    }
    await _NearbyBridge.instance.prepare(instanceId);
  }

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) async {
    await _prepare();
    final context = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'id': sessionId,
          'name': sessionName,
          'version': protocolVersion,
        }),
      ),
    );
    final host = _NearbyHost(instanceId);
    try {
      await _NearbyBridge.instance.startAdvertising(instanceId, context);
      return host;
    } catch (_) {
      await host.dispose();
      rethrow;
    }
  }

  @override
  Future<GTransportDiscovery> discover() async {
    await _prepare();
    final discovery = _NearbyDiscovery(instanceId);
    try {
      await _NearbyBridge.instance.startDiscovery(instanceId);
      return discovery;
    } catch (_) {
      await discovery.dispose();
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_created) {
      _created = false;
      await _NearbyBridge.instance.dispose(instanceId);
    }
  }

  @override
  Future<GTransportConnection> connect(Object endpoint) async {
    await _prepare();
    if (endpoint is! _NearbyEndpoint || endpoint.instanceId != instanceId) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Invalid nearby endpoint.',
      );
    }

    final connected = Completer<void>();
    late final StreamSubscription<Map<String, Object?>> subscription;
    subscription = _NearbyBridge.instance.eventsFor(instanceId).listen((event) {
      if (event['endpointId'] != endpoint.endpointId) return;
      switch (event['type']) {
        case 'connected':
          if (!connected.isCompleted) connected.complete();
        case 'connectionFailed':
          if (!connected.isCompleted) {
            connected.completeError(
              StateError(
                event['message'] as String? ?? 'Nearby connection failed.',
              ),
            );
          }
      }
    });

    try {
      await _NearbyBridge.instance.requestConnection(
        instanceId,
        endpoint.endpointId,
      );
      await connected.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'GraphX Connect nearby connection timed out.',
        ),
      );
      return _NearbyConnection(instanceId, endpoint.endpointId);
    } finally {
      await subscription.cancel();
    }
  }
}

final class _NearbyHost implements GTransportHost {
  _NearbyHost(this.instanceId) {
    _subscription = _NearbyBridge.instance
        .eventsFor(instanceId)
        .listen(
          _onEvent,
          onError: _connections.addError,
        );
  }

  final String instanceId;
  final _connections = StreamController<GTransportConnection>.broadcast(sync: true);
  final Map<String, _NearbyConnection> _active = <String, _NearbyConnection>{};
  late final StreamSubscription<Map<String, Object?>> _subscription;
  bool _disposed = false;

  @override
  Stream<GTransportConnection> get connections => _connections.stream;

  void _onEvent(Map<String, Object?> event) {
    if (_disposed || event['type'] != 'connected') return;
    final endpointId = event['endpointId'];
    if (endpointId is! String || endpointId.isEmpty) return;
    if (_active.containsKey(endpointId)) return;
    final connection = _NearbyConnection(instanceId, endpointId);
    _active[endpointId] = connection;
    connection.done.whenComplete(() => _active.remove(endpointId));
    _connections.add(connection);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    for (final connection in _active.values.toList(growable: false)) {
      await connection.close();
    }
    _active.clear();
    await _NearbyBridge.instance.stopAdvertising(instanceId);
    await _NearbyBridge.instance.dispose(instanceId);
    await _connections.close();
  }
}

final class _NearbyDiscovery implements GTransportDiscovery {
  _NearbyDiscovery(this.instanceId) {
    _subscription = _NearbyBridge.instance
        .eventsFor(instanceId)
        .listen(
          _onEvent,
          onError: _events.addError,
        );
  }

  final String instanceId;
  final _events = StreamController<GTransportDiscoveryEvent>.broadcast(sync: true);
  final Map<String, GTransportService> _known = <String, GTransportService>{};
  late final StreamSubscription<Map<String, Object?>> _subscription;
  bool _disposed = false;

  @override
  Stream<GTransportDiscoveryEvent> get events => _events.stream;

  void _onEvent(Map<String, Object?> event) {
    if (_disposed) return;
    final type = event['type'];
    final endpointId = event['endpointId'];
    if (endpointId is! String || endpointId.isEmpty) return;

    if (type == 'lost') {
      final service = _known.remove(endpointId);
      if (service != null) {
        _events.add(
          GTransportDiscoveryEvent(GTransportDiscoveryKind.lost, service),
        );
      }
      return;
    }
    if (type != 'found') return;

    final rawContext = event['context'];
    if (rawContext is! Uint8List) return;

    try {
      final decoded = jsonDecode(utf8.decode(rawContext));
      if (decoded is! Map) return;
      final id = decoded['id'];
      final name = decoded['name'];
      final version = decoded['version'];
      if (id is! String || id.isEmpty || name is! String || name.isEmpty || version is! num) {
        return;
      }
      final service = GTransportService(
        id: id,
        name: name,
        protocolVersion: version.toInt(),
        endpoint: _NearbyEndpoint(instanceId, endpointId),
      );
      _known[endpointId] = service;
      _events.add(
        GTransportDiscoveryEvent(GTransportDiscoveryKind.found, service),
      );
    } on FormatException {
      return;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _NearbyBridge.instance.stopDiscovery(instanceId);
    _known.clear();
    await _events.close();
  }
}

final class _NearbyConnection implements GTransportConnection {
  _NearbyConnection(this.instanceId, this.endpointId) {
    _subscription = _NearbyBridge.instance
        .eventsFor(instanceId)
        .listen(
          _onEvent,
          onError: (Object error, StackTrace stack) {
            if (!_messages.isClosed) _messages.addError(error, stack);
          },
        );
  }

  final String instanceId;
  final String endpointId;
  final _messages = StreamController<Object>();
  late final StreamSubscription<Map<String, Object?>> _subscription;
  final _done = Completer<void>();
  bool _closed = false;

  Future<void> get done => _done.future;

  @override
  Stream<Object> get messages => _messages.stream;

  void _onEvent(Map<String, Object?> event) {
    if (_closed || event['endpointId'] != endpointId) return;
    switch (event['type']) {
      case 'payload':
        final data = event['data'];
        if (data is! Uint8List || data.isEmpty) return;
        switch (data[0]) {
          case _wireControl:
            try {
              _messages.add(utf8.decode(Uint8List.sublistView(data, 1)));
            } on FormatException catch (error, stack) {
              _messages.addError(error, stack);
            }
          case _wireBinary:
            _messages.add(Uint8List.sublistView(data, 1));
        }
      case 'disconnected':
      case 'connectionFailed':
        unawaited(_closeLocal());
      case 'error':
        final message = event['message'];
        _messages.addError(
          StateError(
            message is String ? message : 'Nearby transport error.',
          ),
        );
    }
  }

  @override
  void send(Object message) {
    if (_closed) throw StateError('Nearby connection is closed.');

    late final Uint8List wire;
    if (message is String) {
      final encoded = utf8.encode(message);
      if (encoded.length + 1 > _nearbyMaxWireBytes) {
        throw ArgumentError.value(
          encoded.length,
          'message',
          'Nearby control payload exceeds the byte-payload limit.',
        );
      }
      wire = Uint8List(encoded.length + 1);
      wire[0] = _wireControl;
      wire.setRange(1, wire.length, encoded);
    } else if (message is Uint8List) {
      if (message.length + 1 > _nearbyMaxWireBytes) {
        throw ArgumentError.value(
          message.length,
          'message',
          'Nearby binary payload exceeds the byte-payload limit.',
        );
      }
      wire = Uint8List(message.length + 1);
      wire[0] = _wireBinary;
      wire.setRange(1, wire.length, message);
    } else {
      throw ArgumentError.value(
        message,
        'message',
        'Expected String or Uint8List.',
      );
    }

    unawaited(
      _NearbyBridge.instance.send(instanceId, endpointId, wire).catchError((
        Object error,
        StackTrace stack,
      ) {
        if (!_messages.isClosed) _messages.addError(error, stack);
      }),
    );
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    try {
      await _NearbyBridge.instance.disconnect(instanceId, endpointId);
    } finally {
      await _closeLocal();
    }
  }

  Future<void> _closeLocal() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _messages.close();
    if (!_done.isCompleted) _done.complete();
  }
}

final class _NearbyEndpoint {
  const _NearbyEndpoint(this.instanceId, this.endpointId);

  final String instanceId;
  final String endpointId;
}

final class _NearbyBridge {
  _NearbyBridge._();

  static final _NearbyBridge instance = _NearbyBridge._();

  static const _methods = MethodChannel(_nearbyMethodChannel);
  static const _eventsChannel = EventChannel(_nearbyEventChannel);

  Stream<Map<String, Object?>>? _events;

  Stream<Map<String, Object?>> get events {
    return _events ??= _eventsChannel.receiveBroadcastStream().map((event) {
      if (event is! Map) {
        throw const FormatException('Invalid graphx_connect nearby event.');
      }
      return event.cast<String, Object?>();
    }).asBroadcastStream();
  }

  Stream<Map<String, Object?>> eventsFor(String instanceId) {
    return events.where((event) => event['instanceId'] == instanceId);
  }

  Future<void> create({
    required String instanceId,
    required String serviceId,
    required String endpointName,
  }) {
    return _invoke('create', <String, Object?>{
      'instanceId': instanceId,
      'serviceId': serviceId,
      'endpointName': endpointName,
    });
  }

  Future<void> prepare(String instanceId) {
    return _invoke('prepare', <String, Object?>{'instanceId': instanceId});
  }

  Future<void> startAdvertising(String instanceId, Uint8List context) {
    return _invoke('startAdvertising', <String, Object?>{
      'instanceId': instanceId,
      'context': context,
    });
  }

  Future<void> stopAdvertising(String instanceId) {
    return _invoke('stopAdvertising', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> startDiscovery(String instanceId) {
    return _invoke('startDiscovery', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> stopDiscovery(String instanceId) {
    return _invoke('stopDiscovery', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> requestConnection(String instanceId, String endpointId) {
    return _invoke('requestConnection', <String, Object?>{
      'instanceId': instanceId,
      'endpointId': endpointId,
    });
  }

  Future<void> send(
    String instanceId,
    String endpointId,
    Uint8List data,
  ) {
    return _invoke('send', <String, Object?>{
      'instanceId': instanceId,
      'endpointId': endpointId,
      'data': data,
    });
  }

  Future<void> disconnect(String instanceId, String endpointId) {
    return _invoke('disconnect', <String, Object?>{
      'instanceId': instanceId,
      'endpointId': endpointId,
    });
  }

  Future<void> dispose(String instanceId) {
    return _invoke('dispose', <String, Object?>{'instanceId': instanceId});
  }

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    await _methods.invokeMethod<void>(method, arguments);
  }
}

String _validName(String value, String argument) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 63) {
    throw ArgumentError.value(
      value,
      argument,
      'Expected 1–63 non-whitespace characters.',
    );
  }
  return normalized;
}

String _validService(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 128) {
    throw ArgumentError.value(
      value,
      'service',
      'Expected a stable 1–128 character service identifier.',
    );
  }
  return normalized;
}

String _randomId() {
  Random random;
  try {
    random = Random.secure();
  } on UnsupportedError {
    random = Random(DateTime.now().microsecondsSinceEpoch);
  }
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import 'transport.dart';

const _serviceType = '_graphx._tcp';
const _socketPath = '/graphx-connect';
const _socketPingInterval = Duration(seconds: 5);

GConnectTransport createTransport() => const _LanTransport();

final class _LanTransport implements GConnectTransport {
  const _LanTransport();

  @override
  bool get supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  @override
  String get name => 'lan';

  void _ensureSupported() {
    if (!supported) {
      throw UnsupportedError(
        'GraphX Connect LAN currently supports Android, iOS, macOS, and Windows.',
      );
    }
  }

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) async {
    _ensureSupported();
    final server = await _bindServer();
    try {
      final registration = await nsd.register(
        nsd.Service(
          name: sessionName,
          type: _serviceType,
          port: server.port,
          txt: <String, Uint8List?>{
            'sid': Uint8List.fromList(utf8.encode(sessionId)),
            'v': Uint8List.fromList(utf8.encode('$protocolVersion')),
          },
        ),
      );
      return _IoHost(server, registration);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }

  static Future<HttpServer> _bindServer() async {
    try {
      return await HttpServer.bind(
        InternetAddress.anyIPv6,
        0,
        v6Only: false,
      );
    } on SocketException {
      return HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
  }

  @override
  Future<GTransportDiscovery> discover() async {
    _ensureSupported();
    final discovery = await nsd.startDiscovery(
      _serviceType,
      ipLookupType: nsd.IpLookupType.any,
    );
    return _IoDiscovery(discovery);
  }

  @override
  Future<GTransportConnection> connect(Object endpoint) async {
    _ensureSupported();
    if (endpoint is! _LanEndpoint) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Invalid LAN endpoint.');
    }

    Object? lastError;
    StackTrace? lastStack;
    for (final host in endpoint.hosts) {
      try {
        final uri = Uri(
          scheme: 'ws',
          host: host,
          port: endpoint.port,
          path: _socketPath,
        );
        final socket = await WebSocket.connect(uri.toString());
        return _IoConnection(socket);
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack!);
    }
    throw StateError('Discovered GraphX Connect service has no address.');
  }
}

final class _IoHost implements GTransportHost {
  _IoHost(this._server, this._registration) {
    _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final nsd.Registration _registration;
  final _connections = StreamController<GTransportConnection>.broadcast(
    sync: true,
  );
  final Set<WebSocket> _sockets = <WebSocket>{};
  bool _disposed = false;

  @override
  Stream<GTransportConnection> get connections => _connections.stream;

  Future<void> _handleRequest(HttpRequest request) async {
    if (_disposed) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    if (request.uri.path != _socketPath || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      if (_disposed) {
        await socket.close();
        return;
      }
      _sockets.add(socket);
      unawaited(socket.done.whenComplete(() => _sockets.remove(socket)));
      _connections.add(_IoConnection(socket));
    } catch (error, stack) {
      if (!_connections.isClosed) {
        _connections.addError(error, stack);
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await nsd.unregister(_registration);
    for (final socket in _sockets.toList(growable: false)) {
      await socket.close();
    }
    _sockets.clear();
    await _server.close(force: true);
    await _connections.close();
  }
}

final class _IoDiscovery implements GTransportDiscovery {
  _IoDiscovery(this._discovery) {
    _discovery.addServiceListener(_serviceChanged);
    Timer.run(() {
      if (_disposed) return;
      for (final service in _discovery.services) {
        _serviceChanged(service, nsd.ServiceStatus.found);
      }
    });
  }

  final nsd.Discovery _discovery;
  final _events = StreamController<GTransportDiscoveryEvent>.broadcast(
    sync: true,
  );
  final Map<String, GTransportService> _knownByName = <String, GTransportService>{};
  bool _disposed = false;

  @override
  Stream<GTransportDiscoveryEvent> get events => _events.stream;

  void _serviceChanged(nsd.Service service, nsd.ServiceStatus status) {
    if (_disposed) return;
    final name = service.name;
    if (name == null || name.isEmpty) return;

    if (status == nsd.ServiceStatus.lost) {
      final known = _knownByName[name];
      if (known == null) return;
      final lostId = _txt(service, 'sid');
      if (lostId != null && lostId.isNotEmpty && lostId != known.id) return;
      _knownByName.remove(name);
      _events.add(
        GTransportDiscoveryEvent(GTransportDiscoveryKind.lost, known),
      );
      return;
    }

    final id = _txt(service, 'sid');
    final versionText = _txt(service, 'v');
    final port = service.port;
    final version = int.tryParse(versionText ?? '');
    if (id == null || id.isEmpty || version == null || port == null) return;

    final hosts = <String>[];
    final hostname = service.host;
    if (hostname != null && hostname.isNotEmpty) {
      hosts.add(hostname);
    }
    final addresses = service.addresses ?? const <InternetAddress>[];
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4 && !hosts.contains(address.address)) {
        hosts.add(address.address);
      }
    }
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv6 && !hosts.contains(address.address)) {
        hosts.add(address.address);
      }
    }
    if (hosts.isEmpty) return;

    final endpoint = _LanEndpoint(hosts, port);
    final previous = _knownByName[name];
    if (previous != null) {
      final previousEndpoint = previous.endpoint;
      if (previous.id == id &&
          previous.protocolVersion == version &&
          previousEndpoint is _LanEndpoint &&
          previousEndpoint.sameAs(endpoint)) {
        return;
      }
      if (previous.id != id) {
        _events.add(
          GTransportDiscoveryEvent(GTransportDiscoveryKind.lost, previous),
        );
      }
    }

    final discovered = GTransportService(
      id: id,
      name: name,
      protocolVersion: version,
      endpoint: endpoint,
    );
    _knownByName[name] = discovered;
    _events.add(
      GTransportDiscoveryEvent(GTransportDiscoveryKind.found, discovered),
    );
  }

  static String? _txt(nsd.Service service, String key) {
    final bytes = service.txt?[key];
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await nsd.stopDiscovery(_discovery);
    _knownByName.clear();
    await _events.close();
  }
}

final class _IoConnection implements GTransportConnection {
  _IoConnection(this._socket) {
    _socket.pingInterval = _socketPingInterval;
  }

  final WebSocket _socket;

  @override
  Stream<Object> get messages => _socket.map<Object>((event) {
    if (event is String || event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    throw const FormatException('Unsupported GraphX Connect WebSocket frame.');
  });

  @override
  void send(Object message) {
    if (message is! String && message is! Uint8List) {
      throw ArgumentError.value(
        message,
        'message',
        'GraphX Connect transports accept String or Uint8List frames.',
      );
    }
    _socket.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) => _socket.close(code, reason);
}

final class _LanEndpoint {
  _LanEndpoint(List<String> hosts, this.port) : hosts = List<String>.unmodifiable(hosts);

  final List<String> hosts;
  final int port;

  bool sameAs(_LanEndpoint other) {
    if (port != other.port || hosts.length != other.hosts.length) return false;
    for (var i = 0; i < hosts.length; i++) {
      if (hosts[i] != other.hosts[i]) return false;
    }
    return true;
  }
}

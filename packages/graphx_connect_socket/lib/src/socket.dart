import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect/graphx_connect_spi.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'tcp_stub.dart' if (dart.library.io) 'tcp_io.dart' as tcp;

extension GSocketConnectExtension on GConnect {
  Future<GSession> webSocket(
    Uri uri, {
    String session = 'default',
    GSocketOptions options = const GSocketOptions(),
  }) {
    final normalized = _validSession(session);
    final transport = _WebSocketTransport(options);
    return GConnectSpi.join(
      connect: this,
      transport: transport,
      endpoint: uri,
      sessionId: normalized,
      sessionName: normalized,
    );
  }

  Future<GSession> tcp(
    String host, {
    required int port,
    String session = 'default',
    GSocketOptions options = const GSocketOptions(),
  }) {
    final normalized = _validSession(session);
    final transport = _TcpTransport(options);
    return GConnectSpi.join(
      connect: this,
      transport: transport,
      endpoint: _TcpEndpoint(host, port),
      sessionId: normalized,
      sessionName: normalized,
    );
  }
}

final class GSocketOptions {
  const GSocketOptions({
    this.timeout = const Duration(seconds: 10),
  });

  final Duration timeout;
}

final class _WebSocketTransport implements GConnectTransport {
  const _WebSocketTransport(this.options);

  final GSocketOptions options;

  @override
  bool get supported => true;

  @override
  String get name => 'websocket';

  @override
  Future<GTransportConnection> connect(Object endpoint) async {
    if (endpoint is! Uri || (endpoint.scheme != 'ws' && endpoint.scheme != 'wss')) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Expected a ws:// or wss:// URI.',
      );
    }
    final channel = WebSocketChannel.connect(endpoint);
    await channel.ready.timeout(options.timeout);
    return _WebSocketConnection(channel);
  }

  @override
  Future<GTransportDiscovery> discover() {
    throw UnsupportedError('WebSocket does not provide discovery.');
  }

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) {
    throw UnsupportedError(
      'WebSocket hosting is server-side and is not provided by this client connector.',
    );
  }
}

final class _WebSocketConnection implements GTransportConnection {
  _WebSocketConnection(this.channel);

  final WebSocketChannel channel;

  @override
  Stream<Object> get messages => channel.stream.map<Object>((event) {
    if (event is String || event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    throw FormatException(
      'Unsupported GraphX Connect WebSocket frame: \${event.runtimeType}.',
    );
  });

  @override
  void send(Object message) {
    if (message is! String && message is! Uint8List) {
      throw ArgumentError.value(
        message,
        'message',
        'Expected String or Uint8List.',
      );
    }
    channel.sink.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await channel.sink.close(code, reason);
  }
}

final class _TcpTransport implements GConnectTransport {
  const _TcpTransport(this.options);

  final GSocketOptions options;

  @override
  bool get supported => tcp.tcpSupported;

  @override
  String get name => 'tcp';

  @override
  Future<GTransportConnection> connect(Object endpoint) {
    if (endpoint is! _TcpEndpoint) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Expected TCP endpoint.');
    }
    if (!supported) {
      throw UnsupportedError('TCP is unavailable on this platform.');
    }
    return tcp.connectTcp(
      endpoint.host,
      endpoint.port,
      timeout: options.timeout,
    );
  }

  @override
  Future<GTransportDiscovery> discover() {
    throw UnsupportedError('TCP does not provide discovery.');
  }

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) {
    throw UnsupportedError(
      'TCP server hosting is not part of the client connector yet.',
    );
  }
}

final class _TcpEndpoint {
  const _TcpEndpoint(this.host, this.port);

  final String host;
  final int port;
}

String _validSession(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 128) {
    throw ArgumentError.value(
      value,
      'session',
      'Expected 1-128 non-whitespace characters.',
    );
  }
  return normalized;
}

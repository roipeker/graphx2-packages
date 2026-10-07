import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect/graphx_connect_spi.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'tcp_stub.dart' if (dart.library.io) 'tcp_io.dart' as tcp_impl;

/// General socket connectors plus optional GraphX session shortcuts.
extension GSocketConnectExtension on GConnect {
  /// Opens a raw WebSocket connection.
  ///
  /// No GraphX handshake or framing is added. Text and binary WebSocket frames
  /// are exposed directly through [GConnection].
  Future<GConnection> webSocket(
    Uri uri, {
    GSocketOptions options = const GSocketOptions(),
  }) {
    final transport = _WebSocketTransport(options);
    return GConnectSpi.open(
      connect: this,
      transport: transport,
      endpoint: uri,
    );
  }

  /// Opens a WebSocket and immediately layers the GraphX session protocol on
  /// top of it.
  Future<GSession> webSocketSession(
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

  /// Opens a raw TCP byte stream.
  ///
  /// Incoming events are byte chunks. No message framing or GraphX protocol
  /// bytes are added. Sending a [String] writes its UTF-8 bytes.
  Future<GConnection> tcp(
    String host, {
    required int port,
    GSocketOptions options = const GSocketOptions(),
  }) {
    final transport = _RawTcpTransport(options);
    return GConnectSpi.open(
      connect: this,
      transport: transport,
      sessionTransport: _TcpSessionTransport(options),
      sessionAdapter: tcp_impl.frameTcpConnection,
      endpoint: _TcpEndpoint(host, port),
    );
  }

  /// Opens framed TCP and immediately layers the GraphX session protocol on
  /// top of it.
  ///
  /// GraphX's TCP session framing preserves text/binary message boundaries over
  /// TCP's byte stream. Use [tcp] instead for arbitrary TCP protocols.
  Future<GSession> tcpSession(
    String host, {
    required int port,
    String session = 'default',
    GSocketOptions options = const GSocketOptions(),
  }) {
    final normalized = _validSession(session);
    final transport = _TcpSessionTransport(options);
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
      'Unsupported WebSocket frame: ${event.runtimeType}.',
    );
  });

  @override
  void send(Object message) {
    if (message is! String && message is! Uint8List && message is! List<int>) {
      throw ArgumentError.value(
        message,
        'message',
        'Expected String, Uint8List, or List<int>.',
      );
    }
    channel.sink.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await channel.sink.close(code, reason);
  }
}

final class _RawTcpTransport implements GConnectTransport {
  const _RawTcpTransport(this.options);

  final GSocketOptions options;

  @override
  bool get supported => tcp_impl.tcpSupported;

  @override
  String get name => 'tcp';

  @override
  Future<GTransportConnection> connect(Object endpoint) {
    final target = _validTcpEndpoint(endpoint);
    if (!supported) {
      throw UnsupportedError('TCP is unavailable on this platform.');
    }
    return tcp_impl.connectRawTcp(
      target.host,
      target.port,
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

final class _TcpSessionTransport implements GConnectTransport {
  const _TcpSessionTransport(this.options);

  final GSocketOptions options;

  @override
  bool get supported => tcp_impl.tcpSupported;

  @override
  String get name => 'tcp-session';

  @override
  Future<GTransportConnection> connect(Object endpoint) {
    final target = _validTcpEndpoint(endpoint);
    if (!supported) {
      throw UnsupportedError('TCP is unavailable on this platform.');
    }
    return tcp_impl.connectTcp(
      target.host,
      target.port,
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

_TcpEndpoint _validTcpEndpoint(Object endpoint) {
  if (endpoint is! _TcpEndpoint) {
    throw ArgumentError.value(endpoint, 'endpoint', 'Expected TCP endpoint.');
  }
  return endpoint;
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

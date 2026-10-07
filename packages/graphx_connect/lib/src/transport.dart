import 'dart:async';

/// Internal transport contract used by the LAN implementation and tests.
///
/// This library is intentionally not exported by `graphx_connect.dart`.
abstract interface class GConnectTransport {
  bool get supported;
  String get name;

  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  });

  Future<GTransportDiscovery> discover();

  Future<GTransportConnection> connect(Object endpoint);
}

/// Optional lifecycle hook for transports that own native/runtime state.
abstract interface class GDisposableTransport {
  Future<void> dispose();
}

abstract interface class GTransportHost {
  Stream<GTransportConnection> get connections;
  Future<void> dispose();
}

abstract interface class GTransportDiscovery {
  Stream<GTransportDiscoveryEvent> get events;
  Future<void> dispose();
}

abstract interface class GTransportConnection {
  /// Internal wire frames. Current transports carry [String] control/data
  /// frames and binary byte frames.
  Stream<Object> get messages;

  /// Sends one internal wire frame.
  void send(Object message);

  Future<void> close([int? code, String? reason]);
}

enum GTransportDiscoveryKind { found, lost }

final class GTransportDiscoveryEvent {
  const GTransportDiscoveryEvent(this.kind, this.service);

  final GTransportDiscoveryKind kind;
  final GTransportService service;
}

final class GTransportService {
  const GTransportService({
    required this.id,
    required this.name,
    required this.protocolVersion,
    required this.endpoint,
  });

  final String id;
  final String name;
  final int protocolVersion;
  final Object endpoint;
}

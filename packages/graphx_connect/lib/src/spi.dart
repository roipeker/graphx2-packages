import 'api.dart';
import 'connect.dart';
import 'transport.dart';

/// Stable construction seam for GraphX Connect transport packages.
abstract final class GConnectSpi {
  static GSession host({
    required GConnect connect,
    required GTransportHost host,
    GConnectTransport? transport,
    required String sessionId,
    required String sessionName,
  }) {
    return GSessionInternal.host(
      host: host,
      transport: transport,
      sessionId: sessionId,
      sessionName: sessionName,
      localPeerId: connect.id,
      localPeerName: connect.name,
      binaryMode: connect.binaryMode,
    );
  }

  static Future<GSession> join({
    required GConnect connect,
    required GConnectTransport transport,
    required Object endpoint,
    required String sessionId,
    required String sessionName,
  }) {
    return GSessionInternal.join(
      transport: transport,
      endpoint: endpoint,
      sessionId: sessionId,
      sessionName: sessionName,
      localPeerId: connect.id,
      localPeerName: connect.name,
      binaryMode: connect.binaryMode,
    );
  }

  static Future<GSession> joinDiscovered({
    required GConnect connect,
    required GConnectTransport transport,
    required GSessionInfo session,
  }) async {
    if (!session.compatible) {
      throw StateError(
        'GraphX Connect protocol ${session.protocolVersion} is incompatible '
        'with local protocol ${GConnect.protocolVersion}.',
      );
    }
    return join(
      connect: connect,
      transport: transport,
      endpoint: endpoint(session),
      sessionId: session.id,
      sessionName: session.name,
    );
  }

  static GDiscovery discovery(GTransportDiscovery transport) {
    return GDiscoveryInternal.create(transport);
  }

  static Object endpoint(GSessionInfo info) {
    return GSessionInfoInternal.endpoint(info);
  }
}

import 'connect.dart';
import 'protocol.dart';
import 'remote.dart';

/// Minimal entry point for GraphX peer sessions.
///
/// Pick how peers become reachable, then work only with [GSession].
abstract final class GConnect {
  static const int protocolVersion = gConnectProtocolVersion;

  /// Same-network discovery and direct local sessions.
  static GLocalConnect local({
    String name = 'GraphX peer',
    GBinaryMode binaryMode = GBinaryMode.raw,
  }) {
    return GLocalConnect(name: name, binaryMode: binaryMode);
  }

  /// Internet-capable peer sessions introduced through a rendezvous server.
  ///
  /// The server handles rendezvous/signaling. Application traffic uses the
  /// direct WebRTC path when available and may use TURN when required.
  static GRemoteConnect remote(
    Uri server, {
    String name = 'GraphX peer',
    GBinaryMode binaryMode = GBinaryMode.raw,
    List<GIceServer> iceServers = const <GIceServer>[],
    bool serverIce = true,
  }) {
    return GRemoteConnect(
      server,
      name: name,
      binaryMode: binaryMode,
      iceServers: iceServers,
      serverIce: serverIce,
    );
  }
}

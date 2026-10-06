import 'transport.dart';

GConnectTransport createTransport() => const _UnsupportedTransport();

final class _UnsupportedTransport implements GConnectTransport {
  const _UnsupportedTransport();

  @override
  bool get supported => false;

  @override
  String get name => 'lan';

  Never _unsupported() => throw UnsupportedError(
    'GraphX Connect LAN requires a native Flutter platform with local network access.',
  );

  @override
  Future<GTransportConnection> connect(Object endpoint) => _unsupported();

  @override
  Future<GTransportDiscovery> discover() => _unsupported();

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) => _unsupported();
}

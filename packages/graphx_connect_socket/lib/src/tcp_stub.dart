import 'package:graphx_connect/graphx_connect_spi.dart';

const bool tcpSupported = false;

Future<GTransportConnection> connectTcp(
  String host,
  int port, {
  required Duration timeout,
}) {
  throw UnsupportedError('TCP is unavailable on this platform.');
}

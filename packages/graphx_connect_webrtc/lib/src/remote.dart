import 'dart:math';

import 'package:graphx_connect/graphx_connect.dart';
import 'package:graphx_connect/graphx_connect_spi.dart';

import 'transport_webrtc.dart';

extension GWebRtcConnectExtension on GConnect {
  GWebRtc webRtc(
    Uri server, {
    List<GIceServer> iceServers = const <GIceServer>[],
    bool serverIce = true,
  }) {
    return GWebRtc._(
      this,
      server,
      iceServers: iceServers,
      serverIce: serverIce,
    );
  }
}

/// Pairing-code WebRTC connector.
final class GWebRtc {
  GWebRtc._(
    this.connect,
    this.server, {
    required List<GIceServer> iceServers,
    required this.serverIce,
  }) : _transport = GWebRtcTransport(
         server,
         iceServers: <Map<String, Object?>>[
           for (final server in iceServers) server.toMap(),
         ],
         serverIce: serverIce,
       );

  final GConnect connect;
  final Uri server;
  final bool serverIce;
  final GWebRtcTransport _transport;

  bool get supported => _transport.supported;
  String get transport => _transport.name;

  Future<GSession> host(String sessionName, {String? code}) async {
    final normalized = _validName(sessionName, 'sessionName');
    final roomCode = code == null ? _randomCode() : _normalizeCode(code);
    final host = await _transport.host(
      sessionId: roomCode,
      sessionName: normalized,
      protocolVersion: GConnect.protocolVersion,
    );
    return GConnectSpi.host(
      connect: connect,
      host: host,
      sessionId: roomCode,
      sessionName: normalized,
    );
  }

  Future<GSession> join(String code) {
    final normalized = _normalizeCode(code);
    return GConnectSpi.join(
      connect: connect,
      transport: _transport,
      endpoint: normalized,
      sessionId: normalized,
      sessionName: normalized,
    );
  }
}

final class GIceServer {
  const GIceServer(this.urls, {this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, Object?> toMap() => <String, Object?>{
    'urls': urls,
    if (username != null) 'username': username,
    if (credential != null) 'credential': credential,
  };
}

const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _randomCode() {
  final random = Random.secure();
  return List<String>.generate(
    6,
    (_) => _codeAlphabet[random.nextInt(_codeAlphabet.length)],
    growable: false,
  ).join();
}

String _normalizeCode(String value) {
  final normalized = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9]{3,12}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'code',
      'Expected 3-12 letters or digits.',
    );
  }
  return normalized;
}

String _validName(String value, String argument) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 63) {
    throw ArgumentError.value(value, argument, 'Name must be 1-63 characters.');
  }
  return normalized;
}

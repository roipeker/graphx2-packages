import 'dart:math';

import 'connect.dart';
import 'protocol.dart';
import 'transport_webrtc.dart';

/// Remote peer entry point returned by `GConnect.remote(...)`.
///
/// The rendezvous server introduces peers and may provide session-scoped ICE
/// servers. Application traffic moves over WebRTC data channels.
final class GRemoteConnect {
  GRemoteConnect(
    this.server, {
    this.name = 'GraphX peer',
    this.binaryMode = GBinaryMode.raw,
    List<GIceServer> iceServers = const <GIceServer>[],
    this.serverIce = true,
  }) : _peerId = _randomId(),
       _transport = GWebRtcTransport(
         server,
         iceServers: <Map<String, Object?>>[
           for (final server in iceServers) server._toMap(),
         ],
         serverIce: serverIce,
       ) {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 63) {
      throw ArgumentError.value(name, 'name', 'Name must be 1–63 characters.');
    }
  }

  final Uri server;
  final String name;
  final GBinaryMode binaryMode;

  /// Accept ICE configuration supplied by the rendezvous server.
  ///
  /// This is the preferred production path because TURN credentials can stay
  /// short-lived and server-side.
  final bool serverIce;

  final String _peerId;
  final GWebRtcTransport _transport;

  bool get supported => _transport.supported;
  String get transport => _transport.name;

  /// Creates a direct WebRTC session.
  ///
  /// When [code] is omitted a friendly six-character code is generated.
  /// Applications may provide their own short code (for example a 4-digit
  /// game-room code) as long as it is 3–12 uppercase letters or digits.
  Future<GSession> host(String sessionName, {String? code}) async {
    final normalized = sessionName.trim();
    if (normalized.isEmpty || normalized.length > 63) {
      throw ArgumentError.value(
        sessionName,
        'sessionName',
        'Name must be 1–63 characters.',
      );
    }
    final roomCode = code == null ? _randomCode() : _normalizeCode(code);
    final host = await _transport.host(
      sessionId: roomCode,
      sessionName: normalized,
      protocolVersion: gConnectProtocolVersion,
    );
    return GSessionInternal.host(
      host: host,
      sessionId: roomCode,
      sessionName: normalized,
      localPeerId: _peerId,
      localPeerName: name.trim(),
      binaryMode: binaryMode,
    );
  }

  /// Joins a remote session by pairing code.
  Future<GSession> join(String code) {
    final normalized = _normalizeCode(code);
    return GSessionInternal.join(
      transport: _transport,
      endpoint: normalized,
      sessionId: normalized,
      sessionName: normalized,
      localPeerId: _peerId,
      localPeerName: name.trim(),
      binaryMode: binaryMode,
    );
  }
}

/// Optional static ICE fallback.
///
/// Prefer server-provided ICE for public deployments so TURN credentials can
/// be short-lived. Static configuration remains useful for LAN tests and
/// self-hosted environments.
final class GIceServer {
  const GIceServer(this.urls, {this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  Map<String, Object?> _toMap() => <String, Object?>{
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
      'Expected 3–12 letters or digits.',
    );
  }
  return normalized;
}

String _randomId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

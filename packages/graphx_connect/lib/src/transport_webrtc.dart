import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

final class GWebRtcTransport implements GConnectTransport {
  GWebRtcTransport(
    this.server, {
    List<Map<String, Object?>>? iceServers,
    this.serverIce = true,
  }) : _iceServers = iceServers ?? const <Map<String, Object?>>[];

  final Uri server;
  final List<Map<String, Object?>> _iceServers;
  final bool serverIce;

  @override
  bool get supported => server.scheme == 'ws' || server.scheme == 'wss';

  @override
  String get name => 'webrtc';

  @override
  Future<GTransportHost> host({
    required String sessionId,
    required String sessionName,
    required int protocolVersion,
  }) => _WebRtcHost.open(
    server,
    room: sessionId,
    protocolVersion: protocolVersion,
    iceServers: _iceServers,
    serverIce: serverIce,
  );

  @override
  Future<GTransportDiscovery> discover() => throw UnsupportedError(
    'WebRTC rendezvous uses pairing codes instead of discovery.',
  );

  @override
  Future<GTransportConnection> connect(Object endpoint) {
    if (endpoint is! String || endpoint.isEmpty) {
      throw ArgumentError.value(endpoint, 'endpoint', 'Expected a room code.');
    }
    return _WebRtcClient.connect(
      server,
      room: endpoint,
      iceServers: _iceServers,
      serverIce: serverIce,
    );
  }
}

final class _WebRtcHost implements GTransportHost {
  _WebRtcHost._(
    this._signal,
    List<Map<String, Object?>> iceServers, {
    required this.serverIce,
  }) : _iceServers = List<Map<String, Object?>>.of(iceServers);

  static Future<_WebRtcHost> open(
    Uri server, {
    required String room,
    required int protocolVersion,
    required List<Map<String, Object?>> iceServers,
    required bool serverIce,
  }) async {
    final signal = await _SignalSocket.open(server, <String, String>{
      'role': 'host',
      'room': room,
      'protocol': '$protocolVersion',
      'peer': _signalPeerId(),
    });
    final host = _WebRtcHost._(
      signal,
      iceServers,
      serverIce: serverIce,
    );
    host._subscription = signal.attach(host._onSignal);
    return host;
  }

  final _SignalSocket _signal;
  final bool serverIce;
  List<Map<String, Object?>> _iceServers;
  final _connections = StreamController<GTransportConnection>.broadcast(sync: true);
  final Map<String, _RtcLink> _links = <String, _RtcLink>{};
  StreamSubscription<Map<String, Object?>>? _subscription;
  bool _disposed = false;

  @override
  Stream<GTransportConnection> get connections => _connections.stream;

  Future<void> _onSignal(Map<String, Object?> message) async {
    if (_disposed) return;
    if (serverIce) {
      final supplied = _readIceServers(message['iceServers']);
      if (supplied.isNotEmpty) _iceServers = supplied;
    }

    final type = message['type'];
    if (type == 'joined' || type == 'config') return;

    if (type == 'join' || type == 'peer-ready') {
      final rawClient = message['client'];
      final client = rawClient is String && rawClient.isNotEmpty ? rawClient : 'peer';
      if (_links.containsKey(client)) return;
      final old = _links.remove(client);
      if (old != null) await old.close();
      final link = await _RtcLink.host(
        client,
        _signal,
        _iceServers,
        onOpen: _connections.add,
        onClosed: () => _links.remove(client),
      );
      _links[client] = link;
      return;
    }

    _RtcLink? link;
    final client = message['client'];
    if (client is String) {
      link = _links[client];
    } else if (_links.length == 1) {
      link = _links.values.single;
    }
    if (link == null) return;

    if (type == 'signal') {
      await link.acceptSignal(message);
    } else if (type == 'leave' || type == 'peer-left') {
      _links.remove(link.id);
      await link.close();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    for (final link in _links.values.toList(growable: false)) {
      await link.close();
    }
    _links.clear();
    await _signal.close();
    await _connections.close();
  }
}

final class _WebRtcClient {
  static Future<GTransportConnection> connect(
    Uri server, {
    required String room,
    required List<Map<String, Object?>> iceServers,
    required bool serverIce,
  }) async {
    final signal = await _SignalSocket.open(
      server,
      <String, String>{
        'role': 'join',
        'room': room,
        'peer': _signalPeerId(),
      },
    );

    var effectiveIce = List<Map<String, Object?>>.of(iceServers);
    if (serverIce) {
      final bootstrap = await signal.waitForBootstrap();
      final supplied = _readIceServers(bootstrap?['iceServers']);
      if (supplied.isNotEmpty) effectiveIce = supplied;
    }

    final completer = Completer<GTransportConnection>();
    late final _RtcLink link;
    link = await _RtcLink.client(
      signal,
      effectiveIce,
      onOpen: (connection) {
        if (!completer.isCompleted) completer.complete(connection);
      },
      onClosed: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('WebRTC connection closed before opening.'),
          );
        }
      },
    );
    link.ownedSignal = signal;
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () async {
        await link.close();
        throw TimeoutException('GraphX Connect WebRTC handshake timed out.');
      },
    );
  }
}

final class _RtcLink {
  _RtcLink._(this.id, this.signal, this.pc, this._onOpen, this._onClosed);

  static Future<_RtcLink> host(
    String client,
    _SignalSocket signal,
    List<Map<String, Object?>> iceServers, {
    required void Function(GTransportConnection) onOpen,
    required void Function() onClosed,
  }) async {
    final pc = await createPeerConnection(
      <String, dynamic>{'iceServers': iceServers},
    );
    final link = _RtcLink._(client, signal, pc, onOpen, onClosed);
    link._wirePeerConnection();

    final init = RTCDataChannelInit();
    init.ordered = true;
    init.binaryType = 'binary';
    final channel = await pc.createDataChannel('graphx-connect', init);
    link._attachChannel(channel);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    signal.send(<String, Object?>{
      'type': 'signal',
      'client': client,
      'description': <String, Object?>{
        'type': offer.type,
        'sdp': offer.sdp,
      },
    });
    return link;
  }

  static Future<_RtcLink> client(
    _SignalSocket signal,
    List<Map<String, Object?>> iceServers, {
    required void Function(GTransportConnection) onOpen,
    required void Function() onClosed,
  }) async {
    final pc = await createPeerConnection(
      <String, dynamic>{'iceServers': iceServers},
    );
    final link = _RtcLink._('', signal, pc, onOpen, onClosed);
    link._wirePeerConnection();
    pc.onDataChannel = link._attachChannel;
    link._signalSubscription = signal.attach(link.acceptSignal);
    return link;
  }

  final String id;
  final _SignalSocket signal;
  final RTCPeerConnection pc;
  final void Function(GTransportConnection) _onOpen;
  final void Function() _onClosed;
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];
  StreamSubscription<Map<String, Object?>>? _signalSubscription;
  _RtcConnection? _connection;
  _SignalSocket? ownedSignal;
  bool _remoteDescriptionSet = false;
  bool _closed = false;

  void _wirePeerConnection() {
    pc.onIceCandidate = (candidate) {
      if (_closed || candidate.candidate == null) return;
      signal.send(<String, Object?>{
        'type': 'signal',
        if (id.isNotEmpty) 'client': id,
        'candidate': <String, Object?>{
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        unawaited(close());
      }
    };
  }

  void _attachChannel(RTCDataChannel channel) {
    final connection = _RtcConnection(channel, closeOwner: close);
    _connection = connection;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _onOpen(connection);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        unawaited(close());
      }
    };
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      _onOpen(connection);
    }
  }

  Future<void> acceptSignal(Map<String, Object?> message) async {
    if (_closed || message['type'] != 'signal') return;

    final description = message['description'];
    if (description is Map) {
      final type = description['type'];
      final sdp = description['sdp'];
      if (type is String && sdp is String) {
        await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
        _remoteDescriptionSet = true;
        for (final candidate in _pendingCandidates) {
          await pc.addCandidate(candidate);
        }
        _pendingCandidates.clear();

        if (type == 'offer') {
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          signal.send(<String, Object?>{
            'type': 'signal',
            if (id.isNotEmpty) 'client': id,
            'description': <String, Object?>{
              'type': answer.type,
              'sdp': answer.sdp,
            },
          });
        }
      }
    }

    final candidateMap = message['candidate'];
    if (candidateMap is Map) {
      final lineIndex = candidateMap['sdpMLineIndex'];
      final candidate = RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        lineIndex is num ? lineIndex.toInt() : null,
      );
      if (_remoteDescriptionSet) {
        await pc.addCandidate(candidate);
      } else {
        _pendingCandidates.add(candidate);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _signalSubscription?.cancel();
    await _connection?._closeChannel();
    await pc.close();
    await pc.dispose();
    await ownedSignal?.close();
    _onClosed();
  }
}

final class _RtcConnection implements GTransportConnection {
  _RtcConnection(
    this._channel, {
    required Future<void> Function() closeOwner,
  }) : _closeOwner = closeOwner {
    _channel.onMessage = (message) {
      if (!_messages.isClosed) {
        _messages.add(message.isBinary ? message.binary : message.text);
      }
    };
  }

  final RTCDataChannel _channel;
  final Future<void> Function() _closeOwner;
  final _messages = StreamController<Object>.broadcast(sync: true);
  bool _closed = false;

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  void send(Object message) {
    if (_closed) throw StateError('WebRTC data channel is closed.');
    if (message is String) {
      unawaited(_channel.send(RTCDataChannelMessage(message)));
      return;
    }
    if (message is Uint8List) {
      unawaited(
        _channel.send(RTCDataChannelMessage.fromBinary(message)),
      );
      return;
    }
    throw ArgumentError.value(
      message,
      'message',
      'Expected String or Uint8List.',
    );
  }

  Future<void> _closeChannel() async {
    if (_closed) return;
    _closed = true;
    await _channel.close();
    await _messages.close();
  }

  @override
  Future<void> close([int? code, String? reason]) => _closeOwner();
}

final class _SignalSocket {
  _SignalSocket._(this._channel) {
    _subscription = _channel.stream.listen(
      (event) {
        if (event is! String) return;
        Object? decoded;
        try {
          decoded = jsonDecode(event);
        } on FormatException {
          return;
        }
        if (decoded is! Map) return;
        final message = decoded.cast<String, Object?>();
        final type = message['type'];
        if (!_bootstrap.isCompleted && (type == 'joined' || type == 'config')) {
          _bootstrap.complete(message);
        }
        if (_buffering) {
          _pending.add(message);
        } else if (!_events.isClosed) {
          _events.add(message);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_bootstrap.isCompleted) _bootstrap.complete(null);
        if (!_events.isClosed) _events.addError(error, stack);
      },
      onDone: () {
        if (!_bootstrap.isCompleted) _bootstrap.complete(null);
        if (!_events.isClosed) _events.close();
      },
    );
  }

  static Future<_SignalSocket> open(
    Uri server,
    Map<String, String> query,
  ) async {
    final uri = server.replace(
      queryParameters: <String, String>{
        ...server.queryParameters,
        ...query,
      },
    );
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return _SignalSocket._(channel);
  }

  final WebSocketChannel _channel;
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  final _bootstrap = Completer<Map<String, Object?>?>();
  final _pending = <Map<String, Object?>>[];
  late final StreamSubscription<Object?> _subscription;
  bool _buffering = true;

  StreamSubscription<Map<String, Object?>> attach(
    void Function(Map<String, Object?>) onData,
  ) {
    final subscription = _events.stream.listen(onData);
    final pending = List<Map<String, Object?>>.of(_pending);
    _pending.clear();
    _buffering = false;
    for (final message in pending) {
      onData(message);
    }
    return subscription;
  }

  Future<Map<String, Object?>?> waitForBootstrap() {
    return _bootstrap.future.timeout(
      const Duration(milliseconds: 750),
      onTimeout: () => null,
    );
  }

  void send(Map<String, Object?> message) {
    _channel.sink.add(jsonEncode(message));
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _channel.sink.close();
    if (!_bootstrap.isCompleted) _bootstrap.complete(null);
    if (!_events.isClosed) await _events.close();
  }
}

List<Map<String, Object?>> _readIceServers(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];

  final result = <Map<String, Object?>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final urls = item['urls'];
    if (urls is! String &&
        !(urls is List && urls.isNotEmpty && urls.every((value) => value is String))) {
      continue;
    }

    final server = <String, Object?>{'urls': urls};
    final username = item['username'];
    final credential = item['credential'];
    if (username is String && username.isNotEmpty) {
      server['username'] = username;
    }
    if (credential is String && credential.isNotEmpty) {
      server['credential'] = credential;
    }
    result.add(server);
  }
  return result;
}

String _signalPeerId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 8; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

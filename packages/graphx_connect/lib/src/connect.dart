import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'protocol.dart';
import 'transport.dart';
import 'transport_stub.dart' if (dart.library.io) 'transport_io.dart' as transport_impl;

/// Small entry point for hosting, discovering, and joining local sessions.
final class GConnect {
  factory GConnect({
    String name = 'GraphX peer',
    GBinaryMode binaryMode = GBinaryMode.raw,
  }) => GConnect._(
    transport_impl.createTransport(),
    name: _validName(name, 'name'),
    peerId: _randomId(),
    binaryMode: binaryMode,
  );

  GConnect._(
    this._transport, {
    required this.name,
    required String peerId,
    required this.binaryMode,
  }) : _peerId = peerId;

  static const int protocolVersion = gConnectProtocolVersion;

  final GConnectTransport _transport;
  final String _peerId;

  /// Human-readable identity sent to remote peers.
  final String name;

  /// Binary packet policy. Raw is the zero-envelope fast path.
  final GBinaryMode binaryMode;

  /// Whether the default LAN transport is usable on this platform.
  bool get supported => _transport.supported;

  /// Name of the selected transport. The initial implementation is `lan`.
  String get transport => _transport.name;

  /// Hosts a discoverable local session.
  Future<GSession> host(String sessionName) async {
    _ensureSupported();
    final normalized = _validName(sessionName, 'sessionName');
    final sessionId = _randomId();
    final host = await _transport.host(
      sessionId: sessionId,
      sessionName: normalized,
      protocolVersion: protocolVersion,
    );
    return GSessionInternal.host(
      host: host,
      sessionId: sessionId,
      sessionName: normalized,
      localPeerId: _peerId,
      localPeerName: name,
      binaryMode: binaryMode,
    );
  }

  /// Starts local discovery. Dispose the returned object when scanning ends.
  Future<GDiscovery> discover() async {
    _ensureSupported();
    final discovery = await _transport.discover();
    return GDiscovery._(discovery);
  }

  /// Joins one discovered session.
  Future<GSession> join(GSessionInfo info) async {
    _ensureSupported();
    if (info.protocolVersion != protocolVersion) {
      throw StateError(
        'GraphX Connect protocol ${info.protocolVersion} is incompatible with local protocol $protocolVersion.',
      );
    }
    return GSessionInternal.join(
      transport: _transport,
      endpoint: info._endpoint,
      sessionId: info.id,
      sessionName: info.name,
      localPeerId: _peerId,
      localPeerName: name,
      binaryMode: binaryMode,
    );
  }

  void _ensureSupported() {
    if (!supported) {
      throw UnsupportedError(
        'GraphX Connect ${_transport.name} transport is unavailable on this platform.',
      );
    }
  }
}

/// One session found by [GConnect.discover].
final class GSessionInfo {
  const GSessionInfo._({
    required this.id,
    required this.name,
    required this.protocolVersion,
    required Object endpoint,
  }) : _endpoint = endpoint;

  final String id;
  final String name;
  final int protocolVersion;
  final Object _endpoint;

  bool get compatible => protocolVersion == GConnect.protocolVersion;

  @override
  String toString() => 'GSessionInfo($name, v$protocolVersion)';
}

enum GDiscoveryEventType { found, lost }

final class GDiscoveryEvent {
  const GDiscoveryEvent(this.type, this.session);

  final GDiscoveryEventType type;
  final GSessionInfo session;
}

/// Live local-session discovery.
final class GDiscovery {
  GDiscovery._(this._transport) {
    _subscription = _transport.events.listen(_onTransportEvent);
  }

  final GTransportDiscovery _transport;
  final Map<String, GSessionInfo> _sessions = <String, GSessionInfo>{};
  final _events = StreamController<GDiscoveryEvent>.broadcast(sync: true);
  late final StreamSubscription<GTransportDiscoveryEvent> _subscription;
  bool _disposed = false;

  List<GSessionInfo> get sessions => List<GSessionInfo>.unmodifiable(_sessions.values);

  Stream<GDiscoveryEvent> get events => _events.stream;

  bool get disposed => _disposed;

  void _onTransportEvent(GTransportDiscoveryEvent event) {
    if (_disposed) return;
    final service = event.service;
    if (event.kind == GTransportDiscoveryKind.lost) {
      final removed = _sessions.remove(service.id);
      if (removed != null) {
        _events.add(GDiscoveryEvent(GDiscoveryEventType.lost, removed));
      }
      return;
    }

    final info = GSessionInfo._(
      id: service.id,
      name: service.name,
      protocolVersion: service.protocolVersion,
      endpoint: service.endpoint,
    );
    _sessions[info.id] = info;
    _events.add(GDiscoveryEvent(GDiscoveryEventType.found, info));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _transport.dispose();
    _sessions.clear();
    await _events.close();
  }
}

enum GBinaryMode {
  /// Send exactly the supplied bytes. Compatibility is checked once during
  /// the peer handshake; packets carry no GraphX Connect header.
  raw,

  /// Prefix binary packets with a 4-byte unsigned sender sequence.
  sequenced,
}

enum GSessionState { connecting, connected, disconnected, disposed }

enum GPeerState { connected, disconnected }

enum GPeerEventType { connected, reconnected, disconnected }

final class GPeerEvent {
  const GPeerEvent(this.type, this.peer);

  final GPeerEventType type;
  final GPeer peer;
}

/// Stable remote-peer identity for the lifetime of a session.
final class GPeer {
  GPeer._(this.id, this._name);

  final String id;
  String _name;
  GPeerState _state = GPeerState.disconnected;
  Duration? _latency;

  String get name => _name;
  GPeerState get state => _state;
  bool get connected => _state == GPeerState.connected;
  Duration? get latency => _latency;

  @override
  String toString() => 'GPeer($name, $state)';
}

/// One application message received from a remote peer.
final class GMessage {
  const GMessage({
    required this.peer,
    required this.sequence,
    required this.data,
    this.bytes,
  }) : assert(bytes == null || data == null);

  final GPeer peer;

  /// Sender sequence for structured or sequenced-binary messages.
  /// Raw binary messages intentionally have no per-packet sequence.
  final int? sequence;

  /// Structured JSON-compatible payload. Null for binary messages.
  final Object? data;

  /// Raw binary payload when [isBinary] is true.
  final Uint8List? bytes;

  bool get isBinary => bytes != null;
}

/// Active host or joined connection.
///
/// Client reconnects are explicit: a dropped connection moves to
/// [GSessionState.disconnected] until [reconnect] is called.
final class GSession {
  GSession._({
    required this.id,
    required this.name,
    required this.isHost,
    required this.binaryMode,
    required String localPeerId,
    required String localPeerName,
    required GSessionState state,
    GConnectTransport? transport,
    Object? endpoint,
    GTransportHost? host,
  }) : localPeer = GPeer._(localPeerId, localPeerName),
       _state = state,
       _transport = transport,
       _endpoint = endpoint,
       _host = host {
    localPeer._state = GPeerState.connected;
  }

  final String id;
  final String name;
  final bool isHost;
  final GBinaryMode binaryMode;
  final GPeer localPeer;

  final GConnectTransport? _transport;
  final Object? _endpoint;
  final GTransportHost? _host;
  final Map<String, GPeer> _peers = <String, GPeer>{};
  final Map<String, _GLink> _hostLinks = <String, _GLink>{};
  final _messages = StreamController<GMessage>.broadcast(sync: true);
  final _peerEvents = StreamController<GPeerEvent>.broadcast(sync: true);

  StreamSubscription<GTransportConnection>? _hostSubscription;
  _GLink? _clientLink;
  GSessionState _state;
  int _nextSequence = 0;

  GSessionState get state => _state;
  bool get connected => _state == GSessionState.connected;
  bool get disposed => _state == GSessionState.disposed;

  /// All remote peers observed during this session, including disconnected
  /// peers retained so a reconnect preserves object identity.
  List<GPeer> get peers => List<GPeer>.unmodifiable(_peers.values);

  Stream<GPeerEvent> get peerEvents => _peerEvents.stream;
  Stream<GMessage> get messages => _messages.stream;

  /// Sends JSON-compatible application data.
  ///
  /// Hosts broadcast when [to] is omitted. Joined clients send to their host.
  void send(Object? data, {GPeer? to}) {
    _ensureCanSend();
    final sequence = _nextSequence++;
    _sendEncoded(
      GConnectProtocol.data(
        sessionId: id,
        peerId: localPeer.id,
        sequence: sequence,
        payload: data,
      ),
      to: to,
    );
  }

  /// Sends raw application bytes as a binary transport frame.
  ///
  /// Binary payloads are not JSON encoded or base64 wrapped. Hosts broadcast
  /// when [to] is omitted. Joined clients send to their host.
  void sendBytes(Uint8List bytes, {GPeer? to}) {
    _ensureCanSend();
    if (binaryMode == GBinaryMode.raw) {
      _sendEncoded(bytes, to: to);
      return;
    }
    final sequence = _nextSequence++ & 0xffffffff;
    _sendEncoded(
      GConnectProtocol.binaryData(sequence: sequence, payload: bytes),
      to: to,
    );
  }

  void _ensureCanSend() {
    _ensureUsable();
    if (!connected) {
      throw StateError('Cannot send while the session is not connected.');
    }
  }

  void _sendEncoded(Object encoded, {GPeer? to}) {
    if (isHost) {
      if (to != null) {
        final known = _peers[to.id];
        final link = _hostLinks[to.id];
        if (!identical(known, to) || link == null || !to.connected) {
          throw ArgumentError.value(to, 'to', 'Peer is not connected here.');
        }
        link.sendEncoded(encoded);
        return;
      }
      for (final link in _hostLinks.values) {
        link.sendEncoded(encoded);
      }
      return;
    }

    final link = _clientLink;
    if (link == null || link.peer == null) {
      throw StateError('Client session has no connected host.');
    }
    if (to != null && !identical(to, link.peer)) {
      throw ArgumentError.value(to, 'to', 'Client sessions can only send to their host.');
    }
    link.sendEncoded(encoded);
  }

  /// Disconnects a joined client while preserving identity for [reconnect].
  Future<void> disconnect() async {
    _ensureUsable();
    if (isHost) {
      throw StateError('Host sessions are stopped with dispose().');
    }
    final link = _clientLink;
    if (link == null) {
      _state = GSessionState.disconnected;
      return;
    }
    await link.close(1000, 'disconnect');
  }

  /// Performs one explicit reconnect attempt for a joined client.
  Future<void> reconnect() async {
    _ensureUsable();
    if (isHost) {
      throw StateError('Host sessions do not reconnect.');
    }
    if (connected) return;
    if (_state == GSessionState.connecting) {
      throw StateError('Reconnect is already in progress.');
    }
    _state = GSessionState.connecting;
    try {
      await _connectClient();
    } catch (_) {
      if (!disposed) _state = GSessionState.disconnected;
      rethrow;
    }
  }

  Future<void> _connectClient() async {
    final transport = _transport;
    final endpoint = _endpoint;
    if (transport == null || endpoint == null) {
      throw StateError('Client session has no transport endpoint.');
    }
    final connection = await transport.connect(endpoint);
    if (disposed) {
      await connection.close();
      throw StateError('Session was disposed while connecting.');
    }

    final link = _GLink.client(this, connection);
    _clientLink = link;
    try {
      await link.ready;
      if (!disposed) _state = GSessionState.connected;
    } catch (_) {
      if (identical(_clientLink, link)) _clientLink = null;
      await link.close(4000, 'handshake failed');
      rethrow;
    }
  }

  void _startHost() {
    final host = _host!;
    _hostSubscription = host.connections.listen(
      (connection) => _GLink.host(this, connection),
      onError: (Object error, StackTrace stack) {
        if (!_messages.isClosed) _messages.addError(error, stack);
      },
    );
  }

  GPeer _acceptHostPeer(_GLink link, String peerId, String peerName) {
    final existing = _peers[peerId];
    final peer = existing ?? GPeer._(peerId, peerName);
    final previous = _hostLinks[peerId];

    peer._name = peerName;
    peer._state = GPeerState.connected;
    _peers[peerId] = peer;
    _hostLinks[peerId] = link;

    if (previous != null && !identical(previous, link)) {
      unawaited(previous.close(4002, 'replaced by reconnect'));
    }

    _peerEvents.add(
      GPeerEvent(
        existing == null ? GPeerEventType.connected : GPeerEventType.reconnected,
        peer,
      ),
    );
    return peer;
  }

  GPeer _acceptServerPeer(_GLink link, String peerId, String peerName) {
    final existing = _peers[peerId];
    final peer = existing ?? GPeer._(peerId, peerName);
    peer._name = peerName;
    peer._state = GPeerState.connected;
    _peers[peerId] = peer;
    _peerEvents.add(
      GPeerEvent(
        existing == null ? GPeerEventType.connected : GPeerEventType.reconnected,
        peer,
      ),
    );
    return peer;
  }

  void _receive(_GLink link, GConnectFrame frame) {
    final peer = link.peer;
    if (peer == null) return;
    if (frame.sessionId != id || frame.peerId != peer.id) {
      unawaited(link.close(4001, 'invalid frame identity'));
      return;
    }

    switch (frame.type) {
      case 'data':
        final sequence = frame.sequence;
        if (sequence == null) {
          unawaited(link.close(4001, 'missing sequence'));
          return;
        }
        _messages.add(
          GMessage(
            peer: peer,
            sequence: sequence,
            data: frame.payload,
          ),
        );
        return;
      case 'ping':
        final pingId = frame.pingId;
        if (pingId == null) {
          unawaited(link.close(4001, 'missing ping id'));
          return;
        }
        link.sendEncoded(
          GConnectProtocol.pong(
            sessionId: id,
            peerId: localPeer.id,
            pingId: pingId,
          ),
        );
        return;
      case 'pong':
        final pingId = frame.pingId;
        if (pingId == null || !link.acceptPong(pingId)) {
          return;
        }
        return;
      default:
        unawaited(link.close(4001, 'unexpected frame'));
    }
  }

  void _receiveBinary(
    _GLink link,
    Uint8List bytes, {
    int? sequence,
  }) {
    final peer = link.peer;
    if (peer == null) return;
    _messages.add(
      GMessage(
        peer: peer,
        sequence: sequence,
        data: null,
        bytes: bytes,
      ),
    );
  }

  void _linkClosed(_GLink link) {
    final peer = link.peer;
    if (isHost) {
      if (peer == null || !identical(_hostLinks[peer.id], link)) return;
      _hostLinks.remove(peer.id);
      peer._state = GPeerState.disconnected;
      peer._latency = null;
      if (!disposed && !_peerEvents.isClosed) {
        _peerEvents.add(GPeerEvent(GPeerEventType.disconnected, peer));
      }
      return;
    }

    if (!identical(_clientLink, link)) return;
    _clientLink = null;
    if (peer != null) {
      peer._state = GPeerState.disconnected;
      peer._latency = null;
      if (!disposed && !_peerEvents.isClosed) {
        _peerEvents.add(GPeerEvent(GPeerEventType.disconnected, peer));
      }
    }
    if (!disposed) _state = GSessionState.disconnected;
  }

  void _ensureUsable() {
    if (disposed) throw StateError('GSession is disposed.');
  }

  Future<void> dispose() async {
    if (disposed) return;
    _state = GSessionState.disposed;

    await _hostSubscription?.cancel();
    _hostSubscription = null;

    final clientLink = _clientLink;
    _clientLink = null;
    if (clientLink != null) await clientLink.close();

    final links = _hostLinks.values.toList(growable: false);
    _hostLinks.clear();
    for (final link in links) {
      await link.close();
    }
    for (final peer in _peers.values) {
      peer._state = GPeerState.disconnected;
      peer._latency = null;
    }

    await _host?.dispose();
    await _messages.close();
    await _peerEvents.close();
  }
}

/// Internal construction seam. Not exported from the package entry point.
abstract final class GSessionInternal {
  static GSession host({
    required GTransportHost host,
    required String sessionId,
    required String sessionName,
    required String localPeerId,
    required String localPeerName,
    required GBinaryMode binaryMode,
  }) {
    final session = GSession._(
      id: sessionId,
      name: sessionName,
      isHost: true,
      localPeerId: localPeerId,
      localPeerName: localPeerName,
      binaryMode: binaryMode,
      state: GSessionState.connected,
      host: host,
    );
    session._startHost();
    return session;
  }

  static Future<GSession> join({
    required GConnectTransport transport,
    required Object endpoint,
    required String sessionId,
    required String sessionName,
    required String localPeerId,
    required String localPeerName,
    required GBinaryMode binaryMode,
  }) async {
    final session = GSession._(
      id: sessionId,
      name: sessionName,
      isHost: false,
      localPeerId: localPeerId,
      localPeerName: localPeerName,
      binaryMode: binaryMode,
      state: GSessionState.connecting,
      transport: transport,
      endpoint: endpoint,
    );
    try {
      await session._connectClient();
      return session;
    } catch (_) {
      await session.dispose();
      rethrow;
    }
  }
}

/// Internal injection seam used by package tests and future transport work.
/// Not exported from the public library.
abstract final class GConnectInternal {
  static GConnect create({
    required GConnectTransport transport,
    required String name,
    required String peerId,
    GBinaryMode binaryMode = GBinaryMode.raw,
  }) => GConnect._(
    transport,
    name: _validName(name, 'name'),
    peerId: peerId,
    binaryMode: binaryMode,
  );
}

final class _GLink {
  _GLink.host(this.session, this.connection) : _incoming = true {
    _start();
  }

  _GLink.client(this.session, this.connection) : _incoming = false {
    _ready = Completer<void>();
    _start();
    sendEncoded(
      GConnectProtocol.hello(
        sessionId: session.id,
        peerId: session.localPeer.id,
        peerName: session.localPeer.name,
        binaryMode: session.binaryMode.name,
      ),
    );
  }

  final GSession session;
  final GTransportConnection connection;
  final bool _incoming;

  GPeer? peer;
  StreamSubscription<Object>? _subscription;
  Completer<void>? _ready;
  Timer? _handshakeTimer;
  Timer? _pingTimer;
  int _nextPingId = 0;
  int? _pendingPingId;
  Stopwatch? _pingWatch;
  bool _closed = false;

  Future<void> get ready => _ready?.future ?? Future<void>.value();

  void _start() {
    _subscription = connection.messages.listen(
      _onMessage,
      onError: (Object error, StackTrace stack) => _finish(error, stack),
      onDone: _finish,
      cancelOnError: false,
    );
    _handshakeTimer = Timer(const Duration(seconds: 5), () {
      if (peer != null || _closed) return;
      _failHandshake(StateError('GraphX Connect handshake timed out.'));
      unawaited(close(4000, 'handshake timeout'));
    });
  }

  void _onMessage(Object encoded) {
    if (_closed) return;

    if (encoded is Uint8List) {
      if (peer == null) {
        _failHandshake(
          StateError('Binary GraphX Connect frame received before handshake.'),
        );
        unawaited(close(4001, 'binary before handshake'));
        return;
      }

      if (session.binaryMode == GBinaryMode.raw) {
        session._receiveBinary(this, encoded);
        return;
      }

      try {
        final frame = GConnectProtocol.decodeBinary(encoded);
        session._receiveBinary(
          this,
          frame.payload,
          sequence: frame.sequence,
        );
      } catch (error, stack) {
        _failHandshake(error, stack);
        unawaited(close(4001, 'invalid binary frame'));
      }
      return;
    }

    if (encoded is! String) {
      _failHandshake(StateError('Unsupported GraphX Connect frame type.'));
      unawaited(close(4001, 'invalid frame type'));
      return;
    }

    GConnectFrame frame;
    try {
      frame = GConnectProtocol.decode(encoded);
    } catch (error, stack) {
      _failHandshake(error, stack);
      unawaited(close(4001, 'invalid frame'));
      return;
    }

    if (frame.version != GConnect.protocolVersion) {
      _failHandshake(
        StateError('Incompatible GraphX Connect protocol ${frame.version}.'),
      );
      unawaited(close(4001, 'protocol mismatch'));
      return;
    }

    if (peer == null) {
      if (_incoming) {
        _acceptHello(frame);
      } else {
        _acceptWelcome(frame);
      }
      return;
    }
    session._receive(this, frame);
  }

  void _acceptHello(GConnectFrame frame) {
    if (frame.type != 'hello' || frame.sessionId != session.id) {
      unawaited(close(4001, 'invalid hello'));
      return;
    }
    final peerId = frame.peerId;
    final peerName = frame.peerName;
    if (peerId == null ||
        peerId.isEmpty ||
        peerName == null ||
        peerName.isEmpty ||
        frame.binaryMode != session.binaryMode.name) {
      unawaited(close(4001, 'invalid peer or binary mode'));
      return;
    }

    peer = session._acceptHostPeer(this, peerId, peerName);
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    sendEncoded(
      GConnectProtocol.welcome(
        sessionId: session.id,
        peerId: session.localPeer.id,
        peerName: session.localPeer.name,
        binaryMode: session.binaryMode.name,
      ),
    );
    _startPing();
  }

  void _acceptWelcome(GConnectFrame frame) {
    if (frame.type != 'welcome' || frame.sessionId != session.id) {
      _failHandshake(StateError('Invalid GraphX Connect welcome frame.'));
      unawaited(close(4001, 'invalid welcome'));
      return;
    }
    final peerId = frame.peerId;
    final peerName = frame.peerName;
    if (peerId == null ||
        peerId.isEmpty ||
        peerName == null ||
        peerName.isEmpty ||
        frame.binaryMode != session.binaryMode.name) {
      _failHandshake(
        StateError('Invalid GraphX Connect host identity or binary mode.'),
      );
      unawaited(close(4001, 'invalid host'));
      return;
    }

    peer = session._acceptServerPeer(this, peerId, peerName);
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    if (!(_ready?.isCompleted ?? true)) _ready!.complete();
    _startPing();
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_closed || peer == null || _pendingPingId != null) return;
      final pingId = _nextPingId++;
      _pendingPingId = pingId;
      final watch = Stopwatch();
      watch.start();
      _pingWatch = watch;
      sendEncoded(
        GConnectProtocol.ping(
          sessionId: session.id,
          peerId: session.localPeer.id,
          pingId: pingId,
        ),
      );
    });
  }

  bool acceptPong(int pingId) {
    if (_pendingPingId != pingId) return false;
    final watch = _pingWatch;
    _pendingPingId = null;
    _pingWatch = null;
    if (watch != null && peer != null) {
      watch.stop();
      peer!._latency = watch.elapsed;
    }
    return true;
  }

  void sendEncoded(Object encoded) {
    if (_closed) throw StateError('Connection is closed.');
    connection.send(encoded);
  }

  void _failHandshake(Object error, [StackTrace? stack]) {
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(error, stack ?? StackTrace.current);
    }
  }

  void _finish([Object? error, StackTrace? stack]) {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _pingTimer?.cancel();
    _pingWatch?.stop();
    if (error != null) _failHandshake(error, stack);
    if (peer == null) {
      _failHandshake(StateError('Connection closed during handshake.'));
    }
    session._linkClosed(this);
  }

  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _pingTimer?.cancel();
    _pingWatch?.stop();
    if (peer == null) {
      _failHandshake(StateError('Connection closed during handshake.'));
    }
    await _subscription?.cancel();
    _subscription = null;
    await connection.close(code, reason);
    session._linkClosed(this);
  }
}

String _validName(String value, String argument) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, argument, 'Name cannot be empty.');
  }
  if (normalized.length > 63) {
    throw ArgumentError.value(value, argument, 'Name must be 63 characters or fewer.');
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

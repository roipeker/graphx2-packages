import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect_spi.dart';

const bool tcpSupported = true;

Future<GTransportConnection> connectRawTcp(
  String host,
  int port, {
  required Duration timeout,
}) async {
  if (host.trim().isEmpty) {
    throw ArgumentError.value(host, 'host', 'Host must not be empty.');
  }
  if (port < 1 || port > 65535) {
    throw RangeError.range(port, 1, 65535, 'port');
  }
  final socket = await Socket.connect(host, port, timeout: timeout);
  socket.setOption(SocketOption.tcpNoDelay, true);
  return _RawTcpConnection(socket);
}

Future<GTransportConnection> connectTcp(
  String host,
  int port, {
  required Duration timeout,
}) async {
  final raw = await connectRawTcp(host, port, timeout: timeout);
  return frameTcpConnection(raw);
}

GTransportConnection frameTcpConnection(GTransportConnection raw) {
  return _FramedTcpConnection(raw);
}

final class _RawTcpConnection implements GTransportConnection {
  _RawTcpConnection(this.socket);

  final Socket socket;
  bool _closed = false;

  @override
  Stream<Object> get messages => socket.map<Object>(
    (data) => Uint8List.fromList(data),
  );

  @override
  void send(Object message) {
    if (_closed) throw StateError('TCP connection is closed.');
    if (message is String) {
      socket.add(utf8.encode(message));
      return;
    }
    if (message is Uint8List) {
      socket.add(message);
      return;
    }
    if (message is List<int>) {
      socket.add(message);
      return;
    }
    throw ArgumentError.value(
      message,
      'message',
      'Expected String, Uint8List, or List<int>.',
    );
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    await socket.flush();
    await socket.close();
  }
}

final class _FramedTcpConnection implements GTransportConnection {
  _FramedTcpConnection(this.raw) {
    _subscription = raw.messages.listen(
      _onData,
      onError: _messages.addError,
      onDone: _closeMessages,
      cancelOnError: false,
    );
  }

  static const int _headerBytes = 5;
  static const int _text = 0;
  static const int _binary = 1;
  static const int _maxFrameBytes = 64 * 1024 * 1024;

  final GTransportConnection raw;
  final _messages = StreamController<Object>.broadcast(sync: true);
  late final StreamSubscription<Object> _subscription;
  final List<int> _buffer = <int>[];
  bool _closed = false;

  @override
  Stream<Object> get messages => _messages.stream;

  void _onData(Object event) {
    if (_closed) return;
    if (event is! Uint8List) {
      _messages.addError(
        FormatException(
          'Raw TCP produced non-binary data: ${event.runtimeType}.',
        ),
      );
      unawaited(close());
      return;
    }

    _buffer.addAll(event);
    while (_buffer.length >= _headerBytes) {
      final type = _buffer[0];
      final length = (_buffer[1] << 24) | (_buffer[2] << 16) | (_buffer[3] << 8) | _buffer[4];

      if (length < 0 || length > _maxFrameBytes) {
        _messages.addError(
          FormatException('Invalid GraphX Connect TCP frame length: $length.'),
        );
        unawaited(close());
        return;
      }
      if (_buffer.length < _headerBytes + length) return;

      final payload = Uint8List.fromList(
        _buffer.sublist(_headerBytes, _headerBytes + length),
      );
      _buffer.removeRange(0, _headerBytes + length);

      switch (type) {
        case _text:
          try {
            _messages.add(utf8.decode(payload));
          } on FormatException catch (error, stack) {
            _messages.addError(error, stack);
          }
        case _binary:
          _messages.add(payload);
        default:
          _messages.addError(
            FormatException('Unknown GraphX Connect TCP frame type: $type.'),
          );
          unawaited(close());
          return;
      }
    }
  }

  @override
  void send(Object message) {
    if (_closed) throw StateError('TCP connection is closed.');

    final int type;
    final Uint8List payload;
    if (message is String) {
      type = _text;
      payload = Uint8List.fromList(utf8.encode(message));
    } else if (message is Uint8List) {
      type = _binary;
      payload = message;
    } else {
      throw ArgumentError.value(
        message,
        'message',
        'Expected String or Uint8List.',
      );
    }

    if (payload.length > _maxFrameBytes) {
      throw ArgumentError.value(
        payload.length,
        'message',
        'TCP frame exceeds $_maxFrameBytes bytes.',
      );
    }

    final framed = Uint8List(_headerBytes + payload.length);
    final header = ByteData.sublistView(framed, 0, _headerBytes);
    header.setUint8(0, type);
    header.setUint32(1, payload.length, Endian.big);
    framed.setRange(_headerBytes, framed.length, payload);
    raw.send(framed);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await raw.close(code, reason);
    await _closeMessages();
  }

  Future<void> _closeMessages() async {
    if (!_messages.isClosed) await _messages.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphx_connect/graphx_connect_spi.dart';

const bool tcpSupported = true;

Future<GTransportConnection> connectTcp(
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
  return _TcpConnection(socket);
}

final class _TcpConnection implements GTransportConnection {
  _TcpConnection(this.socket) {
    _subscription = socket.listen(
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

  final Socket socket;
  final _messages = StreamController<Object>.broadcast(sync: true);
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _buffer = <int>[];
  bool _closed = false;

  @override
  Stream<Object> get messages => _messages.stream;

  void _onData(Uint8List data) {
    if (_closed) return;
    _buffer.addAll(data);

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

    final header = ByteData(_headerBytes);
    header.setUint8(0, type);
    header.setUint32(1, payload.length, Endian.big);
    socket.add(header.buffer.asUint8List());
    socket.add(payload);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await socket.flush();
    await socket.close();
    await _closeMessages();
  }

  Future<void> _closeMessages() async {
    if (!_messages.isClosed) await _messages.close();
  }
}

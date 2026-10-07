import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:graphx_connect_socket/src/tcp_io.dart';
import 'package:test/test.dart';

void main() {
  test('TCP transport frames text and binary in both directions', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final accepted = server.first;
    final connection = await connectTcp(
      InternetAddress.loopbackIPv4.address,
      server.port,
      timeout: const Duration(seconds: 2),
    );
    addTearDown(connection.close);

    final socket = await accepted;
    addTearDown(socket.close);

    final reader = _SocketReader(socket);
    addTearDown(reader.close);

    connection.send('hello');
    final textFrame = await reader.frame();
    expect(textFrame.type, 0);
    expect(utf8.decode(textFrame.payload), 'hello');

    connection.send(Uint8List.fromList(<int>[1, 2, 3, 255]));
    final binaryFrame = await reader.frame();
    expect(binaryFrame.type, 1);
    expect(binaryFrame.payload, orderedEquals(<int>[1, 2, 3, 255]));

    final incomingText = connection.messages.first;
    socket.add(_frame(0, utf8.encode('world')));
    expect(await incomingText, 'world');

    final incomingBinary = connection.messages.first;
    socket.add(_frame(1, <int>[9, 8, 7]));
    final message = await incomingBinary;
    expect(message, isA<Uint8List>());
    expect(message as Uint8List, orderedEquals(<int>[9, 8, 7]));
  });

  test('TCP transport waits for a complete fragmented frame', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final accepted = server.first;
    final connection = await connectTcp(
      InternetAddress.loopbackIPv4.address,
      server.port,
      timeout: const Duration(seconds: 2),
    );
    addTearDown(connection.close);

    final socket = await accepted;
    addTearDown(socket.close);

    final expected = connection.messages.first;
    final frame = _frame(0, utf8.encode('fragmented'));
    socket.add(frame.sublist(0, 3));
    await socket.flush();

    var completed = false;
    expected.then((_) => completed = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(completed, isFalse);

    socket.add(frame.sublist(3));
    expect(await expected, 'fragmented');
  });

  test('TCP transport validates host and port before connecting', () {
    expect(
      () => connectTcp('', 9000, timeout: const Duration(milliseconds: 10)),
      throwsArgumentError,
    );
    expect(
      () => connectTcp('127.0.0.1', 0, timeout: const Duration(milliseconds: 10)),
      throwsRangeError,
    );
  });
}

Uint8List _frame(int type, List<int> payload) {
  final bytes = Uint8List(5 + payload.length);
  final header = ByteData.sublistView(bytes, 0, 5);
  header.setUint8(0, type);
  header.setUint32(1, payload.length, Endian.big);
  bytes.setRange(5, bytes.length, payload);
  return bytes;
}

final class _Frame {
  const _Frame(this.type, this.payload);

  final int type;
  final Uint8List payload;
}

final class _SocketReader {
  _SocketReader(Socket socket) {
    _subscription = socket.listen(_onData);
  }

  final _buffer = <int>[];
  final _frames = StreamController<_Frame>.broadcast(sync: true);
  late final StreamSubscription<Uint8List> _subscription;

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    while (_buffer.length >= 5) {
      final header = ByteData.sublistView(Uint8List.fromList(_buffer), 0, 5);
      final length = header.getUint32(1, Endian.big);
      if (_buffer.length < 5 + length) return;
      final type = _buffer[0];
      final payload = Uint8List.fromList(_buffer.sublist(5, 5 + length));
      _buffer.removeRange(0, 5 + length);
      _frames.add(_Frame(type, payload));
    }
  }

  Future<_Frame> frame() => _frames.stream.first;

  Future<void> close() async {
    await _subscription.cancel();
    await _frames.close();
  }
}

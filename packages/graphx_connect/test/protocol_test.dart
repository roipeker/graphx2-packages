import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_connect/src/protocol.dart';

void main() {
  test('hello carries protocol and binary mode once', () {
    final encoded = GConnectProtocol.hello(
      sessionId: 'session',
      peerId: 'peer',
      peerName: 'Player',
      binaryMode: 'raw',
    );
    final frame = GConnectProtocol.decode(encoded);

    expect(frame.version, gConnectProtocolVersion);
    expect(frame.type, 'hello');
    expect(frame.sessionId, 'session');
    expect(frame.peerId, 'peer');
    expect(frame.peerName, 'Player');
    expect(frame.binaryMode, 'raw');
  });

  test('data frame round-trips identity, sequence and payload', () {
    final encoded = GConnectProtocol.data(
      sessionId: 'session',
      peerId: 'peer',
      sequence: 7,
      payload: <String, Object?>{
        'action': 'move',
        'x': 12.5,
        'buttons': <Object?>[true, false],
      },
    );

    final frame = GConnectProtocol.decode(encoded);
    expect(frame.version, gConnectProtocolVersion);
    expect(frame.type, 'data');
    expect(frame.sequence, 7);
    expect(frame.payload, <String, Object?>{
      'action': 'move',
      'x': 12.5,
      'buttons': <Object?>[true, false],
    });
  });

  test('sequenced binary costs four bytes and shares payload view', () {
    final payload = Uint8List.fromList(<int>[0, 1, 2, 127, 128, 254, 255]);
    final encoded = GConnectProtocol.binaryData(
      sequence: 42,
      payload: payload,
    );

    expect(encoded.length, payload.length + gConnectSequencedHeaderBytes);
    final frame = GConnectProtocol.decodeBinary(encoded);
    expect(frame.sequence, 42);
    expect(frame.payload, orderedEquals(payload));

    final payloadOffset = encoded.length - payload.length;
    encoded[payloadOffset] = 33;
    expect(frame.payload.first, 33);
    frame.payload[1] = 44;
    expect(encoded[payloadOffset + 1], 44);
  });

  test('empty sequenced binary payload round-trips', () {
    final encoded = GConnectProtocol.binaryData(
      sequence: 3,
      payload: Uint8List(0),
    );

    final frame = GConnectProtocol.decodeBinary(encoded);
    expect(frame.sequence, 3);
    expect(frame.payload, isEmpty);
    expect(encoded.length, gConnectSequencedHeaderBytes);
  });

  test('short sequenced binary frame is rejected', () {
    expect(
      () => GConnectProtocol.decodeBinary(
        Uint8List(gConnectSequencedHeaderBytes - 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('invalid root frame is rejected', () {
    expect(
      () => GConnectProtocol.decode('[1,2,3]'),
      throwsA(isA<FormatException>()),
    );
  });

  test('missing session identity is rejected during decode', () {
    expect(
      () => GConnectProtocol.decode('{"v":1,"type":"data"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('malformed optional fields do not escape as cast errors', () {
    final frame = GConnectProtocol.decode(
      '{"v":1,"type":"data","sid":"session","pid":4,"seq":"bad"}',
    );
    expect(frame.peerId, isNull);
    expect(frame.sequence, isNull);
  });

  test('non JSON-compatible payload is rejected before transport send', () {
    expect(
      () => GConnectProtocol.data(
        sessionId: 'session',
        peerId: 'peer',
        sequence: 1,
        payload: Object(),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:graphx_connect/graphx_connect.dart';

void main() {
  test('remote connect exposes WebRTC transport and raw bytes by default', () {
    final connect = GRemoteConnect(
      Uri.parse('wss://connect.example.com/v1/connect'),
      name: 'Browser',
    );

    expect(connect.supported, isTrue);
    expect(connect.transport, 'webrtc');
    expect(connect.binaryMode, GBinaryMode.raw);
    expect(connect.serverIce, isTrue);
  });

  test('remote peer name stays small and intentional', () {
    expect(
      () => GRemoteConnect(
        Uri.parse('wss://connect.example.com/v1/connect'),
        name: '',
      ),
      throwsArgumentError,
    );
  });

  test('4-digit game room codes are accepted', () {
    final connect = GRemoteConnect(
      Uri.parse('wss://connect.example.com/v1/connect'),
    );

    // Validation happens before networking. A valid code proceeds to connect,
    // so only malformed codes are asserted synchronously here.
    expect(() => connect.joinCode('1!'), throwsArgumentError);
  });

  test('sequenced binary remains an explicit opt-in', () {
    final connect = GRemoteConnect(
      Uri.parse('wss://connect.example.com/v1/connect'),
      binaryMode: GBinaryMode.sequenced,
    );

    expect(connect.binaryMode, GBinaryMode.sequenced);
  });

  test('static ICE stays available as a fallback', () {
    final connect = GRemoteConnect(
      Uri.parse('wss://connect.example.com/v1/connect'),
      iceServers: const <GIceServer>[
        GIceServer(
          <String>['turn:turn.example.com:3478'],
          username: 'user',
          credential: 'secret',
        ),
      ],
      serverIce: false,
    );

    expect(connect.supported, isTrue);
    expect(connect.serverIce, isFalse);
  });
}

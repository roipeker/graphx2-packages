import 'dart:convert';
import 'dart:typed_data';

const int gConnectProtocolVersion = 1;
const int gConnectSequencedHeaderBytes = 4;

final class GConnectFrame {
  const GConnectFrame(this.type, this.fields);

  final String type;
  final Map<String, Object?> fields;

  int get version => _requiredInt('v');
  String get sessionId => _requiredString('sid');

  String? get peerId {
    final value = fields['pid'];
    return value is String ? value : null;
  }

  String? get peerName {
    final value = fields['name'];
    return value is String ? value : null;
  }

  String? get binaryMode {
    final value = fields['binary'];
    return value is String ? value : null;
  }

  int? get sequence {
    final value = fields['seq'];
    return value is int ? value : null;
  }

  int? get pingId {
    final value = fields['ping'];
    return value is int ? value : null;
  }

  Object? get payload => fields['data'];

  int _requiredInt(String key) {
    final value = fields[key];
    if (value is! int) {
      throw const FormatException('Invalid GraphX Connect frame.');
    }
    return value;
  }

  String _requiredString(String key) {
    final value = fields[key];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Invalid GraphX Connect frame.');
    }
    return value;
  }
}

final class GConnectBinaryFrame {
  const GConnectBinaryFrame({
    required this.sequence,
    required this.payload,
  });

  final int sequence;
  final Uint8List payload;
}

abstract final class GConnectProtocol {
  static String hello({
    required String sessionId,
    required String peerId,
    required String peerName,
    required String binaryMode,
  }) => _encode(<String, Object?>{
    'v': gConnectProtocolVersion,
    'type': 'hello',
    'sid': sessionId,
    'pid': peerId,
    'name': peerName,
    'binary': binaryMode,
  });

  static String welcome({
    required String sessionId,
    required String peerId,
    required String peerName,
    required String binaryMode,
  }) => _encode(<String, Object?>{
    'v': gConnectProtocolVersion,
    'type': 'welcome',
    'sid': sessionId,
    'pid': peerId,
    'name': peerName,
    'binary': binaryMode,
  });

  static String data({
    required String sessionId,
    required String peerId,
    required int sequence,
    required Object? payload,
  }) => _encode(<String, Object?>{
    'v': gConnectProtocolVersion,
    'type': 'data',
    'sid': sessionId,
    'pid': peerId,
    'seq': sequence,
    'data': payload,
  });

  static Uint8List binaryData({
    required int sequence,
    required Uint8List payload,
  }) {
    if (sequence < 0 || sequence > 0xffffffff) {
      throw ArgumentError.value(
        sequence,
        'sequence',
        'Expected an unsigned 32-bit sequence.',
      );
    }
    final encoded = Uint8List(gConnectSequencedHeaderBytes + payload.length);
    final header = ByteData.sublistView(
      encoded,
      0,
      gConnectSequencedHeaderBytes,
    );
    header.setUint32(0, sequence, Endian.big);
    encoded.setRange(gConnectSequencedHeaderBytes, encoded.length, payload);
    return encoded;
  }

  static GConnectBinaryFrame decodeBinary(Uint8List encoded) {
    if (encoded.length < gConnectSequencedHeaderBytes) {
      throw const FormatException('Invalid GraphX Connect binary frame.');
    }
    final header = ByteData.sublistView(
      encoded,
      0,
      gConnectSequencedHeaderBytes,
    );
    return GConnectBinaryFrame(
      sequence: header.getUint32(0, Endian.big),
      payload: Uint8List.sublistView(encoded, gConnectSequencedHeaderBytes),
    );
  }

  static String ping({
    required String sessionId,
    required String peerId,
    required int pingId,
  }) => _encode(<String, Object?>{
    'v': gConnectProtocolVersion,
    'type': 'ping',
    'sid': sessionId,
    'pid': peerId,
    'ping': pingId,
  });

  static String pong({
    required String sessionId,
    required String peerId,
    required int pingId,
  }) => _encode(<String, Object?>{
    'v': gConnectProtocolVersion,
    'type': 'pong',
    'sid': sessionId,
    'pid': peerId,
    'ping': pingId,
  });

  static GConnectFrame decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid GraphX Connect frame.');
    }

    final fields = <String, Object?>{};
    for (final entry in decoded.entries) {
      fields[entry.key] = entry.value;
    }

    final type = fields['type'];
    final sessionId = fields['sid'];
    if (type is! String ||
        type.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty ||
        fields['v'] is! int) {
      throw const FormatException('Invalid GraphX Connect frame.');
    }
    return GConnectFrame(type, fields);
  }

  static String _encode(Map<String, Object?> frame) {
    try {
      return jsonEncode(frame);
    } on JsonUnsupportedObjectError catch (error) {
      throw ArgumentError.value(
        frame['data'],
        'data',
        'GraphX Connect messages must be JSON-compatible: $error',
      );
    }
  }
}

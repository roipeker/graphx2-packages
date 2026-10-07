import 'dart:math';

import 'connect.dart';
import 'protocol.dart';

/// Shared entry point configured once, then extended by optional transports.
final class GConnect {
  GConnect({
    String name = 'GraphX peer',
    String? id,
    this.binaryMode = GBinaryMode.raw,
  }) : identity = GIdentity(id: id, name: name);

  GConnect.identity(this.identity, {this.binaryMode = GBinaryMode.raw});

  static const int protocolVersion = gConnectProtocolVersion;

  final GIdentity identity;
  final GBinaryMode binaryMode;

  String get id => identity.id;
  String get name => identity.name;
}

/// Stable identity shared across whichever transports a GConnect instance uses.
final class GIdentity {
  GIdentity({String? id, String name = 'GraphX peer'})
    : id = _validIdentity(id ?? _randomId(), 'id'),
      name = _validIdentity(name, 'name');

  final String id;
  final String name;
}

String _validIdentity(String value, String argument) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 128) {
    throw ArgumentError.value(
      value,
      argument,
      'Expected 1-128 non-whitespace characters.',
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

// Copyright (c) 2026 GraphX by roipeker.

part of '../graphx_paths.dart';

/// Allocation-free receiver for the exact authored commands retained by
/// [GPath].
///
/// This is intentionally lower-level than sampling/metrics. It lets tooling,
/// serialization and backend adapters replay semantic path geometry without
/// exposing GPath's storage lists or flattening curves.
abstract interface class GPathCommandSink {
  void moveTo(double x, double y);
  void lineTo(double x, double y);
  void quadraticTo(double controlX, double controlY, double x, double y);
  void cubicTo(
    double controlX1,
    double controlY1,
    double controlX2,
    double controlY2,
    double x,
    double y,
  );
  void close();
}

extension GPathCommandReplay on GPath {
  /// Replays the exact retained path commands in authored order.
  ///
  /// No path sampling, flattening or per-command object allocation occurs.
  void replayCommands(GPathCommandSink sink) {
    var valueIndex = 0;
    for (var i = 0; i < _verbs.length; ++i) {
      switch (_verbs[i]) {
        case _verbMove:
          sink.moveTo(_values[valueIndex], _values[valueIndex + 1]);
          valueIndex += 2;
          break;
        case _verbLine:
          sink.lineTo(_values[valueIndex], _values[valueIndex + 1]);
          valueIndex += 2;
          break;
        case _verbQuadratic:
          sink.quadraticTo(
            _values[valueIndex],
            _values[valueIndex + 1],
            _values[valueIndex + 2],
            _values[valueIndex + 3],
          );
          valueIndex += 4;
          break;
        case _verbCubic:
          sink.cubicTo(
            _values[valueIndex],
            _values[valueIndex + 1],
            _values[valueIndex + 2],
            _values[valueIndex + 3],
            _values[valueIndex + 4],
            _values[valueIndex + 5],
          );
          valueIndex += 6;
          break;
        case _verbClose:
          sink.close();
          break;
        default:
          throw StateError('Unknown GPath verb ${_verbs[i]}.');
      }
    }
    assert(valueIndex == _values.length);
  }
}
